class_name NetCodec
extends RefCounted
## Encodes and decodes NetProtocol messages to and from JSON text (cycle 12 plan P2, P10).
## Pure and static: no clock, no node, no state.
##
## decode() checks every field of the message's kind and returns {} for anything malformed
## (text that is not JSON or not an object, an unknown kind, a missing or wrong-typed
## field, an `action`, `view` or event the engine's parsers refuse) or too large (a client
## kind past NetProtocol.MAX_MESSAGE_BYTES, any kind past MAX_SERVER_MESSAGE_BYTES). It
## never errors. A decoded message holds only its kind's keys, with every whole JSON float
## turned back into an int (MatchEvent.whole_numbers), so decode(encode(m)) reads as m.
## encode() applies the same checks to the message it is given and returns "" when it
## would not decode.

enum Field { TEXT, COUNT, SEAT, PLAYER, STATE, ERROR, ACTION, VIEW, EVENTS, DECKS, OPPONENT }

## The name rule (spec R3, Identity.normalize_name), applied again by the server.
const MAX_NAME_LENGTH: int = 16
const DEFAULT_NAME: String = "Player"
## How much of a raw name or code is looked at before trimming (a message may be 16 KiB).
const MAX_NAME_SCAN: int = 256
const MAX_CODE_SCAN: int = 16
## An install id: Identity's UUID text, or any short id of these characters.
const MAX_INSTALL_ID_LENGTH: int = 64
const INSTALL_ID_CHARS: String = (
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
)
## The most characters of client text a stdout line carries.
const MAX_PRINTED: int = 64


## The message as JSON text; "" when it is malformed or past its size bound.
static func encode(message: Dictionary) -> String:
	var checked: Dictionary = _checked(message)
	if checked.is_empty():
		return ""
	var text: String = JSON.stringify(checked)
	if not _fits(text.to_utf8_buffer().size(), checked):
		return ""
	return text


## The message `text` holds, its fields checked and normalised; {} when malformed or too
## large.
static func decode(text: String) -> Dictionary:
	if text.length() > NetProtocol.MAX_SERVER_MESSAGE_BYTES:
		return {}
	var size: int = text.to_utf8_buffer().size()
	if size > NetProtocol.MAX_SERVER_MESSAGE_BYTES:
		return {}
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if not data is Dictionary:
		return {}
	var parsed: Dictionary = data
	var checked: Dictionary = _checked(parsed)
	if checked.is_empty() or not _fits(size, checked):
		return {}
	return checked


## The EngineAction in an `act` or `rejected` message; null when absent or malformed.
static func action_of(message: Dictionary) -> EngineAction:
	var raw: Variant = message.get(NetProtocol.KEY_ACTION)
	if not raw is Dictionary:
		return null
	var d: Dictionary = raw
	return EngineAction.from_dict(d)


## The SeatView in a `started`, `events` or `resync` message; null when absent or malformed.
static func view_of(message: Dictionary) -> SeatView:
	var raw: Variant = message.get(NetProtocol.KEY_VIEW)
	if not raw is Dictionary:
		return null
	var d: Dictionary = raw
	return SeatView.from_dict(d)


## The events of a `started`, `events` or `resync` message, in order; empty when absent or
## when any entry is malformed.
static func events_of(message: Dictionary) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var raw: Variant = message.get(NetProtocol.KEY_EVENTS)
	if not raw is Array:
		return out
	var entries: Array = raw
	for entry: Variant in entries:
		var event: MatchEvent = _event_of(entry)
		if event == null:
			out.clear()
			return out
		out.append(event)
	return out


## The EngineError code a `rejected` message names; -1 when absent or unknown.
static func error_of(message: Dictionary) -> int:
	var raw: Variant = message.get(NetProtocol.KEY_ERROR)
	if not raw is String:
		return -1
	var error_name: String = raw
	return _error_code(error_name)


# --- Untrusted text (NSC-226 S4) --------------------------------------------------------


## A player name as the server keeps and prints it: control characters dropped, then the
## title screen's rule (R3): surrounding whitespace dropped, at most MAX_NAME_LENGTH
## characters, empty reads DEFAULT_NAME.
static func clean_name(raw: String) -> String:
	var kept: String = ""
	var scan: String = raw.substr(0, MAX_NAME_SCAN)
	for at: int in range(scan.length()):
		var code: int = scan.unicode_at(at)
		if code >= 32 and code != 127 and (code < 128 or code > 159):
			kept += scan[at]
	var trimmed: String = kept.strip_edges()
	if trimmed.length() > MAX_NAME_LENGTH:
		trimmed = trimmed.substr(0, MAX_NAME_LENGTH).strip_edges()
	return DEFAULT_NAME if trimmed == "" else trimmed


