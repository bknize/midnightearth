class_name TestPlayoutProtocol
extends GdUnitTestSuite
## PlayoutProtocol and PlayoutHandler (cycle 11 R25 to R29, R31, plan P9, T05): request
## parsing, reply field order, the digest, and the handler called as a function.


## The length of `value`, an Array held as a Variant.
func _size(value: Variant) -> int:
	var listed: Array = value
	return listed.size()


func _play_line(extra: Dictionary = {}) -> String:
	var d: Dictionary = {"id": 1, "kind": "play", "seed": 5, "decks": [], "generator": "random"}
	d.merge(extra, true)
	return JSON.stringify(d)


func _label_line(extra: Dictionary = {}) -> String:
	var d: Dictionary = {
		"id": "a",
		"kind": "label",
		"seed": 5,
		"decks": [],
		"actions": [],
		"seat": 0,
		"k": 2,
		"determinizations": 2,
		"rollout": "random",
		"label_seed": 9,
	}
	d.merge(extra, true)
	return JSON.stringify(d)


func _without(line: String, key: String) -> String:
	var parsed: Variant = JSON.parse_string(line)
	var d: Dictionary = parsed
	assert_bool(d.erase(key)).is_true()
	return JSON.stringify(d)


func test_valid_play_request() -> void:
	var request: Dictionary = PlayoutProtocol.parse_request(_play_line())
	assert_bool(request.has("error")).is_false()
	assert_str(request["kind"]).is_equal("play")
	assert_int(request["seed"]).is_equal(5)
	assert_int(_size(request["decks"])).is_equal(0)
	assert_str(request["generator"]).is_equal("random")


func test_play_accepts_two_decks_and_a_text_seed() -> void:
	var line: String = _play_line({"decks": ["a", "b"], "seed": "9007199254740993"})
	var request: Dictionary = PlayoutProtocol.parse_request(line)
	assert_bool(request.has("error")).is_false()
	assert_int(request["seed"]).is_equal(9007199254740993)
	assert_int(_size(request["decks"])).is_equal(2)


func test_play_field_errors() -> void:
	for key: String in ["id", "seed", "decks", "generator"]:
		var request: Dictionary = PlayoutProtocol.parse_request(_without(_play_line(), key))
		assert_bool(request.has("error")).is_true()
	var wrong: Array[Dictionary] = [
		{"seed": "x"},
		{"seed": 1.5},
		{"decks": ["a"]},
		{"decks": [1, 2]},
		{"decks": "ab"},
		{"generator": 3},
		{"generator": "nope"},
		{"id": null},
	]
	for extra: Dictionary in wrong:
		var request: Dictionary = PlayoutProtocol.parse_request(_play_line(extra))
		assert_bool(request.has("error")).is_true()


func test_unparseable_lines_and_kinds_are_errors() -> void:
	assert_bool(PlayoutProtocol.parse_request("{nope").has("error")).is_true()
	assert_bool(PlayoutProtocol.parse_request("[1]").has("error")).is_true()
	assert_bool(PlayoutProtocol.parse_request('{"id": 1}').has("error")).is_true()
	assert_bool(PlayoutProtocol.parse_request('{"id": 1, "kind": "dance"}').has("error")).is_true()
	var bad: Dictionary = PlayoutProtocol.parse_request('{"id": 7, "kind": "dance"}')
	assert_int(bad["id"]).is_equal(7)


func test_quit_request() -> void:
	var request: Dictionary = PlayoutProtocol.parse_request('{"kind": "quit"}')
	assert_bool(request.has("error")).is_false()
	assert_str(request["kind"]).is_equal("quit")
	assert_bool(PlayoutHandler.is_quit('{"kind": "quit"}')).is_true()
	assert_bool(PlayoutHandler.is_quit(_play_line())).is_false()


func test_valid_label_request_with_k() -> void:
	var request: Dictionary = PlayoutProtocol.parse_request(_label_line())
	assert_bool(request.has("error")).is_false()
	assert_str(request["id"]).is_equal("a")
	assert_int(request["k"]).is_equal(2)
	assert_int(_size(request["candidates"])).is_equal(0)
	assert_int(request["seat"]).is_equal(0)
	assert_int(request["determinizations"]).is_equal(2)
	assert_int(request["label_seed"]).is_equal(9)


func test_valid_label_request_with_candidates() -> void:
	var commit: Dictionary = {"k": "commit", "s": 0, "c": [1, 2], "p": [0, 1]}
	var line: String = _without(_label_line({"candidates": [commit]}), "k")
	var request: Dictionary = PlayoutProtocol.parse_request(line)
	assert_bool(request.has("error")).is_false()
	assert_int(request["k"]).is_equal(0)
	assert_int(_size(request["candidates"])).is_equal(1)


func test_label_field_errors() -> void:
	for key: String in [
		"id", "seed", "decks", "actions", "seat", "k", "determinizations", "rollout", "label_seed"
	]:
		var request: Dictionary = PlayoutProtocol.parse_request(_without(_label_line(), key))
		assert_bool(request.has("error")).is_true()
	var wrong: Array[Dictionary] = [
		{"seat": 2},
		{"seat": "0"},
		{"k": 0},
		{"k": "2"},
		{"determinizations": 0},
		{"rollout": "nope"},
		{"actions": "x"},
		{"actions": [5]},
		{"actions": [{"k": "dance"}]},
		{"label_seed": 1.5},
		{"candidates": []},
		{"candidates": [{"k": "commit", "s": 1, "c": [], "p": []}]},
	]
	for extra: Dictionary in wrong:
		var request: Dictionary = PlayoutProtocol.parse_request(_label_line(extra))
		assert_bool(request.has("error")).is_true()


