class_name GreedyBot
extends RefCounted
## The greedy bot (R35-R38, C8, plan P13; Phase 3 R7): a pure decision function over one
## seat's redacted SeatView, its own seed and the engine's pure previews.
##
## Commits (R36): for each legal set of the view's hand and budget (LegalPlays, ascending
## bitmask order) the bot lists up to four candidates: the set in two orders (bonus desc
## then flat desc; flat desc then bonus desc; both then ascending instance id), each at the
## row's left end (slots 0..k-1) or its right end (row_size..row_size+k-1). Identical
## candidates are listed once (both orders equal; the two ends of an empty row), so a
## decision costs at most 128 * 4 = 512 previews and at most 128 * 2 = 256 on an empty row;
## in practice far fewer, since the budget caps the legal sets and most cards have bonus 0,
## which makes both orders equal.
##
## The free first card (R10, DC-05 T07): while the view's `free_first` is true, the
## leftmost card of the commit (the lowest slot, which is cards[0]) costs 0, the rule of
## LegalPlays.validate. Sets are then enumerated up to the budget plus the hand's highest
## cost, a third order is listed (the costliest card first, ties by the bonus-first order,
## then the rest in bonus-first order) when it differs from the other two, and an order is
## kept only if LegalPlays.commit_cost() of it fits the budget. So every set the discount
## makes affordable has a candidate, and none costs more than the engine accepts. With the
## grant a decision costs at most 128 * 6 = 768 previews; it holds for one commit, after a
## c10 reveal. Without the grant the search is exactly the one above.
##
## Each candidate is
## scored by MatchEngine.preview() as own score minus the opponent's; the best wins, and a
## tie is broken by one pick_index from a fresh generator seeded
## MatchRng.derive_seed(bot_seed, [round, turn]).
##
## Prompts (R37): each option of the view's prompt is scored by
## MatchEngine.preview_choice() the same way; a tie is broken with the seed derived from
## [round, turn, PROMPT_TAG, the prompt's source card], distinct from the commit's. A
## multi-select prompt (DC-07 P7, P13) has n + 1 candidate sets for its n options: for each
## k from 0 to n, the k options with the lowest effective flat (ties by lower position),
## listed in ascending position (set_candidates). Each is scored by
## MatchEngine.preview_set() and the best wins, ties by the same prompt seed. No other set
## is previewed, so a sacrifice prompt costs at most n + 1 previews.
##
## Orders (DC-07 P13, R36): "bonus first" is +-part desc, then ×-part desc, then flat desc;
## "flat first" is flat desc, then the bonus (+-part desc, then ×-part desc); both end on
## ascending instance id. The bot ranks a card by what its definition carries (stats_of).
##
## Hidden information (R7, R38): the bot reads only its own SeatView (its hand, budget, row
## size, prompt, round and turn) and asks the engine only for previews of its own seat's
## candidates. A preview returns nothing but two scores, and the engine computes them with
## the opponent's face-down cards scoring nothing (MatchEngine.preview: its face-down commit
## absent, its unrevealed row cards inert in their slots; DC-06 R23), so the scores are
## a function of what the view already shows plus the bot's own cards. The choice therefore
## depends only on the seed and the view, and the bot can learn no hidden card through it.
##
## The bot holds no generator between calls, so the same seed and view (on an engine in the
## state the view was built from) always give the same action (R38). Every candidate is a
## commit the engine has just accepted as a preview (preview() returns [] for one it would
## reject, and such a candidate is dropped), so the engine accepts the returned action. It
## never writes output, halts or reports errors itself.

## Separates bot seeds from any other derivation of the match seed ("bot" in ASCII).
const SEED_TAG: int = 0x626F74
## Separates a prompt decision's seed from the commit decision of the same turn ("ask").
const PROMPT_TAG: int = 0x61736B

## Plan P13's fallback lever: false drops the flat-first order, halving the search, should
## the test stage outgrow its budget (plan, risks). True is the specified search.
var search_flat_first: bool = true

var _bot_seed: int = 0
var _cards: MatchCards = null


