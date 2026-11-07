class_name TestScoring
extends GdUnitTestSuite
## Scoring (cycle 9 plan P7; spec R23 to R28, C3; DC-13 T03): the walking total in integer
## ten-thousandths, the Bonus value, the Walk-end rounding, Mult growth with its cap, and a
## card's effective stats and Cost. The canon's worked rows ([[rules/rules-v2]] section 5)
## are pinned: A (Power 2, ×1.5), B (Power 3, +1), C (Power 4) give 16 in the order A B C
## and 24 in the order C A B.

const SCALE: int = MatchRules.SCALE


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## The walking total after each card of `row` Scores, each card [power, adds, mults].
func _walk(row: Array) -> Array[int]:
	var out: Array[int] = []
	var total: int = 0
	for card: Array in row:
		var power: int = card[0]
		var raw_adds: Array = card[1]
		var raw_mults: Array = card[2]
		var adds: Array[int] = _typed(raw_adds)
		var mults: Array[int] = _typed(raw_mults)
		total = Scoring.step_total(total, power, Scoring.bonus_value(adds, mults))
		out.append(total)
	return out


# --- The walking total ----------------------------------------------------------------


func test_the_canons_worked_rows_give_16_and_24() -> void:
	var a: Array = [2, [], [150]]
	var b: Array = [3, [100], []]
	var c: Array = [4, [], []]
	var abc: Array[int] = _walk([a, b, c])
	assert_array(abc).is_equal(_typed([3 * SCALE, 12 * SCALE, 16 * SCALE]))
	assert_int(Scoring.walk_score(abc[2])).is_equal(16)
	var cab: Array[int] = _walk([c, a, b])
	assert_array(cab).is_equal(_typed([4 * SCALE, 9 * SCALE, 24 * SCALE]))
	assert_int(Scoring.walk_score(cab[2])).is_equal(24)
	# B A C also gives 16, the canon's coincidence: (3 x 2 + 2) x 1.5 + 4.
	assert_int(Scoring.walk_score(_walk([b, a, c])[2])).is_equal(16)


## (1 + 0.5) x 1.25 is 1.875: Void's grant (canon crew-v2).
func test_a_bonus_value_applies_every_add_then_every_mult() -> void:
	assert_int(Scoring.bonus_value(_typed([50]), _typed([125]))).is_equal(18750)
	assert_int(Scoring.bonus_value(_typed([]), _typed([]))).is_equal(SCALE)
	assert_int(Scoring.bonus_value(_typed([100]), _typed([]))).is_equal(20000)
	assert_int(Scoring.bonus_value(_typed([25, 25]), _typed([150, 200]))).is_equal(45000)
	# A Mult below 1 simply multiplies; the value is never below 0.
	assert_int(Scoring.bonus_value(_typed([]), _typed([50]))).is_equal(5000)
	assert_int(Scoring.bonus_value(_typed([-300]), _typed([]))).is_equal(0)


## A total of 2.5 and a card of Power 1 with ×1.25: (2.5 + 1) x 1.25 = 4.375.
func test_a_total_of_25000_with_power_1_and_x1_25_is_43750() -> void:
	var bv: int = Scoring.bonus_value(_typed([]), _typed([125]))
	assert_int(Scoring.step_total(25000, 1, bv)).is_equal(43750)


## Each multiply rounds to the ten-thousandth, half up: 3 x 1.0001 is 3.0003 exactly, 0.0001
## x 1.5 is 0.00015, which rounds to 0.0002.
func test_each_multiply_rounds_to_the_ten_thousandth() -> void:
	assert_int(Scoring.step_total(1, 0, 15000)).is_equal(2)
	assert_int(Scoring.step_total(-1, 0, 15000)).is_equal(-1)
	assert_int(Scoring.round_half_up(7, 2)).is_equal(4)
	assert_int(Scoring.round_half_up(-7, 2)).is_equal(-3)
	assert_int(Scoring.round_half_up(-8, 2)).is_equal(-4)
	assert_int(Scoring.round_half_up(6, 0)).is_equal(0)


## A negative total is multiplied like any other: a Mult above 1 makes it more negative.
func test_a_negative_total_is_multiplied_like_any_other() -> void:
	var bv: int = Scoring.bonus_value(_typed([]), _typed([200]))
	assert_int(Scoring.step_total(0, -3, bv)).is_equal(-60000)
	assert_int(Scoring.step_total(-60000, 1, SCALE)).is_equal(-50000)


# --- Walk-end rounding ----------------------------------------------------------------


