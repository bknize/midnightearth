class_name Choice
extends RefCounted
## Prompt targets (cycle 9 plan P12): the zones, the prompt flags and the card a position
## names. Pure: reads a MatchState, never writes one.
##
## Zones are relative to the prompted seat: OWN_* are its own hand, row, Pile and Deck top,
## OPPONENT_* the other seat's. An index is the position in that zone's ordered list at the
## time of the choice: a hand in hand order, a row in slot order, a Pile in Pile order, the
## Deck top from the top card down. A face-down card is chosen by its position, never by
## its id.
##
## Two-seat zones: BOTH_BOARDS is one flat list made of the prompted seat's own row in slot
## order followed by the opponent's; index i < own row size is own slot i, otherwise
## opponent slot i - own row size. BOTH_PILES maps the two Piles the same way. Both sizes
## are public, so either seat (and the board) can map an index to a card.
##
## The prompt dictionary (MatchState.prompt, SeatView.prompt, PROMPT_OPENED) names its zone
## by ZONE_NAMES (KEY_ZONE, a String, P12); EngineAction.choose and choose_set carry the
## Zone value, and zone_of() reads either form. Every prompt carries `multi`, `exact` (the
## set size a multi-select requires, -1 for any size), `min`, `optional`, `resume` and
## `step`, and an "up to N" multi-select also `max` (DC-14 T17, C15 2a: Exhume); is_valid_set()
## checks a set answer against them.

enum Zone {
	OWN_HAND,
	OWN_BOARD,
	OPPONENT_HAND,
	OPPONENT_BOARD,
	BOTH_BOARDS,
	OWN_PILE,
	OPPONENT_PILE,
	BOTH_PILES,
	OWN_DECK_TOP,
}

## Names of Zone, indexed by the enum value: the prompt's and the events' `zone`.
const ZONE_NAMES: Array[String] = [
	"own_hand",
	"own_board",
	"opponent_hand",
	"opponent_board",
	"both_boards",
	"own_pile",
	"opponent_pile",
	"both_piles",
	"own_deck_top",
]
const KEY_ZONE: String = "zone"
const KEY_OPTIONS: String = "options"
## Whether a prompt takes a set (EngineAction.CHOOSE_SET).
const KEY_MULTI: String = "multi"
## The set size a multi-select requires (the discard-down's excess); -1 for any size.
const KEY_EXACT: String = "exact"
## The fewest cards a multi-select set may name (0 for "any number" or "up to N").
const KEY_MIN: String = "min"
## The most cards a multi-select set may name ("up to N", C15 2a); absent or -1 for no bound
## but the options.
const KEY_MAX: String = "max"
## Whether a prompt may be declined (EngineAction.DECLINE).
const KEY_OPTIONAL: String = "optional"
## What an answered prompt resumes: one of the RESUME_* names.
const KEY_RESUME: String = "resume"
## The drain point a prompt opened at, "D1" to "D12", for the board's banner.
const KEY_STEP: String = "step"
## The Crew id of a Crew prompt, "" for a card prompt (whose `card` is the source; a Crew
## prompt's `card` is -1).
const KEY_CREW: String = "crew"
const RESUME_WALK: String = "walk"
const RESUME_TURN_START: String = "turn_start"
const RESUME_COMMIT: String = "commit"
const RESUME_TURN_END: String = "turn_end"
const RESUME_ROUND_END: String = "round_end"
const RESUMES: Array[String] = [
	RESUME_WALK, RESUME_TURN_START, RESUME_COMMIT, RESUME_TURN_END, RESUME_ROUND_END
]
const NO_ZONE: int = -1
## `exact` of a multi-select that takes a set of any size.
const ANY_SIZE: int = -1
## `max` of a multi-select bounded only by its options.
const NO_MAX: int = -1


## The name of a zone, or "" when out of range.
static func zone_name(zone: int) -> String:
	if zone < 0 or zone >= ZONE_NAMES.size():
		return ""
	return ZONE_NAMES[zone]


