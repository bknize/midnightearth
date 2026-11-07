class_name Scoring
extends RefCounted
## The walking-total arithmetic (cycle 9 plan P7; spec R23 to R28, C3): pure integer maths
## and the effective stats of a card. No float, no node, no clock.
##
## Units: a Bonus (printed, grown or granted) is in hundredths (MatchRules.BONUS_ONE is ×1
## or +1); a Bonus value and the walking total are in ten-thousandths (MatchRules.SCALE).
## Every multiply rounds once with round_half_up(), whose half rounds toward +inf, so a
## negative half rounds up as the canon's "half rounds up" reads (P7).
##
## - bonus_value(adds, mults): (100 + every Add) × 100, then for each Mult
##   round_half_up(bv × mult / 100), never below 0; a card with no Bonus has SCALE.
## - step_total(total, power, bv): total + power × SCALE, then round_half_up(total × bv /
##   SCALE): the three Score steps of R26.
## - walk_score(total): the Walk-end Score, round_half_up(total / SCALE) (R27).
## - grown_mult(base, add_steps, times_steps, cap): base + add_steps, then each ×step as
##   round_half_up(v × step / 100), each result capped at `cap` when it is above 0 (R24).
##
## A card's stats (stats()): its Power (printed, or a copied base, plus Memory's and the
## Board changes' Power), its Adds (printed with Memory's add steps, then granted ones) and
## its Mults (printed grown by Memory, then granted ones). Its Cost (effective_cost()): the
## printed Cost, or the `cost_on_turn` Cost on the named Turn, plus Memory's cost change,
## never below MatchRules.MIN_COST. Ongoing reads (Banner, Void's grant, Tallyman) join with
## DC-13 T06 and T07 through ongoing_power() and the hooks named there.

## The verb that sets a Cost on a named Turn (Colossus, plan P3).
const COST_ON_TURN_VERB: String = "cost_on_turn"
## The verb of an Ongoing "your Hand size is +N" (Pantry, plan P3).
const HAND_SIZE_ADD_VERB: String = "hand_size_add"
## The verb of an Ongoing "each of your cards with no rules text has Power +N" (Banner).
const PLAIN_POWER_VERB: String = "plain_power"
const MOMENT_ONGOING: String = "ongoing"


## round_half_up(x / d) for ints and d > 0: floor((x + d / 2) / d), so a half rounds toward
## +inf for either sign (P7). 0 for a d that is not positive.
static func round_half_up(x: int, d: int) -> int:
	if d <= 0:
		return 0
	@warning_ignore("integer_division")
	var shifted: int = x + d / 2
	@warning_ignore("integer_division")
	var quotient: int = shifted / d
	# GDScript truncates toward 0; floor a negative quotient that has a remainder.
	if shifted % d != 0 and shifted < 0:
		quotient -= 1
	return quotient


## A Bonus value in ten-thousandths from `adds` and `mults` in hundredths (R26, C20): 1 plus
## every Add, then times every Mult, each multiply rounded; never below 0.
static func bonus_value(adds: Array[int], mults: Array[int]) -> int:
	var summed: int = MatchRules.BONUS_ONE
	for add: int in adds:
		summed += add
	var value: int = summed * MatchRules.BONUS_ONE
	for mult: int in mults:
		value = round_half_up(value * mult, MatchRules.BONUS_ONE)
	return maxi(value, 0)


## The walking total after a card of `power` with Bonus value `bv` Scores on `total` (R26,
## R28): the Power is added, then the total is multiplied by the Bonus value.
static func step_total(total: int, power: int, bv: int) -> int:
	var added: int = total + power * MatchRules.SCALE
	return round_half_up(added * bv, MatchRules.SCALE)


## The Walk-end Score of a walking total (R27): rounded once to a whole number, half up.
static func walk_score(total: int) -> int:
	return round_half_up(total, MatchRules.SCALE)


