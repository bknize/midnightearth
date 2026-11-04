class_name ScoreTracker
extends RefCounted
## The numbers the board shows (R32-R34, plan P11). `tally` and `tally_mults` are the walk's
## running score and multiplier per seat (shown beside the rows); `held` is the previous turn's
## total, the only number the HUD shows. A walk start zeroes the tally; each scoring pulse sets
## its seat's tally to the engine's values; the turn end moves the totals into `held` and clears
## the tally. `held` changes only at TURN_END or CLEAR_TABLE, so no half-walk number reaches the
## HUD. Pure: no nodes.

## A mult of x1.00, in hundredths.
const MULT_ONE: int = 100

## The walk's running score and multiplier (hundredths) per seat.
var tally: Array[int] = [0, 0]
var tally_mults: Array[int] = [MULT_ONE, MULT_ONE]
## Cards in each seat's destroyed pile: grows at DESTROYED_CLEARED, shrinks at RECOVER, and
## empties at CLEAR_TABLE (round start burns the piles).
var destroyed: Array[int] = [0, 0]
## The HUD's score per seat: the last turn's total.
var held: Array[int] = [0, 0]


func reset() -> void:
	tally.assign([0, 0])
	tally_mults.assign([MULT_ONE, MULT_ONE])
	held.assign([0, 0])
	destroyed.assign([0, 0])


## Folds one step in; steps that carry no score are ignored.
func apply(step: BoardStep) -> void:
	match step.kind:
		BoardStep.Kind.WALK_START:
			tally.assign([0, 0])
			tally_mults.assign([MULT_ONE, MULT_ONE])
		BoardStep.Kind.PULSE:
			_apply_pulse(step)
		BoardStep.Kind.TURN_END:
			held.assign(step.scores)
			tally.assign([0, 0])
			tally_mults.assign([MULT_ONE, MULT_ONE])
		BoardStep.Kind.CLEAR_TABLE:
			reset()
		BoardStep.Kind.CLEAR_DESTROYED:
			_count_pile(step.seat, 1 if step.pile else 0)
		BoardStep.Kind.RECOVER:
			_count_pile(step.from_seat, -1)


func _count_pile(seat: int, change: int) -> void:
	if seat >= 0 and seat < destroyed.size():
		destroyed[seat] = maxi(destroyed[seat] + change, 0)


func _apply_pulse(step: BoardStep) -> void:
	if step.seat < 0 or step.seat >= tally.size():
		return
	if step.destroyed:
		return
	# A pulse with no CARD_SCORED (a reveal paused on its prompt, or a card destroyed before
	# its score) leaves the tally as it is: it holds until a score arrives (R35).
	if step.score >= 0:
		tally[step.seat] = step.score
		tally_mults[step.seat] = step.mult
