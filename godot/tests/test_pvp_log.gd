class_name TestPvpLog
extends FullMatchHarness
## PvpLog (cycle 12 T04; plan P9 and Data model; spec R52 to R58), in a temp folder under
## user://: the header's schema, the dated path, a rewrite after every accepted action of
## the seed-1 match whose `log` replays to the file's action count, an abandoned match's
## file, and the orphan scan marking a running file `interrupted`.

const SEED: int = 1
const TEMP_DIR: String = "user://test_pvp_log_tmp"
const CODE: String = "K7QX"
const START_TEXT: String = "2026-11-07T21:45:12"
const STAMP: String = "r7-1a2b3c4d5e6f7a8b"
const BUILD: String = "0123456789abcdef0123456789abcdef01234567"
const SCHEMA: Array[String] = [
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


func before_test() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEMP_DIR))


func after_test() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEMP_DIR))


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _start_s() -> int:
	return Time.get_unix_time_from_datetime_string(START_TEXT)


func _players() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		PvpLog.player(0, "Ben", "2f1c-install", "human"),
		PvpLog.player(1, "bot:random", "9ab0-install", "bot"),
	]
	return out


func _record_for(engine: MatchEngine, started_s: int) -> Dictionary:
	var record: Dictionary = PvpLog.new_record(
		CODE, started_s, STAMP, BUILD, _players(), engine.deck_ids()
	)
	PvpLog.set_log(record, engine.action_log())
	return record


## The number of actions in `record`'s `log`, or -1 when it does not parse.
func _logged_actions(record: Dictionary) -> int:
	var parsed: ActionLog = _parsed_log(record)
	if parsed == null:
		return -1
	return parsed.actions.size()


func _parsed_log(record: Dictionary) -> ActionLog:
	var raw: Variant = record.get("log", null)
	if not raw is Dictionary:
		return null
	var log_dict: Dictionary = raw
	return ActionLog.from_json(JSON.stringify(log_dict))


func _int_at(record: Dictionary, key: String) -> int:
	var raw: Variant = record.get(key, null)
	if typeof(raw) != TYPE_INT:
		return -999
	var value: int = raw
	return value


func _end_of(record: Dictionary) -> Dictionary:
	var raw: Variant = record.get("end", null)
	if not raw is Dictionary:
		return {}
	var end: Dictionary = raw
	return end


# --- Names and schema -------------------------------------------------------------------


func test_match_id_time_and_path() -> void:
	var started: int = _start_s()
	assert_str(PvpLog.match_id(started, CODE)).is_equal("20261107T214512Z-K7QX")
	assert_str(PvpLog.iso_utc(started)).is_equal("2026-11-07T21:45:12Z")
	var record: Dictionary = {"match_id": PvpLog.match_id(started, CODE)}
	var expected: String = TEMP_DIR + "/2026-11-07/20261107T214512Z-K7QX.json"
	assert_str(PvpLog.path_of(TEMP_DIR, record)).is_equal(expected)
	assert_str(PvpLog.path_of(TEMP_DIR, {"match_id": "nonsense"})).is_equal("")
	assert_str(PvpLog.path_of(TEMP_DIR, {})).is_equal("")
	assert_int(PvpLog.write(TEMP_DIR, {"match_id": 3})).is_equal(ERR_INVALID_PARAMETER)


func test_header_schema() -> void:
	var engine: MatchEngine = _new_engine(SEED)
	assert_bool(engine.start().ok).is_true()
	var record: Dictionary = _record_for(engine, _start_s())
	assert_int(PvpLog.write(TEMP_DIR, record)).is_equal(OK)
	var back: Dictionary = PvpLog.read(PvpLog.path_of(TEMP_DIR, record))
	var keys: Array[String] = []
	for key: Variant in back:
		var text: String = key
		keys.append(text)
	assert_array(keys).is_equal(SCHEMA)
	assert_str(back["match_id"]).is_equal("20261107T214512Z-K7QX")
	assert_str(back["room"]).is_equal(CODE)
	assert_str(back["mode"]).is_equal("pvp")
	assert_str(back["stamp"]).is_equal(STAMP)
	assert_int(_int_at(back, "rules")).is_equal(MatchRules.RULES_VERSION)
	assert_int(_int_at(back, "log_format")).is_equal(MatchRules.LOG_FORMAT)
	assert_int(_int_at(back, "protocol")).is_equal(NetProtocol.VERSION)
	assert_str(back["build"]).is_equal(BUILD)
	var players: Array = back["players"]
	assert_int(players.size()).is_equal(2)
	var second: Dictionary = players[1]
	assert_int(_int_at(second, "seat")).is_equal(1)
	assert_str(second["name"]).is_equal("bot:random")
	assert_str(second["install_id"]).is_equal("9ab0-install")
	assert_str(second["kind"]).is_equal("bot")
	var decks: Array = back["decks"]
	var ids: Array[String] = engine.deck_ids()
	assert_array(decks).is_equal([ids[0], ids[1]])
	assert_str(back["started_at"]).is_equal("2026-11-07T21:45:12Z")
	assert_bool(back["ended_at"] == null).is_true()
	assert_bool(back["end"] == null).is_true()
	assert_bool(PvpLog.has_end(back)).is_false()
	assert_bool(back["complete"]).is_false()
	var disconnects: Array = back["disconnects"]
	assert_bool(disconnects.is_empty()).is_true()
	var parsed: ActionLog = _parsed_log(back)
	assert_object(parsed).is_not_null()
	if parsed != null:
		assert_array(parsed.deck_ids).is_equal(ids)
		assert_int(parsed.actions.size()).is_equal(0)