## `cards` supplies card stats and costs: the MatchCards of the match the bot plays in
## (MatchEngine.match_cards(), DC-07 P3), so a card is read through its origin's deck.
##
## Null, or a MatchCards whose build failed (is_valid() false), is kept, not reported:
## every card then has cost -1, the only legal set is the empty one, and choose() always
## commits nothing, so a bot built on it passes every turn. The bot does not signal this
## itself, since engine code never reports errors out of band (R27). It cannot happen
## through the engine: the engine never builds a bot, and a match cannot start without
## valid cards and decks (CARD_DATA_INVALID, DECK_UNKNOWN), so callers that pass the
## match's own MatchCards always give the bot valid data.
func _init(bot_seed: int, cards: MatchCards) -> void:
	_bot_seed = bot_seed
	_cards = cards if cards != null else MatchCards.new()


## The seed a caller should give the bot playing `seat` in a match seeded `match_seed`.
static func seed_for(match_seed: int, seat: int) -> int:
	var parts: Array[int] = [SEED_TAG, seat]
	return MatchRng.derive_seed(match_seed, parts)


## The action for `view.seat`: while a prompt is open for that seat, its best answer
## (answer_prompt); otherwise its best commit (best_commit). `engine` is the match the view
## was built from; it is used only for previews of `view.seat`. With a null engine nothing
## can be previewed and every candidate ties, so the seed picks among them.
func choose(view: SeatView, engine: MatchEngine) -> EngineAction:
	var answer: EngineAction = answer_prompt(view, engine)
	if answer != null:
		return answer
	return best_commit(view, engine)


## The best-scoring commit for `view.seat` among candidates(view), ties by the seeded pick.
## The empty commit when no candidate previews (never, for an awaited seat: the empty set
## is always a legal candidate).
func best_commit(view: SeatView, engine: MatchEngine) -> EngineAction:
	var best: Array[EngineAction] = []
	var best_value: int = 0
	for action: EngineAction in candidates(view):
		var scores: Array[int] = _preview_commit(engine, view.seat, action)
		if scores.size() != 2:
			continue
		var value: int = scores[view.seat] - scores[1 - view.seat]
		if best.is_empty() or value > best_value:
			best.clear()
			best_value = value
			best.append(action)
		elif value == best_value:
			best.append(action)
	if best.is_empty():
		var none: Array[int] = []
		return EngineAction.commit(view.seat, none, none)
	var parts: Array[int] = [view.round_number, view.turn]
	var rng: MatchRng = MatchRng.new(MatchRng.derive_seed(_bot_seed, parts))
	return best[rng.pick_index(best.size())]


## The answer to the prompt open for `view.seat`: the option with the best previewed score,
## ties by the seeded pick (R37). Null when no prompt is open for that seat.
func answer_prompt(view: SeatView, engine: MatchEngine) -> EngineAction:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	if not open or asked != view.seat:
		return null
	var options: Array[int] = Choice.options_of(view.prompt)
	var zone: int = view.prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	if Choice.is_multi_prompt(view.prompt):
		return answer_set(view, engine)
	if options.is_empty():
		return EngineAction.choose(view.seat, zone, -1)
	var best: Array[int] = []
	var best_value: int = 0
	for option: int in options:
		var scores: Array[int] = _preview_option(engine, view.seat, option)
		if scores.size() != 2:
			continue
		var value: int = scores[view.seat] - scores[1 - view.seat]
		if best.is_empty() or value > best_value:
			best.clear()
			best_value = value
			best.append(option)
		elif value == best_value:
			best.append(option)
	if best.is_empty():
		return EngineAction.choose(view.seat, zone, options[0])
	var rng: MatchRng = _prompt_rng(view)
	return EngineAction.choose(view.seat, zone, best[rng.pick_index(best.size())])


## The answer to the multi-select prompt open for `view.seat` (DC-07 P13, R37): the
## candidate set of set_candidates() with the best previewed own-minus-opponent score, ties
## by the prompt's seeded pick. The empty set (always a candidate, always valid) when no
## candidate previews; with a null engine every candidate ties and the seed picks one. Null
## when no multi-select prompt is open for that seat.
func answer_set(view: SeatView, engine: MatchEngine) -> EngineAction:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	if not open or asked != view.seat or not Choice.is_multi_prompt(view.prompt):
		return null
	var zone: int = view.prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var best: Array[Array] = []
	var best_value: int = 0
	for listed: Array in set_candidates(view):
		var candidate: Array[int] = []
		candidate.assign(listed)
		var scores: Array[int] = _preview_set(engine, view.seat, candidate)
		if scores.size() != 2:
			continue
		var value: int = scores[view.seat] - scores[1 - view.seat]
		if best.is_empty() or value > best_value:
			best.clear()
			best_value = value
			best.append(candidate)
		elif value == best_value:
			best.append(candidate)
	var chosen: Array[int] = []
	if not best.is_empty():
		var rng: MatchRng = _prompt_rng(view)
		chosen.assign(best[rng.pick_index(best.size())])
	return EngineAction.choose_set(view.seat, zone, chosen)