## The Zone value of a name, NO_ZONE for an unknown one.
static func zone_from_name(name: String) -> int:
	return ZONE_NAMES.find(name)


## The Zone value of `prompt`'s `zone`, read as a name (P12) or, for a hand-made prompt, as
## the value itself; NO_ZONE when absent or unknown.
static func zone_of(prompt: Dictionary) -> int:
	var raw: Variant = prompt.get(KEY_ZONE, NO_ZONE)
	if raw is String:
		var named: String = raw
		return zone_from_name(named)
	if raw is int:
		var value: int = raw
		return value if value >= 0 and value < ZONE_NAMES.size() else NO_ZONE
	return NO_ZONE


## Whether `zone` is a hand (its cards are hidden from the other seat).
static func is_hand(zone: int) -> bool:
	return zone == Zone.OWN_HAND or zone == Zone.OPPONENT_HAND


## Whether `zone` is made of Piles: its cards are public.
static func is_pile(zone: int) -> bool:
	return zone == Zone.OWN_PILE or zone == Zone.OPPONENT_PILE or zone == Zone.BOTH_PILES


## Whether `zone` holds cards the other seat may not see: a hand or the Deck top.
static func is_hidden_zone(zone: int) -> bool:
	return is_hand(zone) or zone == Zone.OWN_DECK_TOP


## Whether the prompt dictionary `prompt` is a multi-select (its `multi` flag).
static func is_multi_prompt(prompt: Dictionary) -> bool:
	return _flag(prompt, KEY_MULTI)


## Whether the prompt dictionary `prompt` may be declined (its `optional` flag).
static func is_optional_prompt(prompt: Dictionary) -> bool:
	return _flag(prompt, KEY_OPTIONAL)


## The set size `prompt` requires (its `exact`), ANY_SIZE when absent.
static func exact_of(prompt: Dictionary) -> int:
	return _int(prompt, KEY_EXACT, ANY_SIZE)


## The fewest cards a set answer to `prompt` may name (its `min`), 0 when absent.
static func min_of(prompt: Dictionary) -> int:
	return _int(prompt, KEY_MIN, 0)


## The most cards a set answer to `prompt` may name (its `max`), NO_MAX when absent.
static func max_of(prompt: Dictionary) -> int:
	return _int(prompt, KEY_MAX, NO_MAX)


## What answering `prompt` resumes (its `resume`), RESUME_WALK when absent or unknown.
static func resume_of(prompt: Dictionary) -> String:
	var resume: String = _string(prompt, KEY_RESUME, RESUME_WALK)
	return resume if RESUMES.has(resume) else RESUME_WALK


## The drain point of `prompt` (its `step`), "" when absent.
static func step_of(prompt: Dictionary) -> String:
	return _string(prompt, KEY_STEP, "")


## The Crew id of `prompt` (its `crew`), "" for a card prompt.
static func crew_of(prompt: Dictionary) -> String:
	return _string(prompt, KEY_CREW, "")


## Whether `indices` is a valid answer to the multi-select `prompt` in `zone` (R14): the
## zone is the prompt's, every index is one of its options, none repeats, and the set's
## size is the prompt's `exact` (when it has one), at least its `min` and at most its `max`
## (when it has one; LegalPlays.set_size_ok). The caller has checked the prompt is a
## multi-select.
static func is_valid_set(prompt: Dictionary, zone: int, indices: Array[int]) -> bool:
	if zone != zone_of(prompt):
		return false
	var options: Array[int] = options_of(prompt)
	var seen: Dictionary[int, bool] = {}
	for index: int in indices:
		if seen.has(index) or not options.has(index):
			return false
		seen[index] = true
	return LegalPlays.set_size_ok(indices.size(), exact_of(prompt), min_of(prompt), max_of(prompt))


## The card at `index` of `zone` for `seat`, or -1 when the index or zone is out of range.
static func resolve(state: MatchState, seat: int, zone: int, index: int) -> int:
	var listed: Array[int] = zone_cards(state, seat, zone)
	if index < 0 or index >= listed.size():
		return -1
	return listed[index]


