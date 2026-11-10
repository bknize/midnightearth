class_name TestMatchRoom
extends GdUnitTestSuite
## MatchRoom (cycle 12 T03; plan P4, P10, P11; spec B, D, E, F) on a fake clock with two
## fake clients (PvpTable): host, join and start; a full random-bot match through act();
## seat forcing (R34); rejection changes nothing (R40); reconnect with the right and the
## wrong install id (R46, R48); abandonment at 120 s (R49, R50); Leave (R19, R26, R27);
## expiry (R13); linger (R39); the per-seat history equals the concatenated redactions; the
## log record's Data model fields.

const SEED: int = 7
const LATE_CONN: int = 303
const WRONG_ID: Dictionary = {"name": "Eve", "install_id": "install-eve", "kind": "human"}
const ENGINE_REASONS: Array[String] = [
	MatchEngine.REASON_WINS,
	MatchEngine.REASON_ROUNDS,
	MatchEngine.REASON_SUDDEN_DEATH,
	MatchEngine.REASON_STALEMATE,
	MatchEngine.REASON_CONCEDE,
]
const LOG_KEYS: Array[String] = [
	"match_id",
	"room",
	"mode",
	"stamp",
	"rules",
	"log_format",
	"protocol",
	"build",
	"players",
	"decks",
	"started_at",
	"ended_at",
	"end",
	"complete",
	"disconnects",
	"log",
]


func _started() -> PvpTable:
	var table: PvpTable = PvpTable.create(SEED)
	table.start()
	return table


func _kinds(entries: Array[PvpTable.Sent]) -> Array[String]:
	var out: Array[String] = []
	for entry: PvpTable.Sent in entries:
		out.append(entry.kind)
	return out


func _event_kinds(entry: PvpTable.Sent) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in NetCodec.events_of(entry.message):
		out.append(event.kind)
	return out


## The payload of the first event of `kind` in `entry`; {} when none.
func _payload_of(entry: PvpTable.Sent, kind: int) -> Dictionary:
	for event: MatchEvent in NetCodec.events_of(entry.message):
		if event.kind == kind:
			return event.payload
	return {}


func _actions_logged(room: MatchRoom) -> int:
	var record: Dictionary = room.log_record()
	var logged: Dictionary = record.get("log", {})
	var actions: Array = logged.get("actions", [])
	return actions.size()


# --- Host, join, start ----------------------------------------------------------------


func test_host_answers_hosted_with_the_code_and_the_expiry() -> void:
	var table: PvpTable = PvpTable.create(SEED)
	var out: Array[PvpTable.Sent] = table.host()
	assert_array(_kinds(out)).is_equal([NetProtocol.T_HOSTED])
	assert_int(out[0].conn).is_equal(PvpTable.HOST_CONN)
	assert_str(out[0].message[NetProtocol.KEY_CODE]).is_equal("K7QX")
	assert_int(out[0].message[NetProtocol.KEY_EXPIRES_IN_S]).is_equal(600)
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.WAITING)
	assert_dict(table.room.log_record()).is_empty()


func test_join_starts_the_match_host_in_seat_0_joiner_in_seat_1() -> void:
	var table: PvpTable = PvpTable.create(SEED)
	table.host("greed")
	var out: Array[PvpTable.Sent] = table.join("ramp")
	assert_array(_kinds(out)).is_equal([NetProtocol.T_STARTED, NetProtocol.T_STARTED])
	assert_array(table.unencodable).is_empty()
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.RUNNING)
	var names: Array[String] = ["bot:random", "Ana"]
	var decks: Array[String] = ["ramp", "greed"]
	for seat: int in range(MatchEngine.SEATS):
		var entry: PvpTable.Sent = out[seat]
		assert_int(entry.conn).is_equal(table.conns[seat])
		assert_int(entry.message[NetProtocol.KEY_SEAT]).is_equal(seat)
		var opponent: Dictionary = entry.message[NetProtocol.KEY_OPPONENT]
		assert_str(opponent[NetProtocol.KEY_NAME]).is_equal(names[seat])
		assert_str(opponent[NetProtocol.KEY_DECK]).is_equal(decks[seat])
		assert_array(entry.message[NetProtocol.KEY_DECKS]).is_equal(["greed", "ramp"])
		assert_int(table.views[seat].seat).is_equal(seat)
		assert_bool(_event_kinds(entry).has(MatchEvent.Kind.MATCH_STARTED)).is_true()
	assert_int(table.awaited_seat()).is_not_equal(-1)


