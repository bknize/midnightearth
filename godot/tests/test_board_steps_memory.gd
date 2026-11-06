class_name TestBoardStepsMemory
extends GdUnitTestSuite
## BoardSteps with card memory (cycle 8 P16, v7 STATS_CHANGED {card, power, mult, add, cost,
## permanent, cause}): a private change on a hand card is a hand step.


func _grow_event(card: int, owner: int) -> MatchEvent:
	var payload: Dictionary = {
		"card": card,
		"power": 3,
		"mult": 175,
		"add": 0,
		"cost": 2,
		"cause": "grow",
		"permanent": true,
	}
	return BoardEvents.make("STATS_CHANGED", payload, owner)


func test_private_stats_on_a_viewers_hand_card_is_a_hand_step() -> void:
	var step: BoardStep = BoardEvents.one(_grow_event(4, 0))
	assert_int(step.kind).is_equal(BoardStep.Kind.STATS)
	assert_bool(step.in_hand).is_true()
	assert_int(step.cost).is_equal(2)
	assert_bool(step.permanent).is_true()
	assert_int(step.power).is_equal(3)
	assert_int(step.mult).is_equal(175)


func test_private_stats_on_an_opponents_hidden_card_yields_no_step() -> void:
	var events: Array[MatchEvent] = [_grow_event(MatchEvent.HIDDEN_CARD, 1)]
	assert_int(BoardEvents.steps(events).size()).is_equal(0)


func test_public_stats_on_a_row_card_is_not_a_hand_step() -> void:
	var step: BoardStep = BoardEvents.one(_grow_event(4, MatchEvent.PUBLIC))
	assert_bool(step.in_hand).is_false()
	assert_int(step.seat).is_equal(-1)


func test_a_stats_change_carries_mult_and_add() -> void:
	var event: MatchEvent = BoardEvents.make(
		"STATS_CHANGED", {"card": 3, "power": 1, "mult": 125, "add": 50, "cost": 1, "cause": "x"}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.mult).is_equal(125)
	assert_int(step.add).is_equal(50)
