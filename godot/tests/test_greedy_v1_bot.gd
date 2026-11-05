class_name TestGreedyV1Bot
extends GdUnitTestSuite
## The frozen reference bot `greedy_v1` (cycle 7 T02; R21, R22, R23, plan P3): its choices on
## a fixed suite of (view, seed) fixtures are pinned, it agrees with GreedyBot today, it calls
## nothing of GreedyBot, and the registry builds it by name.
##
## The fixtures: for each match seed 1-12 (the fixture deck on both seats), two GreedyV1Bot
## seats (seeded BotRegistry.seed_for) play from the start up to the first decision of round 1
## turn 3; the fixture is that decision's view for the awaited seat, with that seat's bot
## seed. A thirteenth fixture is a multi-select prompt: test_greedy_bot.gd's sacrifice table
## (seat 0's row [c04, c08, c03, c02], c02 carrying sacrifice_destroy, against [c14, c07];
## both pass and the walk pauses on c02's prompt), decided by seat 0 of match seed 1.
##
## PINS holds GreedyV1Bot's action on each fixture as action_text() renders it. It never
## changes (R21): an API-forced edit to the bot (R22) must leave every pin standing wherever
## the rules still allow the pinned action. While PINS is empty the pin assertion is skipped,
## each fixture is compared with GreedyBot instead (equal at cycle 6's merge), and the suite
## prints one `GreedyV1 pin:` line per fixture, ready to paste into PINS.

## The match seeds the twelve commit fixtures are built from.
const MATCH_SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
## Where each commit fixture is taken: the first decision of this round and turn.
const FIXTURE_ROUND: int = 1
const FIXTURE_TURN: int = 3
## Decisions played to reach a fixture; a bug fails the test instead of hanging the suite.
const MAX_ACTIONS: int = 200
## The set-prompt fixture's match seed and deciding seat.
const SET_SEED: int = 1
const SET_SEAT: int = 0
const SET_LABEL: String = "set_prompt"
const BOT_SOURCE: String = "res://engine/bot/reference/greedy_v1_bot.gd"
## The frozen bot may hold an engine, but only to ask previews for itself (as GreedyBot).
const FORBIDDEN_TOKENS: Array[String] = [
	"MatchState",
	"full_state",
	"_state",
	"view_for",
	"open_prompt",
	"action_log",
	"accepted_actions",
	"apply(",
	"randi(",
	"randf(",
	"randomize(",
	"Time.",
	"OS.",
	"print",
	"push_error",
	"push_warning",
	"assert(",
]

## Fixture deck indices (instance id = seat * 20 + index; tests/fixtures/dc05_cards.json).
const C03: int = 2
const C04: int = 3
const C07: int = 6
const C08: int = 7
const C14: int = 13

## PINS: fixture label ("seed_01".."seed_12", "set_prompt") -> GreedyV1Bot's action as
## action_text() renders it. Pasted by the orchestrator from the `GreedyV1 pin:` lines
## printed by test_pinned_actions after the first gate run; then never edited (R21).
const PINS: Dictionary = {
	"seed_01": "commit s1 c[30] p[0]",
	"seed_02": "commit s1 c[29] p[0]",
	"seed_03": "commit s1 c[] p[]",
	"seed_04": "commit s1 c[22, 25] p[1, 2]",
	"seed_05": "commit s1 c[28] p[2]",
	"seed_06": "commit s1 c[21, 24] p[2, 3]",
	"seed_07": "commit s1 c[25] p[0]",
	"seed_08": "commit s1 c[22, 21] p[0, 1]",
	"seed_09": "commit s1 c[26] p[0]",
	"seed_10": "commit s1 c[30] p[2]",
	"seed_11": "commit s1 c[26] p[0]",
	"seed_12": "commit s0 c[4] p[1]",
	"set_prompt": "choose_set s0 z1 i[0, 2]",
}

var _cached_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


func _label(match_seed: int) -> String:
	return "seed_%02d" % match_seed