func test_disconnect_entry_shape() -> void:
	var entry: Dictionary = PvpLog.disconnect_entry(1, _start_s() + 60, true)
	assert_dict(entry).is_equal({"seat": 1, "at": "2026-11-07T21:46:12Z", "reconnected": true})


# --- A whole match, rewritten per action ------------------------------------------------


func test_rewrite_after_each_action_and_replay() -> void:
	var engine: MatchEngine = _new_engine(SEED)
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	var started_s: int = _start_s()
	var record: Dictionary = _record_for(engine, started_s)
	var path: String = PvpLog.path_of(TEMP_DIR, record)
	assert_int(PvpLog.write(TEMP_DIR, record)).is_equal(OK)
	assert_int(_logged_actions(PvpLog.read(path))).is_equal(0)
	var bots: Array[BotPlayer] = _new_bots(SEED, engine)
	assert_bool(bots.has(null)).is_false()
	if bots.has(null):
		return
	var mismatches: Array[String] = []
	var end_payload: Dictionary = {}
	while not engine.is_over() and engine.accepted_action_count() < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var result: ApplyResult = engine.apply(bots[seat].choose(engine.view_for(seat), engine))
		if not result.ok:
			mismatches.append("action rejected, code %d" % result.error)
			break
		for event: MatchEvent in result.events:
			if event.kind == MatchEvent.Kind.MATCH_ENDED:
				end_payload = event.payload.duplicate(true)
		PvpLog.set_log(record, engine.action_log())
		if PvpLog.write(TEMP_DIR, record) != OK:
			mismatches.append("write failed after %d" % engine.accepted_action_count())
			break
		var on_disk: Dictionary = PvpLog.read(path)
		var count: int = _logged_actions(on_disk)
		if count != engine.accepted_action_count():
			mismatches.append("file holds %d of %d" % [count, engine.accepted_action_count()])
		if on_disk.get("complete", true) != false:
			mismatches.append("running file not complete: false")
	_assert_none(mismatches, "rewrite per action")
	assert_bool(engine.is_over()).is_true()
	assert_bool(end_payload.is_empty()).is_false()
	assert_bool(FileAccess.file_exists(path + PvpLog.TMP_SUFFIX)).is_false()
	PvpLog.finish(record, PvpLog.engine_end(end_payload), started_s + 1108)
	assert_int(PvpLog.write(TEMP_DIR, record)).is_equal(OK)
	var final: Dictionary = PvpLog.read(path)
	assert_bool(final["complete"]).is_true()
	assert_str(final["ended_at"]).is_equal("2026-11-07T22:03:40Z")
	var end: Dictionary = _end_of(final)
	assert_str(end["reason"]).is_equal(end_payload["reason"])
	assert_int(_int_at(end, "winner")).is_equal(engine.match_winner())
	assert_int(_int_at(end, "rounds")).is_equal(_int_at(end_payload, "rounds_played"))
	var wins: Array = end["wins"]
	var engine_wins: Array[int] = engine.round_wins()
	assert_array(wins).is_equal([engine_wins[0], engine_wins[1]])
	# The acceptance check: the parsed file's `log` replays to the same action count.
	var parsed: ActionLog = _parsed_log(final)
	assert_object(parsed).is_not_null()
	if parsed == null:
		return
	assert_int(parsed.actions.size()).is_equal(engine.accepted_action_count())
	var replayed: ReplayResult = parsed.replay(_db(), _decks(), CrewPool.load_default())
	assert_bool(replayed.ok).is_true()
	if not replayed.ok:
		return
	assert_int(replayed.engine.accepted_action_count()).is_equal(parsed.actions.size())
	assert_bool(replayed.engine.is_over()).is_true()
	assert_bool(replayed.engine.full_state() == engine.full_state()).is_true()


