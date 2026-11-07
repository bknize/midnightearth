class_name TestBoardStepsMult
extends GdUnitTestSuite
## BoardSteps' DC-07 beats (R44-R50, plan P16): the hundredths mult chips, grouped moves,
## unreveal, the strip steps and (rules 7, DC-13 T03) a return to its Owner's hand. Events
## are built by hand.

const EPSILON: float = 0.0001


func _event(kind: int, payload: Dictionary) -> MatchEvent:
	return MatchEvent.new(kind, payload, MatchEvent.PUBLIC)


func _one(event: MatchEvent, speed: float = 1.0, viewer: int = 0) -> BoardStep:
	var events: Array[MatchEvent] = [event]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, speed, viewer)
	assert_int(steps.size()).is_equal(1)
	return steps[0]


func _scored_with(times: int, plus: int, mult: int) -> MatchEvent:
	return _event(
		MatchEvent.Kind.CARD_SCORED,
		{
			"seat": 0,
			"card": 4,
			"slot": 1,
			"flat": 4,
			"times": times,
			"plus": plus,
			"mult": mult,
			"added": 5,
			"score": 5,
			"again": false,
		}
	)


func test_a_times_score_yields_a_mult_chip_then_the_added_chip() -> void:
	var step: BoardStep = _one(_scored_with(125, 0, 125))
	assert_int(step.times).is_equal(125)
	assert_int(step.mult).is_equal(125)
	assert_array(ScoreChips.chip_texts(step)).is_equal(["×1.25", "+5"])


func test_a_vanilla_score_yields_only_the_added_chip() -> void:
	var step: BoardStep = _one(_scored_with(100, 0, 100))
	assert_array(ScoreChips.chip_texts(step)).is_equal(["+5"])


func test_a_run_of_moves_is_one_step_with_every_card() -> void:
	var events: Array[MatchEvent] = []
	for i: int in range(3):
		var payload: Dictionary = {
			"seat": 0, "card": 10 + i, "from_slot": i, "to_slot": (i + 1) % 3
		}
		events.append(_event(MatchEvent.Kind.CARD_MOVED, payload))
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 2.0)
	assert_int(steps.size()).is_equal(1)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.MOVE)
	assert_array(steps[0].cards).is_equal([10, 11, 12])
	assert_array(steps[0].from_slots).is_equal([0, 1, 2])
	assert_array(steps[0].slots_to).is_equal([1, 2, 0])
	assert_float(steps[0].duration).is_equal_approx(0.3 / 2.0, EPSILON)


func test_moves_of_two_seats_are_two_steps() -> void:
	var events: Array[MatchEvent] = [
		_event(MatchEvent.Kind.CARD_MOVED, {"seat": 0, "card": 1, "from_slot": 0, "to_slot": 1}),
		_event(MatchEvent.Kind.CARD_MOVED, {"seat": 1, "card": 2, "from_slot": 0, "to_slot": 1}),
	]
	assert_int(BoardSteps.from_events(events, 1.0).size()).is_equal(2)


func test_unreveal_step() -> void:
	var unrevealed: int = MatchEvent.Kind.CARD_UNREVEALED
	var flip: BoardStep = _one(_event(unrevealed, {"seat": 1, "card": 25, "slot": 2}), 2.0)
	assert_int(flip.kind).is_equal(BoardStep.Kind.UNREVEAL)
	assert_int(flip.slot).is_equal(2)
	assert_float(flip.duration).is_equal_approx(0.35 / 2.0, EPSILON)


## Rules 7 (DC-13 T03): a card going to its Owner's hand (CARD_RETURNED {owner, card}) is a
## RETURN step for that Owner; nothing is recovered from a destroyed pile any more.
func test_a_return_names_its_owner() -> void:
	var back: BoardStep = _one(
		_event(MatchEvent.Kind.CARD_RETURNED, {"owner": 0, "card": 25}), 2.0
	)
	assert_int(back.kind).is_equal(BoardStep.Kind.RETURN)
	assert_int(back.seat).is_equal(0)
	assert_int(back.card).is_equal(25)
	assert_float(back.duration).is_equal_approx(0.3 / 2.0, EPSILON)
	assert_bool(MatchEvent.Kind.keys().has("CARD_RECOVERED")).is_false()


func test_strip_steps_take_a_quarter_second_over_speed() -> void:
	var shown: BoardStep = BoardSteps.strip_step(true, 4.0)
	assert_int(shown.kind).is_equal(BoardStep.Kind.STRIP_SHOW)
	assert_float(shown.duration).is_equal_approx(0.25 / 4.0, EPSILON)
	assert_int(BoardSteps.strip_step(false, 1.0).kind).is_equal(BoardStep.Kind.STRIP_HIDE)


func test_a_stats_change_carries_times_and_plus() -> void:
	var step: BoardStep = _one(
		_event(
			MatchEvent.Kind.STATS_CHANGED,
			{"seat": 0, "card": 3, "flat": 1, "times": 125, "plus": 1, "cause": "copy"}
		)
	)
	assert_int(step.times).is_equal(125)
	assert_int(step.plus).is_equal(1)
