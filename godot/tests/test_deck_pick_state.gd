class_name TestDeckPickState
extends GdUnitTestSuite
## DeckPickState (DC-07 T11; R39-R41, plan P15): Start only with both picks, preselection
## from a pair, and a pick replacing the column's previous one.


func _state(preselected: Array[String]) -> DeckPickState:
	var state: DeckPickState = DeckPickState.new()
	var available: Array[String] = ["ruin", "drift", "fixture"]
	state.setup(available, preselected)
	return state


func test_start_needs_both_picks() -> void:
	var state: DeckPickState = _state([])
	assert_bool(state.can_start()).is_false()
	assert_bool(state.pick(0, "ruin")).is_true()
	assert_bool(state.can_start()).is_false()
	assert_bool(state.pick(1, "drift")).is_true()
	assert_bool(state.can_start()).is_true()


func test_preselection_from_a_pair() -> void:
	var state: DeckPickState = _state(["drift", "ruin"])
	assert_bool(state.can_start()).is_true()
	assert_str(state.picked_id(0)).is_equal("drift")
	assert_str(state.picked_id(1)).is_equal("ruin")
	assert_array(state.deck_ids()).contains_exactly(["drift", "ruin"])


func test_preselection_ignores_unknown_ids() -> void:
	var state: DeckPickState = _state(["ruin", "nope"])
	assert_str(state.picked_id(0)).is_equal("ruin")
	assert_str(state.picked_id(1)).is_equal("")
	assert_bool(state.can_start()).is_false()


func test_a_pick_replaces_the_previous_pick() -> void:
	var state: DeckPickState = _state(["ruin", "ruin"])
	assert_bool(state.pick(0, "drift")).is_true()
	assert_str(state.picked_id(0)).is_equal("drift")
	assert_str(state.picked_id(1)).is_equal("ruin")
	assert_bool(state.can_start()).is_true()


func test_a_refused_pick_changes_nothing() -> void:
	var state: DeckPickState = _state(["ruin", "drift"])
	assert_bool(state.pick(0, "nope")).is_false()
	assert_bool(state.pick(2, "ruin")).is_false()
	assert_array(state.deck_ids()).contains_exactly(["ruin", "drift"])


func test_default_is_two_columns() -> void:
	var state: DeckPickState = _state([])
	assert_int(state.column_count()).is_equal(2)


func test_one_column_starts_with_one_pick() -> void:
	var state: DeckPickState = DeckPickState.new()
	var available: Array[String] = ["ruin", "drift"]
	state.setup(available, [], 1)
	assert_int(state.column_count()).is_equal(1)
	assert_bool(state.can_start()).is_false()
	assert_bool(state.pick(0, "ruin")).is_true()
	assert_bool(state.can_start()).is_true()
	assert_array(state.deck_ids()).contains_exactly(["ruin"])


func test_one_column_refuses_a_second_column() -> void:
	var state: DeckPickState = DeckPickState.new()
	var available: Array[String] = ["ruin", "drift"]
	state.setup(available, ["drift", "ruin"], 1)
	assert_bool(state.pick(1, "ruin")).is_false()
	assert_array(state.deck_ids()).contains_exactly(["drift"])