func test_join_refusals() -> void:
	var table: PvpTable = PvpTable.create(SEED)
	var unhosted: Array[PvpTable.Sent] = table.join()
	assert_str(unhosted[0].message[NetProtocol.KEY_REASON]).is_equal(
		NetProtocol.REASON_UNKNOWN_ROOM
	)
	table.room.allowed_decks.assign(["greed", "ramp"])
	var bad_deck: Array[PvpTable.Sent] = table.host("nonsense")
	assert_str(bad_deck[0].message[NetProtocol.KEY_REASON]).is_equal(
		NetProtocol.REASON_BAD_MESSAGE
	)
	table.host()
	var twice: Array[PvpTable.Sent] = table.host()
	assert_str(twice[0].message[NetProtocol.KEY_REASON]).is_equal(NetProtocol.REASON_BAD_MESSAGE)
	table.join()
	var third: Array[PvpTable.Sent] = table.take(
		table.room.join(LATE_CONN, WRONG_ID, "greed", table.now_ms)
	)
	assert_array(_kinds(third)).is_equal([NetProtocol.T_REFUSED])
	assert_int(third[0].conn).is_equal(LATE_CONN)
	assert_str(third[0].message[NetProtocol.KEY_REASON]).is_equal(NetProtocol.REASON_ROOM_FULL)


func test_join_after_ten_minutes_is_refused_room_expired() -> void:
	var table: PvpTable = PvpTable.create(SEED)
	table.host()
	table.now_ms = PvpTable.T0_MS + MatchRoom.ROOM_EXPIRY_MS
	var out: Array[PvpTable.Sent] = table.join()
	assert_str(out[0].message[NetProtocol.KEY_REASON]).is_equal(NetProtocol.REASON_ROOM_EXPIRED)


## Two clients on one device share its install id; a join from the host's own id is refused,
## since a rejoin could not tell the two seats apart (cycle-12 T13 S7). The room keeps waiting
## and a joiner from another device still starts it.
func test_join_from_the_hosts_install_id_is_refused_same_install() -> void:
	var table: PvpTable = PvpTable.create(SEED)
	table.host()
	var twin: Dictionary = {"name": "Ana 2", "install_id": "install-ana", "kind": "human"}
	var out: Array[PvpTable.Sent] = table.take(
		table.room.join(LATE_CONN, twin, "ramp", table.now_ms)
	)
	assert_array(_kinds(out)).is_equal([NetProtocol.T_REFUSED])
	assert_int(out[0].conn).is_equal(LATE_CONN)
	assert_str(out[0].message[NetProtocol.KEY_REASON]).is_equal(NetProtocol.REASON_SAME_INSTALL)
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.WAITING)
	assert_int(table.room.seat_of(LATE_CONN)).is_equal(-1)
	var joined: Array[PvpTable.Sent] = table.join()
	assert_array(_kinds(joined)).is_equal([NetProtocol.T_STARTED, NetProtocol.T_STARTED])


# --- Playing --------------------------------------------------------------------------


