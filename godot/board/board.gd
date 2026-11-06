class_name Board
extends Node3D
## The table (R3-R8, R31-R39, R44): a fixed camera on four card collections, a HUD, and the
## step queue that plays a MatchDriver's events one beat at a time, and the player's side of
## the table: drag staging against the energy (R11-R20), Commit, pause, concede and rematch
## (R40-R43). Everything reaches the engine through the driver.
##
## Seeds: `fixed_seed` if non-zero, else `--seed=N`, else a clock seed. The clock is read
## here and nowhere else, and only to make a seed. `--autoplay` or `autoplay` makes seat 0
## a bot too and plays at 4x; the player cannot drag then.

## Emitted when the queue is empty and the human's commit is awaited. Input is unlocked.
signal player_turn_started
## Internal: emitted when the node-owned wait ends, or is cut short by a restart or exit.
signal wait_finished
## Internal: emitted when the open prompt is answered, or cut short by a restart or exit.
signal prompt_resolved
## Emitted when a pause or result "Decks" button is pressed; main frees the board.
signal decks_requested

## The drop-zone glow looks (R12-R14).
enum GlowLook { IDLE, HOVER, REFUSE }

const CARD_SCENE: PackedScene = preload("res://board/board_card.tscn")
const AUTOPLAY_SPEED: float = 4.0
const NORMAL_SPEED: float = 1.0
const AUTOPLAY_ARG: String = "--autoplay"
const GLOW_GOLD: Color = Color(1.0, 0.85, 0.45)
const GLOW_RED: Color = Color(0.95, 0.25, 0.2)
const GLOW_IDLE_ALPHA: float = 0.18
const GLOW_HOVER_ALPHA: float = 0.35
## Seconds at 1x for a player commit to slide onto the row when it is not already there.
const PLAYER_COMMIT_TIME: float = 0.25
## Where a row's tally rests: past the right end of the row, and toward the camera.
const TALLY_OFFSET: Vector3 = Vector3(14.5, 0.0, 1.0)
## Seconds at 1x for an unstaged card to slide back to the hand.
const UNSTAGE_TIME: float = 0.2

## 0 means "ask the command line, then the clock".
@export var fixed_seed: int = 0
@export var autoplay: bool = false
## True for stand-alone verify scenes: start the seeded pairing in _ready. Main starts it.
@export var auto_start: bool = false
var bot: String = BotRegistry.default_name()
var level: int = BotPlayer.FULL_LEVEL

## The current match, for T08 and tests.
var driver: MatchDriver = null

## True while any step is queued or running (R39).
var input_locked: bool:
	get:
		return _input_locked or _paused

## Seconds divisor for every step: 1 normally, 4 under autoplay.
var speed: float = NORMAL_SPEED

## The player's staged cards for this turn; always the uncommitted cards of `player_row`.
var staging: Staging = Staging.new()

var _cards: CardDb = null
var _decks: DeckList = DeckList.load_default()
var _crew: CrewPool = CrewPool.load_default()  # Each deck's three Crew (cycle 8 R42).
## The ids of the running match ("" = the seeded pick); a rematch keeps them.
var _deck_ids: Array[String] = ["", ""]
var _autoplay: bool = false
var _input_locked: bool = true
## Whether seat 0 is awaited; refreshed once per step in _advance(), false while steps run.
var _awaited: bool = false
var _running: bool = false
var _halted: bool = false
## Bumped by start_match so a runner from an earlier match stops touching the table.
var _serial: int = 0
## The node-owned wait behind _wait(): counted down in _process, so it always resumes.
var _wait_left: float = 0.0
var _waiting: bool = false
var _queue: Array[BoardStep] = []
## Seat 0's cards by engine instance id.
var _player_cards: Dictionary[int, BoardCard] = {}
## Displayed scores and multipliers; they follow pulses and turn ends, not the engine.
var _tracker: ScoreTracker = ScoreTracker.new()
## Plays the pulse, the effect steps and the shared card motions.
var _fx: EffectPlayer = EffectPlayer.new()
## The prompt on the table (R55-R57): banner, glows, dim and tap routing.
var _prompt: PromptHost = PromptHost.new()
## Each side's three Crew beside its hand (cycle 8 R59-R62).
var _crew_line: CrewLine = CrewLine.new()
## True when the first seed was fixed (`fixed_seed` or --seed=), so a rematch uses seed + 1.
var _seed_fixed: bool = false
var _paused: bool = false
var _turn_energy: int = 0
var _free_first: bool = false
## Seat 0's instance ids already committed this round; they stay on the row, unmovable.
var _committed_ids: Dictionary[int, bool] = {}
## Seat 0's instance ids lying face down on the row; the walk's flip pulse turns them up.
var _face_down_ids: Dictionary[int, bool] = {}
## The drag in progress: the card, where it started, and whether the pointer was over the
## row's drop zone (R14).
var _drag_card: BoardCard = null
var _drag_from_hand: bool = false
var _over_row: bool = false
var _drag_cancelled: bool = false
var _last_error: int = EngineError.Code.NONE

