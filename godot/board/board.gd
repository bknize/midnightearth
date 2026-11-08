# gdlint: disable=max-file-lines
class_name Board
extends Node3D
## The table (R3-R8, R31-R39, R44): a fixed camera on four card collections, a HUD, and the
## step queue that plays a MatchSource's events one beat at a time, and the player's side of
## the table: drag staging against the energy (R11-R20), Commit, pause, concede and rematch
## (R40-R43). Everything reaches the match through the source: a local source (engine and bots
## in this process) or a remote one (cycle 12 P5). The board's seats are table seats: 0 is the
## player's side, whichever engine seat the source says the player holds (P6).
##
## Main (or a verify scene's starter) builds the source and hands it to start_source().
## `--autoplay` or `autoplay` makes seat 0 a bot too and plays at 4x; the player cannot drag
## then.

## Emitted when the queue is empty and the human's commit is awaited. Input is unlocked.
signal player_turn_started
## Internal: emitted when the node-owned wait ends, or is cut short by a restart or exit.
signal wait_finished
## Internal: emitted when the open prompt is answered, or cut short by a restart or exit.
signal prompt_resolved
## Emitted when a pause or result "Decks" button is pressed; main frees the board.
signal decks_requested
## Emitted when Leave is pressed (a PVP pause menu or result panel); a running match has been
## conceded first. Main closes the room and returns to the title screen.
signal leave_requested
## Emitted when the result panel's Rematch is pressed; main starts a fresh local source.
signal rematch_requested

const CARD_SCENE: PackedScene = preload("res://board/board_card.tscn")
const AUTOPLAY_SPEED: float = 4.0
const NORMAL_SPEED: float = 1.0
const AUTOPLAY_ARG: String = "--autoplay"
## Where a row's tally rests: past the right end of the row, and toward the camera.
const TALLY_OFFSET: Vector3 = Vector3(14.5, 0.0, 1.0)
## Seconds at 1x for an unstaged card to slide back to the hand.
const UNSTAGE_TIME: float = 0.2
## Playback speed while a reconnect's history is replayed (cycle 12 P8).
const CATCH_UP_SPEED: float = 8.0
## Seconds a "<name> is back" note stays on the connection overlay.
const CONNECTION_NOTE_TIME: float = 4.0

@export var autoplay: bool = false

## What the board plays against: set by start_source. The board never learns which kind it is.
var source: MatchSource = null

## True while a reconnect's history is replayed: fast, with no prompt waits (cycle 12 P8).
var catching_up: bool = false

## True while any step is queued or running (R39).
var input_locked: bool:
	get:
		return _input_locked or _paused

## Seconds divisor for every step: 1 normally, 4 under autoplay.
var speed: float = NORMAL_SPEED

## The player's staged cards for this turn; always the uncommitted cards of `player_row`.
var staging: Staging = Staging.new()

var _cards: CardDb = null
var _crew: CrewPool = CrewPool.load_default()  # Each deck's three Crew (cycle 8 R42).
var _autoplay: bool = false
var _input_locked: bool = true
## Whether seat 0 is awaited; refreshed once per step in _advance(), false while steps run.
var _awaited: bool = false
var _running: bool = false
var _halted: bool = false
## Bumped by start_source so a runner from an earlier match stops touching the table.
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
## Cards arriving on the table: deals, commits, created and placed cards (DC-14 T15).
var _arrivals: CardArrivals = CardArrivals.new()
## The prompt on the table (R55-R57): banner, glows, dim and tap routing.
var _prompt: PromptHost = PromptHost.new()
## Each side's three Crew beside its hand (cycle 8 R59-R62).
var _crew_line: CrewLine = CrewLine.new()
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
## True from an action being sent until the source answers it (events or a rejection), so a
## remote answer in flight keeps input locked.
var _in_flight: bool = false
## Holds the runner back while _submit() still has setup to do after the source answered.
var _deferring_run: bool = false
## Set by the rejection handler; read by the call that submitted.
var _rejected: bool = false
## Set by the events handler; _answer() reads it to tell a local answer (already here) from a
## remote one (still to come).
var _answered_events: bool = false
## A prompt answer that flew a card out of the Pile strip: the strip leaves after its events.
var _pile_hide_pending: bool = false
## True until the first events of a match arrive; they build the Crew line and bind the cards.
var _crew_pending: bool = false
## The room was closed under the player (abandonment); nothing more is sent.
var _closed: bool = false
var _connection_left: float = 0.0

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
	decks_err += hud.leave_pressed.connect(_on_leave_pressed)
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


