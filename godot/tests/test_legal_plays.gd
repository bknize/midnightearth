# gdlint: disable=max-public-methods
class_name TestLegalPlays
extends GdUnitTestSuite
## LegalPlays: R5, R13 (cost <= turn energy), R26 (commit validation codes), R36 (the
## enumeration the bot chooses from), Phase 3 R5 (multi-card subset-sum); DC-05 R5, R6
## (positional slots, BAD_SLOTS), R9 (budget with carry) and R10 (the free first card).
##
## Instance ids are seat * 20 + index (plan), so with the default card table:
## 0..3 = c01..c04 (cost 1), 4..7 = c05..c08 (cost 2), 8 = c09 (3), 11 = c12 (4),
## 12 = c13 (4), 14 = c15 (5), 16 = c17 (6), 18 = c19 (7); seat 1 adds 20.


func _db() -> CardDb:
	return CardDb.load_default()


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## validate() for a commit appended to an empty row, with no free first card: the
## pre-DC-05 shape of the cycle-1 checks below.
func _check(proposal: Array[int], hand: Array[int], budget: int, db: CardDb) -> int:
	var slots: Array[int] = LegalPlays.append_slots(0, proposal.size())
	return LegalPlays.validate(proposal, slots, hand, 0, budget, false, db)


# --- Card cost lookup by instance id --------------------------------------------------


func test_cost_of_maps_instance_id_mod_20() -> void:
	var db: CardDb = _db()
	assert_int(LegalPlays.cost_of(0, db)).is_equal(1)
	assert_int(LegalPlays.cost_of(18, db)).is_equal(7)
	assert_int(LegalPlays.cost_of(38, db)).is_equal(7)
	assert_int(LegalPlays.cost_of(31, db)).is_equal(4)
	assert_int(LegalPlays.cost_of(-1, db)).is_equal(-1)


# --- Enumeration counts ---------------------------------------------------------------


func test_seven_card_hand_at_energy_seven_counts_64() -> void:
	# Seat 1, costs [1, 1, 1, 1, 2, 2, 7]. With the 7: only {7} alone fits (1 set).
	# Without it: every subset of the six small cards fits except all six (cost 8),
	# so 2^6 - 1 = 63. Total 64.
	var hand: Array[int] = [20, 21, 22, 23, 24, 25, 38]
	var sets: Array[Array] = LegalPlays.enumerate(hand, 7, _db())
	assert_int(sets.size()).is_equal(64)


func test_seven_card_hand_distinct_costs_counts_19() -> void:
	# Seat 0, costs [1, 2, 3, 4, 5, 6, 7]. Legal sets are partitions of 0..7 into
	# distinct parts: 1 + 1 + 1 + 2 + 2 + 3 + 4 + 5 = 19.
	var hand: Array[int] = [0, 4, 8, 11, 14, 16, 18]
	var sets: Array[Array] = LegalPlays.enumerate(hand, 7, _db())
	assert_int(sets.size()).is_equal(19)


func test_every_enumerated_set_is_within_budget_and_validates() -> void:
	var db: CardDb = _db()
	var hand: Array[int] = [0, 4, 8, 11, 14, 16, 18]
	for energy: int in range(1, MatchRules.TURNS + 1):
		for s: Array in LegalPlays.enumerate(hand, energy, db):
			var cards: Array[int] = _typed(s)
			assert_int(LegalPlays.total_cost(cards, db)).is_less_equal(energy)
			assert_int(_check(cards, hand, energy, db)).is_equal(EngineError.Code.NONE)


func test_full_hand_affordable_lists_all_128() -> void:
	# Seat 0, costs [1, 1, 1, 1, 2, 2, 2]: total 10, so energy 10 admits every subset.
	var hand: Array[int] = [0, 1, 2, 3, 4, 5, 6]
	assert_int(LegalPlays.enumerate(hand, 10, _db()).size()).is_equal(128)


# --- Deterministic order --------------------------------------------------------------


func test_order_is_ascending_bitmask_over_hand_order() -> void:
	var hand: Array[int] = [0, 1, 2]
	var masks: Array[int] = LegalPlays.enumerate_masks(hand, 3, _db())
	var expected_masks: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	assert_array(masks).is_equal(expected_masks)
	var sets: Array[Array] = LegalPlays.enumerate(hand, 3, _db())
	var expected: Array[Array] = [[], [0], [1], [0, 1], [2], [0, 2], [1, 2], [0, 1, 2]]
	assert_int(sets.size()).is_equal(expected.size())
	for i: int in range(expected.size()):
		assert_array(_typed(sets[i])).is_equal(_typed(expected[i]))


