class_name TestMatchDriver
extends GdUnitTestSuite
## MatchDriver (R2, R5, R6, C11): the seed-1 autoplay match through the driver equals the
## smoke match and prints the board's result line, seat 0 never sees a seat-1 card id, a
## seat-0 concede ends the match with reason "concede", and bot turns are due exactly when
## the human is not awaited. DC-05 T07: play_bot() answers a bot's prompt, and seat 0's
## prompt is read with open_prompt() and answered with apply_choice(). DC-07 T02 (P14):
## the driver takes the pool, the deck list and a deck id per seat (the fixture deck on
## both seats here), resolves an empty id to the seed's pick, and the result line names
## both decks right after the seed.

const SEED: int = 1
const MAX_ACTIONS: int = 2000
## An index no prompt offers (options are positions in a zone of at most a few cards).
const NOT_AN_OPTION: int = 99
## Seed 1's pinned board result line, re-pinned at DC-07 T13 with `decks=<a>/<b>` after
## the seed (P14), from the shipped pool and deck list under seed 1's own pairing, as the
## board plays it (headless `--fixed-fps 60 --autoplay` prints the same line);
## the DC-06 T09 line (rules version 3) was "Board: match ended seed=1 winner=0 wins=4-3
## rounds=7 end=wins actions=120", the DC-05 line "... wins=4-2 rounds=6 ... actions=114".
## An empty EXPECTED_LINE fails the pinned-line test (DC-15 C6); the autoplay test also
## compares against a direct bot-vs-bot engine run.
## DC-08 T07 (R5) added `bot=<name>` after the decks; the DC-09 T07 pin under the greedy
## bot was "Board: match ended seed=1 decks=bloom/ruin bot=greedy winner=0 wins=4-0
## rounds=4 end=wins actions=72". Emptied at DC-13 T01 (cycle 9 R70: only the random bot
## is left); re-pinned at DC-13 T11 (rules 7, the random bot): "Board: match ended seed=1
## decks=greed/greed bot=random winner=0 wins=3-1 rounds=7 end=rounds actions=121".
## Unpinned at DC-14 T14 (six decks change seed 1's seeded pairing); re-pinned at DC-14 T18.
## Re-pinned at DC-14 T18 (six decks, 90 cards, ten Crew).
const EXPECTED_LINE: String = (
	"Board: match ended seed=1 decks=combo/graveyard bot=random winner=0 wins=4-1 rounds=5"
	+ " end=wins actions=191"
)
## The bot the helpers build: the random bot, the only one (cycle 9 R70).
const BOT: String = "random"
## Event kinds whose card ids are private to their owner (rules 7: nothing is burned; a
## look-at is private, DC-13 T03).
const PRIVATE_KINDS: Array[int] = [
	MatchEvent.Kind.CARD_DEALT,
	MatchEvent.Kind.CARD_DRAWN,
	MatchEvent.Kind.CARD_LOOKED,
	MatchEvent.Kind.COMMITTED,
]

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## The fixture-vs-fixture definitions over _db() (DC-07 T02), for the MatchCards APIs.
func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


## A driver for `match_seed` with the fixture deck on both seats.
func _driver(match_seed: int, autoplay: bool) -> MatchDriver:
	return MatchDriver.create(
		match_seed,
		_db(),
		FixtureDecks.decks(),
		FixtureDecks.ids(),
		autoplay,
		BOT,
		FixtureDecks.crew()
	)


## Every int under an event payload's `card` or `cards` key.
func _event_card_ids(event: MatchEvent) -> Array[int]:
	var out: Array[int] = []
	var single: Variant = event.payload.get(MatchEvent.KEY_CARD)
	if single is int:
		var card: int = single
		out.append(card)
	var many: Variant = event.payload.get(MatchEvent.KEY_CARDS)
	if many is Array:
		var items: Array = many
		for item: Variant in items:
			if item is int:
				var listed: int = item
				out.append(listed)
	return out


## The seat-1 card ids named by the private events in `events`, as strings for the message.
## A public event is skipped: a Discard enters a public Pile (rules 7).
func _opponent_leaks(events: Array[MatchEvent]) -> Array[String]:
	var found: Array[String] = []
	for event: MatchEvent in events:
		if not PRIVATE_KINDS.has(event.kind) or not event.is_private():
			continue
		for card: int in _event_card_ids(event):
			if card >= MatchRules.DECK_SIZE:
				found.append("event %d names card %d" % [event.kind, card])
	return found


