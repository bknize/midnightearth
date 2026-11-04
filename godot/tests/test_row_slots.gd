class_name TestRowSlots
extends GdUnitTestSuite
## RowSlots (R43, R47, P15): staged index around played cards, slot order, insert index.


func test_staged_before_ignores_played_cards() -> void:
	var played: Dictionary = {1: true, 2: true}
	var row: Array[int] = [1, 7, 2, 8]
	assert_int(RowSlots.staged_before(row, played, 7)).is_equal(0)
	assert_int(RowSlots.staged_before(row, played, 8)).is_equal(1)


func test_staged_before_a_gap_between_two_played_cards() -> void:
	var played: Dictionary = {1: true, 2: true}
	var row: Array[int] = [1, 9, 2]
	assert_int(RowSlots.staged_before(row, played, 9)).is_equal(0)


func test_order_by_slot_sorts_lowest_first() -> void:
	var slots: Array[int] = [3, 0, 2]
	assert_array(RowSlots.order_by_slot(slots, 3)).is_equal([1, 2, 0])


func test_order_by_slot_keeps_index_order_without_matching_slots() -> void:
	var none: Array[int] = []
	assert_array(RowSlots.order_by_slot(none, 3)).is_equal([0, 1, 2])
	assert_array(RowSlots.order_by_slot(none, 0)).is_empty()


func test_inserting_in_slot_order_lands_each_card_at_its_slot() -> void:
	var slots: Array[int] = [3, 0]
	var row: Array[String] = ["a", "b"]
	var names: Array[String] = ["x", "y"]
	for k: int in RowSlots.order_by_slot(slots, 2):
		row.insert(RowSlots.insert_index(slots[k], row.size()), names[k])
	assert_array(row).is_equal(["y", "a", "b", "x"])


func test_staging_slots_follow_a_row_with_a_gap_between_played_cards() -> void:
	var staging: Staging = Staging.new()
	staging.reset(10, 2)
	assert_bool(staging.insert(7, 1, 0)).is_true()
	assert_bool(staging.insert(8, 1, 1)).is_true()
	staging.set_row([1, 7, 2, 8])
	assert_array(staging.slots()).is_equal([1, 3])
	assert_array(staging.to_action(0).slots).is_equal([1, 3])


func test_staging_slots_before_the_first_played_card() -> void:
	var staging: Staging = Staging.new()
	staging.reset(10, 1)
	assert_bool(staging.insert(7, 1, 0)).is_true()
	staging.set_row([7, 1])
	assert_array(staging.slots()).is_equal([0])


func test_insert_index_clamps() -> void:
	assert_int(RowSlots.insert_index(9, 2)).is_equal(2)
	assert_int(RowSlots.insert_index(-1, 2)).is_equal(0)
