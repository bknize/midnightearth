class_name CardState
extends RefCounted
## Per-instance modifiers of one card on a row (plan, MatchState additions; P4). Kept in
## MatchState.card_states by instance id, cleared at round start and whenever the card
## leaves the board. A card with no entry has every field at its default.
##
## ScoreWalk.effective() applies them in this order: `switched` swaps the definition's flat
## and bonus, then `flat_delta` adds to the flat, then `bonus_zero` sets the bonus to 0.
## `return_marked` does not change stats: the card goes back at the end of the turn (R24).

## Added to the flat after any switch (the on-score flat-up effect).
var flat_delta: int = 0
## The card's flat and bonus are exchanged (the switch effect).
var switched: bool = false
## The card's bonus is 0 for the rest of the round (R22).
var bonus_zero: bool = false
## The card returns to its owner's hand at the end of this turn (R24).
var return_marked: bool = false


## True when every field is at its default, so the entry changes nothing.
func is_default() -> bool:
	return flat_delta == 0 and not switched and not bonus_zero and not return_marked


## An independent copy.
func copy() -> CardState:
	var out: CardState = CardState.new()
	out.flat_delta = flat_delta
	out.switched = switched
	out.bonus_zero = bonus_zero
	out.return_marked = return_marked
	return out


## Plain data, for MatchState.to_dict() and comparisons.
func to_dict() -> Dictionary:
	return {
		"flat_delta": flat_delta,
		"switched": switched,
		"bonus_zero": bonus_zero,
		"return_marked": return_marked,
	}