## Seed 1 played bot-vs-bot straight through MatchEngine, as main.gd's smoke run plays it,
## written as the board's result line; a message naming the problem when it fails.
func _smoke_line() -> String:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	if not engine.start().ok:
		return "smoke match did not start"
	var bots: Array[RandomBot] = [
		RandomBot.new(BotRegistry.seed_for(SEED, 0), _defs()),
		RandomBot.new(BotRegistry.seed_for(SEED, 1), _defs()),
	]
	var ended: Dictionary = {}
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var action: EngineAction = bots[seat].choose(engine.view_for(seat), engine)
		var result: ApplyResult = engine.apply(action)
		if not result.ok:
			return "smoke action %d rejected" % actions
		actions += 1
		for event: MatchEvent in result.events:
			if event.kind == MatchEvent.Kind.MATCH_ENDED:
				ended = event.payload
	if ended.is_empty():
		return "smoke match did not end"
	var winner: int = ended["winner"]
	var reason: String = ended["reason"]
	var rounds: int = ended["rounds_played"]
	var raw_wins: Array = ended["wins"]
	var wins: Array[int] = []
	wins.assign(raw_wins)
	var decks: Array[String] = engine.deck_ids()
	return (
		(
			"Board: match ended seed=%d decks=%s/%s bot=%s winner=%d wins=%d-%d rounds=%d end=%s"
			+ " actions=%d"
		)
		% [SEED, decks[0], decks[1], BOT, winner, wins[0], wins[1], rounds, reason, actions]
	)


## True when `events` holds an event of `kind`.
func _has_kind(events: Array[MatchEvent], kind: int) -> bool:
	for event: MatchEvent in events:
		if event.kind == kind:
			return true
	return false


## The seat a prompt is open for in seat 0's view, or -1 when none is open.
func _prompted_seat(driver: MatchDriver) -> int:
	var prompt: Dictionary = driver.view().prompt
	if prompt.is_empty():
		return -1
	var seat: int = prompt.get("seat", -1)
	return seat


## Opens a hand-made prompt for `seat` on `driver`'s started match, at turn start (resume
## `turn_start`, so the answer hands the turn back to the first committer): over positions
## 0 and 1 of the seat's hand, a multi-select when `multi`. No DC-13 T02 ability opens a
## prompt, so the driver's prompt paths are driven this way until T05 and T06.
func _open_prompt(driver: MatchDriver, seat: int, multi: bool) -> void:
	var state: MatchState = driver._engine._state
	state.prompt = {
		"seat": seat,
		"card": -1,
		"verb": "discard_own",
		Choice.KEY_ZONE: Choice.Zone.OWN_HAND,
		Choice.KEY_OPTIONS: [0, 1],
		Choice.KEY_MULTI: multi,
		Choice.KEY_OPTIONAL: false,
		Choice.KEY_RESUME: Choice.RESUME_TURN_START,
		Choice.KEY_CREW: "",
	}
	state.phase = MatchState.Phase.AWAIT_CHOICE


# --- Tests ----------------------------------------------------------------------------


func test_seed_1_autoplay_equals_the_smoke_match() -> void:
	var driver: MatchDriver = _driver(SEED, true)
	assert_bool(driver.autoplay).is_true()
	assert_int(driver.match_seed).is_equal(SEED)
	assert_str(driver.result_line()).is_empty()
	var leaks: Array[String] = _opponent_leaks(driver.begin())
	var steps: int = 0
	while driver.bot_turn_due() and steps < MAX_ACTIONS:
		var result: ApplyResult = driver.play_bot()
		assert_bool(result.ok).override_failure_message("action %d rejected" % steps).is_true()
		if not result.ok:
			return
		leaks.append_array(_opponent_leaks(driver.last_events()))
		steps += 1
	assert_bool(driver.is_over()).override_failure_message("not over after %d" % steps).is_true()
	assert_bool(driver.bot_turn_due()).is_false()
	assert_str(driver.result_line()).is_equal(_smoke_line())
	assert_int(driver.action_count()).is_equal(steps)
	# R6: across the whole match, no seat-1 card id reached seat 0.
	assert_array(leaks).override_failure_message("leaks: %s" % [leaks]).is_empty()