## True for 1 to MAX_INSTALL_ID_LENGTH characters of INSTALL_ID_CHARS (Identity's UUIDs,
## a test's "install-ana").
static func is_install_id(raw: String) -> bool:
	if raw.is_empty() or raw.length() > MAX_INSTALL_ID_LENGTH:
		return false
	for at: int in range(raw.length()):
		if not INSTALL_ID_CHARS.contains(raw[at]):
			return false
	return true


## A typed room code as the server keys it (RoomCodes.normalized), or "" when it is not
## RoomCodes.LENGTH characters of RoomCodes.ALPHABET, so a bad code is never echoed.
static func room_code(raw: String) -> String:
	if raw.length() > MAX_CODE_SCAN:
		return ""
	var code: String = RoomCodes.normalized(raw)
	return code if RoomCodes.is_valid(code) else ""


## `raw` safe for one stdout line: control characters replaced by `?`, at most `limit`
## characters, a cut marked with `...`.
static func printable(raw: String, limit: int = MAX_PRINTED) -> String:
	var out: String = ""
	var scan: String = raw.substr(0, limit)
	for at: int in range(scan.length()):
		var code: int = scan.unicode_at(at)
		out += "?" if code < 32 or code == 127 else scan[at]
	return out + "..." if raw.length() > limit else out


# --- Checks -----------------------------------------------------------------------------


## The fields each kind carries beyond `t`, each with its Field check.
static func _fields_of(kind: String) -> Dictionary[String, int]:
	var fields: Dictionary[String, int] = {}
	if kind == NetProtocol.T_HELLO:
		fields[NetProtocol.KEY_PROTOCOL] = Field.COUNT
		fields[NetProtocol.KEY_STAMP] = Field.TEXT
		fields[NetProtocol.KEY_NAME] = Field.TEXT
		fields[NetProtocol.KEY_INSTALL_ID] = Field.TEXT
		fields[NetProtocol.KEY_KIND] = Field.PLAYER
	elif kind == NetProtocol.T_HOST:
		fields[NetProtocol.KEY_DECK] = Field.TEXT
	elif kind == NetProtocol.T_JOIN:
		fields[NetProtocol.KEY_CODE] = Field.TEXT
		fields[NetProtocol.KEY_DECK] = Field.TEXT
	elif kind == NetProtocol.T_REJOIN:
		fields[NetProtocol.KEY_CODE] = Field.TEXT
	elif kind == NetProtocol.T_ACT:
		fields[NetProtocol.KEY_ACTION] = Field.ACTION
	elif kind == NetProtocol.T_WELCOME:
		fields[NetProtocol.KEY_PROTOCOL] = Field.COUNT
		fields[NetProtocol.KEY_STAMP] = Field.TEXT
	elif kind == NetProtocol.T_REFUSED:
		fields[NetProtocol.KEY_REASON] = Field.TEXT
		fields[NetProtocol.KEY_DETAIL] = Field.TEXT
	elif kind == NetProtocol.T_HOSTED:
		fields[NetProtocol.KEY_CODE] = Field.TEXT
		fields[NetProtocol.KEY_EXPIRES_IN_S] = Field.COUNT
	elif kind == NetProtocol.T_STARTED:
		fields[NetProtocol.KEY_SEAT] = Field.SEAT
		fields[NetProtocol.KEY_OPPONENT] = Field.OPPONENT
		fields[NetProtocol.KEY_DECKS] = Field.DECKS
		fields[NetProtocol.KEY_VIEW] = Field.VIEW
		fields[NetProtocol.KEY_EVENTS] = Field.EVENTS
	elif kind == NetProtocol.T_EVENTS or kind == NetProtocol.T_RESYNC:
		fields[NetProtocol.KEY_EVENTS] = Field.EVENTS
		fields[NetProtocol.KEY_VIEW] = Field.VIEW
	elif kind == NetProtocol.T_REJECTED:
		fields[NetProtocol.KEY_ERROR] = Field.ERROR
		fields[NetProtocol.KEY_ACTION] = Field.ACTION
	elif kind == NetProtocol.T_OPPONENT:
		fields[NetProtocol.KEY_STATE] = Field.STATE
		fields[NetProtocol.KEY_SECONDS_LEFT] = Field.COUNT
		fields[NetProtocol.KEY_NAME] = Field.TEXT
	elif kind == NetProtocol.T_ABANDONED:
		fields[NetProtocol.KEY_SEAT] = Field.SEAT
		fields[NetProtocol.KEY_NAME] = Field.TEXT
	elif kind == NetProtocol.T_CLOSED:
		fields[NetProtocol.KEY_REASON] = Field.TEXT
	return fields


