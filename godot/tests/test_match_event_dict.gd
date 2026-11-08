class_name TestMatchEventDict
extends FullMatchHarness
## MatchEvent.from_dict() and EngineError.name_of() (cycle 12 plan P3, T01): every event of
## the seed-1 match, in full and as each seat's redacted copy, survives to_dict() ->
## from_dict() -> to_dict(); JSON floats read back as ints; a bad kind, owner or payload
## reads as null; name_of() names each code and gives "" out of range.

const SEED: int = 1
# Two forms compare as PvpTable.sorted_json() text, key order aside.


func _assert_null(d: Dictionary, what: String) -> void:
	var event: MatchEvent = MatchEvent.from_dict(d)
	assert_object(event).override_failure_message("not null: " + what).is_null()


# --- Round trips ------------------------------------------------------------------------


func test_every_seed_1_event_round_trips() -> void:
	var played: PlayedSteps = _played_steps(SEED)
	assert_bool(played.over).is_true()
	assert_bool(played.events.is_empty()).is_false()
	var problems: Array[String] = []
	for at: int in range(played.events.size()):
		var event: MatchEvent = played.events[at]
		var dict: Dictionary = event.to_dict()
		var back: MatchEvent = MatchEvent.from_dict(dict)
		if back == null:
			problems.append("event %d: from_dict gave null" % at)
			continue
		if back.kind != event.kind or back.owner_seat != event.owner_seat:
			problems.append("event %d: kind or owner differs" % at)
		if PvpTable.sorted_json(back.to_dict()) != PvpTable.sorted_json(dict):
			problems.append("event %d: round trip differs" % at)
	_assert_none(problems, "seed 1 events")


func test_seed_1_has_private_and_redacted_events() -> void:
	var played: PlayedSteps = _played_steps(SEED)
	var private_count: int = 0
	var hidden_count: int = 0
	for event: MatchEvent in played.events:
		if event.is_private():
			private_count += 1
			if event.payload.get(MatchEvent.KEY_CARD, 0) == MatchEvent.HIDDEN_CARD:
				hidden_count += 1
	assert_int(private_count).is_greater(0)
	assert_int(hidden_count).is_greater(0)


func test_json_floats_read_as_ints() -> void:
	var event: MatchEvent = MatchEvent.new(
		MatchEvent.Kind.COMMITTED, {"seat": 1, "cards": [3, 4], "nested": {"cost": 2}}, 1
	)
	var parsed: Variant = JSON.parse_string(JSON.stringify(event.to_dict()))
	assert_bool(parsed is Dictionary).is_true()
	if not parsed is Dictionary:
		return
	var json_dict: Dictionary = parsed
	var back: MatchEvent = MatchEvent.from_dict(json_dict)
	assert_object(back).is_not_null()
	if back == null:
		return
	assert_int(back.kind).is_equal(MatchEvent.Kind.COMMITTED)
	assert_int(back.owner_seat).is_equal(1)
	assert_str(PvpTable.sorted_json(back.to_dict())).is_equal(PvpTable.sorted_json(event.to_dict()))
	var cards: Array = back.payload["cards"]
	assert_int(typeof(cards[0])).is_equal(TYPE_INT)
	var nested: Dictionary = back.payload["nested"]
	assert_int(typeof(nested["cost"])).is_equal(TYPE_INT)


func test_fractional_payload_numbers_stay_floats() -> void:
	var back: MatchEvent = MatchEvent.from_dict(
		{"kind": 0.0, "owner": -1.0, "payload": {"x": 1.5}}
	)
	assert_object(back).is_not_null()
	if back == null:
		return
	assert_int(back.kind).is_equal(MatchEvent.Kind.MATCH_STARTED)
	assert_int(back.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_int(typeof(back.payload["x"])).is_equal(TYPE_FLOAT)


func test_rebuilt_payload_is_a_copy() -> void:
	var payload: Dictionary = {"cards": [1, 2]}
	var back: MatchEvent = MatchEvent.from_dict({"kind": 8, "owner": 0, "payload": payload})
	assert_object(back).is_not_null()
	if back == null:
		return
	var cards: Array = payload["cards"]
	cards.append(3)
	var kept: Array = back.payload["cards"]
	assert_int(kept.size()).is_equal(2)


# --- Malformed shapes -------------------------------------------------------------------


func test_null_on_missing_keys() -> void:
	_assert_null({}, "empty")
	_assert_null({"owner": -1, "payload": {}}, "no kind")
	_assert_null({"kind": 0, "payload": {}}, "no owner")
	_assert_null({"kind": 0, "owner": -1}, "no payload")


func test_null_on_bad_kind() -> void:
	_assert_null({"kind": -1, "owner": -1, "payload": {}}, "kind -1")
	var past: int = MatchEvent.Kind.size()
	_assert_null({"kind": past, "owner": -1, "payload": {}}, "kind past the enum")
	_assert_null({"kind": 2.5, "owner": -1, "payload": {}}, "fractional kind")
	_assert_null({"kind": "MATCH_STARTED", "owner": -1, "payload": {}}, "kind as text")
	_assert_null({"kind": null, "owner": -1, "payload": {}}, "null kind")


func test_null_on_bad_owner() -> void:
	_assert_null({"kind": 0, "owner": 2, "payload": {}}, "owner 2")
	_assert_null({"kind": 0, "owner": -2, "payload": {}}, "owner -2")
	_assert_null({"kind": 0, "owner": "0", "payload": {}}, "owner as text")
	_assert_null({"kind": 0, "owner": 0.5, "payload": {}}, "fractional owner")


func test_null_on_bad_payload() -> void:
	_assert_null({"kind": 0, "owner": -1, "payload": []}, "payload as a list")
	_assert_null({"kind": 0, "owner": -1, "payload": "x"}, "payload as text")
	_assert_null({"kind": 0, "owner": -1, "payload": null}, "null payload")


# --- EngineError.name_of ----------------------------------------------------------------


func test_name_of_names_each_code() -> void:
	assert_str(EngineError.name_of(EngineError.Code.WRONG_SEAT)).is_equal("WRONG_SEAT")
	assert_str(EngineError.name_of(EngineError.Code.NONE)).is_equal("NONE")
	assert_str(EngineError.name_of(EngineError.Code.NOT_OPTIONAL)).is_equal("NOT_OPTIONAL")
	for key: Variant in EngineError.Code.keys():
		var code_name: String = key
		var code: int = EngineError.Code[code_name]
		assert_str(EngineError.name_of(code)).is_equal(code_name)


func test_name_of_is_empty_out_of_range() -> void:
	assert_str(EngineError.name_of(-1)).is_empty()
	assert_str(EngineError.name_of(EngineError.Code.size())).is_empty()
