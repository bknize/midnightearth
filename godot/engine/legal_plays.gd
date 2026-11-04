class_name LegalPlays
extends RefCounted
## Legal card sets for a turn (R5, R13, R26, R36; Phase 3 R5).
##
## A card set is legal when every card is in the hand, no card appears twice, and the
## total cost is at most the energy given (enumeration) or the seat's budget with the
## free first card (validate, R9, R10). Costs come from CardDb by instance id:
## instance id = seat * DECK_SIZE + index, so the definition is card_at(id % DECK_SIZE).
##
## Enumeration order is deterministic and part of the contract (the bot's seeded
## tie-break depends on it): subsets are listed by ascending bitmask over the hand's
## order, where bit i stands for hand[i], and each subset keeps the hand's order. So the
## empty set (mask 0) always comes first, then {hand[0]}, {hand[1]}, {hand[0], hand[1]},
## {hand[2]}, and so on. A hand holds at most HAND_CAP = 7 cards, so at most 128 subsets.
##
## Nothing here prints, asserts or pushes an error; failures are EngineError codes.


## The cost of one card instance, or -1 when the id maps to no definition.
static func cost_of(instance_id: int, cards: CardDb) -> int:
	if instance_id < 0:
		return -1
	var def: CardDef = cards.card_at(instance_id % MatchRules.DECK_SIZE)
	if def == null:
		return -1
	return def.cost


## The summed cost of a card list, or -1 when any card maps to no definition.
static func total_cost(card_ids: Array[int], cards: CardDb) -> int:
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
static func enumerate_masks(hand: Array[int], energy: int, cards: CardDb) -> Array[int]:
	var costs: Array[int] = []
	for instance_id: int in hand:
		costs.append(cost_of(instance_id, cards))
	var out: Array[int] = [0]
	var subset_count: int = 1 << hand.size()
	for mask: int in range(1, subset_count):
		var total: int = 0
		var priced: bool = true
		for i: int in range(costs.size()):
			if (mask & (1 << i)) == 0:
				continue
			if costs[i] < 0:
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
static func enumerate(hand: Array[int], energy: int, cards: CardDb) -> Array[Array]:
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
	cards: CardDb
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
	var total: int = commit_cost(proposal, free_first, cards)
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
static func commit_cost(proposal: Array[int], free_first: bool, cards: CardDb) -> int:
	var total: int = total_cost(proposal, cards)
	if total < 0 or proposal.is_empty() or not free_first:
		return total
	return total - cost_of(proposal[0], cards)
