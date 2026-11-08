class_name TestNetCodec
extends FullMatchHarness
## NetCodec and NetProtocol (cycle 12 plan P2, P10, T02): every message kind survives
## encode() -> decode(), with views and events from the real seed-1 match; every malformed
## text decodes to {}; a client message of 16 KiB + 1 byte is refused; action_of, view_of
## and events_of rebuild typed engine objects; the codec reads no clock and no node.

const SEED: int = 1
const STAMP: String = "r7-1a2b3c4d5e6f7a8b"
const CODE: String = "K7QX"

## _samples()'s messages, built once per suite run (each build plays the seed-1 match).
var _sample_cache: Array[Dictionary] = []


## Kept apart from NetCodec.dicts_of(): it is the codec's independent oracle.
func _plain(events: Array[MatchEvent]) -> Array:
	var out: Array = []
	for event: MatchEvent in events:
		out.append(event.to_dict())
	return out


## `message` with its action, view and events read back through the engine's parsers, so
## a to_dict() form (int `looked` keys, typed arrays) and its decoded JSON compare equal.
func _canon(message: Dictionary) -> Dictionary:
	var out: Dictionary = message.duplicate(true)
	if out.has(NetProtocol.KEY_ACTION):
		var action: EngineAction = NetCodec.action_of(out)
		if action != null:
			out[NetProtocol.KEY_ACTION] = action.to_dict()
	if out.has(NetProtocol.KEY_VIEW):
		var view: SeatView = NetCodec.view_of(out)
		if view != null:
			out[NetProtocol.KEY_VIEW] = view.to_dict()
	if out.has(NetProtocol.KEY_EVENTS):
		out[NetProtocol.KEY_EVENTS] = _plain(NetCodec.events_of(out))
	return out


## The seed-1 match played bot against bot, kept as the server would send it to `seat`.
func _seat_match(seat: int) -> SeatMatch:
	var kept: SeatMatch = SeatMatch.new()
	var engine: MatchEngine = _new_engine(SEED)
	var result: ApplyResult = engine.start()
	assert_bool(result.ok).is_true()
	kept.deck_ids.assign(engine.deck_ids())
	kept.start_events = result.events_for(seat)
	kept.start_view = engine.view_for(seat)
	kept.history.append_array(kept.start_events)
	var bots: Array[BotPlayer] = _new_bots(SEED, engine)
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var awaited: int = engine.awaited_seat()
		if awaited < 0 or awaited >= MatchEngine.SEATS:
			break
		result = engine.apply(bots[awaited].choose(engine.view_for(awaited), engine))
		if not result.ok:
			break
		actions += 1
		var step: Array[MatchEvent] = result.events_for(seat)
		kept.history.append_array(step)
		if step.size() > kept.busiest_step.size():
			kept.busiest_step = step
	kept.over = engine.is_over()
	kept.final_view = engine.view_for(seat)
	return kept


func _hello(player_name: String) -> Dictionary:
	return {
		NetProtocol.KEY_T: NetProtocol.T_HELLO,
		NetProtocol.KEY_PROTOCOL: NetProtocol.VERSION,
		NetProtocol.KEY_STAMP: STAMP,
		NetProtocol.KEY_NAME: player_name,
		NetProtocol.KEY_INSTALL_ID: "2f1c0a9e-5b7d-4c3e-8f21-6a4b9d0c7e15",
		NetProtocol.KEY_KIND: NetProtocol.PLAYER_HUMAN,
	}


## One message of every kind, the server's built from seat 1's side of the seed-1 match.
## Callers copy before changing one (_with, _without).
func _samples() -> Array[Dictionary]:
	if _sample_cache.is_empty():
		_sample_cache = _build_samples()
	return _sample_cache