func test_a_full_random_bot_match_ends_and_each_history_is_its_redactions() -> void:
	var table: PvpTable = _started()
	var played: int = table.play_to_end()
	assert_array(table.unencodable).is_empty()
	assert_int(played).is_greater(0)
	assert_int(played).is_less(PvpTable.MAX_ACTIONS)
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.FINISHED)
	assert_int(table.awaited_seat()).is_equal(-1)
	for seat: int in range(MatchEngine.SEATS):
		var history: Array[Dictionary] = table.room.history_of(seat)
		assert_str(PvpTable.sorted_json(table.events[seat])).is_equal(PvpTable.sorted_json(history))
	var record: Dictionary = table.room.log_record()
	assert_bool(record["complete"]).is_true()
	var end: Dictionary = record["end"]
	var reason: String = end["reason"]
	assert_bool(ENGINE_REASONS.has(reason)).is_true()
	assert_int(_actions_logged(table.room)).is_equal(played)
	var parsed: ActionLog = ActionLog.from_json(JSON.stringify(record["log"]))
	assert_object(parsed).is_not_null()
	if parsed == null:
		return
	var crew: CrewPool = CrewPool.load_default()
	var replayed: ReplayResult = parsed.replay(
		CardDb.load_default(), DeckList.load_default(), crew
	)
	assert_bool(replayed.ok).is_true()
	assert_int(replayed.engine.accepted_action_count()).is_equal(played)


func test_a_concede_naming_the_other_seat_concedes_the_senders_seat() -> void:
	for sender: int in range(MatchEngine.SEATS):
		var table: PvpTable = _started()
		var other: int = 1 - sender
		var out: Array[PvpTable.Sent] = table.act(sender, EngineAction.concede(other))
		assert_array(_kinds(out)).is_equal([NetProtocol.T_EVENTS, NetProtocol.T_EVENTS])
		var conceded: Dictionary = _payload_of(out[0], MatchEvent.Kind.CONCEDED)
		assert_int(conceded.get("seat", -1)).is_equal(sender)
		var ended: Dictionary = _payload_of(out[0], MatchEvent.Kind.MATCH_ENDED)
		assert_int(ended.get("winner", -1)).is_equal(other)
		var record: Dictionary = table.room.log_record()
		var end: Dictionary = record["end"]
		assert_int(end["winner"]).is_equal(other)
		assert_str(end["reason"]).is_equal(MatchEngine.REASON_CONCEDE)
		var logged: Dictionary = record["log"]
		var actions: Array = logged["actions"]
		var first: Dictionary = actions[0]
		assert_int(first[EngineAction.KEY_SEAT]).is_equal(sender)


func test_a_commit_from_the_seat_not_awaited_is_rejected_and_changes_nothing() -> void:
	var table: PvpTable = _started()
	var awaited: int = table.awaited_seat()
	assert_int(awaited).is_not_equal(-1)
	var idle: int = 1 - awaited
	var revision: int = table.room.revision()
	var sizes: Array[int] = [table.room.history_of(0).size(), table.room.history_of(1).size()]
	var none: Array[int] = []
	# Naming the awaited seat changes nothing: the room acts for the sender.
	var out: Array[PvpTable.Sent] = table.act(idle, EngineAction.commit(awaited, none, none))
	assert_array(_kinds(out)).is_equal([NetProtocol.T_REJECTED])
	assert_int(out[0].conn).is_equal(table.conns[idle])
	assert_str(out[0].message[NetProtocol.KEY_ERROR]).is_equal("WRONG_SEAT")
	var echoed: EngineAction = NetCodec.action_of(out[0].message)
	assert_int(echoed.seat).is_equal(idle)
	assert_int(table.room.revision()).is_equal(revision)
	assert_int(table.room.history_of(0).size()).is_equal(sizes[0])
	assert_int(table.room.history_of(1).size()).is_equal(sizes[1])
	assert_int(_actions_logged(table.room)).is_equal(0)


func test_act_from_a_connection_without_a_seat_is_bad_message() -> void:
	var table: PvpTable = _started()
	var out: Array[PvpTable.Sent] = table.take(
		table.room.act(LATE_CONN, EngineAction.concede(0), table.now_ms)
	)
	assert_array(_kinds(out)).is_equal([NetProtocol.T_REFUSED])
	assert_str(out[0].message[NetProtocol.KEY_REASON]).is_equal(NetProtocol.REASON_BAD_MESSAGE)
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.RUNNING)


# --- Disconnects ----------------------------------------------------------------------


