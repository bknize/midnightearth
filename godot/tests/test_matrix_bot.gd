class_name TestMatrixBot
extends GdUnitTestSuite
## The matrix bot (cycle 7 DC-10 T13; R50-R53, plan P11-P14). As the second committer every
## opponent hypothesis it previews has the observed count and slots (R53); it asks the engine
## for nothing but previews; the engine accepts every action over 50 seeds; the same seed and
## view give the same action; a commit decision costs at most k · k_opp joint previews (plus
## at most k plain previews on the fallback); and when preview_pair refuses every
## hypothesis it commits as the tuned bot does.
##
## Matches play the four shipped decks under seeded pairings. To keep the suite inside its
## gdUnit budget, the bots use small caps (SMALL_K, SMALL_K_OPP, SMALL_SAMPLES,
## SMALL_ITERATIONS) and the 50 seeds play only their first DECISIONS_PER_SEED decisions.

const SEEDS: int = 50
const DECISIONS_PER_SEED: int = 4
const SECOND_SEEDS: int = 12
const FALLBACK_SEEDS: int = 5
const REPEAT_SEEDS: int = 5
const SMALL_K: int = 4
const SMALL_K_OPP: int = 4
const SMALL_SAMPLES: int = 2
const SMALL_ITERATIONS: int = 50
const LOW_LEVEL: int = 3
const BOT_SOURCE: String = "res://engine/bot/matrix_bot.gd"
## What the bot's own source may call on its engine (R2); the rest it inherits from TunedBot.
const ALLOWED_CALLS: Array[String] = ["preview", "preview_choice", "preview_set", "preview_pair"]
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

var _pool: CardDb = null
var _decks: DeckList = null


func _engine(match_seed: int) -> PairEngine:
	if _pool == null:
		_pool = CardDb.load_default()
		_decks = DeckList.load_default()
	var seeded: Array[String] = ["", ""]
	var real: MatchEngine = MatchEngine.create(match_seed, _pool, _decks, seeded)
	var engine: PairEngine = PairEngine.wrap(real)
	assert_bool(engine.start().ok).is_true()
	return engine


func _small_weights() -> BotWeights:
	var weights: BotWeights = BotWeights.defaults("matrix")
	weights.k = SMALL_K
	weights.k_opp = SMALL_K_OPP
	weights.samples = SMALL_SAMPLES
	weights.rm_iterations = SMALL_ITERATIONS
	return weights


func _matrix(bot_seed: int, cards: MatchCards, level: int) -> MatrixBot:
	var bot: MatrixBot = MatrixBot.new(bot_seed, cards)
	bot.weights = _small_weights()
	bot.level = level
	return bot


func _is_commit_view(view: SeatView) -> bool:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	return not (open and asked == view.seat)


func _keys(listed: Array[EngineAction]) -> Array[String]:
	var out: Array[String] = []
	for action: EngineAction in listed:
		out.append(CandidateGen.key_of(action))
	return out


## Commits the first committer's turn-1 play with a small tuned bot, leaving the second seat
## awaited; returns that seat.
func _commit_first(engine: PairEngine, match_seed: int) -> int:
	var first: int = engine.awaited_seat()
	var tuned: TunedBot = TunedBot.new(
		BotRegistry.seed_for(match_seed, first), engine.match_cards()
	)
	tuned.weights = _small_weights()
	var action: EngineAction = tuned.choose(engine.view_for(first), engine)
	assert_bool(engine.apply(action).ok).is_true()
	return engine.awaited_seat()


# --- R53: the second committer's hypotheses ---------------------------------------------


