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

const CARD_SCENE: PackedScene = preload("res://board/board_card.tscn")
const AUTOPLAY_SPEED: float = 4.0
const NORMAL_SPEED: float = 1.0
const SEED_ARG: String = "--seed="
const AUTOPLAY_ARG: String = "--autoplay"
## Shortest tween the collections are given, so a zero-length step never divides or stalls.
const MIN_TWEEN_TIME: float = 0.01
## Seconds at 1x for a player commit to slide onto the row when it is not already there.
const PLAYER_COMMIT_TIME: float = 0.25
const REVEAL_LIFT: float = 0.8
const SEED_MASK: int = 0x7FFFFFFF
## Seconds at 1x for an unstaged card to slide back to the hand.
const UNSTAGE_TIME: float = 0.2

## 0 means "ask the command line, then the clock".
@export var fixed_seed: int = 0
@export var autoplay: bool = false

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
## Displayed scores; they follow reveals and turn ends, not the engine.
var _scores: Array[int] = [0, 0]
## True when the first seed was fixed (`fixed_seed` or --seed=), so a rematch uses seed + 1.
var _seed_fixed: bool = false
var _paused: bool = false
var _turn_energy: int = 0
## Seat 0's instance ids already committed this round; they stay on the row, unmovable.
var _committed_ids: Dictionary[int, bool] = {}
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
@onready var _pointer: PointerShim = $PointerShim
@onready var _entry: Marker3D = $EntryMarker
@onready var _exit: Marker3D = $ExitMarker
@onready var _loose: Node3D = $Loose


func _ready() -> void:
	player_hand.drag_strategy = _make_strategy(BoardDragStrategy.Role.PLAYER_HAND)
	player_row.drag_strategy = _make_strategy(BoardDragStrategy.Role.PLAYER_ROW)
	opponent_row.drag_strategy = _make_strategy(BoardDragStrategy.Role.OPPONENT)
	opponent_hand.drag_strategy = _make_strategy(BoardDragStrategy.Role.OPPONENT)
	hud.set_commit_enabled(false)
	_cards = CardDb.load_default()
	if not _cards.is_valid():
		push_error("Card data failed to load: %s" % _cards.load_error())
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_autoplay = autoplay or args.has(AUTOPLAY_ARG)
	speed = AUTOPLAY_SPEED if _autoplay else NORMAL_SPEED
	start_match(_resolve_seed(args))


func _process(delta: float) -> void:
	if not _waiting:
		return
	_wait_left -= delta
	if _wait_left <= 0.0:
		_end_wait()


func _exit_tree() -> void:
	_serial += 1
	_end_wait()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_open_pause()
		get_viewport().set_input_as_handled()


## Starts a fresh match: new driver, empty table, the opening events as steps.
func start_match(new_seed: int) -> void:
	_serial += 1
	_end_wait()
	_running = false
	_halted = false
	_input_locked = true
	_awaited = false
	_paused = false
	_queue.clear()
	driver = MatchDriver.create(new_seed, _cards, _autoplay)
	_clear_table_now()
	hud.show_pause(false)
	_refresh_staging_ui()
	var events: Array[MatchEvent] = driver.start()
	if events.is_empty():
		push_error("Board: the match did not start (seed %d)" % new_seed)
		_halted = true
		return
	_enqueue(events)
	_run()


## Applies the player's action through the driver and queues its steps. Returns false,
## changing nothing, while input is locked or when the engine rejects the action (the
## engine's error code is then in `_last_error`).
func submit_player(action: EngineAction) -> bool:
	if _input_locked or driver == null or driver.is_over() or _halted:
		return false
	return _submit(action)


## True while the player may drag and commit (R18): no step queued or running, not under
## autoplay, the match not over, the pause menu closed, and seat 0 awaited.
func may_act() -> bool:
	if driver == null or _autoplay or _input_locked or _paused or _halted:
		return false
	if driver.is_over():
		return false
	return _awaited


## A turn starts (R15, R16): staging is emptied for the turn's energy and Commit waits for
## the player to be awaited.
func _on_turn_started(step: BoardStep) -> void:
	_turn_energy = step.energy
	_unstage_all()


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
	_run()
	return true


