class_name Evaluator
extends RefCounted
## The value of a previewed candidate and the level's push (cycle 7 R8, R13-R15, plan P5,
## P6). Static, pure and integer: no state, no output, every draw from the generator passed
## in.
##
## features_of() reads the candidate's preview scores and the seat's view (FEATURES, in that
## order). value() is their weighted sum, the weights in hundredths (BotWeights.weights; a
## feature the dictionary does not name weighs 0), floored to whole points, so the default
## weights (`score_diff` at 100) give exactly the greedy bot's own-minus-opponent score.
##
## pushed() is the level knob (P6, R13-R15). Level 20 changes nothing. Below it, with
## `weakness = 120 - 2 * level`, `spread = min(best - worst, push_unit)` and, per candidate,
## `gap = best - value` and a draw `d = rng.pick_index(weakness)` (one per candidate, in
## order, every candidate drawing):
##   a candidate with `gap <= push_unit` gets `value + weakness * gap / 128 + spread * d / 128`
##   (each quotient floored), a candidate with `gap > push_unit` keeps its value.
## So a candidate further than push_unit below the best can never be lifted above it (R14),
## while near ones close most of their gap at level 0 and keep more of it as the level rises.
## The gap term is floored on its own, so it closes strictly less than the gap
## (`weakness < 128`), and the noise term has one distribution for every candidate: the best
## candidate's expected pushed value stays strictly the highest at every level.
## The level reads nothing but the values and the generator, and never drops a candidate
## (R15). The draw is whole-number arithmetic, so every platform pushes alike.

## The feature names, in the order features_of() fills them (P5).
const FEATURES: Array[String] = [
	"score_diff",
	"own_score",
	"opp_score",
	"energy_left",
	"cards_left",
	"cards_committed",
	"turns_left",
	"wins_diff",
	"wins_needed",
	"opp_hand",
	"opp_pending",
	"deck_left",
	"row_len_diff",
]

## A weight of WEIGHT_ONE counts a feature once (weights are in hundredths, P7).
const WEIGHT_ONE: int = 100
## The push's weakness at level 0, and how much each level takes off it (P6).
const WEAKNESS_BASE: int = 120
const WEAKNESS_STEP: int = 2
## The push's denominator (P6): above WEAKNESS_BASE, so the gap term never closes a gap.
const PUSH_DENOMINATOR: int = 128


## The features of `action` for `view.seat` (FEATURES order): `scores` is the candidate's
## preview, indexed by seat ([0, 0] when it is not two scores). The cost, cards and row
## counts are those of `action.cards` (none for a prompt answer), the cost at the effective
## costs the engine checks (cycle 8 R21, P3: `energy_left`); `row_len_diff` is the own
## row after the commit less the opponent's row with its face-down commit, as the view
## counts them.
static func features_of(
	view: SeatView, scores: Array[int], action: EngineAction, cards: MatchCards
) -> PackedInt32Array:
	var seat: int = view.seat
	var other: int = 1 - seat
	var own_score: int = scores[seat] if scores.size() == 2 else 0
	var opp_score: int = scores[other] if scores.size() == 2 else 0
	var committed: Array[int] = []
	if action != null:
		committed = action.cards
	var cost: int = 0
	if cards != null:
		var committed_costs: Array[int] = _costs_of(view, committed, cards)
		cost = maxi(LegalPlays.commit_cost_with(committed, committed_costs, view.free_first), 0)
	var opp_row: int = view.opponent_board.size() + view.opponent_pending_count
	var out: Array[int] = [
		own_score - opp_score,
		own_score,
		opp_score,
		view.energy - cost,
		view.own_hand.size() - committed.size(),
		committed.size(),
		MatchRules.TURNS - view.turn,
		view.wins[seat] - view.wins[other],
		MatchRules.WINS_TO_TAKE - view.wins[seat],
		view.opponent_hand_count,
		view.opponent_pending_count,
		view.deck_counts[seat],
		view.own_board.size() + committed.size() - opp_row,
	]
	return PackedInt32Array(out)


## The cost of each card of `committed` (cycle 8 R21, P3): its effective cost from the view's
## `own_hand_costs` (GreedyBot.hand_costs, printed when the view carries none), or its
## printed cost for a card not in the view's hand.
static func _costs_of(view: SeatView, committed: Array[int], cards: MatchCards) -> Array[int]:
	var costs: Array[int] = GreedyBot.hand_costs(view, cards)
	var out: Array[int] = []
	for card: int in committed:
		var at: int = view.own_hand.find(card)
		out.append(costs[at] if at >= 0 else LegalPlays.cost_of(card, cards))
	return out


## The weighted sum of `features` (FEATURES order) under `weights` (the built-in defaults
## when null), in hundredths, floored to whole points.
static func value(features: PackedInt32Array, weights: BotWeights) -> int:
	var table: Dictionary = BotWeights.defaults("").weights if weights == null else weights.weights
	var total: int = 0
	for index: int in range(mini(features.size(), FEATURES.size())):
		var name: String = FEATURES[index]
		if not table.has(name):
			continue
		var weight: int = table[name]
		total += features[index] * weight
	return _floor_points(total)


## `values` pushed for `level` (see the class comment): unchanged at level 20 and above;
## below it, each candidate within `push_unit` of the best lifted by its gap term and a draw
## from `rng` (no draw, 0, with a null rng). A new array, in the order of `values`.
static func pushed(
	values: PackedInt32Array, level: int, push_unit: int, rng: MatchRng
) -> PackedInt32Array:
	var out: PackedInt32Array = values.duplicate()
	if level >= BotPlayer.FULL_LEVEL or values.is_empty():
		return out
	var weakness: int = WEAKNESS_BASE - WEAKNESS_STEP * maxi(level, 0)
	var unit: int = maxi(push_unit, 0)
	var best: int = values[0]
	var worst: int = values[0]
	for listed: int in values:
		best = maxi(best, listed)
		worst = mini(worst, listed)
	var spread: int = mini(best - worst, unit)
	for index: int in range(values.size()):
		var draw: int = rng.pick_index(weakness) if rng != null else 0
		var gap: int = best - values[index]
		if gap > unit:
			continue
		out[index] = values[index] + _push_part(weakness, gap) + _push_part(spread, draw)
	return out


## `a * b / PUSH_DENOMINATOR`, floored (both are non-negative here).
static func _push_part(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return a * b / PUSH_DENOMINATOR


## A hundredths total in whole points, floored (toward minus infinity, so the rounding does
## not depend on the sign).
static func _floor_points(total: int) -> int:
	@warning_ignore("integer_division")
	var quotient: int = total / WEIGHT_ONE
	if total < 0 and quotient * WEIGHT_ONE != total:
		quotient -= 1
	return quotient