## The seed-1 autoplay line equals the pinned EXPECTED_LINE; an empty pin fails.
func test_seed_1_autoplay_prints_the_pinned_line() -> void:
	assert_str(EXPECTED_LINE).override_failure_message("EXPECTED_LINE is not pinned").is_not_empty()
	# The board's own match: the shipped pool and list, seed 1's seeded pairing.
	var seeded: Array[String] = ["", ""]
	var driver: MatchDriver = MatchDriver.create(
		SEED,
		CardDb.load_default(),
		DeckList.load_default(),
		seeded,
		true,
		BOT,
		CrewPool.load_default()
	)
	driver.start()
	var steps: int = 0
	while driver.bot_turn_due() and steps < MAX_ACTIONS:
		if not driver.play_bot().ok:
			break
		steps += 1
	assert_str(driver.result_line()).is_equal(EXPECTED_LINE)


## DC-07 P14: the result line carries both deck ids right after the seed, and deck_ids()
## gives the ids the engine resolved: the named ones, or the seed's own pick for an empty
## id.
func test_result_line_names_both_decks_after_the_seed() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	assert_array(driver.deck_ids()).is_equal(FixtureDecks.ids())
	driver.start()
	assert_bool(driver.submit_player(EngineAction.concede(0)).ok).is_true()
	var line: String = driver.result_line()
	var head: String = "Board: match ended seed=%d decks=fixture/fixture bot=random winner=" % SEED
	assert_bool(line.begins_with(head)).override_failure_message(line).is_true()
	var seeded: Array[String] = ["", ""]
	var decks: DeckList = FixtureDecks.decks()
	var picked: MatchDriver = MatchDriver.create(
		7, _db(), decks, seeded, true, BOT, FixtureDecks.crew()
	)
	var expected: Array[String] = [decks.seeded_pick(7, 0), decks.seeded_pick(7, 1)]
	assert_array(picked.deck_ids()).is_equal(expected)
	assert_bool(picked.begin().is_empty()).is_false()
	var unknown: Array[String] = ["fixture", "nope"]
	var refused: MatchDriver = MatchDriver.create(
		SEED, _db(), decks, unknown, true, BOT, FixtureDecks.crew()
	)
	assert_array(refused.begin()).is_empty()


func test_seat_0_concede_ends_the_match_with_concede() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	var started: Array[MatchEvent] = driver.begin()
	assert_bool(started.is_empty()).is_false()
	assert_str(driver.result_line()).is_empty()
	var result: ApplyResult = driver.submit_player(EngineAction.concede(0))
	assert_bool(result.ok).is_true()
	assert_bool(driver.is_over()).is_true()
	assert_bool(driver.bot_turn_due()).is_false()
	var line: String = driver.result_line()
	assert_bool(line.contains("end=concede")).override_failure_message(line).is_true()
	assert_bool(line.contains("winner=1")).override_failure_message(line).is_true()


func test_bot_turn_is_due_exactly_when_seat_0_is_not_awaited() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	assert_bool(driver.autoplay).is_false()
	driver.start()
	var passes: int = 0
	var bot_moves: int = 0
	var discards: int = 0
	var steps: int = 0
	while not driver.is_over() and steps < 100:
		var awaited: int = driver.view().awaited_seat
		assert_bool(driver.bot_turn_due()).is_equal(awaited != 0)
		var result: ApplyResult = null
		var prompt: Dictionary = driver.open_prompt()
		if driver.bot_turn_due():
			result = driver.play_bot()
			bot_moves += 1
		elif not prompt.is_empty():
			# Seat 0's discard-down after a pass (rules 7): its first `exact` hand cards.
			var picked: Array[int] = []
			picked.assign(Choice.options_of(prompt).slice(0, Choice.exact_of(prompt)))
			result = driver.apply_set(Choice.zone_of(prompt), picked)
			discards += 1
		else:
			var none: Array[int] = []
			result = driver.submit_player(EngineAction.commit(0, none))
			passes += 1
		assert_bool(result.ok).override_failure_message("step %d rejected" % steps).is_true()
		if not result.ok:
			return
		steps += 1
	assert_int(passes).is_greater(0)
	assert_int(bot_moves).is_greater(0)
	# Passing grows seat 0's hand past its Hand size, so it met its discard-down.
	assert_int(discards).is_greater(0)