## R53: after the first committer's play, every hypothesis the matrix bot hands preview_pair
## has the observed face-down count and slots, and the engine accepts its answer.
func test_second_committer_hypotheses_have_the_observed_count_and_slots() -> void:
	var recorded: int = 0
	var counted: int = 0
	for match_seed: int in range(1, SECOND_SEEDS + 1):
		var engine: PairEngine = _engine(match_seed)
		var seat: int = _commit_first(engine, match_seed)
		var view: SeatView = engine.view_for(seat)
		if not _is_commit_view(view):
			continue
		assert_bool(MatrixBot.opponent_committed(view)).is_true()
		var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
		var bot: MatrixBot = _matrix(bot_seed, engine.match_cards(), BotPlayer.FULL_LEVEL)
		engine.watching = true
		var action: EngineAction = bot.choose(view, engine)
		engine.watching = false
		for opp: EngineAction in engine.opp_hypotheses:
			assert_int(opp.seat).is_equal(view.opponent)
			assert_int(opp.cards.size()).is_equal(view.opponent_pending_count)
			assert_array(opp.slots).is_equal(view.opponent_pending_slots)
		recorded += engine.opp_hypotheses.size()
		if view.opponent_pending_count > 0:
			counted += 1
		for opp: EngineAction in bot.opponent_candidates(view):
			assert_bool(MatrixBot.matches_observed(view, opp)).is_true()
		assert_bool(engine.apply(action).ok).is_true()
	assert_int(recorded).is_greater(0)
	assert_int(counted).is_greater(0)


# --- R2, R3: the engine accepts every action; only previews are asked --------------------


## R3, R2 over 50 seeds: a matrix bot at level 20 (seat 0) and one at level 3 (seat 1) play
## each match's first DECISIONS_PER_SEED decisions; the engine accepts every action, a
## commit is one of the bot's own candidates, the bot calls nothing on the engine but the
## previews, and a commit decision costs at most k · k_opp joint previews (and at most k
## plain previews, only on the fallback); a prompt costs at most its options plus one.
func test_every_action_over_50_seeds_is_accepted() -> void:
	var levels: Array[int] = [BotPlayer.FULL_LEVEL, LOW_LEVEL]
	var pairs: int = 0
	for match_seed: int in range(1, SEEDS + 1):
		var engine: PairEngine = _engine(match_seed)
		var bots: Array[MatrixBot] = []
		for seat: int in range(MatchEngine.SEATS):
			var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
			bots.append(_matrix(bot_seed, engine.match_cards(), levels[seat]))
		var actions: int = 0
		while not engine.is_over() and actions < DECISIONS_PER_SEED:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			engine.reset_counts()
			engine.watching = true
			var action: EngineAction = bots[seat].choose(view, engine)
			engine.watching = false
			assert_int(action.seat).is_equal(seat)
			assert_int(engine.other_calls).is_equal(0)
			if _is_commit_view(view):
				assert_int(engine.pair_previews).is_less_equal(SMALL_K * SMALL_K_OPP)
				assert_int(engine.commit_previews).is_less_equal(SMALL_K)
				assert_int(engine.choice_previews + engine.set_previews).is_equal(0)
				var own: Array[String] = _keys(bots[seat].candidates(view))
				if engine.commit_previews == 0:
					assert_bool(own.has(CandidateGen.key_of(action))).is_true()
			else:
				var options: int = Choice.options_of(view.prompt).size()
				assert_int(engine.pair_previews + engine.commit_previews).is_equal(0)
				assert_int(engine.choice_previews + engine.set_previews).is_less_equal(options + 1)
			pairs += engine.pair_previews
			var result: ApplyResult = engine.apply(action)
			if not result.ok:
				fail(
					(
						"seed %d action %d rejected (error %d): %s"
						% [match_seed, actions, result.error, str(action.to_dict())]
					)
				)
				return
			actions += 1
	assert_int(pairs).is_greater(0)


## R2: the source reads only its view and calls nothing on its engine but previews.
func test_source_asks_only_previews() -> void:
	var text: String = FileAccess.get_file_as_string(BOT_SOURCE)
	assert_str(text).is_not_empty()
	for token: String in FORBIDDEN_TOKENS:
		if text.contains(token):
			fail("matrix_bot.gd contains %s" % token)
	var calls: RegEx = RegEx.create_from_string("engine\\.([A-Za-z_]+)\\(")
	var named: Dictionary[String, bool] = {}
	for found: RegExMatch in calls.search_all(text):
		var called: String = found.get_string(1)
		named[called] = true
		assert_bool(ALLOWED_CALLS.has(called)).override_failure_message(called).is_true()
	assert_bool(named.has("preview_pair")).is_true()