func _build_samples() -> Array[Dictionary]:
	var played: SeatMatch = _seat_match(1)
	var commit: EngineAction = EngineAction.commit(0, [3, 7] as Array[int], [0, 2] as Array[int])
	return [
		_hello("Ben"),
		{NetProtocol.KEY_T: NetProtocol.T_HOST, NetProtocol.KEY_DECK: "greed"},
		{
			NetProtocol.KEY_T: NetProtocol.T_JOIN,
			NetProtocol.KEY_CODE: CODE,
			NetProtocol.KEY_DECK: "ramp",
		},
		{NetProtocol.KEY_T: NetProtocol.T_REJOIN, NetProtocol.KEY_CODE: CODE},
		{
			NetProtocol.KEY_T: NetProtocol.T_ACT,
			NetProtocol.KEY_ACTION: commit.to_dict(),
		},
		{NetProtocol.KEY_T: NetProtocol.T_LEAVE},
		{NetProtocol.KEY_T: NetProtocol.T_PING},
		{NetProtocol.KEY_T: NetProtocol.T_PONG},
		{
			NetProtocol.KEY_T: NetProtocol.T_WELCOME,
			NetProtocol.KEY_PROTOCOL: NetProtocol.VERSION,
			NetProtocol.KEY_STAMP: STAMP,
		},
		{
			NetProtocol.KEY_T: NetProtocol.T_REFUSED,
			NetProtocol.KEY_REASON: NetProtocol.REASON_STAMP_MISMATCH,
			NetProtocol.KEY_DETAIL: "client r7-0000000000000000, server " + STAMP,
		},
		{
			NetProtocol.KEY_T: NetProtocol.T_HOSTED,
			NetProtocol.KEY_CODE: CODE,
			NetProtocol.KEY_EXPIRES_IN_S: 600,
		},
		{
			NetProtocol.KEY_T: NetProtocol.T_STARTED,
			NetProtocol.KEY_SEAT: 1,
			NetProtocol.KEY_OPPONENT: {NetProtocol.KEY_NAME: "Ben", NetProtocol.KEY_DECK: "greed"},
			NetProtocol.KEY_DECKS: played.deck_ids,
			NetProtocol.KEY_VIEW: played.start_view.to_dict(),
			NetProtocol.KEY_EVENTS: _plain(played.start_events),
		},
		{
			NetProtocol.KEY_T: NetProtocol.T_EVENTS,
			NetProtocol.KEY_EVENTS: _plain(played.busiest_step),
			NetProtocol.KEY_VIEW: played.final_view.to_dict(),
		},
		{
			NetProtocol.KEY_T: NetProtocol.T_REJECTED,
			NetProtocol.KEY_ERROR: EngineError.name_of(EngineError.Code.WRONG_SEAT),
			NetProtocol.KEY_ACTION: EngineAction.concede(1).to_dict(),
		},
		{
			NetProtocol.KEY_T: NetProtocol.T_RESYNC,
			NetProtocol.KEY_EVENTS: _plain(played.history),
			NetProtocol.KEY_VIEW: played.final_view.to_dict(),
		},
		{
			NetProtocol.KEY_T: NetProtocol.T_OPPONENT,
			NetProtocol.KEY_STATE: NetProtocol.STATE_LOST,
			NetProtocol.KEY_SECONDS_LEFT: 120,
			NetProtocol.KEY_NAME: "Ben",
		},
		{
			NetProtocol.KEY_T: NetProtocol.T_ABANDONED,
			NetProtocol.KEY_SEAT: 0,
			NetProtocol.KEY_NAME: "Ben"
		},
		{NetProtocol.KEY_T: NetProtocol.T_EXPIRED},
		{
			NetProtocol.KEY_T: NetProtocol.T_CLOSED,
			NetProtocol.KEY_REASON: NetProtocol.REASON_SERVER_ERROR
		},
	]


## The sample of `kind` from _samples().
func _sample(kind: String) -> Dictionary:
	for message: Dictionary in _samples():
		if message[NetProtocol.KEY_T] == kind:
			return message
	return {}