func _process(delta: float) -> void:
	if _connection_left > 0.0:
		_connection_left -= delta
		if _connection_left <= 0.0:
			hud.show_connection("", "")
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
	_arrivals.fx = _fx
	_arrivals.entry_marker = _entry
	_arrivals.spawn = _spawn_card
	_prompt.wire(_collections(), card_lift, hud, _row_glow.material_override)
	_prompt.strip_parent = self
	_prompt.spawn = _spawn_card
	_prompt.crew_pool = _crew


## Starts a fresh match against any source (a remote one for PVP): empty table, then the
## source's own start; its opening events arrive through `events_ready`.
func start_source(new_source: MatchSource) -> void:
	_reset_for_match()
	_begin_source(new_source)


## Clears the runner, the queue and the table state for a new match.
func _reset_for_match() -> void:
	_serial += 1
	_end_wait()
	card_lift.drop_now()
	_running = false
	_halted = false
	_closed = false
	_input_locked = true
	_awaited = false
	_paused = false
	_in_flight = false
	_deferring_run = false
	_pile_hide_pending = false
	catching_up = false
	speed = AUTOPLAY_SPEED if _autoplay else NORMAL_SPEED
	_queue.clear()
	_close_prompt()


## Connects to `new_source`, shows its names and starts it.
func _begin_source(new_source: MatchSource) -> void:
	_release_source()
	source = new_source
	var events_err: int = source.events_ready.connect(_on_events_ready)
	events_err += source.action_rejected.connect(_on_action_rejected)
	events_err += source.connection_changed.connect(_on_connection_changed)
	events_err += source.match_closed.connect(_on_match_closed)
	if source.has_signal("catch_up"):
		events_err += source.connect("catch_up", _on_catch_up)
	if events_err != OK:
		push_warning("Board: could not connect the match source's signals")
	_fx.view_source = source.view
	_fx.viewer = source.player_seat
	_prompt.source = source
	_prompt.viewer = source.player_seat
	_bind_cards()
	_clear_table_now()
	hud.show_pause(false, _pvp())
	hud.set_opponent_name(source.opponent_name())
	hud.set_waiting("")
	hud.show_connection("", "")
	_refresh_staging_ui()
	_crew_pending = true
	source.start()


func _release_source() -> void:
	if source == null:
		return
	if source.events_ready.is_connected(_on_events_ready):
		source.events_ready.disconnect(_on_events_ready)
	if source.action_rejected.is_connected(_on_action_rejected):
		source.action_rejected.disconnect(_on_action_rejected)
	if source.connection_changed.is_connected(_on_connection_changed):
		source.connection_changed.disconnect(_on_connection_changed)
	if source.match_closed.is_connected(_on_match_closed):
		source.match_closed.disconnect(_on_match_closed)
	if source.has_signal("catch_up") and source.is_connected("catch_up", _on_catch_up):
		source.disconnect("catch_up", _on_catch_up)


## Takes the deck ids and the card definitions from the source once it holds them.
func _bind_cards() -> void:
	var defs: MatchCards = source.match_cards()
	if defs != null:
		_fx.match_cards = defs


## True for a match served remotely: no rematch, no Decks, a Leave button, waiting text.
func _pvp() -> bool:
	return source != null and not source.allows_rematch()


## Sends the player's action through the source and queues its steps when they come. False,
## changing nothing, while input is locked or the source refuses it (its code is in
## `_last_error`).
func submit_player(action: EngineAction) -> bool:
	if _input_locked or source == null or source.is_over() or _halted or _closed:
		return false
	return _submit(action)


## True while the player may drag and commit (R18): no step queued or running, not under
## autoplay, the match not over, the pause menu closed, and the player awaited.
func may_act() -> bool:
	if source == null or _autoplay or _input_locked or _paused or _halted:
		return false
	if card_lift.is_holding() or source.is_over():
		return false
	return _awaited


## Sends an action with no lock check, then queues its steps. The one door to the match for
## the player, shared by commit and concede. A local source answers inside the call; a remote
## one later, and input stays locked until it does (R22).
func _submit(action: EngineAction) -> bool:
	var was_locked: bool = _input_locked
	var was_awaited: bool = _awaited
	_rejected = false
	_input_locked = true
	_awaited = false
	_in_flight = true
	_deferring_run = true
	_refresh_commit_enabled()
	source.submit(action)
	_deferring_run = false
	if _rejected:
		_input_locked = was_locked
		_awaited = was_awaited
		_refresh_commit_enabled()
		return false
	# A concede ends the match under an open prompt; the runner then plays on.
	_close_prompt()
	_run()
	return true


