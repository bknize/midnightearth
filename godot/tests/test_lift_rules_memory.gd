class_name TestLiftRulesMemory
extends GdUnitTestSuite
## LiftRules with card memory (cycle 8 R28): a hand restat puts the held card down.


func _restat(card: int) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.STATS
	step.seat = 0
	step.card = card
	step.in_hand = true
	return step


func test_a_hand_restat_of_the_held_card_touches_it() -> void:
	assert_bool(LiftRules.step_touches(_restat(7), 7, LiftRules.Place.HAND, false)).is_true()


func test_a_hand_restat_of_another_card_leaves_the_held_card() -> void:
	assert_bool(LiftRules.step_touches(_restat(8), 7, LiftRules.Place.HAND, false)).is_false()
