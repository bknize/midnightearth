class_name TestEvaluator
extends GdUnitTestSuite
## Evaluator (cycle 7 T03; R8, R13-R15, plan P5, P6): the 13 features in order, the weighted
## value in hundredths (the defaults give the plain score difference), and the level push:
## unchanged at level 20; at level 0 the best candidate keeps the highest expected pushed
## value and a candidate more than push_unit below the best never beats it.

const DRAWS: int = 1000
const PUSH_UNIT: int = 10
const MAX_ACTIONS: int = 1000

var _cached_db: CardDb = null


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## Commit views from one random-vs-random fixture match.
func _views(match_seed: int) -> Array[SeatView]:
	var out: Array[SeatView] = []
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	if not engine.start().ok:
		return out
	var bots: Array[RandomBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(RandomBot.new(BotRegistry.seed_for(match_seed, seat), engine.match_cards()))
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		if view.prompt.is_empty():
			out.append(view)
		if not engine.apply(bots[seat].choose(view, engine)).ok:
			break
		actions += 1
	return out


func test_features_are_the_thirteen_names_in_order() -> void:
	var expected: Array[String] = [
		"score_diff",
		"own_score",
		"opp_score",
		"energy_left",
		"cards_left",
		"cards_committed",
		"turns_left",
		"wins_diff",
		"wins_needed",
		"opp_hand",
		"opp_pending",
		"deck_left",
		"row_len_diff",
	]
	assert_array(Evaluator.FEATURES).is_equal(expected)


## features_of() reads the preview scores and the view as P5 says.
func test_features_of_reads_scores_and_view() -> void:
	var cards: MatchCards = FixtureDecks.defs(_db())
	var views: Array[SeatView] = _views(1)
	assert_int(views.size()).is_greater(0)
	for view: SeatView in views:
		var seat: int = view.seat
		for action: EngineAction in GreedyBot.candidates_for(view, cards):
			var scores: Array[int] = [0, 0]
			scores[seat] = 17
			scores[1 - seat] = 5
			var f: PackedInt32Array = Evaluator.features_of(view, scores, action, cards)
			assert_int(f.size()).is_equal(Evaluator.FEATURES.size())
			assert_int(f[0]).is_equal(12)
			assert_int(f[1]).is_equal(17)
			assert_int(f[2]).is_equal(5)
			var cost: int = LegalPlays.commit_cost(action.cards, view.free_first, cards)
			assert_int(f[3]).is_equal(view.energy - cost)
			assert_int(f[3]).is_greater_equal(0)
			assert_int(f[4]).is_equal(view.own_hand.size() - action.cards.size())
			assert_int(f[5]).is_equal(action.cards.size())
			assert_int(f[6]).is_equal(MatchRules.TURNS - view.turn)
			assert_int(f[7]).is_equal(view.wins[seat] - view.wins[1 - seat])
			assert_int(f[8]).is_equal(MatchRules.WINS_TO_TAKE - view.wins[seat])
			assert_int(f[9]).is_equal(view.opponent_hand_count)
			assert_int(f[10]).is_equal(view.opponent_pending_count)
			assert_int(f[11]).is_equal(view.deck_counts[seat])
			var opp_row: int = view.opponent_board.size() + view.opponent_pending_count
			assert_int(f[12]).is_equal(view.own_board.size() + action.cards.size() - opp_row)


## R12's premise: the default weights value a candidate at exactly its score difference.
func test_default_weights_value_is_score_diff() -> void:
	var defaults: BotWeights = BotWeights.defaults("tuned")
	var cards: MatchCards = FixtureDecks.defs(_db())
	for view: SeatView in _views(2):
		for action: EngineAction in GreedyBot.candidates_for(view, cards):
			for own: int in [30, 0, 7]:
				var pair: Array[int] = [own, 41 - own]
				var f: PackedInt32Array = Evaluator.features_of(view, pair, action, cards)
				assert_int(Evaluator.value(f, defaults)).is_equal(f[0])
				assert_int(Evaluator.value(f, null)).is_equal(f[0])


## Weights in hundredths, a missing feature weighing 0, the sum floored to whole points.
func test_value_weighs_in_hundredths_and_floors() -> void:
	var weights: BotWeights = BotWeights.defaults("tuned")
	weights.weights = {"score_diff": 100, "energy_left": 50, "turns_left": -25}
	var f: PackedInt32Array = PackedInt32Array([10, 0, 0, 3, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	# 1000 + 150 - 25 = 1125 hundredths -> 11.
	assert_int(Evaluator.value(f, weights)).is_equal(11)
	var g: PackedInt32Array = PackedInt32Array([-10, 0, 0, 3, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	# -1000 + 150 - 25 = -875 hundredths -> floor -8.75 = -9.
	assert_int(Evaluator.value(g, weights)).is_equal(-9)
	var empty: BotWeights = BotWeights.defaults("tuned")
	empty.weights = {}
	assert_int(Evaluator.value(f, empty)).is_equal(0)


## R13: level 20 returns the values unchanged and draws nothing that matters.
func test_level_20_pushes_nothing() -> void:
	var values: PackedInt32Array = PackedInt32Array([50, 48, 45, 30, -4])
	for draw_seed: int in range(1, 30):
		var rng: MatchRng = MatchRng.new(draw_seed)
		var got: PackedInt32Array = Evaluator.pushed(values, BotPlayer.FULL_LEVEL, PUSH_UNIT, rng)
		assert_array(Array(got)).is_equal(Array(values))


## R14 at level 0 over 1,000 draws: the best candidate has the highest mean pushed value; a
## candidate whose gap exceeds push_unit (30 against 50) never beats the best; a near one
## does sometimes (the knob does something).
func test_level_0_keeps_the_best_on_top_in_expectation() -> void:
	var values: PackedInt32Array = PackedInt32Array([50, 48, 45, 30])
	var sums: Array[int] = [0, 0, 0, 0]
	var near_wins: int = 0
	for draw: int in range(DRAWS):
		var draw_parts: Array[int] = [draw]
		var rng: MatchRng = MatchRng.new(MatchRng.derive_seed(7, draw_parts))
		var got: PackedInt32Array = Evaluator.pushed(values, 0, PUSH_UNIT, rng)
		assert_int(got.size()).is_equal(values.size())
		for index: int in range(got.size()):
			sums[index] += got[index]
			assert_int(got[index]).is_greater_equal(values[index])
		assert_int(got[3]).is_less(got[0])
		if got[1] > got[0] or got[2] > got[0]:
			near_wins += 1
	for index: int in range(1, sums.size()):
		assert_int(sums[0]).is_greater(sums[index])
	assert_int(near_wins).is_greater(0)


## At every level below 20, a candidate further than push_unit from the best keeps its value.
func test_far_candidates_never_pass_the_best_at_any_level() -> void:
	var values: PackedInt32Array = PackedInt32Array([40, 29, 12, 39])
	for level: int in range(BotPlayer.FULL_LEVEL):
		for draw_seed: int in range(1, 60):
			var rng: MatchRng = MatchRng.new(draw_seed)
			var got: PackedInt32Array = Evaluator.pushed(values, level, PUSH_UNIT, rng)
			assert_int(got[1]).is_equal(29)
			assert_int(got[2]).is_equal(12)
			assert_int(got[1]).is_less(got[0])


## The same generator seed gives the same push (the log replays).
func test_push_is_deterministic_per_seed() -> void:
	var values: PackedInt32Array = PackedInt32Array([20, 18, 15, 11, 3])
	for level: int in [0, 5, 13, 19]:
		var first: PackedInt32Array = Evaluator.pushed(values, level, PUSH_UNIT, MatchRng.new(99))
		var again: PackedInt32Array = Evaluator.pushed(values, level, PUSH_UNIT, MatchRng.new(99))
		assert_array(Array(again)).is_equal(Array(first))
