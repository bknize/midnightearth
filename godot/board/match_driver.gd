class_name MatchDriver
extends RefCounted
## Owns one match for the board (R2, R5, R6): the card data, the engine, the bots, the seed
## and the MATCH_ENDED payload. Seat 1 is always a GreedyBot; seat 0 is too under autoplay.
##
## Bots are seeded GreedyBot.seed_for(seed, seat), exactly as main.gd's smoke run, so the
## seed-1 autoplay match is the smoke match. Only seat 0's redacted events leave the driver
## (R6); only the bots read another seat's view, and only their own.

## The human's seat.
const PLAYER_SEAT: int = 0

## The match seed (read-only).
var match_seed: int:
	get:
		return _seed

## True when both seats are bots (read-only).
var autoplay: bool:
	get:
		return _autoplay

var _seed: int = 0
var _autoplay: bool = false
var _cards: CardDb = null
var _engine: MatchEngine = null
## One entry per seat; null for a seat a human drives.
var _bots: Array[GreedyBot] = []
## Seat 0's redacted events of the last accepted call (start, submit_player or play_bot).
var _last_events: Array[MatchEvent] = []
## The MATCH_ENDED payload, empty until the match is over.
var _end_payload: Dictionary = {}


static func create(p_seed: int, cards: CardDb, p_autoplay: bool) -> MatchDriver:
	var driver: MatchDriver = MatchDriver.new()
	driver._seed = p_seed
	driver._autoplay = p_autoplay
	driver._cards = cards
	driver._engine = MatchEngine.create(p_seed, cards)
	for seat: int in MatchEngine.SEATS:
		if seat == PLAYER_SEAT and not p_autoplay:
			driver._bots.append(null)
		else:
			driver._bots.append(GreedyBot.new(GreedyBot.seed_for(p_seed, seat), cards))
	return driver


## The card data the match was created with.
func card_db() -> CardDb:
	return _cards


## Starts the engine and returns seat 0's redacted events. Empty if the start was rejected
## (failed card data, or already started).
func start() -> Array[MatchEvent]:
	var result: ApplyResult = _engine.start()
	_take(result)
	return _last_events


## Applies a seat-0 action. The caller reads `events_for(0)` of the result, or
## last_events().
func submit_player(action: EngineAction) -> ApplyResult:
	var result: ApplyResult = _engine.apply(action)
	_take(result)
	return result


## Answers seat 0's open prompt with option `index` of `zone` (a `Choice.Zone` value), as
## the plan's CHOOSE action (P3, P19). Rejected like any action when no prompt is open for
## seat 0 or the option is not eligible; the caller reads `events_for(0)` of the result.
func submit_choice(zone: int, index: int) -> ApplyResult:
	return submit_player(EngineAction.choose(PLAYER_SEAT, zone, index))


## Seat 0's open prompt (`{seat, card, verb, zone, options}`), or `{}` when none is open for
## seat 0. Options are positions in the zone, never hidden ids (R34).
func open_prompt() -> Dictionary:
	var prompt: Dictionary = _engine.open_prompt()
	if prompt.is_empty():
		return {}
	var seat: int = prompt.get("seat", -1)
	if seat != PLAYER_SEAT:
		return {}
	return prompt


## True when the match is not over and the awaited seat is bot-driven.
func bot_turn_due() -> bool:
	if _engine.is_over():
		return false
	var seat: int = _engine.awaited_seat()
	if seat < 0 or seat >= _bots.size():
		return false
	return _bots[seat] != null


## One bot action for the awaited seat, chosen from that seat's own view. Fails with
## WRONG_SEAT when no bot is due.
func play_bot() -> ApplyResult:
	if not bot_turn_due():
		return ApplyResult.failure(EngineError.Code.WRONG_SEAT)
	var seat: int = _engine.awaited_seat()
	var bot: GreedyBot = _bots[seat]
	var action: EngineAction = bot.choose(_engine.view_for(seat), _engine)
	var result: ApplyResult = _engine.apply(action)
	_take(result)
	return result


## Seat 0's redacted events of the last accepted action (or of start()).
func last_events() -> Array[MatchEvent]:
	return _last_events


## Seat 0's redacted view.
func view() -> SeatView:
	return _engine.view_for(PLAYER_SEAT)


func is_over() -> bool:
	return _engine.is_over()


## Accepted actions so far.
func action_count() -> int:
	return _engine.accepted_action_count()


## The smoke line's fields (R5); empty until the match is over.
func result_line() -> String:
	if _end_payload.is_empty():
		return ""
	var winner: int = _end_payload["winner"]
	var reason: String = _end_payload["reason"]
	var rounds: int = _end_payload["rounds_played"]
	var raw_wins: Array = _end_payload["wins"]
	var wins: Array[int] = []
	wins.assign(raw_wins)
	return (
		"Board: match ended seed=%d winner=%d wins=%d-%d rounds=%d end=%s actions=%d"
		% [_seed, winner, wins[0], wins[1], rounds, reason, _engine.accepted_action_count()]
	)


## Keeps seat 0's redacted events of an accepted result and the MATCH_ENDED payload.
func _take(result: ApplyResult) -> void:
	if not result.ok:
		_last_events = []
		return
	_last_events = result.events_for(PLAYER_SEAT)
	for event: MatchEvent in result.events:
		if event.kind == MatchEvent.Kind.MATCH_ENDED:
			_end_payload = event.payload.duplicate(true)