func test_order_skips_unaffordable_masks() -> void:
	# Costs [4, 1, 4] at energy 5: masks 5 (4+4) and 7 (9) are over budget.
	var hand: Array[int] = [11, 0, 12]
	var masks: Array[int] = LegalPlays.enumerate_masks(hand, 5, _db())
	var expected: Array[int] = [0, 1, 2, 3, 4, 6]
	assert_array(masks).is_equal(expected)
	assert_array(LegalPlays.subset(hand, 6)).is_equal(_typed([0, 12]))


func test_enumeration_is_stable_across_calls() -> void:
	var db: CardDb = _db()
	var hand: Array[int] = [20, 21, 22, 23, 24, 25, 38]
	var first: Array[int] = LegalPlays.enumerate_masks(hand, 7, db)
	var second: Array[int] = LegalPlays.enumerate_masks(hand, 7, db)
	assert_array(second).is_equal(first)


# --- Empty set always present ---------------------------------------------------------


func test_empty_set_always_first() -> void:
	var db: CardDb = _db()
	var hands: Array[Array] = [[], [18], [18, 38], [0, 4, 8, 11, 14, 16, 18]]
	for h: Array in hands:
		var hand: Array[int] = _typed(h)
		for energy: int in range(0, MatchRules.TURNS + 1):
			var sets: Array[Array] = LegalPlays.enumerate(hand, energy, db)
			assert_int(sets.size()).is_greater_equal(1)
			assert_array(_typed(sets[0])).is_empty()


func test_empty_or_unaffordable_hand_has_only_the_pass() -> void:
	var sets: Array[Array] = LegalPlays.enumerate([], 7, _db())
	assert_int(sets.size()).is_equal(1)
	assert_array(_typed(sets[0])).is_empty()
	var hand: Array[int] = [18, 38]
	var masks: Array[int] = LegalPlays.enumerate_masks(hand, 6, _db())
	var expected: Array[int] = [0]
	assert_array(masks).is_equal(expected)


func test_empty_commit_is_always_legal() -> void:
	var db: CardDb = _db()
	var hand: Array[int] = [18]
	assert_int(_check([], hand, 1, db)).is_equal(EngineError.Code.NONE)
	assert_int(_check([], [], 1, db)).is_equal(EngineError.Code.NONE)


# --- Budget edges ---------------------------------------------------------------------


func test_single_card_exactly_at_energy_is_legal_one_over_is_not() -> void:
	var db: CardDb = _db()
	var hand: Array[int] = [11, 0]
	var card: Array[int] = [11]
	assert_int(_check(card, hand, 4, db)).is_equal(EngineError.Code.NONE)
	assert_int(_check(card, hand, 3, db)).is_equal(EngineError.Code.OVER_BUDGET)


func test_multi_card_exactly_at_energy_is_legal_one_over_is_not() -> void:
	var db: CardDb = _db()
	var hand: Array[int] = [11, 0, 12]
	var pair: Array[int] = [11, 0]
	assert_int(_check(pair, hand, 5, db)).is_equal(EngineError.Code.NONE)
	assert_int(_check(pair, hand, 4, db)).is_equal(EngineError.Code.OVER_BUDGET)


func test_enumeration_budget_edge() -> void:
	var db: CardDb = _db()
	var hand: Array[int] = [11]
	var at_energy: Array[int] = [0, 1]
	var one_short: Array[int] = [0]
	assert_array(LegalPlays.enumerate_masks(hand, 4, db)).is_equal(at_energy)
	assert_array(LegalPlays.enumerate_masks(hand, 3, db)).is_equal(one_short)


# --- Duplicate and missing cards ------------------------------------------------------


func test_duplicate_card_rejected() -> void:
	var hand: Array[int] = [0, 1]
	var proposal: Array[int] = [0, 0]
	assert_int(_check(proposal, hand, 7, _db())).is_equal(EngineError.Code.DUPLICATE_CARD)


func test_missing_card_rejected() -> void:
	var hand: Array[int] = [0, 1]
	var proposal: Array[int] = [5]
	assert_int(_check(proposal, hand, 7, _db())).is_equal(EngineError.Code.CARD_NOT_IN_HAND)


func test_opponents_copy_rejected_and_codes_distinct() -> void:
	# Instance 20 is seat 1's c01; seat 0 holds instance 0, the same definition.
	var hand: Array[int] = [0]
	var proposal: Array[int] = [20]
	assert_int(_check(proposal, hand, 7, _db())).is_equal(EngineError.Code.CARD_NOT_IN_HAND)
	# The two rejections carry distinct codes.
	assert_int(EngineError.Code.DUPLICATE_CARD).is_not_equal(EngineError.Code.CARD_NOT_IN_HAND)
	assert_int(EngineError.Code.DUPLICATE_CARD).is_not_equal(EngineError.Code.NONE)
	assert_int(EngineError.Code.CARD_NOT_IN_HAND).is_not_equal(EngineError.Code.NONE)


