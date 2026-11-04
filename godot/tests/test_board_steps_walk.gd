class_name TestBoardStepsWalk
extends GdUnitTestSuite
## BoardSteps' DC-06 beats (R28-R30, R34): destroyed reveals, re-scores, the destroy mark,
## the turn-end fly-out and the longer turn end. Events are hand-built.

const EPSILON: float = 0.0001


func _event(kind: int, payload: Dictionary) -> MatchEvent:
	return MatchEvent.new(kind, payload)


func _reveal_event(card: int, seat: int = 0) -> MatchEvent:
	return _event(
		MatchEvent.Kind.CARD_REVEALED,
		{"seat": seat, "card": card, "def_id": "c01", "slot": 1, "flat": 2, "bonus": 1, "order": 0}
	)


func _scored_event(card: int, seat: int = 0) -> MatchEvent:
	return _event(
		MatchEvent.Kind.CARD_SCORED,
		{
			"seat": seat,
			"card": card,
			"slot": 1,
			"flat": 2,
			"bonus": 1,
			"mult": 3,
			"added": 9,
			"score": 12,
		}
	)


func _one(event: MatchEvent) -> BoardStep:
	var events: Array[MatchEvent] = [event]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0)
	assert_int(steps.size()).is_equal(1)
	return steps[0]


func test_a_destroyed_reveal_yields_a_flip_only_pulse_with_no_score() -> void:
	var reveal: MatchEvent = _event(
		MatchEvent.Kind.CARD_REVEALED,
		{
			"seat": 1,
			"card": 25,
			"def_id": "c01",
			"slot": 0,
			"flat": 2,
			"bonus": 1,
			"order": 0,
			"destroyed": true,
		}
	)
	# A stray score for the same card is not folded in: the pulse stays flip-only.
	var events: Array[MatchEvent] = [reveal, _scored_event(25, 1)]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.PULSE)
	assert_bool(steps[0].destroyed).is_true()
	assert_bool(steps[0].revealed).is_false()
	assert_int(steps[0].score).is_equal(-1)
	assert_int(steps[0].added).is_equal(0)
	assert_float(steps[0].duration).is_equal_approx(0.35, EPSILON)


func test_a_second_score_for_a_card_yields_a_short_pulse_with_again() -> void:
	var again: MatchEvent = _scored_event(3)
	again.payload["again"] = true
	var events: Array[MatchEvent] = [_reveal_event(3), _scored_event(3), again]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0)
	assert_int(steps.size()).is_equal(2)
	assert_bool(steps[0].again).is_false()
	assert_bool(steps[0].revealed).is_false()
	assert_int(steps[1].kind).is_equal(BoardStep.Kind.PULSE)
	assert_bool(steps[1].again).is_true()
	assert_bool(steps[1].revealed).is_true()
	assert_float(steps[1].duration).is_equal_approx(0.5, EPSILON)


func test_destroyed_cleared_yields_clear_destroyed_and_destroy_does_not_remove() -> void:
	var cleared: BoardStep = _one(
		_event(MatchEvent.Kind.DESTROYED_CLEARED, {"seat": 1, "card": 25, "slot": 2})
	)
	assert_int(cleared.kind).is_equal(BoardStep.Kind.CLEAR_DESTROYED)
	assert_int(cleared.slot).is_equal(2)
	assert_float(cleared.duration).is_equal_approx(0.45, EPSILON)
	var marked: BoardStep = _one(
		_event(MatchEvent.Kind.CARD_DESTROYED, {"seat": 1, "card": 25, "slot": 2})
	)
	assert_int(marked.kind).is_equal(BoardStep.Kind.DESTROY)
	assert_float(marked.duration).is_equal_approx(0.35, EPSILON)


func test_turn_end_takes_time_for_the_fly_in_and_count() -> void:
	var end: BoardStep = _one(
		_event(MatchEvent.Kind.TURN_ENDED, {"round": 1, "turn": 1, "scores": [3, 4]})
	)
	assert_int(end.kind).is_equal(BoardStep.Kind.TURN_END)
	assert_float(end.duration).is_equal_approx(0.6, EPSILON)