@onready var hud: BoardHud = $BoardHud
@onready var player_hand: CardCollection3D = $DragController/PlayerHand
@onready var player_row: CardCollection3D = $DragController/PlayerRow
@onready var opponent_row: CardCollection3D = $DragController/OpponentRow
@onready var opponent_hand: CardCollection3D = $DragController/OpponentHand
@onready var card_lift: CardLift = $CardLift
@onready var _hand_glow: MeshInstance3D = $DragController/PlayerHand/ZoneGlow
@onready var _row_glow: MeshInstance3D = $DragController/PlayerRow/ZoneGlow
@onready var _pointer: PointerShim = $PointerShim
@onready var _entry: Marker3D = $EntryMarker
@onready var _exit: Marker3D = $ExitMarker
@onready var _loose: Node3D = $Loose
@onready var _dimmer: MeshInstance3D = $Camera3D/Dimmer
@onready var _chips: ScoreChips = $ScoreChips
@onready var _tally: RowTally = $RowTally


func _ready() -> void:
	player_hand.drag_strategy = _make_strategy(BoardDragStrategy.Role.PLAYER_HAND)
	player_row.drag_strategy = _make_strategy(BoardDragStrategy.Role.PLAYER_ROW)
	opponent_row.drag_strategy = _make_strategy(BoardDragStrategy.Role.OPPONENT)
	opponent_hand.drag_strategy = _make_strategy(BoardDragStrategy.Role.OPPONENT)
	hud.set_commit_enabled(false)
	_tally.place(0, player_row.global_position + TALLY_OFFSET)
	_tally.place(1, opponent_row.global_position + TALLY_OFFSET)
	card_lift.setup($Camera3D as Camera3D, _loose, _dimmer, _spawn_card)
	var lifted_err: int = card_lift.lifted.connect(_on_card_lifted)
	var down_err: int = card_lift.put_down_finished.connect(_on_card_put_down)
	var action_err: int = hud.action_pressed.connect(_on_action_pressed)
	var decks_err: int = hud.decks_pressed.connect(decks_requested.emit)
	if lifted_err != OK or down_err != OK or action_err != OK or decks_err != OK:
		push_warning("Board: could not connect the card lift or action signals")
	var prompt_err: int = hud.confirm_pressed.connect(_on_confirm_pressed)
	prompt_err += hud.skip_pressed.connect(_on_skip_pressed)
	prompt_err += hud.pile_pressed.connect(_on_pile_pressed)
	if prompt_err != OK:
		push_warning("Board: could not connect the confirm, skip or Pile buttons")
	_cards = CardDb.load_default()
	if not _cards.is_valid():
		push_error("Card data failed to load: %s" % _cards.load_error())
		return
	_setup_effects()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_autoplay = autoplay or args.has(AUTOPLAY_ARG)
	speed = AUTOPLAY_SPEED if _autoplay else NORMAL_SPEED
	var first_seed: int = _resolve_seed(args)
	if auto_start:
		start_match(first_seed, _deck_ids)


func _process(delta: float) -> void:
	if not _waiting:
		return
	_wait_left -= delta
	if _wait_left <= 0.0:
		_end_wait()


func _exit_tree() -> void:
	_serial += 1
	_end_wait()
	_prompt.drop()
	prompt_resolved.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _prompt.is_open():
			# R43: Escape puts a lifted card down; the prompt keeps waiting.
			_prompt.put_down()
			get_viewport().set_input_as_handled()
			return
		if card_lift.is_holding():
			card_lift.put_down()
			get_viewport().set_input_as_handled()
			return
		_open_pause()
		get_viewport().set_input_as_handled()


## Hands the effect player the table it plays on. The id books are shared, never reassigned.
func _setup_effects() -> void:
	_fx.player_hand = player_hand
	_fx.player_row = player_row
	_fx.opponent_row = opponent_row
	_fx.opponent_hand = opponent_hand
	_fx.loose = _loose
	_fx.exit_marker = _exit
	_fx.glow_material = _row_glow.material_override
	_fx.player_cards = _player_cards
	_fx.committed_ids = _committed_ids
	_fx.face_down_ids = _face_down_ids
	_prompt.wire(_collections(), card_lift, hud, _row_glow.material_override)
	_prompt.strip_parent = self
	_prompt.spawn = _spawn_card
	_prompt.crew_pool = _crew