## `message` with `key` set to `value`, as JSON text.
func _with(message: Dictionary, key: String, value: Variant) -> String:
	var out: Dictionary = message.duplicate(true)
	out[key] = value
	return JSON.stringify(out)


## `message` without `key`, as JSON text.
func _without(message: Dictionary, key: String) -> String:
	var out: Dictionary = message.duplicate(true)
	out.erase(key)
	return JSON.stringify(out)


## A hello whose JSON text is exactly `size` bytes, padded in its name.
func _padded_hello(size: int) -> String:
	var message: Dictionary = _hello("")
	var bare: int = JSON.stringify(message).to_utf8_buffer().size()
	message[NetProtocol.KEY_NAME] = "a".repeat(size - bare)
	var text: String = JSON.stringify(message)
	assert_int(text.to_utf8_buffer().size()).is_equal(size)
	return text


# --- Round trips ------------------------------------------------------------------------


func test_every_kind_round_trips() -> void:
	var problems: Array[String] = []
	var seen: Array[String] = []
	for message: Dictionary in _samples():
		var kind: String = message[NetProtocol.KEY_T]
		seen.append(kind)
		var text: String = NetCodec.encode(message)
		if text == "":
			problems.append('%s: encode gave ""' % kind)
			continue
		var back: Dictionary = NetCodec.decode(text)
		if back.is_empty():
			problems.append("%s: decode gave {} (%d bytes)" % [kind, text.to_utf8_buffer().size()])
			continue
		if PvpTable.sorted_json(_canon(back)) != PvpTable.sorted_json(_canon(message)):
			problems.append("%s: round trip differs" % kind)
	_assert_none(problems, "round trips")
	var missing: Array[String] = []
	for kind: String in NetProtocol.CLIENT_KINDS + NetProtocol.SERVER_KINDS:
		if not seen.has(kind):
			missing.append(kind)
	_assert_none(missing, "kinds without a sample")


func test_decoded_numbers_are_ints() -> void:
	var hosted: Dictionary = NetCodec.decode(NetCodec.encode(_sample(NetProtocol.T_HOSTED)))
	assert_int(typeof(hosted[NetProtocol.KEY_EXPIRES_IN_S])).is_equal(TYPE_INT)
	var started: Dictionary = NetCodec.decode(NetCodec.encode(_sample(NetProtocol.T_STARTED)))
	assert_int(typeof(started[NetProtocol.KEY_SEAT])).is_equal(TYPE_INT)
	var hello: Dictionary = NetCodec.decode(NetCodec.encode(_hello("Ben")))
	assert_int(typeof(hello[NetProtocol.KEY_PROTOCOL])).is_equal(TYPE_INT)


func test_whole_floats_read_as_ints() -> void:
	var hosted: Dictionary = NetCodec.decode(
		'{"t": "hosted", "code": "K7QX", "expires_in_s": 600.0}'
	)
	assert_bool(hosted.is_empty()).is_false()
	assert_int(typeof(hosted.get(NetProtocol.KEY_EXPIRES_IN_S))).is_equal(TYPE_INT)
	assert_int(hosted.get(NetProtocol.KEY_EXPIRES_IN_S, -1)).is_equal(600)
	var act: Dictionary = NetCodec.decode('{"t": "act", "action": {"k": "concede", "s": 1.0}}')
	var action: EngineAction = NetCodec.action_of(act)
	assert_object(action).is_not_null()
	if action == null:
		return
	assert_int(action.kind).is_equal(EngineAction.Kind.CONCEDE)
	assert_int(action.seat).is_equal(1)


func test_extra_keys_are_dropped() -> void:
	var back: Dictionary = NetCodec.decode('{"t": "leave", "x": 1}')
	var leave: Dictionary = {NetProtocol.KEY_T: NetProtocol.T_LEAVE}
	assert_str(PvpTable.sorted_json(back)).is_equal(PvpTable.sorted_json(leave))


