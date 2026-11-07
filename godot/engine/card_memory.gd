class_name CardMemory
extends RefCounted
## What "for the match" and "permanently" abilities gave one card instance (cycle 9 plan P8;
## spec R30): Memory, which follows the card through every zone, the Pile and a Deck
## included. Kept in MatchState.memory by instance id: created at its defaults by
## MatchState.memory_for(), never cleared, started empty only when a match is created.
## CardState holds the Board changes, which leave with the row.
##
## Scoring reads it (plan P7): `power` adds to the card's Power; its Mult is
## Scoring.grown_mult(printed Mult, `mult_add_steps`, `mult_times_steps`, `mult_cap`), the
## base, then the additive steps, then each multiplicative step rounded to the hundredth,
## capped; `add_steps` adds to its printed Add; `cost_delta` (signed, a reduction is
## negative) adds to its Cost, never below MatchRules.MIN_COST. `uses_left` is -1 until the
## card's limited ability is first read, then the uses it has left.
## `permanent_statuses` lists the statuses given "permanently" (Statuses, DC-13 T04, P8,
## P9), in the order given: Memory, so they survive the Pile, a redraw and an un-reveal.

## Power gained for the match, in whole units.
var power: int = 0
## Additive Mult growth in hundredths (+0.25 is 25), applied before `mult_times_steps`.
var mult_add_steps: int = 0
## Multiplicative Mult growth steps in hundredths (×1.2 is 120), applied in order.
var mult_times_steps: Array[int] = []
## The highest cap a Mult growth named, in hundredths (Sapling 200, Graft 250); 0 when no
## growth named one.
var mult_cap: int = 0
## Add growth in hundredths.
var add_steps: int = 0
## A Cost change for the match: negative reduces (Tinker, Layaway).
var cost_delta: int = 0
## The uses left of the card's limited ability; -1 until first read.
var uses_left: int = -1
## Permanent statuses (Statuses.MUTED, SQUELCHED, ANCHORED), each at most once.
var permanent_statuses: Array[String] = []


## True when no ability has written anything: every growth 0 or empty and `uses_left`
## unread. An entry with `uses_left` set is not empty, so a spent card still shows its mark.
func is_empty() -> bool:
	return (
		power == 0
		and mult_add_steps == 0
		and mult_times_steps.is_empty()
		and mult_cap == 0
		and add_steps == 0
		and cost_delta == 0
		and uses_left == -1
		and permanent_statuses.is_empty()
	)


## Whether the Memory grows the card's Mult (an additive or multiplicative step).
func grows_mult() -> bool:
	return mult_add_steps != 0 or not mult_times_steps.is_empty()


## An independent copy.
func copy() -> CardMemory:
	var out: CardMemory = CardMemory.new()
	out.power = power
	out.mult_add_steps = mult_add_steps
	out.mult_times_steps.assign(mult_times_steps)
	out.mult_cap = mult_cap
	out.add_steps = add_steps
	out.cost_delta = cost_delta
	out.uses_left = uses_left
	out.permanent_statuses.assign(permanent_statuses)
	return out


## Plain data, for MatchState.to_dict() and comparisons: {power, mult_add_steps,
## mult_times_steps, mult_cap, add_steps, cost_delta, uses_left, permanent_statuses}.
func to_dict() -> Dictionary:
	var steps: Array = []
	steps.assign(mult_times_steps)
	var kept_statuses: Array = []
	kept_statuses.assign(permanent_statuses)
	return {
		"power": power,
		"mult_add_steps": mult_add_steps,
		"mult_times_steps": steps,
		"mult_cap": mult_cap,
		"add_steps": add_steps,
		"cost_delta": cost_delta,
		"uses_left": uses_left,
		"permanent_statuses": kept_statuses,
	}