## Starts a fresh match (new driver, empty table, opening steps); a "" deck id = seeded pick.
func start_match(new_seed: int, deck_ids: Array[String]) -> void:
	_serial += 1
	_end_wait()
	card_lift.drop_now()
	_running = false
	_halted = false
	_input_locked = true
	_awaited = false
	_paused = false
	_queue.clear()
	_close_prompt()
	driver = MatchDriver.create(new_seed, _cards, _decks, deck_ids, _autoplay, bot, level, _crew)
	if driver == null:
		push_error("Board: cannot build bot '%s' at level %d" % [bot, level])
		return
	_deck_ids = driver.deck_ids()
	_fx.match_cards = driver.match_cards()
	_fx.view_source = driver.view
	_prompt.driver = driver
	_clear_table_now()
	hud.show_pause(false)
	_refresh_staging_ui()
	var events: Array[MatchEvent] = driver.start()
	if events.is_empty():
		push_error("Board: the match did not start (seed %d)" % new_seed)
		_halted = true
		return
	_crew_line.build(self, driver.view(), _crew)
	_enqueue(events)
	_run()


## Applies the player's action through the driver and queues its steps. False, changing
## nothing, while input is locked or the engine rejects it (its code is in `_last_error`).
func submit_player(action: EngineAction) -> bool:
	if _input_locked or driver == null or driver.is_over() or _halted:
		return false
	return _submit(action)


## True while the player may drag and commit (R18): no step queued or running, not under
## autoplay, the match not over, the pause menu closed, and seat 0 awaited.
func may_act() -> bool:
	if driver == null or _autoplay or _input_locked or _paused or _halted:
		return false
	if card_lift.is_holding() or driver.is_over():
		return false
	return _awaited


## Applies a seat-0 action through the driver with no lock check, then queues its steps.
## The one door to the engine for the player, shared by commit and concede.
func _submit(action: EngineAction) -> bool:
	var result: ApplyResult = driver.submit_player(action)
	if not result.ok:
		_last_error = result.error
		return false
	_input_locked = true
	_awaited = false
	_refresh_commit_enabled()
	_enqueue(driver.last_events())
	# A concede ends the match under an open prompt; the runner then plays on.
	_close_prompt()
	_run()
	return true


## The seed for a first match: fixed, then --seed=N, then the clock.
func _resolve_seed(args: PackedStringArray) -> int:
	var flagged: int = fixed_seed if fixed_seed != 0 else BoardSeeds.from_args(args)
	_seed_fixed = flagged != 0
	return flagged if flagged != 0 else BoardSeeds.clock_seed()


# --- The queue ---------------------------------------------------------------------------


func _enqueue(events: Array[MatchEvent]) -> void:
	var steps: Array[BoardStep] = BoardSteps.from_events(events, speed, MatchDriver.PLAYER_SEAT)
	_queue.append_array(steps)


## The one runner. Plays the queue, then asks _advance() what comes next, until nothing
## more is queued. A second call while running is a no-op: the running loop picks up
## whatever was enqueued.
func _run() -> void:
	if _running or not is_inside_tree():
		return
	_running = true
	_input_locked = true
	_refresh_commit_enabled()
	var serial: int = _serial
	while true:
		while not _queue.is_empty():
			var step: BoardStep = _queue.pop_front()
			await _release_held_for(step)
			if serial != _serial:
				return
			await _play(step, serial)
			if serial != _serial:
				return
		_advance()
		if _queue.is_empty():
			break
	_running = false
	if driver.is_over():
		_input_locked = false
	_refresh_commit_enabled()


## Called when the queue runs dry: the bot moves, or the human is awaited. Anything it
## enqueues is picked up by the runner.
func _advance() -> void:
	if _halted or driver.is_over():
		return
	if driver.bot_turn_due():
		var result: ApplyResult = driver.play_bot()
		if not result.ok:
			push_error("Board: the bot's action was rejected (code %d)" % result.error)
			_halted = true
			return
		_awaited = false
		_enqueue(driver.last_events())
		return
	_awaited = driver.view().is_awaited()
	_input_locked = false
	_refresh_commit_enabled()
	player_turn_started.emit()


