# gdlint: ignore=max-public-methods
class_name TestPromptRules
extends GdUnitTestSuite
## PromptRules (plan P19, R55, R56, C16): the glow set per zone and the tap routing, on
## positions only. The prompt is seat 0's, as the board sees it.

const OWN_SIZE: int = 3


func _prompt(zone: String, options: Array[int]) -> Dictionary:
	return {"seat": 0, "card": 5, "verb": "copy_stats", "zone": zone, "options": options}


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
		_prompt("own_hand", [0, 2]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(2)
	_check(found[0], 0, true, 0)
	_check(found[1], 0, true, 2)


func test_own_board_glows_own_row_slots() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt("own_board", [1, 2]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(2)
	_check(found[0], 0, false, 1)
	_check(found[1], 0, false, 2)


func test_opponent_hand_is_found_by_fan_index() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt("opponent_hand", [1, 3]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(2)
	_check(found[0], 1, true, 1)
	_check(found[1], 1, true, 3)


func test_opponent_board_glows_the_other_row() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt("opponent_board", [0]), _view(OWN_SIZE)
	)
	assert_int(found.size()).is_equal(1)
	_check(found[0], 1, false, 0)


func test_both_boards_splits_at_the_own_row_size() -> void:
	var found: Array[CardSpot] = PromptRules.glow_set(
		_prompt("both_boards", [0, 2, 3, 4]), _view(OWN_SIZE)
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
	var prompt: Dictionary = _prompt("both_boards", [0, 4])
	var own: PromptTap = PromptRules.on_tap(CardSpot.new(0, false, 0), true, prompt, OWN_SIZE)
	assert_int(own.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(own.index).is_equal(0)
	var other: PromptTap = PromptRules.on_tap(CardSpot.new(1, false, 1), true, prompt, OWN_SIZE)
	assert_int(other.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(other.index).is_equal(4)


func test_tap_on_a_face_down_eligible_card_lifts_by_position() -> void:
	var prompt: Dictionary = _prompt("opponent_hand", [2])
	var tap: PromptTap = PromptRules.on_tap(CardSpot.new(1, true, 2), false, prompt, OWN_SIZE)
	assert_int(tap.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(tap.index).is_equal(2)


func test_tap_on_another_eligible_card_while_lifted_swaps_the_lift() -> void:
	var prompt: Dictionary = _prompt("both_boards", [0, 4])
	var tap: PromptTap = PromptRules.on_tap(CardSpot.new(1, false, 1), true, prompt, OWN_SIZE, 0)
	assert_int(tap.kind).is_equal(PromptRules.Tap.SWAP_LIFT)
	assert_int(tap.index).is_equal(4)


func test_tap_on_the_lifted_card_or_the_table_puts_it_down() -> void:
	var prompt: Dictionary = _prompt("both_boards", [0, 4])
	var same: PromptTap = PromptRules.on_tap(CardSpot.new(0, false, 0), true, prompt, OWN_SIZE, 0)
	assert_int(same.kind).is_equal(PromptRules.Tap.PUT_DOWN)
	var table: PromptTap = PromptRules.on_tap(CardSpot.new(), false, prompt, OWN_SIZE, 0)
	assert_int(table.kind).is_equal(PromptRules.Tap.PUT_DOWN)
	var none: PromptTap = PromptRules.on_tap(null, false, prompt, OWN_SIZE, 4)
	assert_int(none.kind).is_equal(PromptRules.Tap.PUT_DOWN)


func test_tap_on_a_non_eligible_face_up_card_lifts() -> void:
	var prompt: Dictionary = _prompt("own_board", [1])
	var tap: PromptTap = PromptRules.on_tap(CardSpot.new(0, false, 0), true, prompt, OWN_SIZE)
	assert_int(tap.kind).is_equal(PromptRules.Tap.LIFT)
	var hand: PromptTap = PromptRules.on_tap(CardSpot.new(0, true, 1), true, prompt, OWN_SIZE)
	assert_int(hand.kind).is_equal(PromptRules.Tap.LIFT)


func test_other_taps_do_nothing_when_nothing_is_lifted() -> void:
	var prompt: Dictionary = _prompt("own_board", [1])
	var down: PromptTap = PromptRules.on_tap(CardSpot.new(1, true, 0), false, prompt, OWN_SIZE)
	assert_int(down.kind).is_equal(PromptRules.Tap.NOTHING)
	var miss: PromptTap = PromptRules.on_tap(CardSpot.new(), true, prompt, OWN_SIZE)
	assert_int(miss.kind).is_equal(PromptRules.Tap.NOTHING)
	var none: PromptTap = PromptRules.on_tap(null, true, prompt, OWN_SIZE)
	assert_int(none.kind).is_equal(PromptRules.Tap.NOTHING)


func test_action_label_names_the_move() -> void:
	assert_str(PromptRules.action_label("copy_stats")).is_equal("Copy")
	assert_str(PromptRules.action_label("discard_own")).is_equal("Discard")
	assert_str(PromptRules.action_label("delve")).is_equal("Take")
	assert_str(PromptRules.action_label("nope")).is_equal("")


func test_action_label_reads_the_engine_prompt_verb() -> void:
	var cases: Dictionary[String, String] = {
		"copy_stats": "Copy",
		"discard_own": "Discard",
		"look_at_opposing": "Look",
	}
	for verb: String in cases:
		var prompt: Dictionary = _prompt("own_hand", [1])
		prompt["verb"] = verb
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


# --- The multi-select, the discard-down and the Pile strip (R78, R80) ----------------------


func _multi_prompt(options: Array[int]) -> Dictionary:
	return {
		"seat": 0,
		"card": 5,
		"verb": "discard_own",
		"zone": "own_hand",
		"options": options,
		"multi": true,
		"exact": -1,
		"min": 0,
	}


func test_tap_on_an_eligible_card_in_a_multi_prompt_lifts_it() -> void:
	var prompt: Dictionary = _multi_prompt([0, 2])
	var tap: PromptTap = PromptRules.on_tap(CardSpot.new(0, true, 2), true, prompt, OWN_SIZE)
	assert_int(tap.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(tap.index).is_equal(2)
	var other: PromptTap = PromptRules.on_tap(CardSpot.new(0, true, 1), true, prompt, OWN_SIZE)
	assert_int(other.kind).is_equal(PromptRules.Tap.LIFT)


func test_the_button_toggles_in_a_multi_prompt_and_chooses_otherwise() -> void:
	var multi: PromptTap = PromptRules.action_tap(_multi_prompt([0, 2]), 2)
	assert_int(multi.kind).is_equal(PromptRules.Tap.TOGGLE_SELECT)
	assert_int(multi.index).is_equal(2)
	var single: PromptTap = PromptRules.action_tap(_prompt("own_hand", [1]), 1)
	assert_int(single.kind).is_equal(PromptRules.Tap.CHOOSE)
	var none: PromptTap = PromptRules.action_tap(_multi_prompt([0]), -1)
	assert_int(none.kind).is_equal(PromptRules.Tap.NOTHING)


func test_toggled_adds_then_removes_a_position() -> void:
	var empty: Array[int] = []
	var one: Array[int] = PromptRules.toggled(empty, 2)
	assert_array(one).is_equal([2])
	var two: Array[int] = PromptRules.toggled(one, 0)
	assert_array(two).is_equal([0, 2])
	var back: Array[int] = PromptRules.toggled(two, 2)
	assert_array(back).is_equal([0])
	assert_array(one).is_equal([2])


func test_action_label_by_verb_and_state() -> void:
	assert_str(PromptRules.action_label("discard_own", true, false)).is_equal("Select")
	assert_str(PromptRules.action_label("discard_own", true, true)).is_equal("Deselect")
	var prompt: Dictionary = _multi_prompt([0])
	assert_str(PromptRules.action_label_for(prompt, false)).is_equal("Select")
	assert_str(PromptRules.action_label_for(prompt, true)).is_equal("Deselect")


func test_the_confirm_text_follows_the_set_size() -> void:
	var prompt: Dictionary = _multi_prompt([0, 1, 2])
	assert_str(PromptRules.confirm_text(prompt, 0)).is_equal("Discard 0")
	assert_str(PromptRules.confirm_text(prompt, 2)).is_equal("Discard 2")


func _discard_down(exact: int) -> Dictionary:
	var prompt: Dictionary = _multi_prompt([0, 1, 2, 3])
	prompt["verb"] = "discard_down"
	prompt["exact"] = exact
	prompt["resume"] = "commit"
	prompt["step"] = "D4"
	return prompt


func test_a_prompt_with_exact_two_enables_confirm_at_two_selected_only() -> void:
	var prompt: Dictionary = _discard_down(2)
	assert_bool(PromptRules.confirm_enabled(prompt, 0)).is_false()
	assert_bool(PromptRules.confirm_enabled(prompt, 1)).is_false()
	assert_bool(PromptRules.confirm_enabled(prompt, 2)).is_true()
	assert_bool(PromptRules.confirm_enabled(prompt, 3)).is_false()


func test_a_prompt_without_exact_accepts_any_size_up_to_the_options() -> void:
	var prompt: Dictionary = _multi_prompt([0, 1, 2])
	assert_bool(PromptRules.confirm_enabled(prompt, 0)).is_true()
	assert_bool(PromptRules.confirm_enabled(prompt, 3)).is_true()
	assert_bool(PromptRules.confirm_enabled(prompt, 4)).is_false()
	prompt["min"] = 1
	assert_bool(PromptRules.confirm_enabled(prompt, 0)).is_false()


## An "up to N" prompt (Exhume, C15 2a): Confirm is on for 0 to `max` selected, and the
## banner reads "Choose up to N".
func test_an_up_to_n_prompt_confirms_zero_to_max_and_says_so() -> void:
	var prompt: Dictionary = _multi_prompt([0, 1, 2, 3])
	prompt["verb"] = "exhume"
	prompt["zone"] = "both_piles"
	prompt["optional"] = true
	prompt["max"] = 2
	assert_bool(PromptRules.confirm_enabled(prompt, 0)).is_true()
	assert_bool(PromptRules.confirm_enabled(prompt, 1)).is_true()
	assert_bool(PromptRules.confirm_enabled(prompt, 2)).is_true()
	assert_bool(PromptRules.confirm_enabled(prompt, 3)).is_false()
	assert_str(PromptRules.banner_for(prompt, "ignored", "")).is_equal(
		"Choose up to 2"
	)


func test_the_discard_down_banner_and_button_read_discard_n() -> void:
	var prompt: Dictionary = _discard_down(2)
	assert_bool(PromptRules.is_discard_down(prompt)).is_true()
	assert_str(PromptRules.banner_for(prompt, "ignored", "")).is_equal("Discard 2")
	assert_str(PromptRules.confirm_text(prompt, 1)).is_equal("Discard 1")
	var other: Dictionary = _multi_prompt([0])
	assert_bool(PromptRules.is_discard_down(other)).is_false()
	assert_str(PromptRules.banner_for(other, "Pick.", "")).is_equal("Pick.")


func test_pile_zones_name_the_seats_whose_piles_the_strip_shows() -> void:
	assert_bool(PromptRules.is_pile_zone(Choice.Zone.OWN_PILE)).is_true()
	assert_bool(PromptRules.is_pile_zone(Choice.Zone.OWN_HAND)).is_false()
	assert_array(PromptRules.pile_seats(Choice.Zone.OWN_PILE, 0)).is_equal([0])
	assert_array(PromptRules.pile_seats(Choice.Zone.OPPONENT_PILE, 0)).is_equal([1])
	assert_array(PromptRules.pile_seats(Choice.Zone.BOTH_PILES, 0)).is_equal([0, 1])
	assert_array(PromptRules.pile_seats(Choice.Zone.OWN_HAND, 0)).is_empty()


func test_every_zone_classifies_as_its_name_did() -> void:
	for zone: int in range(Choice.ZONE_NAMES.size()):
		var label: String = Choice.zone_name(zone)
		assert_bool(PromptRules.is_pile_zone(zone)).is_equal(label.contains("pile"))
		assert_bool(PromptRules.is_deck_top_zone(zone)).is_equal(label == "own_deck_top")
		var seats: Array[int] = PromptRules.pile_seats(zone, 0)
		if not label.contains("pile"):
			assert_array(seats).is_empty()
		elif label.begins_with("own"):
			assert_array(seats).is_equal([0])
		elif label.begins_with("opponent"):
			assert_array(seats).is_equal([1])
		else:
			assert_array(seats).is_equal([0, 1])
	assert_bool(PromptRules.is_pile_zone(Choice.NO_ZONE)).is_false()
	assert_array(PromptRules.pile_seats(Choice.NO_ZONE, 0)).is_empty()


func test_a_pile_prompt_glows_no_row_card_and_routes_strip_entries() -> void:
	var prompt: Dictionary = _prompt("both_piles", [0, 1])
	assert_int(PromptRules.glow_set(prompt, _view(OWN_SIZE)).size()).is_equal(0)
	var lift: PromptTap = PromptRules.route(true, 1, false)
	assert_int(lift.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(lift.index).is_equal(1)
	var swap: PromptTap = PromptRules.route(true, 0, true, 1)
	assert_int(swap.kind).is_equal(PromptRules.Tap.SWAP_LIFT)


func test_an_optional_prompt_wants_the_skip_button_and_a_plain_one_does_not() -> void:
	var plain: Dictionary = _prompt("own_hand", [0])
	assert_bool(PromptRules.wants_skip(plain)).is_false()
	plain["optional"] = false
	assert_bool(PromptRules.wants_skip(plain)).is_false()
	var optional: Dictionary = _prompt("own_hand", [0])
	optional["optional"] = true
	assert_bool(PromptRules.wants_skip(optional)).is_true()


func test_a_crew_prompt_banner_names_the_crew() -> void:
	assert_str(PromptRules.banner_text("Flip one card.", "Shade")).is_equal("Shade: Flip one card.")
	assert_str(PromptRules.banner_text("Swap two cards.", "")).is_equal("Swap two cards.")


func test_a_delve_prompt_names_the_deck_top_and_glows_no_row_card() -> void:
	var prompt: Dictionary = _prompt("own_deck_top", [0, 1, 2])
	assert_str(PromptRules.zone_name_of(prompt)).is_equal("own_deck_top")
	assert_bool(PromptRules.is_deck_top_zone(Choice.Zone.OWN_DECK_TOP)).is_true()
	assert_bool(PromptRules.is_deck_top_zone(Choice.Zone.OWN_HAND)).is_false()
	assert_int(PromptRules.glow_set(prompt, _view(OWN_SIZE)).size()).is_equal(0)
