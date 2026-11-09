class_name ScoreTracker
extends RefCounted
## The numbers the board shows (R77, R78, plan P17). `tally` is the walk's walking total per
## seat in ten-thousandths (shown beside the rows); `held` is the rounded Score the HUD shows;
## `piles` counts each seat's Pile. A walk start zeroes the tally; each scoring pulse sets its
## seat's tally to the engine's `CARD_SCORED.total`; the Walk end sets `held` to the engine's
## Scores and the tally to its totals; the turn end settles `held` again and clears the tally.
## Pure: no nodes.

## The walk's walking total per seat (ten-thousandths).
var tally: Array[int] = [0, 0]
## The walking total each seat held just before the Walk end settled it (ten-thousandths): the
## Walk-end multiply (Dross) shows as the step from this to `tally`.
var pre_end: Array[int] = [0, 0]
## Cards in each seat's Pile: grows at each Discard (its `pile_index` + 1) and empties at a
## shuffle-in. A Pile lasts the whole Match, so a table clear leaves it.
var piles: Array[int] = [0, 0]
## The HUD's Score per seat.
var held: Array[int] = [0, 0]


func reset() -> void:
	tally.assign([0, 0])
	pre_end.assign([0, 0])
	held.assign([0, 0])
	piles.assign([0, 0])


## Folds one step in; steps that carry no score are ignored.
func apply(step: BoardStep) -> void:
	match step.kind:
		BoardStep.Kind.WALK_START:
			tally.assign([0, 0])
			pre_end.assign([0, 0])
		BoardStep.Kind.PULSE:
			_apply_pulse(step)
		BoardStep.Kind.WALK_END:
			held.assign(step.scores)
			pre_end.assign(tally)
			if step.totals.size() == tally.size():
				tally.assign(step.totals)
		BoardStep.Kind.TURN_END:
			if step.scores.size() == held.size():
				held.assign(step.scores)
			tally.assign([0, 0])
		BoardStep.Kind.CLEAR_TABLE:
			tally.assign([0, 0])
		BoardStep.Kind.DISCARD:
			_grow_pile(step.seat, step.pile_index)
		BoardStep.Kind.EXIT:
			_grow_pile(step.seat, step.pile_index if step.exit_to == BoardStep.ExitTo.PILE else -1)
		BoardStep.Kind.DROSS_EXPIRE:
			if step.zone == TurnFlow.FROM_PILE:
				_empty_pile(step.seat, 1)  # The Dross card leaves the Pile itself (C13).
		BoardStep.Kind.SHUFFLE_IN:
			_empty_pile(step.seat, step.count)
		BoardStep.Kind.PLACE:
			if step.from_pile:
				_empty_pile(step.seat, 1)  # Revive takes one card out of the Pile.


func _grow_pile(seat: int, pile_index: int) -> void:
	if seat >= 0 and seat < piles.size() and pile_index >= 0:
		piles[seat] = maxi(piles[seat], pile_index + 1)


func _empty_pile(seat: int, count: int) -> void:
	if seat >= 0 and seat < piles.size():
		piles[seat] = maxi(piles[seat] - count, 0)


func _apply_pulse(step: BoardStep) -> void:
	if step.seat < 0 or step.seat >= tally.size():
		return
	# A pulse with no CARD_SCORED (a reveal paused on its prompt) leaves the tally as it is: it
	# holds until a score arrives (R35).
	if step.scored:
		tally[step.seat] = step.total


## The walking totals before the Walk end for the seats that held Dross (the engine's `dross`
## count per seat), else the settled tally: only a seat the Walk end multiplied shows a step.
func dross_before(dross: Array[int]) -> Array[int]:
	var out: Array[int] = []
	out.assign(tally)
	for seat: int in range(mini(dross.size(), out.size())):
		if dross[seat] > 0:
			out[seat] = pre_end[seat]
	return out
