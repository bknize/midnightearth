class_name CardDb
extends RefCounted
## Loads and validates a card pool, format 5 (cycle 9 plan P2, spec R22, R60, R64).
##
## {"version": 5, "cards": [{"id", "name", "tag", "cost", "power", "bonus", "abilities",
## "text"}]}, where `bonus` is null, {"mult": hundredths} or {"add": hundredths} and
## `abilities` a list of CardAbility objects (P3). `bonus` (null), `abilities` ([]) and
## `text` ("") may be left out. The checks, each failing by its name: version 5; unique ids;
## a tag in CardDef.TAGS; Cost 1..MatchRules.MAX_PRINTED_COST unless an ability has the
## verb CardAbility.COST_EXCEPTION_VERB (then any Cost from 1); Power MIN_POWER..MAX_POWER;
## a Bonus in MatchRules.MULT_VALUES or ADD_VALUES; each ability per CardAbility.problem_of
## (a known moment and verb, the verb allowed on the moment, amounts in range, known scope,
## watch and zone, whole uses, its own text); a non-empty card `text` when it has
## abilities. A pool has no card count: decks are checked by DeckList.validate().
## An optional `"created": true` (KEY_DROSS: the pool keeps that key name) marks a Dross
## definition, made only by an ability, never dealt from a Deck (the Dross card, DC-14 T12):
## cards_tagged() leaves it out and dross_cards() lists it. A Dross definition may carry
## `"lifetime"`: CardDef.LIFETIME_ROUND (the default when absent: removed at the end of the
## Round) or CardDef.LIFETIME_MATCH (lasts the Match); any other value, `until_piled`
## included, fails with ERR_LIFETIME (rules 9, cycle 14 R9, C13). The key is read only for
## a Dross definition; the format version stays 5.
##
## Loading never prints, asserts or pushes an error: every failure is reported through
## load_error(), and a failed database holds no cards, so the engine refuses to start.

const DEFAULT_PATH: String = "res://engine/data/cards.json"
const FORMAT_VERSION: int = 5
const MIN_COST: int = 1
const MAX_COST: int = MatchRules.MAX_PRINTED_COST
const MIN_POWER: int = -20
const MAX_POWER: int = 40

# Error prefixes, stable so tests and callers can match on them.
const ERR_FILE: String = "card data file"
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"
const ERR_DUPLICATE: String = "duplicate id"
const ERR_TAG: String = "unknown tag"
const ERR_COST: String = "cost out of range"
const ERR_POWER: String = "power out of range"
const ERR_BONUS: String = "bonus out of range"
const ERR_MOMENT: String = CardAbility.ERR_MOMENT
const ERR_VERB: String = CardAbility.ERR_VERB
const ERR_PAIR: String = CardAbility.ERR_PAIR
const ERR_AMOUNT: String = CardAbility.ERR_AMOUNT
const ERR_SCOPE: String = CardAbility.ERR_SCOPE
const ERR_WATCH: String = CardAbility.ERR_WATCH
const ERR_ZONE: String = CardAbility.ERR_ZONE
const ERR_USES: String = CardAbility.ERR_USES
const ERR_TEXT: String = CardAbility.ERR_TEXT
const ERR_LIFETIME: String = "unknown lifetime"

const KEY_ID: String = "id"
const KEY_NAME: String = "name"
const KEY_TAG: String = "tag"
const KEY_COST: String = "cost"
const KEY_POWER: String = "power"
const KEY_BONUS: String = "bonus"
const KEY_ABILITIES: String = "abilities"
const KEY_TEXT: String = "text"
## The pool key of a Dross definition (CardDef.dross): cards.json keeps the name `created`.
const KEY_DROSS: String = "created"
const KEY_LIFETIME: String = "lifetime"

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
	var root_problem: String = _root_problem(root)
	if root_problem != "":
		return _failed(root_problem)
	var entries: Array = root["cards"]
	var db: CardDb = CardDb.new()
	for i: int in range(entries.size()):
		var entry_problem: String = _entry_problem(entries[i], i)
		if entry_problem != "":
			return _failed(entry_problem)
		var def: CardDef = _build_entry(entries[i])
		if db._index_by_id.has(def.id):
			return _failed("%s: %s" % [ERR_DUPLICATE, def.id])
		db._index_by_id[def.id] = db._cards.size()
		db._cards.append(def)
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


