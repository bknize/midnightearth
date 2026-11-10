class_name TestPromptHost
extends GdUnitTestSuite
## PromptHost (DC-15 C5): a tap on a Pile count does nothing while the open prompt chooses
## from the strip, so the prompt keeps its options. The host is bare (no table, no strip
## parent): a guard that let the tap through would try to build a strip and fail.


func _host_with(zone: String) -> PromptHost:
	var host: PromptHost = PromptHost.new()
	host._prompt = {"seat": 0, "card": 5, "verb": "revive", "zone": zone, "options": [0]}
	return host


func test_a_pile_tap_is_ignored_while_a_pile_prompt_is_open() -> void:
	for zone: String in ["own_pile", "opponent_pile", "both_piles"]:
		var host: PromptHost = _host_with(zone)
		host.toggle_pile(0, SeatView.new())
		assert_bool(host.strip_up()).override_failure_message(zone).is_false()
		assert_bool(host.is_open()).override_failure_message(zone).is_true()


func test_a_pile_tap_is_ignored_while_a_deck_top_prompt_is_open() -> void:
	var host: PromptHost = _host_with("own_deck_top")
	host.toggle_pile(1, SeatView.new())
	assert_bool(host.strip_up()).is_false()
	assert_bool(host.is_open()).is_true()


## Seat 1's prompt (the joiner, viewer 1) lands on the player's own side of the table, and each
## spot maps back to the engine's own option (cycle-12 T13 B1).
func test_a_seat_one_prompt_resolves_to_the_players_own_cards() -> void:
	var own_size: int = 2
	for zone: String in ["own_hand", "own_board"]:
		var engine_prompt: Dictionary = {
			"seat": 1, "card": 5, "verb": "discard_own", "zone": zone, "options": [0, 1]
		}
		var table: Dictionary = PromptHost.table_prompt(engine_prompt, 1)
		var found: Array[CardSpot] = PromptRules.spots(table, own_size)
		assert_int(found.size()).override_failure_message(zone).is_equal(2)
		for i: int in range(found.size()):
			assert_int(found[i].seat).override_failure_message(zone).is_equal(BoardSteps.OWN_SIDE)
			assert_bool(found[i].in_hand).is_equal(zone == "own_hand")
			assert_int(PromptRules.option_at(found[i], table, own_size)).is_equal(i)
		# The engine's prompt is untouched: answers go back with its own values.
		var engine_seat: int = engine_prompt["seat"]
		assert_int(engine_seat).is_equal(1)


func test_a_seat_one_both_boards_prompt_splits_at_the_players_row() -> void:
	var engine_prompt: Dictionary = {
		"seat": 1, "card": 5, "verb": "pin", "zone": "both_boards", "options": [0, 3]
	}
	var table: Dictionary = PromptHost.table_prompt(engine_prompt, 1)
	var found: Array[CardSpot] = PromptRules.spots(table, 2)
	assert_int(found.size()).is_equal(2)
	assert_int(found[0].seat).is_equal(0)
	assert_int(found[0].slot).is_equal(0)
	assert_int(found[1].seat).is_equal(1)
	assert_int(found[1].slot).is_equal(1)
	assert_int(PromptRules.option_at(found[1], table, 2)).is_equal(3)


## A tap on the player's own hand card (table seat 0) answers seat 1's discard-down prompt;
## the opponent's card at the same position does not.
func test_a_seat_one_tap_on_the_players_card_finds_its_option() -> void:
	var host: PromptHost = PromptHost.new()
	host.viewer = 1
	host._prompt = {
		"seat": 1, "card": 5, "verb": "discard_down", "zone": "own_hand", "options": [2]
	}
	host._table_prompt = PromptHost.table_prompt(host._prompt, 1)
	var routed: PromptTap = PromptRules.on_tap(CardSpot.new(0, true, 2), true, host._table_prompt, 0)
	assert_int(routed.kind).is_equal(PromptRules.Tap.LIFT_ELIGIBLE)
	assert_int(routed.index).is_equal(2)
	var wrong: PromptTap = PromptRules.on_tap(CardSpot.new(1, true, 2), true, host._table_prompt, 0)
	assert_int(wrong.kind).is_equal(PromptRules.Tap.LIFT)


func test_a_seat_zero_prompt_is_unchanged_for_viewer_zero() -> void:
	var engine_prompt: Dictionary = {"seat": 0, "zone": "own_hand", "options": [1]}
	assert_dict(PromptHost.table_prompt(engine_prompt, 0)).is_equal(engine_prompt)
