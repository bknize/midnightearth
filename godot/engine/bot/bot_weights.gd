class_name BotWeights
extends RefCounted
## The `linear` bot's weights file (cycle 13 spec R4, R8, R9; plan P2), restored from cycle 7's
## reader and cut to what R8 names. Every number is whole, so the bot stays integer
## arithmetic and deterministic across machines; weights are in hundredths, so a weight of
## 100 counts a feature once.
##
## The file: a JSON object
## `{"version": 2, "bot": "linear", "stamp": "r8-…", "features": "f1", "k": 64,
## "fit": {"id": "…", "runs": ["…"], "digest": "…"}, "weights": {"committed_power": 100, …}}`.
## `version` and `features` are required and must be FORMAT_VERSION and
## BotFeatures.SET_VERSION; every other key is optional and keeps its default when absent;
## keys outside that list are ignored. A weight a file does not name is 0. load() and
## from_json() never print: on any fault (no file, bad JSON, not an object, another format
## version or feature set, a field of the wrong type, `k` below 1, a weight naming no feature
## of the set, a weight that is not whole or beyond MAX_WEIGHT) they return defaults() with
## `load_error` saying why, and the launcher reports it (R9; the engine prints nothing,
## cycle 7 R11). The stamp is read as written; stamp_matches() compares it with
## BotStamp.current().

## The weights file format this build reads and writes.
const FORMAT_VERSION: int = 2
## The bot a weights file is for.
const BOT_NAME: String = "linear"
## The committed weights file (spec Clarifications; plan P15).
const DEFAULT_PATH: String = "res://engine/bot/data/linear_weights.json"
## The candidates the bot scores at most per decision when the file names no `k`.
const DEFAULT_K: int = 64
## The one feature the built-in defaults weigh, and its weight: committed Power once (R9).
const DEFAULT_FEATURE: String = "committed_power"
const DEFAULT_WEIGHT: int = 100
## JSON numbers arrive as floats: a whole number is exact up to here.
const MAX_SAFE_FLOAT: float = 9007199254740992.0
## The largest weight accepted either way, in hundredths (10000 times a feature).
const MAX_WEIGHT: int = 1000000

## Parsed files by path (cached()), so a rollout that builds two bots per play-out parses
## its file once per process.
static var _cache: Dictionary = {}
## The feature names of the shipped card pool (known_names()), built on first use.
static var _shipped_names: Array[String] = []

## The bot these weights are for.
var bot: String = BOT_NAME
## The rules-and-data stamp the weights were fitted under; "" when the file names none.
var stamp: String = ""
## The feature set the weights are laid out for (BotFeatures.SET_VERSION).
var features: String = BotFeatures.SET_VERSION
## How many candidates the bot scores at most per decision (R6).
var k: int = DEFAULT_K
## The fit that produced the weights: {"id": String, "runs": Array of String, "digest":
## String}; empty strings and an empty list for the defaults.
var fit: Dictionary = _empty_fit()
## Feature name -> weight in hundredths. Values are ints.
var weights: Dictionary = {}
## Why loading failed ("" when it did not); the defaults are then in force (R9).
var load_error: String = ""
## vector_for()'s memo: the pool it was built for (MatchCards.pool_key; -1 before the first
## call) and the vector.
var _vector_key: int = -1
var _vector_memo: PackedInt64Array = PackedInt64Array()


## The built-in weights: committed Power counted once, every other feature 0, `k`
## DEFAULT_K, no stamp and no fit (R9).
static func defaults() -> BotWeights:
	var out: BotWeights = BotWeights.new()
	out.weights = {DEFAULT_FEATURE: DEFAULT_WEIGHT}
	return out


## The weights file at `path` (a res://, user:// or absolute path), or the defaults with
## `load_error` set (see the class comment).
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


## load(`path`) once per path per process; the same object on every later call, so callers
## must treat it as read-only. An empty `path` is DEFAULT_PATH.
static func cached(path: String) -> BotWeights:
	var key: String = path if path != "" else DEFAULT_PATH
	if _cache.has(key):
		var held: BotWeights = _cache[key]
		return held
	var loaded: BotWeights = BotWeights.load(key)
	_cache[key] = loaded
	return loaded


## Drops every cached file (a suite that rewrites a file between reads).
static func forget_cached() -> void:
	_cache.clear()


## The weights in `text` (the file's JSON), or the defaults with `load_error` set. A weight
## must name one of `known` (known_names() when empty).
static func from_json(text: String, known: Array[String] = []) -> BotWeights:
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
		problem = _read_fit(root, out)
	if problem == "":
		var names: Array[String] = known if not known.is_empty() else known_names()
		problem = _read_weights(root, out, names)
	if problem != "":
		return _failed(problem)
	return out


## Every feature name a weights file may weigh: BotFeatures.COMPACT, then `card:<id>` for
## every card of the shipped pool (CardDb.DEFAULT_PATH), in CardDb order. Only COMPACT when
## the pool fails to load.
static func known_names() -> Array[String]:
	if _shipped_names.is_empty():
		var names: Array[String] = []
		names.assign(BotFeatures.COMPACT)
		var pool: CardDb = CardDb.load_default()
		if pool.is_valid():
			for def: CardDef in pool.cards():
				names.append(BotFeatures.CARD_PREFIX + def.id)
		_shipped_names = names
	var out: Array[String] = []
	out.assign(_shipped_names)
	return out