# --- The source's answers ----------------------------------------------------------------


## The source's events (the opening, an accepted action of either seat): queued and played.
func _on_events_ready(events: Array[MatchEvent]) -> void:
	_in_flight = false
	_answered_events = true
	if _crew_pending:
		_crew_pending = false
		_bind_cards()
		_crew_line.build(self, source.view(), _crew)
	_enqueue(events)
	if _pile_hide_pending:
		_pile_hide_pending = false
		_queue.append(BoardSteps.pile_step(false, speed))
	if not _deferring_run:
		_run()


## The source refused the player's action (R24): unstage, flash the energy readout, name the
## code in a warning, and stay awaiting the player.
func _on_action_rejected(code: int) -> void:
	_in_flight = false
	_rejected = true
	_last_error = code
	push_warning("Board: the match refused the action (error %d)" % code)
	if _running or not _queue.is_empty() or not source.is_player_awaited():
		return
	if not staging.cards().is_empty():
		hud.flash_energy()
	_unstage_all()
	_input_locked = false
	_awaited = true
	_refresh_commit_enabled()


func _on_connection_changed(state: String, detail: String) -> void:
	hud.show_connection(state, detail)
	_connection_left = CONNECTION_NOTE_TIME if state == MatchSource.STATE_OPPONENT_BACK else 0.0


## The room closed under the player. An abandonment shows "Match abandoned" with Leave (R49);
## any other close is main's to route.
func _on_match_closed(reason: String) -> void:
	if reason != MatchSource.CLOSED_ABANDONED:
		return
	_closed = true
	_paused = false
	if card_lift.is_holding():
		card_lift.put_down()
	hud.show_pause(false, true)
	hud.set_waiting("")
	hud.show_abandoned()
	_refresh_commit_enabled()


## A reconnect's whole redacted history (P8): the table is cleared and the history replayed at
## speed with no prompt waits, then play resumes at normal speed.
func _on_catch_up(events: Array[MatchEvent], _view: SeatView) -> void:
	_serial += 1
	_end_wait()
	card_lift.drop_now()
	_running = false
	_input_locked = true
	_awaited = false
	_paused = false
	_in_flight = false
	_deferring_run = false
	_pile_hide_pending = false
	_queue.clear()
	_close_prompt()
	_clear_table_now()
	hud.show_pause(false, _pvp())
	hud.set_waiting("")
	_crew_pending = false
	_bind_cards()
	_crew_line.build(self, source.view(), _crew)
	catching_up = true
	speed = CATCH_UP_SPEED
	_enqueue(events)
	_run()


func _finish_catch_up() -> void:
	catching_up = false
	speed = AUTOPLAY_SPEED if _autoplay else NORMAL_SPEED


# --- The queue ---------------------------------------------------------------------------


func _enqueue(events: Array[MatchEvent]) -> void:
	var steps: Array[BoardStep] = BoardSteps.from_events(events, speed, source.player_seat)
	for step: BoardStep in steps:
		# A replayed history has no bot thinking time.
		if catching_up and step.kind == BoardStep.Kind.BOT_WAIT:
			continue
		_queue.append(step)


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
	if source.is_over():
		_input_locked = false
	_refresh_commit_enabled()


