class_name TestMatchDriver
extends GdUnitTestSuite
## MatchDriver (R2, R5, R6, C11): the seed-1 autoplay match through the driver equals the
## smoke match and prints the board's result line, seat 0 never sees a seat-1 card id, a
## seat-0 concede ends the match with reason "concede", and bot turns are due exactly when
## the human is not awaited. DC-05 T07: play_bot() answers a bot's prompt, and seat 0's
## prompt is read with open_prompt() and answered with submit_choice(). DC-07 T02 (P14):
## the driver takes the pool, the deck list and a deck id per seat (the fixture deck on
## both seats here), resolves an empty id to the seed's pick, and the result line names
## both decks right after the seed.

const SEED: int = 1
const MAX_ACTIONS: int = 2000
## Seeds tried, in order (1 first), until the prompt a case needs turns up.
const PROMPT_SEEDS: int = 10
## An index no prompt offers (options are positions in a zone of at most a few cards).
const NOT_AN_OPTION: int = 99
## Sentinel line meaning "not pinned yet".
const LINE_UNPINNED: String = ""
## Seed 1's pinned board result line, re-pinned at DC-07 T13 with `decks=<a>/<b>` after
## the seed (P14), from the shipped pool and deck list under seed 1's own pairing, as the
## board plays it (headless `--fixed-fps 60 --autoplay` prints the same line);
## the DC-06 T09 line (rules version 3) was "Board: match ended seed=1 winner=0 wins=4-3
## rounds=7 end=wins actions=120", the DC-05 line "... wins=4-2 rounds=6 ... actions=114".
## While it is LINE_UNPINNED the pinned-line test is skipped with LINE_SKIP_NOTE; the
## autoplay test still compares against a direct bot-vs-bot engine run.
## DC-08 T07 (R5): the line gains `bot=<name>` after the decks and the greedy bot is
## unchanged, so this pin is built with "greedy" explicitly. The pre-bot literal was
## "Board: match ended seed=1 decks=ruin/ruin winner=1 wins=1-4 rounds=5 end=wins actions=88".
## DC-09 T04 (cycle 8 R10, R30): the pool and list gain Bloom and Echo, so seed 1's seeded
## pairing draws from four decks and both pins are emptied until the orchestrator re-pins
## them at T07. The DC-08 lines were "Board: match ended seed=1 decks=ruin/ruin bot=greedy
## winner=1 wins=1-4 rounds=5 end=wins actions=88" (EXPECTED_LINE) and the same with
## `bot=tuned` (GOLDEN_TUNED).
## Re-pinned at DC-09 T07 (headless --fixed-fps 60 autoplay agrees, greedy and tuned alike).
const EXPECTED_LINE: String = (
	"Board: match ended seed=1 decks=bloom/ruin bot=greedy winner=0 wins=4-0 rounds=4 end=wins"
	+ " actions=72"
)
## Seed 1's result line under the default bot (tuned, level 20, k 24); pinned at DC-08 T11,
## moved at DC-11 T10 (live Crew: actions 64 -> 72, same result: "Board: match ended seed=1
## decks=bloom/ruin bot=tuned winner=0 wins=4-0 rounds=4 end=wins actions=72"). Emptied at
## DC-11 T11 (the tuned bot may decline an optional Crew prompt and answers Shade by rule,
## cycle 8 R56, R57); re-pinned at DC-11 T14.
## While empty the test prints the line and checks only `bot=tuned`.
const GOLDEN_TUNED: String = (
	"Board: match ended seed=1 decks=bloom/ruin bot=tuned winner=0 wins=4-0 rounds=4 end=wins"
	+ " actions=74"
)
## The bot the helpers build: the greedy bot, whose play the goldens pin (R5).
const GREEDY: String = "greedy"
const FULL_LEVEL: int = 20
const LINE_SKIP_NOTE: String = (
	"unpinned at DC-09 T04 (Bloom and Echo shipped, four-deck pairing): pin EXPECTED_LINE"
	+ " from seed 1's greedy 'Board: match ended' line"
)
## Event kinds whose card ids are private to their owner.
const PRIVATE_KINDS: Array[int] = [
	MatchEvent.Kind.CARD_DEALT,
	MatchEvent.Kind.CARD_DRAWN,
	MatchEvent.Kind.CARD_BURNED,
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
		GREEDY,
		FULL_LEVEL,
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
## A public burn is skipped: since DC-05 T05 a card returned to a full hand burns in public,
## having been face up on its row.
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
	var bots: Array[GreedyBot] = [
		GreedyBot.new(GreedyBot.seed_for(SEED, 0), _defs()),
		GreedyBot.new(GreedyBot.seed_for(SEED, 1), _defs()),
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
		% [SEED, decks[0], decks[1], GREEDY, winner, wins[0], wins[1], rounds, reason, actions]
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


## A human-seat driver for `match_seed`, started and played until a prompt opens for seat 0
## (or the match ends, or the cap): seat 1 by play_bot(), seat 0 by submit_player() with
## the commit a GreedyBot of its own would choose. Null when a step was rejected.
func _drive_to_player_prompt(match_seed: int) -> MatchDriver:
	var driver: MatchDriver = _driver(match_seed, false)
	driver.start()
	var bot: GreedyBot = GreedyBot.new(GreedyBot.seed_for(match_seed, 0), _defs())
	var steps: int = 0
	while not driver.is_over() and steps < MAX_ACTIONS:
		if not driver.open_prompt().is_empty():
			return driver
		var result: ApplyResult = null
		if driver.bot_turn_due():
			result = driver.play_bot()
		else:
			result = driver.submit_player(bot.choose(driver.view(), driver._engine))
		if not result.ok:
			return null
		steps += 1
	return driver


# --- Tests ----------------------------------------------------------------------------


func test_seed_1_autoplay_equals_the_smoke_match() -> void:
	var driver: MatchDriver = _driver(SEED, true)
	assert_bool(driver.autoplay).is_true()
	assert_int(driver.match_seed).is_equal(SEED)
	assert_str(driver.result_line()).is_empty()
	var leaks: Array[String] = _opponent_leaks(driver.start())
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


## The seed-1 autoplay line equals the pinned EXPECTED_LINE. Skipped, with LINE_SKIP_NOTE
## as the reason, until the orchestrator pins it at DC-06 T09.
func test_seed_1_autoplay_prints_the_pinned_line(
	_do_skip: bool = EXPECTED_LINE == LINE_UNPINNED, _skip_reason: String = LINE_SKIP_NOTE
) -> void:
	# The board's own match: the shipped pool and list, seed 1's seeded pairing.
	var seeded: Array[String] = ["", ""]
	var driver: MatchDriver = MatchDriver.create(
		SEED,
		CardDb.load_default(),
		DeckList.load_default(),
		seeded,
		true,
		GREEDY,
		FULL_LEVEL,
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
	var head: String = "Board: match ended seed=%d decks=fixture/fixture bot=greedy winner=" % SEED
	assert_bool(line.begins_with(head)).override_failure_message(line).is_true()
	var seeded: Array[String] = ["", ""]
	var decks: DeckList = FixtureDecks.decks()
	var picked: MatchDriver = MatchDriver.create(
		7, _db(), decks, seeded, true, GREEDY, FULL_LEVEL, FixtureDecks.crew()
	)
	var expected: Array[String] = [decks.seeded_pick(7, 0), decks.seeded_pick(7, 1)]
	assert_array(picked.deck_ids()).is_equal(expected)
	assert_bool(picked.start().is_empty()).is_false()
	var unknown: Array[String] = ["fixture", "nope"]
	var refused: MatchDriver = MatchDriver.create(
		SEED, _db(), decks, unknown, true, GREEDY, FULL_LEVEL, FixtureDecks.crew()
	)
	assert_array(refused.start()).is_empty()


func test_seat_0_concede_ends_the_match_with_concede() -> void:
	var driver: MatchDriver = _driver(SEED, false)
	var started: Array[MatchEvent] = driver.start()
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
	var steps: int = 0
	while not driver.is_over() and steps < 100:
		var awaited: int = driver.view().awaited_seat
		assert_bool(driver.bot_turn_due()).is_equal(awaited != 0)
		var result: ApplyResult = null
		if driver.bot_turn_due():
			result = driver.play_bot()
			bot_moves += 1
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
## while seat 1 is prompted, set while seat 0 is. Stops at the first answered prompt.
func test_play_bot_answers_a_bot_prompt() -> void:
	var answered: int = 0
	for match_seed: int in range(1, PROMPT_SEEDS + 1):
		var driver: MatchDriver = _driver(match_seed, true)
		driver.start()
		var steps: int = 0
		while driver.bot_turn_due() and steps < MAX_ACTIONS:
			var prompted: int = _prompted_seat(driver)
			if prompted == 1:
				assert_dict(driver.open_prompt()).is_empty()
			elif prompted == 0:
				assert_bool(driver.open_prompt().is_empty()).is_false()
			var result: ApplyResult = driver.play_bot()
			var where: String = "seed %d action %d" % [match_seed, steps]
			assert_bool(result.ok).override_failure_message(where + " rejected").is_true()
			if not result.ok:
				return
			if prompted >= 0:
				answered += 1
				var made: bool = _has_kind(driver.last_events(), MatchEvent.Kind.CHOICE_MADE)
				assert_bool(made).override_failure_message(where + ": no CHOICE_MADE").is_true()
			steps += 1
			if answered > 0:
				break
		if answered > 0:
			break
	assert_int(answered).override_failure_message("no bot prompt in the seeds").is_greater(0)


## Seat 0's prompt (DC-05 T07): with no prompt open submit_choice() fails with NO_PROMPT;
## once one opens, open_prompt() gives its zone and options, an option it does not offer
## fails with NOT_ELIGIBLE and changes nothing, and an offered option is accepted.
func test_submit_choice_answers_the_open_player_prompt() -> void:
	var idle: MatchDriver = _driver(SEED, false)
	idle.start()
	assert_dict(idle.open_prompt()).is_empty()
	var early: ApplyResult = idle.submit_choice(Choice.Zone.OWN_HAND, 0)
	assert_bool(early.ok).is_false()
	assert_int(early.error).is_equal(EngineError.Code.NO_PROMPT)
	var driver: MatchDriver = null
	for match_seed: int in range(1, PROMPT_SEEDS + 1):
		var candidate: MatchDriver = _drive_to_player_prompt(match_seed)
		var rejected: String = "seed %d: a step was rejected" % match_seed
		assert_bool(candidate != null).override_failure_message(rejected).is_true()
		if candidate != null and not candidate.open_prompt().is_empty():
			driver = candidate
			break
	assert_object(driver).override_failure_message("no seat-0 prompt in the seeds").is_not_null()
	if driver == null:
		return
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
	var refused: ApplyResult = driver.submit_choice(zone, NOT_AN_OPTION)
	assert_bool(refused.ok).is_false()
	assert_int(refused.error).is_equal(EngineError.Code.NOT_ELIGIBLE)
	assert_int(driver.action_count()).is_equal(count)
	assert_dict(driver.open_prompt()).is_equal(prompt)
	var answered: ApplyResult = driver.submit_choice(zone, options[0])
	assert_bool(answered.ok).is_true()
	assert_int(driver.action_count()).is_equal(count + 1)
	var made: bool = _has_kind(driver.last_events(), MatchEvent.Kind.CHOICE_MADE)
	assert_bool(made).override_failure_message("no CHOICE_MADE for seat 0").is_true()


## DC-07 T05 (P7): submit_set() reaches the engine. With c02 given sacrifice_destroy and
## seat 0's row [c04, c08, c02] set by hand, open_prompt() says `multi`, a set naming the
## source fails with BAD_SET, and a valid set is accepted with CHOICE_MADE `indices`.
func test_submit_set_answers_the_open_multi_prompt() -> void:
	var driver: MatchDriver = MatchDriver.create(
		SEED,
		FixtureDecks.sacrifice_cards(),
		FixtureDecks.decks(),
		FixtureDecks.ids(),
		false,
		GREEDY,
		FULL_LEVEL,
		FixtureDecks.crew()
	)
	driver.start()
	var own: Array[int] = [3, 7, FixtureDecks.C02_SACRIFICE]
	var none: Array[int] = []
	assert_bool(FixtureDecks.play_table(driver._engine, own, none)).is_true()
	var prompt: Dictionary = driver.open_prompt()
	var multi: bool = prompt.get(Choice.KEY_MULTI, false)
	assert_bool(multi).is_true()
	var count: int = driver.action_count()
	var bad: Array[int] = [2]
	var refused: ApplyResult = driver.submit_set(Choice.Zone.OWN_BOARD, bad)
	assert_int(refused.error).is_equal(EngineError.Code.BAD_SET)
	var chosen: Array[int] = [1]
	var result: ApplyResult = driver.submit_set(Choice.Zone.OWN_BOARD, chosen)
	assert_bool(result.ok).is_true()
	assert_int(driver.action_count()).is_equal(count + 1)
	var indices: Array = []
	for event: MatchEvent in driver.last_events():
		if event.kind == MatchEvent.Kind.CHOICE_MADE:
			indices = event.payload["indices"]
	assert_array(indices).is_equal([1])


## DC-08 T07 (R4): the default bot is tuned at level 20. Seed 1 autoplays on the shipped pool
## under it and the result line carries `bot=tuned`; the line is printed for pinning and
## compared with GOLDEN_TUNED once that is set.
func test_default_bot_is_tuned_and_named_in_the_result_line() -> void:
	assert_str(BotRegistry.default_name()).is_equal("tuned")
	var seeded: Array[String] = ["", ""]
	var driver: MatchDriver = MatchDriver.create(
		SEED,
		CardDb.load_default(),
		DeckList.load_default(),
		seeded,
		true,
		BotRegistry.default_name(),
		FULL_LEVEL,
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
	print("TUNED_LINE %s" % line)
	assert_bool(line.contains(" bot=tuned ")).override_failure_message(line).is_true()
	if GOLDEN_TUNED != "":
		assert_str(line).is_equal(GOLDEN_TUNED)


## DC-08 T07 (R4, R16): the random bot takes only the full level; a lower level makes create
## return null, and level 20 builds a driver whose bots play.
func test_create_with_random_accepts_only_the_full_level() -> void:
	var full: MatchDriver = MatchDriver.create(
		SEED,
		_db(),
		FixtureDecks.decks(),
		FixtureDecks.ids(),
		true,
		"random",
		FULL_LEVEL,
		FixtureDecks.crew()
	)
	assert_object(full).is_not_null()
	if full != null:
		assert_bool(full.start().is_empty()).is_false()
		assert_bool(full.bot_turn_due()).is_true()
	var low: MatchDriver = MatchDriver.create(
		SEED,
		_db(),
		FixtureDecks.decks(),
		FixtureDecks.ids(),
		true,
		"random",
		5,
		FixtureDecks.crew()
	)
	assert_object(low).is_null()
	var unknown: MatchDriver = MatchDriver.create(
		SEED,
		_db(),
		FixtureDecks.decks(),
		FixtureDecks.ids(),
		true,
		"nope",
		FULL_LEVEL,
		FixtureDecks.crew()
	)
	assert_object(unknown).is_null()
