class_name TestBotRegistry
extends GdUnitTestSuite
## The bot base class and the registry (cycle 7 T01; R1, R2, R5, plan P1, P2): make() builds
## the greedy bot exactly as GreedyBot.new does, refuses an unknown name and a level on a
## bot without an evaluator, seed_for() is GreedyBot's old value, and decision_rng() is the
## documented derivation. Every match here plays the fixture deck on both seats.

const MATCH_SEEDS: Array[int] = [1, 2, 3, 4, 5]
## Decisions compared per match seed; a bug fails the test instead of hanging the suite.
const MAX_ACTIONS: int = 60
## The pre-cycle-7 GreedyBot.SEED_TAG ("bot" in ASCII).
const OLD_SEED_TAG: int = 0x626F74
## A level below full strength, for the bots that take one.
const LOW_LEVEL: int = 3

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


func _make(bot_name: String, bot_seed: int, level: int) -> BotPlayer:
	return BotRegistry.make(bot_name, bot_seed, _defs(), BotWeights.defaults(bot_name), level)


## On seeds 1-5 a registry greedy bot and GreedyBot.new on the same seed choose the same
## action at every decision of the match's opening (both seats, prompts included).
func test_make_greedy_chooses_as_greedy_bot_new() -> void:
	for match_seed: int in MATCH_SEEDS:
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
		assert_bool(engine.start().ok).is_true()
		var direct: Array[GreedyBot] = []
		var made: Array[BotPlayer] = []
		for seat: int in range(MatchEngine.SEATS):
			var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
			direct.append(GreedyBot.new(bot_seed, engine.match_cards()))
			var bot: BotPlayer = BotRegistry.make(
				"greedy", bot_seed, engine.match_cards(), null, BotPlayer.FULL_LEVEL
			)
			assert_object(bot).is_not_null()
			made.append(bot)
		var actions: int = 0
		while not engine.is_over() and actions < MAX_ACTIONS:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			var expected: EngineAction = direct[seat].choose(view, engine)
			var got: EngineAction = made[seat].choose(view, engine)
			assert_dict(got.to_dict()).is_equal(expected.to_dict())
			if not engine.apply(expected).ok:
				fail("seed %d action %d rejected" % [match_seed, actions])
				return
			actions += 1
		assert_int(actions).is_greater(0)


func test_make_greedy_is_a_greedy_bot_at_full_level() -> void:
	var bot: BotPlayer = _make("greedy", 7, BotPlayer.FULL_LEVEL)
	assert_object(bot).is_not_null()
	assert_bool(bot is GreedyBot).is_true()
	assert_str(bot.bot_name()).is_equal("greedy")
	assert_int(bot.level).is_equal(BotPlayer.FULL_LEVEL)
	assert_object(bot.weights).is_not_null()


func test_make_random_is_a_random_bot() -> void:
	var bot: BotPlayer = _make("random", 7, BotPlayer.FULL_LEVEL)
	assert_object(bot).is_not_null()
	assert_bool(bot is RandomBot).is_true()
	assert_str(bot.bot_name()).is_equal("random")


## The frozen reference (T02, R21): `greedy_v1` builds a GreedyV1Bot at full level only.
func test_make_greedy_v1_is_a_greedy_v1_bot_at_full_level_only() -> void:
	var bot: BotPlayer = _make("greedy_v1", 7, BotPlayer.FULL_LEVEL)
	assert_object(bot).is_not_null()
	assert_bool(bot is GreedyV1Bot).is_true()
	assert_bool(bot is GreedyBot).is_false()
	assert_str(bot.bot_name()).is_equal("greedy_v1")
	assert_int(bot.level).is_equal(BotPlayer.FULL_LEVEL)
	assert_object(bot.weights).is_not_null()
	assert_object(_make("greedy_v1", 7, 0)).is_null()
	assert_object(_make("greedy_v1", 7, 19)).is_null()
	assert_object(_make("greedy_v1", 7, 21)).is_null()


func test_make_unknown_name_is_null() -> void:
	assert_object(_make("nope", 1, BotPlayer.FULL_LEVEL)).is_null()
	assert_object(_make("", 1, BotPlayer.FULL_LEVEL)).is_null()
	assert_object(_make("Greedy", 1, BotPlayer.FULL_LEVEL)).is_null()


## A level below full strength on a bot without an evaluator is refused (P2).
func test_make_with_a_level_on_a_bot_without_one_is_null() -> void:
	var weights: BotWeights = BotWeights.defaults("random")
	assert_object(BotRegistry.make("random", 1, _defs(), weights, 5)).is_null()
	assert_object(_make("greedy", 1, 5)).is_null()
	assert_object(_make("greedy", 1, 0)).is_null()
	assert_object(_make("random", 1, 19)).is_null()


