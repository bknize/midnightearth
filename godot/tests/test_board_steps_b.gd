class_name TestBoardStepsB
extends GdUnitTestSuite
## BoardSteps on the milestone B events (DC-14 T15): CARD_CREATED, CARD_PLACED,
## CONTROL_CHANGED, a Pile-zone prompt and both-seat prompt order.


func _created(seat: int, to: String, slot: int) -> MatchEvent:
	return BoardEvents.make(
		"CARD_CREATED",
		{"seat": seat, "card": 200, "def": "dross", "owner": seat, "to": to, "slot": slot}
	)


func test_a_card_created_in_the_viewers_hand_is_a_draw_with_the_face() -> void:
	var step: BoardStep = BoardEvents.one(_created(0, "hand", -1))
	assert_int(step.kind).is_equal(BoardStep.Kind.DRAW)
	assert_int(step.seat).is_equal(0)
	assert_int(step.card).is_equal(200)
	assert_bool(step.created).is_true()
	assert_str(step.def_id).is_equal("dross")


func test_a_card_created_in_the_opponents_hand_is_a_count() -> void:
	var step: BoardStep = BoardEvents.one(_created(1, "hand", -1))
	assert_int(step.kind).is_equal(BoardStep.Kind.DRAW)
	assert_int(step.seat).is_equal(1)


func test_a_card_created_on_a_row_is_a_create_at_its_slot() -> void:
	var step: BoardStep = BoardEvents.one(_created(0, "row", 2))
	assert_int(step.kind).is_equal(BoardStep.Kind.CREATE)
	assert_int(step.slot).is_equal(2)


func test_a_card_placed_from_a_pile_is_a_placement() -> void:
	var event: MatchEvent = BoardEvents.make(
		"CARD_PLACED", {"seat": 0, "card": 12, "from": "pile", "slot": 3}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.PLACE)
	assert_int(step.card).is_equal(12)
	assert_int(step.slot).is_equal(3)
	assert_int(step.seat).is_equal(0)


func test_a_control_change_moves_the_card_to_the_controllers_row() -> void:
	var event: MatchEvent = BoardEvents.make(
		"CONTROL_CHANGED", {"card": 7, "owner": 1, "controller": 0, "from_seat": 1, "slot": 4}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.CONTROL)
	assert_int(step.seat).is_equal(0)
	assert_int(step.from_seat).is_equal(1)
	assert_int(step.owner).is_equal(1)
	assert_int(step.slot).is_equal(4)


func test_a_pile_zone_prompt_carries_its_zone_for_the_strip() -> void:
	var event: MatchEvent = (
		BoardEvents
		. make(
			"PROMPT_OPENED",
			{
				"seat": 0,
				"card": 5,
				"verb": "revive",
				"zone": "own_pile",
				"options": [0, 2],
				"multi": false,
				"exact": -1,
				"text": "Choose a card in your Pile",
				"step": "D2",
			}
		)
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.PROMPT)
	assert_bool(PromptRules.is_pile_zone(step.zone)).is_true()
	assert_array(step.options).is_equal([0, 2])
	assert_str(PromptRules.action_label("revive")).is_equal("Revive")


func test_the_human_prompt_comes_before_the_bots_answer_in_order() -> void:
	var prompt: MatchEvent = BoardEvents.make(
		"PROMPT_OPENED",
		{"seat": 0, "card": 5, "verb": "quorum", "zone": "own_board", "options": [0, 1, 2]}
	)
	var bot_prompt: MatchEvent = BoardEvents.make(
		"PROMPT_OPENED", {"seat": 1, "card": 5, "verb": "quorum", "zone": "own_board"}
	)
	var answer: MatchEvent = BoardEvents.make(
		"CHOICE_MADE", {"seat": 1, "card": 5, "zone": "own_board", "index": 0, "target": -1}
	)
	var events: Array[MatchEvent] = [prompt, bot_prompt, answer]
	var made: Array[BoardStep] = BoardEvents.steps(events)
	assert_int(made.size()).is_equal(2)
	assert_int(made[0].kind).is_equal(BoardStep.Kind.PROMPT)
	assert_int(made[1].kind).is_equal(BoardStep.Kind.CHOICE_SHOW)


