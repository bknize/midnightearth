class_name EngineAction
extends RefCounted
## One seat's action (R5): a commit naming zero or more of its hand's cards in the order
## given, or a concede. The dictionary form is the action log's entry (plan, R31):
## {"k": "commit", "s": 0, "c": [3, 7]} or {"k": "concede", "s": 1}.

enum Kind { COMMIT, CONCEDE }

const KEY_KIND: String = "k"
const KEY_SEAT: String = "s"
const KEY_CARDS: String = "c"
const KIND_COMMIT: String = "commit"
const KIND_CONCEDE: String = "concede"

var kind: int = Kind.COMMIT
var seat: int = 0
## Card instance ids in commit order; always empty for a concede.
var cards: Array[int] = []


static func commit(p_seat: int, p_cards: Array[int]) -> EngineAction:
	var action: EngineAction = EngineAction.new()
	action.kind = Kind.COMMIT
	action.seat = p_seat
	action.cards.assign(p_cards)
	return action


static func concede(p_seat: int) -> EngineAction:
	var action: EngineAction = EngineAction.new()
	action.kind = Kind.CONCEDE
	action.seat = p_seat
	return action


## An independent copy, so a caller mutating its action cannot alter the engine's record.
func copy() -> EngineAction:
	var action: EngineAction = EngineAction.new()
	action.kind = kind
	action.seat = seat
	action.cards.assign(cards)
	return action


func to_dict() -> Dictionary:
	if kind == Kind.CONCEDE:
		return {KEY_KIND: KIND_CONCEDE, KEY_SEAT: seat}
	return {KEY_KIND: KIND_COMMIT, KEY_SEAT: seat, KEY_CARDS: MatchState.plain(cards)}


## Parses the dictionary form, accepting JSON floats with no fractional part as ints.
## Returns null when malformed: missing or mistyped keys, an unknown kind, a seat other
## than 0 or 1, a commit without a card list, or a concede that carries one.
static func from_dict(d: Dictionary) -> EngineAction:
	if not (d.has(KEY_KIND) and d.has(KEY_SEAT)):
		return null
	var kind_raw: Variant = d[KEY_KIND]
	if not kind_raw is String:
		return null
	var kind_name: String = kind_raw
	var seat_raw: Variant = d[KEY_SEAT]
	if not _is_whole_number(seat_raw):
		return null
	var parsed_seat: int = _as_int(seat_raw)
	if parsed_seat < 0 or parsed_seat > 1:
		return null
	if kind_name == KIND_CONCEDE:
		if d.has(KEY_CARDS):
			return null
		return concede(parsed_seat)
	if kind_name != KIND_COMMIT or not d.has(KEY_CARDS):
		return null
	var cards_raw: Variant = d[KEY_CARDS]
	if not cards_raw is Array:
		return null
	var entries: Array = cards_raw
	var ids: Array[int] = []
	for entry: Variant in entries:
		if not _is_whole_number(entry):
			return null
		ids.append(_as_int(entry))
	return commit(parsed_seat, ids)


## Converts a value already checked by _is_whole_number to int without an unsafe call.
static func _as_int(value: Variant) -> int:
	if value is int:
		var whole: int = value
		return whole
	var number: float = value
	return int(number)


static func _is_whole_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var f: float = value
		return is_finite(f) and f == floorf(f)
	return false