func test_reconnect_with_the_right_install_id_resyncs_the_seat() -> void:
	var table: PvpTable = _started()
	for _i: int in range(6):
		table.play_one()
	table.now_ms += 1000
	var lost: Array[PvpTable.Sent] = table.take(
		table.room.connection_lost(PvpTable.JOIN_CONN, table.now_ms)
	)
	assert_array(_kinds(lost)).is_equal([NetProtocol.T_OPPONENT])
	assert_int(lost[0].conn).is_equal(PvpTable.HOST_CONN)
	assert_str(lost[0].message[NetProtocol.KEY_STATE]).is_equal(NetProtocol.STATE_LOST)
	assert_int(lost[0].message[NetProtocol.KEY_SECONDS_LEFT]).is_equal(120)
	assert_str(lost[0].message[NetProtocol.KEY_NAME]).is_equal("bot:random")
	table.now_ms += 40000
	table.conns[1] = LATE_CONN
	var back: Array[PvpTable.Sent] = table.take(
		table.room.rejoin(LATE_CONN, PvpTable.JOIN_ID, table.now_ms)
	)
	assert_array(_kinds(back)).is_equal([NetProtocol.T_OPPONENT, NetProtocol.T_RESYNC])
	assert_int(back[0].conn).is_equal(PvpTable.HOST_CONN)
	assert_str(back[0].message[NetProtocol.KEY_STATE]).is_equal(NetProtocol.STATE_BACK)
	assert_int(back[1].conn).is_equal(LATE_CONN)
	var history: Array[Dictionary] = table.room.history_of(1)
	var sent_events: String = PvpTable.sorted_json(back[1].message[NetProtocol.KEY_EVENTS])
	assert_str(sent_events).is_equal(PvpTable.sorted_json(history))
	assert_int(NetCodec.view_of(back[1].message).seat).is_equal(1)
	assert_int(table.room.seat_of(LATE_CONN)).is_equal(1)
	assert_int(table.room.seat_of(PvpTable.JOIN_CONN)).is_equal(-1)
	var record: Dictionary = table.room.log_record()
	var disconnects: Array = record["disconnects"]
	assert_int(disconnects.size()).is_equal(1)
	var entry: Dictionary = disconnects[0]
	assert_int(entry["seat"]).is_equal(1)
	assert_bool(entry["reconnected"]).is_true()
	assert_str(entry["at"]).is_equal("2026-11-07T21:45:13Z")
	# The rejoined seat plays on, and the window no longer runs.
	assert_int(table.play_to_end()).is_greater(0)
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.FINISHED)


func test_reconnect_with_a_wrong_install_id_is_refused() -> void:
	var table: PvpTable = _started()
	table.take(table.room.connection_lost(PvpTable.JOIN_CONN, table.now_ms))
	var out: Array[PvpTable.Sent] = table.take(
		table.room.rejoin(LATE_CONN, WRONG_ID, table.now_ms)
	)
	assert_array(_kinds(out)).is_equal([NetProtocol.T_REFUSED])
	assert_int(out[0].conn).is_equal(LATE_CONN)
	assert_str(out[0].message[NetProtocol.KEY_REASON]).is_equal(
		NetProtocol.REASON_WRONG_INSTALL_ID
	)
	assert_int(table.room.seat_of(LATE_CONN)).is_equal(-1)
	# The host's install id names the host's seat, which is still attached: it hands over.
	var host_again: Array[PvpTable.Sent] = table.take(
		table.room.rejoin(LATE_CONN, PvpTable.HOST_ID, table.now_ms)
	)
	assert_array(_kinds(host_again)).is_equal([NetProtocol.T_CLOSED, NetProtocol.T_RESYNC])
	assert_int(table.room.seat_of(LATE_CONN)).is_equal(0)