func test_play_bot_refuses_when_the_human_is_awaited() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	driver.start()
	# Play bot turns until seat 0 is awaited, then ask for a bot action anyway.
	var steps: int = 0
	while driver.bot_turn_due() and steps < MAX_ACTIONS:
		assert_bool(driver.play_bot().ok).is_true()
		steps += 1
	assert_bool(driver.is_over()).is_false()
	var refused: ApplyResult = driver.play_bot()
	assert_bool(refused.ok).is_false()
	assert_int(refused.error).is_equal(EngineError.Code.WRONG_SEAT)


## A bot's prompt (DC-05 T07): play_bot() answers it with a CHOICE action the engine
## accepts, and seat 0 sees the CHOICE_MADE. open_prompt() is seat 0's prompt only: empty
## while seat 1 is prompted. The prompt is hand-made (_open_prompt, DC-13 T02).
func test_play_bot_answers_a_bot_prompt() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	driver.start()
	_open_prompt(driver, 1, false)
	assert_int(_prompted_seat(driver)).is_equal(1)
	assert_dict(driver.open_prompt()).is_empty()
	assert_bool(driver.bot_turn_due()).is_true()
	var result: ApplyResult = driver.play_bot()
	assert_bool(result.ok).is_true()
	var made: bool = _has_kind(driver.last_events(), MatchEvent.Kind.CHOICE_MADE)
	assert_bool(made).override_failure_message("no CHOICE_MADE").is_true()
	assert_int(_prompted_seat(driver)).is_equal(-1)


## Seat 0's prompt (DC-05 T07): with no prompt open apply_choice() fails with NO_PROMPT;
## once one opens, open_prompt() gives its zone and options, an option it does not offer
## fails with NOT_ELIGIBLE and changes nothing, and an offered option is accepted.
func test_submit_choice_answers_the_open_player_prompt() -> void:
	var idle: MatchDriver = _driver(SEED, false)
	idle.start()
	assert_dict(idle.open_prompt()).is_empty()
	var early: ApplyResult = idle.apply_choice(Choice.Zone.OWN_HAND, 0)
	assert_bool(early.ok).is_false()
	assert_int(early.error).is_equal(EngineError.Code.NO_PROMPT)
	var driver: MatchDriver = _driver(SEED, false)
	driver.start()
	_open_prompt(driver, MatchDriver.PLAYER_SEAT, false)
	var prompt: Dictionary = driver.open_prompt()
	var seat: int = prompt.get("seat", -1)
	assert_int(seat).is_equal(MatchDriver.PLAYER_SEAT)
	assert_int(_prompted_seat(driver)).is_equal(MatchDriver.PLAYER_SEAT)
	assert_bool(driver.bot_turn_due()).is_false()
	var zone: int = prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var options: Array[int] = Choice.options_of(prompt)
	assert_int(options.size()).is_greater_equal(2)
	assert_bool(options.has(NOT_AN_OPTION)).is_false()
	var count: int = driver.action_count()
	var refused: ApplyResult = driver.apply_choice(zone, NOT_AN_OPTION)
	assert_bool(refused.ok).is_false()
	assert_int(refused.error).is_equal(EngineError.Code.NOT_ELIGIBLE)
	assert_int(driver.action_count()).is_equal(count)
	assert_dict(driver.open_prompt()).is_equal(prompt)
	var answered: ApplyResult = driver.apply_choice(zone, options[0])
	assert_bool(answered.ok).is_true()
	assert_int(driver.action_count()).is_equal(count + 1)
	var made: bool = _has_kind(driver.last_events(), MatchEvent.Kind.CHOICE_MADE)
	assert_bool(made).override_failure_message("no CHOICE_MADE for seat 0").is_true()


