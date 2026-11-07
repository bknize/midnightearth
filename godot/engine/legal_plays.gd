class_name LegalPlays
extends RefCounted
## Legal card sets for a turn (R5, R13, R26, R36; Phase 3 R5; cycle 9 R8, R9, R13, R14).
##
## A card set is legal when every card is in the hand, no card appears twice, and the
## total cost is at most the energy given (enumeration) or the seat's budget with the
## free first card (validate, R9, R10).
##
## Two families (cycle 8 R4, R21, plan P3). The `_with` functions (enumerate_masks_with,
## validate_with, commit_cost_with) take the costs as an array parallel to the cards: the
## engine and the random bot pass effective costs (Scoring.effective_cost, the view's
## `own_hand_costs`), so a card whose cost an ability reduced is priced as the engine
## accepts it. The printed-cost functions (cost_of, total_cost, enumerate_masks, enumerate,
## validate, commit_cost) read the definition's cost from MatchCards by instance id
## (MatchCards.def_of: origin * DECK_SIZE + index into the origin's deck, DC-07 P3). They
## are the `_with` functions over printed costs, so both families agree whenever no cost is
## reduced.
##
## Enumeration order is deterministic and part of the contract (the bot's seeded
## tie-break depends on it): subsets are listed by ascending bitmask over the hand's
## order, where bit i stands for hand[i], and each subset keeps the hand's order. So the
## empty set (mask 0) always comes first, then {hand[0]}, {hand[1]}, {hand[0], hand[1]},
## {hand[2]}, and so on. Under rules 7 (DC-13 T03) a hand at its Commit holds its Hand size
## plus the Turn's draws, so a few cards (the discard-down brings it back after each Commit).
##
## The discard-down (cycle 9 R13, R14, plan P12): excess() is the number of cards a hand
## must Discard after its Commit, and set_size_ok() checks a set answer's size against a
## prompt's `exact` and `min` (Choice.is_valid_set).
##
## Nothing here prints, asserts or pushes an error; failures are EngineError codes. Static
## and pure.


## The cost of one card instance, or -1 when the id maps to no definition.
static func cost_of(instance_id: int, cards: MatchCards) -> int:
	if instance_id < 0:
		return -1
	var def: CardDef = cards.def_of(instance_id)
	if def == null:
		return -1
	return def.cost


## The summed cost of a card list, or -1 when any card maps to no definition.
static func total_cost(card_ids: Array[int], cards: MatchCards) -> int:
	var total: int = 0
	for instance_id: int in card_ids:
		var cost: int = cost_of(instance_id, cards)
		if cost < 0:
			return -1
		total += cost
	return total


## Bitmasks over the hand's order of every legal subset, ascending. Mask 0 (the empty
## set, a pass) is always included, even if energy is negative. A subset containing a
## card with no definition is never legal.
static func enumerate_masks(hand: Array[int], energy: int, cards: MatchCards) -> Array[int]:
	return enumerate_masks_with(hand, def_costs(hand, cards), energy)


## The definition (printed) cost of each card of `card_ids`, in order (cost_of; -1 for an
## unpriced one).
static func def_costs(card_ids: Array[int], cards: MatchCards) -> Array[int]:
	var out: Array[int] = []
	for instance_id: int in card_ids:
		out.append(cost_of(instance_id, cards))
	return out


## enumerate_masks() over `costs`, parallel to `hand` (cycle 8 P3): a negative cost marks an
## unpriced card, never legal; a cost missing from a short array counts as unpriced.
static func enumerate_masks_with(hand: Array[int], costs: Array[int], energy: int) -> Array[int]:
	var out: Array[int] = [0]
	var subset_count: int = 1 << hand.size()
	for mask: int in range(1, subset_count):
		var total: int = 0
		var priced: bool = true
		for i: int in range(hand.size()):
			if (mask & (1 << i)) == 0:
				continue
			if i >= costs.size() or costs[i] < 0:
				priced = false
				break
			total += costs[i]
		if priced and total <= energy:
			out.append(mask)
	return out


