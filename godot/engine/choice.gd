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
## Two-board zone (DC-05 T05): a verb whose targets may lie on either row
## (RETURN_AT_TURN_END; the switch it also served retired at DC-07 T01) uses BOTH_BOARDS,
## one flat list made of the prompted seat's own row in slot order followed by the
## opponent's row in slot order. Index i < own row size is own slot i; otherwise it is
## opponent slot i - own row size. Both row sizes are public, so either seat (and the
## board's PromptRules) can map an index to a card.
##
## Two-pile zone (DC-07 R19, P12, C12): RECOVER_DESTROYED uses BOTH_DESTROYED, the prompted
## seat's own destroyed pile in pile order followed by the opponent's, mapped like
## BOTH_BOARDS (index i < own pile size is own position i, else opponent position i - own
## pile size). Both pile sizes are public; an opponent entry is chosen by position, and its
## id is not public unless the card was revealed when it left the row (R18). A card
## destroyed this turn is still on its row, not in a pile, so it is never offered (R21).
##
## Eligibility per verb (R20):
## - DRAW_THEN_DISCARD: OWN_HAND, every position (after the draws).
## - SWAP_PLACES: OWN_BOARD, every card but the source, revealed or not, destroyed or not
##   (DC-06 R16).
## - RETURN_AT_TURN_END: BOTH_BOARDS, every revealed card not destroyed but the source.
## - RECOVER_DESTROYED: BOTH_DESTROYED, every position (DC-07 P12).
## - SACRIFICE_DESTROY: OWN_BOARD, every live (not destroyed) card but the source, revealed
##   or not; a multi-select (DC-07 P7, P12, R22): the answer is a set of those positions.
## - DISCARD_OWN (DC-07 P12): OWN_HAND, every position.
## - DESTROY_OWN_THEN_DRAW, DESTROY_OWN_THEN_FLAT_UP (DC-07 P12): OWN_BOARD, every live card
##   but the source, revealed or not.
## - COPY_STATS (DC-07 P12): OPPONENT_BOARD, every revealed live card.
## - MOVE_OPPONENT_LEFT (DC-07 P12): OPPONENT_BOARD, every position but slot 0, face down or
##   destroyed included: a face-down card is chosen by its position and its id stays hidden.
## - SWAP_OPPONENT_RIGHT (DC-07 P12): OPPONENT_BOARD, every position but the rightmost, face
##   down or destroyed included.
## - GROW_OTHER_FLAT (cycle 8 P8): OWN_BOARD, every live card but the source, revealed or not.
## - GROW_HAND_ONE_TIMES (cycle 8 P8): OWN_HAND, every position (one card auto-chooses).
## - RETURN_OWN_AT_TURN_END (cycle 8 P8): OWN_BOARD, every live card not already marked to
##   return but the source, revealed or not.
## - RETURN_OPPONENT_AT_TURN_END (cycle 8 P8): OPPONENT_BOARD, every revealed live card not
##   already marked to return.
## Any other verb needs no choice: eligible() gives zone -1 and no options. The three
## OPPONENT_BOARD verbs are DriftEffects' (DC-07 T07).
##
## Multi-select prompts (DC-07 P7, R22-R25): the prompt carries `multi` (KEY_MULTI) true;
## every prompt carries the key, false for a single-target one. is_valid_set() checks a set
## answer against the prompt.
##
## Events name zones by ZONE_NAMES (as they name verbs and triggers by their JSON names);
## MatchState.prompt, SeatView.prompt and EngineAction.choose use the enum value.

enum Zone { OWN_HAND, OWN_BOARD, OPPONENT_HAND, OPPONENT_BOARD, BOTH_BOARDS, BOTH_DESTROYED }

