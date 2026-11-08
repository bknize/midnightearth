class_name Identity
extends RefCounted
## The device's identity (cycle 12 spec R2 to R5, plan P16): a display name, a random install
## id created once and never edited, and the server address last used. Persisted as
## `{name, install_id, server}` JSON at `user://identity.json`. Client-side only, so it may
## draw its install id from a clock-seeded RandomNumberGenerator.

const DEFAULT_PATH: String = "user://identity.json"
const DEFAULT_NAME: String = "Player"
const MAX_NAME_LENGTH: int = 16
## The compiled-in server address (plan P16); `--server=` overrides it for a run.
const DEFAULT_SERVER: String = NetDefaults.SERVER_ADDRESS
const KEY_NAME: String = "name"
const KEY_INSTALL_ID: String = "install_id"
const KEY_SERVER: String = "server"

var name: String = DEFAULT_NAME
var install_id: String = ""
var server: String = DEFAULT_SERVER
var _path: String = DEFAULT_PATH


## Loads the identity at `path`, or creates it (fresh install id, defaults) and saves it
## when the file is missing, unreadable or holds no usable install id.
static func load_or_create(path: String = DEFAULT_PATH) -> Identity:
	var identity: Identity = Identity.new()
	identity._path = path
	var loaded: bool = identity._read()
	if not loaded:
		identity.install_id = new_install_id()
		identity.save()
	return identity


## Trims a typed name: surrounding whitespace dropped, at most 16 characters, and an empty
## result reads "Player" (R3).
static func normalize_name(raw: String) -> String:
	var trimmed: String = raw.strip_edges()
	if trimmed.length() > MAX_NAME_LENGTH:
		trimmed = trimmed.substr(0, MAX_NAME_LENGTH).strip_edges()
	if trimmed == "":
		return DEFAULT_NAME
	return trimmed


## A random version-4 UUID as text.
static func new_install_id() -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var bytes: PackedByteArray = PackedByteArray()
	for _i: int in range(16):
		var value: int = rng.randi_range(0, 255)
		var failed: bool = bytes.append(value)  # true on failure
		if failed:
			push_warning("Identity: could not build an install id")
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return (
		"%s-%s-%s-%s-%s"
		% [
			hex.substr(0, 8),
			hex.substr(8, 4),
			hex.substr(12, 4),
			hex.substr(16, 4),
			hex.substr(20, 12)
		]
	)


## Sets the name through the trim rule and returns the stored value.
func set_name(raw: String) -> String:
	name = normalize_name(raw)
	return name


## Sets the server address (surrounding whitespace dropped; empty falls back to the default).
func set_server(raw: String) -> String:
	var trimmed: String = raw.strip_edges()
	server = trimmed if trimmed != "" else DEFAULT_SERVER
	return server


## Writes the identity to its file. Failure is a warning: the game plays on without it.
func save() -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("Identity: cannot write %s (error %d)" % [_path, FileAccess.get_open_error()])
		return
	var data: Dictionary = {KEY_NAME: name, KEY_INSTALL_ID: install_id, KEY_SERVER: server}
	var stored: bool = file.store_string(JSON.stringify(data))
	file.close()
	if not stored:
		push_warning("Identity: writing %s failed" % _path)


## Reads the file into this identity. False when it is missing, malformed or has no install id.
func _read() -> bool:
	if not FileAccess.file_exists(_path):
		return false
	var text: String = FileAccess.get_file_as_string(_path)
	# JSON.new().parse() reports a malformed file without logging an error (parse_string would).
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		return false
	var data: Dictionary = parsed
	var saved_id: Variant = data.get(KEY_INSTALL_ID, "")
	if not saved_id is String:
		return false
	var id_text: String = saved_id
	if id_text == "":
		return false
	install_id = id_text
	name = DEFAULT_NAME
	var saved_name: Variant = data.get(KEY_NAME, DEFAULT_NAME)
	if saved_name is String:
		var name_text: String = saved_name
		name = normalize_name(name_text)
	server = DEFAULT_SERVER
	var saved_server: Variant = data.get(KEY_SERVER, DEFAULT_SERVER)
	if saved_server is String:
		var server_text: String = saved_server
		var applied: String = set_server(server_text)
		if applied == "":
			return false
	return true