func test_make_with_a_level_out_of_range_is_null() -> void:
	assert_object(_make("greedy", 1, 21)).is_null()
	assert_object(_make("greedy", 1, -1)).is_null()


## The weights given are the ones the bot holds; null gives the defaults for the name.
func test_make_keeps_the_given_weights() -> void:
	var weights: BotWeights = BotWeights.defaults("greedy")
	weights.k = 5
	var bot: BotPlayer = BotRegistry.make("greedy", 1, _defs(), weights, BotPlayer.FULL_LEVEL)
	assert_object(bot).is_not_null()
	assert_bool(bot.weights == weights).is_true()
	var plain: BotPlayer = BotRegistry.make("greedy", 1, _defs(), null, BotPlayer.FULL_LEVEL)
	assert_object(plain).is_not_null()
	assert_int(plain.weights.k).is_equal(48)
	assert_str(plain.weights.bot).is_equal("greedy")


func test_names_and_default_name() -> void:
	var expected: Array[String] = ["greedy", "greedy_v1", "random", "tuned", "matrix"]
	assert_array(BotRegistry.NAMES).is_equal(expected)
	assert_bool(BotRegistry.NAMES.has(BotRegistry.default_name())).is_true()
	assert_str(BotRegistry.default_name()).is_equal("tuned")
	var bot: BotPlayer = _make(BotRegistry.default_name(), 1, BotPlayer.FULL_LEVEL)
	assert_object(bot).is_not_null()
	assert_bool(bot is TunedBot).is_true()


## The tuned bot (T04, R13): built at every level 0..20 with the weights given; with none,
## the shipped file's (no load error); refused outside 0..20.
func test_make_tuned_is_a_tuned_bot_at_levels_0_and_20() -> void:
	for level: int in [0, LOW_LEVEL, BotPlayer.FULL_LEVEL]:
		var bot: BotPlayer = _make("tuned", 7, level)
		assert_object(bot).is_not_null()
		assert_bool(bot is TunedBot).is_true()
		assert_str(bot.bot_name()).is_equal("tuned")
		assert_int(bot.level).is_equal(level)
		assert_str(bot.weights.bot).is_equal("tuned")
	var shipped: BotPlayer = BotRegistry.make("tuned", 7, _defs(), null, 0)
	assert_object(shipped).is_not_null()
	assert_str(shipped.weights.load_error).is_equal("")
	assert_str(shipped.weights.stamp).is_not_empty()
	assert_object(_make("tuned", 7, 21)).is_null()
	assert_object(_make("tuned", 7, -1)).is_null()


## default_weights(): the defaults for a bot without an evaluator, the shipped file for one
## with an evaluator.
func test_default_weights_by_name() -> void:
	var plain: BotWeights = BotRegistry.default_weights("greedy")
	assert_str(plain.bot).is_equal("greedy")
	assert_dict(plain.weights).is_equal({"score_diff": 100})
	var tuned: BotWeights = BotRegistry.default_weights("tuned")
	var shipped: BotWeights = BotWeights.load(BotRegistry.default_weights_path("tuned"))
	assert_str(tuned.load_error).is_equal("")
	assert_str(tuned.to_json()).is_equal(shipped.to_json())


func test_seed_for_equals_greedy_bot_seed_for() -> void:
	for match_seed: int in range(1, 51):
		for seat: int in range(MatchEngine.SEATS):
			var parts: Array[int] = [OLD_SEED_TAG, seat]
			var old: int = MatchRng.derive_seed(match_seed, parts)
			assert_int(BotRegistry.seed_for(match_seed, seat)).is_equal(old)
			assert_int(GreedyBot.seed_for(match_seed, seat)).is_equal(old)


func test_default_weights_path() -> void:
	assert_str(BotRegistry.default_weights_path("tuned")).is_equal(
		"res://engine/bot/data/tuned_weights.json"
	)
	assert_str(BotRegistry.default_weights_path("matrix")).is_equal(
		"res://engine/bot/data/matrix_weights.json"
	)


func test_weights_defaults() -> void:
	var weights: BotWeights = BotWeights.defaults("tuned")
	assert_str(weights.bot).is_equal("tuned")
	assert_int(weights.k).is_equal(48)
	assert_int(weights.k_opp).is_equal(12)
	assert_int(weights.samples).is_equal(4)
	assert_int(weights.rm_iterations).is_equal(200)
	assert_int(weights.push_unit).is_equal(10)
	assert_dict(weights.weights).is_equal({"score_diff": 100})
	assert_str(weights.stamp).is_equal("")
	assert_str(weights.load_error).is_equal("")


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
	assert_int(bot.level).is_equal(BotPlayer.FULL_LEVEL)
