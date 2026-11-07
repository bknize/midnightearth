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
