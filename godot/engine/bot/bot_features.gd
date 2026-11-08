class_name BotFeatures
extends RefCounted
## The feature set of the `linear` bot and of the play-out labels (cycle 13 spec R1 to R4,
## plan P1): for one seat's view and one candidate commit, a vector of whole numbers in a
## fixed order, named by names() and versioned by SET_VERSION.
##
## The vector is the 33 compact features of COMPACT, in that order, then one indicator per
## card id of the card pool in CardDb order (`card:<id>`), each the number of copies of that
## card the candidate commits. It reads the SeatView, the candidate's cards and slots and the
## definitions of MatchCards only: no play-out, no hidden information, no clock, no
## generator, integer arithmetic only, so one view and candidate give one vector everywhere.
##
## The compact features (the hand's stats from `own_hand_row`, its costs from
## `own_hand_costs`, falling back to the row's `cost` when the view carries none):
## - `pass`: 1 when the candidate commits no card, else 0.
## - `committed_count`: cards committed. `committed_cost`: what the commit spends, the summed
##   effective Cost less the first (leftmost) card's while the free first card is granted,
##   as the engine charges it (LegalPlays.commit_cost_with). `budget_left`: the seat's
##   Budget (`energy`) less `committed_cost`.
## - `committed_power`, `committed_mult` (Σ of mult hundredths − 100), `committed_add` (Σ of
##   add hundredths), `committed_grown` (cards whose Memory is not empty) and
##   `committed_abilities` (cards whose definition has an ability and whose `uses_left` is not
##   0: a view shows -1 both for an unlimited ability and for no ability, so the definition
##   tells them apart).
## - `kept_count`, `kept_power`, `kept_cost`: the hand cards not committed, their Power and
##   effective Cost (no free-first discount).
## - `right_end`: 1 when the first committed card's slot is at or past the row's length (an
##   empty slot list is the engine's append default, so it counts too).
## - `own_row_after`: own row length plus the cards committed. `opp_row`: the opponent's row
##   length now (its face-down Commit, if any, is `opp_pending`). `row_diff_after`: their
##   difference.
## - `own_score`, `opp_score`, `score_diff`; `total_diff`: the walking totals' difference in
##   hundredths (ten-thousandths / 100, integer division toward zero).
## - `wins_diff`; `wins_needed`, `opp_wins_needed`: MatchRules.WINS_TO_TAKE (that is
##   ROUNDS / 2 + 1) less the seat's round wins, at least 0.
## - `round_number` (counts past MatchRules.ROUNDS in sudden death), `turn`, `opp_hand`,
##   `opp_pending`, `own_deck`, `opp_deck`, `own_pile`, `opp_pile`.
## - `free_first_used`: 1 when the free first card is granted and the candidate commits a
##   card, so that card costs nothing.
## - `budget_diff`: the seat's Budget less the opponent's.
## A pass has every committed feature (`committed_*`, `right_end`, `free_first_used`) 0 and
## `pass` 1. Any action that is not a commit reads as a pass.

## Indices into the vector, one per COMPACT name in the same order.
enum F {
	PASS,
	COMMITTED_COUNT,
	COMMITTED_COST,
	BUDGET_LEFT,
	COMMITTED_POWER,
	COMMITTED_MULT,
	COMMITTED_ADD,
	COMMITTED_GROWN,
	COMMITTED_ABILITIES,
	KEPT_COUNT,
	KEPT_POWER,
	KEPT_COST,
	RIGHT_END,
	OWN_ROW_AFTER,
	OPP_ROW,
	ROW_DIFF_AFTER,
	OWN_SCORE,
	OPP_SCORE,
	SCORE_DIFF,
	TOTAL_DIFF,
	WINS_DIFF,
	WINS_NEEDED,
	OPP_WINS_NEEDED,
	ROUND_NUMBER,
	TURN,
	OPP_HAND,
	OPP_PENDING,
	OWN_DECK,
	OPP_DECK,
	OWN_PILE,
	OPP_PILE,
	FREE_FIRST_USED,
	BUDGET_DIFF,
}

