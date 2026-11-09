class_name PvpLog
extends RefCounted
## The PVP match file (cycle 12 plan P9 and Data model; spec R52 to R58): one JSON file per
## match at `<logs>/<YYYY-MM-DD>/<YYYYMMDDTHHMMSSZ>-<code>.json` (UTC), rewritten whole
## after `started`, after every accepted action and at close, as `<file>.tmp` then renamed
## over the file, so a reboot keeps every move up to the last accepted one.
##
## The record is the Dictionary the room's `log_record()` returns, with the Data model's
## keys: match_id, room, mode, stamp, rules, log_format, protocol, build, players (seat,
## name, install_id, kind), decks, started_at, ended_at, end (reason, winner, wins, rounds),
## complete, disconnects (seat, at, reconnected) and `log`, the engine's ActionLog JSON
## parsed back into a Dictionary. A running match has `end` and `ended_at` null and
## `complete` false.
##
## Static and pure apart from file I/O: every time is a UTC Unix time in seconds the caller
## passes; the one clock read is unix_ms_now(), which anchors the server's timestamps (R28:
## every timeout runs on the monotonic clock, wall-clock time is for log timestamps only).
## JSON is parsed with JSON.new().parse(), never JSON.parse_string(), and a corrupt file is
## skipped with a warning, never an error.

const MODE_PVP: String = "pvp"
const TMP_SUFFIX: String = ".tmp"
const FILE_SUFFIX: String = ".json"
const REASON_ABANDONED: String = "abandoned"
const REASON_SERVER_ERROR: String = "server_error"
const REASON_INTERRUPTED: String = "interrupted"
## The engine's end reasons (MatchEngine.REASON_*): only these make a file complete (R56).
const ENGINE_REASONS: Array[String] = [
	MatchEngine.REASON_WINS,
	MatchEngine.REASON_ROUNDS,
	MatchEngine.REASON_SUDDEN_DEATH,
	MatchEngine.REASON_STALEMATE,
	MatchEngine.REASON_CONCEDE,
]
## Whole floats below this magnitude read back as ints (JSON numbers parse as floats).
const WHOLE_LIMIT: float = 9.0e15
## "YYYYMMDDTHHMMSSZ": the time part of a match id.
const STAMP_LENGTH: int = 16
## R33: the writer's JSON is one line whose `log` (the big part) is the last key, so every key
## before it, `end` included, sits in this many leading bytes (players and the 10 disconnects
## are bounded); the orphan scan reads no more than this to tell a running match from a
## finished one.
const HEADER_BYTES: int = 16384
const LOG_KEY_MARK: String = ',"log":'
## header_state(): the file has an `end`, has none, or the header cannot tell.
const HEADER_ENDED: int = 1
const HEADER_RUNNING: int = 0
const HEADER_UNKNOWN: int = -1

const KEY_MATCH_ID: String = "match_id"
const KEY_ROOM: String = "room"
const KEY_MODE: String = "mode"
const KEY_STAMP: String = "stamp"
const KEY_RULES: String = "rules"
const KEY_LOG_FORMAT: String = "log_format"
const KEY_PROTOCOL: String = "protocol"
const KEY_BUILD: String = "build"
const KEY_PLAYERS: String = "players"
const KEY_DECKS: String = "decks"
const KEY_STARTED_AT: String = "started_at"
const KEY_ENDED_AT: String = "ended_at"
const KEY_END: String = "end"
const KEY_COMPLETE: String = "complete"
const KEY_DISCONNECTS: String = "disconnects"
const KEY_LOG: String = "log"
const KEY_REASON: String = "reason"
const KEY_WINNER: String = "winner"
const KEY_WINS: String = "wins"
const KEY_ROUNDS: String = "rounds"
## Keys of a players entry and of a disconnects entry.
const KEY_SEAT: String = "seat"
const KEY_NAME: String = "name"
const KEY_INSTALL_ID: String = "install_id"
const KEY_KIND: String = "kind"
const KEY_AT: String = "at"
const KEY_RECONNECTED: String = "reconnected"
## The MATCH_ENDED payload's key for the Rounds played.
const PAYLOAD_ROUNDS: String = "rounds_played"

