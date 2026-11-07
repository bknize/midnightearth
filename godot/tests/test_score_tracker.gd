class_name TestScoreTracker
extends GdUnitTestSuite
## ScoreTracker (R77, R78, plan P17): the walking total follows each scoring pulse, the Walk end
## sets the HUD Score, the turn end settles it, and the Pile counts follow Discards and shuffles.
## Steps are hand-built.


func _pulse(seat: int, total: int, scored: bool = true) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.PULSE
	step.seat = seat
	step.total = total
	step.scored = scored
	return step


func _kind_step(kind: int, seat: int = 0) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = kind
	step.seat = seat
	return step


func test_the_tally_follows_each_scoring_pulse_per_seat() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.apply(_kind_step(BoardStep.Kind.WALK_START))
	tracker.apply(_pulse(0, 43750))
	tracker.apply(_pulse(1, -15000))
	assert_array(tracker.tally).is_equal([43750, -15000])
	tracker.apply(_pulse(0, 160000))
	assert_array(tracker.tally).is_equal([160000, -15000])


func test_a_pulse_with_no_score_leaves_the_tally_alone() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.apply(_pulse(0, 20000))
	tracker.apply(_pulse(0, 0, false))
	assert_array(tracker.tally).is_equal([20000, 0])


func test_the_hud_score_is_held_until_the_walk_end() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.apply(_kind_step(BoardStep.Kind.WALK_START))
	tracker.apply(_pulse(0, 43750))
	assert_array(tracker.held).is_equal([0, 0])
	var walk_end: BoardStep = _kind_step(BoardStep.Kind.WALK_END)
	walk_end.scores.assign([4, 16])
	walk_end.totals.assign([43750, 160000])
	tracker.apply(walk_end)
	assert_array(tracker.held).is_equal([4, 16])
	assert_array(tracker.tally).is_equal([43750, 160000])


func test_turn_end_settles_the_scores_and_clears_the_tally() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.apply(_pulse(0, 43750))
	var turn_end: BoardStep = _kind_step(BoardStep.Kind.TURN_END)
	turn_end.scores.assign([4, 16])
	tracker.apply(turn_end)
	assert_array(tracker.held).is_equal([4, 16])
	assert_array(tracker.tally).is_equal([0, 0])


func test_clear_table_clears_the_tally_but_not_the_piles() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.apply(_pulse(0, 20000))
	var discard: BoardStep = _kind_step(BoardStep.Kind.DISCARD, 1)
	discard.pile_index = 2
	tracker.apply(discard)
	tracker.apply(_kind_step(BoardStep.Kind.CLEAR_TABLE))
	assert_array(tracker.tally).is_equal([0, 0])
	assert_array(tracker.piles).is_equal([0, 3])


func test_a_discard_sets_the_pile_count_from_its_index_and_a_shuffle_in_empties_it() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	for index: int in range(3):
		var discard: BoardStep = _kind_step(BoardStep.Kind.DISCARD, 0)
		discard.pile_index = index
		tracker.apply(discard)
	assert_array(tracker.piles).is_equal([3, 0])
	var shuffle: BoardStep = _kind_step(BoardStep.Kind.SHUFFLE_IN, 0)
	shuffle.count = 3
	tracker.apply(shuffle)
	assert_array(tracker.piles).is_equal([0, 0])


func test_reset_clears_everything() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	var discard: BoardStep = _kind_step(BoardStep.Kind.DISCARD, 1)
	discard.pile_index = 0
	tracker.apply(discard)
	tracker.apply(_pulse(0, 5000))
	tracker.reset()
	assert_array(tracker.piles).is_equal([0, 0])
	assert_array(tracker.tally).is_equal([0, 0])
	assert_array(tracker.held).is_equal([0, 0])
