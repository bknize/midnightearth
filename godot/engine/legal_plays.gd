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
## plus the Turn's draws and any created cards (Dross), so it can pass 12 cards; the
## discard-down brings it back after each Commit, and a hand above ENUMERATE_MAX is counted
## rather than enumerated (below).
##
## The discard-down (cycle 9 R13, R14, plan P12): excess() is the number of cards a hand
## must Discard after its Commit, and set_size_ok() checks a set answer's size against a
## prompt's `exact`, `min` and `max` (Choice.is_valid_set).
##
## Above ENUMERATE_MAX cards, enumeration is replaced by counting and unranking
## (set_counts(), DC-14 T17).
##
## Nothing here prints, asserts or pushes an error; failures are EngineError codes. Static
## and pure.


## The most hand cards enumerate_masks_with() is asked to walk (2^n masks): a larger hand is
## counted and unranked instead (lead_order() .. unrank_set(), DC-14 T17).
const ENUMERATE_MAX: int = 12


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


## Counting and unranking (DC-14 T17): a hand of more than ENUMERATE_MAX cards is not walked
## mask by mask (2^n, seconds for a 16-card hand). lead_order() lists its priced cards by
## cost, highest first (ties by hand position); set_counts() tabulates, from each position of
## that order on, how many subsets fit each budget 0 .. `budget`; count_sets() and
## unrank_set() read the table, so the random bot draws one legal set uniformly in
## O(n * budget). Under the free first card a set is legal when its cost less its costliest
## card fits (that card is committed first), so each non-empty set is counted once under its
## lead, its first card in lead_order(), with the rest drawn from after the lead.
static func lead_order(costs: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for index: int in range(costs.size()):
		if costs[index] < 0:
			continue
		var at: int = out.size()
		while at > 0 and costs[out[at - 1]] < costs[index]:
			at -= 1
		if out.insert(at, index) != OK:
			out.append(index)
	return out


## The summed cost of the priced cards of `costs` (unpriced ones, below 0, left out).
static func priced_total(costs: Array[int]) -> int:
	var total: int = 0
	for cost: int in costs:
		if cost > 0:
			total += cost
	return total


## How many subsets of the cards order[k ..] (costs by hand position in `costs`) have a
## summed cost of at most b, for k in 0 .. order.size() and b in 0 .. `budget`: one flat
## list, entry k * (budget + 1) + b (count_at()). The last row is all ones (the empty set).
## Empty when `budget` is negative.
static func set_counts(costs: Array[int], order: Array[int], budget: int) -> Array[int]:
	var width: int = budget + 1
	var rows: int = order.size() + 1
	var out: Array[int] = []
	if width <= 0:
		return out
	out.assign(range(rows * width))
	for b: int in range(width):
		out[order.size() * width + b] = 1
	for k: int in range(order.size() - 1, -1, -1):
		var cost: int = costs[order[k]]
		for b: int in range(width):
			var count: int = out[(k + 1) * width + b]
			if cost <= b:
				count += out[(k + 1) * width + b - cost]
			out[k * width + b] = count
	return out


## The entry of set_counts() for row `k` and budget `b` (its table built for `budget`).
static func count_at(table: Array[int], budget: int, k: int, b: int) -> int:
	return table[k * (budget + 1) + b]


## How many legal sets (the empty one included) `table` (set_counts over `order`, `budget`)
## holds: every subset within the budget, or under `free_first` the empty set plus, per lead,
## the subsets of the cards after it within the budget. 1 when `budget` is negative.
static func count_sets(
	order: Array[int], table: Array[int], budget: int, free_first: bool
) -> int:
	if budget < 0 or table.is_empty():
		return 1
	if not free_first:
		return count_at(table, budget, 0, budget)
	var total: int = 1
	for lead: int in range(order.size()):
		total += count_at(table, budget, lead + 1, budget)
	return total


## The legal set of rank `rank` (0 .. count_sets() - 1) as hand positions: under
## `free_first` its lead first, then the rest in lead_order(); rank 0 under `free_first`, or
## any rank with a negative budget, is the empty set. Each rank gives a different set, so a
## uniform rank is a uniform set.
static func unrank_set(
	costs: Array[int],
	order: Array[int],
	table: Array[int],
	budget: int,
	free_first: bool,
	rank: int
) -> Array[int]:
	var out: Array[int] = []
	if budget < 0 or table.is_empty():
		return out
	var left_rank: int = rank
	var start: int = 0
	if free_first:
		if left_rank <= 0:
			return out
		left_rank -= 1
		var lead: int = -1
		for at: int in range(order.size()):
			var under: int = count_at(table, budget, at + 1, budget)
			if left_rank < under:
				lead = at
				break
			left_rank -= under
		if lead < 0:
			return out
		out.append(order[lead])
		start = lead + 1
	var room: int = budget
	for k: int in range(start, order.size()):
		var skip: int = count_at(table, budget, k + 1, room)
		if left_rank < skip:
			continue
		left_rank -= skip
		out.append(order[k])
		room -= costs[order[k]]
		if room < 0:
			break
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


## Whether a set of `count` cards answers a multi-select whose `exact`, `min` and `max` are
## given (plan P12): exactly `exact` when it is 0 or more (Choice.ANY_SIZE is -1), at least
## `min_count`, and at most `max_count` when it is 0 or more (Choice.NO_MAX is -1; "up to N",
## C15 2a).
static func set_size_ok(count: int, exact: int, min_count: int, max_count: int = -1) -> bool:
	if exact >= 0 and count != exact:
		return false
	if max_count >= 0 and count > max_count:
		return false
	return count >= min_count