## Event names of Zone, indexed by the enum value (CHOICE_REQUESTED, CHOICE_MADE `zone`).
const ZONE_NAMES: Array[String] = [
	"own_hand", "own_board", "opponent_hand", "opponent_board", "both_boards", "both_destroyed"
]
const KEY_ZONE: String = "zone"
const KEY_OPTIONS: String = "options"
## Whether a prompt takes a set (DC-07 P7): MatchState.prompt, SeatView.prompt and
## CHOICE_REQUESTED all carry it.
const KEY_MULTI: String = "multi"
const NO_ZONE: int = -1


## The event name of a zone, or "" when out of range.
static func zone_name(zone: int) -> String:
	if zone < 0 or zone >= ZONE_NAMES.size():
		return ""
	return ZONE_NAMES[zone]


## Whether `zone` is a hand (its cards are hidden from the other seat, R34).
static func is_hand(zone: int) -> bool:
	return zone == Zone.OWN_HAND or zone == Zone.OPPONENT_HAND


## Whether `zone` is made of destroyed piles (DC-07 P12): its cards are off the rows, so
## their identity is public only where `destroyed_known` says so (R18).
static func is_pile(zone: int) -> bool:
	return zone == Zone.BOTH_DESTROYED


## Whether `verb` (a CardEffect.Verb) needs a target chosen (the two grow prompt verbs and
## the two prompt return verbs since cycle 8 P8).
static func needs_choice(verb: int) -> bool:
	return (
		verb == CardEffect.Verb.DRAW_THEN_DISCARD
		or verb == CardEffect.Verb.SWAP_PLACES
		or verb == CardEffect.Verb.RETURN_AT_TURN_END
		or verb == CardEffect.Verb.RECOVER_DESTROYED
		or verb == CardEffect.Verb.SACRIFICE_DESTROY
		or verb == CardEffect.Verb.DISCARD_OWN
		or verb == CardEffect.Verb.DESTROY_OWN_THEN_DRAW
		or verb == CardEffect.Verb.DESTROY_OWN_THEN_FLAT_UP
		or verb == CardEffect.Verb.GROW_OTHER_FLAT
		or verb == CardEffect.Verb.GROW_HAND_ONE_TIMES
		or verb == CardEffect.Verb.RETURN_OWN_AT_TURN_END
		or zone_for(verb) == Zone.OPPONENT_BOARD
	)


## Whether `verb` (a CardEffect.Verb) asks for a set of targets (DC-07 P7, R22): its prompt
## is a multi-select, opened even for one eligible position (R25).
static func is_multi(verb: int) -> bool:
	return verb == CardEffect.Verb.SACRIFICE_DESTROY


## Whether the prompt dictionary `prompt` is a multi-select (its `multi` flag).
static func is_multi_prompt(prompt: Dictionary) -> bool:
	var raw: Variant = prompt.get(KEY_MULTI, false)
	if not raw is bool:
		return false
	var multi: bool = raw
	return multi


## Whether `indices` is a valid answer to the multi-select `prompt` in `zone` (R23, P7): the
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


## The zone `verb` chooses from, or NO_ZONE when it needs no choice.
static func zone_for(verb: int) -> int:
	match verb:
		CardEffect.Verb.DRAW_THEN_DISCARD, CardEffect.Verb.DISCARD_OWN:
			return Zone.OWN_HAND
		CardEffect.Verb.SWAP_PLACES, CardEffect.Verb.SACRIFICE_DESTROY:
			return Zone.OWN_BOARD
		CardEffect.Verb.DESTROY_OWN_THEN_DRAW, CardEffect.Verb.DESTROY_OWN_THEN_FLAT_UP:
			return Zone.OWN_BOARD
		CardEffect.Verb.RETURN_AT_TURN_END:
			return Zone.BOTH_BOARDS
		CardEffect.Verb.RECOVER_DESTROYED:
			return Zone.BOTH_DESTROYED
		CardEffect.Verb.COPY_STATS, CardEffect.Verb.MOVE_OPPONENT_LEFT:
			return Zone.OPPONENT_BOARD
		CardEffect.Verb.SWAP_OPPONENT_RIGHT:
			return Zone.OPPONENT_BOARD
		CardEffect.Verb.GROW_OTHER_FLAT:
			return Zone.OWN_BOARD
		CardEffect.Verb.GROW_HAND_ONE_TIMES:
			return Zone.OWN_HAND
		CardEffect.Verb.RETURN_OWN_AT_TURN_END:
			return Zone.OWN_BOARD
		CardEffect.Verb.RETURN_OPPONENT_AT_TURN_END:
			return Zone.OPPONENT_BOARD
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
	var own_size: int = _size_in(state.seats[seat], zone)
	if zone == Zone.OPPONENT_HAND or zone == Zone.OPPONENT_BOARD:
		holder = 1 - seat
	elif (zone == Zone.BOTH_BOARDS or zone == Zone.BOTH_DESTROYED) and index >= own_size:
		holder = 1 - seat
		local = index - own_size
	return holder if local < _size_in(state.seats[holder], zone) else -1


