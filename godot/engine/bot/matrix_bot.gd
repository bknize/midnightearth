class_name MatrixBot
extends TunedBot
## The matrix bot (cycle 7 R50-R54, plan P11-P14): the simultaneous commit played as a small
## zero-sum matrix game between the bot's own candidates and hypothetical opponent commits.
##
## Commits (matrix_commit):
## - Rows: the tuned bot's candidates (TunedBot.candidates: the first `weights.k` of
##   CandidateGen.all() by bound, priced at the view's effective costs).
## - Columns: opponent_candidates(): `weights.samples` hands of HandSampler.sample() from
##   decision_rng(view, HANDS_TAG), each enumerated by CandidateGen.all() for the opponent
##   with its public budget (`budgets[opponent]`), its row size and no free-first grant (the
##   view cannot know it, P14), at the definitions' costs (the view cannot know an unseen card's
##   memory); while the opponent has committed first, only commits with its observed count
##   and slots (R53); deduplicated (CandidateGen.key_of), then the first `weights.k_opp` by
##   CandidateGen.ranked().
## - Cell [i][j]: Evaluator.value() of the features of own candidate i with the scores of
##   engine.preview_pair(seat, own_i, opp_j). Columns are previewed one at a time, rows in
##   order. A column every row's preview refuses ([]) is skipped (a hypothesis the engine
##   does not take, PairPreview); a row refused in a column some row accepts is dropped.
## - Push (R13-R15, P6 on expected payoffs): each kept row's expected payoff is its mean
##   over the kept columns (whole points, floored); below level 20 Evaluator.pushed() of
##   those with decision_rng(view, PUSH_TAG) gives each row a push, added to every cell of
##   that row. Level 20 takes no push draw.
## - RegretMatching.solve() over `weights.rm_iterations` gives the mixed strategy; the row
##   played is RegretMatching.sample_index() with decision_rng(view, MATRIX_TAG).
## - Fallback: with no opponent candidate, or no column kept, the bot commits as the tuned
##   bot does (TunedBot.best_commit: one engine.preview per own candidate). preview_pair
##   may legitimately refuse every hypothesis (PairPreview.accepts: a hidden cost cut or a
##   recovered card of this seat's deck), so this is a real path, never an error.
##
## Previews per commit decision: at most `k · k_opp` joint previews, plus at most `k` plain
## previews on the fallback. Prompts (R52): answered exactly as the tuned bot answers them
## (TunedBot.answer_prompt), so they cost the tuned bot's option previews.
##
## R2: the bot reads only its own SeatView, its seed, `level` and `weights`, and asks the
## engine for nothing but preview_pair() and the tuned bot's previews of its own seat. It
## holds no generator between calls. Floats live only inside RegretMatching; the chosen
## action is one of the candidates, built from whole numbers. With a null engine every joint
## preview is [0, 0].

## Separates the strategy draw from every other draw of a decision ("mtx" in ASCII).
const MATRIX_TAG: int = 0x6D7478
## Separates the opponent-hand samples from every other draw of a decision ("hnd").
const HANDS_TAG: int = 0x686E64
## How many leading Evaluator.FEATURES depend on the preview scores (score_diff, own_score,
## opp_score); the rest depend only on the view and the own candidate.
const SCORE_FEATURES: int = 3


## `cards` as BotPlayer._init. The registry sets `weights` (the shipped file, or the
## defaults when it fails to load) and `level`.
func _init(bot_seed: int, cards: MatchCards) -> void:
	super(bot_seed, cards)


## The registry name (BotRegistry.NAMES).
func bot_name() -> String:
	return "matrix"


## The action for `view.seat`: while a prompt is open for that seat, the tuned bot's answer
## (answer_prompt); otherwise the matrix commit (matrix_commit).
func choose(view: SeatView, engine: MatchEngine) -> EngineAction:
	var answer: EngineAction = answer_prompt(view, engine)
	if answer != null:
		return answer
	return matrix_commit(view, engine)


## The commit drawn from the matrix game's strategy (see the class comment), or the tuned
## bot's best commit on the fallback. Score tables are column-major: `rows` entries per kept
## column, each indexed by own candidate position.
func matrix_commit(view: SeatView, engine: MatchEngine) -> EngineAction:
	var own: Array[EngineAction] = candidates(view)
	var opp: Array[EngineAction] = opponent_candidates(view)
	if own.is_empty() or opp.is_empty():
		return best_commit(view, engine)
	var rows: int = own.size()
	var own_scores: Array[int] = []
	var opp_scores: Array[int] = []
	var kept_cols: int = 0
	var dropped: Dictionary[int, bool] = {}
	var even: Array[int] = [0, 0]
	for column: EngineAction in opp:
		var refused: Array[int] = []
		var cells: Array[int] = []
		var accepted: bool = false
		for row: int in range(rows):
			var scores: Array[int] = even
			if not dropped.has(row):
				scores = _preview_pair(engine, view.seat, own[row], column)
				if scores.size() != 2:
					refused.append(row)
					scores = even
				else:
					accepted = true
			cells.append_array(scores)
		if not accepted:
			continue
		for row: int in refused:
			dropped[row] = true
		kept_cols += 1
		for row: int in range(rows):
			own_scores.append(cells[2 * row + view.seat])
			opp_scores.append(cells[2 * row + view.opponent])
	var kept_rows: Array[int] = []
	for row: int in range(rows):
		if not dropped.has(row):
			kept_rows.append(row)
	if kept_cols == 0 or kept_rows.is_empty():
		return best_commit(view, engine)
	var payoff: Array[PackedInt32Array] = _payoff(view, own, kept_rows, own_scores, opp_scores)
	_push_rows(view, payoff)
	var strategy: PackedFloat32Array = RegretMatching.solve(payoff, _weights().rm_iterations)
	var picked: int = RegretMatching.sample_index(strategy, decision_rng(view, MATRIX_TAG))
	if picked < 0:
		return best_commit(view, engine)
	return own[kept_rows[picked]]


