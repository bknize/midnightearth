class_name CrewPool
extends RefCounted
## Loads and validates the Crew pool, v2 (cycle 9 plan P4, spec R62, R64):
## {"version": 2, "crew": [{"id", "name", "tag", "moment", "verb", "amount", "amount_2",
## "optional", "uses", "scope", "text"}, ...]} (CrewDef). `amount`, `amount_2` (0),
## `optional` (false), `uses` (0) and `scope` ("") may be left out.
##
## The checks, each failing by its name: version 2; unique non-empty string ids and names; a
## tag in CardDef.TAGS; a known moment (CardAbility.MOMENTS) and verb (CrewDef.VERBS), the
## verb on its own moment; each amount whole and within the verb's range; a bool `optional`;
## a whole `uses` >= 0; a scope in CardAbility.SCOPES or ""; a non-empty string text. The
## pool has no Crew count: each deck names three of it (DeckList.validate).
##
## Like CardDb, loading never prints, asserts or pushes an error: every failure is reported
## through load_error() (and validate()), and a failed pool holds no Crew, so a deck list
## checked against it fails and the engine refuses to start.

const DEFAULT_PATH: String = "res://engine/data/crew.json"
const FORMAT_VERSION: int = 2

const KEY_ID: String = "id"
const KEY_NAME: String = "name"
const KEY_TAG: String = "tag"
const KEY_MOMENT: String = "moment"
const KEY_VERB: String = "verb"
const KEY_AMOUNT: String = "amount"
const KEY_AMOUNT_2: String = "amount_2"
const KEY_OPTIONAL: String = "optional"
const KEY_USES: String = "uses"
const KEY_SCOPE: String = "scope"
const KEY_TEXT: String = "text"
## The keys whose value must be a non-empty string.
const STRING_KEYS: Array[String] = [KEY_ID, KEY_NAME, KEY_TAG, KEY_MOMENT, KEY_VERB, KEY_TEXT]

# Error prefixes, stable so tests and callers can match on them.
const ERR_FILE: String = "crew file"
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"
const ERR_DUPLICATE: String = "duplicate crew id"
const ERR_TAG: String = "unknown tag"
const ERR_MOMENT: String = CardAbility.ERR_MOMENT
const ERR_VERB: String = CardAbility.ERR_VERB
const ERR_PAIR: String = CardAbility.ERR_PAIR
const ERR_AMOUNT: String = CardAbility.ERR_AMOUNT
const ERR_OPTIONAL: String = "bad optional"
const ERR_SCOPE: String = CardAbility.ERR_SCOPE
const ERR_USES: String = CardAbility.ERR_USES

var _crew: Array[CrewDef] = []
var _index_by_id: Dictionary[String, int] = {}
var _error: String = ""


## Loads the shipped Crew pool, res://engine/data/crew.json (DEFAULT_PATH).
static func load_default() -> CrewPool:
	return load_from_path(DEFAULT_PATH)


## Loads a Crew pool from any path. Missing or unreadable files fail silently.
static func load_from_path(path: String) -> CrewPool:
	if not FileAccess.file_exists(path):
		return _failed("%s not found: %s" % [ERR_FILE, path])
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failed("%s unreadable: %s" % [ERR_FILE, path])
	var text: String = file.get_as_text()
	file.close()
	return from_json(text)


## Loads a Crew pool from JSON text (used by tests with in-memory data).
static func from_json(text: String) -> CrewPool:
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
	if not root.has("version") or not CardAbility.is_whole_number(root["version"]):
		return _failed("%s: missing or non-integer version" % ERR_SHAPE)
	var version: int = CardAbility.as_int(root["version"])
	if version != FORMAT_VERSION:
		return _failed("%s: %d (expected %d)" % [ERR_VERSION, version, FORMAT_VERSION])
	if not root.has("crew") or not root["crew"] is Array:
		return _failed("%s: missing crew array" % ERR_SHAPE)
	var entries: Array = root["crew"]
	var out: CrewPool = CrewPool.new()
	for i: int in range(entries.size()):
		var problem: String = _entry_problem(entries[i], i)
		if problem != "":
			return _failed(problem)
		var def: CrewDef = _build_entry(entries[i])
		if out._index_by_id.has(def.id):
			return _failed("%s: %s" % [ERR_DUPLICATE, def.id])
		out._index_by_id[def.id] = out._crew.size()
		out._crew.append(def)
	return out


func is_valid() -> bool:
	return _error == ""


## Empty when the load succeeded.
func load_error() -> String:
	return _error


## "" when the pool loaded and every Crew passed the checks; otherwise the first problem
## found, as load_error() reports it.
func validate() -> String:
	return _error


## Number of Crew (0 when the load failed).
func size() -> int:
	return _crew.size()


## Every Crew id, in file order.
func ids() -> Array[String]:
	var out: Array[String] = []
	for def: CrewDef in _crew:
		out.append(def.id)
	return out


## Whether the pool holds a Crew with this id.
func has_id(crew_id: String) -> bool:
	return _index_by_id.has(crew_id)


## The Crew with this id, or null when absent.
func crew_of(crew_id: String) -> CrewDef:
	if not _index_by_id.has(crew_id):
		return null
	return _crew[_index_by_id[crew_id]]