# --- Determinism --------------------------------------------------------------------------


## The same seed and view give the same action: twice from one bot, and from a second bot
## built on the same seed, at level 20 and at level 3, for both seats' first decisions.
func test_same_seed_and_view_same_action() -> void:
	for level: int in [BotPlayer.FULL_LEVEL, LOW_LEVEL]:
		for match_seed: int in range(1, REPEAT_SEEDS + 1):
			var engine: PairEngine = _engine(match_seed)
			for _step: int in range(MatchEngine.SEATS):
				var seat: int = engine.awaited_seat()
				var view: SeatView = engine.view_for(seat)
				var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
				var bot: MatrixBot = _matrix(bot_seed, engine.match_cards(), level)
				var first: EngineAction = bot.choose(view, engine)
				var again: EngineAction = bot.choose(view, engine)
				var twin: EngineAction = _matrix(bot_seed, engine.match_cards(), level).choose(
					view, engine
				)
				assert_dict(again.to_dict()).is_equal(first.to_dict())
				assert_dict(twin.to_dict()).is_equal(first.to_dict())
				assert_bool(engine.apply(first).ok).is_true()


# --- The fallback --------------------------------------------------------------------------


## When preview_pair refuses every hypothesis (as it may for a real commit that used a
## free-first grant, a hidden cost cut or a recovered card), the bot commits exactly as a
## tuned bot on the same seed and weights does, and the engine accepts it; as the first and
## as the second committer.
func test_every_hypothesis_refused_falls_back_to_the_tuned_commit() -> void:
	for match_seed: int in range(1, FALLBACK_SEEDS + 1):
		var engine: PairEngine = _engine(match_seed)
		engine.refuse_pairs = true
		for step: int in range(MatchEngine.SEATS):
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			if not _is_commit_view(view):
				break
			var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
			var bot: MatrixBot = _matrix(bot_seed, engine.match_cards(), BotPlayer.FULL_LEVEL)
			var tuned: TunedBot = TunedBot.new(bot_seed, engine.match_cards())
			tuned.weights = _small_weights()
			engine.reset_counts()
			engine.watching = true
			var action: EngineAction = bot.choose(view, engine)
			engine.watching = false
			var expected: EngineAction = tuned.choose(view, engine)
			assert_dict(action.to_dict()).is_equal(expected.to_dict())
			if step == 0:
				assert_int(engine.pair_previews).is_greater(0)
			assert_int(engine.pair_previews).is_less_equal(SMALL_K * SMALL_K_OPP)
			assert_int(engine.commit_previews).is_equal(bot.candidates(view).size())
			assert_bool(engine.apply(action).ok).is_true()


## With no engine every joint preview is [0, 0]: the bot still returns one of its own
## candidates.
func test_null_engine_returns_an_own_candidate() -> void:
	var engine: PairEngine = _engine(2)
	var seat: int = engine.awaited_seat()
	var view: SeatView = engine.view_for(seat)
	var bot: MatrixBot = _matrix(9, engine.match_cards(), BotPlayer.FULL_LEVEL)
	var action: EngineAction = bot.choose(view, null)
	assert_bool(_keys(bot.candidates(view)).has(CandidateGen.key_of(action))).is_true()
	assert_bool(engine.apply(action).ok).is_true()


# --- The registry and the shipped weights -------------------------------------------------