func test_membership_checked_before_budget() -> void:
	# A duplicate or missing card is reported even when the set is also over budget.
	var db: CardDb = _db()
	var hand: Array[int] = [18, 0]
	var dup: Array[int] = [18, 18]
	var missing: Array[int] = [18, 38]
	assert_int(_check(dup, hand, 1, db)).is_equal(EngineError.Code.DUPLICATE_CARD)
	assert_int(_check(missing, hand, 1, db)).is_equal(EngineError.Code.CARD_NOT_IN_HAND)


# --- Failed card data -----------------------------------------------------------------


func test_failed_card_db_prices_nothing() -> void:
	var bad: CardDb = CardDb.from_json("{}")
	var hand: Array[int] = [0, 1]
	var proposal: Array[int] = [0]
	assert_int(LegalPlays.cost_of(0, bad)).is_equal(-1)
	assert_int(_check(proposal, hand, 7, bad)).is_equal(EngineError.Code.CARD_DATA_INVALID)
	var only_pass: Array[int] = [0]
	assert_array(LegalPlays.enumerate_masks(hand, 7, bad)).is_equal(only_pass)


# --- Slots (DC-05 R5, R6, plan P1) ----------------------------------------------------


## validate() of `proposal` (all in hand, ample budget) at `slots` on a row of
## `row_size` played cards.
func _with_slots(proposal: Array, slots: Array, row_size: int) -> int:
	var cards: Array[int] = _typed(proposal)
	return LegalPlays.validate(cards, _typed(slots), cards, row_size, 99, false, _db())


func test_slots_within_the_resulting_row_are_accepted() -> void:
	# Two played cards plus two new ones: the final row is 0..3.
	var accepted: Array[Array] = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]
	for slots: Array in accepted:
		var code: int = _with_slots([0, 1], slots, 2)
		assert_int(code).override_failure_message(str(slots)).is_equal(EngineError.Code.NONE)
	assert_int(_with_slots([0, 1, 2], [0, 1, 2], 0)).is_equal(EngineError.Code.NONE)
	assert_int(_with_slots([0], [5], 5)).is_equal(EngineError.Code.NONE)
	assert_int(_with_slots([], [], 4)).is_equal(EngineError.Code.NONE)


func test_out_of_range_slots_are_bad_slots() -> void:
	var cases: Array[Array] = [
		[[0, 1], [0, 4], 2],
		[[0, 1], [3, 4], 2],
		[[0, 1], [-1, 1], 2],
		[[0, 1], [0, 2], 0],
		[[0], [1], 0],
		[[0], [6], 5],
	]
	for c: Array in cases:
		var proposal: Array = c[0]
		var slots: Array = c[1]
		var row_size: int = c[2]
		var code: int = _with_slots(proposal, slots, row_size)
		assert_int(code).override_failure_message(str(c)).is_equal(EngineError.Code.BAD_SLOTS)


func test_repeated_slots_are_bad_slots() -> void:
	assert_int(_with_slots([0, 1], [1, 1], 2)).is_equal(EngineError.Code.BAD_SLOTS)
	assert_int(_with_slots([0, 1, 2], [0, 2, 2], 1)).is_equal(EngineError.Code.BAD_SLOTS)
	assert_int(_with_slots([0, 1], [0, 0], 0)).is_equal(EngineError.Code.BAD_SLOTS)


func test_out_of_order_slots_are_bad_slots() -> void:
	assert_int(_with_slots([0, 1], [2, 1], 2)).is_equal(EngineError.Code.BAD_SLOTS)
	assert_int(_with_slots([0, 1], [3, 0], 2)).is_equal(EngineError.Code.BAD_SLOTS)
	assert_int(_with_slots([0, 1, 2], [0, 2, 1], 0)).is_equal(EngineError.Code.BAD_SLOTS)


func test_slot_count_must_match_the_cards() -> void:
	assert_int(_with_slots([0, 1], [0], 2)).is_equal(EngineError.Code.BAD_SLOTS)
	assert_int(_with_slots([0, 1], [0, 1, 2], 2)).is_equal(EngineError.Code.BAD_SLOTS)
	# validate() takes explicit slots: the empty default is resolved by the engine.
	assert_int(_with_slots([0], [], 2)).is_equal(EngineError.Code.BAD_SLOTS)
	assert_int(_with_slots([], [0], 2)).is_equal(EngineError.Code.BAD_SLOTS)