## R8, R9: steps that do not touch the held card play on underneath it; one that would move,
## flip or remove it sets the card down first.
func _release_held_for(step: BoardStep) -> void:
	var card: BoardCard = card_lift.held
	if card == null:
		return
	var touches: bool = true
	if is_instance_valid(card):
		var staged: bool = staging.has(card.instance_id)
		touches = LiftRules.step_touches(step, card.instance_id, _place_of(card), staged)
	if touches:
		await card_lift.put_down()


func _play(step: BoardStep, serial: int) -> void:
	if step.delay > 0.0:
		await _wait(step.delay)
		if serial != _serial:
			return
	_apply(step)
	if step.duration > 0.0:
		await _wait(step.duration)
		if serial != _serial:
			return
	if PromptRules.waits(step, _autoplay):
		# R55: untimed. The runner holds here until a choice is accepted.
		while _prompt.is_open() and serial == _serial:
			await prompt_resolved


func _wait(seconds: float) -> void:
	if not is_inside_tree():
		return
	_wait_left = seconds
	_waiting = true
	await wait_finished


## Ends the current wait, if any; the suspended runner resumes at once and checks its serial.
func _end_wait() -> void:
	if not _waiting:
		return
	_waiting = false
	wait_finished.emit()


# --- Step effects (R31-R38) --------------------------------------------------------------


func _apply(step: BoardStep) -> void:
	_fx.note_step(step)
	_crew_line.note_step(step)
	staging.clear_view_costs()
	_tracker.apply(step)
	hud.set_piles(_tracker.piles)
	match step.kind:
		BoardStep.Kind.CLEAR_TABLE:
			_clear_table(step)
		BoardStep.Kind.DEAL, BoardStep.Kind.DRAW:
			_deal(step)
		BoardStep.Kind.TURN_START:
			hud.set_round_turn(step.round_number, step.turn, step.round_number > MatchRules.ROUNDS)
			hud.set_energy(step.budget, step.budget, step.free_first)
			_turn_energy = step.budget
			_free_first = step.free_first
			_unstage_all()
		BoardStep.Kind.WALK_START:
			_refresh_tally(true)
		BoardStep.Kind.WALK_END:
			_refresh_tally(false)
			_tally.fly_in(step.scores, hud, $Camera3D as Camera3D, speed)
		BoardStep.Kind.TURN_END:
			_refresh_scores()
		BoardStep.Kind.OPPONENT_COMMIT:
			_opponent_commit(step)
		BoardStep.Kind.PLAYER_COMMIT:
			_player_commit(step)
		BoardStep.Kind.PULSE:
			_fx.pulse(step)
			_pulse_chips(step)
			_refresh_tally(false)
		BoardStep.Kind.ROUND_END:
			hud.set_wins(step.wins)
		BoardStep.Kind.MATCH_END:
			_match_end(step)
		_:
			_apply_effect(step)


## The effect steps (P18, R53). BOT_WAIT is only its duration. PROMPT opens the prompt; the
## runner holds in _play(), not here.
func _apply_effect(step: BoardStep) -> void:
	match step.kind:
		BoardStep.Kind.EFFECT:
			_fx.effect(step)
		BoardStep.Kind.FIZZLE:
			_fx.fizzle(step)
		BoardStep.Kind.CHOICE_SHOW:
			_fx.choice_show(step)
		BoardStep.Kind.STATS:
			_fx.stats(step)
		BoardStep.Kind.STATUS:
			_fx.status(step)
		BoardStep.Kind.EXIT:
			_fx.exit_card(step)
		BoardStep.Kind.LOOK:
			_fx.look(step)
		BoardStep.Kind.EMPTY_DRAW:
			hud.note_deck(step.seat, "Deck empty", step.duration)
		BoardStep.Kind.SHUFFLE_IN:
			hud.note_deck(step.seat, "Pile shuffled in", step.duration)
		BoardStep.Kind.ENERGY_GRANT:
			if step.seat == MatchDriver.PLAYER_SEAT:
				_turn_energy += step.amount
				_unstage_all()
		BoardStep.Kind.UNREVEAL:
			_fx.unreveal(step)
		BoardStep.Kind.PILE_SHOW:
			_on_pile_pressed(step.seat)
		BoardStep.Kind.PILE_HIDE:
			_prompt.hide_strip(step.duration)
			_fx.strip = null
		BoardStep.Kind.MOVE:
			_fx.move(step)
		BoardStep.Kind.RETURN:
			_fx.return_card(step)
		BoardStep.Kind.DISCARD:
			_fx.discard(step)
		BoardStep.Kind.PROMPT:
			_open_prompt(step)
		BoardStep.Kind.DECLINE:
			_close_prompt()


