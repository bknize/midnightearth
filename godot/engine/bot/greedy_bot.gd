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
## which makes both orders equal. Each candidate is
## scored by MatchEngine.preview() as own score minus the opponent's; the best wins, and a
## tie is broken by one pick_index from a fresh generator seeded
## MatchRng.derive_seed(bot_seed, [round, turn]).
##
## Prompts (R37): each option of the view's prompt is scored by
## MatchEngine.preview_choice() the same way; a tie is broken with the seed derived from
## [round, turn, PROMPT_TAG, the prompt's source card], distinct from the commit's.
##
## Hidden information (R7, R38): the bot reads only its own SeatView (its hand, budget, row
## size, prompt, round and turn) and asks the engine only for previews of its own seat's
## candidates. A preview returns nothing but two scores, and the engine computes them with
## the opponent's face-down cards treated as absent (MatchEngine.preview), so the scores are
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
var _cards: CardDb = null


## `cards` supplies card stats and costs; null loads CardDb.load_default(). The plan's
## signature is `_init(bot_seed)`, so the card database is an optional extra.
##
## A card database that failed to load (CardDb.is_valid() false) is kept, not reported:
## every card then has cost -1, the only legal set is the empty one, and choose() always
## commits nothing, so a bot built on it passes every turn. The bot does not signal this
## itself, since engine code never reports errors out of band (R27). It cannot happen
## through the engine: the engine never builds a bot, and a match cannot start without a
## valid card database (CARD_DATA_INVALID), so callers that pass the database they started
## the match with always give the bot valid data.
func _init(bot_seed: int, cards: CardDb = null) -> void:
	_bot_seed = bot_seed
	if cards == null:
		_cards = CardDb.load_default()
	else:
		_cards = cards


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
	var source: int = view.prompt.get("card", -1)
	var parts: Array[int] = [view.round_number, view.turn, PROMPT_TAG, source]
	var rng: MatchRng = MatchRng.new(MatchRng.derive_seed(_bot_seed, parts))
	return EngineAction.choose(view.seat, zone, best[rng.pick_index(best.size())])


## Every candidate commit for the view (see the class comment), in search order: legal sets
## by ascending bitmask; per set the bonus-first order, then the flat-first order when it
## differs; per order the left end, then the right end when the row is not empty. Each
## commit carries explicit slots; the empty set is one candidate with none.
func candidates(view: SeatView) -> Array[EngineAction]:
	var out: Array[EngineAction] = []
	var row_size: int = view.own_board.size()
	for mask: int in LegalPlays.enumerate_masks(view.own_hand, view.energy, _cards):
		var picked: Array[int] = LegalPlays.subset(view.own_hand, mask)
		if picked.is_empty():
			var none: Array[int] = []
			out.append(EngineAction.commit(view.seat, picked, none))
			continue
		var bonus_first: Array[int] = []
		bonus_first.assign(picked)
		bonus_first.sort_custom(_bonus_before)
		var flat_first: Array[int] = []
		flat_first.assign(picked)
		flat_first.sort_custom(_flat_before)
		_add_ends(out, view.seat, bonus_first, row_size)
		if search_flat_first and flat_first != bonus_first:
			_add_ends(out, view.seat, flat_first, row_size)
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


## The definition's (flat, bonus) of a card instance (instance id % DECK_SIZE is its definition);
## (0, 0) when it has none. A hand card carries no modifiers (they leave the board with it).
func stats_of(instance_id: int) -> Vector2i:
	if instance_id < 0:
		return Vector2i.ZERO
	var def: CardDef = _cards.card_at(instance_id % MatchRules.DECK_SIZE)
	if def == null:
		return Vector2i.ZERO
	return Vector2i(def.flat, def.bonus)


## Bonus-first order: higher bonus, then higher flat, then lower instance id.
func _bonus_before(a: int, b: int) -> bool:
	var sa: Vector2i = stats_of(a)
	var sb: Vector2i = stats_of(b)
	if sa.y != sb.y:
		return sa.y > sb.y
	if sa.x != sb.x:
		return sa.x > sb.x
	return a < b


## Flat-first order: higher flat, then higher bonus, then lower instance id.
func _flat_before(a: int, b: int) -> bool:
	var sa: Vector2i = stats_of(a)
	var sb: Vector2i = stats_of(b)
	if sa.x != sb.x:
		return sa.x > sb.x
	if sa.y != sb.y:
		return sa.y > sb.y
	return a < b