func test_a_multi_prompt_with_an_unknown_verb_still_labels_its_button() -> void:
	assert_str(PromptRules.action_label("quorum", true, false)).is_equal("Select")
	assert_str(PromptRules.action_label("quorum", true, true)).is_equal("Deselect")


func test_the_walk_end_multiply_shows_before_and_after() -> void:
	var tracker: ScoreTracker = ScoreTracker.new()
	var scored: BoardStep = BoardStep.new()
	scored.kind = BoardStep.Kind.PULSE
	scored.seat = 0
	scored.scored = true
	scored.total = 160000
	tracker.apply(scored)
	var ended: BoardStep = BoardStep.new()
	ended.kind = BoardStep.Kind.WALK_END
	ended.totals.assign([120000, 0])
	ended.scores.assign([12, 0])
	tracker.apply(ended)
	assert_int(tracker.pre_end[0]).is_equal(160000)
	assert_int(tracker.tally[0]).is_equal(120000)
	assert_str(RowTally.multiplied_text(160000, 120000)).is_equal("16 → 12")
	assert_str(RowTally.multiplied_text(120000, 120000)).is_equal("12")


func test_a_tithe_grant_lands_next_turn() -> void:
	var event: MatchEvent = BoardEvents.make(
		"ENERGY_GRANTED", {"seat": 0, "amount": 2, "source": 5, "next_turn": true}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.ENERGY_GRANT)
	assert_bool(step.next_turn).is_true()


func test_the_walk_end_reads_the_engines_dross_count() -> void:
	var event: MatchEvent = BoardEvents.make(
		"WALK_ENDED", {"totals": [120000, 0], "scores": [12, 0], "dross": [1, 0]}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.dross[0]).is_equal(1)
	var tracker: ScoreTracker = ScoreTracker.new()
	tracker.tally.assign([160000, 90000])
	tracker.pre_end.assign([170000, 95000])
	var before: Array[int] = tracker.dross_before(step.dross)
	assert_int(before[0]).is_equal(170000)
	assert_int(before[1]).is_equal(90000)


func test_an_exhume_shuffle_lists_its_pile_cards() -> void:
	var event: MatchEvent = BoardEvents.make(
		"PILE_SHUFFLED_IN", {"seat": 1, "count": 1, "pile_cards": [33]}
	)
	var step: BoardStep = BoardEvents.one(event)
	assert_int(step.kind).is_equal(BoardStep.Kind.SHUFFLE_IN)
	assert_int(step.cards[0]).is_equal(33)


func test_a_return_after_its_exit_to_hand_adds_no_step() -> void:
	var resolved: MatchEvent = BoardEvents.make(
		"EXIT_RESOLVED", {"card": 4, "mark": "fleeting", "owner": 0, "to": "hand"}
	)
	var returned: MatchEvent = BoardEvents.make("CARD_RETURNED", {"owner": 0, "card": 4})
	var events: Array[MatchEvent] = [resolved, returned]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0, 0)
	assert_int(steps.size()).is_equal(1)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.EXIT)


## A hidden exit (DC-14 T17): the other seat's redacted EXIT_RESOLVED names the row and the
## card's slot, so the EXIT step carries them (`from_seat`, `slot`), its `seat` the Owner,
## and no mark word.
func test_a_hidden_exit_carries_its_row_and_slot() -> void:
	var payload: Dictionary = {
		"card": 30, "mark": "fleeting", "owner": 1, "to": "hand", "seat": 1, "slot": 2
	}
	var event: MatchEvent = BoardEvents.make("EXIT_RESOLVED", payload, 1)
	var step: BoardStep = BoardEvents.one(event.redacted_for(0))
	assert_int(step.kind).is_equal(BoardStep.Kind.EXIT)
	assert_int(step.card).is_equal(MatchEvent.HIDDEN_CARD)
	assert_int(step.seat).is_equal(1)
	assert_int(step.from_seat).is_equal(1)
	assert_int(step.slot).is_equal(2)
	assert_str(step.exit_to).is_equal("hand")
	assert_str(step.word).is_empty()
