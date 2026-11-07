class_name Choice
extends RefCounted
## Prompt targets (R28-R34, plan P9, P10; cycle 9 plan P12): the zones, the prompt flags and
## the card a position names. Pure: reads a MatchState, never writes one.
##
## Zones are relative to the prompted seat: OWN_* are its own hand and row, OPPONENT_* the
## other seat's. An index is the position in that zone's ordered list at the time of the
## choice (R30): a hand in hand order, a row in slot order. A face-down card is chosen by
## its position, never by its id.
##
## Two-board zone: BOTH_BOARDS is one flat list made of the prompted seat's own row in slot
## order followed by the opponent's row in slot order. Index i < own row size is own slot
## i; otherwise it is opponent slot i - own row size. Both row sizes are public, so either
## seat (and the board's PromptRules) can map an index to a card. BOTH_DESTROYED maps the
## two destroyed piles the same way (v6; DC-13 T03 replaces it with the Pile zones).
##
## Which positions an ability may choose is its verb's (Abilities, DC-13 T06); the v6 verb
## eligibility went with the v6 verbs (DC-13 T02).
##
## Multi-select prompts carry `multi` (KEY_MULTI) true; every prompt carries the key, false
## for a single-target one. is_valid_set() checks a set answer against the prompt. Every
## prompt also carries `optional`, `resume` (RESUME_WALK or RESUME_TURN_START) and `crew`
## (the Crew id, "" for a card prompt).
##
## Events name zones by ZONE_NAMES; MatchState.prompt, SeatView.prompt and
## EngineAction.choose use the enum value.

enum Zone { OWN_HAND, OWN_BOARD, OPPONENT_HAND, OPPONENT_BOARD, BOTH_BOARDS, BOTH_DESTROYED }

## Event names of Zone, indexed by the enum value (CHOICE_REQUESTED, CHOICE_MADE `zone`).
const ZONE_NAMES: Array[String] = [
	"own_hand", "own_board", "opponent_hand", "opponent_board", "both_boards", "both_destroyed"
]
const KEY_ZONE: String = "zone"
const KEY_OPTIONS: String = "options"
## Whether a prompt takes a set: MatchState.prompt, SeatView.prompt and CHOICE_REQUESTED all
## carry it.
const KEY_MULTI: String = "multi"
## Whether a prompt may be declined: every prompt carries it; EngineAction.DECLINE is legal
## only while it is true.
const KEY_OPTIONAL: String = "optional"
## What an answered prompt resumes: RESUME_WALK for a prompt a walk paused on,
## RESUME_TURN_START for one the turn start paused on.
const KEY_RESUME: String = "resume"
## The Crew id of a Crew prompt, "" for a card prompt (whose `card` is the source; a Crew
## prompt's `card` is -1).
const KEY_CREW: String = "crew"
const RESUME_WALK: String = "walk"
const RESUME_TURN_START: String = "turn_start"
const NO_ZONE: int = -1


## The event name of a zone, or "" when out of range.
static func zone_name(zone: int) -> String:
	if zone < 0 or zone >= ZONE_NAMES.size():
		return ""
	return ZONE_NAMES[zone]


## Whether `zone` is a hand (its cards are hidden from the other seat, R34).
static func is_hand(zone: int) -> bool:
	return zone == Zone.OWN_HAND or zone == Zone.OPPONENT_HAND


## Whether `zone` is made of destroyed piles: its cards are off the rows.
static func is_pile(zone: int) -> bool:
	return zone == Zone.BOTH_DESTROYED


## Whether the prompt dictionary `prompt` is a multi-select (its `multi` flag).
static func is_multi_prompt(prompt: Dictionary) -> bool:
	var raw: Variant = prompt.get(KEY_MULTI, false)
	if not raw is bool:
		return false
	var multi: bool = raw
	return multi