func test_label_with_neither_k_nor_candidates_is_an_error() -> void:
	var request: Dictionary = PlayoutProtocol.parse_request(_without(_label_line(), "k"))
	assert_bool(request.has("error")).is_true()


func test_reply_field_order() -> void:
	var hello: Dictionary = PlayoutProtocol.hello_reply("r7-x", 7, 5, "4.6")
	assert_array(hello.keys()).is_equal(["hello", "stamp", "rules", "format", "godot"])
	var played: Dictionary = PlayoutProtocol.play_reply(1, "s", {}, {}, [[], []], 3)
	assert_array(played.keys()).is_equal(["id", "stamp", "log", "result", "commits", "us"])
	var labelled: Dictionary = PlayoutProtocol.label_reply(1, "s", 4, [], [], 0, 3)
	assert_array(labelled.keys()).is_equal(
		["id", "stamp", "legal", "candidates", "values", "rollouts", "us"]
	)
	var result: Dictionary = PlayoutProtocol.result_object(0, [2, 1], 3, "wins")
	assert_array(result.keys()).is_equal(["winner", "wins", "rounds", "reason"])
	assert_array(PlayoutProtocol.error_reply(1, "no").keys()).is_equal(["id", "error"])
	var line: String = PlayoutProtocol.encode(played)
	assert_bool(line.begins_with('{"id":1,"stamp":"s","log"')).is_true()


func test_digest_drops_us_and_godot() -> void:
	var first: Array[String] = [
		PlayoutProtocol.encode(PlayoutProtocol.hello_reply("s", 7, 5, "4.6.3")),
		PlayoutProtocol.encode(PlayoutProtocol.label_reply(1, "s", 4, [], [], 0, 111)),
	]
	var second: Array[String] = [
		PlayoutProtocol.encode(PlayoutProtocol.hello_reply("s", 7, 5, "9.9")),
		PlayoutProtocol.encode(PlayoutProtocol.label_reply(1, "s", 4, [], [], 0, 999)),
	]
	var other: Array[String] = [
		PlayoutProtocol.encode(PlayoutProtocol.hello_reply("s", 7, 5, "4.6.3")),
		PlayoutProtocol.encode(PlayoutProtocol.label_reply(1, "s", 5, [], [], 0, 111)),
	]
	assert_str(PlayoutProtocol.digest(first)).is_equal(PlayoutProtocol.digest(second))
	assert_str(PlayoutProtocol.digest(first)).is_not_equal(PlayoutProtocol.digest(other))
	assert_int(PlayoutProtocol.digest(first).length()).is_equal(64)
	var stripped: Dictionary = PlayoutProtocol.strip_timing(
		PlayoutProtocol.label_reply(1, "s", 4, [], [], 0, 5)
	)
	assert_bool(stripped.has("us")).is_false()
	assert_bool(stripped.has("legal")).is_true()


func test_a_prefix_that_does_not_replay_gives_an_error_reply() -> void:
	var handler: PlayoutHandler = PlayoutHandler.load_default()
	assert_object(handler).is_not_null()
	if handler == null:
		return
	var bad: Dictionary = {"k": "commit", "s": 0, "c": [9999], "p": [0]}
	var reply: Dictionary = handler.handle_line(_label_line({"actions": [bad]}))
	assert_array(reply.keys()).is_equal(["id", "error"])
	assert_str(reply["id"]).is_equal("a")
	assert_str(reply["error"]).contains("prefix action 0")


func test_a_malformed_line_gives_an_error_reply() -> void:
	var handler: PlayoutHandler = PlayoutHandler.load_default()
	assert_object(handler).is_not_null()
	if handler == null:
		return
	var reply: Dictionary = handler.handle_line("{nope")
	assert_bool(reply.has("error")).is_true()
	assert_bool(handler.handle_line('{"kind": "quit"}').is_empty()).is_true()


func test_play_then_label_a_logged_position() -> void:
	var handler: PlayoutHandler = PlayoutHandler.load_default()
	assert_object(handler).is_not_null()
	if handler == null:
		return
	var played: Dictionary = handler.handle_line(_play_line())
	assert_bool(played.has("error")).is_false()
	assert_array(played.keys()).is_equal(["id", "stamp", "log", "result", "commits", "us"])
	var log: Dictionary = played["log"]
	var actions: Array = log["actions"]
	var commits: Array = played["commits"]
	var by_seat: Array = commits[0]
	assert_int(by_seat.size()).is_greater(0)
	var at: int = by_seat[by_seat.size() >> 1]
	var line: String = _label_line({"actions": actions.slice(0, at), "seat": 0})
	var first: Dictionary = handler.handle_line(line)
	var again: Dictionary = handler.handle_line(line)
	assert_bool(first.has("error")).is_false()
	assert_int(first["rollouts"]).is_equal(_size(first["candidates"]) * 2)
	assert_int(_size(first["values"])).is_equal(_size(first["candidates"]))
	assert_str(first["stamp"]).is_equal(played["stamp"])
	assert_str(PlayoutProtocol.digest([PlayoutProtocol.encode(first)])).is_equal(
		PlayoutProtocol.digest([PlayoutProtocol.encode(again)])
	)