# --- Server ends ------------------------------------------------------------------------


func test_abandoned_match_file() -> void:
	var engine: MatchEngine = _new_engine(SEED)
	assert_bool(engine.start().ok).is_true()
	var started_s: int = _start_s()
	var record: Dictionary = _record_for(engine, started_s)
	var bots: Array[BotPlayer] = _new_bots(SEED, engine)
	for _step: int in range(5):
		var seat: int = engine.awaited_seat()
		var result: ApplyResult = engine.apply(bots[seat].choose(engine.view_for(seat), engine))
		assert_bool(result.ok).is_true()
	PvpLog.set_log(record, engine.action_log())
	record["disconnects"] = [PvpLog.disconnect_entry(1, started_s + 30, false)]
	assert_int(PvpLog.write(TEMP_DIR, record)).is_equal(OK)
	PvpLog.finish(record, PvpLog.server_end(PvpLog.REASON_ABANDONED), started_s + 150)
	assert_int(PvpLog.write(TEMP_DIR, record)).is_equal(OK)
	var back: Dictionary = PvpLog.read(PvpLog.path_of(TEMP_DIR, record))
	var end: Dictionary = _end_of(back)
	assert_str(end["reason"]).is_equal("abandoned")
	assert_int(_int_at(end, "winner")).is_equal(-1)
	assert_bool(back["complete"]).is_false()
	assert_str(back["ended_at"]).is_equal("2026-11-07T21:47:42Z")
	assert_int(_logged_actions(back)).is_equal(5)
	var disconnects: Array = back["disconnects"]
	assert_int(disconnects.size()).is_equal(1)


func test_only_engine_reasons_complete() -> void:
	for reason: String in PvpLog.ENGINE_REASONS:
		assert_bool(PvpLog.is_engine_end({"reason": reason})).is_true()
	var server_reasons: Array[String] = [
		PvpLog.REASON_ABANDONED, PvpLog.REASON_SERVER_ERROR, PvpLog.REASON_INTERRUPTED
	]
	for reason: String in server_reasons:
		assert_bool(PvpLog.is_engine_end(PvpLog.server_end(reason))).is_false()


# --- The orphan scan --------------------------------------------------------------------


func test_orphan_marked_interrupted() -> void:
	var engine: MatchEngine = _new_engine(SEED)
	assert_bool(engine.start().ok).is_true()
	var started_s: int = _start_s()
	var running: Dictionary = _record_for(engine, started_s)
	assert_int(PvpLog.write(TEMP_DIR, running)).is_equal(OK)
	var finished: Dictionary = PvpLog.new_record(
		"ABCD", started_s + 86400, STAMP, BUILD, _players(), engine.deck_ids()
	)
	PvpLog.finish(finished, PvpLog.server_end(PvpLog.REASON_ABANDONED), started_s + 86500)
	assert_int(PvpLog.write(TEMP_DIR, finished)).is_equal(OK)
	var corrupt_path: String = TEMP_DIR + "/2026-11-07/corrupt.json"
	var corrupt: FileAccess = FileAccess.open(corrupt_path, FileAccess.WRITE)
	assert_object(corrupt).is_not_null()
	if corrupt != null:
		corrupt.store_string("{not json")
		corrupt.close()
	assert_int(PvpLog.scan_orphans(TEMP_DIR)).is_equal(1)
	var marked: Dictionary = PvpLog.read(PvpLog.path_of(TEMP_DIR, running))
	var end: Dictionary = _end_of(marked)
	assert_str(end["reason"]).is_equal("interrupted")
	assert_int(_int_at(end, "winner")).is_equal(-1)
	assert_bool(marked["complete"]).is_false()
	assert_int(_logged_actions(marked)).is_equal(0)
	var kept: Dictionary = PvpLog.read(PvpLog.path_of(TEMP_DIR, finished))
	assert_str(_end_of(kept)["reason"]).is_equal("abandoned")
	# A second scan finds nothing left to mark.
	assert_int(PvpLog.scan_orphans(TEMP_DIR)).is_equal(0)


