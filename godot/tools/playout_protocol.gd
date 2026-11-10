class_name PlayoutProtocol
extends RefCounted
## The play-out worker's wire format (cycle 11 R25 to R29, R31, plan P9): request parsing
## with error strings, reply builders with a fixed field order, and the digest helper. Pure
## and static, so a suite checks it without a process. One JSON object per line each way.
##
## Requests (parse_request):
##   {"id", "kind": "play", "seed", "decks": [a, b] | [], "generator", "generator_weights"?}
##   {"id", "kind": "label", "seed", "decks", "actions": [prefix], "seat",
##    "k" | "candidates": [action dicts], "determinizations", "rollout", "label_seed",
##    "rollout_weights"?}
##   {"kind": "quit"}
## Protocol v2 (cycle 13 R13, R14, plan P5): `inspect` is gone (an `inspect` line gets an
## unknown-kind error; the label reply carries the position's Round, Turn and hand), and the
## optional `*_weights` members are weights file paths ("" or absent: the committed file),
## used when the named bot is `linear`.
## `seed` and `label_seed` are whole numbers or decimal strings (a 64-bit seed does not
## survive a JSON float, so the trainer sends it as text; a numeric seed of magnitude 2^53 or
## more is refused, B-38). `id` is a number or a string, echoed back as given.
## A request line is at most MAX_REQUEST_BYTES long (B-39); the worker answers a longer
## one with too_long_reply() and never parses it, so parse_request does not check the length.
##
## parse_request returns {"error": text, "id": the id when readable, else null} for a bad
## line, otherwise the request with typed members: kind, and for play id, seed, decks
## (Array[String], empty or two), generator; for label id, seed, decks, actions
## (Array[EngineAction]), seat, k (0 when candidates are given), candidates
## (Array[EngineAction], empty when k is given), determinizations, rollout, label_seed,
## rollout_weights (String); play also has generator_weights (String).
##
## Replies keep the field order of the builders, and encode() does not sort keys, so equal
## replies are equal strings. digest() drops the timing fields `us` and `godot`.

const KIND_PLAY: String = "play"
const KIND_LABEL: String = "label"
const KIND_QUIT: String = "quit"
## The longest request line, in bytes (B-39): ten times a 2000-action prefix (about 150 KB)
## with headroom. The worker reads each line with a buffer of this size. OS.read_string_from_stdin
## returns a longer line in pieces of MAX_REQUEST_BYTES - 1 bytes with no marker, so a line
## of that many bytes or more is taken as over-long (is_over_long), never parsed.
const MAX_REQUEST_BYTES: int = 1048576
## The error text for an over-long line.
const TOO_LONG_MESSAGE: String = "request line is longer than the %d byte limit"
## The fields a digest ignores: the time spent and the Godot version of the reply's worker.
const TIMING_FIELDS: Array[String] = ["us", "godot"]

# --- Parsing --------------------------------------------------------------------------