## The HUD shows the tracker's held totals only: the previous turn's (R33, R35).
func _refresh_scores() -> void:
	hud.set_scores(_tracker.held)


## The row tallies follow the tracker's walk numbers (R32); `reveal` also shows them.
func _refresh_tally(reveal: bool) -> void:
	if reveal or _tally.is_shown(0) or _tally.is_shown(1):
		_tally.show_values(_tracker.tally)


## R31: the chips above the pulsed card; none for a pulse with no score.
func _pulse_chips(step: BoardStep) -> void:
	if ScoreChips.chip_texts(step).is_empty():
		return
	var card: BoardCard = _fx.card_for(step)
	if card != null:
		_chips.spawn(card, step, speed)


func _deal(step: BoardStep) -> void:
	var hand: CardCollection3D = player_hand if step.seat == 0 else opponent_hand
	var card: BoardCard = _spawn_card()
	hand.card_move_tween_duration = maxf(step.duration, EffectPlayer.MIN_TWEEN_TIME)
	hand.append_card(card)
	card.global_position = _entry.global_position
	if step.seat == 0:
		_fx.show(card, step)
		_player_cards[step.card] = card
	else:
		card.face_down = true


func _opponent_commit(step: BoardStep) -> void:
	var each: float = step.duration / float(maxi(step.count, 1))
	# Slot order, so each card lands at its final row index (R47).
	for k: int in RowSlots.order_by_slot(step.slots, step.count):
		if opponent_hand.cards.is_empty():
			push_warning("Board: the opponent committed more cards than its fan holds")
			return
		var card: Card3D = opponent_hand.cards[opponent_hand.cards.size() - 1]
		var at: int = step.slots[k] if k < step.slots.size() else -1
		_fx.move_card(card, opponent_hand, opponent_row, each, at)


## Autoplay: the committed cards are still in the hand and slide to their slots. Player mode:
## they were staged on the row already. Either way every one flips face down in place (R46)
## and is remembered, so the walk's flip pulse turns it up again.
func _player_commit(step: BoardStep) -> void:
	var raw: Array = step.source.payload["cards"]
	var ids: Array[int] = []
	ids.assign(raw)
	for k: int in RowSlots.order_by_slot(step.slots, ids.size()):
		var id: int = ids[k]
		_committed_ids[id] = true
		var card: BoardCard = _player_card(id)
		if card == null:
			continue
		if not player_row.cards.has(card):
			var at: int = step.slots[k] if k < step.slots.size() else -1
			_fx.move_card(card, player_hand, player_row, PLAYER_COMMIT_TIME / speed, at)
		_face_down_ids[id] = true
		_fx.flip_down(card, step.duration)


func _clear_table(step: BoardStep) -> void:
	for collection: CardCollection3D in _collections():
		var transforms: Array[Transform3D] = []
		for card: Card3D in collection.cards:
			transforms.append(card.global_transform)
		var removed: Array[Card3D] = collection.remove_all()
		for i: int in range(removed.size()):
			_loose.add_child(removed[i])
			removed[i].global_transform = transforms[i]
			_fx.fly_out(removed[i], step.duration)
	_fx.reset()
	_tally.hide_all()
	_chips.clear()
	_refresh_scores()


## The final table stays (R42); Commit and drags are off from here, since may_act() is false
## once the driver is over.
func _match_end(step: BoardStep) -> void:
	print(driver.result_line())
	if card_lift.is_holding():
		card_lift.put_down()
	var reason: String = step.source.payload["reason"]
	_paused = false
	hud.show_pause(false)
	var rounds: int = step.source.payload["rounds_played"]
	hud.show_result(step.seat, step.wins, reason, rounds)
	_refresh_commit_enabled()


# --- Prompts (R55-R58, C16) ----------------------------------------------------------------


## Shows seat 0's open prompt. Under autoplay the bot answers through play_bot(), so there is
## no banner and no wait (R58). If the engine holds no prompt for seat 0 nothing opens, and
## the runner does not wait either.
func _open_prompt(step: BoardStep) -> void:
	if _autoplay:
		return
	var open: Dictionary = driver.open_prompt()
	if open.is_empty():
		push_warning("Board: a PROMPT step but the engine holds no prompt for seat 0")
		return
	_prompt.open(open, step.text, driver.view())
	_fx.strip = _prompt.strip_collection()
	_refresh_commit_enabled()


## Clears the banner, glows and dim, and lets a held runner continue (R57). `keep_strip` leaves
## the Pile strip up for a choice that flies a card out of it (PILE_HIDE clears it).
func _close_prompt(keep_strip: bool = false) -> void:
	_prompt.close(keep_strip)
	_fx.strip = _prompt.strip_collection()
	prompt_resolved.emit()