# --- Times and names --------------------------------------------------------------------


## The wall clock as Unix milliseconds, UTC: read once by the server to anchor its monotonic
## clock, so log timestamps are real times (the only wall-clock read in the server, R28).
static func unix_ms_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## "2026-11-07T21:45:12Z" for `unix_s`.
static func iso_utc(unix_s: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_s, false) + "Z"


## "20261107T214512Z-K7QX": the match id and file stem for a room `code` started at `unix_s`.
static func match_id(unix_s: int, code: String) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix_s)
	var year: int = d["year"]
	var month: int = d["month"]
	var day: int = d["day"]
	var hour: int = d["hour"]
	var minute: int = d["minute"]
	var second: int = d["second"]
	var fields: Array = [year, month, day, hour, minute, second, code]
	return "%04d%02d%02dT%02d%02d%02dZ-%s" % fields


## The file of `record` under `logs_dir`: `<logs>/<YYYY-MM-DD>/<match_id>.json`; "" when the
## record has no well-formed match_id.
static func path_of(logs_dir: String, record: Dictionary) -> String:
	var raw: Variant = record.get(KEY_MATCH_ID, "")
	if typeof(raw) != TYPE_STRING:
		return ""
	var id: String = raw
	if not _is_match_id(id):
		return ""
	var date: String = "%s-%s-%s" % [id.substr(0, 4), id.substr(4, 2), id.substr(6, 2)]
	return logs_dir.path_join(date).path_join(id + FILE_SUFFIX)


# --- The record -------------------------------------------------------------------------


## One players entry (R53).
static func player(seat: int, name: String, install_id: String, kind: String) -> Dictionary:
	return {KEY_SEAT: seat, KEY_NAME: name, KEY_INSTALL_ID: install_id, KEY_KIND: kind}


## One disconnects entry (R53).
static func disconnect_entry(seat: int, at_unix_s: int, reconnected: bool) -> Dictionary:
	return {KEY_SEAT: seat, KEY_AT: iso_utc(at_unix_s), KEY_RECONNECTED: reconnected}


## A running match's header (Data model): no end, not complete, no disconnects, and an
## empty `log` until set_log(). `players` are player() entries; `decks` are both deck ids
## by seat; `stamp` is BotStamp.current() and `build` the server's git commit.
static func new_record(
	code: String,
	started_unix_s: int,
	stamp: String,
	build: String,
	players: Array[Dictionary],
	decks: Array[String]
) -> Dictionary:
	var player_list: Array = []
	for entry: Dictionary in players:
		player_list.append(entry.duplicate(true))
	var deck_list: Array = []
	for deck_id: String in decks:
		deck_list.append(deck_id)
	return {
		KEY_MATCH_ID: match_id(started_unix_s, code),
		KEY_ROOM: code,
		KEY_MODE: MODE_PVP,
		KEY_STAMP: stamp,
		KEY_RULES: MatchRules.RULES_VERSION,
		KEY_LOG_FORMAT: MatchRules.LOG_FORMAT,
		KEY_PROTOCOL: NetProtocol.VERSION,
		KEY_BUILD: build,
		KEY_PLAYERS: player_list,
		KEY_DECKS: deck_list,
		KEY_STARTED_AT: iso_utc(started_unix_s),
		KEY_ENDED_AT: null,
		KEY_END: null,
		KEY_COMPLETE: false,
		KEY_DISCONNECTS: [],
		KEY_LOG: {},
	}


## The `log` field for `action_log`: its to_json() parsed back, numbers as ints, so the
## trainer can hand it to ActionLog.from_json() unchanged. Empty when it does not parse.
static func log_field(action_log: ActionLog) -> Dictionary:
	var parsed: Dictionary = _parse_object(action_log.to_json())
	return parsed


## Sets `record`'s `log` from `action_log` (after every accepted action).
static func set_log(record: Dictionary, action_log: ActionLog) -> void:
	record[KEY_LOG] = log_field(action_log)


