class_name TunedBot
extends BotPlayer
## The tuned bot (cycle 7 R6-R16, plan P9): the greedy search pruned to the top `k`
## candidates of a cheap bound, valued by the linear evaluator under `weights`, with the
## level's push. The shipped opponent (BotRegistry.default_name()).
##
## Commits: CandidateGen.all() (the greedy bot's candidates, each once, in its search order),
## cut to the first `weights.k` by CandidateGen.ranked() (exactly CandidateGen.top(); the cut
## is kept in search order, so ties are listed as the greedy bot lists them). Each kept
## candidate is previewed for the view's seat; one whose preview is empty is dropped (R3).
## The rest are valued by Evaluator.value(Evaluator.features_of(...)) under `weights`, pushed
## below level 20 by Evaluator.pushed() with decision_rng(view, PUSH_TAG), and the highest
## (pushed) value wins, ties by one pick_index from a fresh generator seeded
## MatchRng.derive_seed(bot_seed, [round, turn]), the greedy bot's commit derivation.
##
## Prompts (R9): answered as the greedy bot answers them, valued by the evaluator. A
## single-target prompt previews each option (preview_choice); a RECOVER_DESTROYED or
## DISCARD_OWN prompt is answered by the greedy bot's rule with no preview
## (GreedyBot.ranked_option); a multi-select prompt previews the greedy bot's n + 1 candidate
## sets (GreedyBot.set_candidates, preview_set). Below level 20 the values are pushed with
## decision_rng(view, PUSH_TAG, [the prompt's source card]); ties by the greedy bot's prompt
## derivation, MatchRng.derive_seed(bot_seed, [round, turn, GreedyBot.PROMPT_TAG, source]).
##
## R12 by construction: with the default weights (score_diff at 100 hundredths, the rest 0)
## a value is exactly own minus opponent score (100 · diff / 100 floors to diff, so no two
## distinct greedy values merge); with `k` at least the candidate count the candidates are
## the greedy bot's, previewed and listed in its order; level 20 takes no push draw; and the
## tie-break generators are the greedy bot's derivations. So the argmax set, its order and the
## pick equal the greedy bot's on every decision.
##
## R2: the bot reads only its own SeatView, its seed, `level` and `weights`, and asks the
## engine for nothing but preview(), preview_choice() and preview_set() of its own seat. It
## holds no generator between calls; every draw is from a fresh one (the push from
## decision_rng with PUSH_TAG, the tie from the derivations above). No clock is read. With
## a null engine every candidate previews [0, 0], as with the greedy bot.

## Separates the level push's draw from every other draw of a decision ("psh" in ASCII).
const PUSH_TAG: int = 0x707368

## The greedy bot over the same seed and cards, for its prompt rules and set candidates
## (neither asks the engine anything).
var _greedy: GreedyBot = null


## `cards` as BotPlayer._init. The registry sets `weights` (the shipped file, or the
## defaults when it fails to load) and `level`.
func _init(bot_seed: int, cards: MatchCards) -> void:
	super(bot_seed, cards)
	_greedy = GreedyBot.new(bot_seed, _cards)


## The registry name (BotRegistry.NAMES).
func bot_name() -> String:
	return "tuned"


## The action for `view.seat`: while a prompt is open for that seat, its best answer
## (answer_prompt); otherwise its best commit (best_commit). `engine` is the match the view
## was built from, used only for previews of `view.seat`.
func choose(view: SeatView, engine: MatchEngine) -> EngineAction:
	var answer: EngineAction = answer_prompt(view, engine)
	if answer != null:
		return answer
	return best_commit(view, engine)


## The best-valued commit among candidates(view) (see the class comment). The empty commit
## when no candidate previews.
func best_commit(view: SeatView, engine: MatchEngine) -> EngineAction:
	var kept: Array[EngineAction] = []
	var values: Array[int] = []
	for action: EngineAction in candidates(view):
		var scores: Array[int] = _preview_commit(engine, view.seat, action)
		if scores.size() != 2:
			continue
		kept.append(action)
		values.append(_value_of(view, scores, action))
	if kept.is_empty():
		var none: Array[int] = []
		return EngineAction.commit(view.seat, none, none)
	var none_extra: Array[int] = []
	var pushed: PackedInt32Array = _pushed(view, values, none_extra)
	var parts: Array[int] = [view.round_number, view.turn]
	var tie: MatchRng = MatchRng.new(MatchRng.derive_seed(_bot_seed, parts))
	return kept[pick_best(pushed, tie)]


## The candidates the bot previews for `view`: the first `weights.k` of CandidateGen.all()
## by CandidateGen.ranked(), listed in all()'s (the greedy bot's) search order. All of them
## when `k` is at least their count.
func candidates(view: SeatView) -> Array[EngineAction]:
	var listed: Array[EngineAction] = CandidateGen.all(
		view.own_hand, view.energy, view.own_board.size(), view.free_first, view.seat, _cards
	)
	var k: int = _weights().k
	if k >= listed.size():
		return listed
	var keep: Dictionary[String, bool] = {}
	for action: EngineAction in CandidateGen.ranked(listed, _cards).slice(0, maxi(k, 0)):
		keep[CandidateGen.key_of(action)] = true
	var out: Array[EngineAction] = []
	for action: EngineAction in listed:
		if keep.has(CandidateGen.key_of(action)):
			out.append(action)
	return out


