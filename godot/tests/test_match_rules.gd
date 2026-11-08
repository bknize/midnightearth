class_name TestMatchRules
extends GdUnitTestSuite
## MatchRules v9 (DC-13 T02, cycle 9 plan P1; rules 8 at cycle 13 C9, rules 9 at DC-20 T03,
## cycle 14 R12): the constants the
## rest of the engine reads, pinned so a change to one is a decision, not a slip.


## Rules 9 (DC-20 T03): a rules-8 log is refused at replay (test_action_log.gd).
func test_versions() -> void:
	assert_int(MatchRules.RULES_VERSION).is_equal(9)
	assert_int(MatchRules.LOG_FORMAT).is_equal(5)


func test_match_shape() -> void:
	assert_int(MatchRules.ROUNDS).is_equal(7)
	assert_int(MatchRules.TURNS).is_equal(7)
	assert_int(MatchRules.WINS_TO_TAKE).is_equal(4)


func test_deck_and_hand() -> void:
	assert_int(MatchRules.DECK_SIZE).is_equal(40)
	assert_int(MatchRules.MAX_COPIES).is_equal(4)
	assert_int(MatchRules.OPENING_HAND).is_equal(4)
	assert_int(MatchRules.HAND_SIZE).is_equal(4)
	assert_int(MatchRules.CREW_SIZE).is_equal(3)


func test_arithmetic_units_and_bonus_values() -> void:
	assert_int(MatchRules.SCALE).is_equal(10000)
	assert_int(MatchRules.BONUS_ONE).is_equal(100)
	var mults: Array[int] = [125, 150, 200]
	var adds: Array[int] = [25, 50, 100]
	assert_array(MatchRules.MULT_VALUES).is_equal(mults)
	assert_array(MatchRules.ADD_VALUES).is_equal(adds)


func test_costs_and_the_trigger_budget() -> void:
	assert_int(MatchRules.MIN_COST).is_equal(0)
	assert_int(MatchRules.MAX_PRINTED_COST).is_equal(7)
	assert_int(MatchRules.TRIGGER_BUDGET).is_equal(50)
	assert_int(MatchCards.DROSS_BASE).is_equal(2 * MatchRules.DECK_SIZE)  # The first Dross id.