func test_a_seat_dropped_for_120_s_abandons_the_match() -> void:
	var table: PvpTable = _started()
	for _i: int in range(4):
		table.play_one()
	var actions: int = _actions_logged(table.room)
	var dropped_at: int = table.now_ms + 5000
	table.take(table.room.connection_lost(PvpTable.JOIN_CONN, dropped_at))
	var early: Array[PvpTable.Sent] = table.take(
		table.room.tick(dropped_at + MatchRoom.RECONNECT_WINDOW_MS - 1)
	)
	assert_array(early).is_empty()
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.RUNNING)
	var out: Array[PvpTable.Sent] = table.take(
		table.room.tick(dropped_at + MatchRoom.RECONNECT_WINDOW_MS)
	)
	assert_array(_kinds(out)).is_equal([NetProtocol.T_ABANDONED])
	assert_int(out[0].conn).is_equal(PvpTable.HOST_CONN)
	assert_int(out[0].message[NetProtocol.KEY_SEAT]).is_equal(1)
	assert_str(out[0].message[NetProtocol.KEY_NAME]).is_equal("bot:random")
	assert_bool(table.room.is_closed()).is_true()
	var record: Dictionary = table.room.log_record()
	var end: Dictionary = record["end"]
	assert_str(end["reason"]).is_equal(MatchRoom.END_ABANDONED)
	assert_int(end["winner"]).is_equal(-1)
	assert_bool(record["complete"]).is_false()
	assert_str(record["ended_at"]).is_not_empty()
	assert_int(_actions_logged(table.room)).is_equal(actions)
	var late: Array[PvpTable.Sent] = table.take(
		table.room.rejoin(LATE_CONN, PvpTable.JOIN_ID, table.now_ms)
	)
	assert_str(late[0].message[NetProtocol.KEY_REASON]).is_equal(NetProtocol.REASON_UNKNOWN_ROOM)


func test_both_seats_dropped_abandon_with_nobody_told() -> void:
	var table: PvpTable = _started()
	table.take(table.room.connection_lost(PvpTable.HOST_CONN, table.now_ms))
	table.take(table.room.connection_lost(PvpTable.JOIN_CONN, table.now_ms + 1000))
	var out: Array[PvpTable.Sent] = table.take(
		table.room.tick(table.now_ms + MatchRoom.RECONNECT_WINDOW_MS)
	)
	assert_array(out).is_empty()
	assert_bool(table.room.is_closed()).is_true()
	var record: Dictionary = table.room.log_record()
	var end: Dictionary = record["end"]
	assert_str(end["reason"]).is_equal(MatchRoom.END_ABANDONED)


# --- Leave, expiry, linger ------------------------------------------------------------


func test_leave_while_running_concedes_for_the_leaver() -> void:
	var table: PvpTable = _started()
	var out: Array[PvpTable.Sent] = table.take(
		table.room.leave(PvpTable.HOST_CONN, table.now_ms)
	)
	assert_array(_kinds(out)).is_equal([NetProtocol.T_EVENTS])
	assert_int(out[0].conn).is_equal(PvpTable.JOIN_CONN)
	var ended: Dictionary = _payload_of(out[0], MatchEvent.Kind.MATCH_ENDED)
	assert_int(ended.get("winner", -1)).is_equal(1)
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.FINISHED)
	table.take(table.room.leave(PvpTable.JOIN_CONN, table.now_ms))
	assert_bool(table.room.is_closed()).is_true()
	var record: Dictionary = table.room.log_record()
	assert_bool(record["complete"]).is_true()


func test_host_leaving_a_waiting_room_closes_it() -> void:
	var table: PvpTable = PvpTable.create(SEED)
	table.host()
	var out: Array[PvpTable.Sent] = table.take(
		table.room.leave(PvpTable.HOST_CONN, table.now_ms)
	)
	assert_array(out).is_empty()
	assert_bool(table.room.is_closed()).is_true()
	assert_dict(table.room.log_record()).is_empty()


