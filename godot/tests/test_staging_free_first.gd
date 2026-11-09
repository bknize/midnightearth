class_name TestStagingFreeFirst
extends GdUnitTestSuite
## Staging.can_afford agrees with Staging.insert at a free-first Turn (NSC-186, R21).


func test_a_cost_seven_card_is_affordable_on_budget_four_at_a_free_first_turn() -> void:
	var staging: Staging = Staging.new()
	staging.reset(4, 0, true)
	assert_bool(staging.can_afford(7)).is_true()
	assert_bool(staging.insert(1, 7, 0)).is_true()
	assert_int(staging.energy_left()).is_equal(4)


func test_can_afford_agrees_with_insert_at_slot_zero_with_a_card_staged() -> void:
	var staging: Staging = Staging.new()
	staging.reset(4, 0, true)
	assert_bool(staging.insert(1, 4, 0)).is_true()
	# A cost-7 card cannot go on the right end, but at slot 0 it is free and the 4 pays.
	assert_bool(staging.can_afford(7)).is_true()
	assert_bool(staging.insert(2, 7, 0)).is_true()
	assert_int(staging.energy_left()).is_equal(0)
	# Now the row holds 7 (free) and 4: nothing else fits at either end.
	assert_bool(staging.can_afford(5)).is_false()
	assert_bool(staging.insert(3, 5, 0)).is_false()


func test_can_afford_refuses_when_no_free_first_and_the_cost_is_over() -> void:
	var staging: Staging = Staging.new()
	staging.reset(4, 0, false)
	assert_bool(staging.can_afford(5)).is_false()
	assert_bool(staging.can_afford(4)).is_true()
