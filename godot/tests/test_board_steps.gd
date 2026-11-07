# gdlint: ignore=max-public-methods
class_name TestBoardSteps
extends GdUnitTestSuite
## BoardSteps on the v7 events (cycle 9 plan: event table and P17). Events are hand-built by
## Kind name through BoardEvents, so each suite line names the engine key it relies on.

const EPSILON: float = 0.0001


func _scored(card: int, total: int, bonus_value: int = 10000, pass_number: int = 1) -> MatchEvent:
	return BoardEvents.make(
		"CARD_SCORED",
		{
			"seat": 0,
			"card": card,
			"slot": 1,
			"power": 4,
			"bonus_value": bonus_value,
			"total": total,
			"pass": pass_number,
		}
	)


func _revealed(card: int, seat: int = 0) -> MatchEvent:
	return BoardEvents.make(
		"CARD_REVEALED",
		{
			"seat": seat,
			"card": card,
			"slot": 1,
			"power": 4,
			"mult": 125,
			"add": 0,
			"statuses": ["muted"],
			"order": 0,
		}
	)


func test_a_card_scored_yields_a_pulse_with_the_walking_total() -> void:
	var step: BoardStep = BoardEvents.one(_scored(7, 43750, 12500))
	assert_int(step.kind).is_equal(BoardStep.Kind.PULSE)
	assert_bool(step.scored).is_true()
	assert_int(step.total).is_equal(43750)
	assert_int(step.bonus_value).is_equal(12500)
	assert_bool(step.revealed).is_true()
	assert_bool(step.again).is_false()
	assert_array(ScoreChips.chip_texts(step)).is_equal(["+4", "×1.25"])


func test_a_negative_total_is_still_a_scored_pulse() -> void:
	var step: BoardStep = BoardEvents.one(_scored(7, -15000))
	assert_bool(step.scored).is_true()
	assert_int(step.total).is_equal(-15000)
	assert_array(ScoreChips.chip_texts(step)).is_equal(["+4"])


func test_the_second_pass_of_a_card_is_an_again_pulse() -> void:
	assert_bool(BoardEvents.one(_scored(7, 20000, 10000, 2)).again).is_true()


func test_reveal_then_score_is_one_flip_pulse_carrying_the_face() -> void:
	var events: Array[MatchEvent] = [_revealed(7), _scored(7, 50000)]
	var made: Array[BoardStep] = BoardEvents.steps(events)
	assert_int(made.size()).is_equal(1)
	assert_bool(made[0].revealed).is_false()
	assert_int(made[0].power).is_equal(4)
	assert_int(made[0].mult).is_equal(125)
	assert_int(made[0].total).is_equal(50000)
	assert_array(made[0].statuses).is_equal(["Muted"])
	assert_float(made[0].chip_delay).is_equal_approx(BoardSteps.REVEAL_TIME, EPSILON)


func test_a_reveal_with_no_score_is_a_flip_with_no_total() -> void:
	var step: BoardStep = BoardEvents.one(_revealed(7))
	assert_bool(step.scored).is_false()
	assert_array(ScoreChips.chip_texts(step)).is_empty()


func test_exit_to_pile_flies_to_the_owners_pile() -> void:
	var event: MatchEvent = BoardEvents.make(
		"EXIT_RESOLVED", {"card": 9, "mark": "condemned", "owner": 1, "to": "pile"}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.EXIT)
	assert_str(step.exit_to).is_equal("pile")
	assert_int(step.seat).is_equal(1)
	assert_int(step.card).is_equal(9)
	assert_str(step.word).is_equal("Condemned")


func test_exit_to_hand_is_a_return_and_face_down_is_a_flip() -> void:
	var back: BoardStep = BoardEvents.one(
		BoardEvents.make("EXIT_RESOLVED", {"card": 9, "mark": "fleeting", "owner": 0, "to": "hand"})
	)
	assert_str(back.exit_to).is_equal("hand")
	assert_int(back.seat).is_equal(0)
	var flip: BoardStep = BoardEvents.one(
		BoardEvents.make(
			"EXIT_RESOLVED", {"card": 9, "mark": "fade", "owner": 1, "to": "face_down"}
		)
	)
	assert_str(flip.exit_to).is_equal("face_down")


func test_status_set_yields_a_status_step_with_the_word() -> void:
	var set_event: MatchEvent = BoardEvents.make(
		"STATUS_SET", {"card": 5, "status": "muted", "cessation": {}, "cause": "x"}
	)
	var step: BoardStep = BoardEvents.one(set_event)
	assert_int(step.kind).is_equal(BoardStep.Kind.STATUS)
	assert_str(step.word).is_equal("Muted")
	assert_bool(step.status_on).is_true()
	var ended: BoardStep = BoardEvents.one(
		BoardEvents.make("STATUS_ENDED", {"card": 5, "status": "muted", "cause": "turn"})
	)
	assert_bool(ended.status_on).is_false()