## Called when the queue runs dry: a local bot moves, a remote opponent is waited for, or the
## player is awaited. Anything it enqueues is picked up by the runner.
func _advance() -> void:
	if _halted or source.is_over() or _in_flight:
		return
	if catching_up:
		_finish_catch_up()
	if source.advance():
		_awaited = false
		return
	if not source.is_player_awaited():
		if _pvp():
			hud.set_waiting(source.opponent_name())
		return
	hud.set_waiting("")
	_awaited = true
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
	if PromptRules.waits(step, _autoplay or catching_up):
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
			_arrivals.deal(step)
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
			_tally.show_multiplied(_tracker.dross_before(step.dross), _tracker.tally)
			_tally.fly_in(step.scores, hud, $Camera3D as Camera3D, speed)
		BoardStep.Kind.TURN_END:
			_refresh_scores()
		BoardStep.Kind.OPPONENT_COMMIT:
			_arrivals.opponent_commit(step)
		BoardStep.Kind.PLAYER_COMMIT:
			_arrivals.player_commit(step, speed)
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
		BoardStep.Kind.EFFECT, BoardStep.Kind.TELEGRAPH:
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
			_arrivals.shuffle_in(step)
			hud.note_deck(step.seat, "Pile shuffled in", step.duration)
		BoardStep.Kind.ENERGY_GRANT:
			# Tithe's grant lands next Turn: this Turn's Energy stays as it is.
			if step.seat == BoardSteps.OWN_SIDE and not step.next_turn:
				_turn_energy += step.amount
				_unstage_all()
		BoardStep.Kind.UNREVEAL:
			_fx.unreveal(step)
		BoardStep.Kind.CREATE:
			_arrivals.create_on_row(step)
		BoardStep.Kind.PLACE:
			_arrivals.place(step)
		BoardStep.Kind.CONTROL:
			_fx.control(step)
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


func _clear_table(step: BoardStep) -> void:
	var rows: Array[CardCollection3D] = [player_row, opponent_row]
	for collection: CardCollection3D in rows:
		var transforms: Array[Transform3D] = []
		for card: Card3D in collection.cards:
			transforms.append(card.global_transform)
		var removed: Array[Card3D] = collection.remove_all()
		for i: int in range(removed.size()):
			_loose.add_child(removed[i])
			removed[i].global_transform = transforms[i]
			_fx.fly_out(removed[i], step.duration)
	_fx.reset_rows()
	_tally.hide_all()
	_chips.clear()
	_refresh_scores()


## The final table stays (R42); Commit and drags are off from here, since may_act() is false
## once the source is over.
func _match_end(step: BoardStep) -> void:
	var line: String = source.result_line()
	if line != "":
		print(line)
	if card_lift.is_holding():
		card_lift.put_down()
	var reason: String = step.source.payload["reason"]
	_paused = false
	hud.show_pause(false, _pvp())
	var rounds: int = step.source.payload["rounds_played"]
	hud.show_result(step.seat, step.wins, reason, rounds, _pvp())
	_refresh_commit_enabled()


# --- Prompts (R55-R58, C16) ----------------------------------------------------------------


## Shows the player's open prompt. Under autoplay the bot answers through the source, so there
## is no banner and no wait (R58). If the source holds no prompt for the player nothing opens,
## and the runner does not wait either. A replayed history (catch-up) opens only its last
## prompt: the source returns the current prompt only, so an earlier one would show it early.
func _open_prompt(step: BoardStep) -> void:
	if _autoplay:
		return
	if catching_up and _prompt_queued():
		return
	var open: Dictionary = source.open_prompt()
	if open.is_empty():
		if not catching_up:
			push_warning("Board: a PROMPT step but the source holds no prompt for the player")
		return
	if catching_up:
		_finish_catch_up()
	_prompt.open(open, step.text, source.view())
	_fx.strip = _prompt.strip_collection()
	_refresh_commit_enabled()


## Whether a PROMPT step is still waiting in the queue.
func _prompt_queued() -> bool:
	for queued: BoardStep in _queue:
		if queued.kind == BoardStep.Kind.PROMPT:
			return true
	return false


## Clears the banner, glows and dim, and lets a held runner continue (R57). `keep_strip` leaves
## the Pile strip up for a choice that flies a card out of it (PILE_HIDE clears it).
func _close_prompt(keep_strip: bool = false) -> void:
	_prompt.close(keep_strip)
	_fx.strip = _prompt.strip_collection()
	prompt_resolved.emit()


## Closes the prompt after the source took its answer (R57, R47): `submitted` is what
## PromptHost returned. The events come through `events_ready` (already here for a local
## source), then the strip's exit. A rejection leaves the prompt up (it should not happen).
func _answer(submitted: bool) -> void:
	if not submitted or _rejected:
		return
	var strip_up: bool = _prompt.strip_up()
	if _answered_events:
		if strip_up:
			_queue.append(BoardSteps.pile_step(false, speed))
	else:
		# A remote answer is still on its way: input stays locked until it lands.
		_in_flight = true
		_pile_hide_pending = strip_up
	_close_prompt(strip_up)
	_prompt.put_down(strip_up)


func _begin_answer() -> void:
	_rejected = false
	_answered_events = false