func test_protocol_names_its_constants() -> void:
	assert_int(NetProtocol.VERSION).is_equal(1)
	assert_int(NetProtocol.MAX_MESSAGE_BYTES).is_equal(16384)
	assert_int(NetProtocol.CLIENT_KINDS.size()).is_equal(7)  # ping: DC-19 review
	assert_int(NetProtocol.SERVER_KINDS.size()).is_equal(12)  # pong: DC-19 review
	# same_install, idle_timeout: NSC-226; too_many_connections, too_many_from_address: DC-19
	assert_int(NetProtocol.REASONS.size()).is_equal(16)
	assert_bool(NetProtocol.is_client_kind(NetProtocol.T_PING)).is_true()
	for kind: String in NetProtocol.CLIENT_KINDS:
		assert_bool(NetProtocol.SERVER_KINDS.has(kind)).is_false()


# --- Malformed --------------------------------------------------------------------------


func test_every_malformed_text_decodes_to_empty() -> void:
	var hello: Dictionary = _hello("Ben")
	var started: Dictionary = _sample(NetProtocol.T_STARTED)
	var events: Dictionary = _sample(NetProtocol.T_EVENTS)
	var act: Dictionary = _sample(NetProtocol.T_ACT)
	var bad_event: Dictionary = {"kind": -5, "owner": -1, "payload": {}}
	var cases: Dictionary[String, String] = {
		"empty text": "",
		"not JSON": "hello there",
		"truncated JSON": NetCodec.encode(hello).left(-3),
		"a list": "[1, 2]",
		"a number": "42",
		"a string": '"hello"',
		"null": "null",
		"an empty object": "{}",
		"no t": _without(hello, NetProtocol.KEY_T),
		"t a number": _with(hello, NetProtocol.KEY_T, 5),
		"unknown t": _with(hello, NetProtocol.KEY_T, "bogus"),
		"hello without install_id": _without(hello, NetProtocol.KEY_INSTALL_ID),
		"hello protocol as text": _with(hello, NetProtocol.KEY_PROTOCOL, "1"),
		"hello protocol fractional": _with(hello, NetProtocol.KEY_PROTOCOL, 1.5),
		"hello protocol negative": _with(hello, NetProtocol.KEY_PROTOCOL, -1),
		"hello protocol a bool": _with(hello, NetProtocol.KEY_PROTOCOL, true),
		"hello unknown player kind": _with(hello, NetProtocol.KEY_KIND, "alien"),
		"hello name a number": _with(hello, NetProtocol.KEY_NAME, 7),
		"host deck null": _with(_sample(NetProtocol.T_HOST), NetProtocol.KEY_DECK, null),
		"join without code": _without(_sample(NetProtocol.T_JOIN), NetProtocol.KEY_CODE),
		"rejoin code a list": _with(_sample(NetProtocol.T_REJOIN), NetProtocol.KEY_CODE, []),
		"act without action": _without(act, NetProtocol.KEY_ACTION),
		"act action text": _with(act, NetProtocol.KEY_ACTION, "concede"),
		"act action unknown kind": _with(act, NetProtocol.KEY_ACTION, {"k": "fly", "s": 0}),
		"act action seat 2": _with(act, NetProtocol.KEY_ACTION, {"k": "concede", "s": 2}),
		"welcome without stamp": _without(_sample(NetProtocol.T_WELCOME), NetProtocol.KEY_STAMP),
		"refused without detail": _without(_sample(NetProtocol.T_REFUSED), NetProtocol.KEY_DETAIL),
		"hosted expiry text":
		_with(_sample(NetProtocol.T_HOSTED), NetProtocol.KEY_EXPIRES_IN_S, "600"),
		"started seat 2": _with(started, NetProtocol.KEY_SEAT, 2),
		"started one deck": _with(started, NetProtocol.KEY_DECKS, ["greed"]),
		"started decks numbers": _with(started, NetProtocol.KEY_DECKS, [1, 2]),
		"started opponent without deck": _with(started, NetProtocol.KEY_OPPONENT, {"name": "Ben"}),
		"started opponent text": _with(started, NetProtocol.KEY_OPPONENT, "Ben"),
		"started empty view": _with(started, NetProtocol.KEY_VIEW, {}),
		"started view a list": _with(started, NetProtocol.KEY_VIEW, []),
		"started bad event": _with(started, NetProtocol.KEY_EVENTS, [bad_event]),
		"events not a list": _with(events, NetProtocol.KEY_EVENTS, {}),
		"events entry text": _with(events, NetProtocol.KEY_EVENTS, ["x"]),
		"events without view": _without(events, NetProtocol.KEY_VIEW),
		"resync without events": _without(_sample(NetProtocol.T_RESYNC), NetProtocol.KEY_EVENTS),
		"rejected unknown error":
		_with(_sample(NetProtocol.T_REJECTED), NetProtocol.KEY_ERROR, "NOPE"),
		"rejected error NONE":
		_with(_sample(NetProtocol.T_REJECTED), NetProtocol.KEY_ERROR, "NONE"),
		"rejected error a code": _with(_sample(NetProtocol.T_REJECTED), NetProtocol.KEY_ERROR, 3),
		"opponent unknown state":
		_with(_sample(NetProtocol.T_OPPONENT), NetProtocol.KEY_STATE, "gone"),
		"opponent negative seconds":
		_with(_sample(NetProtocol.T_OPPONENT), NetProtocol.KEY_SECONDS_LEFT, -1),
		"abandoned seat 3": _with(_sample(NetProtocol.T_ABANDONED), NetProtocol.KEY_SEAT, 3),
		"closed reason a number": _with(_sample(NetProtocol.T_CLOSED), NetProtocol.KEY_REASON, 5),
	}
	var problems: Array[String] = []
	for what: String in cases:
		var back: Dictionary = NetCodec.decode(cases[what])
		if not back.is_empty():
			problems.append(what)
	_assert_none(problems, "decoded although malformed")


