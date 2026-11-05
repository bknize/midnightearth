class_name CardState
extends RefCounted
## Per-instance modifiers of one card on a row (plan, MatchState additions; DC-07 P5). Kept
## in MatchState.card_states by instance id, cleared at round start and whenever the card
## leaves the board. A card with no entry has every field at its default.
##
## ScoreWalk.effective() reads them as: the base (the definition's flat and bonus, or the
## stored `base_flat`, `base_times` and `base_plus` once `has_base` is set by a copy, DC-07
## T07, R34, C22), then the positional ×-parts, then `flat_delta` adds to the flat and
## `temp_plus` to the +-part, then `no_bonus` makes the ×-part ×1.00 and the +-part 0 (R13,
## R14).
## `temp_plus` lasts until the walk ends (ScoreWalk clears it for every card then);
## `no_bonus` and `flat_delta` live until the card leaves the board.
## `return_marked` does not change stats: the card goes back at the end of the turn (R24).
## `destroyed` (DC-06 R12-R22, P4) does not change stats either: the card keeps its slot,
## scores nothing and fires nothing, and leaves for its seat's destroyed pile at turn end
## (EffectResolver.clear_destroyed), which ends the mark with the rest of the entry.

## The base below is in use instead of the definition's stats (set by a copy, DC-07 T07).
var has_base: bool = false
## The base flat once `has_base` is set.
var base_flat: int = 0
## The base ×-part once `has_base` is set, in hundredths (MatchRules.MULT_ONE for none). A
## copy stores the target's whole shown bonus, so the base may hold a ×-part and a +-part
## at once (R34, C22).
var base_times: int = MatchRules.MULT_ONE
## The base +-part once `has_base` is set, in whole units (0 for none). Both base parts go
## with the entry when the card leaves the board or is un-revealed.
var base_plus: int = 0
## Added to the base flat (the on-score flat-up effect).
var flat_delta: int = 0
## The card has no bonus (R14): ×1.00 and +0, whatever its base and `temp_plus` say.
var no_bonus: bool = false
## Whole units added to the +-part until the walk ends (DC-07 P5, P11).
var temp_plus: int = 0
## The card returns to its owner's hand at the end of this turn (R24).
var return_marked: bool = false
## The card is destroyed (DC-06 R12): it stays in its slot until the turn ends.
var destroyed: bool = false
## Salvager was accepted for this destroyed card (cycle 8 R51, P14; DC-11 T10); at turn end
## EffectResolver.clear_destroyed() sends it to its controller's hand, not to the pile.
var salvaged: bool = false


## True when every field is at its default, so the entry changes nothing.
func is_default() -> bool:
	return (
		not has_base
		and flat_delta == 0
		and not no_bonus
		and temp_plus == 0
		and not return_marked
		and not destroyed
		and not salvaged
	)


## An independent copy.
func copy() -> CardState:
	var out: CardState = CardState.new()
	out.has_base = has_base
	out.base_flat = base_flat
	out.base_times = base_times
	out.base_plus = base_plus
	out.flat_delta = flat_delta
	out.no_bonus = no_bonus
	out.temp_plus = temp_plus
	out.return_marked = return_marked
	out.destroyed = destroyed
	out.salvaged = salvaged
	return out


## Plain data, for MatchState.to_dict() and comparisons.
func to_dict() -> Dictionary:
	return {
		"has_base": has_base,
		"base_flat": base_flat,
		"base_times": base_times,
		"base_plus": base_plus,
		"flat_delta": flat_delta,
		"no_bonus": no_bonus,
		"temp_plus": temp_plus,
		"return_marked": return_marked,
		"destroyed": destroyed,
		"salvaged": salvaged,
	}
