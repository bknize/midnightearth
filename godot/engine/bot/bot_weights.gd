class_name BotWeights
extends RefCounted
## A bot's parameters (cycle 7 plan P7): the search caps, the level's push unit and the
## evaluator's feature weights, all whole numbers so every bot stays integer arithmetic and
## deterministic across machines (R18). Feature weights are in hundredths: a weight of 100
## counts a feature once.
##
## The file (P7, R10): a JSON object
## `{"version": 1, "bot": "tuned", "stamp": "r4-…", "k": 24, "k_opp": 12, "samples": 4,
## "rm_iterations": 200, "push_unit": 10, "weights": {"score_diff": 100, …}}`. `version` is
## required and must be FORMAT_VERSION; every other key is optional and keeps its default
## when absent; keys outside that list are ignored. load() and from_json() never print: on
## any fault (no file, bad JSON, not an object, wrong version, a field of the wrong type, a
## number that is not whole or out of range, a weight naming no Evaluator.FEATURES entry)
## they return the built-in defaults with `load_error` saying why (R11), and the launcher
## reports it. The stamp is read as written; comparing it with BotStamp.current() is the
## sweep's job (R35).

## The weights file format this build reads and writes.
const FORMAT_VERSION: int = 1
## The integer fields of the file, in the order to_json() writes them.
const INT_FIELDS: Array[String] = ["k", "k_opp", "samples", "rm_iterations", "push_unit"]
## The least value each INT_FIELDS entry accepts, in the same order.
const INT_MINIMUMS: Array[int] = [1, 1, 1, 0, 0]
## JSON numbers arrive as floats: a whole number is exact up to here.
const MAX_SAFE_FLOAT: float = 9007199254740992.0

## The bot these weights are for (the registry name), "" when unnamed.
var bot: String = ""
## The tuned bot's preview cap: how many candidates of the bound ranking are previewed (R7);
## 24 since DC-08, the cap that keeps R17's decision budget (Ben, 2026-11-04).
var k: int = 24
## The matrix bot's cap on opponent candidates (milestone B).
var k_opp: int = 12
## How many opponent hands the matrix bot samples (milestone B).
var samples: int = 4
## Regret-matching iterations of the matrix bot (milestone B).
var rm_iterations: int = 200
## The level push's spread cap (P6), about one mid card's score at ×1.00.
var push_unit: int = 10
## Feature name -> weight in hundredths (P5). Values are ints.
var weights: Dictionary = {}
## The rules-and-data stamp the weights were trained under (P8); "" for the defaults.
var stamp: String = ""
## Why loading failed ("" when it did not); the defaults are then in force (R11).
var load_error: String = ""


## The built-in weights for `bot_name`: every cap at its default and the plain
## own-minus-opponent score (`score_diff` at 100 hundredths), so a bot on the defaults
## values a candidate exactly as the greedy bot does (R11, R12).
static func defaults(bot_name: String) -> BotWeights:
	var out: BotWeights = BotWeights.new()
	out.bot = bot_name
	out.weights = {"score_diff": 100}
	return out


## The weights file at `path` (a res:// or user:// path), or the defaults with `load_error`
## set (see the class comment).
@warning_ignore("shadowed_global_identifier")
static func load(path: String) -> BotWeights:
	if not FileAccess.file_exists(path):
		return _failed("weights file not found: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failed("weights file unreadable: %s" % path)
	var text: String = file.get_as_text()
	file.close()
	return from_json(text)


## The weights in `text` (the file's JSON), or the defaults with `load_error` set.
static func from_json(text: String) -> BotWeights:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		var where: int = json.get_error_line()
		return _failed("bad JSON at line %d: %s" % [where, json.get_error_message()])
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return _failed("bad shape: not an object")
	var root: Dictionary = parsed
	var out: BotWeights = BotWeights.new()
	var problem: String = _read_header(root, out)
	if problem == "":
		problem = _read_ints(root, out)
	if problem == "":
		problem = _read_weights(root, out)
	if problem != "":
		return _failed(problem)
	return out


## The weights as the file's JSON (format FORMAT_VERSION, tab-indented): the header, the
## integer fields, then the weights in Evaluator.FEATURES order, each feature this object
## weighs. from_json() of the text gives back equal fields.
func to_json() -> String:
	var root: Dictionary = {"version": FORMAT_VERSION, "bot": bot, "stamp": stamp}
	for field: String in INT_FIELDS:
		root[field] = get(field)
	var listed: Dictionary = {}
	for feature: String in Evaluator.FEATURES:
		if weights.has(feature):
			listed[feature] = weights[feature]
	root["weights"] = listed
	return JSON.stringify(root, "\t", false)


## The defaults with `message` as the load error.
static func _failed(message: String) -> BotWeights:
	var out: BotWeights = defaults("")
	out.load_error = message
	return out


## Reads `version` (required), `bot` and `stamp` into `out`; the problem, or "".
static func _read_header(root: Dictionary, out: BotWeights) -> String:
	var version: Variant = root.get("version", null)
	if not _is_whole_number(version) or _as_int(version) != FORMAT_VERSION:
		return "unsupported version: %s (expected %d)" % [JSON.stringify(version), FORMAT_VERSION]
	var named: Variant = root.get("bot", "")
	var stamped: Variant = root.get("stamp", "")
	if not named is String:
		return "bad shape: bot is not a string"
	if not stamped is String:
		return "bad shape: stamp is not a string"
	out.bot = named
	out.stamp = stamped
	return ""


## Reads the INT_FIELDS present in `root` into `out`; the problem, or "".
static func _read_ints(root: Dictionary, out: BotWeights) -> String:
	for index: int in range(INT_FIELDS.size()):
		var field: String = INT_FIELDS[index]
		if not root.has(field):
			continue
		var raw: Variant = root[field]
		if not _is_whole_number(raw):
			return "%s is not a whole number: %s" % [field, JSON.stringify(raw)]
		var number: int = _as_int(raw)
		if number < INT_MINIMUMS[index]:
			return "%s out of range: %d (least %d)" % [field, number, INT_MINIMUMS[index]]
		out.set(field, number)
	return ""


## Reads `weights` (when present) into `out`, replacing the defaults' table: every key a
## Evaluator.FEATURES name, every value a whole number; the problem, or "".
static func _read_weights(root: Dictionary, out: BotWeights) -> String:
	if not root.has("weights"):
		out.weights = {"score_diff": 100}
		return ""
	var raw: Variant = root["weights"]
	if not raw is Dictionary:
		return "bad shape: weights is not an object"
	var table: Dictionary = raw
	var read: Dictionary = {}
	for key: Variant in table:
		if not key is String or not Evaluator.FEATURES.has(key):
			return "unknown feature: %s" % JSON.stringify(key)
		var name: String = key
		var weight: Variant = table[key]
		if not _is_whole_number(weight):
			return "weight of %s is not a whole number: %s" % [name, JSON.stringify(weight)]
		read[name] = _as_int(weight)
	out.weights = read
	return ""


## True for an int, or a finite float with no fractional part within MAX_SAFE_FLOAT (JSON
## numbers arrive as floats).
static func _is_whole_number(value: Variant) -> bool:
	if value is int:
		return true
	if not value is float:
		return false
	var number: float = value
	return is_finite(number) and number == floorf(number) and absf(number) <= MAX_SAFE_FLOAT


## `value`, already checked by _is_whole_number, as an int.
static func _as_int(value: Variant) -> int:
	if value is int:
		var whole: int = value
		return whole
	var number: float = value
	return int(number)