## The answer to the prompt open for `view.seat` (see the class comment): a multi-select
## prompt by answer_set(); a recovery or a discard by the greedy bot's rule; otherwise the
## best-valued previewed option, ties by the greedy bot's prompt seed. Null when no prompt
## is open for that seat.
func answer_prompt(view: SeatView, engine: MatchEngine) -> EngineAction:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	if not open or asked != view.seat:
		return null
	if Choice.is_multi_prompt(view.prompt):
		return answer_set(view, engine)
	var options: Array[int] = Choice.options_of(view.prompt)
	var zone: int = view.prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var ranked: int = -1 if options.is_empty() else _greedy.ranked_option(view)
	if options.is_empty() or ranked >= 0:
		return EngineAction.choose(view.seat, zone, ranked)
	var kept: Array[int] = []
	var values: Array[int] = []
	for option: int in options:
		var scores: Array[int] = _preview_option(engine, view.seat, option)
		if scores.size() != 2:
			continue
		kept.append(option)
		values.append(_value_of(view, scores, null))
	if kept.is_empty():
		return EngineAction.choose(view.seat, zone, options[0])
	var pushed: PackedInt32Array = _pushed(view, values, _source_of(view))
	return EngineAction.choose(view.seat, zone, kept[pick_best(pushed, _prompt_rng(view))])


## The answer to the multi-select prompt open for `view.seat`: the best-valued of the greedy
## bot's n + 1 candidate sets, each previewed once, ties by the greedy bot's prompt seed;
## the empty set (always valid) when none previews. Null when no multi-select prompt is open
## for that seat.
func answer_set(view: SeatView, engine: MatchEngine) -> EngineAction:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	if not open or asked != view.seat or not Choice.is_multi_prompt(view.prompt):
		return null
	var zone: int = view.prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var kept: Array[Array] = []
	var values: Array[int] = []
	for listed: Array in _greedy.set_candidates(view):
		var candidate: Array[int] = []
		candidate.assign(listed)
		var scores: Array[int] = _preview_set(engine, view.seat, candidate)
		if scores.size() != 2:
			continue
		kept.append(candidate)
		values.append(_value_of(view, scores, null))
	var chosen: Array[int] = []
	if not kept.is_empty():
		var pushed: PackedInt32Array = _pushed(view, values, _source_of(view))
		chosen.assign(kept[pick_best(pushed, _prompt_rng(view))])
	return EngineAction.choose_set(view.seat, zone, chosen)


## The position of the highest of `values`, ties by one pick_index of `rng` over the tied
## positions in order (the greedy bot's argmax); -1 for no values, with no draw.
static func pick_best(values: PackedInt32Array, rng: MatchRng) -> int:
	var best: Array[int] = []
	var best_value: int = 0
	for index: int in range(values.size()):
		var value: int = values[index]
		if best.is_empty() or value > best_value:
			best.clear()
			best_value = value
			best.append(index)
		elif value == best_value:
			best.append(index)
	if best.is_empty():
		return -1
	return best[rng.pick_index(best.size())]


## The evaluator's value of a previewed candidate (`action` null for a prompt answer).
func _value_of(view: SeatView, scores: Array[int], action: EngineAction) -> int:
	var features: PackedInt32Array = Evaluator.features_of(view, scores, action, _cards)
	return Evaluator.value(features, _weights())


## `values` pushed for the bot's level: unchanged, with no generator built, at level 20;
## below it Evaluator.pushed() with decision_rng(view, PUSH_TAG, extra).
func _pushed(view: SeatView, values: Array[int], extra: Array[int]) -> PackedInt32Array:
	var packed: PackedInt32Array = PackedInt32Array(values)
	if level >= FULL_LEVEL:
		return packed
	var rng: MatchRng = decision_rng(view, PUSH_TAG, extra)
	return Evaluator.pushed(packed, level, _weights().push_unit, rng)


## The weights in force: `weights`, or the defaults for this bot when none are set.
func _weights() -> BotWeights:
	if weights == null:
		return BotWeights.defaults(bot_name())
	return weights


## [the open prompt's source card], which tells two prompts of one turn apart.
func _source_of(view: SeatView) -> Array[int]:
	var source: int = view.prompt.get("card", -1)
	var out: Array[int] = [source]
	return out


## The greedy bot's prompt tie generator: seeded [round, turn, GreedyBot.PROMPT_TAG, the
## prompt's source card], fresh per decision.
func _prompt_rng(view: SeatView) -> MatchRng:
	var source: int = view.prompt.get("card", -1)
	var parts: Array[int] = [view.round_number, view.turn, GreedyBot.PROMPT_TAG, source]
	return MatchRng.new(MatchRng.derive_seed(_bot_seed, parts))


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
