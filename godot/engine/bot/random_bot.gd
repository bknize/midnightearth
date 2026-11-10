class_name RandomBot
extends BotPlayer
## The random bot (cycle 7 R20; cycle 9 R70, P16): the engine's one bot. It chooses
## uniformly, with its per-decision seed, among the legal candidate commits and among a
## prompt's legal answers.
##
## Commits: one pick_index over candidates_for(view, cards), drawn from
## decision_rng(view, COMMIT_TAG). The candidates are every legal set of the view's hand
## within its budget (LegalPlays.enumerate_masks_with over the view's effective costs,
## ascending bitmask), each in the hand's order at the row's left end and, for a non-empty
## row, its right end. While the free first card is granted the sets are enumerated up to
## the budget plus the hand's highest cost, the costliest-first order is listed too when it
## differs, and an order is kept only when LegalPlays.commit_cost_with() of it fits the
## budget, so every set the discount makes affordable has a candidate and none costs more
## than the engine accepts.
##
## A hand of more than LegalPlays.ENUMERATE_MAX cards (DC-14 T17: 20 cards with Dross) is not
## enumerated (2^n masks): large_hand_commit() counts its legal sets over the view's
## effective costs and the free first card (LegalPlays.set_counts, O(n * budget)), draws one
## uniformly by rank, commits it costliest first under the free first card (else in hand
## order) and draws its slots uniformly among every valid placement. Hands of 12 or fewer keep
## the enumeration above, unchanged.
##
## Prompts (cycle 9 R70, P16), every v2 shape: a multi-select prompt with an `exact` size
## (the discard-down, DC-13 T03) gets a uniform set of exactly that many options; an
## any-size one keeps each option on a coin flip, redrawn while the set falls short of its
## `min` (at most SET_TRIES draws), so each of its subsets of at least `min` is equally
## likely; a single-target prompt picks one of its options by pick_index, or the decline as
## one more equally likely answer when the prompt is optional. An "up to N" set (a `max`,
## Exhume, C15 2a) is uniform over every subset of `min` to `max` options. Both draw from
## decision_rng(view, PROMPT_TAG, [the prompt's source card]).
##
## R2: the bot reads only its own SeatView and its seed; it never asks the engine anything.
## R3: every commit is one of the enumerated legal candidates and every answer uses only
## the prompt's offered options (or the decline it allows), so the engine accepts it.

## Separates the commit draw ("rnd" in ASCII).
const COMMIT_TAG: int = 0x726E64
## Separates a prompt answer's draw from the commit's ("rna").
const PROMPT_TAG: int = 0x726E61
## The coin-flip draws an any-size set gets to reach its `min` before it is topped up from
## the front (a `min` above half the options rarely needs more than a few).
const SET_TRIES: int = 64
## The largest count one pick_index draw covers (the generator draws 32-bit values); a larger
## count is drawn from two such draws (draw_below).
const DRAW_CHUNK: int = 1 << 30


func _init(bot_seed: int, cards: MatchCards) -> void:
	super(bot_seed, cards)


## The registry name (BotRegistry.NAMES).
func bot_name() -> String:
	return "random"


## The action for `view.seat`: a uniform answer while a prompt is open for that seat,
## otherwise a uniform legal commit. `_engine` is not read.
func choose(view: SeatView, _engine: MatchEngine) -> EngineAction:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	if open and asked == view.seat:
		return _answer(view)
	if view.own_hand.size() > LegalPlays.ENUMERATE_MAX:
		return large_hand_commit(view, _cards, decision_rng(view, COMMIT_TAG))
	var listed: Array[EngineAction] = candidates_for(view, _cards)
	if listed.is_empty():
		var none: Array[int] = []
		return EngineAction.commit(view.seat, none, none)
	var rng: MatchRng = decision_rng(view, COMMIT_TAG)
	return listed[rng.pick_index(listed.size())]


## Every candidate commit for `view` over `cards` (see the class comment), in order: legal
## sets by ascending bitmask; per set the hand order, then (with the free first card) the
## costliest-first order when it differs; per order the left end, then the right end when
## the row is not empty. The empty set is one candidate with no slots.
static func candidates_for(view: SeatView, cards: MatchCards) -> Array[EngineAction]:
	var out: Array[EngineAction] = []
	var row_size: int = view.own_board.size()
	var costs: Array[int] = hand_costs(view, cards)
	var cap: int = view.energy
	if view.free_first:
		cap += _highest(costs)
	for mask: int in LegalPlays.enumerate_masks_with(view.own_hand, costs, cap):
		var picked: Array[int] = LegalPlays.subset(view.own_hand, mask)
		if picked.is_empty():
			var none: Array[int] = []
			out.append(EngineAction.commit(view.seat, picked, none))
			continue
		var orders: Array[Array] = [picked]
		if view.free_first:
			var costly: Array[int] = _costliest_first(picked, view.own_hand, costs)
			if costly != picked:
				orders.append(costly)
		for order: Array in orders:
			var ordered: Array[int] = []
			ordered.assign(order)
			# Without the free first card the mask already fits the budget (cap is energy).
			if not view.free_first or _fits_free_first(ordered, view, costs):
				_add_ends(out, view.seat, ordered, row_size)
	return out


