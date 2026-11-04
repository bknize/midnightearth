class_name EngineAction
extends RefCounted
## One seat's action (R5, R31): a commit naming zero or more of its hand's cards with the
## row slot each will occupy, a choice answering an open prompt, a set choice answering an
## open multi-select prompt (DC-07 P7, R22-R25), or a concede. The dictionary form is the
## action log's entry (plan, action log format 3):
## {"k": "commit", "s": 0, "c": [3, 7], "p": [0, 2]}, {"k": "choose", "s": 1, "z": 1,
## "i": 0}, {"k": "choose_set", "s": 0, "z": 1, "i": [0, 2]} or {"k": "concede", "s": 1}.
## A set choice's `i` is a list of positions, possibly empty (the decline).
##
## Slots are final-row indices (plan P1): `slots[i]` is where `cards[i]` sits once every
## committed card is in place; strictly increasing; each within 0 .. row + cards - 1.
##
## Compatibility default: a commit whose `slots` is empty while `cards` is not means
## "append at the row's right end". The engine resolves it to row_size .. row_size + k - 1
## when it validates the commit and stores the resolved slots in its state and its log,
## so an accepted commit is always logged with explicit slots and replays the same.

enum Kind { COMMIT, CONCEDE, CHOOSE, CHOOSE_SET }

const KEY_KIND: String = "k"
const KEY_SEAT: String = "s"
const KEY_CARDS: String = "c"
const KEY_SLOTS: String = "p"
const KEY_ZONE: String = "z"
const KEY_INDEX: String = "i"
const KIND_COMMIT: String = "commit"
const KIND_CONCEDE: String = "concede"
const KIND_CHOOSE: String = "choose"
const KIND_CHOOSE_SET: String = "choose_set"
## 2^53. Larger whole floats cannot be told apart from their neighbours, and int() of a
## float beyond the int64 range is platform-defined, so they are rejected. ActionLog
## shares this bound for its header numbers.
const MAX_SAFE_FLOAT: float = 9007199254740992.0

var kind: int = Kind.COMMIT
var seat: int = 0
## Card instance ids in commit order; always empty for a concede or a (set) choice.
var cards: Array[int] = []
## Final-row slot of each card in `cards`; empty means the compatibility default (append).
## Always empty for a concede or a (set) choice.
var slots: Array[int] = []
## A choice's zone (relative to the choosing seat) and its position in that zone (R30). A
## set choice uses `zone` and `indices`; its `index` stays 0.
var zone: int = 0
var index: int = 0
## A set choice's positions in `zone`, in the order given (DC-07 P7); empty for the decline
## and for every other kind.
var indices: Array[int] = []


## A commit. `p_slots` may be left empty for the compatibility default (append at the
## row's right end); the engine resolves it when it validates the commit.
static func commit(p_seat: int, p_cards: Array[int], p_slots: Array[int] = []) -> EngineAction:
	var action: EngineAction = EngineAction.new()
	action.kind = Kind.COMMIT
	action.seat = p_seat
	action.cards.assign(p_cards)
	action.slots.assign(p_slots)
	return action


static func concede(p_seat: int) -> EngineAction:
	var action: EngineAction = EngineAction.new()
	action.kind = Kind.CONCEDE
	action.seat = p_seat
	return action


## A choice answering the open prompt: position `p_index` in zone `p_zone` (R30).
static func choose(p_seat: int, p_zone: int, p_index: int) -> EngineAction:
	var action: EngineAction = EngineAction.new()
	action.kind = Kind.CHOOSE
	action.seat = p_seat
	action.zone = p_zone
	action.index = p_index
	return action


## A set choice answering the open multi-select prompt: positions `p_indices` of zone
## `p_zone` (DC-07 P7, R22). An empty set declines.
static func choose_set(p_seat: int, p_zone: int, p_indices: Array[int]) -> EngineAction:
	var action: EngineAction = EngineAction.new()
	action.kind = Kind.CHOOSE_SET
	action.seat = p_seat
	action.zone = p_zone
	action.indices.assign(p_indices)
	return action


## An independent copy, so a caller mutating its action cannot alter the engine's record.
func copy() -> EngineAction:
	var action: EngineAction = EngineAction.new()
	action.kind = kind
	action.seat = seat
	action.cards.assign(cards)
	action.slots.assign(slots)
	action.zone = zone
	action.index = index
	action.indices.assign(indices)
	return action