## The Deck cards with tag `tag`, in file order (a Dross definition is left out).
func cards_tagged(tag: String) -> Array[CardDef]:
	var out: Array[CardDef] = []
	for def: CardDef in _cards:
		if def.tag == tag and not def.dross:
			out.append(def)
	return out


## The Dross definitions (`"created": true`: the Dross card), in file order (C13).
func dross_cards() -> Array[CardDef]:
	var out: Array[CardDef] = []
	for def: CardDef in _cards:
		if def.dross:
			out.append(def)
	return out


static func _failed(message: String) -> CardDb:
	var db: CardDb = CardDb.new()
	db._error = message
	return db


## The first problem of the pool's top level, or "": a whole `version` equal to
## FORMAT_VERSION and a `cards` array.
static func _root_problem(root: Dictionary) -> String:
	if not root.has("version") or not EngineAction.is_whole_number(root["version"]):
		return "%s: missing or non-integer version" % ERR_SHAPE
	var version: int = EngineAction.as_int(root["version"])
	if version != FORMAT_VERSION:
		return "%s: %d (expected %d)" % [ERR_VERSION, version, FORMAT_VERSION]
	if not root.has("cards") or not root["cards"] is Array:
		return "%s: missing cards array" % ERR_SHAPE
	return ""


## The first problem of one card entry, as an error message naming card `i`, or "".
static func _entry_problem(entry: Variant, i: int) -> String:
	var shape_error: String = (
		"%s: card %d needs a non-empty string id and name, a string tag, whole cost and %s"
		% [ERR_SHAPE, i, "power, a bonus object or null, an abilities array and a string text"]
	)
	if not entry is Dictionary:
		return shape_error
	var d: Dictionary = entry
	if not _has_card_fields(d):
		return shape_error
	var tag: String = d[KEY_TAG]
	if not CardDef.TAGS.has(tag):
		return '%s: card %d has tag "%s" (allowed %s)' % [ERR_TAG, i, tag, str(CardDef.TAGS)]
	var bonus_problem: String = _bonus_problem(d.get(KEY_BONUS), i)
	if bonus_problem != "":
		return bonus_problem
	var abilities: Array = d.get(KEY_ABILITIES, [])
	for a: int in range(abilities.size()):
		var ability_problem: String = CardAbility.problem_of(abilities[a])
		if ability_problem != "":
			return "%s (card %d, ability %d)" % [ability_problem, i, a]
	var text: String = d.get(KEY_TEXT, "")
	if not abilities.is_empty() and text == "":
		return "%s: card %d has abilities and no rules text" % [ERR_TEXT, i]
	return _range_problem(d, abilities, i)


## Whether `d` has a non-empty string id and name, a string tag, whole cost and power, and
## (when present) an abilities array and a string text.
static func _has_card_fields(d: Dictionary) -> bool:
	for key: String in [KEY_ID, KEY_NAME, KEY_TAG]:
		if not d.get(key) is String:
			return false
	var card_id: String = d[KEY_ID]
	var card_name: String = d[KEY_NAME]
	if card_id == "" or card_name == "":
		return false
	if not EngineAction.is_whole_number(d.get(KEY_COST)):
		return false
	if not EngineAction.is_whole_number(d.get(KEY_POWER)):
		return false
	if d.has(KEY_ABILITIES) and not d[KEY_ABILITIES] is Array:
		return false
	if d.has(KEY_DROSS) and not d[KEY_DROSS] is bool:
		return false
	return not d.has(KEY_TEXT) or d[KEY_TEXT] is String


## The cost, power and lifetime problem of a card entry (fields already checked), or "".
static func _range_problem(d: Dictionary, abilities: Array, i: int) -> String:
	var cost: int = EngineAction.as_int(d[KEY_COST])
	var max_cost: int = MAX_COST
	if _has_cost_exception(abilities):
		max_cost = cost
	if cost < MIN_COST or cost > max_cost:
		return (
			"%s: card %d has cost %d (allowed %d..%d unless it has %s)"
			% [ERR_COST, i, cost, MIN_COST, MAX_COST, CardAbility.COST_EXCEPTION_VERB]
		)
	var power: int = EngineAction.as_int(d[KEY_POWER])
	if power < MIN_POWER or power > MAX_POWER:
		return (
			"%s: card %d has power %d (allowed %d..%d)"
			% [ERR_POWER, i, power, MIN_POWER, MAX_POWER]
		)
	return _lifetime_problem(d, i)