## The feature set's version: every label, weights file and the bot name it (R4).
const SET_VERSION: String = "f1"
## The compact feature names, in vector order.
const COMPACT: Array[String] = [
	"pass",
	"committed_count",
	"committed_cost",
	"budget_left",
	"committed_power",
	"committed_mult",
	"committed_add",
	"committed_grown",
	"committed_abilities",
	"kept_count",
	"kept_power",
	"kept_cost",
	"right_end",
	"own_row_after",
	"opp_row",
	"row_diff_after",
	"own_score",
	"opp_score",
	"score_diff",
	"total_diff",
	"wins_diff",
	"wins_needed",
	"opp_wins_needed",
	"round_number",
	"turn",
	"opp_hand",
	"opp_pending",
	"own_deck",
	"opp_deck",
	"own_pile",
	"opp_pile",
	"free_first_used",
	"budget_diff",
]
## The prefix of a card indicator's name.
const CARD_PREFIX: String = "card:"
## Ten-thousandths (walking totals) to hundredths.
const TOTAL_DIVISOR: int = 100


## The feature names in vector order: COMPACT, then `card:<id>` for every card of the pool
## `cards` was built from, in CardDb order. Only COMPACT for a null or failed `cards`.
static func names(cards: MatchCards) -> Array[String]:
	var out: Array[String] = []
	out.assign(COMPACT)
	if cards == null:
		return out
	for card_id: String in cards.pool_ids():
		out.append(CARD_PREFIX + card_id)
	return out


## The feature vector of the candidate `action` for the seat of `view`, laid out as names().
static func of(view: SeatView, action: EngineAction, cards: MatchCards) -> PackedInt64Array:
	var pool_size: int = 0 if cards == null else cards.pool_size()
	var out: PackedInt64Array = PackedInt64Array()
	if out.resize(COMPACT.size() + pool_size) != OK:
		return out
	var committed: Array[int] = []
	if action != null and action.kind == EngineAction.Kind.COMMIT:
		committed.assign(action.cards)
	_fill_committed(out, view, action, committed, cards)
	_fill_kept(out, view, committed)
	_fill_position(out, view, committed.size())
	return out


## The candidate's own features and its card indicators.
static func _fill_committed(
	out: PackedInt64Array,
	view: SeatView,
	action: EngineAction,
	committed: Array[int],
	cards: MatchCards
) -> void:
	var count: int = committed.size()
	out[F.PASS] = 1 if count == 0 else 0
	out[F.COMMITTED_COUNT] = count
	var costs: Array[int] = []
	for card: int in committed:
		var at: int = view.own_hand.find(card)
		costs.append(_cost_at(view, at))
		if at < 0 or at >= view.own_hand_row.size():
			_add_indicator(out, card, cards)
			continue
		var entry: Dictionary = view.own_hand_row[at]
		var power: int = entry.get("power", 0)
		var mult: int = entry.get("mult", MatchRules.BONUS_ONE)
		var add: int = entry.get("add", 0)
		var grown: bool = entry.get("grown", false)
		var uses: int = entry.get("uses_left", -1)
		out[F.COMMITTED_POWER] += power
		out[F.COMMITTED_MULT] += mult - MatchRules.BONUS_ONE
		out[F.COMMITTED_ADD] += add
		out[F.COMMITTED_GROWN] += 1 if grown else 0
		out[F.COMMITTED_ABILITIES] += 1 if uses != 0 and _has_ability(card, cards) else 0
		_add_indicator(out, card, cards)
	var spent: int = 0
	for cost: int in costs:
		spent += cost
	var free: bool = view.free_first and count > 0
	if free:
		spent -= costs[0]
	out[F.COMMITTED_COST] = spent
	out[F.BUDGET_LEFT] = view.energy - spent
	out[F.FREE_FIRST_USED] = 1 if free else 0
	var first_slot: int = -1
	if count > 0 and not action.slots.is_empty():
		first_slot = action.slots[0]
	var at_end: bool = count > 0 and (first_slot < 0 or first_slot >= view.own_board.size())
	out[F.RIGHT_END] = 1 if at_end else 0