## The position of `index` of `zone` for `seat` within its holder's own list (the hand, the
## row or the destroyed pile), or -1 when out of range: CARD_RECOVERED `position`.
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


static func _is_eligible(
	state: MatchState, seat: int, verb: int, source: int, zone: int, index: int, card: int
) -> bool:
	match verb:
		CardEffect.Verb.DRAW_THEN_DISCARD, CardEffect.Verb.DISCARD_OWN:
			return true
		CardEffect.Verb.SWAP_PLACES:
			return card != source
		CardEffect.Verb.RETURN_AT_TURN_END:
			return card != source and _is_live_and_revealed(state, seat, zone, index, card)
		CardEffect.Verb.RECOVER_DESTROYED:
			return true
		CardEffect.Verb.SACRIFICE_DESTROY, CardEffect.Verb.DESTROY_OWN_THEN_DRAW:
			return card != source and not state.is_destroyed(card)
		CardEffect.Verb.DESTROY_OWN_THEN_FLAT_UP, CardEffect.Verb.GROW_OTHER_FLAT:
			return card != source and not state.is_destroyed(card)
		CardEffect.Verb.GROW_HAND_ONE_TIMES:
			return true
		CardEffect.Verb.RETURN_OWN_AT_TURN_END:
			var live: bool = card != source and not state.is_destroyed(card)
			return live and not EchoEffects.is_return_marked(state, card)
		CardEffect.Verb.RETURN_OPPONENT_AT_TURN_END:
			var shown: bool = _is_live_and_revealed(state, seat, zone, index, card)
			return shown and not EchoEffects.is_return_marked(state, card)
		CardEffect.Verb.COPY_STATS:
			return _is_live_and_revealed(state, seat, zone, index, card)
		CardEffect.Verb.MOVE_OPPONENT_LEFT:
			return index > 0
		CardEffect.Verb.SWAP_OPPONENT_RIGHT:
			# A card stands to its right: the next position is on the same row.
			return seat_at(state, seat, zone, index + 1) >= 0
	return false


## Whether `card` is revealed and not destroyed (DC-06 R16): the return skips destroyed
## cards; the swap does not ask.
## The size of `zone`'s list held by `piles`: its hand, destroyed pile or row.
static func _size_in(piles: MatchState.SeatPiles, zone: int) -> int:
	if is_hand(zone):
		return piles.hand.size()
	if is_pile(zone):
		return piles.destroyed.size()
	return piles.board.size()


static func _is_live_and_revealed(
	state: MatchState, seat: int, zone: int, index: int, card: int
) -> bool:
	return not state.is_destroyed(card) and _is_revealed_at(state, seat, zone, index, card)


static func _is_revealed_at(state: MatchState, seat: int, zone: int, index: int, card: int) -> bool:
	var holder: int = seat_at(state, seat, zone, index)
	if holder < 0:
		return false
	var piles: MatchState.SeatPiles = state.seats[holder]
	return piles.is_revealed(card)