## A uniform legal commit for a hand too large to enumerate (see the class comment): one
## rank below LegalPlays.count_sets() drawn from `rng`, unranked to a set, then a uniform set
## of `count` distinct slots in 0 .. row size + count - 1 (ascending, so the set's first card
## takes the leftmost). Bounded by the hand size times the budget.
static func large_hand_commit(view: SeatView, cards: MatchCards, rng: MatchRng) -> EngineAction:
	var costs: Array[int] = hand_costs(view, cards)
	var order: Array[int] = LegalPlays.lead_order(costs)
	var budget: int = mini(view.energy, LegalPlays.priced_total(costs))
	var table: Array[int] = LegalPlays.set_counts(costs, order, budget)
	var count: int = LegalPlays.count_sets(order, table, budget, view.free_first)
	var rank: int = draw_below(rng, count)
	var at_hand: Array[int] = LegalPlays.unrank_set(
		costs, order, table, budget, view.free_first, rank
	)
	var picked: Array[int] = []
	var none: Array[int] = []
	if at_hand.is_empty():
		return EngineAction.commit(view.seat, picked, none)
	var rest: Array[int] = []
	rest.assign(at_hand)
	if view.free_first:
		picked.append(view.own_hand[rest[0]])
		rest.remove_at(0)
	rest.sort()
	for index: int in rest:
		picked.append(view.own_hand[index])
	var slots: Array[int] = uniform_slots(view.own_board.size(), picked.size(), rng)
	return EngineAction.commit(view.seat, picked, slots)


## `count` distinct slots of 0 .. row_size + count - 1, uniform over every such set (a
## partial Fisher-Yates), ascending.
static func uniform_slots(row_size: int, count: int, rng: MatchRng) -> Array[int]:
	return _draw_distinct(LegalPlays.append_slots(0, row_size + count), count, rng)


## A value in 0 .. count - 1 from `rng` (0 when count < 1): uniform from one pick_index up
## to DRAW_CHUNK; above it (a hand of more than 30 priced cards) two draws combined and
## reduced modulo `count`, near enough uniform.
static func draw_below(rng: MatchRng, count: int) -> int:
	if count <= DRAW_CHUNK:
		return rng.pick_index(count)
	var high: int = rng.pick_index(DRAW_CHUNK)
	var low: int = rng.pick_index(DRAW_CHUNK)
	return (high * DRAW_CHUNK + low) % count


## The costs of `view.own_hand`, parallel to it: the view's effective `own_hand_costs` when
## it carries one per hand card, else each card's definition cost over `cards`. With no
## usable `cards` every card is unpriced (-1), so the only candidate is the empty set.
static func hand_costs(view: SeatView, cards: MatchCards) -> Array[int]:
	if cards == null or not cards.is_valid() or cards.size() == 0:
		var unpriced: Array[int] = []
		for _card: int in view.own_hand:
			unpriced.append(-1)
		return unpriced
	if view.own_hand_costs.size() == view.own_hand.size():
		var given: Array[int] = []
		given.assign(view.own_hand_costs)
		return given
	return LegalPlays.def_costs(view.own_hand, cards)


## A set answer over `options` drawn from `rng`, in ascending position: with `exact` 0 or
## more, a uniform set of exactly that many (a partial Fisher-Yates over a copy, each draw
## one pick_index); with Choice.ANY_SIZE, each option kept on a coin flip, redrawn until
## the set holds at least `min_count` (rejection, so every such subset is equally likely);
## after SET_TRIES short draws the last one is topped up from the front to `min_count`. With
## a `max_count` of 0 or more ("up to N", C15 2a) and no `exact`, a size from `min_count` to
## `max_count` is drawn weighted by how many sets have it, then a uniform set of that size, so
## every such set is equally likely (bounded_set()).
static func set_answer(
	options: Array[int], exact: int, min_count: int, rng: MatchRng, max_count: int = Choice.NO_MAX
) -> Array[int]:
	var kept: Array[int] = []
	if exact < 0 and max_count >= 0:
		return bounded_set(options, min_count, max_count, rng)
	if exact >= 0:
		return _draw_distinct(options, exact, rng)
	for _try: int in range(SET_TRIES):
		kept.clear()
		for option: int in options:
			if rng.coin_flip() == 1:
				kept.append(option)
		if kept.size() >= min_count:
			kept.sort()
			return kept
	for option: int in options:
		if kept.size() >= min_count:
			break
		if not kept.has(option):
			kept.append(option)
	kept.sort()
	return kept