## The `end` of an engine-finished match from its MATCH_ENDED payload (R56).
static func engine_end(payload: Dictionary) -> Dictionary:
	var wins: Array = []
	var raw_wins: Variant = payload.get(KEY_WINS, [])
	if raw_wins is Array:
		var wins_in: Array = raw_wins
		for value: Variant in wins_in:
			wins.append(_int_or(value, 0))
	return {
		KEY_REASON: _string_or(payload.get(KEY_REASON, ""), ""),
		KEY_WINNER: _int_or(payload.get(KEY_WINNER, -1), -1),
		KEY_WINS: wins,
		KEY_ROUNDS: _int_or(payload.get(PAYLOAD_ROUNDS, 0), 0),
	}


## The `end` the server writes for a match the engine did not finish (R57, R58):
## `abandoned`, `server_error` or `interrupted`, with no winner.
static func server_end(reason: String) -> Dictionary:
	return {KEY_REASON: reason, KEY_WINNER: -1}


## Closes `record` with `end` at `ended_unix_s`: `complete` is true only when the reason is
## one of the engine's (R56, R57).
static func finish(record: Dictionary, end: Dictionary, ended_unix_s: int) -> void:
	record[KEY_END] = end.duplicate(true)
	record[KEY_ENDED_AT] = iso_utc(ended_unix_s)
	record[KEY_COMPLETE] = is_engine_end(end)


## True when `end` names an engine reason.
static func is_engine_end(end: Dictionary) -> bool:
	var reason: String = _string_or(end.get(KEY_REASON, ""), "")
	return ENGINE_REASONS.has(reason)


## True when `record` carries an end: a non-empty `end` Dictionary.
static func has_end(record: Dictionary) -> bool:
	var raw: Variant = record.get(KEY_END, null)
	if not raw is Dictionary:
		return false
	var end: Dictionary = raw
	return not end.is_empty()


# --- Files ------------------------------------------------------------------------------


## Writes `record` to its file under `logs_dir` (path_of), atomically. OK or the error;
## ERR_INVALID_PARAMETER when the record has no well-formed match_id.
static func write(logs_dir: String, record: Dictionary) -> int:
	var path: String = path_of(logs_dir, record)
	if path == "":
		return ERR_INVALID_PARAMETER
	return write_to(path, record)


## Writes `record` as JSON to `<path>.tmp` in the same folder, then renames it over `path`
## (making the folder first). OK or the error.
static func write_to(path: String, record: Dictionary) -> int:
	var target: String = ProjectSettings.globalize_path(path)
	var folder: String = target.get_base_dir()
	var made: int = DirAccess.make_dir_recursive_absolute(folder)
	if made != OK and made != ERR_ALREADY_EXISTS:
		return made
	var tmp: String = target + TMP_SUFFIX
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored: bool = file.store_string(JSON.stringify(record, "", false))
	var file_error: int = file.get_error()
	file.close()
	if not stored:
		return file_error if file_error != OK else ERR_FILE_CANT_WRITE
	return DirAccess.rename_absolute(tmp, target)


## The record in the file at `path`, numbers as ints; empty when the file is missing or is
## not a JSON object.
static func read(path: String) -> Dictionary:
	var target: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(target):
		return {}
	return _parse_object(FileAccess.get_file_as_string(target))


## The orphan scan at server start (R58): every `.json` file in every dated folder under
## `logs_dir` with no end gets `end: {reason: "interrupted", winner: -1}` and `complete:
## false`, rewritten atomically; `ended_at` is left as it was (the interruption's time is
## unknown). A lone `<file>.json.tmp` (a crash between the old file's removal and the
## rename) is promoted to `<file>.json` first, then marked the same way. A file that does
## not parse is skipped with a warning. Returns how many files were marked.
static func scan_orphans(logs_dir: String) -> int:
	var root: String = ProjectSettings.globalize_path(logs_dir)
	if not DirAccess.dir_exists_absolute(root):
		return 0
	var marked: int = 0
	var folders: PackedStringArray = DirAccess.get_directories_at(root)
	folders.sort()
	for folder: String in folders:
		var dated: String = root.path_join(folder)
		_promote_lone_tmps(dated)
		var names: PackedStringArray = DirAccess.get_files_at(dated)
		names.sort()
		for file_name: String in names:
			if file_name.ends_with(FILE_SUFFIX) and _mark_interrupted(dated.path_join(file_name)):
				marked += 1
	return marked


