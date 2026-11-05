class_name CardMemory
extends RefCounted
## What persisting abilities gave one card instance for the match (cycle 8 R1-R8, plan P2).
## Kept in MatchState.memory by instance id: created at its defaults by
## MatchState.memory_for(), never cleared at round start, a return, an un-reveal or a
## recovery, and started empty only when a match is created. Unlike CardState, which leaves
## with the card's row, it follows the card through every zone.
##
## ScoreWalk.effective() adds `flat`, `times` and `plus` to the card's base (printed or
## copied) before any board-specific change (P3); ScoreWalk.effective_cost() subtracts
## `cost` from the printed cost, never below MatchRules.MIN_COST. `uses_left` is -1 until
## the card's limited ability is first read, then the uses it has left (P7).

## A flat delta, in whole units.
var flat: int = 0
## A ×-part delta in hundredths: +25 turns a printed ×1.25 into ×1.50, and a card with no
## ×-bonus into ×1.25 (R3).
var times: int = 0
## A +-part delta, in whole units.
var plus: int = 0
## A cost reduction, >= 0 (R4).
var cost: int = 0
## The uses left of the card's limited ability; -1 until first read (P7).
var uses_left: int = -1


## True when no ability has written anything: every delta 0 and `uses_left` unread. An entry
## with `uses_left` set is not empty, so a spent once-per-match card still shows its mark.
func is_empty() -> bool:
	return flat == 0 and times == 0 and plus == 0 and cost == 0 and uses_left == -1


## An independent copy.
func copy() -> CardMemory:
	var out: CardMemory = CardMemory.new()
	out.flat = flat
	out.times = times
	out.plus = plus
	out.cost = cost
	out.uses_left = uses_left
	return out


## Plain data, for MatchState.to_dict() and comparisons: {flat, times, plus, cost,
## uses_left}.
func to_dict() -> Dictionary:
	return {
		"flat": flat,
		"times": times,
		"plus": plus,
		"cost": cost,
		"uses_left": uses_left,
	}