## A new message holding `message`'s kind and that kind's fields, checked and normalised;
## {} when anything is missing, of the wrong type or of an unknown kind. Extra keys are
## dropped.
static func _checked(message: Dictionary) -> Dictionary:
	var kind_raw: Variant = message.get(NetProtocol.KEY_T)
	if not kind_raw is String:
		return {}
	var kind: String = kind_raw
	if not NetProtocol.is_kind(kind):
		return {}
	var out: Dictionary = {NetProtocol.KEY_T: kind}
	var fields: Dictionary[String, int] = _fields_of(kind)
	for key: String in fields:
		if not message.has(key):
			return {}
		var value: Variant = _field(fields[key], message[key])
		if typeof(value) == TYPE_NIL:
			return {}
		out[key] = value
	return out


## `raw` normalised (whole floats as ints) when it is a valid `type`; null otherwise.
static func _field(type: int, raw: Variant) -> Variant:
	var value: Variant = MatchEvent.whole_numbers(raw)
	match type:
		Field.TEXT:
			if value is String:
				return value
		Field.COUNT:
			if value is int:
				var count: int = value
				if count >= 0:
					return count
		Field.SEAT:
			if value is int:
				var seat: int = value
				if seat >= 0 and seat < MatchEngine.SEATS:
					return seat
		Field.PLAYER:
			if _one_of(value, [NetProtocol.PLAYER_HUMAN, NetProtocol.PLAYER_BOT]):
				return value
		Field.STATE:
			if _one_of(value, [NetProtocol.STATE_LOST, NetProtocol.STATE_BACK]):
				return value
		Field.ERROR:
			if value is String:
				var error_name: String = value
				if _error_code(error_name) > EngineError.Code.NONE:
					return value
		Field.ACTION:
			if value is Dictionary:
				var action: Dictionary = value
				if EngineAction.from_dict(action) != null:
					return value
		Field.VIEW:
			if value is Dictionary:
				var view: Dictionary = value
				if SeatView.from_dict(view) != null:
					return value
		Field.EVENTS:
			if value is Array and _all_events(value):
				return value
		Field.DECKS:
			if _is_decks(value):
				return value
		Field.OPPONENT:
			return _opponent(value)
	return null


## True when `value` is a String among `allowed`.
static func _one_of(value: Variant, allowed: Array[String]) -> bool:
	if not value is String:
		return false
	var text: String = value
	return allowed.has(text)


## The EngineError code named `error_name`; -1 when it names none.
static func _error_code(error_name: String) -> int:
	var names: Array = EngineError.Code.keys()
	return names.find(error_name)


static func _event_of(entry: Variant) -> MatchEvent:
	if not entry is Dictionary:
		return null
	var d: Dictionary = entry
	return MatchEvent.from_dict(d)


static func _all_events(value: Variant) -> bool:
	var entries: Array = value
	for entry: Variant in entries:
		if _event_of(entry) == null:
			return false
	return true


## True when `value` is one deck id per seat.
static func _is_decks(value: Variant) -> bool:
	if not value is Array:
		return false
	var ids: Array = value
	if ids.size() != MatchEngine.SEATS:
		return false
	for id: Variant in ids:
		if not id is String:
			return false
	return true


## `{name, deck}` rebuilt from `value`; null when either is missing or not text.
static func _opponent(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var d: Dictionary = value
	var name_raw: Variant = d.get(NetProtocol.KEY_NAME)
	var deck_raw: Variant = d.get(NetProtocol.KEY_DECK)
	if not (name_raw is String and deck_raw is String):
		return null
	return {NetProtocol.KEY_NAME: name_raw, NetProtocol.KEY_DECK: deck_raw}


## True when a message of `checked`'s kind may be `size` bytes long.
static func _fits(size: int, checked: Dictionary) -> bool:
	var kind: String = checked[NetProtocol.KEY_T]
	if NetProtocol.is_client_kind(kind):
		return size <= NetProtocol.MAX_MESSAGE_BYTES
	return size <= NetProtocol.MAX_SERVER_MESSAGE_BYTES
