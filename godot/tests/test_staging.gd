class_name TestStaging
extends GdUnitTestSuite
## Staging (R12-R16, C9, C10): insert at an index, move, remove, the budget refusal, the
## energy readout and the commit action.

const SEAT: int = 0


func _staged(energy: int) -> Staging:
	var staging: Staging = Staging.new()
	staging.reset(energy)
	return staging


## Stages every id at cost 1, appended in the order given.
func _fill(staging: Staging, ids: Array[int]) -> void:
	for id: int in ids:
		assert_bool(staging.insert(id, 1, staging.cards().size())).is_true()


func test_insert_at_index_keeps_order() -> void:
	var staging: Staging = _staged(10)
	assert_bool(staging.insert(1, 1, 0)).is_true()
	assert_bool(staging.insert(2, 1, 1)).is_true()
	assert_bool(staging.insert(3, 1, 0)).is_true()
	assert_bool(staging.insert(4, 1, 2)).is_true()
	assert_array(staging.cards()).is_equal([3, 1, 4, 2])


func test_insert_index_is_clamped() -> void:
	var staging: Staging = _staged(10)
	assert_bool(staging.insert(1, 1, 99)).is_true()
	assert_bool(staging.insert(2, 1, -5)).is_true()
	assert_array(staging.cards()).is_equal([2, 1])


func test_insert_duplicate_is_refused() -> void:
	var staging: Staging = _staged(10)
	assert_bool(staging.insert(1, 2, 0)).is_true()
	assert_bool(staging.insert(1, 2, 0)).is_false()
	assert_array(staging.cards()).is_equal([1])
	assert_int(staging.energy_left()).is_equal(8)


func test_over_budget_insert_leaves_state_unchanged() -> void:
	var staging: Staging = _staged(3)
	assert_bool(staging.insert(1, 2, 0)).is_true()
	assert_bool(staging.can_afford(2)).is_false()
	assert_bool(staging.insert(2, 2, 0)).is_false()
	assert_bool(staging.has(2)).is_false()
	assert_array(staging.cards()).is_equal([1])
	assert_int(staging.energy_left()).is_equal(1)


func test_exact_budget_is_affordable() -> void:
	var staging: Staging = _staged(3)
	assert_bool(staging.can_afford(3)).is_true()
	assert_bool(staging.insert(1, 3, 0)).is_true()
	assert_int(staging.energy_left()).is_equal(0)
	assert_bool(staging.can_afford(1)).is_false()


func test_zero_cost_card_fits_with_no_energy_left() -> void:
	var staging: Staging = _staged(0)
	assert_bool(staging.insert(1, 0, 0)).is_true()
	assert_bool(staging.insert(2, 1, 0)).is_false()
	assert_array(staging.cards()).is_equal([1])


func test_energy_left_is_energy_minus_staged_cost() -> void:
	var staging: Staging = _staged(7)
	assert_int(staging.energy_left()).is_equal(7)
	assert_bool(staging.insert(1, 2, 0)).is_true()
	assert_bool(staging.insert(2, 3, 1)).is_true()
	assert_int(staging.energy_left()).is_equal(2)
	staging.remove(1)
	assert_int(staging.energy_left()).is_equal(4)
	staging.remove(2)
	assert_int(staging.energy_left()).is_equal(7)


func test_remove_keeps_order_and_ignores_unstaged() -> void:
	var staging: Staging = _staged(10)
	_fill(staging, [1, 2, 3])
	staging.remove(2)
	assert_array(staging.cards()).is_equal([1, 3])
	assert_bool(staging.has(2)).is_false()
	staging.remove(99)
	assert_array(staging.cards()).is_equal([1, 3])
	assert_int(staging.energy_left()).is_equal(8)


func test_move_reorders_within_the_row() -> void:
	var staging: Staging = _staged(10)
	_fill(staging, [1, 2, 3, 4])
	staging.move(4, 0)
	assert_array(staging.cards()).is_equal([4, 1, 2, 3])
	staging.move(4, 2)
	assert_array(staging.cards()).is_equal([1, 2, 4, 3])
	staging.move(1, 3)
	assert_array(staging.cards()).is_equal([2, 4, 3, 1])