## DC-07 T05 (P7): apply_set() reaches the engine. With a hand-made multi-select prompt
## for seat 0 over hand positions 0 and 1, open_prompt() says `multi`, a set naming a
## position it does not offer fails with BAD_SET, and a valid set is accepted with
## CHOICE_MADE `indices`.
func test_submit_set_answers_the_open_multi_prompt() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	driver.start()
	_open_prompt(driver, MatchDriver.PLAYER_SEAT, true)
	var prompt: Dictionary = driver.open_prompt()
	var multi: bool = prompt.get(Choice.KEY_MULTI, false)
	assert_bool(multi).is_true()
	var count: int = driver.action_count()
	var bad: Array[int] = [2]
	var refused: ApplyResult = driver.apply_set(Choice.Zone.OWN_HAND, bad)
	assert_int(refused.error).is_equal(EngineError.Code.BAD_SET)
	var chosen: Array[int] = [1]
	var result: ApplyResult = driver.apply_set(Choice.Zone.OWN_HAND, chosen)
	assert_bool(result.ok).is_true()
	assert_int(driver.action_count()).is_equal(count + 1)
	var indices: Array = []
	for event: MatchEvent in driver.last_events():
		if event.kind == MatchEvent.Kind.CHOICE_MADE:
			indices = event.payload["indices"]
	assert_array(indices).is_equal([1])


## Cycle 9 R73: the default bot is `random`. Seed 1 autoplays on the shipped pool under it
## and the result line carries `bot=random`.
func test_default_bot_is_random_and_named_in_the_result_line() -> void:
	assert_str(BotRegistry.default_name()).is_equal("random")
	var seeded: Array[String] = ["", ""]
	var driver: MatchDriver = MatchDriver.create(
		SEED,
		CardDb.load_default(),
		DeckList.load_default(),
		seeded,
		true,
		BotRegistry.default_name(),
		CrewPool.load_default()
	)
	assert_object(driver).is_not_null()
	if driver == null:
		return
	driver.start()
	var steps: int = 0
	while driver.bot_turn_due() and steps < MAX_ACTIONS:
		if not driver.play_bot().ok:
			break
		steps += 1
	var line: String = driver.result_line()
	print("RANDOM_LINE %s" % line)
	assert_bool(line.contains(" bot=random ")).override_failure_message(line).is_true()


## Cycle 9 R73: `random` builds a driver whose bots play; a removed or unknown bot makes
## create return null.
func test_create_with_an_unknown_bot_is_null() -> void:
	var made: MatchDriver = MatchDriver.create(
		SEED, _db(), FixtureDecks.decks(), FixtureDecks.ids(), true, "random", FixtureDecks.crew()
	)
	assert_object(made).is_not_null()
	if made != null:
		assert_bool(made.begin().is_empty()).is_false()
		assert_bool(made.bot_turn_due()).is_true()
	for unknown: String in ["tuned", "nope"]:
		var refused: MatchDriver = MatchDriver.create(
			SEED,
			_db(),
			FixtureDecks.decks(),
			FixtureDecks.ids(),
			true,
			unknown,
			FixtureDecks.crew()
		)
		assert_object(refused).is_null()


## One accepted call for whichever seat is awaited: a bot move, seat 0's discard-down, or
## seat 0's Pass.
func _one_call(driver: MatchDriver) -> ApplyResult:
	if driver.bot_turn_due():
		return driver.play_bot()
	var prompt: Dictionary = driver.open_prompt()
	if not prompt.is_empty():
		var picked: Array[int] = []
		picked.assign(Choice.options_of(prompt).slice(0, Choice.exact_of(prompt)))
		return driver.apply_set(Choice.zone_of(prompt), picked)
	var none: Array[int] = []
	return driver.submit_player(EngineAction.commit(0, none))


## DC-15 C4: view() builds seat 0's view once per engine change. Two reads between calls
## share one view; any call (accepted or rejected) drops it, and the next read matches a
## freshly built view. is_player_awaited() agrees with the view.
func test_view_is_shared_between_calls_and_rebuilt_after_each() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	driver.start()
	var first: SeatView = driver.view()
	assert_object(driver.view()).is_same(first)
	assert_bool(driver.is_player_awaited()).is_equal(first.is_awaited())
	var accepted: ApplyResult = _one_call(driver)
	assert_bool(accepted.ok).is_true()
	var second: SeatView = driver.view()
	assert_object(second).is_not_same(first)
	assert_object(driver.view()).is_same(second)
	assert_bool(driver.is_player_awaited()).is_equal(second.is_awaited())
	var refused: ApplyResult = driver.apply_choice(Choice.Zone.OWN_HAND, NOT_AN_OPTION)
	assert_bool(refused.ok).is_false()
	var third: SeatView = driver.view()
	assert_object(third).is_not_same(second)
	assert_dict(third.to_dict()).is_equal(second.to_dict())


# --- The MatchSource contract (cycle 12 P5) -----------------------------------------------