func test_walk_end_rounding_rounds_half_up_once() -> void:
	assert_int(Scoring.walk_score(43750)).is_equal(4)
	assert_int(Scoring.walk_score(-15000)).is_equal(-1)
	assert_int(Scoring.walk_score(5000)).is_equal(1)
	assert_int(Scoring.walk_score(4999)).is_equal(0)
	assert_int(Scoring.walk_score(160000)).is_equal(16)
	assert_int(Scoring.walk_score(-15001)).is_equal(-2)
	assert_int(Scoring.walk_score(0)).is_equal(0)


# --- Growth ---------------------------------------------------------------------------


## (1.5 + 0.25) x 1.2 = 2.10 (canon rules-v2 section 5): the base, the additive steps, then
## the multiplicative ones, rounded to the hundredth.
func test_growth_is_base_then_adds_then_times() -> void:
	assert_int(Scoring.grown_mult(150, 25, _typed([120]), 0)).is_equal(210)
	assert_int(Scoring.grown_mult(125, 0, _typed([]), 0)).is_equal(125)
	# 1.25 x 1.2 = 1.5; x 1.2 again = 1.8.
	assert_int(Scoring.grown_mult(125, 0, _typed([120, 120]), 0)).is_equal(180)
	# 1.33 x 1.25 = 1.6625 rounds to 1.66.
	assert_int(Scoring.grown_mult(133, 0, _typed([125]), 0)).is_equal(166)


## Sapling's +0.25 per Score caps at ×2.00; Graft's ×1.2 caps at ×2.50.
func test_sapling_caps_at_200_and_graft_at_250() -> void:
	var sapling: Array[int] = []
	for scores: int in range(6):
		sapling.append(Scoring.grown_mult(125, 25 * scores, _typed([]), 200))
	assert_array(sapling).is_equal(_typed([125, 150, 175, 200, 200, 200]))
	assert_int(Scoring.grown_mult(200, 0, _typed([120]), 250)).is_equal(240)
	assert_int(Scoring.grown_mult(200, 0, _typed([120, 120]), 250)).is_equal(250)
	assert_int(Scoring.grown_mult(150, 0, _typed([120, 120, 120]), 250)).is_equal(250)


# --- A card's stats and Cost ----------------------------------------------------------


func _defs() -> MatchCards:
	var ids: Array[String] = ["greed", "ramp"]
	return MatchCards.build(
		CardDb.load_default(), DeckList.load_default(), ids, CrewPool.load_default()
	)


## Skim (Power 2, ×1.25) with Memory +0.25 Mult and +1 Power, a Board change of +2 Power
## and a granted ×1.5: Power 5, Mults [150, 150], Bonus value 2.25.
func test_stats_read_printed_memory_and_board_changes() -> void:
	var defs: MatchCards = _defs()
	var skim: int = 12
	var state: MatchState = MatchState.new(1)
	var plain: Scoring.Stats = Scoring.stats(skim, state, defs)
	assert_dict(plain.to_dict()).is_equal({"power": 2, "mult": 125, "add": 0})
	state.memory_for(skim).power = 1
	state.memory_for(skim).mult_add_steps = 25
	state.card_state_for(skim).power_delta = 2
	state.card_state_for(skim).grant(CardState.KIND_MULT, 150, "turn")
	var grown: Scoring.Stats = Scoring.stats(skim, state, defs)
	assert_int(grown.power).is_equal(5)
	assert_array(grown.mults).is_equal(_typed([150, 150]))
	assert_int(grown.bonus_value()).is_equal(22500)
	assert_int(grown.mult()).is_equal(225)
	assert_bool(Scoring.is_grown(skim, state)).is_true()
	var unknown: Scoring.Stats = Scoring.stats(999, state, defs)
	assert_dict(unknown.to_dict()).is_equal({"power": 0, "mult": 100, "add": 0})


## A Memory reduction lowers the Cost, never below 0 (R8); Colossus costs 7 on Turn 7 and
## its printed 12 otherwise (cost_on_turn).
func test_effective_cost_reads_memory_and_the_turn() -> void:
	var defs: MatchCards = _defs()
	var gilt: int = 32
	var colossus: int = MatchRules.DECK_SIZE + 36
	var state: MatchState = MatchState.new(1)
	assert_int(Scoring.effective_cost(gilt, state, defs)).is_equal(6)
	state.memory_for(gilt).cost_delta = -1
	assert_int(Scoring.effective_cost(gilt, state, defs)).is_equal(5)
	state.memory_for(gilt).cost_delta = -9
	assert_int(Scoring.effective_cost(gilt, state, defs)).is_equal(0)
	state.turn = 6
	assert_int(Scoring.effective_cost(colossus, state, defs)).is_equal(12)
	state.turn = 7
	assert_int(Scoring.effective_cost(colossus, state, defs)).is_equal(7)
	assert_int(Scoring.effective_cost(999, state, defs)).is_equal(-1)
