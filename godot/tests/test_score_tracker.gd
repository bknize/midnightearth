class_name TestScoreTracker
extends GdUnitTestSuite
## ScoreTracker (R32-R34): after every scoring pulse the tally and multiplier of its side
## equal the pulse's own, over a real seed-1 match's steps.

const SEED: int = 1
const MAX_ACTIONS: int = 2000


func _steps() -> Array[BoardStep]:
	var cards: CardDb = CardDb.load_default()
	var engine: MatchEngine = MatchEngine.create(SEED, cards)
	var collected: Array[MatchEvent] = []
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	collected.append_array(started.events_for(0))
	var bots: Array[GreedyBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(GreedyBot.new(GreedyBot.seed_for(SEED, seat), cards))
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var awaited: int = engine.awaited_seat()
		var action: EngineAction = bots[awaited].choose(engine.view_for(awaited), engine)
		var result: ApplyResult = engine.apply(action)
		assert_bool(result.ok).is_true()
		if not result.ok:
			break
		collected.append_array(result.events_for(0))
		actions += 1
	return BoardSteps.from_events(collected, 1.0)


func _pulse(seat: int, score: int, mult: int) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.PULSE
	step.seat = seat
	step.score = score
	step.mult = mult
	return step


func test_tally_equals_each_pulses_score_over_a_real_match() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	var checked: int = 0
	for step: BoardStep in _steps():
		tracker.apply(step)
		if step.kind == BoardStep.Kind.PULSE and step.score >= 0:
			assert_int(tracker.tally[step.seat]).is_equal(step.score)
			assert_int(tracker.tally_mults[step.seat]).is_equal(step.mult)
			checked += 1
	assert_int(checked).is_greater(0)


func _kind_step(kind: int) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = kind
	return step


func test_held_never_changes_during_a_walk_and_the_tally_follows_pulses() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.held.assign([5, 8])
	tracker.apply(_kind_step(BoardStep.Kind.WALK_START))
	assert_array(tracker.tally).is_equal([0, 0])
	assert_array(tracker.tally_mults).is_equal([100, 100])
	tracker.apply(_pulse(0, 3, 200))
	tracker.apply(_pulse(1, 7, 300))
	tracker.apply(_pulse(0, 9, 400))
	assert_array(tracker.tally).is_equal([9, 7])
	assert_array(tracker.tally_mults).is_equal([400, 300])
	assert_array(tracker.held).is_equal([5, 8])


func test_a_destroyed_pulse_leaves_the_tally_alone() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.apply(_kind_step(BoardStep.Kind.WALK_START))
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.PULSE
	step.seat = 0
	step.destroyed = true
	step.flat = 4
	tracker.apply(step)
	assert_array(tracker.tally).is_equal([0, 0])


func test_a_pulse_without_a_score_leaves_the_tally_alone() -> void:
	# c12's reveal paused on its prompt: no CARD_SCORED yet, so the tally holds (R35).
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.apply(_kind_step(BoardStep.Kind.WALK_START))
	tracker.apply(_pulse(0, 4, 200))
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.PULSE
	step.seat = 0
	step.flat = 4
	step.score = -1
	tracker.apply(step)
	assert_array(tracker.tally).is_equal([4, 0])
	assert_array(tracker.tally_mults).is_equal([200, 100])


func test_turn_end_moves_the_total_into_held_and_clears_the_tally() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.apply(_kind_step(BoardStep.Kind.WALK_START))
	tracker.apply(_pulse(0, 4, 200))
	var end: BoardStep = _kind_step(BoardStep.Kind.TURN_END)
	end.scores.assign([4, 6])
	tracker.apply(end)
	assert_array(tracker.held).is_equal([4, 6])
	assert_array(tracker.tally).is_equal([0, 0])
	assert_array(tracker.tally_mults).is_equal([100, 100])


func test_clear_table_resets_held_and_the_tally() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.held.assign([4, 6])
	tracker.apply(_pulse(0, 4, 200))
	tracker.apply(_kind_step(BoardStep.Kind.CLEAR_TABLE))
	assert_array(tracker.held).is_equal([0, 0])
	assert_array(tracker.tally).is_equal([0, 0])


func test_the_destroyed_piles_count_clears_and_recovers_and_reset_at_the_table_clear() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	var cleared: BoardStep = _kind_step(BoardStep.Kind.CLEAR_DESTROYED)
	cleared.seat = 1
	cleared.pile = true
	tracker.apply(cleared)
	tracker.apply(cleared)
	assert_array(tracker.destroyed).is_equal([0, 2])
	var recovered: BoardStep = _kind_step(BoardStep.Kind.RECOVER)
	recovered.seat = 0
	recovered.from_seat = 1
	tracker.apply(recovered)
	assert_array(tracker.destroyed).is_equal([0, 1])
	var no_pile: BoardStep = _kind_step(BoardStep.Kind.CLEAR_DESTROYED)
	no_pile.seat = 0
	tracker.apply(no_pile)
	assert_array(tracker.destroyed).is_equal([0, 1])
	tracker.apply(_kind_step(BoardStep.Kind.CLEAR_TABLE))
	assert_array(tracker.destroyed).is_equal([0, 0])
