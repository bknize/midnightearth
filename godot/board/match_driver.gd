# gdlint: ignore=max-public-methods
class_name MatchDriver
extends MatchSource
## The local MatchSource (cycle 12 P5), owning one match for the board (R2, R5, R6): the card
## data, the engine, the bots, the seed, both deck ids (DC-07 P14) and the MATCH_ENDED payload.
## Seat 1 is always the named bot (BotRegistry); seat 0 is too under autoplay.
##
## Bots are seeded BotRegistry.seed_for(seed, seat), exactly as main.gd's smoke run, so the
## seed-1 autoplay match is the smoke match under the same bot. Only seat 0's redacted
## events leave the driver (R6); only the bots read another seat's view, and only their own.
## The board plays against it through the MatchSource calls; the older apply-style calls
## (begin, submit_player, apply_choice, apply_set, play_bot, last_events) stay for the suites.

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
var _engine: MatchEngine = null
## One entry per seat; null for a seat a human drives.
var _bots: Array[BotPlayer] = []
var _bot_name: String = ""
## Seat 0's redacted events of the last call (start, submit_player or play_bot); empty
## after a rejected one.
var _last_events: Array[MatchEvent] = []
## The MATCH_ENDED payload, empty until the match is over.
var _end_payload: Dictionary = {}
## Seat 0's view, built on first use after each accepted call (the engine changes only there).
var _view: SeatView = null


## A match on `p_seed` where seat s plays `deck_ids[s]` of `decks` over the pool `cards`
## and its deck's Crew from `crew` (cycle 8 R42, P12). An empty id takes the seed's own
## pairing (DC-07 R6, P14; MatchEngine.create). An unknown id or failed data makes start()
## return no events. The bots come from
## BotRegistry.make(`bot_name`); null when it cannot build one (the caller reports).
static func create(
	p_seed: int,
	cards: CardDb,
	decks: DeckList,
	ids: Array[String],
	p_autoplay: bool,
	p_bot_name: String,
	crew: CrewPool
) -> MatchDriver:
	var driver: MatchDriver = MatchDriver.new()
	driver._seed = p_seed
	driver.player_seat = PLAYER_SEAT
	driver._autoplay = p_autoplay
	driver._bot_name = p_bot_name
	driver._engine = MatchEngine.create(p_seed, cards, decks, ids, crew)
	var defs: MatchCards = driver._engine.match_cards()
	for seat: int in MatchEngine.SEATS:
		if seat == PLAYER_SEAT and not p_autoplay:
			driver._bots.append(null)
			continue
		var bot: BotPlayer = BotRegistry.make(p_bot_name, BotRegistry.seed_for(p_seed, seat), defs)
		if bot == null:
			return null
		driver._bots.append(bot)
	return driver


## The match's definitions by instance id (DC-07 P3): read a card through its origin's
## deck, not the pool.
func match_cards() -> MatchCards:
	return _engine.match_cards()


## The deck id each seat plays, indexed by seat, with a seeded pairing already resolved
## (DC-07 P14).
func deck_ids() -> Array[String]:
	return _engine.deck_ids()


## Starts the engine and returns seat 0's redacted events. Empty if the start was rejected
## (failed card data, or already started).
func begin() -> Array[MatchEvent]:
	var result: ApplyResult = _engine.start()
	_take(result)
	return _last_events


## MatchSource: starts the match and emits seat 0's opening events (none if the start was
## rejected).
func start() -> void:
	var opening: Array[MatchEvent] = begin()
	if not opening.is_empty():
		events_ready.emit(opening)


## MatchSource: applies the player's action; `events_ready` carries its events, or
## `action_rejected` its error. A bot's reply is not played here: the board asks advance().
func submit(action: EngineAction) -> void:
	var result: ApplyResult = submit_player(action)
	if not result.ok:
		action_rejected.emit(result.error)
		return
	events_ready.emit(_last_events)


## MatchSource: answers the open prompt through submit().
func submit_choice(zone: int, index: int) -> void:
	submit(EngineAction.choose(PLAYER_SEAT, zone, index))


## MatchSource: answers the open multi-select prompt through submit().
func submit_set(zone: int, indices: Array[int]) -> void:
	submit(EngineAction.choose_set(PLAYER_SEAT, zone, indices))


## MatchSource: declines the open optional prompt through submit().
func submit_decline() -> void:
	submit(EngineAction.decline(PLAYER_SEAT))


## MatchSource: plays the next due bot action and emits its events. False when no bot is due,
## or when the engine rejected the bot's action (reported with push_error).
func advance() -> bool:
	if not bot_turn_due():
		return false
	var result: ApplyResult = play_bot()
	if not result.ok:
		push_error("Board: the bot's action was rejected (code %d)" % result.error)
		return false
	events_ready.emit(_last_events)
	return true