## Plays an accepted answer (R57, R47): its steps, then the strip's exit, and the prompt
## closes. A rejection leaves the prompt up (it should not happen); null means nothing to do.
func _answer(result: ApplyResult) -> void:
	if result == null:
		return
	if not result.ok:
		push_warning("Board: the engine rejected the choice (code %d)" % result.error)
		return
	var strip_up: bool = _prompt.strip_up()
	_enqueue(driver.last_events())
	if strip_up:
		_queue.append(BoardSteps.pile_step(false, speed))
	_close_prompt(strip_up)
	_prompt.put_down(strip_up)


## The reader's button (R42, R48): submits the lifted option, or toggles it in a multi set.
func _on_action_pressed() -> void:
	_answer(_prompt.press())


## The HUD confirm (R48): submits the selected set.
func _on_confirm_pressed() -> void:
	_answer(_prompt.confirm())


## A Pile count was tapped (R78): the Pile face up in the strip, or the strip away.
func _on_pile_pressed(seat: int) -> void:
	if driver == null or _halted:
		return
	_prompt.toggle_pile(seat, driver.view())
	_fx.strip = _prompt.strip_collection()


## The Skip button (R63): declines the optional prompt.
func _on_skip_pressed() -> void:
	_answer(_prompt.skip())


# --- Card helpers ------------------------------------------------------------------------


func _collections() -> Array[CardCollection3D]:
	return [player_hand, player_row, opponent_row, opponent_hand]


## Seat 0's card with this instance id, or null.
func _player_card(id: int) -> BoardCard:
	if not _player_cards.has(id):
		return null
	return _player_cards[id]


func _spawn_card() -> BoardCard:
	var card: BoardCard = CARD_SCENE.instantiate() as BoardCard
	return card


## Frees every card now and clears the HUD, for a new match.
func _clear_table_now() -> void:
	_pointer.cancel()
	for collection: CardCollection3D in _collections():
		var removed: Array[Card3D] = collection.remove_all()
		for card: Card3D in removed:
			card.queue_free()
	for child: Node in _loose.get_children():
		child.queue_free()
	_turn_energy = 0
	staging.reset(0)
	_hide_glows()
	_drag_card = null
	_drag_from_hand = false
	_over_row = false
	_tracker.reset()
	_tally.hide_all()
	_chips.clear()
	_fx.reset()
	hud.set_piles(_tracker.piles)
	_refresh_scores()
	var zeros: Array[int] = [0, 0]
	hud.set_wins(zeros)
	hud.hide_result()


# --- The player's side: strategies, staging, drags (R11-R20, R26) --------------------------


func _make_strategy(role: BoardDragStrategy.Role) -> BoardDragStrategy:
	var strategy: BoardDragStrategy = BoardDragStrategy.new()
	strategy.role = role
	strategy.can_act = may_act
	strategy.is_locked = _is_locked
	strategy.can_afford = _card_affordable
	strategy.is_staged = _card_staged
	strategy.is_played = _card_played
	return strategy


func _is_locked() -> bool:
	return _input_locked or card_lift.is_holding()


## True when the card (a seat-0 BoardCard; anything else is false) fits in the energy left
## this turn (R14).
func _card_affordable(card: Object) -> bool:
	var board_card: BoardCard = card as BoardCard
	if board_card == null:
		return false
	return staging.can_afford(_cost_of(board_card.instance_id))


func _card_staged(card: Object) -> bool:
	var board_card: BoardCard = card as BoardCard
	if board_card == null:
		return false
	return staging.has(board_card.instance_id)


## True for a seat-0 card already played this round (committed): it never drags (R44).
func _card_played(card: Object) -> bool:
	var board_card: BoardCard = card as BoardCard
	if board_card == null:
		return false
	return _committed_ids.has(board_card.instance_id)


## The cost of a card instance, from the match's own definitions (the seats' decks differ).
func _cost_of(id: int) -> int:
	var def: CardDef = driver.match_cards().def_of(id)
	return staging.cached_cost(id, driver.view, 0 if def == null else def.cost)


## Commit is on only while the player may act (R18); the label follows the staging (R16).
func _refresh_commit_enabled() -> void:
	hud.set_commit_enabled(may_act() and not _prompt.is_open())


func _refresh_staging_ui() -> void:
	hud.set_energy(staging.energy_left(), _turn_energy, _free_first)
	hud.set_commit_label(not staging.cards().is_empty())
	_refresh_commit_enabled()