func test_encode_refuses_malformed_messages() -> void:
	assert_str(NetCodec.encode({})).is_equal("")
	assert_str(NetCodec.encode({NetProtocol.KEY_T: "bogus"})).is_equal("")
	var hello: Dictionary = _hello("Ben")
	hello.erase(NetProtocol.KEY_STAMP)
	assert_str(NetCodec.encode(hello)).is_equal("")


# --- Size -------------------------------------------------------------------------------


func test_client_message_at_the_cap_decodes() -> void:
	var text: String = _padded_hello(NetProtocol.MAX_MESSAGE_BYTES)
	assert_bool(NetCodec.decode(text).is_empty()).is_false()


func test_client_message_over_the_cap_is_refused() -> void:
	var text: String = _padded_hello(NetProtocol.MAX_MESSAGE_BYTES + 1)
	assert_bool(NetCodec.decode(text).is_empty()).is_true()
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	if not parsed is Dictionary:
		return
	var message: Dictionary = parsed
	assert_str(NetCodec.encode(message)).is_equal("")


func test_cap_counts_bytes_not_characters() -> void:
	var message: Dictionary = _hello("")
	var bare: int = JSON.stringify(message).to_utf8_buffer().size()
	# Two bytes per character: few enough characters, too many bytes.
	var count: int = floori((NetProtocol.MAX_MESSAGE_BYTES + 2 - bare) / 2.0)
	message[NetProtocol.KEY_NAME] = "é".repeat(count)
	var text: String = JSON.stringify(message)
	assert_int(text.length()).is_less_equal(NetProtocol.MAX_MESSAGE_BYTES)
	assert_int(text.to_utf8_buffer().size()).is_greater(NetProtocol.MAX_MESSAGE_BYTES)
	assert_bool(NetCodec.decode(text).is_empty()).is_true()
	assert_str(NetCodec.encode(message)).is_equal("")