## The candidate sets for the open multi-select prompt of `view` (DC-07 P13, R37): with n
## options, n + 1 sets, the k-th holding the k options with the lowest effective flat as the
## view shows it (ties by lower position), itself in ascending position. Set 0 is the empty
## set (the decline). Every index is one of the prompt's options, and none repeats. Empty
## when the view has no multi-select prompt for its seat. Each set is an Array[int].
func set_candidates(view: SeatView) -> Array[Array]:
	var out: Array[Array] = []
	var asked: int = view.prompt.get("seat", -1)
	if asked != view.seat or not Choice.is_multi_prompt(view.prompt):
		return out
	var zone: int = view.prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var options: Array[int] = Choice.options_of(view.prompt)
	var flats: Dictionary[int, int] = {}
	for option: int in options:
		flats[option] = _option_flat(view, zone, option)
	var lowest_first: Array[int] = []
	lowest_first.assign(options)
	lowest_first.sort_custom(
		func(a: int, b: int) -> bool: return flats[a] < flats[b] or (flats[a] == flats[b] and a < b)
	)
	for count: int in range(lowest_first.size() + 1):
		var picked: Array[int] = []
		picked.assign(lowest_first.slice(0, count))
		picked.sort()
		out.append(picked)
	return out


## The effective flat the view shows for position `index` of `zone`: a row card's shown
## flat (SeatView.own_row, opponent_row), a hand card's definition flat; 0 for any other
## zone or a position out of range.
func _option_flat(view: SeatView, zone: int, index: int) -> int:
	var row: Array[Dictionary] = []
	if zone == Choice.Zone.OWN_BOARD:
		row = view.own_row
	elif zone == Choice.Zone.OPPONENT_BOARD:
		row = view.opponent_row
	elif zone == Choice.Zone.OWN_HAND and index >= 0 and index < view.own_hand.size():
		return stats_of(view.own_hand[index]).x
	if index < 0 or index >= row.size():
		return 0
	var entry: Dictionary = row[index]
	var flat: int = entry.get("flat", 0)
	return flat


## The generator that breaks a tie between prompt answers: seeded from [round, turn,
## PROMPT_TAG, the prompt's source card], fresh per decision.
func _prompt_rng(view: SeatView) -> MatchRng:
	var source: int = view.prompt.get("card", -1)
	var parts: Array[int] = [view.round_number, view.turn, PROMPT_TAG, source]
	return MatchRng.new(MatchRng.derive_seed(_bot_seed, parts))


## Every candidate commit for the view (see the class comment), in search order: legal sets
## by ascending bitmask; per set the bonus-first order, then the flat-first order when it
## differs, then (with the free first card) the costliest-first order when it differs; per
## order the left end, then the right end when the row is not empty. An order whose
## commit_cost() exceeds the budget is skipped. Each commit carries explicit slots; the
## empty set is one candidate with none.
func candidates(view: SeatView) -> Array[EngineAction]:
	var out: Array[EngineAction] = []
	var row_size: int = view.own_board.size()
	var cap: int = view.energy
	if view.free_first:
		cap += _highest_cost(view.own_hand)
	for mask: int in LegalPlays.enumerate_masks(view.own_hand, cap, _cards):
		var picked: Array[int] = LegalPlays.subset(view.own_hand, mask)
		if picked.is_empty():
			var none: Array[int] = []
			out.append(EngineAction.commit(view.seat, picked, none))
			continue
		var bonus_first: Array[int] = []
		bonus_first.assign(picked)
		bonus_first.sort_custom(_bonus_before)
		var orders: Array[Array] = [bonus_first]
		var flat_first: Array[int] = []
		flat_first.assign(picked)
		flat_first.sort_custom(_flat_before)
		if search_flat_first and flat_first != bonus_first:
			orders.append(flat_first)
		if view.free_first:
			var costly_first: Array[int] = _costliest_first(bonus_first)
			if not orders.has(costly_first):
				orders.append(costly_first)
		for order: Array in orders:
			var cards: Array[int] = []
			cards.assign(order)
			if LegalPlays.commit_cost(cards, view.free_first, _cards) <= view.energy:
				_add_ends(out, view.seat, cards, row_size)
	return out