func test_a_status_on_a_hidden_card_has_no_step() -> void:
	var event: MatchEvent = BoardEvents.make(
		"STATUS_SET", {"card": MatchEvent.HIDDEN_CARD, "status": "muted", "cause": "x"}
	)
	var events: Array[MatchEvent] = [event]
	assert_int(BoardEvents.steps(events).size()).is_equal(0)


func test_an_exit_mark_is_a_status_step_that_replaces_the_older_mark() -> void:
	var event: MatchEvent = BoardEvents.make(
		"EXIT_MARKED", {"card": 5, "mark": "fade", "replaced": "condemned"}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.STATUS)
	assert_str(step.word).is_equal("Fade")
	assert_str(step.old_word).is_equal("Condemned")


func test_draw_empty_and_shuffle_in_yield_their_steps() -> void:
	var empty: BoardStep = BoardEvents.one(BoardEvents.make("DRAW_EMPTY", {"seat": 1}))
	assert_int(empty.kind).is_equal(BoardStep.Kind.EMPTY_DRAW)
	assert_int(empty.seat).is_equal(1)
	var shuffled: BoardStep = BoardEvents.one(
		BoardEvents.make("PILE_SHUFFLED_IN", {"seat": 0, "count": 6})
	)
	assert_int(shuffled.kind).is_equal(BoardStep.Kind.SHUFFLE_IN)
	assert_int(shuffled.count).is_equal(6)


func test_energy_granted_yields_an_energy_grant_step() -> void:
	var granted: MatchEvent = BoardEvents.make(
		"ENERGY_GRANTED", {"seat": 0, "amount": 1, "source": "dynamo"}
	)
	var step: BoardStep = BoardEvents.one(granted)
	assert_int(step.kind).is_equal(BoardStep.Kind.ENERGY_GRANT)
	assert_int(step.amount).is_equal(1)


func _prompt(seat: int, exact: int) -> MatchEvent:
	return BoardEvents.make(
		"PROMPT_OPENED",
		{
			"seat": seat,
			"card": -1,
			"crew": "",
			"verb": "discard_down",
			"zone": "own_hand",
			"options": [0, 1, 2],
			"multi": true,
			"exact": exact,
			"min": 0,
			"optional": false,
			"resume": "commit",
			"step": "D4",
			"text": "Discard 2",
		}
	)


func test_a_prompt_opened_carries_exact_and_step() -> void:
	var step: BoardStep = BoardEvents.one(_prompt(0, 2))
	assert_int(step.kind).is_equal(BoardStep.Kind.PROMPT)
	assert_int(step.exact).is_equal(2)
	var drain: String = step.step
	assert_str(drain).is_equal("D4")
	assert_bool(step.multi).is_true()
	assert_str(step.zone).is_equal("own_hand")
	assert_array(step.options).is_equal([0, 1, 2])
	assert_float(step.duration).is_equal(0.0)


func test_the_opponents_prompt_has_no_step() -> void:
	var events: Array[MatchEvent] = [_prompt(1, 2)]
	assert_int(BoardEvents.steps(events).size()).is_equal(0)


func test_a_discard_from_a_row_is_flagged_with_its_pile_index() -> void:
	var event: MatchEvent = BoardEvents.make(
		"CARD_DISCARDED",
		{"owner": 1, "card": 9, "from": "row", "reason": "condemned", "pile_index": 3}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.DISCARD)
	assert_int(step.seat).is_equal(1)
	assert_bool(step.from_row).is_true()
	assert_int(step.pile_index).is_equal(3)
	assert_str(step.reason).is_equal("condemned")


func test_an_exhausted_fizzle_keeps_its_reason() -> void:
	var event: MatchEvent = BoardEvents.make(
		"TRIGGER_FIZZLED", {"seat": 0, "card": 4, "crew": "", "verb": "draw", "reason": "exhausted"}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.FIZZLE)
	assert_str(step.reason).is_equal("exhausted")
	assert_str(EffectPlayer.fizzle_note(step.reason)).is_equal("exhausted")
	assert_str(EffectPlayer.fizzle_note("no_target")).is_equal("no target")


func test_a_trigger_fired_lifts_the_card_and_a_crew_trigger_has_no_step() -> void:
	var fired: MatchEvent = BoardEvents.make(
		"TRIGGER_FIRED",
		{"seat": 0, "card": 4, "crew": "", "moment": "on_reveal", "verb": "draw", "resolution": 1}
	)
	var step: BoardStep = BoardEvents.one(fired)
	assert_int(step.kind).is_equal(BoardStep.Kind.EFFECT)
	assert_str(step.trigger).is_equal("on_reveal")
	var crew: MatchEvent = BoardEvents.make(
		"TRIGGER_FIRED",
		{"seat": 0, "card": -1, "crew": "void", "moment": "on_empty_draw", "verb": "x"}
	)
	var events: Array[MatchEvent] = [crew]
	assert_int(BoardEvents.steps(events).size()).is_equal(0)


