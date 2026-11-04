class_name ScoreTracker
extends RefCounted
## The scores and multipliers the HUD shows (R50-R52). Steps in, numbers out: a walk start
## zeroes the scores and sets the multipliers to 1, each pulse sets its seat's score and
## multiplier to the engine's values, and the turn end sets the exact totals and ends the
## walk. Pure: no nodes.
##
## DC-06 (R32-R34): `tally` and `tally_mults` are the walk's running numbers (shown beside
## the rows); `held` is the previous turn's total, the only number the HUD shows. `held`
## changes only at TURN_END or CLEAR_TABLE, so no half-walk number reaches the HUD. The
## older `scores`, `mults` and `walking` stay for callers not yet moved over.

var scores: Array[int] = [0, 0]
var mults: Array[int] = [1, 1]
## True from the walk start to the turn end: the HUD then shows "score x mult".
var walking: bool = false
## The walk's running score and multiplier per seat.
var tally: Array[int] = [0, 0]
var tally_mults: Array[int] = [1, 1]
## The HUD's score per seat: the last turn's total.
var held: Array[int] = [0, 0]


func reset() -> void:
	scores.assign([0, 0])
	mults.assign([1, 1])
	walking = false
	tally.assign([0, 0])
	tally_mults.assign([1, 1])
	held.assign([0, 0])


## Folds one step in; steps that carry no score are ignored.
func apply(step: BoardStep) -> void:
	match step.kind:
		BoardStep.Kind.WALK_START:
			scores.assign([0, 0])
			mults.assign([1, 1])
			tally.assign([0, 0])
			tally_mults.assign([1, 1])
			walking = true
		BoardStep.Kind.PULSE:
			_apply_pulse(step)
		BoardStep.Kind.TURN_END:
			scores.assign(step.scores)
			mults.assign([1, 1])
			held.assign(step.scores)
			tally.assign([0, 0])
			tally_mults.assign([1, 1])
			walking = false
		BoardStep.Kind.CLEAR_TABLE:
			reset()


func _apply_pulse(step: BoardStep) -> void:
	if step.seat < 0 or step.seat >= scores.size():
		return
	if step.destroyed:
		return
	if step.score >= 0:
		scores[step.seat] = step.score
		mults[step.seat] = step.mult
		tally[step.seat] = step.score
		tally_mults[step.seat] = step.mult
	else:
		# The engine sent no CARD_SCORED for this card: only its flat is known.
		scores[step.seat] += step.flat
		tally[step.seat] += step.flat
