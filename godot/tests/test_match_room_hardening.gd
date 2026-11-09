class_name TestMatchRoomHardening
extends GdUnitTestSuite
## MatchRoom's cycle 14 P12 behaviour (spec R26, R29, R32): an act the engine answers with
## nothing fails the room; a seat that drops a sixth time is treated as leaving; a `resync`
## carries the accepted-action count. (Its own suite: test_match_room.gd is at the lint cap
## of public methods.)

const SEED: int = 7
const LATE_CONN: int = 303


func _started() -> PvpTable:
	var table: PvpTable = PvpTable.create(SEED)
	table.start()
	return table


func _kinds(entries: Array[PvpTable.Sent]) -> Array[String]:
	var out: Array[String] = []
	for entry: PvpTable.Sent in entries:
		out.append(entry.kind)
	return out


## R26: an engine that answers an action with nothing fails the room through fail(): both
## clients are closed `server_error` and the room is closed.
func test_an_act_the_engine_answers_with_nothing_fails_the_room() -> void:
	var table: PvpTable = _started()
	table.room._engine = NullApplyEngine.new()
	var out: Array[PvpTable.Sent] = table.act(0, EngineAction.decline(0))
	assert_array(_kinds(out)).is_equal([NetProtocol.T_CLOSED, NetProtocol.T_CLOSED])
	assert_str(out[0].message[NetProtocol.KEY_REASON]).is_equal(MatchRoom.END_SERVER_ERROR)
	assert_bool(table.room.is_closed()).is_true()
	assert_array(table.unencodable).is_empty()


## R29: a seat may drop and reconnect five times; its sixth drop counts as leaving, so the
## match is conceded for it and it cannot rejoin.
func test_a_seat_that_drops_a_sixth_time_is_treated_as_leaving() -> void:
	var table: PvpTable = _started()
	var conn: int = PvpTable.JOIN_CONN
	for at: int in range(MatchRoom.MAX_DISCONNECTS_PER_SEAT):
		var lost: Array[PvpTable.Sent] = table.take(table.room.connection_lost(conn, table.now_ms))
		assert_array(_kinds(lost)).is_equal([NetProtocol.T_OPPONENT])
		conn = LATE_CONN + at
		var back: Array[PvpTable.Sent] = table.take(
			table.room.rejoin(conn, PvpTable.JOIN_ID, table.now_ms)
		)
		assert_array(_kinds(back)).is_equal([NetProtocol.T_OPPONENT, NetProtocol.T_RESYNC])
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.RUNNING)
	var sixth: Array[PvpTable.Sent] = table.take(table.room.connection_lost(conn, table.now_ms))
	assert_array(_kinds(sixth)).is_equal([NetProtocol.T_EVENTS])
	assert_int(sixth[0].conn).is_equal(PvpTable.HOST_CONN)
	assert_int(table.room.phase()).is_equal(MatchRoom.Phase.FINISHED)
	var end: Dictionary = table.room.log_record()["end"]
	assert_str(end["reason"]).is_equal(MatchEngine.REASON_CONCEDE)
	var again: Array[PvpTable.Sent] = table.take(
		table.room.rejoin(LATE_CONN + 9, PvpTable.JOIN_ID, table.now_ms)
	)
	assert_str(again[0].message[NetProtocol.KEY_REASON]).is_equal(
		NetProtocol.REASON_WRONG_INSTALL_ID
	)


## R32: a `resync` carries how many actions the match has accepted, so a rejoined client's
## `actions=` counts the ones before its resync too.
func test_a_resync_carries_the_actions_accepted_so_far() -> void:
	var table: PvpTable = _started()
	for _i: int in range(6):
		table.play_one()
	table.take(table.room.connection_lost(PvpTable.JOIN_CONN, table.now_ms))
	var back: Array[PvpTable.Sent] = table.take(
		table.room.rejoin(LATE_CONN, PvpTable.JOIN_ID, table.now_ms)
	)
	var resync: PvpTable.Sent = back[back.size() - 1]
	assert_str(resync.kind).is_equal(NetProtocol.T_RESYNC)
	assert_int(resync.message[NetProtocol.KEY_ACTIONS]).is_equal(6)


## An engine whose apply() answers nothing (R26).
class NullApplyEngine:
	extends MatchEngine

	func apply(action: EngineAction) -> ApplyResult:
		if action == null:
			return null
		return null