## A uniform set of `options` of `min_count` to `max_count` cards (clamped to the options),
## ascending: the size k drawn with weight C(n, k), then k options by partial Fisher-Yates.
static func bounded_set(
	options: Array[int], min_count: int, max_count: int, rng: MatchRng
) -> Array[int]:
	var n: int = options.size()
	var low: int = clampi(min_count, 0, n)
	var high: int = clampi(max_count, low, n)
	var weights: Array[int] = []
	var total: int = 0
	var ways: int = 1
	for size: int in range(high + 1):
		if size > 0:
			@warning_ignore("integer_division")
			var grown: int = ways * (n - size + 1) / size
			ways = grown
		if size >= low:
			weights.append(ways)
			total += ways
	var roll: int = draw_below(rng, total)
	var size_drawn: int = low
	for weight: int in weights:
		if roll < weight:
			break
		roll -= weight
		size_drawn += 1
	return _draw_distinct(options, size_drawn, rng)


## `count` distinct entries of `options` (at most all of them), uniform over every such set:
## a partial Fisher-Yates over a copy, one pick_index per entry, returned ascending.
static func _draw_distinct(options: Array[int], count: int, rng: MatchRng) -> Array[int]:
	var pool: Array[int] = []
	pool.assign(options)
	var kept: Array[int] = []
	for _pick: int in range(mini(count, pool.size())):
		var at: int = rng.pick_index(pool.size())
		kept.append(pool[at])
		pool.remove_at(at)
	kept.sort()
	return kept


## Whether `ordered` (costs by hand position in `costs`) fits `view`'s budget with its first
## card free (LegalPlays.commit_cost_with, as the engine prices it).
static func _fits_free_first(ordered: Array[int], view: SeatView, costs: Array[int]) -> bool:
	var order_costs: Array[int] = LegalPlays.costs_in_hand(ordered, view.own_hand, costs)
	return LegalPlays.commit_cost_with(ordered, order_costs, true) <= view.energy


## The highest of `costs` (0 when empty or all unpriced).
static func _highest(costs: Array[int]) -> int:
	var highest: int = 0
	for cost: int in costs:
		highest = maxi(highest, cost)
	return highest


## `picked` with its costliest card (costs parallel to `hand`) moved to the front, the
## first of equals keeping its place, the rest in their order.
static func _costliest_first(
	picked: Array[int], hand: Array[int], costs: Array[int]
) -> Array[int]:
	var prices: Array[int] = LegalPlays.costs_in_hand(picked, hand, costs)
	var best: int = 0
	for index: int in range(picked.size()):
		if prices[index] > prices[best]:
			best = index
	var out: Array[int] = [picked[best]]
	for index: int in range(picked.size()):
		if index != best:
			out.append(picked[index])
	return out


## Appends `cards` committed at the left end and, for a non-empty row, the right end.
static func _add_ends(
	out: Array[EngineAction], seat: int, cards: Array[int], row_size: int
) -> void:
	var count: int = cards.size()
	out.append(EngineAction.commit(seat, cards, LegalPlays.append_slots(0, count)))
	if row_size > 0:
		out.append(EngineAction.commit(seat, cards, LegalPlays.append_slots(row_size, count)))


## A uniform answer to the prompt open for `view.seat`: for a multi-select, a uniform set of
## exactly its `exact` options (the discard-down's excess, R70) or, with no `exact`, a
## uniform subset of at least its `min` and at most its `max` when it has one (ascending
## position, set_answer()); else one
## uniform option, the decline counted as one more when the prompt is optional (the
## decline, which the engine accepts, with nothing offered and no decline).
func _answer(view: SeatView) -> EngineAction:
	var zone: int = Choice.zone_of(view.prompt)
	var options: Array[int] = Choice.options_of(view.prompt)
	var source: int = view.prompt.get("card", -1)
	var extra: Array[int] = [source]
	var rng: MatchRng = decision_rng(view, PROMPT_TAG, extra)
	if Choice.is_multi_prompt(view.prompt):
		var kept: Array[int] = set_answer(
			options,
			Choice.exact_of(view.prompt),
			Choice.min_of(view.prompt),
			rng,
			Choice.max_of(view.prompt)
		)
		return EngineAction.choose_set(view.seat, zone, kept)
	var answers: int = options.size()
	if Choice.is_optional_prompt(view.prompt):
		answers += 1
	if answers == 0:
		# Nothing offered and no decline: the engine takes the decline (B-22). No RNG
		# draw here, as before, so every other answer is unchanged.
		return EngineAction.decline(view.seat)
	var pick: int = rng.pick_index(answers)
	if pick >= options.size():
		return EngineAction.decline(view.seat)
	return EngineAction.choose(view.seat, zone, options[pick])