## The seed for a first match: fixed, then --seed=N, then the clock.
func _resolve_seed(args: PackedStringArray) -> int:
	if fixed_seed != 0:
		_seed_fixed = true
		return fixed_seed
	for arg: String in args:
		if arg.begins_with(SEED_ARG):
			var text: String = arg.substr(SEED_ARG.length())
			if text.is_valid_int():
				_seed_fixed = true
				return text.to_int()
	return _clock_seed()


## The only clock read: a fresh seed for a first match with no fixed seed, or a rematch.
func _clock_seed() -> int:
	var ticks: int = Time.get_ticks_usec()
	var unix_usec: int = int(Time.get_unix_time_from_system() * 1000000.0)
	var mixed: int = (ticks ^ (unix_usec << 7) ^ (unix_usec >> 11)) & SEED_MASK
	return mixed if mixed != 0 else 1


## The rematch seed (R43): seed + 1 when the first seed was fixed, else a fresh clock seed.
func _next_seed() -> int:
	if _seed_fixed and driver != null:
		var bumped: int = (driver.match_seed + 1) & SEED_MASK
		return bumped if bumped != 0 else 1
	return _clock_seed()


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
	match step.kind:
		BoardStep.Kind.CLEAR_TABLE:
			_clear_table(step)
		BoardStep.Kind.DEAL, BoardStep.Kind.DRAW:
			_deal(step)
		BoardStep.Kind.BURN:
			_burn(step)
		BoardStep.Kind.TURN_START:
			hud.set_round_turn(step.round_number, step.turn, step.round_number > MatchRules.ROUNDS)
			hud.set_energy(step.energy, step.energy)
			_on_turn_started(step)
		BoardStep.Kind.BOT_WAIT:
			pass
		BoardStep.Kind.OPPONENT_COMMIT:
			_opponent_commit(step)
		BoardStep.Kind.PLAYER_COMMIT:
			_player_commit(step)
		BoardStep.Kind.REVEAL:
			_reveal(step)
		BoardStep.Kind.TURN_END:
			_scores.assign(step.scores)
			hud.set_scores(_scores)
		BoardStep.Kind.ROUND_END:
			hud.set_wins(step.wins)
		BoardStep.Kind.MATCH_END:
			_match_end(step)


func _deal(step: BoardStep) -> void:
	var hand: CardCollection3D = player_hand if step.seat == 0 else opponent_hand
	var card: BoardCard = _spawn_card()
	hand.card_move_tween_duration = maxf(step.duration, MIN_TWEEN_TIME)
	hand.append_card(card)
	card.global_position = _entry.global_position
	if step.seat == 0:
		_show(card, step)
		_player_cards[step.card] = card
	else:
		card.face_down = true


func _burn(step: BoardStep) -> void:
	var card: BoardCard = _spawn_card()
	_loose.add_child(card)
	card.global_position = _entry.global_position
	if step.seat == 0:
		_show(card, step)
	else:
		card.face_down = true
	_fly_out(card, step.duration)


func _opponent_commit(step: BoardStep) -> void:
	var each: float = step.duration / float(maxi(step.count, 1))
	for i: int in range(step.count):
		if opponent_hand.cards.is_empty():
			push_warning("Board: the opponent committed more cards than its fan holds")
			return
		var card: Card3D = opponent_hand.cards[opponent_hand.cards.size() - 1]
		_move_card(card, opponent_hand, opponent_row, each)


## Autoplay: the committed cards are still in the hand. Player mode: they were staged on the
## row already, so each is only marked committed.
func _player_commit(step: BoardStep) -> void:
	var raw: Array = step.source.payload["cards"]
	var ids: Array[int] = []
	ids.assign(raw)
	for id: int in ids:
		_committed_ids[id] = true
		var card: BoardCard = _player_card(id)
		if card == null or player_row.cards.has(card):
			continue
		_move_card(card, player_hand, player_row, PLAYER_COMMIT_TIME / speed)


