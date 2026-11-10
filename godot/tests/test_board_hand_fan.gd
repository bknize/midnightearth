class_name TestBoardHandFan
extends GdUnitTestSuite
## The board's fans follow the engine (cycle-9 T11): under rules 7 hands persist across Rounds, so
## CLEAR_TABLE must leave them alone, and every change of the opponent's hand reaches the board
## as a step (DEAL, DRAW, OPPONENT_COMMIT, a hand DISCARD, RETURN). Replays seed 1's autoplay
## match through BoardSteps with the board's own bookkeeping (a count per seat) and compares the
## opponent's fan with SeatView.opponent_hand_count (hand_sizes is the hand LIMIT, not a
## count) after every accepted action.

const SEED: int = 1
const MAX_ACTIONS: int = 2000
const OPPONENT: int = 1

# --- Helpers --------------------------------------------------------------------------


func _driver() -> MatchDriver:
	return MatchDriver.create(
		SEED,
		FixtureDecks.cards(),
		FixtureDecks.decks(),
		FixtureDecks.ids(),
		true,
		"random",
		FixtureDecks.crew()
	)


## The change one step makes to the opponent's fan, as the board applies it.
func _fan_delta(step: BoardStep) -> int:
	match step.kind:
		BoardStep.Kind.DEAL, BoardStep.Kind.DRAW, BoardStep.Kind.RETURN:
			return 1 if step.seat == OPPONENT else 0
		BoardStep.Kind.OPPONENT_COMMIT:
			return -step.count
		BoardStep.Kind.DISCARD:
			return -1 if step.seat == OPPONENT and not step.from_row else 0
	return 0


# --- Tests ----------------------------------------------------------------------------


func test_opponent_fan_follows_the_engine_every_action() -> void:
	var driver: MatchDriver = _driver()
	assert_object(driver).is_not_null()
	var fan: int = 0
	var checked: int = 0
	var clears: int = 0
	var events: Array[MatchEvent] = driver.begin()
	var guard: int = 0
	while guard < MAX_ACTIONS:
		guard += 1
		for step: BoardStep in BoardSteps.from_events(events, 4.0):
			if step.kind == BoardStep.Kind.CLEAR_TABLE:
				clears += 1
			if step.kind == BoardStep.Kind.OPPONENT_COMMIT:
				assert_int(fan).is_greater_equal(step.count)
			fan += _fan_delta(step)
		assert_int(fan).is_equal(driver.view().opponent_hand_count)
		checked += 1
		if driver.is_over() or not driver.bot_turn_due():
			break
		var result: ApplyResult = driver.play_bot()
		assert_bool(result.ok).is_true()
		events = driver.last_events()
	assert_bool(driver.is_over()).is_true()
	assert_int(checked).is_greater(10)
	# Several Rounds were played, so hands lived through at least one table clear.
	assert_int(clears).is_greater(0)
