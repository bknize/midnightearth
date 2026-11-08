class_name VerbTable
extends RefCounted
## The reads and checks shared by the two verb tables, CardAbility.VERBS and CrewDef.VERBS:
## verb name to an entry with the moments it may sit on (`moments` for a card verb, the one
## `moment` for a Crew verb) and, for each amount it takes, an inclusive [low, high] range.

const KEY_MOMENTS: String = "moments"
const KEY_MOMENT: String = "moment"


## Whether the known `verb_name` may sit on `moment_name` in `table`.
static func is_allowed_pair(
	table: Dictionary[String, Dictionary], moment_name: String, verb_name: String
) -> bool:
	if not table.has(verb_name):
		return false
	var entry: Dictionary = table[verb_name]
	var moments: Array = entry.get(KEY_MOMENTS, [entry.get(KEY_MOMENT)])
	return moments.has(moment_name)


## The inclusive [low, high] range of `key` for `verb_name` in `table`, or [0, 0] when the
## verb takes no such amount (or is unknown).
static func range_of(
	table: Dictionary[String, Dictionary], verb_name: String, key: String
) -> Array[int]:
	var out: Array[int] = [0, 0]
	if not table.has(verb_name):
		return out
	var entry: Dictionary = table[verb_name]
	if entry.has(key):
		var listed: Array = entry[key]
		out.assign(listed)
	return out


## The first problem of the amounts `keys` of `d` (whose verb `verb_name` is known), or "":
## each absent or whole and within the verb's range. A value that is not whole fills
## `whole_format` with its key and its JSON; one out of range starts with `range_prefix`.
static func amount_problem(
	d: Dictionary,
	table: Dictionary[String, Dictionary],
	verb_name: String,
	keys: Array[String],
	whole_format: String,
	range_prefix: String
) -> String:
	for key: String in keys:
		var raw: Variant = d.get(key, 0)
		if not EngineAction.is_whole_number(raw):
			return whole_format % [key, JSON.stringify(raw)]
		var value: int = EngineAction.as_int(raw)
		var bounds: Array[int] = range_of(table, verb_name, key)
		if value < bounds[0] or value > bounds[1]:
			return (
				'%s"%s" %s %d (allowed %d..%d)'
				% [range_prefix, verb_name, key, value, bounds[0], bounds[1]]
			)
	return ""


## Whether `raw` is a valid `uses`: a whole number >= 0.
static func is_uses(raw: Variant) -> bool:
	return EngineAction.is_whole_number(raw) and EngineAction.as_int(raw) >= 0