func _reveal(step: BoardStep) -> void:
	if step.seat == 0:
		var own: BoardCard = _player_card(step.card)
		if own != null:
			_lift_and_settle(own, step.duration)
	else:
		var card: BoardCard = _next_unrevealed()
		if card == null:
			push_warning("Board: a reveal found no face-down card on the opponent's row")
		else:
			card.instance_id = step.card
			_show(card, step)
			_flip_up(card, step.duration)
	if step.seat >= 0 and step.seat < _scores.size():
		_scores[step.seat] += step.power
	hud.set_scores(_scores)


func _clear_table(step: BoardStep) -> void:
	for collection: CardCollection3D in _collections():
		var transforms: Array[Transform3D] = []
		for card: Card3D in collection.cards:
			transforms.append(card.global_transform)
		var removed: Array[Card3D] = collection.remove_all()
		for i: int in range(removed.size()):
			_loose.add_child(removed[i])
			removed[i].global_transform = transforms[i]
			_fly_out(removed[i], step.duration)
	_player_cards.clear()
	_committed_ids.clear()
	_scores.assign([0, 0])
	hud.set_scores(_scores)


## The final table stays (R42); Commit and drags are off from here, since may_act() is false
## once the driver is over.
func _match_end(step: BoardStep) -> void:
	print(driver.result_line())
	var reason: String = step.source.payload["reason"]
	_paused = false
	hud.show_pause(false)
	hud.show_result(step.seat, step.wins, reason)
	_refresh_commit_enabled()


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


## Face text for a card the viewer may see. The card must be in the tree.
func _show(card: BoardCard, step: BoardStep) -> void:
	card.instance_id = step.card
	var def: CardDef = _cards.card_at(step.def_index)
	if def == null:
		push_warning("Board: no card definition for index %d" % step.def_index)
		return
	card.show_def(def)


## The first opponent card on the row that still has no id, in row order.
func _next_unrevealed() -> BoardCard:
	for card: Card3D in opponent_row.cards:
		var candidate: BoardCard = card as BoardCard
		if candidate != null and candidate.instance_id == -1:
			return candidate
	return null


## Moves a card between collections, keeping its place on screen so the new layout tweens
## it over from there.
func _move_card(
	card: Card3D, source: CardCollection3D, target: CardCollection3D, duration: float
) -> void:
	var index: int = source.cards.find(card)
	if index < 0:
		return
	var placed: Transform3D = card.global_transform
	var moved: Card3D = source.remove_card(index)
	target.card_move_tween_duration = maxf(duration, MIN_TWEEN_TIME)
	target.append_card(moved)
	moved.global_transform = placed


func _flip_up(card: BoardCard, duration: float) -> void:
	var mesh: Node3D = card.get_node("CardMesh") as Node3D
	var tween: Tween = create_tween()
	_add_tween(tween, mesh, ^"rotation:y", 0.0, maxf(duration, MIN_TWEEN_TIME))
	var err: int = tween.finished.connect(_unflag_face_down.bind(card))
	if err != OK:
		card.face_down = false


func _unflag_face_down(card: BoardCard) -> void:
	if is_instance_valid(card):
		card.face_down = false


func _lift_and_settle(card: BoardCard, duration: float) -> void:
	var mesh: Node3D = card.get_node("CardMesh") as Node3D
	var half: float = maxf(duration, MIN_TWEEN_TIME) / 2.0
	var tween: Tween = create_tween()
	_add_tween(tween, mesh, ^"position:z", REVEAL_LIFT, half)
	_add_tween(tween, mesh, ^"position:z", 0.0, half)


## Sweeps a card from where it is to the exit marker and frees it.
func _fly_out(card: Card3D, duration: float) -> void:
	_stop_card_tweens(card)
	var tween: Tween = create_tween()
	_add_tween(
		tween, card, ^"global_position", _exit.global_position, maxf(duration, MIN_TWEEN_TIME)
	)
	var err: int = tween.finished.connect(card.queue_free)
	if err != OK:
		card.queue_free()


func _stop_card_tweens(card: Card3D) -> void:
	for running: Tween in [card.position_tween, card.rotate_tween, card.hover_tween]:
		if running != null and running.is_valid():
			running.kill()