## The seat whose zone holds position `index` of `zone` for `seat`, or -1 when out of range.
static func seat_at(state: MatchState, seat: int, zone: int, index: int) -> int:
	if seat < 0 or seat > 1 or index < 0 or zone < 0 or zone >= ZONE_NAMES.size():
		return -1
	var holder: int = seat
	var local: int = index
	var own_size: int = _size_in(state.seats[seat], zone)
	if zone == Zone.OPPONENT_HAND or zone == Zone.OPPONENT_BOARD or zone == Zone.OPPONENT_PILE:
		holder = 1 - seat
	elif _is_both(zone) and index >= own_size:
		holder = 1 - seat
		local = index - own_size
	return holder if local < _size_in(state.seats[holder], zone) else -1


## The position of `index` of `zone` for `seat` within its holder's own list, or -1 when out
## of range.
static func local_index(state: MatchState, seat: int, zone: int, index: int) -> int:
	var holder: int = seat_at(state, seat, zone, index)
	if holder < 0:
		return -1
	if holder != seat and _is_both(zone):
		return index - _size_in(state.seats[seat], zone)
	return index


## The cards of `zone` for `seat`, in position order (a copy); empty for an unknown zone.
static func zone_cards(state: MatchState, seat: int, zone: int) -> Array[int]:
	var out: Array[int] = []
	if seat < 0 or seat > 1:
		return out
	var own: MatchState.SeatPiles = state.seats[seat]
	var other: MatchState.SeatPiles = state.seats[1 - seat]
	match zone:
		Zone.OWN_HAND:
			out.assign(own.hand)
		Zone.OWN_BOARD:
			out.assign(own.board)
		Zone.OPPONENT_HAND:
			out.assign(other.hand)
		Zone.OPPONENT_BOARD:
			out.assign(other.board)
		Zone.BOTH_BOARDS:
			out.assign(own.board)
			out.append_array(other.board)
		Zone.OWN_PILE:
			out.assign(own.pile)
		Zone.OPPONENT_PILE:
			out.assign(other.pile)
		Zone.BOTH_PILES:
			out.assign(own.pile)
			out.append_array(other.pile)
		Zone.OWN_DECK_TOP:
			out.assign(own.deck)
	return out


## Whether (`zone`, `index`) is one of the open `prompt`'s options.
static func is_offered(prompt: Dictionary, zone: int, index: int) -> bool:
	if prompt.is_empty() or not prompt.has(KEY_OPTIONS):
		return false
	if zone != zone_of(prompt):
		return false
	return options_of(prompt).has(index)


## The options of a prompt dictionary as a typed copy.
static func options_of(prompt: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var raw: Variant = prompt.get(KEY_OPTIONS)
	if raw is Array:
		var listed: Array = raw
		out.assign(listed)
	return out


## Whether `zone` is one flat list over both seats.
static func _is_both(zone: int) -> bool:
	return zone == Zone.BOTH_BOARDS or zone == Zone.BOTH_PILES


## The size of `zone`'s list held by `piles`: its hand, Pile, Deck or row.
static func _size_in(piles: MatchState.SeatPiles, zone: int) -> int:
	if is_hand(zone):
		return piles.hand.size()
	if is_pile(zone):
		return piles.pile.size()
	if zone == Zone.OWN_DECK_TOP:
		return piles.deck.size()
	return piles.board.size()


static func _flag(prompt: Dictionary, key: String) -> bool:
	var raw: Variant = prompt.get(key, false)
	if not raw is bool:
		return false
	var flag: bool = raw
	return flag


static func _string(prompt: Dictionary, key: String, fallback: String) -> String:
	var raw: Variant = prompt.get(key, fallback)
	if not raw is String:
		return fallback
	var text: String = raw
	return text


static func _int(prompt: Dictionary, key: String, fallback: int) -> int:
	var raw: Variant = prompt.get(key, fallback)
	if not raw is int:
		return fallback
	var value: int = raw
	return value