## A grown Mult in hundredths (R24, P7): `base` plus `add_steps`, then each step of
## `times_steps` (hundredths, ×1.2 is 120) multiplied in and rounded to the hundredth; capped
## at `cap` after every step when `cap` is above 0.
static func grown_mult(base: int, add_steps: int, times_steps: Array[int], cap: int) -> int:
	var value: int = _capped(base + add_steps, cap)
	for step: int in times_steps:
		value = _capped(round_half_up(value * step, MatchRules.BONUS_ONE), cap)
	return value


## The product of `mults` (hundredths) in hundredths, each multiply rounded: what a face
## shows as its Mult (MatchRules.BONUS_ONE for none).
static func mult_product(mults: Array[int]) -> int:
	var value: int = MatchRules.BONUS_ONE
	for mult: int in mults:
		value = round_half_up(value * mult, MatchRules.BONUS_ONE)
	return value


## `card`'s effective stats (see the class comment); zero Power and no Bonus for a card with
## no definition.
static func stats(card: int, state: MatchState, cards: MatchCards) -> Stats:
	var out: Stats = Stats.new()
	var def: CardDef = cards.def_of(card) if cards != null else null
	if def == null:
		return out
	var held: CardState = state.card_state(card) if state != null else null
	var kept: CardMemory = state.memory_of(card) if state != null else null
	if held != null and not held.copied_base.is_empty():
		_read_copied_base(out, held.copied_base)
	else:
		_read_printed(out, def, kept)
	if kept != null:
		out.power += kept.power
	if held != null:
		out.power += held.power_delta
		out.adds.append_array(held.granted_of(CardState.KIND_ADD))
		out.mults.append_array(held.granted_of(CardState.KIND_MULT))
	out.power += ongoing_power(card, state, cards)
	return out


## The stats `card` of `seat` Scores with as the `count`th Score of that seat's Walk
## (DC-13 T07, plan P13): stats(), then the Crew's grants for that Score, Void's held grants
## and Tallyman's Mult (CrewAbilities.score_grants). Reads only; ScoreWalk spends the grants.
static func score_stats(
	card: int, state: MatchState, cards: MatchCards, seat: int, count: int
) -> Stats:
	var out: Stats = stats(card, state, cards)
	CrewAbilities.score_grants(out, state, cards, seat, count)
	return out


## Power that Ongoing abilities give `card` now (DC-13 T06), read when it Scores (Q5):
## Banner's `plain_power`, the amount of every read Banner on its Controller's row, for a
## card with no rules text (CardDef.is_plain) on that row. 0 for a card on no row.
static func ongoing_power(card: int, state: MatchState, cards: MatchCards) -> int:
	if state == null or cards == null or not cards.has_verb(PLAIN_POWER_VERB):
		return 0
	var def: CardDef = cards.def_of(card)
	var seat: int = Statuses.row_seat(state, card)
	if def == null or not def.is_plain() or seat < 0:
		return 0
	var total: int = 0
	for ability: CardAbility in ongoing_on_row(state, cards, seat, PLAIN_POWER_VERB):
		total += ability.amount
	return total


## `card`'s effective Cost (R8): its printed Cost, or the `cost_on_turn` amount on the Turn
## its `amount_2` names, plus its Memory's cost change, never below MatchRules.MIN_COST; -1
## for a card with no definition (an unpriced card, as LegalPlays reads it).
static func effective_cost(card: int, state: MatchState, cards: MatchCards) -> int:
	var def: CardDef = cards.def_of(card) if cards != null else null
	if def == null:
		return -1
	var cost: int = def.cost
	var turn: int = state.turn if state != null else 0
	for ability: CardAbility in def.abilities:
		if ability.verb == COST_ON_TURN_VERB and ability.amount_2 == turn:
			cost = ability.amount
	var kept: CardMemory = state.memory_of(card) if state != null else null
	if kept != null:
		cost += kept.cost_delta
	return maxi(cost, MatchRules.MIN_COST)


## The effective costs of `hand`, in its order (effective_cost each).
static func effective_costs(hand: Array[int], state: MatchState, cards: MatchCards) -> Array[int]:
	var out: Array[int] = []
	for card: int in hand:
		out.append(effective_cost(card, state, cards))
	return out