func test_registry_builds_the_matrix_bot_on_its_shipped_weights() -> void:
	var engine: PairEngine = _engine(1)
	for level: int in [0, LOW_LEVEL, BotPlayer.FULL_LEVEL]:
		var bot: BotPlayer = BotRegistry.make("matrix", 7, engine.match_cards(), null, level)
		assert_object(bot).is_not_null()
		assert_bool(bot is MatrixBot).is_true()
		assert_str(bot.bot_name()).is_equal("matrix")
		assert_int(bot.level).is_equal(level)
		assert_str(bot.weights.load_error).is_equal("")
		assert_str(bot.weights.bot).is_equal("matrix")
		assert_str(bot.weights.stamp).is_not_empty()
		assert_int(bot.weights.k).is_equal(12)
		assert_int(bot.weights.k_opp).is_equal(12)
		assert_int(bot.weights.samples).is_equal(4)
		assert_int(bot.weights.rm_iterations).is_equal(200)
	assert_bool(BotRegistry.PENDING.has("matrix")).is_false()
	assert_object(BotRegistry.make("matrix", 7, engine.match_cards(), null, 21)).is_null()


## A MatchEngine that counts, while `watching`, the previews it is asked for (recording each
## joint preview's hypothesis) and every other public call made from outside a preview. With
## `refuse_pairs` every joint preview answers [] (counted and recorded all the same).
class PairEngine:
	extends MatchEngine

	var watching: bool = false
	var refuse_pairs: bool = false
	var commit_previews: int = 0
	var choice_previews: int = 0
	var set_previews: int = 0
	var pair_previews: int = 0
	var other_calls: int = 0
	var opp_hypotheses: Array[EngineAction] = []
	var _inside: int = 0

	## `real` (not started) as a counting engine: the same seed, state and cards.
	static func wrap(real: MatchEngine) -> PairEngine:
		var out: PairEngine = PairEngine.new()
		out._rng = real._rng
		out._state = real._state
		out._cards = real._cards
		out._setup_error = real._setup_error
		return out

	func reset_counts() -> void:
		commit_previews = 0
		choice_previews = 0
		set_previews = 0
		pair_previews = 0
		other_calls = 0
		opp_hypotheses.clear()

	func preview_pair(seat: int, own: EngineAction, opp: EngineAction) -> Array[int]:
		if watching:
			pair_previews += 1
			opp_hypotheses.append(opp)
		if refuse_pairs:
			var none: Array[int] = []
			return none
		_inside += 1
		var out: Array[int] = super(seat, own, opp)
		_inside -= 1
		return out

	func preview(seat: int, action: EngineAction) -> Array[int]:
		if watching:
			commit_previews += 1
		_inside += 1
		var out: Array[int] = super(seat, action)
		_inside -= 1
		return out

	func preview_choice(seat: int, index: int) -> Array[int]:
		if watching:
			choice_previews += 1
		_inside += 1
		var out: Array[int] = super(seat, index)
		_inside -= 1
		return out

	func preview_set(seat: int, indices: Array[int]) -> Array[int]:
		if watching:
			set_previews += 1
		_inside += 1
		var out: Array[int] = super(seat, indices)
		_inside -= 1
		return out

	func apply(action: EngineAction) -> ApplyResult:
		_other()
		return super(action)

	func awaited_seat() -> int:
		_other()
		return super()

	func open_prompt() -> Dictionary:
		_other()
		return super()

	func is_over() -> bool:
		_other()
		return super()

	func energy() -> int:
		_other()
		return super()

	func budget_for(seat: int) -> int:
		_other()
		return super(seat)

	func budgets() -> Array[int]:
		_other()
		return super()

	func view_for(seat: int) -> SeatView:
		_other()
		return super(seat)

	func full_state() -> Dictionary:
		_other()
		return super()

	func action_log() -> ActionLog:
		_other()
		return super()

	func deck_ids() -> Array[String]:
		_other()
		return super()

	func match_cards() -> MatchCards:
		_other()
		return super()

	func accepted_action_count() -> int:
		_other()
		return super()

	func accepted_actions() -> Array[EngineAction]:
		_other()
		return super()

	func _other() -> void:
		if watching and _inside == 0:
			other_calls += 1
