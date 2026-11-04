class_name CardDb
extends RefCounted
## Loads and validates a card pool, format 3 (R1, R3, plan P1).
##
## {"version": 3, "cards": [{"id", "name", "cost", "flat", "bonus", "effect"}]}, where
## `bonus` is null, {"x": hundredths} or {"plus": units} and `effect` is null or a
## CardEffect object. The checks (R3, C13): unique ids, cost 1..7, flat
## 0..cost + MatchRules.MAX_FLAT_OVER_COST, a bonus in MatchRules.TIMES_VALUES or
## MatchRules.PLUS_VALUES, a known trigger and verb. A pool has no card count and no cost
## mix (C3): decks are checked by DeckList.validate().
##
## Loading never prints, asserts or pushes an error: every failure is reported through
## load_error(), and a failed database holds no cards, so the engine refuses to start.

const DEFAULT_PATH: String = "res://engine/data/cards.json"
const FORMAT_VERSION: int = 3
const MIN_COST: int = 1
const MAX_COST: int = 7

# Error prefixes, stable so tests and callers can match on them.
const ERR_FILE: String = "card data file"
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"
const ERR_DUPLICATE: String = "duplicate id"
const ERR_COST: String = "cost out of range"
const ERR_FLAT: String = "flat out of range"
const ERR_BONUS: String = "bonus out of range"
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


## Loads a card pool from JSON text (used by tests with in-memory data).
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


## Whether the pool holds a card with this id.
func has_id(card_id: String) -> bool:
	return _index_by_id.has(card_id)


## A copy of every definition in file order.
func cards() -> Array[CardDef]:
	var out: Array[CardDef] = []
	out.assign(_cards)
	return out


static func _failed(message: String) -> CardDb:
	var db: CardDb = CardDb.new()
	db._error = message
	return db


## An error message for one card entry, or "" when its shape, bonus value and effect
## names included, is right. Cost and flat ranges are checked later by _validate().
static func _entry_problem(entry: Variant, i: int) -> String:
	var shape_error: String = (
		"%s: card %d needs a non-empty string id and name, integer cost and flat, %s"
		% [ERR_SHAPE, i, "a bonus object or null and an effect object or null"]
	)
	if not entry is Dictionary:
		return shape_error
	var d: Dictionary = entry
	if not _has_card_fields(d):
		return shape_error
	var bonus_problem: String = _bonus_problem(d["bonus"], i)
	if bonus_problem != "":
		return bonus_problem
	return _effect_problem(d["effect"], i)


## Whether `d` has every card key, a non-empty string id and name and whole cost and flat.
static func _has_card_fields(d: Dictionary) -> bool:
	for key: String in ["id", "name", "cost", "flat", "bonus", "effect"]:
		if not d.has(key):
			return false
	if not (d["id"] is String and d["name"] is String):
		return false
	var card_id: String = d["id"]
	var card_name: String = d["name"]
	if card_id == "" or card_name == "":
		return false
	return _is_whole_number(d["cost"]) and _is_whole_number(d["flat"])


## An error message for one entry's bonus, or "" when it is null or one key, "x" or
## "plus", holding a whole number from MatchRules.TIMES_VALUES or PLUS_VALUES.
static func _bonus_problem(value: Variant, i: int) -> String:
	if value == null:
		return ""
	var shape_error: String = (
		'%s: card %d bonus needs null, {"x": hundredths} or {"plus": units}' % [ERR_SHAPE, i]
	)
	if not value is Dictionary:
		return shape_error
	var d: Dictionary = value
	if d.size() != 1:
		return shape_error
	var kind: CardDef.BonusKind = _bonus_kind_of(d)
	if kind == CardDef.BonusKind.NONE:
		return shape_error
	var amount: int = _bonus_amount_of(d, kind)
	var allowed: Array[int] = _allowed_bonuses(kind)
	if not allowed.has(amount):
		return "%s: card %d has bonus %s (allowed %s)" % [ERR_BONUS, i, JSON.stringify(d), allowed]
	return ""


## The kind of a one-key bonus object whose value is a whole number, or NONE when its key
## is neither "x" nor "plus" or its value is not whole.
static func _bonus_kind_of(d: Dictionary) -> CardDef.BonusKind:
	var kind: CardDef.BonusKind = CardDef.BonusKind.NONE
	var key: String = CardDef.KEY_TIMES
	if d.has(CardDef.KEY_TIMES):
		kind = CardDef.BonusKind.TIMES
	elif d.has(CardDef.KEY_PLUS):
		kind = CardDef.BonusKind.PLUS
		key = CardDef.KEY_PLUS
	if kind == CardDef.BonusKind.NONE or not _is_whole_number(d[key]):
		return CardDef.BonusKind.NONE
	return kind


## The whole-number amount of a bonus object of `kind` (already checked by _bonus_kind_of).
static func _bonus_amount_of(d: Dictionary, kind: CardDef.BonusKind) -> int:
	if kind == CardDef.BonusKind.TIMES:
		return _as_int(d[CardDef.KEY_TIMES])
	if kind == CardDef.BonusKind.PLUS:
		return _as_int(d[CardDef.KEY_PLUS])
	return 0


## The legal amounts of a bonus kind (none for NONE).
static func _allowed_bonuses(kind: CardDef.BonusKind) -> Array[int]:
	var out: Array[int] = []
	if kind == CardDef.BonusKind.TIMES:
		out.assign(MatchRules.TIMES_VALUES)
	elif kind == CardDef.BonusKind.PLUS:
		out.assign(MatchRules.PLUS_VALUES)
	return out


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
	var kind: CardDef.BonusKind = CardDef.BonusKind.NONE
	var amount: int = 0
	var raw_bonus: Variant = d["bonus"]
	if raw_bonus is Dictionary:
		var bonus_dict: Dictionary = raw_bonus
		kind = _bonus_kind_of(bonus_dict)
		amount = _bonus_amount_of(bonus_dict, kind)
	return CardDef.new(
		card_id, card_name, _as_int(d["cost"]), _as_int(d["flat"]), kind, amount, effect
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


## Returns an error message, or "" when the pool satisfies R3: unique ids, then each
## card's cost and flat in range.
static func _validate(defs: Array[CardDef]) -> String:
	var seen: Dictionary[String, bool] = {}
	for def: CardDef in defs:
		if seen.has(def.id):
			return "%s: %s" % [ERR_DUPLICATE, def.id]
		seen[def.id] = true
	return _range_problem(defs)


## The first card whose cost or flat is out of range, as an error message, or "".
static func _range_problem(defs: Array[CardDef]) -> String:
	for def: CardDef in defs:
		if def.cost < MIN_COST or def.cost > MAX_COST:
			return (
				"%s: %s has cost %d (allowed %d..%d)"
				% [ERR_COST, def.id, def.cost, MIN_COST, MAX_COST]
			)
		var max_flat: int = def.cost + MatchRules.MAX_FLAT_OVER_COST
		if def.flat < 0 or def.flat > max_flat:
			return (
				"%s: %s has cost %d and flat %d (allowed 0..%d)"
				% [ERR_FLAT, def.id, def.cost, def.flat, max_flat]
			)
	return ""