## The weights laid out as `names` (BotFeatures.names() order): each name's weight, 0 for a
## name the file does not weigh.
func vector(names: Array[String]) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	if out.resize(names.size()) != OK:
		return out
	for index: int in range(names.size()):
		var name: String = names[index]
		if weights.has(name):
			var weight: int = weights[name]
			out[index] = weight
	return out


## vector(BotFeatures.names(`cards`)), built once per card pool (MatchCards.pool_key) and
## kept on this object, so the bots of every play-out over one pool share it. Assumes
## `weights` is not changed after the first call (the object is read-only once loaded).
func vector_for(cards: MatchCards) -> PackedInt64Array:
	var key: int = MatchCards.pool_key(cards)
	if key != _vector_key:
		_vector_memo = vector(BotFeatures.names(cards))
		_vector_key = key
	return _vector_memo


## Whether the file's stamp is the current engine's (BotStamp.current()); false for no stamp.
func stamp_matches() -> bool:
	return stamp != "" and stamp == BotStamp.current()


## The weights as the file's JSON (format FORMAT_VERSION, tab-indented): the header, `k`,
## the fit, then every weight this object holds in known_names() order, any other name
## after them in its own order. from_json() of the text gives back equal fields.
func to_json() -> String:
	var root: Dictionary = {
		"version": FORMAT_VERSION,
		"bot": bot,
		"stamp": stamp,
		"features": features,
		"k": k,
		"fit": fit.duplicate(true),
	}
	var listed: Dictionary = {}
	for name: String in known_names():
		if weights.has(name):
			listed[name] = weights[name]
	for key: Variant in weights:
		if not listed.has(key):
			listed[key] = weights[key]
	root["weights"] = listed
	return JSON.stringify(root, "\t", false)


## The defaults with `message` as the load error.
static func _failed(message: String) -> BotWeights:
	var out: BotWeights = defaults()
	out.load_error = message
	return out


## A fit naming nothing.
static func _empty_fit() -> Dictionary:
	return {"id": "", "runs": [], "digest": ""}


## Reads `version` and `features` (both required), `bot`, `stamp` and `k` into `out`; the
## problem, or "".
static func _read_header(root: Dictionary, out: BotWeights) -> String:
	var version: Variant = root.get("version", null)
	if not _is_whole_number(version) or _as_int(version) != FORMAT_VERSION:
		return "unsupported version: %s (expected %d)" % [JSON.stringify(version), FORMAT_VERSION]
	var set_version: Variant = root.get("features", null)
	if not set_version is String or set_version != BotFeatures.SET_VERSION:
		return (
			"feature set %s is not the engine's (%s)"
			% [JSON.stringify(set_version), BotFeatures.SET_VERSION]
		)
	var named: Variant = root.get("bot", BOT_NAME)
	var stamped: Variant = root.get("stamp", "")
	if not named is String:
		return "bad shape: bot is not a string"
	if not stamped is String:
		return "bad shape: stamp is not a string"
	out.bot = named
	out.stamp = stamped
	out.features = BotFeatures.SET_VERSION
	if root.has("k"):
		var raw: Variant = root["k"]
		if not _is_whole_number(raw):
			return "k is not a whole number: %s" % JSON.stringify(raw)
		var number: int = _as_int(raw)
		if number < 1:
			return "k out of range: %d (least 1)" % number
		out.k = number
	return ""


## Reads `fit` (when present) into `out`: an object whose `id` and `digest` are strings and
## whose `runs` is a list of strings, each optional; the problem, or "".
static func _read_fit(root: Dictionary, out: BotWeights) -> String:
	if not root.has("fit"):
		return ""
	var raw: Variant = root["fit"]
	if not raw is Dictionary:
		return "bad shape: fit is not an object"
	var given: Dictionary = raw
	var read: Dictionary = _empty_fit()
	for key: String in ["id", "digest"]:
		var value: Variant = given.get(key, "")
		if not value is String:
			return "bad shape: fit.%s is not a string" % key
		read[key] = value
	var runs: Variant = given.get("runs", [])
	if not runs is Array:
		return "bad shape: fit.runs is not a list"
	var listed: Array = runs
	var ids: Array = []
	for run: Variant in listed:
		if not run is String:
			return "bad shape: fit.runs holds %s" % JSON.stringify(run)
		ids.append(run)
	read["runs"] = ids
	out.fit = read
	return ""


## Reads `weights` (when present) into `out`, replacing the defaults' table: every key one
## of `known`, every value a whole number within MAX_WEIGHT; the problem, or "".
static func _read_weights(root: Dictionary, out: BotWeights, known: Array[String]) -> String:
	if not root.has("weights"):
		out.weights = {DEFAULT_FEATURE: DEFAULT_WEIGHT}
		return ""
	var raw: Variant = root["weights"]
	if not raw is Dictionary:
		return "bad shape: weights is not an object"
	var table: Dictionary = raw
	var read: Dictionary = {}
	for key: Variant in table:
		if not key is String or not known.has(key):
			return "unknown feature: %s" % JSON.stringify(key)
		var name: String = key
		var weight: Variant = table[key]
		if not _is_whole_number(weight):
			return "weight of %s is not a whole number: %s" % [name, JSON.stringify(weight)]
		var whole: int = _as_int(weight)
		if absi(whole) > MAX_WEIGHT:
			return "weight of %s out of range: %d (limit %d)" % [name, whole, MAX_WEIGHT]
		read[name] = whole
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
