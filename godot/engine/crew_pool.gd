class_name CrewPool
extends RefCounted
## Loads and validates the Crew pool (cycle 8 R39-R41, plan P12):
## {"version": 1, "crew": [{"id", "name", "trigger", "verb", "amount", "optional", "uses",
## "scope", "text"}, ...]} (CrewDef).
##
## The checks: unique non-empty string ids, a non-empty string name, a string text, a known
## trigger, verb and scope, the verb on its own trigger (CrewDef.VERB_TRIGGER), a whole
## amount >= 0, a bool `optional`, a whole `uses` >= 0 that is 0 for scope "none" and > 0
## for "round" or "match". The pool has no Crew count: each deck names three of it
## (DeckList.validate).
##
## Like CardDb, loading never prints, asserts or pushes an error: every failure is reported
## through load_error() (and validate()), and a failed pool holds no Crew, so a deck list
## checked against it fails and the engine refuses to start (R41).

const DEFAULT_PATH: String = "res://engine/data/crew.json"
const FORMAT_VERSION: int = 1

const KEY_ID: String = "id"
const KEY_NAME: String = "name"
const KEY_TRIGGER: String = "trigger"
const KEY_VERB: String = "verb"
const KEY_AMOUNT: String = "amount"
const KEY_OPTIONAL: String = "optional"
const KEY_USES: String = "uses"
const KEY_SCOPE: String = "scope"
const KEY_TEXT: String = "text"
## Every key a Crew entry must hold, and those whose value must be a string.
const ALL_KEYS: Array[String] = [
	KEY_ID, KEY_NAME, KEY_TRIGGER, KEY_VERB, KEY_AMOUNT, KEY_OPTIONAL, KEY_USES, KEY_SCOPE, KEY_TEXT
]
const STRING_KEYS: Array[String] = [KEY_ID, KEY_NAME, KEY_TRIGGER, KEY_VERB, KEY_SCOPE, KEY_TEXT]

# Error prefixes, stable so tests and callers can match on them.
const ERR_FILE: String = "crew file"
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"
const ERR_DUPLICATE: String = "duplicate crew id"
const ERR_TRIGGER: String = "unknown trigger"
const ERR_VERB: String = "unknown verb"
const ERR_PAIR: String = "verb not allowed on trigger"
const ERR_OPTIONAL: String = "bad optional"
const ERR_SCOPE: String = "bad scope"
const ERR_USES: String = "bad uses"

## Whether this pool's Crew fire in a match (DC-11 T10; cycle 8 R45-R51): true for every
## loaded pool. A test seam, as StubCrew is for TurnStart.fire: the suites written before
## the Crew (DC-05 to DC-09) build their matches on a pool with it cleared
## (FixtureDecks.crew()), so their pinned walks, hands and events hold while MATCH_STARTED,
## the views and MatchState.crew_uses still name the Crew. MatchCards.build() reads it, so
## a replay over the same pool fires the same Crew (none).
var fires: bool = true

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
	if not root.has("version") or not _is_whole_number(root["version"]):
		return _failed("%s: missing or non-integer version" % ERR_SHAPE)
	var version: int = _as_int(root["version"])
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


## "" when the pool loaded and every Crew passed the checks (R39, R41); otherwise the first
## problem found, as load_error() reports it.
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
			"%s: crew %d needs a non-empty string id and name, string trigger, verb, scope %s"
			% [ERR_SHAPE, i, "and text, a whole amount >= 0, a bool optional and whole uses"]
		)
	var d: Dictionary = entry
	if not d[KEY_OPTIONAL] is bool:
		return "%s: crew %d has optional %s" % [ERR_OPTIONAL, i, JSON.stringify(d[KEY_OPTIONAL])]
	var name_problem: String = _name_problem(d, i)
	if name_problem != "":
		return name_problem
	return _limit_problem(d, i)


## An error message for one entry's trigger and verb, or "": both known, the verb on its
## own trigger (CrewDef.VERB_TRIGGER).
static func _name_problem(d: Dictionary, i: int) -> String:
	var trigger_text: String = d[KEY_TRIGGER]
	var trigger_value: int = CrewDef.trigger_from_name(trigger_text)
	if trigger_value < 0:
		return '%s: crew %d has trigger "%s"' % [ERR_TRIGGER, i, trigger_text]
	var verb_text: String = d[KEY_VERB]
	var verb_value: int = CrewDef.verb_from_name(verb_text)
	if verb_value < 0:
		return '%s: crew %d has verb "%s"' % [ERR_VERB, i, verb_text]
	if not CrewDef.is_allowed_pair(trigger_value, verb_value):
		return '%s: crew %d has verb "%s" on "%s"' % [ERR_PAIR, i, verb_text, trigger_text]
	return ""


## An error message for one entry's scope and uses, or "": a known scope, whole uses >= 0,
## 0 for "none" and > 0 otherwise.
static func _limit_problem(d: Dictionary, i: int) -> String:
	var scope_text: String = d[KEY_SCOPE]
	var scope_value: int = CrewDef.scope_from_name(scope_text)
	if scope_value < 0:
		return (
			'%s: crew %d has scope "%s" (allowed %s)'
			% [ERR_SCOPE, i, scope_text, str(CrewDef.SCOPE_NAMES)]
		)
	var raw_uses: Variant = d[KEY_USES]
	if not _is_whole_number(raw_uses):
		return "%s: crew %d has uses %s" % [ERR_USES, i, JSON.stringify(raw_uses)]
	var uses: int = _as_int(raw_uses)
	var limited: bool = scope_value != CrewDef.Scope.NONE
	if uses < 0 or (limited and uses == 0) or (not limited and uses != 0):
		return (
			'%s: crew %d has uses %d with scope "%s" (0 for none, > 0 otherwise)'
			% [ERR_USES, i, uses, scope_text]
		)
	return ""


## Whether `entry` is a Dictionary with every Crew key, string id, name, trigger, verb,
## scope and text, a non-empty id and name and a whole amount >= 0. `optional` and `uses`
## need only be present here: they are checked on their own, for their own error codes.
static func _has_fields(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	var d: Dictionary = entry
	for key: String in ALL_KEYS:
		if not d.has(key):
			return false
	for key: String in STRING_KEYS:
		if not d[key] is String:
			return false
	var crew_id: String = d[KEY_ID]
	var crew_name: String = d[KEY_NAME]
	var amount_ok: bool = _is_whole_number(d[KEY_AMOUNT]) and _as_int(d[KEY_AMOUNT]) >= 0
	return crew_id != "" and crew_name != "" and amount_ok


## Builds a CrewDef from an entry already accepted by _entry_problem().
static func _build_entry(entry: Variant) -> CrewDef:
	var d: Dictionary = entry
	var crew_id: String = d[KEY_ID]
	var crew_name: String = d[KEY_NAME]
	var trigger_text: String = d[KEY_TRIGGER]
	var verb_text: String = d[KEY_VERB]
	var scope_text: String = d[KEY_SCOPE]
	var text: String = d[KEY_TEXT]
	var optional: bool = d[KEY_OPTIONAL]
	var trigger_value: int = CrewDef.trigger_from_name(trigger_text)
	var verb_value: int = CrewDef.verb_from_name(verb_text)
	var scope_value: int = CrewDef.scope_from_name(scope_text)
	return CrewDef.new(
		crew_id,
		crew_name,
		trigger_value as CrewDef.Trigger,
		verb_value as CrewDef.Verb,
		_as_int(d[KEY_AMOUNT]),
		optional,
		_as_int(d[KEY_USES]),
		scope_value as CrewDef.Scope,
		text
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
