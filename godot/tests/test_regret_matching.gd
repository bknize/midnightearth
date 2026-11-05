class_name TestRegretMatching
extends GdUnitTestSuite
## RegretMatching (cycle 7 DC-10 T13; R51, plan P13): solve() returns the average row
## strategy of regret matching (matching pennies and rock-paper-scissors stay within 0.05 of
## uniform, a dominant row takes above 0.95), and sample_index() draws over whole-number
## weights, the same index for the same seed.

const ITERATIONS: int = 200
const TOLERANCE: float = 0.05
const DRAW_SEEDS: int = 50


func _matrix(rows: Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for row: Array in rows:
		out.append(PackedInt32Array(row))
	return out


func _assert_sums_to_one(strategy: PackedFloat32Array) -> void:
	var total: float = 0.0
	for probability: float in strategy:
		assert_float(probability).is_greater_equal(0.0)
		total += probability
	assert_float(total).is_equal_approx(1.0, 0.001)


func test_matching_pennies_converges_to_uniform() -> void:
	var pennies: Array[PackedInt32Array] = _matrix([[1, -1], [-1, 1]])
	var strategy: PackedFloat32Array = RegretMatching.solve(pennies, ITERATIONS)
	assert_int(strategy.size()).is_equal(2)
	for probability: float in strategy:
		assert_float(probability).is_equal_approx(0.5, TOLERANCE)
	_assert_sums_to_one(strategy)
	var scissors: Array[PackedInt32Array] = _matrix([[0, -1, 1], [1, 0, -1], [-1, 1, 0]])
	var mixed: PackedFloat32Array = RegretMatching.solve(scissors, ITERATIONS)
	for probability: float in mixed:
		assert_float(probability).is_equal_approx(1.0 / 3.0, TOLERANCE)
	_assert_sums_to_one(mixed)


## Uneven pennies [[2, 0], [0, 1]]: the equilibrium row mix is (1/3, 2/3), reached from a
## uniform start only by the regret updates.
func test_uneven_pennies_converges_to_its_equilibrium() -> void:
	var uneven: Array[PackedInt32Array] = _matrix([[2, 0], [0, 1]])
	var strategy: PackedFloat32Array = RegretMatching.solve(uneven, ITERATIONS)
	assert_float(strategy[0]).is_equal_approx(1.0 / 3.0, TOLERANCE)
	assert_float(strategy[1]).is_equal_approx(2.0 / 3.0, TOLERANCE)
	var again: PackedFloat32Array = RegretMatching.solve(uneven, ITERATIONS)
	assert_bool(again == strategy).is_true()


func test_a_dominant_row_gets_above_95_percent() -> void:
	var payoff: Array[PackedInt32Array] = _matrix([[1, 2, 0], [5, 4, 6], [3, 3, 3]])
	var strategy: PackedFloat32Array = RegretMatching.solve(payoff, ITERATIONS)
	assert_float(strategy[1]).is_greater(0.95)
	_assert_sums_to_one(strategy)
	var single_column: Array[PackedInt32Array] = _matrix([[-3], [7], [2], [6]])
	assert_float(RegretMatching.solve(single_column, ITERATIONS)[1]).is_greater(0.95)


func test_degenerate_matrices_are_uniform() -> void:
	assert_int(RegretMatching.solve(_matrix([]), ITERATIONS).size()).is_equal(0)
	var one: PackedFloat32Array = RegretMatching.solve(_matrix([[4, -2]]), ITERATIONS)
	assert_int(one.size()).is_equal(1)
	assert_float(one[0]).is_equal_approx(1.0, 0.0001)
	var ragged: PackedFloat32Array = RegretMatching.solve(_matrix([[1, 2], [3]]), ITERATIONS)
	assert_float(ragged[0]).is_equal_approx(0.5, 0.0001)
	var idle: PackedFloat32Array = RegretMatching.solve(_matrix([[9, 9], [0, 0]]), 0)
	assert_float(idle[0]).is_equal_approx(0.5, 0.0001)


func test_sample_index_is_deterministic_per_seed() -> void:
	var strategy: PackedFloat32Array = PackedFloat32Array([0.2, 0.5, 0.3])
	var hits: Dictionary[int, bool] = {}
	for draw_seed: int in range(1, DRAW_SEEDS + 1):
		var first: int = RegretMatching.sample_index(strategy, MatchRng.new(draw_seed))
		var again: int = RegretMatching.sample_index(strategy, MatchRng.new(draw_seed))
		assert_int(again).is_equal(first)
		assert_int(first).is_between(0, 2)
		hits[first] = true
		var twin: MatchRng = MatchRng.new(draw_seed)
		var draw: int = twin.pick_index(RegretMatching.SCALE)
		var expected: int = 0 if draw < 2000 else (1 if draw < 7000 else 2)
		assert_int(first).is_equal(expected)
	assert_int(hits.size()).is_equal(3)


func test_sample_index_weights_and_edges() -> void:
	var weights: PackedInt32Array = RegretMatching.weights(PackedFloat32Array([0.25, 0.75]))
	assert_array(Array(weights)).is_equal([2500, 7500])
	var pure: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 0.0])
	for draw_seed: int in range(1, DRAW_SEEDS + 1):
		assert_int(RegretMatching.sample_index(pure, MatchRng.new(draw_seed))).is_equal(1)
	assert_int(RegretMatching.sample_index(PackedFloat32Array(), MatchRng.new(1))).is_equal(-1)
	var zeros: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
	var twin: MatchRng = MatchRng.new(5)
	var expected: int = twin.pick_index(2)
	assert_int(RegretMatching.sample_index(zeros, MatchRng.new(5))).is_equal(expected)