## A compact, stable rendering of an action: "commit s<seat> c<cards> p<slots>", "choose
## s<seat> z<zone> i<index>", "choose_set s<seat> z<zone> i<indices>" or "concede s<seat>".
func action_text(action: EngineAction) -> String:
	if action == null:
		return "null"
	if action.kind == EngineAction.Kind.CHOOSE:
		return "choose s%d z%d i%d" % [action.seat, action.zone, action.index]
	if action.kind == EngineAction.Kind.CHOOSE_SET:
		return "choose_set s%d z%d i%s" % [action.seat, action.zone, str(action.indices)]
	if action.kind == EngineAction.Kind.CONCEDE:
		return "concede s%d" % action.seat
	return "commit s%d c%s p%s" % [action.seat, str(action.cards), str(action.slots)]


## A fixture-deck match on `match_seed` played by two GreedyV1Bot seats up to the first
## decision of round FIXTURE_ROUND, turn FIXTURE_TURN; null if it ends, passes that point or
## an action is rejected first.
func _commit_fixture(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	if not engine.start().ok:
		return null
	var bots: Array[GreedyV1Bot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(GreedyV1Bot.new(BotRegistry.seed_for(match_seed, seat), engine.match_cards()))
	for _step: int in range(MAX_ACTIONS):
		if engine.is_over():
			return null
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		if view.round_number == FIXTURE_ROUND and view.turn == FIXTURE_TURN:
			return engine
		if view.round_number > FIXTURE_ROUND:
			return null
		if not engine.apply(bots[seat].choose(view, engine)).ok:
			return null
	return null


## The sacrifice table of test_greedy_bot.gd: seat 0 awaited on c02's multi-select prompt
## over own row positions 0, 1 and 2. Null if the table cannot be played.
func _set_fixture() -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(SET_SEED, FixtureDecks.sacrifice_cards())
	if not engine.start().ok:
		return null
	var own: Array[int] = [C04, C08, C03, FixtureDecks.C02_SACRIFICE]
	var theirs: Array[int] = [MatchRules.DECK_SIZE + C14, MatchRules.DECK_SIZE + C07]
	if not FixtureDecks.play_table(engine, own, theirs):
		return null
	return engine


## Every fixture as [label, engine, bot seed], the twelve commit fixtures then the set
## prompt; a fixture that cannot be built fails the test and is left out.
func _fixtures() -> Array[Array]:
	var out: Array[Array] = []
	for match_seed: int in MATCH_SEEDS:
		var engine: MatchEngine = _commit_fixture(match_seed)
		if engine == null:
			fail("%s: round 1 turn 3 not reached" % _label(match_seed))
			continue
		var bot_seed: int = BotRegistry.seed_for(match_seed, engine.awaited_seat())
		out.append([_label(match_seed), engine, bot_seed])
	var set_engine: MatchEngine = _set_fixture()
	if set_engine == null or set_engine.awaited_seat() != SET_SEAT:
		fail("%s: the sacrifice prompt did not open for seat %d" % [SET_LABEL, SET_SEAT])
	else:
		out.append([SET_LABEL, set_engine, BotRegistry.seed_for(SET_SEED, SET_SEAT)])
	return out


# --- R21: the pins --------------------------------------------------------------------


## Each fixture's action is its pin (skipped while PINS is empty; GreedyBot's action then
## stands in), and the engine accepts it. Prints the `GreedyV1 pin:` line of each fixture.
func test_pinned_actions() -> void:
	var fixtures: Array[Array] = _fixtures()
	assert_int(fixtures.size()).is_equal(MATCH_SEEDS.size() + 1)
	var labels: Array[String] = []
	for fixture: Array in fixtures:
		var label: String = fixture[0]
		var engine: MatchEngine = fixture[1]
		var bot_seed: int = fixture[2]
		labels.append(label)
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		var frozen: GreedyV1Bot = GreedyV1Bot.new(bot_seed, engine.match_cards())
		var action: EngineAction = frozen.choose(view, engine)
		var text: String = action_text(action)
		print('GreedyV1 pin: "%s": "%s",' % [label, text])
		if PINS.is_empty():
			var live: GreedyBot = GreedyBot.new(bot_seed, engine.match_cards())
			var expected: String = action_text(live.choose(view, engine))
			assert_str(text).override_failure_message(label).is_equal(expected)
		else:
			var pinned: String = PINS.get(label, "")
			assert_str(text).override_failure_message(label).is_equal(pinned)
		assert_int(action.seat).override_failure_message(label).is_equal(seat)
		assert_bool(engine.apply(action).ok).override_failure_message(label).is_true()
	if not PINS.is_empty():
		assert_int(PINS.size()).is_equal(labels.size())
		for label: String in labels:
			assert_bool(PINS.has(label)).override_failure_message(label).is_true()


## The set fixture really is a multi-select prompt, answered with a set.
func test_set_fixture_is_answered_with_a_set() -> void:
	var engine: MatchEngine = _set_fixture()
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var view: SeatView = engine.view_for(SET_SEAT)
	assert_bool(Choice.is_multi_prompt(view.prompt)).is_true()
	var bot_seed: int = BotRegistry.seed_for(SET_SEED, SET_SEAT)
	var action: EngineAction = GreedyV1Bot.new(bot_seed, engine.match_cards()).choose(view, engine)
	assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE_SET)


## The commit fixtures sit where P3 says: the first decision of round 1, turn 3.
func test_commit_fixtures_are_at_round_1_turn_3() -> void:
	for match_seed: int in MATCH_SEEDS:
		var engine: MatchEngine = _commit_fixture(match_seed)
		assert_object(engine).override_failure_message(_label(match_seed)).is_not_null()
		if engine == null:
			continue
		var view: SeatView = engine.view_for(engine.awaited_seat())
		assert_int(view.round_number).is_equal(FIXTURE_ROUND)
		assert_int(view.turn).is_equal(FIXTURE_TURN)


# --- The guard: GreedyV1Bot.new and GreedyBot.new agree today --------------------------


## On the twelve commit fixtures GreedyV1Bot.new and GreedyBot.new on the same seed choose
## the same action, both seats. A later, deliberate change to GreedyBot may break this; the
## pins, not this, are what never changes.
func test_agrees_with_greedy_bot_on_the_twelve_fixtures() -> void:
	for match_seed: int in MATCH_SEEDS:
		var engine: MatchEngine = _commit_fixture(match_seed)
		if engine == null:
			fail("%s: round 1 turn 3 not reached" % _label(match_seed))
			continue
		var seat: int = engine.awaited_seat()
		var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
		var view: SeatView = engine.view_for(seat)
		var frozen: EngineAction = GreedyV1Bot.new(bot_seed, engine.match_cards()).choose(
			view, engine
		)
		var live: EngineAction = GreedyBot.new(bot_seed, engine.match_cards()).choose(view, engine)
		assert_dict(frozen.to_dict()).override_failure_message(_label(match_seed)).is_equal(
			live.to_dict()
		)


## The same seed and view give the same action, and choosing changes no state.
func test_the_same_seed_and_view_give_the_same_action() -> void:
	var engine: MatchEngine = _commit_fixture(MATCH_SEEDS[0])
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var seat: int = engine.awaited_seat()
	var view: SeatView = engine.view_for(seat)
	var before: Dictionary = engine.full_state()
	var bot_seed: int = BotRegistry.seed_for(MATCH_SEEDS[0], seat)
	var bot: GreedyV1Bot = GreedyV1Bot.new(bot_seed, engine.match_cards())
	var first: String = action_text(bot.choose(view, engine))
	var second: String = action_text(bot.choose(view, engine))
	assert_str(second).is_equal(first)
	assert_dict(engine.full_state()).is_equal(before)


# --- R21, R22: the frozen source ------------------------------------------------------


func test_bot_name_is_greedy_v1() -> void:
	var bot: GreedyV1Bot = GreedyV1Bot.new(1, FixtureDecks.defs(_db()))
	assert_str(bot.bot_name()).is_equal("greedy_v1")


## The copy is headed FROZEN, reads only its view and its own previews (as GreedyBot), and
## no code line names GreedyBot, so a later change there cannot change it.
func test_source_is_frozen_and_independent_of_greedy_bot() -> void:
	var text: String = FileAccess.get_file_as_string(BOT_SOURCE)
	assert_str(text).is_not_empty()
	assert_str(text).contains("## FROZEN (cycle 7 R21)")
	assert_str(text).contains("class_name GreedyV1Bot")
	for token: String in FORBIDDEN_TOKENS:
		if text.contains(token):
			fail("greedy_v1_bot.gd contains %s" % token)
	for line: String in text.split("\n"):
		var code: String = line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains("GreedyBot"):
			fail("greedy_v1_bot.gd code names GreedyBot: %s" % code)
	assert_str(text).contains("preview(")
	assert_str(text).contains("preview_choice(")
	assert_str(text).contains("preview_set(")