## The lifetime problem of a Dross entry, or "": absent, or a string in CardDef.LIFETIMES. A
## card that is not Dross is not read for it.
static func _lifetime_problem(d: Dictionary, i: int) -> String:
	var dross: bool = d.get(KEY_DROSS, false)
	if not dross or not d.has(KEY_LIFETIME):
		return ""
	var raw: Variant = d[KEY_LIFETIME]
	if raw is String and CardDef.LIFETIMES.has(raw):
		return ""
	return "%s: card %d has lifetime %s (allowed %s)" % [
		ERR_LIFETIME, i, JSON.stringify(raw), str(CardDef.LIFETIMES)
	]


## Whether one of `abilities` (already accepted) has the Cost exception verb (R12).
static func _has_cost_exception(abilities: Array) -> bool:
	for raw: Variant in abilities:
		var ability: Dictionary = raw
		var verb: String = ability[CardAbility.KEY_VERB]
		if verb == CardAbility.COST_EXCEPTION_VERB:
			return true
	return false


## An error message for one entry's bonus, or "" when it is null or one key, "mult" or
## "add", holding a whole number from MatchRules.MULT_VALUES or ADD_VALUES.
static func _bonus_problem(value: Variant, i: int) -> String:
	if value == null:
		return ""
	var shape_error: String = (
		'%s: card %d bonus needs null, {"mult": hundredths} or {"add": hundredths}'
		% [ERR_SHAPE, i]
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
## is neither "mult" nor "add" or its value is not whole.
static func _bonus_kind_of(d: Dictionary) -> CardDef.BonusKind:
	var kind: CardDef.BonusKind = CardDef.BonusKind.NONE
	var key: String = CardDef.KEY_MULT
	if d.has(CardDef.KEY_MULT):
		kind = CardDef.BonusKind.MULT
	elif d.has(CardDef.KEY_ADD):
		kind = CardDef.BonusKind.ADD
		key = CardDef.KEY_ADD
	if kind == CardDef.BonusKind.NONE or not EngineAction.is_whole_number(d[key]):
		return CardDef.BonusKind.NONE
	return kind


## The whole-number amount of a bonus object of `kind` (already checked by _bonus_kind_of).
static func _bonus_amount_of(d: Dictionary, kind: CardDef.BonusKind) -> int:
	if kind == CardDef.BonusKind.MULT:
		return EngineAction.as_int(d[CardDef.KEY_MULT])
	if kind == CardDef.BonusKind.ADD:
		return EngineAction.as_int(d[CardDef.KEY_ADD])
	return 0


## The legal amounts of a bonus kind (none for NONE).
static func _allowed_bonuses(kind: CardDef.BonusKind) -> Array[int]:
	var out: Array[int] = []
	if kind == CardDef.BonusKind.MULT:
		out.assign(MatchRules.MULT_VALUES)
		out.append_array(MatchRules.MULT_BELOW_ONE)
	elif kind == CardDef.BonusKind.ADD:
		out.assign(MatchRules.ADD_VALUES)
	return out


## Builds a CardDef from an entry already accepted by _entry_problem().
static func _build_entry(entry: Variant) -> CardDef:
	var d: Dictionary = entry
	var card_id: String = d[KEY_ID]
	var card_name: String = d[KEY_NAME]
	var tag: String = d[KEY_TAG]
	var text: String = d.get(KEY_TEXT, "")
	var abilities: Array[CardAbility] = []
	var raw_abilities: Array = d.get(KEY_ABILITIES, [])
	for raw: Variant in raw_abilities:
		var ability: Dictionary = raw
		abilities.append(CardAbility.from_dict(ability))
	var kind: CardDef.BonusKind = CardDef.BonusKind.NONE
	var amount: int = 0
	var raw_bonus: Variant = d.get(KEY_BONUS)
	if raw_bonus is Dictionary:
		var bonus_dict: Dictionary = raw_bonus
		kind = _bonus_kind_of(bonus_dict)
		amount = _bonus_amount_of(bonus_dict, kind)
	var def: CardDef = CardDef.new(
		card_id,
		card_name,
		tag,
		EngineAction.as_int(d[KEY_COST]),
		EngineAction.as_int(d[KEY_POWER]),
		kind,
		amount,
		abilities,
		text
	)
	var dross: bool = d.get(KEY_DROSS, false)
	def.dross = dross
	if dross:
		var lifetime: String = d.get(KEY_LIFETIME, CardDef.LIFETIME_ROUND)
		def.lifetime = lifetime
	return def