## A driver on the shipped data and seed 1's seeded pairing, the board's own match.
func _shipped_driver(autoplay: bool) -> MatchDriver:
	var seeded: Array[String] = ["", ""]
	return MatchDriver.create(
		SEED,
		CardDb.load_default(),
		DeckList.load_default(),
		seeded,
		autoplay,
		BOT,
		CrewPool.load_default()
	)


func test_a_driver_is_the_local_match_source() -> void:
	var source: MatchSource = _driver(SEED, false)
	assert_int(source.player_seat).is_equal(0)
	assert_bool(source.allows_rematch()).is_true()
	assert_str(source.opponent_name()).is_equal("Opponent")
	assert_int(source.deck_ids().size()).is_equal(2)
	assert_object(source.match_cards()).is_not_null()


func test_start_emits_seat_0s_opening_events_once() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	var batches: Array[int] = []
	var leaks: Array[String] = []
	driver.events_ready.connect(
		func(events: Array[MatchEvent]) -> void:
			batches.append(events.size())
			leaks.append_array(_opponent_leaks(events))
	)
	driver.start()
	assert_int(batches.size()).is_equal(1)
	assert_int(batches[0]).is_greater(0)
	assert_array(leaks).is_empty()
	assert_object(driver.view()).is_not_null()


## The seed-1 autoplay match through the source calls alone: start() and advance() print the
## pinned golden line, one events_ready per accepted action (plus the opening).
func test_seed_1_autoplay_through_the_source_calls_prints_the_pinned_line() -> void:
	var driver: MatchDriver = _shipped_driver(true)
	var batches: Array[int] = []
	driver.events_ready.connect(
		func(events: Array[MatchEvent]) -> void: batches.append(events.size())
	)
	driver.start()
	var steps: int = 0
	while steps < MAX_ACTIONS and driver.advance():
		steps += 1
	assert_bool(driver.is_over()).is_true()
	assert_bool(driver.advance()).is_false()
	assert_str(driver.result_line()).is_equal(EXPECTED_LINE)
	assert_int(batches.size()).is_equal(steps + 1)
	assert_int(driver.action_count()).is_equal(steps)


## A human seat through submit(), submit_set() and advance(): the bot replies only when asked
## for, every accepted call emits once, and the match ends.
func test_a_human_match_through_submit_and_advance() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	var batches: Array[int] = []
	var rejected: Array[int] = []
	driver.events_ready.connect(
		func(events: Array[MatchEvent]) -> void: batches.append(events.size())
	)
	driver.action_rejected.connect(func(code: int) -> void: rejected.append(code))
	driver.start()
	var calls: int = 0
	while not driver.is_over() and calls < MAX_ACTIONS:
		if driver.is_player_awaited():
			assert_bool(driver.advance()).is_false()
			var prompt: Dictionary = driver.open_prompt()
			if prompt.is_empty():
				var none: Array[int] = []
				driver.submit(EngineAction.commit(0, none))
			else:
				var picked: Array[int] = []
				picked.assign(Choice.options_of(prompt).slice(0, Choice.exact_of(prompt)))
				driver.submit_set(Choice.zone_of(prompt), picked)
		else:
			assert_bool(driver.advance()).is_true()
		calls += 1
	assert_bool(driver.is_over()).is_true()
	assert_array(rejected).is_empty()
	assert_int(batches.size()).is_equal(calls + 1)
	assert_str(driver.result_line()).is_not_empty()


func test_a_refused_submit_emits_action_rejected_and_no_events() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	driver.start()
	var batches: Array[int] = []
	var rejected: Array[int] = []
	driver.events_ready.connect(
		func(events: Array[MatchEvent]) -> void: batches.append(events.size())
	)
	driver.action_rejected.connect(func(code: int) -> void: rejected.append(code))
	driver.submit_choice(Choice.Zone.OWN_HAND, 0)
	assert_array(batches).is_empty()
	assert_int(rejected.size()).is_equal(1)
	assert_int(rejected[0]).is_equal(EngineError.Code.NO_PROMPT)


## A bot-driven seat is not "the player": advance() has nothing to do when the human is awaited.
func test_the_source_reports_the_player_awaited_like_the_view() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	driver.start()
	assert_bool(driver.is_player_awaited()).is_equal(driver.view().is_awaited())