## The opponent's hypothetical commits for `view` (see the class comment): from
## `weights.samples` sampled hands, filtered to the observed count and slots while the
## opponent has committed first, deduplicated, the first `weights.k_opp` by bound.
func opponent_candidates(view: SeatView) -> Array[EngineAction]:
	var settings: BotWeights = _weights()
	var rng: MatchRng = decision_rng(view, HANDS_TAG)
	var hands: Array[Array] = HandSampler.sample(view, _cards, rng, settings.samples)
	var budget: int = view.budgets[view.opponent]
	var row_size: int = view.opponent_board.size()
	var observed: bool = opponent_committed(view)
	var seen: Dictionary[String, bool] = {}
	var pooled: Array[EngineAction] = []
	for sampled: Array in hands:
		var hand: Array[int] = []
		hand.assign(sampled)
		for action: EngineAction in CandidateGen.all(
			hand, budget, row_size, false, view.opponent, _cards
		):
			if observed and not matches_observed(view, action):
				continue
			var key: String = CandidateGen.key_of(action)
			if seen.has(key):
				continue
			seen[key] = true
			pooled.append(action)
	return CandidateGen.ranked(pooled, _cards).slice(0, maxi(settings.k_opp, 0))


## Whether the opponent has committed first this turn: the view's seat is awaited and the
## turn's first committer is the opponent.
static func opponent_committed(view: SeatView) -> bool:
	return view.awaited_seat == view.seat and view.first_seat == view.opponent


## Whether `action` has the opponent's observed face-down count and slots (R53).
static func matches_observed(view: SeatView, action: EngineAction) -> bool:
	if action.cards.size() != view.opponent_pending_count:
		return false
	return action.slots == view.opponent_pending_slots


## The payoff matrix over `kept_rows` (positions in `own`) and the kept columns, from the
## column-major score tables (`rows` entries per kept column): each cell the evaluator's
## value of its own candidate with that column's scores. Each row's view features are built
## once (Evaluator.features_of) and only the score features change per cell.
func _payoff(
	view: SeatView,
	own: Array[EngineAction],
	kept_rows: Array[int],
	own_scores: Array[int],
	opp_scores: Array[int]
) -> Array[PackedInt32Array]:
	var settings: BotWeights = _weights()
	var rows: int = own.size()
	@warning_ignore("integer_division")
	var cols: int = own_scores.size() / rows
	var even: Array[int] = [0, 0]
	var out: Array[PackedInt32Array] = []
	for row: int in kept_rows:
		var features: PackedInt32Array = Evaluator.features_of(view, even, own[row], _cards)
		var values: Array[int] = []
		for column: int in range(cols):
			var mine: int = own_scores[column * rows + row]
			var theirs: int = opp_scores[column * rows + row]
			if features.size() >= SCORE_FEATURES:
				features[0] = mine - theirs
				features[1] = mine
				features[2] = theirs
			values.append(Evaluator.value(features, settings))
		out.append(PackedInt32Array(values))
	return out


## Below level 20, adds to every cell of each row of `payoff` that row's push: the level's
## push (Evaluator.pushed via TunedBot._pushed, decision_rng(view, PUSH_TAG)) of the rows'
## expected payoffs (mean over the columns, floored). Unchanged, with no draw, at level 20.
func _push_rows(view: SeatView, payoff: Array[PackedInt32Array]) -> void:
	if level >= FULL_LEVEL:
		return
	var expected: Array[int] = []
	for row: PackedInt32Array in payoff:
		var total: int = 0
		for cell: int in row:
			total += cell
		expected.append(_floor_div(total, maxi(row.size(), 1)))
	var none: Array[int] = []
	var pushed: PackedInt32Array = _pushed(view, expected, none)
	for index: int in range(payoff.size()):
		var lift: int = pushed[index] - expected[index]
		if lift == 0:
			continue
		var row: PackedInt32Array = payoff[index]
		for column: int in range(row.size()):
			row[column] += lift
		payoff[index] = row


## The joint preview's scores, [0, 0] with no engine to ask.
func _preview_pair(
	engine: MatchEngine, seat: int, own: EngineAction, opp: EngineAction
) -> Array[int]:
	if engine == null:
		var even: Array[int] = [0, 0]
		return even
	return engine.preview_pair(seat, own, opp)


## `total / count` floored toward minus infinity (`count` > 0).
static func _floor_div(total: int, count: int) -> int:
	@warning_ignore("integer_division")
	var quotient: int = total / count
	if total < 0 and quotient * count != total:
		quotient -= 1
	return quotient