func test_turn_started_carries_the_viewers_budget() -> void:
	var event: MatchEvent = BoardEvents.make(
		"TURN_STARTED", {"round": 2, "turn": 3, "first_seat": 1, "budgets": [3, 4]}
	)
	var mine: BoardStep = BoardEvents.one(event, 1.0, 0)
	assert_int(mine.kind).is_equal(BoardStep.Kind.TURN_START)
	assert_int(mine.budget).is_equal(3)
	assert_int(mine.turn).is_equal(3)
	assert_int(BoardEvents.one(event, 1.0, 1).budget).is_equal(4)


func test_walk_ended_holds_the_totals_and_the_rounded_scores() -> void:
	var event: MatchEvent = BoardEvents.make(
		"WALK_ENDED", {"totals": [43750, 160000], "scores": [4, 16]}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.WALK_END)
	assert_array(step.totals).is_equal([43750, 160000])
	assert_array(step.scores).is_equal([4, 16])
	assert_float(step.duration).is_equal_approx(BoardSteps.WALK_END_TIME, EPSILON)


func test_turn_ended_carries_scores_wins_and_the_winner() -> void:
	var event: MatchEvent = BoardEvents.make(
		"TURN_ENDED", {"scores": [4, 16], "winner": 1, "wins": [0, 1]}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.TURN_END)
	assert_array(step.scores).is_equal([4, 16])
	assert_int(step.seat).is_equal(1)


func test_a_run_of_moves_is_one_step_with_every_card() -> void:
	var events: Array[MatchEvent] = []
	for i: int in range(3):
		events.append(
			BoardEvents.make(
				"CARD_MOVED",
				{"seat": 0, "card": 10 + i, "from": i, "to": (i + 1) % 3, "cause": "x"}
			)
		)
	var made: Array[BoardStep] = BoardEvents.steps(events, 2.0)
	assert_int(made.size()).is_equal(1)
	assert_int(made[0].kind).is_equal(BoardStep.Kind.MOVE)
	assert_array(made[0].cards).is_equal([10, 11, 12])
	assert_array(made[0].from_slots).is_equal([0, 1, 2])
	assert_array(made[0].slots_to).is_equal([1, 2, 0])
	assert_float(made[0].duration).is_equal_approx(0.3 / 2.0, EPSILON)


func test_a_commit_counts_its_cards_and_the_opponent_waits_for_the_bot() -> void:
	var event: MatchEvent = BoardEvents.make(
		"COMMITTED", {"seat": 1, "cards": [-1, -1], "slots": [0, 1], "cost": 2, "pass": false}, 1
	)
	var committed: Array[MatchEvent] = [event]
	var made: Array[BoardStep] = BoardEvents.steps(committed)
	assert_int(made.size()).is_equal(2)
	assert_int(made[0].kind).is_equal(BoardStep.Kind.BOT_WAIT)
	assert_int(made[1].kind).is_equal(BoardStep.Kind.OPPONENT_COMMIT)
	assert_int(made[1].count).is_equal(2)
	assert_array(made[1].slots).is_equal([0, 1])


func test_every_new_duration_at_speed_four_is_a_quarter() -> void:
	var events: Array[MatchEvent] = [
		BoardEvents.make("DRAW_EMPTY", {"seat": 0}),
		BoardEvents.make("PILE_SHUFFLED_IN", {"seat": 0, "count": 2}),
		BoardEvents.make("ENERGY_GRANTED", {"seat": 0, "amount": 1, "source": "x"}),
		BoardEvents.make("EXIT_RESOLVED", {"card": 1, "mark": "fade", "owner": 0, "to": "pile"}),
	]
	var slow: Array[BoardStep] = BoardEvents.steps(events, 1.0)
	var fast: Array[BoardStep] = BoardEvents.steps(events, 4.0)
	assert_int(fast.size()).is_equal(slow.size())
	for i: int in range(slow.size()):
		assert_float(fast[i].duration).is_equal_approx(slow[i].duration / 4.0, EPSILON)


func test_pile_steps_take_a_quarter_second_over_speed() -> void:
	var shown: BoardStep = BoardSteps.pile_step(true, 4.0)
	assert_int(shown.kind).is_equal(BoardStep.Kind.PILE_SHOW)
	assert_float(shown.duration).is_equal_approx(0.25 / 4.0, EPSILON)
	assert_int(BoardSteps.pile_step(false, 1.0).kind).is_equal(BoardStep.Kind.PILE_HIDE)


func test_a_private_card_looked_is_a_look_step_for_the_looking_seat_only() -> void:
	var event: MatchEvent = BoardEvents.make(
		"CARD_LOOKED", {"seat": 0, "card": 30, "slot": 2, "from_seat": 1}, 0
	)
	var mine: BoardStep = BoardEvents.one(event, 1.0, 0)
	assert_int(mine.kind).is_equal(BoardStep.Kind.LOOK)
	assert_int(mine.slot).is_equal(2)
	assert_int(mine.from_seat).is_equal(1)
	var looked: Array[MatchEvent] = [event]
	assert_int(BoardEvents.steps(looked, 1.0, 1).size()).is_equal(0)
