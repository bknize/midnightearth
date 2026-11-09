class_name JsonLoad
extends RefCounted
## The steps every pool loader (CardDb, CrewPool, DeckList) starts with: read the file, parse
## the JSON, check the top level is an object with the format version. Each step returns one
## of these holding its result or the `error` message; like the loaders it never prints,
## asserts or pushes an error, so the caller reports the message through its load_error().

# Error prefixes, stable so tests and callers can match on them (the loaders re-export them).
const ERR_JSON: String = "bad JSON"
const ERR_SHAPE: String = "bad shape"
const ERR_VERSION: String = "unsupported version"

const KEY_VERSION: String = "version"

## The file's text (read()).
var text: String = ""
## The top-level object (parse()).
var root: Dictionary = {}
## The first problem, "" when the step succeeded.
var error: String = ""


## The text of the file at `path`; `err_file` names the file in the error message.
static func read(path: String, err_file: String) -> JsonLoad:
	var out: JsonLoad = JsonLoad.new()
	if not FileAccess.file_exists(path):
		out.error = "%s not found: %s" % [err_file, path]
		return out
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		out.error = "%s unreadable: %s" % [err_file, path]
		return out
	out.text = file.get_as_text()
	file.close()
	return out


## The top-level object of `json_text`, which must hold a whole `version` equal to `format`.
static func parse(json_text: String, format: int) -> JsonLoad:
	var out: JsonLoad = JsonLoad.new()
	# JSON.new().parse() reports through its return code and get_error_message();
	# unlike JSON.parse_string() it does not log an error on malformed input.
	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(json_text)
	if parse_err != OK:
		out.error = (
			"%s at line %d: %s" % [ERR_JSON, json.get_error_line(), json.get_error_message()]
		)
		return out
	var data: Variant = json.data
	if not data is Dictionary:
		out.error = "%s: top level is not an object" % ERR_SHAPE
		return out
	out.root = data
	var raw: Variant = out.root.get(KEY_VERSION)
	if not EngineAction.is_whole_number(raw):
		out.error = "%s: missing or non-integer version" % ERR_SHAPE
		return out
	var version: int = EngineAction.as_int(raw)
	if version != format:
		out.error = "%s: %d (expected %d)" % [ERR_VERSION, version, format]
	return out
