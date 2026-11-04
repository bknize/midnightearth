class_name TestRowTargets
extends GdUnitTestSuite
## RowTargets and CardSpot (plan P18): zone name + index to an absolute seat and slot, with
## both_boards as one flat list.

const OWN_SIZE: int = 3


func _spot(zone: String, chooser: int, index: int) -> CardSpot:
	return RowTargets.resolve(zone, chooser, index, OWN_SIZE)


func test_own_zones_belong_to_the_chooser() -> void:
	var hand: CardSpot = _spot("own_hand", 1, 2)
	assert_int(hand.seat).is_equal(1)
	assert_bool(hand.in_hand).is_true()
	assert_int(hand.slot).is_equal(2)
	var board: CardSpot = _spot("own_board", 0, 1)
	assert_int(board.seat).is_equal(0)
	assert_bool(board.in_hand).is_false()
	assert_int(board.slot).is_equal(1)


func test_opponent_zones_belong_to_the_other_seat() -> void:
	var hand: CardSpot = _spot("opponent_hand", 1, 0)
	assert_int(hand.seat).is_equal(0)
	assert_bool(hand.in_hand).is_true()
	var board: CardSpot = _spot("opponent_board", 0, 4)
	assert_int(board.seat).is_equal(1)
	assert_bool(board.in_hand).is_false()
	assert_int(board.slot).is_equal(4)


func test_both_boards_splits_at_the_own_row_size() -> void:
	var last_own: CardSpot = _spot("both_boards", 0, OWN_SIZE - 1)
	assert_int(last_own.seat).is_equal(0)
	assert_int(last_own.slot).is_equal(OWN_SIZE - 1)
	var first_other: CardSpot = _spot("both_boards", 0, OWN_SIZE)
	assert_int(first_other.seat).is_equal(1)
	assert_int(first_other.slot).is_equal(0)
	var later_other: CardSpot = _spot("both_boards", 1, OWN_SIZE + 2)
	assert_int(later_other.seat).is_equal(0)
	assert_int(later_other.slot).is_equal(2)
	assert_bool(later_other.in_hand).is_false()


func test_both_boards_with_an_empty_own_row_is_all_opponent() -> void:
	var spot: CardSpot = RowTargets.resolve("both_boards", 0, 1, 0)
	assert_int(spot.seat).is_equal(1)
	assert_int(spot.slot).is_equal(1)


func test_unknown_zone_is_invalid() -> void:
	assert_bool(_spot("nowhere", 0, 0).is_valid()).is_false()
	assert_bool(_spot("own_board", 0, -1).is_valid()).is_false()


func test_row_spot_names_the_row_and_slot_of_a_step() -> void:
	var destroy: BoardStep = BoardStep.new()
	destroy.kind = BoardStep.Kind.DESTROY
	destroy.seat = 1
	destroy.slot = 2
	var spot: CardSpot = RowTargets.row_spot(destroy)
	assert_int(spot.seat).is_equal(1)
	assert_int(spot.slot).is_equal(2)
	var move: BoardStep = BoardStep.new()
	move.kind = BoardStep.Kind.MOVE
	move.seat = 0
	move.from_slot = 4
	move.slot = 1
	assert_int(RowTargets.row_spot(move).slot).is_equal(4)
	var turn_end: BoardStep = BoardStep.new()
	turn_end.kind = BoardStep.Kind.TURN_END
	assert_bool(RowTargets.row_spot(turn_end).is_valid()).is_false()
