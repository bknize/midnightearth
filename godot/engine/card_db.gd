class_name CardDb
extends RefCounted
## Loads and validates the 20-card list, format 2 (R1, R2, R3, C14).
##
## Loading never prints, asserts or pushes an error: every failure is reported through
## load_error(), and a failed database holds no cards, so the engine refuses to start.

const DEFAULT_PATH: String = "res://engine/data/cards.json"
const FORMAT_VERSION: int = 2
const CARD_COUNT: int = 20
const MIN_COST: int = 1
const MAX_COST: int = 7
## Cards required per cost, indexed by cost (index 0 unused): 4x1, 4x2, 3x3, 3x4, 2x5, 2x6, 2x7.
const COST_MIX: Array[int] = [0, 4, 4, 3, 3, 2, 2, 2]
## Flat must lie within 0..cost + MAX_FLAT_OVER_COST.
const MAX_FLAT_OVER_COST: int = 2

# Error prefixes, stable so tests and callers can match on them.
const ERR_FILE: String = "card data file"
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"
const ERR_COUNT: String = "wrong count"
const ERR_DUPLICATE: String = "duplicate id"
const ERR_FLAT: String = "flat out of range"
const ERR_BONUS: String = "bonus out of range"
const ERR_COST_MIX: String = "wrong cost mix"
const ERR_TRIGGER: String = "unknown trigger"
const ERR_VERB: String = "unknown verb"

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
		var entry_problem: String = _entry_problem(entries[i], i)
		if entry_problem != "":
			return _failed(entry_problem)
		defs.append(_build_entry(entries[i]))

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


## An error message for one card entry, or "" when its shape, effect names included,
## is right. Ranges are checked later by _validate().
static func _entry_problem(entry: Variant, i: int) -> String:
	var shape_error: String = (
		"%s: card %d needs a non-empty string id and name, integer cost, flat and bonus, %s"
		% [ERR_SHAPE, i, "and an effect object or null"]
	)
	if not entry is Dictionary:
		return shape_error
	var d: Dictionary = entry
	for key: String in ["id", "name", "cost", "flat", "bonus", "effect"]:
		if not d.has(key):
			return shape_error
	if not (d["id"] is String and d["name"] is String):
		return shape_error
	var card_id: String = d["id"]
	var card_name: String = d["name"]
	if card_id == "" or card_name == "":
		return shape_error
	for key: String in ["cost", "flat", "bonus"]:
		if not _is_whole_number(d[key]):
			return shape_error
	return _effect_problem(d["effect"], i)


## An error message for one entry's effect, or "" when it is null or well formed with a
## known trigger and verb.
static func _effect_problem(value: Variant, i: int) -> String:
	if value == null:
		return ""
	var shape_error: String = (
		"%s: card %d effect needs string trigger, verb and text and a whole amount >= 0"
		% [ERR_SHAPE, i]
	)
	if not value is Dictionary:
		return shape_error
	var d: Dictionary = value
	if not CardEffect.has_valid_shape(d):
		return shape_error
	var trigger_text: String = d[CardEffect.KEY_TRIGGER]
	if CardEffect.trigger_from_name(trigger_text) < 0:
		return '%s: card %d has trigger "%s"' % [ERR_TRIGGER, i, trigger_text]
	var verb_text: String = d[CardEffect.KEY_VERB]
	if CardEffect.verb_from_name(verb_text) < 0:
		return '%s: card %d has verb "%s"' % [ERR_VERB, i, verb_text]
	return ""


## Builds a CardDef from an entry already accepted by _entry_problem().
static func _build_entry(entry: Variant) -> CardDef:
	var d: Dictionary = entry
	var card_id: String = d["id"]
	var card_name: String = d["name"]
	var effect: CardEffect = null
	var raw_effect: Variant = d["effect"]
	if raw_effect is Dictionary:
		var effect_dict: Dictionary = raw_effect
		effect = CardEffect.from_dict(effect_dict)
	return CardDef.new(
		card_id, card_name, _as_int(d["cost"]), _as_int(d["flat"]), _as_int(d["bonus"]), effect
	)


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


## Returns an error message, or "" when the list satisfies R2.
static func _validate(defs: Array[CardDef]) -> String:
	if defs.size() != CARD_COUNT:
		return "%s: %d cards (expected %d)" % [ERR_COUNT, defs.size(), CARD_COUNT]

	var seen: Dictionary[String, bool] = {}
	for def: CardDef in defs:
		if seen.has(def.id):
			return "%s: %s" % [ERR_DUPLICATE, def.id]
		seen[def.id] = true

	var range_problem: String = _range_problem(defs)
	if range_problem != "":
		return range_problem

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


## The first card whose flat or bonus is out of range, as an error message, or "".
static func _range_problem(defs: Array[CardDef]) -> String:
	for def: CardDef in defs:
		var max_flat: int = def.cost + MAX_FLAT_OVER_COST
		if def.flat < 0 or def.flat > max_flat:
			return (
				"%s: %s has cost %d and flat %d (allowed 0..%d)"
				% [ERR_FLAT, def.id, def.cost, def.flat, max_flat]
			)
		if def.bonus < 0 or def.bonus > MatchRules.MAX_BONUS:
			return (
				"%s: %s has bonus %d (allowed 0..%d)"
				% [ERR_BONUS, def.id, def.bonus, MatchRules.MAX_BONUS]
			)
	return ""