func test_move_index_is_clamped_and_unstaged_is_a_noop() -> void:
	var staging: Staging = _staged(10)
	_fill(staging, [1, 2, 3])
	staging.move(1, 99)
	assert_array(staging.cards()).is_equal([2, 3, 1])
	staging.move(1, -4)
	assert_array(staging.cards()).is_equal([1, 2, 3])
	staging.move(99, 0)
	assert_array(staging.cards()).is_equal([1, 2, 3])
	assert_int(staging.energy_left()).is_equal(7)


func test_cards_returns_a_copy() -> void:
	var staging: Staging = _staged(10)
	assert_bool(staging.insert(1, 1, 0)).is_true()
	var copy: Array[int] = staging.cards()
	copy.append(2)
	assert_array(staging.cards()).is_equal([1])


func test_reset_clears_cards_and_sets_energy() -> void:
	var staging: Staging = _staged(5)
	assert_bool(staging.insert(1, 4, 0)).is_true()
	staging.reset(6)
	assert_array(staging.cards()).is_empty()
	assert_bool(staging.has(1)).is_false()
	assert_int(staging.energy_left()).is_equal(6)
	assert_bool(staging.insert(1, 6, 0)).is_true()


func test_empty_staging_is_a_pass() -> void:
	var staging: Staging = _staged(4)
	var action: EngineAction = staging.to_action(SEAT)
	assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(action.seat).is_equal(SEAT)
	assert_array(action.cards).is_empty()


func test_action_order_equals_row_order() -> void:
	var staging: Staging = _staged(10)
	assert_bool(staging.insert(5, 1, 0)).is_true()
	assert_bool(staging.insert(6, 1, 1)).is_true()
	assert_bool(staging.insert(7, 1, 0)).is_true()
	staging.move(5, 0)
	var action: EngineAction = staging.to_action(1)
	assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(action.seat).is_equal(1)
	assert_array(action.cards).is_equal(staging.cards())
	assert_array(action.cards).is_equal([5, 7, 6])


func test_slots_follow_row_indices() -> void:
	var staging: Staging = Staging.new()
	staging.reset(10, 2)
	_fill(staging, [1, 2])
	assert_bool(staging.insert(3, 1, 0)).is_true()
	assert_array(staging.cards()).is_equal([3, 1, 2])
	assert_array(staging.slots()).is_equal([2, 3, 4])
	var action: EngineAction = staging.to_action(SEAT)
	assert_array(action.cards).is_equal([3, 1, 2])
	assert_array(action.slots).is_equal([2, 3, 4])


func test_slots_start_at_zero_with_no_played_cards() -> void:
	var staging: Staging = _staged(10)
	_fill(staging, [5, 6])
	assert_array(staging.slots()).is_equal([0, 1])
	staging.reset(10, 3)
	assert_array(staging.slots()).is_empty()


func test_budget_with_carry_is_the_energy_given() -> void:
	# Turn 3 plus 2 carried: the board hands Staging the budget, 5.
	var staging: Staging = _staged(5)
	assert_bool(staging.insert(1, 3, 0)).is_true()
	assert_bool(staging.insert(2, 2, 1)).is_true()
	assert_int(staging.energy_left()).is_equal(0)
	assert_bool(staging.insert(3, 1, 2)).is_false()


func test_free_first_makes_the_leftmost_card_cost_nothing() -> void:
	var staging: Staging = Staging.new()
	staging.reset(3, 0, true)
	assert_bool(staging.free_first()).is_true()
	assert_bool(staging.can_afford(7)).is_true()
	assert_bool(staging.insert(1, 7, 0)).is_true()
	assert_int(staging.energy_left()).is_equal(3)
	assert_int(staging.charged_cost(1)).is_equal(0)
	assert_bool(staging.insert(2, 3, 1)).is_true()
	assert_int(staging.energy_left()).is_equal(0)
	assert_bool(staging.insert(3, 1, 2)).is_false()


func test_free_first_follows_the_lowest_slot() -> void:
	var staging: Staging = Staging.new()
	staging.reset(4, 0, true)
	assert_bool(staging.insert(1, 4, 0)).is_true()
	assert_int(staging.charged_cost(1)).is_equal(0)
	# Putting the cheap card first makes it the free one, so the 4-cost card now pays.
	assert_bool(staging.insert(2, 1, 0)).is_true()
	assert_int(staging.charged_cost(2)).is_equal(0)
	assert_int(staging.charged_cost(1)).is_equal(4)
	assert_int(staging.energy_left()).is_equal(0)
	staging.remove(2)
	assert_int(staging.charged_cost(1)).is_equal(0)
	assert_int(staging.energy_left()).is_equal(4)
