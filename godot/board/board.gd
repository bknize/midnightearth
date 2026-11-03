class_name Board
extends Node3D
## The table (R3-R8, R31-R39, R44): a fixed camera on four card collections, a HUD, and the
## step queue that plays a MatchDriver's events one beat at a time. This task is the
## autoplay path; drag staging, the Commit button, pause, concede and rematch are T08's.
##
## Seeds: `fixed_seed` if non-zero, else `--seed=N`, else a clock seed. The clock is read
## here and nowhere else, and only to make the seed. `--autoplay` or `autoplay` makes seat 0
## a bot too and plays at 4x.

## Emitted when the queue is empty and the human's commit is awaited. Input is unlocked.
signal player_turn_started

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

## 0 means "ask the command line, then the clock".
@export var fixed_seed: int = 0
@export var autoplay: bool = false

## The current match, for T08 and tests.
var driver: MatchDriver = null

## True while any step is queued or running (R39).
var input_locked: bool:
	get:
		return _input_locked

## Seconds divisor for every step: 1 normally, 4 under autoplay.
var speed: float = NORMAL_SPEED

var _cards: CardDb = null
var _autoplay: bool = false
var _input_locked: bool = true
var _running: bool = false
var _halted: bool = false
## Bumped by start_match so a runner from an earlier match stops touching the table.
var _serial: int = 0
var _queue: Array[BoardStep] = []
## Seat 0's cards by engine instance id.
var _player_cards: Dictionary[int, BoardCard] = {}
## Displayed scores; they follow reveals and turn ends, not the engine.
var _scores: Array[int] = [0, 0]

@onready var hud: BoardHud = $BoardHud
@onready var player_hand: CardCollection3D = $DragController/PlayerHand
@onready var player_row: CardCollection3D = $DragController/PlayerRow
@onready var opponent_row: CardCollection3D = $DragController/OpponentRow
@onready var opponent_hand: CardCollection3D = $DragController/OpponentHand
@onready var _entry: Marker3D = $EntryMarker
@onready var _exit: Marker3D = $ExitMarker
@onready var _loose: Node3D = $Loose


func _ready() -> void:
	_cards = CardDb.load_default()
	if not _cards.is_valid():
		push_error("Card data failed to load: %s" % _cards.load_error())
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_autoplay = autoplay or args.has(AUTOPLAY_ARG)
	speed = AUTOPLAY_SPEED if _autoplay else NORMAL_SPEED
	start_match(_resolve_seed(args))


## Starts a fresh match: new driver, empty table, the opening events as steps.
func start_match(new_seed: int) -> void:
	_serial += 1
	_running = false
	_halted = false
	_queue.clear()
	driver = MatchDriver.create(new_seed, _cards, _autoplay)
	_clear_table_now()
	var events: Array[MatchEvent] = driver.start()
	if events.is_empty():
		push_error("Board: the match did not start (seed %d)" % new_seed)
		_halted = true
		return
	_enqueue(events)
	_run()


## Applies the player's action through the driver and queues its steps. Returns false,
## changing nothing, while input is locked or when the engine rejects the action.
func submit_player(action: EngineAction) -> bool:
	if _input_locked or driver == null or driver.is_over() or _halted:
		return false
	var result: ApplyResult = driver.submit_player(action)
	if not result.ok:
		return false
	_input_locked = true
	_enqueue(driver.last_events())
	_run()
	return true


## T08 hook: a turn starts, so staged cards and energy reset here.
func _on_turn_started(_step: BoardStep) -> void:
	pass


## The seed for a first match: fixed, then --seed=N, then the clock.
func _resolve_seed(args: PackedStringArray) -> int:
	if fixed_seed != 0:
		return fixed_seed
	for arg: String in args:
		if arg.begins_with(SEED_ARG):
			var text: String = arg.substr(SEED_ARG.length())
			if text.is_valid_int():
				return text.to_int()
	var ticks: int = Time.get_ticks_usec()
	var unix_usec: int = int(Time.get_unix_time_from_system() * 1000000.0)
	var mixed: int = (ticks ^ (unix_usec << 7) ^ (unix_usec >> 11)) & SEED_MASK
	return mixed if mixed != 0 else 1


# --- The queue ---------------------------------------------------------------------------


func _enqueue(events: Array[MatchEvent]) -> void:
	var steps: Array[BoardStep] = BoardSteps.from_events(events, speed, MatchDriver.PLAYER_SEAT)
	_queue.append_array(steps)


## The one runner. Plays the queue, then asks _advance() what comes next, until nothing
## more is queued. A second call while running is a no-op: the running loop picks up
## whatever was enqueued.
func _run() -> void:
	if _running:
		return
	_running = true
	_input_locked = true
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
		_enqueue(driver.last_events())
		return
	_input_locked = false
	player_turn_started.emit()


func _play(step: BoardStep, serial: int) -> void:
	if step.delay > 0.0:
		await _wait(step.delay)
		if serial != _serial:
			return
	_apply(step)
	if step.duration > 0.0:
		await _wait(step.duration)


func _wait(seconds: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout


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


## Autoplay: the committed cards are still in the hand. Player mode: T08 has them on the
## row already, so each is skipped.
func _player_commit(step: BoardStep) -> void:
	var raw: Array = step.source.payload["cards"]
	var ids: Array[int] = []
	ids.assign(raw)
	for id: int in ids:
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
	_scores.assign([0, 0])
	hud.set_scores(_scores)


func _match_end(step: BoardStep) -> void:
	print(driver.result_line())
	var reason: String = step.source.payload["reason"]
	hud.show_result(step.seat, step.wins, reason)


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
	for collection: CardCollection3D in _collections():
		var removed: Array[Card3D] = collection.remove_all()
		for card: Card3D in removed:
			card.queue_free()
	for child: Node in _loose.get_children():
		child.queue_free()
	_player_cards.clear()
	_scores.assign([0, 0])
	var zeros: Array[int] = [0, 0]
	hud.set_scores(zeros)
	hud.set_wins(zeros)
	hud.hide_result()