## A copy of every definition in file order.
func all() -> Array[CrewDef]:
	var out: Array[CrewDef] = []
	out.assign(_crew)
	return out


static func _failed(message: String) -> CrewPool:
	var out: CrewPool = CrewPool.new()
	out._error = message
	return out


## An error message for one Crew entry, or "" when it is well formed (see the class
## comment). Duplicate ids are from_json()'s.
static func _entry_problem(entry: Variant, i: int) -> String:
	if not _has_fields(entry):
		return (
			"%s: crew %d needs non-empty string id, name, tag, moment, verb and text"
			% [ERR_SHAPE, i]
		)
	var d: Dictionary = entry
	var tag: String = d[KEY_TAG]
	if not CardDef.TAGS.has(tag):
		return '%s: crew %d has tag "%s"' % [ERR_TAG, i, tag]
	var name_problem: String = _name_problem(d, i)
	if name_problem != "":
		return name_problem
	var amount_problem: String = _amount_problem(d, i)
	if amount_problem != "":
		return amount_problem
	return _limit_problem(d, i)


## An error message for one entry's moment and verb, or "": both known, the verb on its
## own moment (CrewDef.VERBS).
static func _name_problem(d: Dictionary, i: int) -> String:
	var moment: String = d[KEY_MOMENT]
	if not CardAbility.is_moment(moment):
		return '%s: crew %d has moment "%s"' % [ERR_MOMENT, i, moment]
	var verb: String = d[KEY_VERB]
	if not CrewDef.is_verb(verb):
		return '%s: crew %d has verb "%s"' % [ERR_VERB, i, verb]
	if not CrewDef.is_allowed_pair(moment, verb):
		return '%s: crew %d has verb "%s" on "%s"' % [ERR_PAIR, i, verb, moment]
	return ""


## An error message for one entry's `amount` and `amount_2`, or "": each absent or whole and
## within the verb's range.
static func _amount_problem(d: Dictionary, i: int) -> String:
	var verb: String = d[KEY_VERB]
	for key: String in [KEY_AMOUNT, KEY_AMOUNT_2]:
		var raw: Variant = d.get(key, 0)
		if not CardAbility.is_whole_number(raw):
			return "%s: crew %d has %s %s" % [ERR_AMOUNT, i, key, JSON.stringify(raw)]
		var value: int = CardAbility.as_int(raw)
		var bounds: Array[int] = CrewDef.range_of(verb, key)
		if value < bounds[0] or value > bounds[1]:
			return (
				'%s: crew %d "%s" %s %d (allowed %d..%d)'
				% [ERR_AMOUNT, i, verb, key, value, bounds[0], bounds[1]]
			)
	return ""


## An error message for one entry's optional, uses and scope, or "": a bool optional, whole
## uses >= 0 and a scope in CardAbility.SCOPES or "", each when present.
static func _limit_problem(d: Dictionary, i: int) -> String:
	if d.has(KEY_OPTIONAL) and not d[KEY_OPTIONAL] is bool:
		return "%s: crew %d has optional %s" % [ERR_OPTIONAL, i, JSON.stringify(d[KEY_OPTIONAL])]
	var raw_uses: Variant = d.get(KEY_USES, 0)
	if not CardAbility.is_whole_number(raw_uses) or CardAbility.as_int(raw_uses) < 0:
		return "%s: crew %d has uses %s" % [ERR_USES, i, JSON.stringify(raw_uses)]
	var raw_scope: Variant = d.get(KEY_SCOPE, "")
	if not raw_scope is String:
		return "%s: crew %d has scope %s" % [ERR_SCOPE, i, JSON.stringify(raw_scope)]
	var scope: String = raw_scope
	if scope != "" and not CardAbility.SCOPES.has(scope):
		return '%s: crew %d has scope "%s"' % [ERR_SCOPE, i, scope]
	return ""


## Whether `entry` is a Dictionary whose STRING_KEYS each hold a non-empty string.
static func _has_fields(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	var d: Dictionary = entry
	for key: String in STRING_KEYS:
		var raw: Variant = d.get(key)
		if not raw is String:
			return false
		var value: String = raw
		if value == "":
			return false
	return true


## Builds a CrewDef from an entry already accepted by _entry_problem().
static func _build_entry(entry: Variant) -> CrewDef:
	var d: Dictionary = entry
	var crew_id: String = d[KEY_ID]
	var crew_name: String = d[KEY_NAME]
	var moment: String = d[KEY_MOMENT]
	var verb: String = d[KEY_VERB]
	var text: String = d[KEY_TEXT]
	var out: CrewDef = CrewDef.new(crew_id, crew_name, moment, verb, text)
	var tag: String = d[KEY_TAG]
	out.tag = tag
	out.amount = CardAbility.as_int(d.get(KEY_AMOUNT, 0))
	out.amount_2 = CardAbility.as_int(d.get(KEY_AMOUNT_2, 0))
	var optional: bool = d.get(KEY_OPTIONAL, false)
	out.optional = optional
	out.uses = CardAbility.as_int(d.get(KEY_USES, 0))
	var scope: String = d.get(KEY_SCOPE, "")
	out.scope = scope
	return out
