class_name TestStagingMemory
extends GdUnitTestSuite
## Staging on effective costs (cycle 8 R24).


func test_a_card_printed_at_three_and_reduced_to_two_stages_on_budget_two() -> void:
	var view: SeatView = SeatView.new()
	view.own_hand.assign([9])
	view.own_hand_costs.assign([2])
	var cost: int = Staging.view_cost(view, 9, 3)
	assert_int(cost).is_equal(2)
	var staging: Staging = Staging.new()
	staging.reset(2)
	assert_bool(staging.can_afford(cost)).is_true()
	assert_bool(staging.insert(9, cost, 0)).is_true()
	assert_int(staging.energy_left()).is_equal(0)


func test_view_cost_falls_back_to_the_printed_cost() -> void:
	var view: SeatView = SeatView.new()
	view.own_hand.assign([9])
	assert_int(Staging.view_cost(view, 9, 3)).is_equal(3)
	assert_int(Staging.view_cost(view, 77, 4)).is_equal(4)