func to_dict() -> Dictionary:
	if kind == Kind.CONCEDE:
		return {KEY_KIND: KIND_CONCEDE, KEY_SEAT: seat}
	if kind == Kind.CHOOSE:
		return {KEY_KIND: KIND_CHOOSE, KEY_SEAT: seat, KEY_ZONE: zone, KEY_INDEX: index}
	if kind == Kind.CHOOSE_SET:
		return {
			KEY_KIND: KIND_CHOOSE_SET,
			KEY_SEAT: seat,
			KEY_ZONE: zone,
			KEY_INDEX: MatchState.plain(indices),
		}
	return {
		KEY_KIND: KIND_COMMIT,
		KEY_SEAT: seat,
		KEY_CARDS: MatchState.plain(cards),
		KEY_SLOTS: MatchState.plain(slots),
	}


## Parses the dictionary form, accepting JSON floats with no fractional part as ints.
## Returns null when malformed: missing or mistyped keys, an unknown kind, a seat other
## than 0 or 1, a commit without a card list, a concede or choice that carries cards or
## slots, a choice without its zone and index, a set choice without its zone or with an
## `i` that is not a list of whole numbers, a concede with either, or a float number
## whose magnitude exceeds MAX_SAFE_FLOAT. A commit's `p` is optional (missing reads as
## the empty, append default) so that a format-1 log still parses and then fails replay
## on its version (R40). Slots are not checked against the cards here: the engine
## rejects a bad list with BAD_SLOTS.
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
	if kind_name == KIND_COMMIT:
		return _commit_from_dict(d, parsed_seat)
	if d.has(KEY_CARDS) or d.has(KEY_SLOTS):
		return null
	if kind_name == KIND_CHOOSE:
		return _choose_from_dict(d, parsed_seat)
	if kind_name == KIND_CHOOSE_SET:
		return _choose_set_from_dict(d, parsed_seat)
	if kind_name != KIND_CONCEDE or d.has(KEY_ZONE) or d.has(KEY_INDEX):
		return null
	return concede(parsed_seat)


static func _commit_from_dict(d: Dictionary, parsed_seat: int) -> EngineAction:
	if not d.has(KEY_CARDS) or d.has(KEY_ZONE) or d.has(KEY_INDEX):
		return null
	var ids: Array[int] = []
	if not _parse_ints(d[KEY_CARDS], ids):
		return null
	var parsed_slots: Array[int] = []
	if d.has(KEY_SLOTS) and not _parse_ints(d[KEY_SLOTS], parsed_slots):
		return null
	return commit(parsed_seat, ids, parsed_slots)


static func _choose_from_dict(d: Dictionary, parsed_seat: int) -> EngineAction:
	if not (d.has(KEY_ZONE) and d.has(KEY_INDEX)):
		return null
	var zone_raw: Variant = d[KEY_ZONE]
	var index_raw: Variant = d[KEY_INDEX]
	if not (_is_whole_number(zone_raw) and _is_whole_number(index_raw)):
		return null
	return choose(parsed_seat, _as_int(zone_raw), _as_int(index_raw))


static func _choose_set_from_dict(d: Dictionary, parsed_seat: int) -> EngineAction:
	if not (d.has(KEY_ZONE) and d.has(KEY_INDEX)):
		return null
	var zone_raw: Variant = d[KEY_ZONE]
	if not _is_whole_number(zone_raw):
		return null
	var parsed_indices: Array[int] = []
	if not _parse_ints(d[KEY_INDEX], parsed_indices):
		return null
	return choose_set(parsed_seat, _as_int(zone_raw), parsed_indices)


## Appends every entry of `raw` to `out` as an int; false when `raw` is not an Array of
## whole numbers within MAX_SAFE_FLOAT.
static func _parse_ints(raw: Variant, out: Array[int]) -> bool:
	if not raw is Array:
		return false
	var entries: Array = raw
	for entry: Variant in entries:
		if not _is_whole_number(entry):
			return false
		out.append(_as_int(entry))
	return true


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
		return is_finite(f) and f == floorf(f) and absf(f) <= MAX_SAFE_FLOAT
	return false