## Renames every `<file>.json.tmp` in `dated` with no `<file>.json` beside it to that
## `.json` (NSC-226 S3). A tmp beside its `.json` is left: the next write replaces it.
static func _promote_lone_tmps(dated: String) -> void:
	for file_name: String in DirAccess.get_files_at(dated):
		if not file_name.ends_with(FILE_SUFFIX + TMP_SUFFIX):
			continue
		var tmp: String = dated.path_join(file_name)
		var target: String = tmp.trim_suffix(TMP_SUFFIX)
		if FileAccess.file_exists(target):
			continue
		var err: int = DirAccess.rename_absolute(tmp, target)
		if err != OK:
			push_warning("PvpLog: cannot promote %s (error %d)" % [tmp, err])


## Whether the file at `path` carries an `end`, read from its first HEADER_BYTES only (R33):
## the text up to the `log` key closed into an object. HEADER_UNKNOWN when the file is
## missing, has no `log` key in that prefix (an old or hand-edited file) or the prefix is not
## JSON; the caller then reads the whole file.
static func header_state(path: String) -> int:
	var target: String = ProjectSettings.globalize_path(path)
	var file: FileAccess = FileAccess.open(target, FileAccess.READ)
	if file == null:
		return HEADER_UNKNOWN
	var head: String = file.get_buffer(HEADER_BYTES).get_string_from_utf8()
	file.close()
	var cut: int = head.find(LOG_KEY_MARK)
	if cut < 0:
		return HEADER_UNKNOWN
	var header: Dictionary = _parse_object(head.substr(0, cut) + "}")
	if header.is_empty():
		return HEADER_UNKNOWN
	return HEADER_ENDED if has_end(header) else HEADER_RUNNING


## Marks the log at `path` interrupted when it has no end; whether it was marked. A file whose
## header already shows an end is not read any further (R33).
static func _mark_interrupted(path: String) -> bool:
	var state: int = header_state(path)
	if state == HEADER_ENDED:
		return false
	var record: Dictionary = read(path)
	if record.is_empty():
		push_warning("PvpLog: skipped unreadable log %s" % path)
		return false
	if has_end(record):
		return false
	record[KEY_END] = server_end(REASON_INTERRUPTED)
	record[KEY_COMPLETE] = false
	var err: int = write_to(path, record)
	if err != OK:
		push_warning("PvpLog: cannot mark %s interrupted (error %d)" % [path, err])
		return false
	return true


# --- Helpers ----------------------------------------------------------------------------


## True for "YYYYMMDDTHHMMSSZ-<code>" with a non-empty code.
static func _is_match_id(id: String) -> bool:
	if id.length() <= STAMP_LENGTH + 1:
		return false
	if id.substr(8, 1) != "T" or id.substr(15, 1) != "Z" or id.substr(16, 1) != "-":
		return false
	var digits: String = id.substr(0, 8) + id.substr(9, 6)
	return digits.is_valid_int() and not digits.contains("-") and not digits.contains("+")


## The JSON object in `text` with whole numbers as ints; empty when it is not one.
static func _parse_object(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	var plain: Variant = _plain(json.data)
	if not plain is Dictionary:
		return {}
	var out: Dictionary = plain
	return out


## `value` with every whole float (JSON's numbers) turned back into an int, recursively.
static func _plain(value: Variant) -> Variant:
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and absf(number) < WHOLE_LIMIT:
			return int(number)
		return number
	if value is Array:
		var items: Array = value
		var out_items: Array = []
		for item: Variant in items:
			out_items.append(_plain(item))
		return out_items
	if value is Dictionary:
		var entries: Dictionary = value
		var out_entries: Dictionary = {}
		for key: Variant in entries:
			out_entries[key] = _plain(entries[key])
		return out_entries
	return value


static func _int_or(value: Variant, fallback: int) -> int:
	if value is int:
		var whole: int = value
		return whole
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and absf(number) < WHOLE_LIMIT:
			return int(number)
	return fallback


static func _string_or(value: Variant, fallback: String) -> String:
	if value is String:
		var text: String = value
		return text
	return fallback