## The uncommitted cards on the player's row, in row order.
func _staged_cards() -> Array[BoardCard]:
	var out: Array[BoardCard] = []
	for card: Card3D in player_row.cards:
		var board_card: BoardCard = card as BoardCard
		if board_card != null and not _committed_ids.has(board_card.instance_id):
			out.append(board_card)
	return out


## The instance ids of the player's row, in row order.
func _row_ids() -> Array[int]:
	var out: Array[int] = []
	for card: Card3D in player_row.cards:
		var board_card: BoardCard = card as BoardCard
		out.append(board_card.instance_id if board_card != null else -1)
	return out


## How many played (committed) cards sit on the player's row: the first staged slot.
func _played_count() -> int:
	return player_row.cards.size() - _staged_cards().size()


## Index of a staged card among the staged cards only: the staged cards before it on the row,
## wherever the played cards sit (R43).
func _staged_index(card: BoardCard) -> int:
	return RowSlots.staged_before(_row_ids(), _committed_ids, card.instance_id)


## Rebuilds staging from the row if it ever differs from it; any staged card that no longer
## fits goes back to the hand (R14). Then refreshes the energy readout and the button.
func _resync_staging() -> void:
	var expected: Array[int] = []
	for card: BoardCard in _staged_cards():
		expected.append(card.instance_id)
	if expected != staging.cards():
		staging.reset(_turn_energy, _played_count(), _free_first)
		var rejected: Array[BoardCard] = []
		for card: BoardCard in _staged_cards():
			var at_end: int = staging.cards().size()
			if not staging.insert(card.instance_id, _cost_of(card.instance_id), at_end):
				rejected.append(card)
		for card: BoardCard in rejected:
			_fx.move_card(card, player_row, player_hand, UNSTAGE_TIME / speed)
	staging.set_row(_row_ids())
	_refresh_staging_ui()


## Sends every staged card back to the hand and empties staging for this turn's energy.
func _unstage_all() -> void:
	for card: BoardCard in _staged_cards():
		_fx.move_card(card, player_row, player_hand, UNSTAGE_TIME / speed)
	staging.reset(_turn_energy, _played_count(), _free_first)
	_refresh_staging_ui()


## The DragController moved a card (R12, R13). Staging follows the row.
func _on_drag_card_moved(
	card: Card3D,
	from_collection: CardCollection3D,
	to_collection: CardCollection3D,
	_from_index: int,
	_to_index: int
) -> void:
	var board_card: BoardCard = card as BoardCard
	if board_card == null:
		return
	var id: int = board_card.instance_id
	if from_collection == player_hand and to_collection == player_row:
		var inserted: bool = staging.insert(id, _cost_of(id), _staged_index(board_card))
		if not inserted:
			push_warning("Board: staging refused card %d dropped on the row" % id)
	elif from_collection == player_row and to_collection == player_hand:
		staging.remove(id)
	elif from_collection == player_row and to_collection == player_row:
		staging.move(id, _staged_index(board_card))
	_resync_staging()


func _on_drag_started(card: Card3D) -> void:
	_drag_card = card as BoardCard
	_drag_from_hand = player_hand.cards.has(card)
	_over_row = false
	_drag_cancelled = false
	# The row refuses an unaffordable card, so its drop zone would stay off; switch it on
	# so the release over the row can be told apart from a release elsewhere (R14).
	if _drag_from_hand and may_act() and not _card_affordable(card):
		player_row.enable_drop_zone()
	if _drag_card != null and may_act():
		_set_glow(_hand_glow, GlowLook.IDLE)
		_set_glow(_row_glow, _row_look(false))


## After every drag, refused or cancelled or not: flash on a refused drop (R14) and make
## sure staging matches the row (R26).
func _on_drag_stopped(card: Card3D) -> void:
	var refused: bool = (
		_drag_from_hand
		and _over_row
		and not _drag_cancelled
		and player_hand.cards.has(card)
		and may_act()
		and not _card_affordable(card)
	)
	if refused:
		hud.flash_energy()
	_hide_glows()
	_drag_card = null
	_drag_from_hand = false
	_over_row = false
	_drag_cancelled = false
	_resync_staging()


func _on_row_zone_entered() -> void:
	_over_row = true
	if _row_glow.visible:
		_set_glow(_row_glow, _row_look(true))


func _on_row_zone_exited() -> void:
	_over_row = false
	if _row_glow.visible:
		_set_glow(_row_glow, _row_look(false))


