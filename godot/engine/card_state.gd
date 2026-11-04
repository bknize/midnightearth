class_name CardState
extends RefCounted
## Per-instance modifiers of one card on a row (plan, MatchState additions; P4). Kept in
## MatchState.card_states by instance id, cleared at round start and whenever the card
## leaves the board. A card with no entry has every field at its default.
##
## ScoreWalk.effective() reads them as: the base (the definition's flat and bonus, or the
## stored `base_flat` and `base_bonus` once `has_base` is set), then `flat_delta` adds to
## the flat, then `bonus_zero` sets the bonus to 0.
##
## A switch (R20; DC-05 T13, Ben's ruling 1a) is a time-ordered mutation, not a flag:
## apply_switch() takes the card's stats as they stand at that moment (flat-ups and the
## bonus-0 mark included), stores them exchanged as the new base, and clears `flat_delta`
## and `bonus_zero`, since both are now folded into the base. A modifier that lands later
## applies to the post-switch stats (a flat-up raises the new flat, a bonus-0 zeroes the
## new bonus); a second switch exchanges what is current then.
## `return_marked` does not change stats: the card goes back at the end of the turn (R24).

## The base below is in use instead of the definition's stats (set by a switch).
var has_base: bool = false
## The base flat once `has_base` is set.
var base_flat: int = 0
## The base bonus once `has_base` is set.
var base_bonus: int = 0
## Added to the base flat (the on-score flat-up effect, since the last switch).
var flat_delta: int = 0
## The card's bonus is 0 (R22), until a switch folds it into the base.
var bonus_zero: bool = false
## The card returns to its owner's hand at the end of this turn (R24).
var return_marked: bool = false


## True when every field is at its default, so the entry changes nothing.
func is_default() -> bool:
	return not has_base and flat_delta == 0 and not bonus_zero and not return_marked


## The switch: `current` is the card's (flat, bonus) right now, from its CardState
## (ScoreWalk.switch_stats); the exchanged pair becomes the base and the folded modifiers
## reset.
func apply_switch(current: Vector2i) -> void:
	has_base = true
	base_flat = current.y
	base_bonus = current.x
	flat_delta = 0
	bonus_zero = false


## An independent copy.
func copy() -> CardState:
	var out: CardState = CardState.new()
	out.has_base = has_base
	out.base_flat = base_flat
	out.base_bonus = base_bonus
	out.flat_delta = flat_delta
	out.bonus_zero = bonus_zero
	out.return_marked = return_marked
	return out


## Plain data, for MatchState.to_dict() and comparisons.
func to_dict() -> Dictionary:
	return {
		"has_base": has_base,
		"base_flat": base_flat,
		"base_bonus": base_bonus,
		"flat_delta": flat_delta,
		"bonus_zero": bonus_zero,
		"return_marked": return_marked,
	}