## Whether the prompt dictionary `prompt` may be declined (its `optional` flag).
static func is_optional_prompt(prompt: Dictionary) -> bool:
	var raw: Variant = prompt.get(KEY_OPTIONAL, false)
	if not raw is bool:
		return false
	var optional: bool = raw
	return optional


## What answering `prompt` resumes (its `resume`): RESUME_TURN_START, else RESUME_WALK (also
## for a prompt without the key).
static func resume_of(prompt: Dictionary) -> String:
	var raw: Variant = prompt.get(KEY_RESUME, RESUME_WALK)
	if not raw is String:
		return RESUME_WALK
	var resume: String = raw
	return RESUME_TURN_START if resume == RESUME_TURN_START else RESUME_WALK


## The Crew id of `prompt` (its `crew`), "" for a card prompt.
static func crew_of(prompt: Dictionary) -> String:
	var raw: Variant = prompt.get(KEY_CREW, "")
	if not raw is String:
		return ""
	var crew: String = raw
	return crew


## Whether `indices` is a valid answer to the multi-select `prompt` in `zone` (R23): the
## zone is the prompt's, every index is one of its options and none repeats. The empty set
## is valid (the decline, R24). The caller has checked the prompt is a multi-select.
static func is_valid_set(prompt: Dictionary, zone: int, indices: Array[int]) -> bool:
	var prompt_zone: int = prompt.get(KEY_ZONE, NO_ZONE)
	if zone != prompt_zone:
		return false
	var options: Array[int] = options_of(prompt)
	var seen: Dictionary[int, bool] = {}
	for index: int in indices:
		if seen.has(index) or not options.has(index):
			return false
		seen[index] = true
	return true


## The card at `index` of `zone` for `seat`, or -1 when the index or zone is out of range.
static func resolve(state: MatchState, seat: int, zone: int, index: int) -> int:
	var listed: Array[int] = zone_cards(state, seat, zone)
	if index < 0 or index >= listed.size():
		return -1
	return listed[index]


## The seat whose pile holds position `index` of `zone` for `seat`, or -1 when out of range.
static func seat_at(state: MatchState, seat: int, zone: int, index: int) -> int:
	if seat < 0 or seat > 1 or index < 0 or zone < 0 or zone >= ZONE_NAMES.size():
		return -1
	var holder: int = seat
	var local: int = index
	var own_size: int = _size_in(state.seats[seat], zone)
	if zone == Zone.OPPONENT_HAND or zone == Zone.OPPONENT_BOARD:
		holder = 1 - seat
	elif (zone == Zone.BOTH_BOARDS or zone == Zone.BOTH_DESTROYED) and index >= own_size:
		holder = 1 - seat
		local = index - own_size
	return holder if local < _size_in(state.seats[holder], zone) else -1


## The position of `index` of `zone` for `seat` within its holder's own list (the hand, the
## row or the destroyed pile), or -1 when out of range.
static func local_index(state: MatchState, seat: int, zone: int, index: int) -> int:
	var holder: int = seat_at(state, seat, zone, index)
	if holder < 0:
		return -1
	if holder != seat and (zone == Zone.BOTH_BOARDS or zone == Zone.BOTH_DESTROYED):
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
		Zone.BOTH_DESTROYED:
			out.assign(own.destroyed)
			out.append_array(other.destroyed)
	return out


## Whether (`zone`, `index`) is one of the open `prompt`'s options (R31).
static func is_offered(prompt: Dictionary, zone: int, index: int) -> bool:
	if prompt.is_empty() or not prompt.has(KEY_ZONE) or not prompt.has(KEY_OPTIONS):
		return false
	var prompt_zone: int = prompt[KEY_ZONE]
	if zone != prompt_zone:
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


## The size of `zone`'s list held by `piles`: its hand, destroyed pile or row.
static func _size_in(piles: MatchState.SeatPiles, zone: int) -> int:
	if is_hand(zone):
		return piles.hand.size()
	if is_pile(zone):
		return piles.destroyed.size()
	return piles.board.size()