## The hand cards the candidate keeps.
static func _fill_kept(out: PackedInt64Array, view: SeatView, committed: Array[int]) -> void:
	for at: int in range(view.own_hand.size()):
		if committed.has(view.own_hand[at]):
			continue
		out[F.KEPT_COUNT] += 1
		out[F.KEPT_COST] += _cost_at(view, at)
		if at < view.own_hand_row.size():
			var entry: Dictionary = view.own_hand_row[at]
			var power: int = entry.get("power", 0)
			out[F.KEPT_POWER] += power


## The position's features: rows after the commit, Scores, wins, the clock and the counts.
static func _fill_position(out: PackedInt64Array, view: SeatView, count: int) -> void:
	var own: int = view.seat
	var opp: int = view.opponent
	var own_row: int = view.own_board.size() + count
	var opp_row: int = view.opponent_board.size()
	out[F.OWN_ROW_AFTER] = own_row
	out[F.OPP_ROW] = opp_row
	out[F.ROW_DIFF_AFTER] = own_row - opp_row
	out[F.OWN_SCORE] = view.scores[own]
	out[F.OPP_SCORE] = view.scores[opp]
	out[F.SCORE_DIFF] = view.scores[own] - view.scores[opp]
	@warning_ignore("integer_division")
	var total_diff: int = (view.totals[own] - view.totals[opp]) / TOTAL_DIVISOR
	out[F.TOTAL_DIFF] = total_diff
	out[F.WINS_DIFF] = view.wins[own] - view.wins[opp]
	out[F.WINS_NEEDED] = maxi(MatchRules.WINS_TO_TAKE - view.wins[own], 0)
	out[F.OPP_WINS_NEEDED] = maxi(MatchRules.WINS_TO_TAKE - view.wins[opp], 0)
	out[F.ROUND_NUMBER] = view.round_number
	out[F.TURN] = view.turn
	out[F.OPP_HAND] = view.opponent_hand_count
	out[F.OPP_PENDING] = view.opponent_pending_count
	out[F.OWN_DECK] = view.deck_counts[own]
	out[F.OPP_DECK] = view.deck_counts[opp]
	out[F.OWN_PILE] = view.own_pile.size()
	out[F.OPP_PILE] = view.opponent_pile.size()
	out[F.BUDGET_DIFF] = view.budgets[own] - view.budgets[opp]


## The effective Cost of the hand card at `at`: `own_hand_costs` when the view carries one
## per hand card, else the row entry's `cost`; 0 for a card not in the hand.
static func _cost_at(view: SeatView, at: int) -> int:
	if at < 0:
		return 0
	if view.own_hand_costs.size() == view.own_hand.size():
		return maxi(view.own_hand_costs[at], 0)
	if at < view.own_hand_row.size():
		var entry: Dictionary = view.own_hand_row[at]
		var cost: int = entry.get("cost", 0)
		return maxi(cost, 0)
	return 0


## Whether `card`'s definition carries any ability.
static func _has_ability(card: int, cards: MatchCards) -> bool:
	if cards == null:
		return false
	var def: CardDef = cards.def_of(card)
	return def != null and not def.abilities.is_empty()


## Counts `card` in its `card:<id>` indicator; nothing for a card with no definition.
static func _add_indicator(out: PackedInt64Array, card: int, cards: MatchCards) -> void:
	if cards == null:
		return
	var def: CardDef = cards.def_of(card)
	if def == null:
		return
	var index: int = cards.pool_index(def.id)
	if index < 0 or COMPACT.size() + index >= out.size():
		return
	out[COMPACT.size() + index] += 1
