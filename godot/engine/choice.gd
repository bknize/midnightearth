class_name Choice
extends RefCounted
## Prompt targets (R28-R34, plan P9, P10): the zones, which positions a prompt verb may
## choose, and the card a position names. Pure: reads a MatchState, never writes one.
##
## Zones are relative to the prompted seat: OWN_* are its own hand and row, OPPONENT_* the
## other seat's. An index is the position in that zone's ordered list at the time of the
## choice (R30): a hand in hand order, a row in slot order. A face-down card is chosen by
## its position, never by its id.
##
## Two-board zone (DC-05 T05): a verb whose targets may lie on either row (SWITCH_STATS,
## RETURN_AT_TURN_END) uses BOTH_BOARDS, one flat list made of the prompted seat's own row
## in slot order followed by the opponent's row in slot order. Index i < own row size is
## own slot i; otherwise it is opponent slot i - own row size. Both row sizes are public,
## so either seat (and the board's PromptRules) can map an index to a card.
##
## Eligibility per verb (R20):
## - DRAW_THEN_DISCARD: OWN_HAND, every position (after the draws).
## - SWAP_PLACES: OWN_BOARD, every card but the source, revealed or not.
## - SWITCH_STATS: BOTH_BOARDS, every revealed card, the source included.
## - RETURN_AT_TURN_END: BOTH_BOARDS, every revealed card but the source.
## Any other verb needs no choice: eligible() gives zone -1 and no options.
##
## Events name zones by ZONE_NAMES (as they name verbs and triggers by their JSON names);
## MatchState.prompt, SeatView.prompt and EngineAction.choose use the enum value.

enum Zone { OWN_HAND, OWN_BOARD, OPPONENT_HAND, OPPONENT_BOARD, BOTH_BOARDS }

## Event names of Zone, indexed by the enum value (CHOICE_REQUESTED, CHOICE_MADE `zone`).
const ZONE_NAMES: Array[String] = [
	"own_hand", "own_board", "opponent_hand", "opponent_board", "both_boards"
]
const KEY_ZONE: String = "zone"
const KEY_OPTIONS: String = "options"
const NO_ZONE: int = -1


## The event name of a zone, or "" when out of range.
static func zone_name(zone: int) -> String:
	if zone < 0 or zone >= ZONE_NAMES.size():
		return ""
	return ZONE_NAMES[zone]


## Whether `zone` is a hand (its cards are hidden from the other seat, R34).
static func is_hand(zone: int) -> bool:
	return zone == Zone.OWN_HAND or zone == Zone.OPPONENT_HAND


## Whether `verb` (a CardEffect.Verb) needs a target chosen.
static func needs_choice(verb: int) -> bool:
	return (
		verb == CardEffect.Verb.DRAW_THEN_DISCARD
		or verb == CardEffect.Verb.SWAP_PLACES
		or verb == CardEffect.Verb.SWITCH_STATS
		or verb == CardEffect.Verb.RETURN_AT_TURN_END
	)


## The zone `verb` chooses from, or NO_ZONE when it needs no choice.
static func zone_for(verb: int) -> int:
	match verb:
		CardEffect.Verb.DRAW_THEN_DISCARD:
			return Zone.OWN_HAND
		CardEffect.Verb.SWAP_PLACES:
			return Zone.OWN_BOARD
		CardEffect.Verb.SWITCH_STATS, CardEffect.Verb.RETURN_AT_TURN_END:
			return Zone.BOTH_BOARDS
	return NO_ZONE


## The eligible targets of `verb` fired by `source` for `seat` (P9):
## {"zone": int, "options": Array[int]}, the options ascending positions in that zone.
static func eligible(state: MatchState, seat: int, verb: int, source: int) -> Dictionary:
	var zone: int = zone_for(verb)
	var options: Array[int] = []
	var listed: Array[int] = zone_cards(state, seat, zone)
	for index: int in range(listed.size()):
		var card: int = listed[index]
		if _is_eligible(state, seat, verb, source, zone, index, card):
			options.append(index)
	return {KEY_ZONE: zone, KEY_OPTIONS: options}


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
	var own_size: int = state.seats[seat].board.size()
	if zone == Zone.OPPONENT_HAND or zone == Zone.OPPONENT_BOARD:
		holder = 1 - seat
	elif zone == Zone.BOTH_BOARDS and index >= own_size:
		holder = 1 - seat
		local = index - own_size
	var piles: MatchState.SeatPiles = state.seats[holder]
	var size: int = piles.hand.size() if is_hand(zone) else piles.board.size()
	return holder if local < size else -1


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


static func _is_eligible(
	state: MatchState, seat: int, verb: int, source: int, zone: int, index: int, card: int
) -> bool:
	match verb:
		CardEffect.Verb.DRAW_THEN_DISCARD:
			return true
		CardEffect.Verb.SWAP_PLACES:
			return card != source
		CardEffect.Verb.SWITCH_STATS:
			return _is_revealed_at(state, seat, zone, index, card)
		CardEffect.Verb.RETURN_AT_TURN_END:
			return card != source and _is_revealed_at(state, seat, zone, index, card)
	return false


static func _is_revealed_at(state: MatchState, seat: int, zone: int, index: int, card: int) -> bool:
	var holder: int = seat_at(state, seat, zone, index)
	if holder < 0:
		return false
	var piles: MatchState.SeatPiles = state.seats[holder]
	return piles.is_revealed(card)
