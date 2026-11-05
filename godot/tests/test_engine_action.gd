class_name TestEngineAction
extends GdUnitTestSuite
## EngineAction: the action kinds (R5; DC-05 adds CHOOSE), copies, and the dictionary
## form the action log stores (R31; format 2 keys, plan "Interfaces and contracts"):
## {"k":"commit","s":0,"c":[3,7],"p":[0,2]}, {"k":"choose","s":1,"z":1,"i":0},
## {"k":"concede","s":1}, and DC-07's set choice {"k":"choose_set","s":0,"z":1,"i":[0,2]}
## (P7), and DC-11's decline {"k":"decline","s":0} (cycle 8 P10). Moved out of
## test_turn.gd when DC-05 T02 grew that suite past the file-length limit.


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func test_exactly_five_action_kinds() -> void:
	# DC-11 T09 (cycle 8 P10) appends DECLINE.
	assert_int(EngineAction.Kind.size()).is_equal(5)
	var cards: Array[int] = [3, 7]
	var slots: Array[int] = [0, 2]
	var commit: EngineAction = EngineAction.commit(0, cards, slots)
	assert_int(commit.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(commit.seat).is_equal(0)
	assert_array(commit.cards).is_equal(cards)
	assert_array(commit.slots).is_equal(slots)
	# The two-argument form is the compatibility default: no slots (append).
	assert_array(EngineAction.commit(0, cards).slots).is_empty()
	var concede: EngineAction = EngineAction.concede(1)
	assert_int(concede.kind).is_equal(EngineAction.Kind.CONCEDE)
	assert_int(concede.seat).is_equal(1)
	assert_array(concede.cards).is_empty()
	assert_array(concede.slots).is_empty()
	var choose: EngineAction = EngineAction.choose(1, 2, 4)
	assert_int(choose.kind).is_equal(EngineAction.Kind.CHOOSE)
	assert_int(choose.seat).is_equal(1)
	assert_int(choose.zone).is_equal(2)
	assert_int(choose.index).is_equal(4)
	assert_array(choose.cards).is_empty()
	assert_array(choose.slots).is_empty()


func test_commit_copies_its_card_and_slot_lists() -> void:
	var cards: Array[int] = [3, 7]
	var slots: Array[int] = [1, 2]
	var commit: EngineAction = EngineAction.commit(0, cards, slots)
	cards.append(9)
	slots.append(5)
	assert_array(commit.cards).is_equal(_typed([3, 7]))
	assert_array(commit.slots).is_equal(_typed([1, 2]))
	var copied: EngineAction = commit.copy()
	commit.slots.append(3)
	assert_array(copied.slots).is_equal(_typed([1, 2]))


func test_action_dict_round_trip() -> void:
	var cards: Array[int] = [7, 3]
	var slots: Array[int] = [0, 2]
	var commit: EngineAction = EngineAction.commit(1, cards, slots)
	var expected_commit: Dictionary = {"k": "commit", "s": 1, "c": [7, 3], "p": [0, 2]}
	assert_dict(commit.to_dict()).is_equal(expected_commit)
	var back: EngineAction = EngineAction.from_dict(commit.to_dict())
	assert_object(back).is_not_null()
	assert_int(back.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(back.seat).is_equal(1)
	assert_array(back.cards).is_equal(cards)
	assert_array(back.slots).is_equal(slots)
	var choose: EngineAction = EngineAction.choose(1, 1, 0)
	var expected_choose: Dictionary = {"k": "choose", "s": 1, "z": 1, "i": 0}
	assert_dict(choose.to_dict()).is_equal(expected_choose)
	var chosen: EngineAction = EngineAction.from_dict(choose.to_dict())
	assert_object(chosen).is_not_null()
	assert_int(chosen.kind).is_equal(EngineAction.Kind.CHOOSE)
	assert_int(chosen.seat).is_equal(1)
	assert_int(chosen.zone).is_equal(1)
	assert_int(chosen.index).is_equal(0)
	var concede: EngineAction = EngineAction.concede(0)
	var expected_concede: Dictionary = {"k": "concede", "s": 0}
	assert_dict(concede.to_dict()).is_equal(expected_concede)
	var conceded: EngineAction = EngineAction.from_dict(concede.to_dict())
	assert_int(conceded.kind).is_equal(EngineAction.Kind.CONCEDE)
	assert_int(conceded.seat).is_equal(0)


func test_action_from_json_style_floats() -> void:
	var parsed: EngineAction = EngineAction.from_dict(
		{"k": "commit", "s": 1.0, "c": [3.0, 27.0], "p": [0.0, 1.0]}
	)
	assert_object(parsed).is_not_null()
	assert_int(parsed.seat).is_equal(1)
	assert_array(parsed.cards).is_equal(_typed([3, 27]))
	assert_array(parsed.slots).is_equal(_typed([0, 1]))
	var choose: EngineAction = EngineAction.from_dict({"k": "choose", "s": 0.0, "z": 3.0, "i": 2.0})
	assert_object(choose).is_not_null()
	assert_int(choose.zone).is_equal(3)
	assert_int(choose.index).is_equal(2)


func test_commit_dict_without_slots_reads_as_the_append_default() -> void:
	# A format-1 entry has no "p": it parses with empty slots (the log then fails replay
	# on its version, test_action_log).
	var parsed: EngineAction = EngineAction.from_dict({"k": "commit", "s": 0, "c": [3]})
	assert_object(parsed).is_not_null()
	assert_array(parsed.cards).is_equal(_typed([3]))
	assert_array(parsed.slots).is_empty()


func test_malformed_action_dicts_give_null() -> void:
	var bad: Array[Dictionary] = [
		{},
		{"k": "commit", "s": 0},
		{"k": "pass", "s": 0, "c": []},
		{"k": 1, "s": 0, "c": []},
		{"k": "commit", "s": 2, "c": []},
		{"k": "commit", "s": -1, "c": []},
		{"k": "commit", "s": 0.5, "c": []},
		{"k": "commit", "s": "0", "c": []},
		{"k": "commit", "s": 0, "c": "3"},
		{"k": "commit", "s": 0, "c": [1.5]},
		{"k": "commit", "s": 0, "c": ["3"]},
		{"k": "concede", "s": 0, "c": []},
		{"s": 0, "c": []},
		{"k": "commit", "s": 0, "c": [], "p": 0},
		{"k": "commit", "s": 0, "c": [3], "p": ["0"]},
		{"k": "commit", "s": 0, "c": [3], "p": [0.5]},
		{"k": "commit", "s": 0, "c": [3], "p": [null]},
		{"k": "commit", "s": 0, "c": [], "z": 0, "i": 0},
		{"k": "concede", "s": 0, "p": []},
		{"k": "concede", "s": 0, "z": 0, "i": 0},
		{"k": "choose", "s": 0},
		{"k": "choose", "s": 0, "z": 1},
		{"k": "choose", "s": 0, "i": 1},
		{"k": "choose", "s": 0, "z": "1", "i": 0},
		{"k": "choose", "s": 0, "z": 1, "i": 0.5},
		{"k": "choose", "s": 0, "z": 1, "i": 0, "c": []},
		{"k": "choose", "s": 0, "z": 1, "i": 0, "p": []},
		{"k": "choose", "s": 2, "z": 1, "i": 0},
	]
	for d: Dictionary in bad:
		assert_object(EngineAction.from_dict(d)).override_failure_message(str(d)).is_null()


func test_out_of_range_float_numbers_give_null() -> void:
	# 2^53 + 2 is the first whole float above EngineAction.MAX_SAFE_FLOAT (2^53).
	var above: float = EngineAction.MAX_SAFE_FLOAT + 2.0
	var bad: Array[Dictionary] = [
		{"k": "commit", "s": 0, "c": [1e30]},
		{"k": "commit", "s": 0, "c": [-1e30]},
		{"k": "commit", "s": 0, "c": [above]},
		{"k": "commit", "s": 0, "c": [-above]},
		{"k": "commit", "s": 0, "c": [3.0, 1e30]},
		{"k": "commit", "s": 1e30, "c": []},
		{"k": "commit", "s": 0, "c": [3], "p": [above]},
		{"k": "concede", "s": -1e30},
		{"k": "choose", "s": 0, "z": 1e30, "i": 0},
		{"k": "choose", "s": 0, "z": 0, "i": -above},
	]
	for d: Dictionary in bad:
		assert_object(EngineAction.from_dict(d)).override_failure_message(str(d)).is_null()


func test_in_range_float_numbers_still_parse() -> void:
	var at_bound: float = EngineAction.MAX_SAFE_FLOAT
	var parsed: EngineAction = EngineAction.from_dict(
		{"k": "commit", "s": 0.0, "c": [3.0, at_bound, -at_bound]}
	)
	assert_object(parsed).is_not_null()
	if parsed != null:
		assert_int(parsed.seat).is_equal(0)
		assert_array(parsed.cards).is_equal(_typed([3, 9007199254740992, -9007199254740992]))


## DC-07 P7: the set choice, its copy and its dictionary form round-trip; the decline (the
## empty set) too, and JSON-style floats parse.
func test_choose_set_round_trips() -> void:
	var indices: Array[int] = [0, 2]
	var chosen: EngineAction = EngineAction.choose_set(0, 1, indices)
	indices.append(5)
	assert_int(chosen.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
	assert_int(chosen.seat).is_equal(0)
	assert_int(chosen.zone).is_equal(1)
	assert_array(chosen.indices).is_equal(_typed([0, 2]))
	assert_array(chosen.cards).is_empty()
	assert_array(chosen.slots).is_empty()
	var expected: Dictionary = {"k": "choose_set", "s": 0, "z": 1, "i": [0, 2]}
	assert_dict(chosen.to_dict()).is_equal(expected)
	var back: EngineAction = EngineAction.from_dict(chosen.to_dict())
	assert_object(back).is_not_null()
	if back == null:
		return
	assert_int(back.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
	assert_int(back.seat).is_equal(0)
	assert_int(back.zone).is_equal(1)
	assert_array(back.indices).is_equal(_typed([0, 2]))
	assert_dict(back.to_dict()).is_equal(expected)
	var copied: EngineAction = chosen.copy()
	chosen.indices.append(3)
	assert_array(copied.indices).is_equal(_typed([0, 2]))
	var declined: EngineAction = EngineAction.choose_set(1, 1, _typed([]))
	var expected_decline: Dictionary = {"k": "choose_set", "s": 1, "z": 1, "i": []}
	assert_dict(declined.to_dict()).is_equal(expected_decline)
	var declined_back: EngineAction = EngineAction.from_dict(expected_decline)
	assert_object(declined_back).is_not_null()
	if declined_back != null:
		assert_array(declined_back.indices).is_empty()
	var floats: EngineAction = EngineAction.from_dict(
		{"k": "choose_set", "s": 1.0, "z": 1.0, "i": [2.0, 0.0]}
	)
	assert_object(floats).is_not_null()
	if floats != null:
		assert_array(floats.indices).is_equal(_typed([2, 0]))
	# The other kinds carry no set.
	assert_array(EngineAction.choose(0, 1, 2).indices).is_empty()


## DC-11 T09 (cycle 8 R52, P10): the decline carries its seat only; it copies and its
## dictionary form {"k":"decline","s":0} round-trips, JSON-style floats included.
func test_decline_round_trips() -> void:
	var declined: EngineAction = EngineAction.decline(1)
	assert_int(declined.kind).is_equal(EngineAction.Kind.DECLINE)
	assert_int(declined.seat).is_equal(1)
	assert_array(declined.cards).is_empty()
	assert_array(declined.slots).is_empty()
	assert_array(declined.indices).is_empty()
	var expected: Dictionary = {"k": "decline", "s": 1}
	assert_dict(declined.to_dict()).is_equal(expected)
	var back: EngineAction = EngineAction.from_dict(expected)
	assert_object(back).is_not_null()
	if back == null:
		return
	assert_int(back.kind).is_equal(EngineAction.Kind.DECLINE)
	assert_int(back.seat).is_equal(1)
	assert_dict(back.to_dict()).is_equal(expected)
	var copied: EngineAction = declined.copy()
	assert_int(copied.kind).is_equal(EngineAction.Kind.DECLINE)
	assert_dict(copied.to_dict()).is_equal(expected)
	var seat_zero: Dictionary = {"k": "decline", "s": 0}
	assert_dict(EngineAction.decline(0).to_dict()).is_equal(seat_zero)
	var floats: EngineAction = EngineAction.from_dict({"k": "decline", "s": 0.0})
	assert_object(floats).is_not_null()
	if floats != null:
		assert_dict(floats.to_dict()).is_equal(seat_zero)


func test_malformed_decline_dicts_give_null() -> void:
	var bad: Array[Dictionary] = [
		{"k": "decline"},
		{"k": "decline", "s": 2},
		{"k": "decline", "s": -1},
		{"k": "decline", "s": 0.5},
		{"k": "decline", "s": "0"},
		{"k": "decline", "s": 0, "c": []},
		{"k": "decline", "s": 0, "p": []},
		{"k": "decline", "s": 0, "z": 0},
		{"k": "decline", "s": 0, "i": 0},
		{"k": "declined", "s": 0},
	]
	for d: Dictionary in bad:
		assert_object(EngineAction.from_dict(d)).override_failure_message(str(d)).is_null()


func test_malformed_choose_set_dicts_give_null() -> void:
	var bad: Array[Dictionary] = [
		{"k": "choose_set", "s": 0},
		{"k": "choose_set", "s": 0, "z": 1},
		{"k": "choose_set", "s": 0, "i": [0]},
		{"k": "choose_set", "s": 0, "z": 1, "i": 0},
		{"k": "choose_set", "s": 0, "z": 1, "i": [0.5]},
		{"k": "choose_set", "s": 0, "z": "1", "i": [0]},
		{"k": "choose_set", "s": 0, "z": 1, "i": ["0"]},
		{"k": "choose_set", "s": 0, "z": 1, "i": [0], "c": []},
		{"k": "choose_set", "s": 0, "z": 1, "i": [0], "p": []},
		{"k": "choose_set", "s": 2, "z": 1, "i": [0]},
	]
	for d: Dictionary in bad:
		assert_object(EngineAction.from_dict(d)).override_failure_message(str(d)).is_null()