## Whether `card` carries a Memory that is not empty (the grown mark, cycle 8 R7).
static func is_grown(card: int, state: MatchState) -> bool:
	var kept: CardMemory = state.memory_of(card)
	return kept != null and not kept.is_empty()


## The uses `card`'s first limited ability has left, as a view shows them: -1 when none of
## its abilities is limited, the ability's `uses` until the Memory has read them, then the
## Memory's `uses_left`.
static func uses_left(card: int, state: MatchState, cards: MatchCards) -> int:
	var def: CardDef = cards.def_of(card) if cards != null else null
	if def == null:
		return -1
	for ability: CardAbility in def.abilities:
		if ability.uses <= 0:
			continue
		var kept: CardMemory = state.memory_of(card)
		if kept == null or kept.uses_left < 0:
			return ability.uses
		return kept.uses_left
	return -1


## The Ongoing abilities with verb `verb` that `seat`'s revealed row cards make apply now,
## in slot order. A Squelched card's Ongoing is not read (reads_ongoing()).
static func ongoing_on_row(
	state: MatchState, cards: MatchCards, seat: int, verb: String
) -> Array[CardAbility]:
	var out: Array[CardAbility] = []
	if cards == null or seat < 0 or seat >= state.seats.size():
		return out
	var piles: MatchState.SeatPiles = state.seats[seat]
	for card: int in piles.board:
		if not piles.is_revealed(card) or not reads_ongoing(state, card):
			continue
		var def: CardDef = cards.def_of(card)
		if def == null:
			continue
		for ability: CardAbility in def.abilities:
			if ability.moment == MOMENT_ONGOING and ability.verb == verb:
				out.append(ability)
	return out


## Whether `card`'s Ongoing abilities are read now (R33): not while it is Squelched (or
## Silenced, which holds the Squelched half), Statuses.
static func reads_ongoing(state: MatchState, card: int) -> bool:
	return not Statuses.has(state, card, Statuses.SQUELCHED)


## Fills `out` from the printed Power and Bonus of `def`, the Mult grown by `kept`.
static func _read_printed(out: Stats, def: CardDef, kept: CardMemory) -> void:
	out.power = def.power
	var add: int = def.printed_add()
	if kept != null:
		add += kept.add_steps
	if add != 0:
		out.adds.append(add)
	var has_mult: bool = def.bonus_kind == CardDef.BonusKind.MULT
	if kept != null and (has_mult or kept.grows_mult()):
		var grown: int = grown_mult(
			def.printed_mult(), kept.mult_add_steps, kept.mult_times_steps, kept.mult_cap
		)
		out.mults.append(grown)
	elif has_mult:
		out.mults.append(def.printed_mult())


## Fills `out` from a CardState.copied_base {power, adds, mults}.
static func _read_copied_base(out: Stats, base: Dictionary) -> void:
	var power: int = base.get("power", 0)
	out.power = power
	var adds: Array = base.get("adds", [])
	var mults: Array = base.get("mults", [])
	out.adds.assign(adds)
	out.mults.assign(mults)


static func _capped(value: int, cap: int) -> int:
	if cap > 0:
		return mini(value, cap)
	return value


## A card's effective stats (stats()): `power` in whole units, `adds` and `mults` in
## hundredths in the order they apply.
class Stats:
	extends RefCounted

	var power: int = 0
	var adds: Array[int] = []
	var mults: Array[int] = []

	## The summed Adds in hundredths (0 for none): what a face shows as "+0.50".
	func add() -> int:
		var total: int = 0
		for value: int in adds:
			total += value
		return total

	## The product of the Mults in hundredths (100 for none): what a face shows as "×1.25".
	func mult() -> int:
		return Scoring.mult_product(mults)

	## The card's Bonus value in ten-thousandths (Scoring.bonus_value).
	func bonus_value() -> int:
		return Scoring.bonus_value(adds, mults)

	## The stats as plain data: {power, mult, add}, the view's and CARD_REVEALED's keys.
	func to_dict() -> Dictionary:
		return {"power": power, "mult": mult(), "add": add()}