func _on_hand_zone_entered() -> void:
	if _hand_glow.visible:
		_set_glow(_hand_glow, GlowLook.HOVER)


func _on_hand_zone_exited() -> void:
	if _hand_glow.visible:
		_set_glow(_hand_glow, GlowLook.IDLE)


## The row panel's look: red when it would refuse the dragged card (R14), else idle/hover.
func _row_look(hovered: bool) -> GlowLook:
	if _drag_from_hand and _drag_card != null and not _card_affordable(_drag_card):
		return GlowLook.REFUSE
	return GlowLook.HOVER if hovered else GlowLook.IDLE


## Shows a drop-zone panel in the given look (R12, R13).
func _set_glow(glow: MeshInstance3D, look: GlowLook) -> void:
	var mat: StandardMaterial3D = glow.material_override as StandardMaterial3D
	var colour: Color = GLOW_GOLD
	var alpha: float = GLOW_IDLE_ALPHA
	if look == GlowLook.HOVER:
		alpha = GLOW_HOVER_ALPHA
	elif look == GlowLook.REFUSE:
		colour = GLOW_RED
		alpha = GLOW_HOVER_ALPHA
	mat.albedo_color = Color(colour, alpha)
	glow.visible = true


func _hide_glows() -> void:
	_hand_glow.visible = false
	_row_glow.visible = false


func _on_pointer_cancelled() -> void:
	_drag_cancelled = true


# --- Card pick-up (R1-R11) -----------------------------------------------------------------


## The LiftRules.Place of a card, or -1 if it is in no collection.
func _place_of(card: Card3D) -> int:
	if _crew_line.has_card(card):
		return LiftRules.Place.CREW
	if player_hand.cards.has(card):
		return LiftRules.Place.HAND
	if player_row.cards.has(card):
		return LiftRules.Place.ROW
	if opponent_row.cards.has(card):
		return LiftRules.Place.OPPONENT_ROW
	if opponent_hand.cards.has(card):
		return LiftRules.Place.OPPONENT_HAND
	return -1


## A tap puts a held card down and does nothing else (R5); otherwise it lifts the card under
## it if the rules allow (R1, R2), never during a drag or a pause (R7).
func _on_pointer_tapped(_position: Vector2, hit: Object) -> void:
	if _prompt.is_open() and not _paused:
		_prompt.handle_tap(LiftRules.card_from_hit(hit))
		return
	if card_lift.is_holding():
		card_lift.put_down()
		return
	if _paused or _drag_card != null:
		return
	var card: BoardCard = LiftRules.card_from_hit(hit)
	if card == null:
		return
	var place: int = _place_of(card)
	if place < 0:
		return
	if LiftRules.may_lift(place as LiftRules.Place, not card.face_down):
		card_lift.lift(card)


func _on_card_lifted(_card: BoardCard) -> void:
	# The prompt's banner and the action button live in the HUD, so it stays up (R40).
	hud.visible = _prompt.is_open()
	player_hand.hover_disabled = true
	player_row.hover_disabled = true
	_refresh_commit_enabled()


func _on_card_put_down(_card: BoardCard) -> void:
	_prompt.lift_ended()
	hud.visible = true
	player_hand.hover_disabled = false
	player_row.hover_disabled = false
	_refresh_commit_enabled()


# --- Commit, pause, concede, rematch (R16, R17, R40-R43) -----------------------------------


func _on_commit_pressed() -> void:
	if not may_act():
		return
	staging.set_row(_row_ids())
	if submit_player(staging.to_action(MatchDriver.PLAYER_SEAT)):
		return
	push_error("Board: the engine rejected the commit (error %d)" % _last_error)
	_unstage_all()


func _on_pause_pressed() -> void:
	_open_pause()


func _on_resume_pressed() -> void:
	_paused = false
	hud.show_pause(false)
	_refresh_commit_enabled()


func _open_pause() -> void:
	if _paused or driver == null or driver.is_over():
		return
	_paused = true
	_pointer.cancel()
	hud.show_pause(true)
	_refresh_commit_enabled()


## Concede works while locked or while the bot is due, so it skips submit_player's lock check.
func _on_concede_pressed() -> void:
	_paused = false
	hud.show_pause(false)
	if driver == null or driver.is_over():
		return
	if not _submit(EngineAction.concede(MatchDriver.PLAYER_SEAT)):
		push_error("Board: the engine rejected the concede (error %d)" % _last_error)
		_refresh_commit_enabled()


func _on_rematch_pressed() -> void:
	hud.hide_result()
	start_match(BoardSeeds.rematch(_seed_fixed, driver.match_seed), _deck_ids)
