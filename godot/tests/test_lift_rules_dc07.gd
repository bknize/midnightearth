class_name TestLiftRulesDc07
extends GdUnitTestSuite
## LiftRules (R52) for the DC-07 step kinds.


func _named(kind: int, seat: int, card: int) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = kind
	step.seat = seat
	step.card = card
	return step


func test_unreveal_and_recover_touch_only_the_held_card() -> void:
	for kind: int in [BoardStep.Kind.UNREVEAL, BoardStep.Kind.RECOVER]:
		var step: BoardStep = _named(kind, 0, 7)
		assert_bool(LiftRules.step_touches(step, 7, LiftRules.Place.ROW, false)).is_true()
		assert_bool(LiftRules.step_touches(step, 8, LiftRules.Place.ROW, false)).is_false()


func test_a_grouped_move_touches_a_held_card_it_names_or_whose_row_it_moves() -> void:
	var step: BoardStep = _named(BoardStep.Kind.MOVE, 0, 3)
	step.cards.assign([3, 4, 5])
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.ROW, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 9, LiftRules.Place.HAND, false)).is_false()


func test_the_strip_steps_never_touch() -> void:
	for kind: int in [BoardStep.Kind.STRIP_SHOW, BoardStep.Kind.STRIP_HIDE]:
		var step: BoardStep = _named(kind, 0, 5)
		assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.ROW, true)).is_false()
