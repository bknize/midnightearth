class_name CardDb
extends RefCounted
## Loads and validates the 20-card list (R7, R8, R10, C6, C7).
##
## Loading never prints, asserts or pushes an error: every failure is reported through
## load_error(), and a failed database holds no cards, so the engine refuses to start.

const DEFAULT_PATH: String = "res://engine/data/cards.json"
const FORMAT_VERSION: int = 1
const CARD_COUNT: int = 20
const MIN_COST: int = 1
const MAX_COST: int = 7
## Cards required per cost, indexed by cost (index 0 unused): 4x1, 4x2, 3x3, 3x4, 2x5, 2x6, 2x7.
const COST_MIX: Array[int] = [0, 4, 4, 3, 3, 2, 2, 2]
## Power must lie within cost..cost + MAX_POWER_BONUS.
const MAX_POWER_BONUS: int = 2

# Error prefixes, stable so tests and callers can match on them.
const ERR_FILE: String = "card data file"
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"
const ERR_COUNT: String = "wrong count"
const ERR_DUPLICATE: String = "duplicate id"
const ERR_POWER: String = "power out of range"
const ERR_COST_MIX: String = "wrong cost mix"

var _cards: Array[CardDef] = []
var _index_by_id: Dictionary[String, int] = {}
var _error: String = ""


## Loads res://engine/data/cards.json.
static func load_default() -> CardDb:
	return load_from_path(DEFAULT_PATH)


## Loads a card file from any path. Missing or unreadable files fail silently.
static func load_from_path(path: String) -> CardDb:
	if not FileAccess.file_exists(path):
		return _failed("%s not found: %s" % [ERR_FILE, path])
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failed("%s unreadable: %s" % [ERR_FILE, path])
	var text: String = file.get_as_text()
	file.close()
	return from_json(text)


## Loads a card list from JSON text (used by tests with in-memory data).
static func from_json(text: String) -> CardDb:
	# JSON.new().parse() reports through its return code and get_error_message();
	# unlike JSON.parse_string() it does not log an error on malformed input.
	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(text)
	if parse_err != OK:
		return _failed(
			"%s at line %d: %s" % [ERR_JSON, json.get_error_line(), json.get_error_message()]
		)
	var data: Variant = json.data
	if not data is Dictionary:
		return _failed("%s: top level is not an object" % ERR_SHAPE)
	var root: Dictionary = data
	if not root.has("version") or not _is_whole_number(root["version"]):
		return _failed("%s: missing or non-integer version" % ERR_SHAPE)
	var version: int = _as_int(root["version"])
	if version != FORMAT_VERSION:
		return _failed("%s: %d (expected %d)" % [ERR_VERSION, version, FORMAT_VERSION])
	if not root.has("cards") or not root["cards"] is Array:
		return _failed("%s: missing cards array" % ERR_SHAPE)
	var entries: Array = root["cards"]

	var defs: Array[CardDef] = []
	for i: int in range(entries.size()):
		var parsed: CardDef = _parse_entry(entries[i])
		if parsed == null:
			return _failed(
				(
					"%s: card %d needs a non-empty string id and name and integer cost and power"
					% [ERR_SHAPE, i]
				)
			)
		defs.append(parsed)

	var problem: String = _validate(defs)
	if problem != "":
		return _failed(problem)

	var db: CardDb = CardDb.new()
	db._cards = defs
	for i: int in range(defs.size()):
		db._index_by_id[defs[i].id] = i
	return db


func is_valid() -> bool:
	return _error == ""


## Empty when the load succeeded.
func load_error() -> String:
	return _error


## Number of definitions (0 when the load failed).
func size() -> int:
	return _cards.size()


## The definition at a 0-based file position, or null when out of range.
func card_at(index: int) -> CardDef:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index]


## The definition with this id, or null when absent.
func card_by_id(card_id: String) -> CardDef:
	var index: int = index_of(card_id)
	if index < 0:
		return null
	return _cards[index]


## The 0-based file position of this id, or -1 when absent.
func index_of(card_id: String) -> int:
	if not _index_by_id.has(card_id):
		return -1
	return _index_by_id[card_id]


## A copy of every definition in file order.
func cards() -> Array[CardDef]:
	var out: Array[CardDef] = []
	out.assign(_cards)
	return out


static func _failed(message: String) -> CardDb:
	var db: CardDb = CardDb.new()
	db._error = message
	return db


static func _parse_entry(entry: Variant) -> CardDef:
	if not entry is Dictionary:
		return null
	var d: Dictionary = entry
	if not (d.has("id") and d.has("name") and d.has("cost") and d.has("power")):
		return null
	if not (d["id"] is String and d["name"] is String):
		return null
	if not (_is_whole_number(d["cost"]) and _is_whole_number(d["power"])):
		return null
	var card_id: String = d["id"]
	var card_name: String = d["name"]
	if card_id == "" or card_name == "":
		return null
	return CardDef.new(card_id, card_name, _as_int(d["cost"]), _as_int(d["power"]))


## Converts a value already checked by _is_whole_number to int without an unsafe call.
static func _as_int(value: Variant) -> int:
	if value is int:
		var whole: int = value
		return whole
	var number: float = value
	return int(number)


## JSON numbers arrive as floats; accept ints and floats with no fractional part.
static func _is_whole_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var f: float = value
		return is_finite(f) and f == floorf(f)
	return false


## Returns an error message, or "" when the list satisfies R8.
static func _validate(defs: Array[CardDef]) -> String:
	if defs.size() != CARD_COUNT:
		return "%s: %d cards (expected %d)" % [ERR_COUNT, defs.size(), CARD_COUNT]

	var seen: Dictionary[String, bool] = {}
	for def: CardDef in defs:
		if seen.has(def.id):
			return "%s: %s" % [ERR_DUPLICATE, def.id]
		seen[def.id] = true

	for def: CardDef in defs:
		if def.power < def.cost or def.power > def.cost + MAX_POWER_BONUS:
			return (
				"%s: %s has cost %d and power %d (allowed %d..%d)"
				% [ERR_POWER, def.id, def.cost, def.power, def.cost, def.cost + MAX_POWER_BONUS]
			)

	var counts: Array[int] = []
	for _slot: int in range(MAX_COST + 1):
		counts.append(0)
	for def: CardDef in defs:
		if def.cost < MIN_COST or def.cost > MAX_COST:
			return (
				"%s: %s has cost %d outside %d..%d"
				% [ERR_COST_MIX, def.id, def.cost, MIN_COST, MAX_COST]
			)
		counts[def.cost] += 1
	for cost: int in range(MIN_COST, MAX_COST + 1):
		if counts[cost] != COST_MIX[cost]:
			return (
				"%s: %d cards at cost %d (expected %d)"
				% [ERR_COST_MIX, counts[cost], cost, COST_MIX[cost]]
			)
	return ""
