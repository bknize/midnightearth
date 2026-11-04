class_name TestBoardDragStrategy
extends GdUnitTestSuite
## BoardDragStrategy.can_drag (R44): a played card never drags; a staged one does.

var _played: Array[int] = []
var _staged: Array[int] = []


func before_test() -> void:
	_played = [1]
	_staged = [2]


func test_a_played_card_never_drags() -> void:
	var row: BoardDragStrategy = _strategy(BoardDragStrategy.Role.PLAYER_ROW)
	assert_bool(row.can_drag(1)).is_false()
	assert_bool(row.can_select_card(1, null)).is_false()
	assert_bool(row.can_remove_card(1, null)).is_false()
	assert_bool(row.can_reorder_card(1, null)).is_false()


func test_a_staged_card_drags() -> void:
	var row: BoardDragStrategy = _strategy(BoardDragStrategy.Role.PLAYER_ROW)
	assert_bool(row.can_drag(2)).is_true()
	assert_bool(row.can_remove_card(2, null)).is_true()


func test_a_card_in_neither_set_does_not_drag_from_the_row() -> void:
	var row: BoardDragStrategy = _strategy(BoardDragStrategy.Role.PLAYER_ROW)
	assert_bool(row.can_drag(3)).is_false()


func _always() -> bool:
	return true


func _in_played(card: int) -> bool:
	return _played.has(card)


func _in_staged(card: int) -> bool:
	return _staged.has(card)


func _strategy(role: BoardDragStrategy.Role) -> BoardDragStrategy:
	var strategy: BoardDragStrategy = BoardDragStrategy.new()
	strategy.role = role
	strategy.can_act = _always
	strategy.is_played = _in_played
	strategy.is_staged = _in_staged
	return strategy