## Parses one request line; see the class comment for the shapes.
static func parse_request(line: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(line) != OK:
		return _bad(null, "request is not JSON")
	var root: Variant = json.data
	if not root is Dictionary:
		return _bad(null, "request is not an object")
	var d: Dictionary = root
	var request_id: Variant = d.get("id", null)
	if EngineAction.is_whole_number(request_id):
		# JSON numbers parse as float; a whole-number id is echoed back as the int it was.
		request_id = EngineAction.as_int(request_id)
	if not d.has("kind") or not d["kind"] is String:
		return _bad(request_id, "kind is missing or not a string")
	var kind: String = d["kind"]
	if kind == KIND_QUIT:
		return {"kind": KIND_QUIT}
	if not (request_id is String or request_id is int or request_id is float):
		return _bad(null, "id is missing or not a number or a string")
	if kind == KIND_PLAY:
		return _parse_play(d, request_id)
	if kind == KIND_LABEL:
		return _parse_label(d, request_id)
	return _bad(request_id, "unknown kind: %s" % kind)


static func _parse_play(d: Dictionary, request_id: Variant) -> Dictionary:
	var seed_out: Array[int] = []
	var seed_problem: String = _read_seed("seed", d.get("seed", null), seed_out)
	if seed_problem != "":
		return _bad(request_id, seed_problem)
	var decks: Array[String] = []
	if not _read_decks(d.get("decks", null), decks):
		return _bad(request_id, "decks must be a list of two deck ids or an empty list")
	var generator_raw: Variant = d.get("generator", null)
	if not generator_raw is String:
		return _bad(request_id, "generator is missing or not a string")
	var generator: String = generator_raw
	if not BotRegistry.NAMES.has(generator):
		return _bad(request_id, "unknown generator bot: %s" % generator)
	var weights_raw: Variant = d.get("generator_weights", "")
	if not weights_raw is String:
		return _bad(request_id, "generator_weights is not a string")
	var weights: String = weights_raw
	return {
		"id": request_id,
		"kind": KIND_PLAY,
		"seed": seed_out[0],
		"decks": decks,
		"generator": generator,
		"generator_weights": weights,
	}


static func _parse_label(d: Dictionary, request_id: Variant) -> Dictionary:
	var seed_out: Array[int] = []
	var seed_problem: String = _read_seed("seed", d.get("seed", null), seed_out)
	if seed_problem != "":
		return _bad(request_id, seed_problem)
	var label_out: Array[int] = []
	var label_problem: String = _read_seed("label_seed", d.get("label_seed", null), label_out)
	if label_problem != "":
		return _bad(request_id, label_problem)
	var decks: Array[String] = []
	if not _read_decks(d.get("decks", null), decks):
		return _bad(request_id, "decks must be a list of two deck ids or an empty list")
	var seat_raw: Variant = d.get("seat", null)
	if not EngineAction.is_whole_number(seat_raw):
		return _bad(request_id, "seat is missing or not a whole number")
	var seat: int = EngineAction.as_int(seat_raw)
	if seat < 0 or seat >= MatchEngine.SEATS:
		return _bad(request_id, "seat must be 0 or 1")
	var det_raw: Variant = d.get("determinizations", null)
	if not EngineAction.is_whole_number(det_raw):
		return _bad(request_id, "determinizations is missing or not a whole number")
	var determinizations: int = EngineAction.as_int(det_raw)
	if determinizations < 1:
		return _bad(request_id, "determinizations must be at least 1")
	var rollout_raw: Variant = d.get("rollout", null)
	if not rollout_raw is String:
		return _bad(request_id, "rollout is missing or not a string")
	var rollout: String = rollout_raw
	if not BotRegistry.NAMES.has(rollout):
		return _bad(request_id, "unknown rollout bot: %s" % rollout)
	var weights_raw: Variant = d.get("rollout_weights", "")
	if not weights_raw is String:
		return _bad(request_id, "rollout_weights is not a string")
	var weights: String = weights_raw
	var prefix: Array[EngineAction] = []
	if not _read_actions(d.get("actions", null), prefix):
		return _bad(request_id, "actions is missing or holds a malformed action")
	var has_k: bool = d.has("k")
	var has_candidates: bool = d.has("candidates")
	if has_k == has_candidates:
		return _bad(request_id, "give exactly one of k and candidates")
	var k: int = 0
	var candidates: Array[EngineAction] = []
	if has_k:
		var k_raw: Variant = d["k"]
		if not EngineAction.is_whole_number(k_raw):
			return _bad(request_id, "k is not a whole number")
		k = EngineAction.as_int(k_raw)
		if k < 1:
			return _bad(request_id, "k must be at least 1")
	else:
		if not _read_actions(d["candidates"], candidates) or candidates.is_empty():
			return _bad(request_id, "candidates must be a non-empty list of actions")
		for candidate: EngineAction in candidates:
			if candidate.kind != EngineAction.Kind.COMMIT or candidate.seat != seat:
				return _bad(request_id, "every candidate must be a commit by seat %d" % seat)
	return {
		"id": request_id,
		"kind": KIND_LABEL,
		"seed": seed_out[0],
		"decks": decks,
		"actions": prefix,
		"seat": seat,
		"k": k,
		"candidates": candidates,
		"determinizations": determinizations,
		"rollout": rollout,
		"label_seed": label_out[0],
		"rollout_weights": weights,
	}


## An error result for parse_request.
static func _bad(request_id: Variant, message: String) -> Dictionary:
	return {"error": message, "id": request_id}


## Reads the seed `name` (a whole number or a decimal string) into `out`; the problem, or "".
## A numeric seed of magnitude 2^53 or more is refused: a JSON number is a float and would
## round it (B-38), so the client sends such a seed as a string.
static func _read_seed(name: String, value: Variant, out: Array[int]) -> String:
	if value is float:
		var number: float = value
		if is_finite(number) and absf(number) >= EngineAction.MAX_SAFE_FLOAT:
			return "%s is a number of magnitude 2^53 or more, send it as a string" % name
	if EngineAction.is_whole_number(value):
		out.append(EngineAction.as_int(value))
		return ""
	if value is String:
		var text: String = value
		if text.is_valid_int():
			out.append(text.to_int())
			return ""
	return "%s is missing or not a whole number" % name


## Reads a deck list (empty, or two strings) into `out`.
static func _read_decks(value: Variant, out: Array[String]) -> bool:
	if not value is Array:
		return false
	var listed: Array = value
	if listed.size() != 0 and listed.size() != MatchEngine.SEATS:
		return false
	for entry: Variant in listed:
		if not entry is String:
			return false
		var id: String = entry
		out.append(id)
	return true


## Reads a list of action dictionaries into `out`; false on a non-list or a bad entry.
static func _read_actions(value: Variant, out: Array[EngineAction]) -> bool:
	if not value is Array:
		return false
	var listed: Array = value
	for entry: Variant in listed:
		if not entry is Dictionary:
			return false
		var as_dict: Dictionary = entry
		var action: EngineAction = EngineAction.from_dict(as_dict)
		if action == null:
			return false
		out.append(action)
	return true


# --- Replies --------------------------------------------------------------------------


static func hello_reply(
	stamp: String, feature_set: String, rules: int, format: int, godot: String
) -> Dictionary:
	return {
		"hello": true,
		"stamp": stamp,
		"feature_set": feature_set,
		"rules": rules,
		"format": format,
		"godot": godot,
	}


static func play_reply(
	request_id: Variant, stamp: String, log: Dictionary, result: Dictionary, commits: Array, us: int
) -> Dictionary:
	return {
		"id": request_id,
		"stamp": stamp,
		"log": log,
		"result": result,
		"commits": commits,
		"us": us,
	}


## The label reply (protocol v2): the position's Round, Turn and the seat's `hand` ([{instance,
## card, name}]), the number of `legal` commits (-1 when not enumerated), the `candidates`
## and, per candidate in the same order, its `features` (an integer list laid out as
## BotFeatures.names(), under `feature_set`), then `values`.
static func label_reply(
	request_id: Variant,
	stamp: String,
	feature_set: String,
	round_number: int,
	turn: int,
	hand: Array,
	legal: int,
	candidates: Array,
	features: Array,
	values: Array,
	rollouts: int,
	us: int
) -> Dictionary:
	return {
		"id": request_id,
		"stamp": stamp,
		"feature_set": feature_set,
		"round": round_number,
		"turn": turn,
		"hand": hand,
		"legal": legal,
		"candidates": candidates,
		"features": features,
		"values": values,
		"rollouts": rollouts,
		"us": us,
	}


static func error_reply(request_id: Variant, message: String) -> Dictionary:
	return {"id": request_id, "error": message}


## The error reply to an over-long request line (is_over_long), which has no readable id.
static func too_long_reply() -> Dictionary:
	return error_reply(null, TOO_LONG_MESSAGE % MAX_REQUEST_BYTES)


## The result object of a finished match: {winner, wins, rounds, reason}.
static func result_object(winner: int, wins: Array, rounds: int, reason: String) -> Dictionary:
	return {"winner": winner, "wins": wins, "rounds": rounds, "reason": reason}


## An action log as a plain dictionary in the log's own key order (ActionLog.to_json holds the
## same keys), with whole numbers kept as ints and the seed as exact decimal text.
static func log_object(log: ActionLog) -> Dictionary:
	var entries: Array = []
	for action: EngineAction in log.actions:
		entries.append(action.to_dict())
	var out: Dictionary = {
		ActionLog.KEY_FORMAT: log.format_version,
		ActionLog.KEY_RULES: log.rules_version,
		ActionLog.KEY_SEED: str(log.match_seed),
	}
	if not log.deck_ids.is_empty():
		out[ActionLog.KEY_DECKS] = MatchState.plain_strings(log.deck_ids)
	out[ActionLog.KEY_ACTIONS] = entries
	return out


## One reply as its output line (keys in insertion order, no indent).
static func encode(reply: Dictionary) -> String:
	return JSON.stringify(reply, "", false)


## Whether a line of `byte_count` bytes is over-long: a longer line reaches the worker in
## pieces of MAX_REQUEST_BYTES - 1 bytes, so that length already counts as over (B-39).
static func is_over_long(byte_count: int) -> bool:
	return byte_count >= MAX_REQUEST_BYTES - 1


# --- Digest ---------------------------------------------------------------------------


## `reply` without the timing fields.
static func strip_timing(reply: Dictionary) -> Dictionary:
	var out: Dictionary = reply.duplicate(true)
	for field: String in TIMING_FIELDS:
		if not out.erase(field) and out.has(field):
			return {}
	return out


## SHA-256 (hex) over the reply `lines` in order, each with its timing fields removed and
## re-encoded, joined by newlines. A line that is not a JSON object contributes itself.
static func digest(lines: Array[String]) -> String:
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for line: String in lines:
		var text: String = line
		var json: JSON = JSON.new()
		if json.parse(line) == OK and json.data is Dictionary:
			var parsed: Dictionary = json.data
			text = encode(strip_timing(parsed))
		if hashing.update((text + "\n").to_utf8_buffer()) != OK:
			return ""
	return hashing.finish().hex_encode()