func test_a_waiting_room_expires_after_ten_minutes() -> void:
	var table: PvpTable = PvpTable.create(SEED)
	table.host()
	var early: Array[PvpTable.Sent] = table.take(
		table.room.tick(PvpTable.T0_MS + MatchRoom.ROOM_EXPIRY_MS - 1)
	)
	assert_array(early).is_empty()
	var out: Array[PvpTable.Sent] = table.take(
		table.room.tick(PvpTable.T0_MS + MatchRoom.ROOM_EXPIRY_MS)
	)
	assert_array(_kinds(out)).is_equal([NetProtocol.T_EXPIRED])
	assert_int(out[0].conn).is_equal(PvpTable.HOST_CONN)
	assert_bool(table.room.is_closed()).is_true()
	assert_array(table.unencodable).is_empty()


func test_a_finished_room_lingers_five_minutes() -> void:
	var table: PvpTable = _started()
	table.act(0, EngineAction.concede(0))
	var ended_at: int = table.now_ms
	assert_array(table.take(table.room.tick(ended_at + MatchRoom.FINISHED_LINGER_MS - 1))).is_empty()
	assert_bool(table.room.is_closed()).is_false()
	var out: Array[PvpTable.Sent] = table.take(
		table.room.tick(ended_at + MatchRoom.FINISHED_LINGER_MS)
	)
	assert_array(_kinds(out)).is_equal([NetProtocol.T_CLOSED, NetProtocol.T_CLOSED])
	assert_bool(table.room.is_closed()).is_true()


func test_fail_closes_the_room_as_a_server_error() -> void:
	var table: PvpTable = _started()
	var out: Array[PvpTable.Sent] = table.take(table.room.fail(table.now_ms))
	assert_array(_kinds(out)).is_equal([NetProtocol.T_CLOSED, NetProtocol.T_CLOSED])
	assert_str(out[0].message[NetProtocol.KEY_REASON]).is_equal(MatchRoom.END_SERVER_ERROR)
	var record: Dictionary = table.room.log_record()
	var end: Dictionary = record["end"]
	assert_str(end["reason"]).is_equal(MatchRoom.END_SERVER_ERROR)
	assert_bool(record["complete"]).is_false()


# --- The log record -------------------------------------------------------------------


func test_the_log_record_carries_the_data_model_fields() -> void:
	var table: PvpTable = _started()
	table.play_one()
	var record: Dictionary = table.room.log_record()
	var keys: Array[String] = []
	for key: Variant in record:
		var key_name: String = key
		keys.append(key_name)
	keys.sort()
	var expected: Array[String] = []
	expected.assign(LOG_KEYS)
	expected.sort()
	assert_array(keys).is_equal(expected)
	assert_str(record["match_id"]).is_equal("20261107T214512Z-K7QX")
	assert_str(record["room"]).is_equal("K7QX")
	assert_str(record["mode"]).is_equal("pvp")
	assert_str(record["stamp"]).is_equal("r7-0123456789abcdef")
	assert_str(record["build"]).is_equal("test-build")
	assert_int(record["rules"]).is_equal(MatchRules.RULES_VERSION)
	assert_int(record["log_format"]).is_equal(MatchRules.LOG_FORMAT)
	assert_int(record["protocol"]).is_equal(NetProtocol.VERSION)
	assert_str(record["started_at"]).is_equal("2026-11-07T21:45:12Z")
	assert_that(record["ended_at"]).is_null()
	assert_that(record["end"]).is_null()
	assert_bool(record["complete"]).is_false()
	assert_array(record["decks"]).is_equal(["greed", "ramp"])
	var players: Array = record["players"]
	var host: Dictionary = players[0]
	assert_str(PvpTable.sorted_json(host)).is_equal(
		PvpTable.sorted_json({"seat": 0, "name": "Ana", "install_id": "install-ana", "kind": "human"})
	)
	var joiner: Dictionary = players[1]
	assert_str(joiner["kind"]).is_equal("bot")
	var logged: Dictionary = record["log"]
	assert_int(logged["format"]).is_equal(MatchRules.LOG_FORMAT)
	var actions: Array = logged["actions"]
	assert_int(actions.size()).is_equal(1)
	# Survives the file's JSON round trip.
	var json: JSON = JSON.new()
	assert_int(json.parse(JSON.stringify(record))).is_equal(OK)
