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
## Prompts: a multi-select prompt keeps each option on a coin flip, so each of its 2^n
## subsets (the empty decline among them) is equally likely; a single-target prompt picks
## one of its options by pick_index, or the decline as one more equally likely answer when
## the prompt is optional. Both draw from decision_rng(view, PROMPT_TAG, [the prompt's
## source card]).
##
## R2: the bot reads only its own SeatView and its seed; it never asks the engine anything.
## R3: every commit is one of the enumerated legal candidates and every answer uses only
## the prompt's offered options (or the decline it allows), so the engine accepts it.

## Separates the commit draw ("rnd" in ASCII).
const COMMIT_TAG: int = 0x726E64
## Separates a prompt answer's draw from the commit's ("rna").
const PROMPT_TAG: int = 0x726E61


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
			var order_costs: Array[int] = LegalPlays.costs_in_hand(ordered, view.own_hand, costs)
			if LegalPlays.commit_cost_with(ordered, order_costs, view.free_first) <= view.energy:
				_add_ends(out, view.seat, ordered, row_size)
	return out


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


## A uniform answer to the prompt open for `view.seat`: a uniform subset of a multi-select
## prompt's options (ascending position); else one uniform option, the decline counted as
## one more when the prompt is optional (-1 with nothing offered and no decline).
func _answer(view: SeatView) -> EngineAction:
	var zone: int = view.prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var options: Array[int] = Choice.options_of(view.prompt)
	var source: int = view.prompt.get("card", -1)
	var extra: Array[int] = [source]
	var rng: MatchRng = decision_rng(view, PROMPT_TAG, extra)
	if Choice.is_multi_prompt(view.prompt):
		var kept: Array[int] = []
		for option: int in options:
			if rng.coin_flip() == 1:
				kept.append(option)
		kept.sort()
		return EngineAction.choose_set(view.seat, zone, kept)
	var answers: int = options.size()
	if Choice.is_optional_prompt(view.prompt):
		answers += 1
	if answers == 0:
		return EngineAction.choose(view.seat, zone, -1)
	var pick: int = rng.pick_index(answers)
	if pick >= options.size():
		return EngineAction.decline(view.seat)
	return EngineAction.choose(view.seat, zone, options[pick])
