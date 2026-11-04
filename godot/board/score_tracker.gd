class_name ScoreTracker
extends RefCounted
## The numbers the board shows (R32-R34, plan P11). `tally` and `tally_mults` are the walk's
## running score and multiplier per seat (shown beside the rows); `held` is the previous turn's
## total, the only number the HUD shows. A walk start zeroes the tally; each scoring pulse sets
## its seat's tally to the engine's values; the turn end moves the totals into `held` and clears
## the tally. `held` changes only at TURN_END or CLEAR_TABLE, so no half-walk number reaches the
## HUD. Pure: no nodes.

## The walk's running score and multiplier per seat.
var tally: Array[int] = [0, 0]
var tally_mults: Array[int] = [1, 1]
## The HUD's score per seat: the last turn's total.
var held: Array[int] = [0, 0]


func reset() -> void:
	tally.assign([0, 0])
	tally_mults.assign([1, 1])
	held.assign([0, 0])


## Folds one step in; steps that carry no score are ignored.
func apply(step: BoardStep) -> void:
	match step.kind:
		BoardStep.Kind.WALK_START:
			tally.assign([0, 0])
			tally_mults.assign([1, 1])
		BoardStep.Kind.PULSE:
			_apply_pulse(step)
		BoardStep.Kind.TURN_END:
			held.assign(step.scores)
			tally.assign([0, 0])
			tally_mults.assign([1, 1])
		BoardStep.Kind.CLEAR_TABLE:
			reset()


func _apply_pulse(step: BoardStep) -> void:
	if step.seat < 0 or step.seat >= tally.size():
		return
	if step.destroyed:
		return
	if step.score >= 0:
		tally[step.seat] = step.score
		tally_mults[step.seat] = step.mult
	else:
		# The engine sent no CARD_SCORED for this card: only its flat is known.
		tally[step.seat] += step.flat