## Server kinds may pass the client cap, up to their own.
func test_server_message_cap() -> void:
	var message: Dictionary = {
		NetProtocol.KEY_T: NetProtocol.T_REFUSED,
		NetProtocol.KEY_REASON: NetProtocol.REASON_SERVER_ERROR,
		NetProtocol.KEY_DETAIL: "d".repeat(NetProtocol.MAX_MESSAGE_BYTES * 2),
	}
	var text: String = NetCodec.encode(message)
	assert_int(text.to_utf8_buffer().size()).is_greater(NetProtocol.MAX_MESSAGE_BYTES)
	assert_bool(NetCodec.decode(text).is_empty()).is_false()
	var huge: Dictionary = {
		NetProtocol.KEY_T: NetProtocol.T_CLOSED,
		NetProtocol.KEY_REASON: "r".repeat(NetProtocol.MAX_SERVER_MESSAGE_BYTES),
	}
	assert_str(NetCodec.encode(huge)).is_equal("")
	assert_bool(NetCodec.decode(JSON.stringify(huge)).is_empty()).is_true()


# --- Typed helpers ----------------------------------------------------------------------


func test_action_of_rebuilds_every_action_kind() -> void:
	var actions: Array[EngineAction] = [
		EngineAction.commit(1, [4, 9] as Array[int], [0, 1] as Array[int]),
		EngineAction.choose(0, 1, 2),
		EngineAction.choose_set(1, 1, [0, 2] as Array[int]),
		EngineAction.decline(0),
		EngineAction.concede(1),
	]
	var problems: Array[String] = []
	for action: EngineAction in actions:
		var message: Dictionary = {
			NetProtocol.KEY_T: NetProtocol.T_ACT, NetProtocol.KEY_ACTION: action.to_dict()
		}
		var back: EngineAction = NetCodec.action_of(NetCodec.decode(NetCodec.encode(message)))
		if back == null:
			problems.append("%s: null" % PvpTable.sorted_json(action.to_dict()))
		elif PvpTable.sorted_json(back.to_dict()) != PvpTable.sorted_json(action.to_dict()):
			problems.append("%s: differs" % PvpTable.sorted_json(action.to_dict()))
	_assert_none(problems, "actions")


func test_action_of_bad_shapes_is_null() -> void:
	assert_object(NetCodec.action_of({})).is_null()
	assert_object(NetCodec.action_of({NetProtocol.KEY_ACTION: "concede"})).is_null()
	assert_object(NetCodec.action_of({NetProtocol.KEY_ACTION: {"k": "fly", "s": 0}})).is_null()


func test_view_of_rebuilds_every_seed_1_view() -> void:
	var played: PlayedSteps = _played_steps(SEED)
	assert_bool(played.over).is_true()
	assert_bool(played.views.is_empty()).is_false()
	var problems: Array[String] = []
	for at: int in range(played.views.size()):
		var view: SeatView = played.views[at]
		var message: Dictionary = {
			NetProtocol.KEY_T: NetProtocol.T_EVENTS,
			NetProtocol.KEY_EVENTS: [],
			NetProtocol.KEY_VIEW: view.to_dict(),
		}
		var back: SeatView = NetCodec.view_of(NetCodec.decode(NetCodec.encode(message)))
		if back == null:
			problems.append("view %d: null" % at)
		elif PvpTable.sorted_json(back.to_dict()) != PvpTable.sorted_json(view.to_dict()):
			problems.append("view %d: differs" % at)
	_assert_none(problems, "seed 1 views")


func test_view_of_bad_shapes_is_null() -> void:
	assert_object(NetCodec.view_of({})).is_null()
	assert_object(NetCodec.view_of({NetProtocol.KEY_VIEW: {}})).is_null()
	assert_object(NetCodec.view_of({NetProtocol.KEY_VIEW: "view"})).is_null()


