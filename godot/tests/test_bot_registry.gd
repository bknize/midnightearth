class_name TestBotRegistry
extends GdUnitTestSuite
## The bot base class and the registry (cycle 7 R1, R2, R5; cycle 9 R70, R73, P16): make()
## builds the random bot and (cycle 13 R5) the linear bot, the default is still `random`,
## seed_for() keeps its cycle-7 value, and decision_rng() is the documented derivation.

## The pre-cycle-7 seed tag ("bot" in ASCII).
const OLD_SEED_TAG: int = 0x626F74

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func test_make_random_is_a_random_bot() -> void:
	var bot: BotPlayer = BotRegistry.make("random", 7, _defs())
	assert_object(bot).is_not_null()
	assert_bool(bot is RandomBot).is_true()
	assert_str(bot.bot_name()).is_equal("random")


## Cycle 13 R5, R8, P4: `linear` is a LinearBot on the committed file (make) or a named
## path (make_with); `random` ignores a path; weights_error is "" for a sound file and for
## `random`, the file's load_error for a missing one.
func test_make_linear_is_a_linear_bot_on_the_committed_file() -> void:
	var bot: BotPlayer = BotRegistry.make("linear", 7, _defs())
	assert_bool(bot is LinearBot).is_true()
	assert_str(bot.bot_name()).is_equal("linear")
	var linear: LinearBot = bot as LinearBot
	assert_str(linear.weights().load_error).is_equal("")
	var missing: String = "res://engine/bot/data/no_such_weights.json"
	var fallback: BotPlayer = BotRegistry.make_with("linear", 7, _defs(), missing)
	assert_bool(fallback is LinearBot).is_true()
	assert_str(BotRegistry.weights_error("linear", "")).is_equal("")
	assert_str(BotRegistry.weights_error("linear", missing)).contains("not found")
	assert_str(BotRegistry.weights_error("random", missing)).is_equal("")
	assert_bool(BotRegistry.make_with("random", 7, _defs(), missing) is RandomBot).is_true()


## Every removed bot (R71) and any other unknown name is null.
func test_make_unknown_name_is_null() -> void:
	for unknown: String in ["tuned", "greedy", "greedy_v1", "matrix", "nope", "", "Random"]:
		assert_object(BotRegistry.make(unknown, 1, _defs())).is_null()


func test_names_and_default_name() -> void:
	var expected: Array[String] = ["random", "linear"]
	assert_array(BotRegistry.NAMES).is_equal(expected)
	assert_str(BotRegistry.default_name()).is_equal("random")
	var bot: BotPlayer = BotRegistry.make(BotRegistry.default_name(), 1, _defs())
	assert_object(bot).is_not_null()
	assert_bool(bot is RandomBot).is_true()


func test_seed_for_keeps_its_cycle_7_value() -> void:
	for match_seed: int in range(1, 51):
		for seat: int in range(MatchEngine.SEATS):
			var parts: Array[int] = [OLD_SEED_TAG, seat]
			var old: int = MatchRng.derive_seed(match_seed, parts)
			assert_int(BotRegistry.seed_for(match_seed, seat)).is_equal(old)


## decision_rng(view, tag, extra) is seeded derive_seed(bot_seed, [round, turn, tag] + extra),
## so it repeats for one view and differs by tag and by extra.
func test_decision_rng_is_the_documented_derivation() -> void:
	var engine: MatchEngine = FixtureDecks.engine(3, _db())
	assert_bool(engine.start().ok).is_true()
	var view: SeatView = engine.view_for(engine.awaited_seat())
	var bot: BotPlayer = BotPlayer.new(11, _defs())
	var extra: Array[int] = [42]
	var parts: Array[int] = [view.round_number, view.turn, 9, 42]
	var expected: MatchRng = MatchRng.new(MatchRng.derive_seed(11, parts))
	assert_int(bot.decision_rng(view, 9, extra).state).is_equal(expected.state)
	var plain: Array[int] = [view.round_number, view.turn, 9]
	var expected_plain: MatchRng = MatchRng.new(MatchRng.derive_seed(11, plain))
	assert_int(bot.decision_rng(view, 9).state).is_equal(expected_plain.state)
	assert_int(bot.decision_rng(view, 9).state).is_equal(bot.decision_rng(view, 9).state)
	assert_int(bot.decision_rng(view, 9).state).is_not_equal(bot.decision_rng(view, 10).state)


## The base bot has no policy: it returns null and its name is empty.
func test_base_bot_has_no_policy() -> void:
	var engine: MatchEngine = FixtureDecks.engine(1, _db())
	assert_bool(engine.start().ok).is_true()
	var bot: BotPlayer = BotPlayer.new(1, null)
	assert_object(bot.choose(engine.view_for(engine.awaited_seat()), engine)).is_null()
	assert_str(bot.bot_name()).is_equal("")
