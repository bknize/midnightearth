class_name TestPromptRules
extends GdUnitTestSuite
## PromptRules (plan P19, R55, R56, C16): the glow set per zone and the tap routing, on
## positions only. The prompt is seat 0's, as the board sees it.

const OWN_SIZE: int = 3


func _prompt(zone: int, options: Array[int]) -> Dictionary:
	return {"seat": 0, "card": 5, "verb": "swap_places", "zone": zone, "options": options}


func _view(own_row: int) -> SeatView:
	var view: SeatView = SeatView.new()
	for i: int in range(own_row):
		view.own_board.append(i)
	return view


func _check(spot: CardSpot, seat: int, in_hand: bool, slot: int) -> void:
	assert_int(spot.seat).is_equal(seat)
	assert_bool(spot.in_hand).is_equal(in_hand)
	assert_int(spot.slot).is_equal(slot)


func test_own_hand_glows_hand_positions() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt(Choice.Zone.OWN_HAND, [0, 2]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(2)
	_check(found[0], 0, true, 0)
	_check(found[1], 0, true, 2)


func test_own_board_glows_own_row_slots() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt(Choice.Zone.OWN_BOARD, [1, 2]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(2)
	_check(found[0], 0, false, 1)
	_check(found[1], 0, false, 2)


func test_opponent_hand_is_found_by_fan_index() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt(Choice.Zone.OPPONENT_HAND, [1, 3]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(2)
	_check(found[0], 1, true, 1)
	_check(found[1], 1, true, 3)


func test_opponent_board_glows_the_other_row() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt(Choice.Zone.OPPONENT_BOARD, [0]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(1)
	_check(found[0], 1, false, 0)


func test_both_boards_splits_at_the_own_row_size() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt(Choice.Zone.BOTH_BOARDS, [0, 2, 3, 4]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(4)
	_check(found[0], 0, false, 0)
	_check(found[1], 0, false, 2)
	_check(found[2], 1, false, 0)
	_check(found[3], 1, false, 1)


func test_no_prompt_glows_nothing() -> void:
	var empty: Dictionary = {}
	assert_int(PromptRules.glow_set(empty, _view(OWN_SIZE)).size()).is_equal(0)


func test_tap_on_an_eligible_card_lifts_it_with_the_button() -> void:
	var prompt: Dictionary = _prompt(Choice.Zone.BOTH_BOARDS, [0, 4])
	var own: PromptTap = PromptRules.on_tap(CardSpot.new(0, false, 0), true, prompt, OWN_SIZE)
	assert_int(own.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(own.index).is_equal(0)
	var other: PromptTap = PromptRules.on_tap(CardSpot.new(1, false, 1), true, prompt, OWN_SIZE)
	assert_int(other.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(other.index).is_equal(4)


func test_tap_on_a_face_down_eligible_card_lifts_by_position() -> void:
	var prompt: Dictionary = _prompt(Choice.Zone.OPPONENT_HAND, [2])
	var tap: PromptTap = PromptRules.on_tap(CardSpot.new(1, true, 2), false, prompt, OWN_SIZE)
	assert_int(tap.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(tap.index).is_equal(2)


func test_tap_on_another_eligible_card_while_lifted_swaps_the_lift() -> void:
	var prompt: Dictionary = _prompt(Choice.Zone.BOTH_BOARDS, [0, 4])
	var tap: PromptTap = PromptRules.on_tap(CardSpot.new(1, false, 1), true, prompt, OWN_SIZE, 0)
	assert_int(tap.kind).is_equal(PromptRules.Tap.SWAP_LIFT)
	assert_int(tap.index).is_equal(4)


func test_tap_on_the_lifted_card_or_the_table_puts_it_down() -> void:
	var prompt: Dictionary = _prompt(Choice.Zone.BOTH_BOARDS, [0, 4])
	var same: PromptTap = PromptRules.on_tap(CardSpot.new(0, false, 0), true, prompt, OWN_SIZE, 0)
	assert_int(same.kind).is_equal(PromptRules.Tap.PUT_DOWN)
	var table: PromptTap = PromptRules.on_tap(CardSpot.new(), false, prompt, OWN_SIZE, 0)
	assert_int(table.kind).is_equal(PromptRules.Tap.PUT_DOWN)
	var none: PromptTap = PromptRules.on_tap(null, false, prompt, OWN_SIZE, 4)
	assert_int(none.kind).is_equal(PromptRules.Tap.PUT_DOWN)


func test_tap_on_a_non_eligible_face_up_card_lifts() -> void:
	var prompt: Dictionary = _prompt(Choice.Zone.OWN_BOARD, [1])
	var tap: PromptTap = PromptRules.on_tap(CardSpot.new(0, false, 0), true, prompt, OWN_SIZE)
	assert_int(tap.kind).is_equal(PromptRules.Tap.LIFT)
	var hand: PromptTap = PromptRules.on_tap(CardSpot.new(0, true, 1), true, prompt, OWN_SIZE)
	assert_int(hand.kind).is_equal(PromptRules.Tap.LIFT)


func test_other_taps_do_nothing_when_nothing_is_lifted() -> void:
	var prompt: Dictionary = _prompt(Choice.Zone.OWN_BOARD, [1])
	var down: PromptTap = PromptRules.on_tap(CardSpot.new(1, true, 0), false, prompt, OWN_SIZE)
	assert_int(down.kind).is_equal(PromptRules.Tap.NOTHING)
	var miss: PromptTap = PromptRules.on_tap(CardSpot.new(), true, prompt, OWN_SIZE)
	assert_int(miss.kind).is_equal(PromptRules.Tap.NOTHING)
	var none: PromptTap = PromptRules.on_tap(null, true, prompt, OWN_SIZE)
	assert_int(none.kind).is_equal(PromptRules.Tap.NOTHING)


func test_action_label_names_the_move() -> void:
	assert_str(PromptRules.action_label("swap_places")).is_equal("Swap")
	assert_str(PromptRules.action_label("draw_then_discard")).is_equal("Discard")
	assert_str(PromptRules.action_label("switch_stats")).is_equal("Switch")
	assert_str(PromptRules.action_label("return_at_turn_end")).is_equal("Return")
	assert_str(PromptRules.action_label("nope")).is_equal("")


func test_action_label_reads_the_engine_prompt_verb() -> void:
	# MatchEngine.open_prompt() holds the CardEffect.Verb value, not its name (R41).
	var cases: Dictionary[int, String] = {
		CardEffect.Verb.SWAP_PLACES: "Swap",
		CardEffect.Verb.DRAW_THEN_DISCARD: "Discard",
		CardEffect.Verb.SWITCH_STATS: "Switch",
		CardEffect.Verb.RETURN_AT_TURN_END: "Return",
	}
	for verb: int in cases:
		var prompt: Dictionary = {"seat": 0, "card": 7, "verb": verb, "zone": 0, "options": [1]}
		assert_str(PromptRules.action_label_for(prompt)).is_equal(cases[verb])
	assert_str(PromptRules.action_label_for({})).is_equal("")


func test_the_runner_waits_on_a_prompt_unless_autoplay() -> void:
	var prompt: BoardStep = BoardStep.new()
	prompt.kind = BoardStep.Kind.PROMPT
	var pulse: BoardStep = BoardStep.new()
	pulse.kind = BoardStep.Kind.PULSE
	assert_bool(PromptRules.waits(prompt, false)).is_true()
	assert_bool(PromptRules.waits(prompt, true)).is_false()
	assert_bool(PromptRules.waits(pulse, false)).is_false()