func _add_tween(
	tween: Tween, target: Object, property: NodePath, value: Variant, duration: float
) -> void:
	var tweener: PropertyTweener = tween.tween_property(target, property, value, duration)
	tweener = tweener.set_trans(Tween.TRANS_SINE)
	tweener = tweener.set_ease(Tween.EASE_IN_OUT)


## Frees every card now and clears the HUD, for a new match.
func _clear_table_now() -> void:
	_pointer.cancel()
	for collection: CardCollection3D in _collections():
		var removed: Array[Card3D] = collection.remove_all()
		for card: Card3D in removed:
			card.queue_free()
	for child: Node in _loose.get_children():
		child.queue_free()
	_player_cards.clear()
	_committed_ids.clear()
	_turn_energy = 0
	staging.reset(0)
	_drag_card = null
	_drag_from_hand = false
	_over_row = false
	_scores.assign([0, 0])
	var zeros: Array[int] = [0, 0]
	hud.set_scores(zeros)
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
	return strategy


func _is_locked() -> bool:
	return _input_locked


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


## The cost of a card instance: its definition is `id % DECK_SIZE` of the card data.
func _cost_of(id: int) -> int:
	var def: CardDef = _cards.card_at(id % MatchRules.DECK_SIZE)
	if def == null:
		return 0
	return def.cost


## Commit is on only while the player may act (R18); the label follows the staging (R16).
func _refresh_commit_enabled() -> void:
	hud.set_commit_enabled(may_act())


func _refresh_staging_ui() -> void:
	hud.set_energy(staging.energy_left(), _turn_energy)
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


## Committed cards keep the left of the row; staged cards sit to their right (C10).
func _normalize_row() -> void:
	var wanted: Array[Card3D] = []
	for card: Card3D in player_row.cards:
		var board_card: BoardCard = card as BoardCard
		if board_card == null or _committed_ids.has(board_card.instance_id):
			wanted.append(card)
	for staged: BoardCard in _staged_cards():
		wanted.append(staged)
	for i: int in range(wanted.size()):
		if player_row.cards[i] != wanted[i]:
			player_row.move_card(wanted[i], i)


## Row index of a staged card among the staged cards only.
func _staged_index(card: Card3D) -> int:
	var committed: int = player_row.cards.size() - _staged_cards().size()
	return maxi(player_row.cards.find(card) - committed, 0)


## Rebuilds staging from the row if it ever differs from it; any staged card that no longer
## fits goes back to the hand (R14). Then refreshes the energy readout and the button.
func _resync_staging() -> void:
	var expected: Array[int] = []
	for card: BoardCard in _staged_cards():
		expected.append(card.instance_id)
	if expected != staging.cards():
		staging.reset(_turn_energy)
		var rejected: Array[BoardCard] = []
		for card: BoardCard in _staged_cards():
			var at_end: int = staging.cards().size()
			if not staging.insert(card.instance_id, _cost_of(card.instance_id), at_end):
				rejected.append(card)
		for card: BoardCard in rejected:
			_move_card(card, player_row, player_hand, UNSTAGE_TIME / speed)
	_refresh_staging_ui()


## Sends every staged card back to the hand and empties staging for this turn's energy.
func _unstage_all() -> void:
	for card: BoardCard in _staged_cards():
		_move_card(card, player_row, player_hand, UNSTAGE_TIME / speed)
	staging.reset(_turn_energy)
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
		_normalize_row()
		var inserted: bool = staging.insert(id, _cost_of(id), _staged_index(card))
		if not inserted:
			push_warning("Board: staging refused card %d dropped on the row" % id)
	elif from_collection == player_row and to_collection == player_hand:
		staging.remove(id)
	elif from_collection == player_row and to_collection == player_row:
		_normalize_row()
		staging.move(id, _staged_index(card))
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
	_drag_card = null
	_drag_from_hand = false
	_over_row = false
	_drag_cancelled = false
	_resync_staging()


func _on_row_zone_entered() -> void:
	_over_row = true


func _on_row_zone_exited() -> void:
	_over_row = false


func _on_pointer_cancelled() -> void:
	_drag_cancelled = true


# --- Commit, pause, concede, rematch (R16, R17, R40-R43) -----------------------------------


func _on_commit_pressed() -> void:
	if not may_act():
		return
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
	start_match(_next_seed())