## The highest cost of any card in `hand` (0 for an empty hand or unpriced cards).
func _highest_cost(hand: Array[int]) -> int:
	var highest: int = 0
	for card: int in hand:
		highest = maxi(highest, LegalPlays.cost_of(card, _cards))
	return highest


## `ordered` with its costliest card moved to the front (the first of equals keeps its
## place), the rest in their order: the order the free first card discounts most.
func _costliest_first(ordered: Array[int]) -> Array[int]:
	var best: int = 0
	for index: int in range(ordered.size()):
		if LegalPlays.cost_of(ordered[index], _cards) > LegalPlays.cost_of(ordered[best], _cards):
			best = index
	var out: Array[int] = []
	if ordered.is_empty():
		return out
	out.append(ordered[best])
	for index: int in range(ordered.size()):
		if index != best:
			out.append(ordered[index])
	return out


## Appends `cards` committed at the left end and, for a non-empty row, the right end.
func _add_ends(out: Array[EngineAction], seat: int, cards: Array[int], row_size: int) -> void:
	var count: int = cards.size()
	out.append(EngineAction.commit(seat, cards, LegalPlays.append_slots(0, count)))
	if row_size > 0:
		out.append(EngineAction.commit(seat, cards, LegalPlays.append_slots(row_size, count)))


## The previewed scores of a commit, [0, 0] with no engine to ask.
func _preview_commit(engine: MatchEngine, seat: int, action: EngineAction) -> Array[int]:
	if engine == null:
		var even: Array[int] = [0, 0]
		return even
	return engine.preview(seat, action)


## The previewed scores of a prompt answer, [0, 0] with no engine to ask.
func _preview_option(engine: MatchEngine, seat: int, option: int) -> Array[int]:
	if engine == null:
		var even: Array[int] = [0, 0]
		return even
	return engine.preview_choice(seat, option)


## The previewed scores of a multi-select answer, [0, 0] with no engine to ask.
func _preview_set(engine: MatchEngine, seat: int, indices: Array[int]) -> Array[int]:
	if engine == null:
		var even: Array[int] = [0, 0]
		return even
	return engine.preview_set(seat, indices)


## The definition's (flat, ×-part, +-part) of a card instance (MatchCards.def_of, through
## its origin's deck; DC-07 P1): the ×-part in hundredths (MULT_ONE when the card has no
## ×-bonus), the +-part in whole units (0 when it has no +-bonus). (0, MULT_ONE, 0) when the
## instance has no definition. A hand card carries no modifiers (they leave the board with
## it), so the definition is what the bot ranks by.
func stats_of(instance_id: int) -> Vector3i:
	var none: Vector3i = Vector3i(0, MatchRules.MULT_ONE, 0)
	if instance_id < 0:
		return none
	var def: CardDef = _cards.def_of(instance_id)
	if def == null:
		return none
	var times: int = MatchRules.MULT_ONE
	var plus: int = 0
	if def.bonus_kind == CardDef.BonusKind.TIMES:
		times = def.bonus
	elif def.bonus_kind == CardDef.BonusKind.PLUS:
		plus = def.bonus
	return Vector3i(def.flat, times, plus)


## Bonus-first order (DC-07 P13, R36): higher +-part, then higher ×-part, then higher flat,
## then lower instance id.
func _bonus_before(a: int, b: int) -> bool:
	var sa: Vector3i = stats_of(a)
	var sb: Vector3i = stats_of(b)
	if sa.z != sb.z:
		return sa.z > sb.z
	if sa.y != sb.y:
		return sa.y > sb.y
	if sa.x != sb.x:
		return sa.x > sb.x
	return a < b


## Flat-first order: higher flat, then the higher bonus (+-part, then ×-part), then lower
## instance id.
func _flat_before(a: int, b: int) -> bool:
	var sa: Vector3i = stats_of(a)
	var sb: Vector3i = stats_of(b)
	if sa.x != sb.x:
		return sa.x > sb.x
	if sa.z != sb.z:
		return sa.z > sb.z
	if sa.y != sb.y:
		return sa.y > sb.y
	return a < b