## The cards a mask selects, in the hand's order.
static func subset(hand: Array[int], mask: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(hand.size()):
		if (mask & (1 << i)) != 0:
			out.append(hand[i])
	return out


## Every legal subset (each an Array[int] in the hand's order), in enumerate_masks order.
static func enumerate(hand: Array[int], energy: int, cards: MatchCards) -> Array[Array]:
	var out: Array[Array] = []
	for mask: int in enumerate_masks(hand, energy, cards):
		out.append(subset(hand, mask))
	return out


## Checks a proposed commit; returns EngineError.Code.NONE when legal.
##
## Cards are checked in the order given: the first card already seen returns
## DUPLICATE_CARD, the first card absent from the hand returns CARD_NOT_IN_HAND. Then
## the slots (R5, R6, plan P1) return BAD_SLOTS unless there is exactly one per card,
## strictly increasing, each within 0 .. row_size + proposal.size() - 1. Then a card with
## no definition returns CARD_DATA_INVALID, and a cost above `budget` returns OVER_BUDGET.
## The cost is the summed cost, less the cost of the leftmost new card (the lowest slot,
## which is proposal[0] once the slots pass) when `free_first` is true (R10). The empty
## commit with no slots is always legal.
##
## `slots` here are explicit: the engine resolves the empty, append-at-the-end
## compatibility default (EngineAction) with append_slots() before calling this.
static func validate(
	proposal: Array[int],
	slots: Array[int],
	hand: Array[int],
	row_size: int,
	budget: int,
	free_first: bool,
	cards: MatchCards
) -> int:
	return validate_with(
		proposal, slots, hand, def_costs(hand, cards), row_size, budget, free_first
	)


## validate() with the hand's costs given by `costs`, parallel to `hand` (cycle 8 P3): the
## engine passes effective costs, so a budget-2 commit of a card printed at 3 and reduced
## by 1 is legal. Same order of checks and codes as validate().
static func validate_with(
	proposal: Array[int],
	slots: Array[int],
	hand: Array[int],
	costs: Array[int],
	row_size: int,
	budget: int,
	free_first: bool
) -> int:
	var seen: Dictionary[int, bool] = {}
	for instance_id: int in proposal:
		if seen.has(instance_id):
			return EngineError.Code.DUPLICATE_CARD
		seen[instance_id] = true
		if not hand.has(instance_id):
			return EngineError.Code.CARD_NOT_IN_HAND
	if not slots_valid(slots, proposal.size(), row_size):
		return EngineError.Code.BAD_SLOTS
	if proposal.is_empty():
		return EngineError.Code.NONE
	var total: int = commit_cost_with(proposal, costs_in_hand(proposal, hand, costs), free_first)
	if total < 0:
		return EngineError.Code.CARD_DATA_INVALID
	if total > budget:
		return EngineError.Code.OVER_BUDGET
	return EngineError.Code.NONE


## True when `slots` holds one final-row index per committed card (`count`), strictly
## increasing, each within 0 .. row_size + count - 1 (plan P1).
static func slots_valid(slots: Array[int], count: int, row_size: int) -> bool:
	if slots.size() != count:
		return false
	var last_slot: int = row_size + count - 1
	var previous: int = -1
	for slot: int in slots:
		if slot <= previous or slot > last_slot:
			return false
		previous = slot
	return true


## The slots that append `count` cards at the right end of a row of `row_size` cards:
## row_size .. row_size + count - 1. The engine's resolution of the empty-slots default.
static func append_slots(row_size: int, count: int) -> Array[int]:
	var out: Array[int] = []
	for offset: int in range(count):
		out.append(row_size + offset)
	return out


## What a commit of `proposal` (in slot order) costs: the summed cost, less the leftmost
## card's when `free_first` is true (R10). -1 when any card maps to no definition.
static func commit_cost(proposal: Array[int], free_first: bool, cards: MatchCards) -> int:
	return commit_cost_with(proposal, def_costs(proposal, cards), free_first)


## commit_cost() over `proposal_costs`, parallel to `proposal` (cycle 8 P3): the summed cost,
## less the first card's when `free_first` is true. -1 when any cost is negative (an
## unpriced card) or missing.
static func commit_cost_with(
	proposal: Array[int], proposal_costs: Array[int], free_first: bool
) -> int:
	if proposal_costs.size() < proposal.size():
		return -1
	var total: int = 0
	for i: int in range(proposal.size()):
		if proposal_costs[i] < 0:
			return -1
		total += proposal_costs[i]
	if proposal.is_empty() or not free_first:
		return total
	return total - proposal_costs[0]


## The costs of `picked` read from `costs`, parallel to `hand` (cycle 8 P3): each card's
## entry at its hand position, -1 for a card not in the hand or with no entry.
static func costs_in_hand(picked: Array[int], hand: Array[int], costs: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for card: int in picked:
		var at: int = hand.find(card)
		out.append(costs[at] if at >= 0 and at < costs.size() else -1)
	return out


## The cards a hand of `hand_count` must Discard down to `hand_size` (R13): the excess, 0
## when it is within the Hand size.
static func excess(hand_count: int, hand_size: int) -> int:
	return maxi(hand_count - hand_size, 0)


## Whether a set of `count` cards answers a multi-select whose `exact` and `min` are given
## (plan P12): exactly `exact` when it is 0 or more (Choice.ANY_SIZE is -1), and at least
## `min_count`.
static func set_size_ok(count: int, exact: int, min_count: int) -> bool:
	if exact >= 0 and count != exact:
		return false
	return count >= min_count