## R33: whether a log has an end is read from its first bytes alone. A finished file whose
## tail is garbage (so a whole-file parse fails) still reads as ended; a running one as
## running; a missing one is undecided; and the scan marks only the running one.
func test_the_orphan_scan_decides_from_the_header_alone() -> void:
	var engine: MatchEngine = _new_engine(SEED)
	assert_bool(engine.start().ok).is_true()
	var started_s: int = _start_s()
	var running: Dictionary = _record_for(engine, started_s)
	assert_int(PvpLog.write(TEMP_DIR, running)).is_equal(OK)
	var finished: Dictionary = _record_for(engine, started_s + 86400)
	finished[PvpLog.KEY_ROOM] = "ABCD"
	finished[PvpLog.KEY_MATCH_ID] = PvpLog.match_id(started_s + 86400, "ABCD")
	PvpLog.finish(finished, PvpLog.server_end(PvpLog.REASON_ABANDONED), started_s + 86500)
	assert_int(PvpLog.write(TEMP_DIR, finished)).is_equal(OK)
	var running_path: String = PvpLog.path_of(TEMP_DIR, running)
	var finished_path: String = PvpLog.path_of(TEMP_DIR, finished)
	var text: String = FileAccess.get_file_as_string(ProjectSettings.globalize_path(finished_path))
	var broken: FileAccess = FileAccess.open(finished_path, FileAccess.WRITE)
	assert_object(broken).is_not_null()
	if broken != null:
		broken.store_string(text + "}}not json")
		broken.close()
	assert_dict(PvpLog.read(finished_path)).is_empty()
	assert_int(PvpLog.header_state(finished_path)).is_equal(PvpLog.HEADER_ENDED)
	assert_int(PvpLog.header_state(running_path)).is_equal(PvpLog.HEADER_RUNNING)
	assert_int(PvpLog.header_state(TEMP_DIR + "/absent.json")).is_equal(PvpLog.HEADER_UNKNOWN)
	assert_int(PvpLog.scan_orphans(TEMP_DIR)).is_equal(1)
	assert_str(_end_of(PvpLog.read(running_path))["reason"]).is_equal("interrupted")
	assert_dict(PvpLog.read(finished_path)).is_empty()


## A crash between the old file's removal and the rename leaves only `<file>.json.tmp`: the
## scan promotes it and marks it interrupted (NSC-226 S3).
func test_a_lone_tmp_is_promoted_and_marked_interrupted() -> void:
	var engine: MatchEngine = _new_engine(SEED)
	assert_bool(engine.start().ok).is_true()
	var running: Dictionary = _record_for(engine, _start_s())
	assert_int(PvpLog.write(TEMP_DIR, running)).is_equal(OK)
	var path: String = ProjectSettings.globalize_path(PvpLog.path_of(TEMP_DIR, running))
	var tmp: String = path + PvpLog.TMP_SUFFIX
	assert_int(DirAccess.rename_absolute(path, tmp)).is_equal(OK)
	assert_bool(FileAccess.file_exists(path)).is_false()
	assert_int(PvpLog.scan_orphans(TEMP_DIR)).is_equal(1)
	assert_bool(FileAccess.file_exists(tmp)).is_false()
	var marked: Dictionary = PvpLog.read(path)
	assert_str(_end_of(marked)["reason"]).is_equal("interrupted")
	assert_bool(marked["complete"]).is_false()


## A failed write is not counted as written: the server retries it on the next poll, and a
## closed room is kept until its record is on disk (NSC-226 S3).
func test_a_failed_log_write_is_retried_on_the_next_flush() -> void:
	var table: PvpTable = PvpTable.create(SEED)
	table.start()
	var server: MatchServer = auto_free(MatchServer.new())
	server.quiet = true
	server.registry = RoomRegistry.create(RandomNumberGenerator.new(), Callable())
	# A plain file where the log folder should be: every write fails.
	var blocked: String = TEMP_DIR + "/blocked"
	var made: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	assert_int(made).is_equal(OK)
	var blocker: FileAccess = FileAccess.open(blocked, FileAccess.WRITE)
	assert_object(blocker).is_not_null()
	if blocker != null:
		blocker.store_string("not a folder")
		blocker.close()
	server.logs_dir = blocked
	var tracked: MatchServer.TrackedRoom = MatchServer.TrackedRoom.new()
	tracked.room = table.room
	server._rooms.append(tracked)
	server._flush_rooms()
	assert_int(tracked.revision).is_equal(-1)
	table.room.fail(table.now_ms)
	server._flush_rooms()
	assert_int(server._rooms.size()).is_equal(1)
	server.logs_dir = TEMP_DIR
	server._flush_rooms()
	assert_int(tracked.revision).is_equal(table.room.revision())
	assert_int(server._rooms.size()).is_equal(0)
	var written: Dictionary = PvpLog.read(PvpLog.path_of(TEMP_DIR, table.room.log_record()))
	assert_str(_end_of(written)["reason"]).is_equal(PvpLog.REASON_SERVER_ERROR)


func test_scan_of_a_missing_folder_marks_nothing() -> void:
	assert_int(PvpLog.scan_orphans(TEMP_DIR + "/absent")).is_equal(0)
