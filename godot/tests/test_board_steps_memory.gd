class_name TestBoardStepsMemory
extends GdUnitTestSuite
## BoardSteps with card memory (cycle 8 P16): a private STATS_CHANGED on a hand card.


func _grow_event(seat: int, card: int, owner: int) -> MatchEvent:
	var payload: Dictionary = {
		"seat": seat,
		"card": card,
		"flat": 3,
		"times": 175,
		"plus": 0,
		"cost": 2,
		"cause": "grow",
		"permanent": true,
	}
	return MatchEvent.new(MatchEvent.Kind.STATS_CHANGED, payload, owner)


func test_private_stats_on_a_viewers_hand_card_is_a_hand_step() -> void:
	var events: Array[MatchEvent] = [_grow_event(0, 4, 0)]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0, 0)
	assert_int(steps.size()).is_equal(1)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.STATS)
	assert_bool(steps[0].in_hand).is_true()
	assert_int(steps[0].cost).is_equal(2)
	assert_bool(steps[0].permanent).is_true()


func test_private_stats_on_an_opponents_hidden_card_yields_no_step() -> void:
	var events: Array[MatchEvent] = [_grow_event(1, MatchEvent.HIDDEN_CARD, 1)]
	assert_int(BoardSteps.from_events(events, 1.0, 0).size()).is_equal(0)


func test_public_stats_on_a_row_card_is_not_a_hand_step() -> void:
	var events: Array[MatchEvent] = [_grow_event(0, 4, MatchEvent.PUBLIC)]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0, 0)
	assert_int(steps.size()).is_equal(1)
	assert_bool(steps[0].in_hand).is_false()