func test_slots_checked_after_membership_and_before_budget() -> void:
	var db: CardDb = _db()
	var hand: Array[int] = [18, 0]
	var twice: Array[int] = [18, 18]
	var bad_slots: Array[int] = [1, 0]
	assert_int(LegalPlays.validate(twice, bad_slots, hand, 0, 99, false, db)).is_equal(
		EngineError.Code.DUPLICATE_CARD
	)
	var over: Array[int] = [18, 0]
	assert_int(LegalPlays.validate(over, bad_slots, hand, 0, 1, false, db)).is_equal(
		EngineError.Code.BAD_SLOTS
	)


func test_append_slots_fill_the_right_end() -> void:
	assert_array(LegalPlays.append_slots(3, 2)).is_equal(_typed([3, 4]))
	assert_array(LegalPlays.append_slots(0, 3)).is_equal(_typed([0, 1, 2]))
	assert_array(LegalPlays.append_slots(4, 0)).is_empty()
	for row_size: int in range(0, 6):
		for count: int in range(0, 4):
			var slots: Array[int] = LegalPlays.append_slots(row_size, count)
			assert_bool(LegalPlays.slots_valid(slots, count, row_size)).is_true()


# --- Budget with carry (DC-05 R9) -----------------------------------------------------


func test_budget_with_carry() -> void:
	# Costs 4 + 1 = 5 on turn 3: over the bare turn, legal with 2 carried, not with 1.
	var db: CardDb = _db()
	var hand: Array[int] = [11, 0]
	var pair: Array[int] = [11, 0]
	var slots: Array[int] = [0, 1]
	var turn: int = 3
	assert_int(LegalPlays.validate(pair, slots, hand, 0, turn, false, db)).is_equal(
		EngineError.Code.OVER_BUDGET
	)
	assert_int(LegalPlays.validate(pair, slots, hand, 0, turn + 1, false, db)).is_equal(
		EngineError.Code.OVER_BUDGET
	)
	assert_int(LegalPlays.validate(pair, slots, hand, 0, turn + 2, false, db)).is_equal(
		EngineError.Code.NONE
	)
	assert_int(LegalPlays.validate(pair, slots, hand, 0, turn + 3, false, db)).is_equal(
		EngineError.Code.NONE
	)


# --- The free first card (DC-05 R10) --------------------------------------------------


func test_free_first_card_makes_the_leftmost_new_card_cost_0() -> void:
	# 18 costs 7, 0 costs 1. With 18 leftmost and free, the commit costs 1.
	var db: CardDb = _db()
	var hand: Array[int] = [18, 0]
	var seven_then_one: Array[int] = [18, 0]
	var slots: Array[int] = [0, 1]
	assert_int(LegalPlays.validate(seven_then_one, slots, hand, 0, 1, true, db)).is_equal(
		EngineError.Code.NONE
	)
	assert_int(LegalPlays.validate(seven_then_one, slots, hand, 0, 0, true, db)).is_equal(
		EngineError.Code.OVER_BUDGET
	)
	assert_int(LegalPlays.validate(seven_then_one, slots, hand, 0, 7, false, db)).is_equal(
		EngineError.Code.OVER_BUDGET
	)
	# With the 1-cost card leftmost, only it is free: the 7 still counts.
	var one_then_seven: Array[int] = [0, 18]
	assert_int(LegalPlays.validate(one_then_seven, slots, hand, 0, 1, true, db)).is_equal(
		EngineError.Code.OVER_BUDGET
	)
	assert_int(LegalPlays.validate(one_then_seven, slots, hand, 0, 7, true, db)).is_equal(
		EngineError.Code.NONE
	)


func test_free_first_card_is_the_lowest_new_slot_not_the_row_start() -> void:
	# Two played cards sit at 0 and 2 of the final row; the new 18 at slot 1 is the
	# leftmost new card, so it is the free one.
	var db: CardDb = _db()
	var hand: Array[int] = [18, 0]
	var proposal: Array[int] = [18, 0]
	var slots: Array[int] = [1, 3]
	assert_int(LegalPlays.validate(proposal, slots, hand, 2, 1, true, db)).is_equal(
		EngineError.Code.NONE
	)
	assert_int(LegalPlays.validate(proposal, slots, hand, 2, 1, false, db)).is_equal(
		EngineError.Code.OVER_BUDGET
	)


func test_commit_cost_with_and_without_the_free_first_card() -> void:
	var db: CardDb = _db()
	var cards: Array[int] = [18, 0]
	assert_int(LegalPlays.commit_cost(cards, false, db)).is_equal(8)
	assert_int(LegalPlays.commit_cost(cards, true, db)).is_equal(1)
	assert_int(LegalPlays.commit_cost([], true, db)).is_equal(0)
	var single: Array[int] = [11]
	assert_int(LegalPlays.commit_cost(single, true, db)).is_equal(0)