## The reader's button (R42, R48): submits the lifted option, or toggles it in a multi set.
func _on_action_pressed() -> void:
	_begin_answer()
	_answer(_prompt.press())


## The HUD confirm (R48): submits the selected set.
func _on_confirm_pressed() -> void:
	_begin_answer()
	_answer(_prompt.confirm())


## A Pile count was tapped (R78): the Pile face up in the strip, or the strip away.
func _on_pile_pressed(seat: int) -> void:
	if source == null or _halted:
		return
	_prompt.toggle_pile(seat, source.view())
	_fx.strip = _prompt.strip_collection()


## The Skip button (R63): declines the optional prompt.
func _on_skip_pressed() -> void:
	_begin_answer()
	_answer(_prompt.skip())


# --- Card helpers ------------------------------------------------------------------------


func _collections() -> Array[CardCollection3D]:
	return [player_hand, player_row, opponent_row, opponent_hand]


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


## Commit is on only while the player may act (R18); the label follows the staging (R16).
func _refresh_commit_enabled() -> void:
	hud.set_commit_enabled(may_act() and not _prompt.is_open())


# --- Staging, drag feedback and card pick-up (R1-R20, R26) ---------------------------------


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
	var def: CardDef = source.match_cards().def_of(id)
	return staging.cached_cost(id, source.view, 0 if def == null else def.cost)


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
	var staged: Array[BoardCard] = _staged_cards()
	var expected: Array[int] = []
	for card: BoardCard in staged:
		expected.append(card.instance_id)
	if expected != staging.cards():
		staging.reset(_turn_energy, player_row.cards.size() - staged.size(), _free_first)
		var rejected: Array[BoardCard] = []
		var at_end: int = 0
		for card: BoardCard in staged:
			if staging.insert(card.instance_id, _cost_of(card.instance_id), at_end):
				at_end += 1
			else:
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
		BoardGlow.show(_hand_glow, BoardGlow.Look.IDLE)
		BoardGlow.show(_row_glow, _row_look(false))


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
		BoardGlow.show(_row_glow, _row_look(true))


func _on_row_zone_exited() -> void:
	_over_row = false
	if _row_glow.visible:
		BoardGlow.show(_row_glow, _row_look(false))


func _on_hand_zone_entered() -> void:
	if _hand_glow.visible:
		BoardGlow.show(_hand_glow, BoardGlow.Look.HOVER)


func _on_hand_zone_exited() -> void:
	if _hand_glow.visible:
		BoardGlow.show(_hand_glow, BoardGlow.Look.IDLE)


## The row panel's look: red when it would refuse the dragged card (R14), else idle/hover.
func _row_look(hovered: bool) -> BoardGlow.Look:
	if _drag_from_hand and _drag_card != null and not _card_affordable(_drag_card):
		return BoardGlow.Look.REFUSE
	return BoardGlow.Look.HOVER if hovered else BoardGlow.Look.IDLE


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
	var sent: bool = submit_player(staging.to_action(source.player_seat))
	if not sent:
		# A rejection has already unstaged and warned (_on_action_rejected).
		_refresh_commit_enabled()


func _on_pause_pressed() -> void:
	_open_pause()


func _on_resume_pressed() -> void:
	_paused = false
	hud.show_pause(false, _pvp())
	_refresh_commit_enabled()


func _open_pause() -> void:
	if _paused or source == null or source.is_over() or _closed:
		return
	_paused = true
	_pointer.cancel()
	hud.show_pause(true, _pvp())
	_refresh_commit_enabled()


## Concede works while locked or while the bot is due, so it skips submit_player's lock check.
func _on_concede_pressed() -> void:
	_paused = false
	hud.show_pause(false, _pvp())
	if source == null or source.is_over() or _closed:
		return
	if not _submit(EngineAction.concede(source.player_seat)):
		push_warning("Board: the match refused the concede (error %d)" % _last_error)
		_refresh_commit_enabled()


## Leave (PVP): a running match is conceded first, then main is asked to close the room.
func _on_leave_pressed() -> void:
	_paused = false
	hud.show_pause(false, _pvp())
	if source != null and not source.is_over() and not _closed:
		var sent: bool = _submit(EngineAction.concede(source.player_seat))
		if not sent:
			push_warning("Board: the concede before Leave was refused (error %d)" % _last_error)
	leave_requested.emit()


## Rematch (a local match only): main starts a fresh source with the next seed.
func _on_rematch_pressed() -> void:
	hud.hide_result()
	rematch_requested.emit()
