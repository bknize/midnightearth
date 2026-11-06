class_name RowTargets
extends RefCounted
## Pure lookups from a step to the table spot it names (plan P18). Zone names are relative
## to the step's seat; spots are absolute (seat 0 is the viewer). No nodes, no scene access.

const OWN_HAND: String = "own_hand"
const OWN_BOARD: String = "own_board"
const OPPONENT_HAND: String = "opponent_hand"
const OPPONENT_BOARD: String = "opponent_board"
const BOTH_BOARDS: String = "both_boards"


## The seat across the table from `seat`.
static func other(seat: int) -> int:
	return 1 - seat


## The spot a zone name and index name for the seat that was asked. `both_boards` is one flat
## list: the asked seat's row in slot order, then the other seat's, so `own_size` (the asked
## seat's row size) splits it. An unknown zone gives an invalid spot.
static func resolve(zone: String, chooser: int, index: int, own_size: int) -> CardSpot:
	match zone:
		OWN_HAND:
			return CardSpot.new(chooser, true, index)
		OWN_BOARD:
			return CardSpot.new(chooser, false, index)
		OPPONENT_HAND:
			return CardSpot.new(other(chooser), true, index)
		OPPONENT_BOARD:
			return CardSpot.new(other(chooser), false, index)
		BOTH_BOARDS:
			if index < own_size:
				return CardSpot.new(chooser, false, index)
			return CardSpot.new(other(chooser), false, index - own_size)
	return CardSpot.new()


## The row spot a move (its source slot), return or pulse step names, or an invalid spot
## for kinds that name none. A step without a slot names the seat only.
static func row_spot(step: BoardStep) -> CardSpot:
	match step.kind:
		BoardStep.Kind.MOVE:
			return CardSpot.new(step.seat, false, step.from_slot)
		BoardStep.Kind.RETURN, BoardStep.Kind.PULSE:
			return CardSpot.new(step.seat, false, step.slot)
	return CardSpot.new()