func allows_rematch() -> bool:
	return true


## Applies a seat-0 action. The caller reads `events_for(0)` of the result, or
## last_events().
func submit_player(action: EngineAction) -> ApplyResult:
	var result: ApplyResult = _engine.apply(action)
	_take(result)
	return result


## Answers seat 0's open prompt with option `index` of `zone` (a `Choice.Zone` value), as
## the plan's CHOOSE action (P3, P19). Rejected like any action when no prompt is open for
## seat 0 or the option is not eligible; the caller reads `events_for(0)` of the result.
func apply_choice(zone: int, index: int) -> ApplyResult:
	return submit_player(EngineAction.choose(PLAYER_SEAT, zone, index))


## Answers seat 0's open multi-select prompt with the set `indices` of `zone` (a
## `Choice.Zone` value), as the plan's CHOOSE_SET action (DC-07 P7). An empty set declines.
## Rejected like any action: NO_PROMPT with no prompt open, NOT_ELIGIBLE for a single-target
## prompt, BAD_SET for a repeated or non-offered index; the caller reads `events_for(0)` of
## the result.
func apply_set(zone: int, indices: Array[int]) -> ApplyResult:
	return submit_player(EngineAction.choose_set(PLAYER_SEAT, zone, indices))


## Seat 0's open prompt (`{seat, card, verb, zone, options, multi}`), or `{}` when none is
## open for seat 0. Options are positions in the zone, never hidden ids (R34); `multi` is
## true when the prompt takes a set (apply_set) rather than one position (apply_choice).
func open_prompt() -> Dictionary:
	var prompt: Dictionary = _engine.open_prompt()
	if prompt.is_empty():
		return {}
	var seat: int = prompt.get("seat", -1)
	if seat != PLAYER_SEAT:
		return {}
	prompt[Choice.KEY_MULTI] = Choice.is_multi_prompt(prompt)
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
	var bot: BotPlayer = _bots[seat]
	var action: EngineAction = bot.choose(_engine.view_for(seat), _engine)
	var result: ApplyResult = _engine.apply(action)
	_take(result)
	return result


## Seat 0's redacted events of the last action (or of start()); empty when it was rejected.
func last_events() -> Array[MatchEvent]:
	return _last_events


## Seat 0's redacted view. Built once per engine change; callers only read it.
func view() -> SeatView:
	if _view == null:
		_view = _engine.view_for(PLAYER_SEAT)
	return _view


## Whether seat 0 is the awaited seat (SeatView.is_awaited() without building a view).
func is_player_awaited() -> bool:
	return _engine.awaited_seat() == PLAYER_SEAT


func is_over() -> bool:
	return _engine.is_over()


## Accepted actions so far.
func action_count() -> int:
	return _engine.accepted_action_count()


## The smoke line's fields (R5), with both deck ids right after the seed (DC-07 P14,
## R53); empty until the match is over.
func result_line() -> String:
	if _end_payload.is_empty():
		return ""
	var summary_line: String = summary(
		_seed, _engine.deck_ids(), _bot_name, _end_payload, _engine.accepted_action_count()
	)
	return "Board: match ended " + summary_line


## The fields of a finished match as the smoke lines print them (main.gd's "Engine smoke:"
## and result_line()): "seed=.. decks=a/b bot=.. winner=.. wins=x-y rounds=.. end=..
## actions=..", from a MATCH_ENDED `payload`.
static func summary(
	p_seed: int, decks: Array[String], bot_name: String, payload: Dictionary, actions: int
) -> String:
	var winner: int = payload["winner"]
	var reason: String = payload["reason"]
	var rounds: int = payload["rounds_played"]
	var raw_wins: Array = payload["wins"]
	var wins: Array[int] = []
	wins.assign(raw_wins)
	return (
		"seed=%d decks=%s/%s bot=%s winner=%d wins=%d-%d rounds=%d end=%s actions=%d"
		% [p_seed, decks[0], decks[1], bot_name, winner, wins[0], wins[1], rounds, reason, actions]
	)


## Keeps seat 0's redacted events of an accepted result and the MATCH_ENDED payload.
func _take(result: ApplyResult) -> void:
	_view = null
	if not result.ok:
		_last_events = []
		return
	_last_events = result.events_for(PLAYER_SEAT)
	for event: MatchEvent in result.events:
		if event.kind == MatchEvent.Kind.MATCH_ENDED:
			_end_payload = event.payload.duplicate(true)