func test_events_of_rebuilds_both_seats_histories() -> void:
	var problems: Array[String] = []
	for seat: int in range(MatchEngine.SEATS):
		var played: SeatMatch = _seat_match(seat)
		assert_bool(played.over).is_true()
		assert_bool(played.start_events.is_empty()).is_false()
		assert_bool(played.busiest_step.is_empty()).is_false()
		var message: Dictionary = {
			NetProtocol.KEY_T: NetProtocol.T_RESYNC,
			NetProtocol.KEY_EVENTS: _plain(played.history),
			NetProtocol.KEY_VIEW: played.final_view.to_dict(),
		}
		var text: String = NetCodec.encode(message)
		if text == "":
			problems.append('seat %d: encode gave ""' % seat)
			continue
		var back: Array[MatchEvent] = NetCodec.events_of(NetCodec.decode(text))
		if back.size() != played.history.size():
			problems.append(
				"seat %d: %d events, not %d" % [seat, back.size(), played.history.size()]
			)
			continue
		for at: int in range(back.size()):
			var event: MatchEvent = played.history[at]
			var got: MatchEvent = back[at]
			if got.kind != event.kind or got.owner_seat != event.owner_seat:
				problems.append("seat %d event %d: kind or owner differs" % [seat, at])
			elif PvpTable.sorted_json(got.to_dict()) != PvpTable.sorted_json(event.to_dict()):
				problems.append("seat %d event %d: differs" % [seat, at])
	_assert_none(problems, "histories")


func test_events_of_bad_shapes_is_empty() -> void:
	var bad_event: Dictionary = {"kind": -5, "owner": -1, "payload": {}}
	var good_event: Dictionary = {"kind": 0, "owner": -1, "payload": {}}
	assert_int(NetCodec.events_of({}).size()).is_equal(0)
	assert_int(NetCodec.events_of({NetProtocol.KEY_EVENTS: "x"}).size()).is_equal(0)
	var mixed: Array = [good_event, bad_event]
	assert_int(NetCodec.events_of({NetProtocol.KEY_EVENTS: mixed}).size()).is_equal(0)
	assert_int(NetCodec.events_of({NetProtocol.KEY_EVENTS: [good_event, 7]}).size()).is_equal(0)
	assert_int(NetCodec.events_of({NetProtocol.KEY_EVENTS: [good_event]}).size()).is_equal(1)


func test_error_of_names_the_engine_code() -> void:
	var back: Dictionary = NetCodec.decode(NetCodec.encode(_sample(NetProtocol.T_REJECTED)))
	assert_int(NetCodec.error_of(back)).is_equal(EngineError.Code.WRONG_SEAT)
	assert_int(NetCodec.error_of({})).is_equal(-1)
	assert_int(NetCodec.error_of({NetProtocol.KEY_ERROR: "NOPE"})).is_equal(-1)


# --- Purity -----------------------------------------------------------------------------


func test_codec_reads_no_clock_and_no_node() -> void:
	var forbidden: RegEx = RegEx.new()
	forbidden.compile("\\bTime\\.|\\bOS\\.|\\bEngine\\.|get_tree|get_node|\\bNode\\b|randi|randf")
	var problems: Array[String] = []
	for path: String in ["res://net/net_codec.gd", "res://net/net_protocol.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		if source == "":
			problems.append(path + ": unreadable")
			continue
		var found: RegExMatch = forbidden.search(source)
		if found != null:
			problems.append("%s: %s" % [path, found.get_string()])
	_assert_none(problems, "clock or node use")


## One seat's side of a played match (_seat_match): what `started`, `events` and `resync`
## carry for it.
class SeatMatch:
	extends RefCounted

	var over: bool = false
	var deck_ids: Array[String] = []
	var start_events: Array[MatchEvent] = []
	var start_view: SeatView = null
	var history: Array[MatchEvent] = []
	var busiest_step: Array[MatchEvent] = []
	var final_view: SeatView = null
