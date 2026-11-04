class_name LiftRules
extends RefCounted
## Pure rules for the card pick-up (R1, R2, R9, R11). No nodes, no scene access.

enum Place { HAND, ROW, OPPONENT_ROW, OPPONENT_HAND }


## R1, R2, R11: may this card be lifted? Decided from the card's own state alone (its
## place and whether it is face up), so a later feature can widen the rule here without
## touching the board.
static func may_lift(_place: Place, face_up: bool) -> bool:
	return face_up


## R9: would this step move, flip or remove the held card? `held_id` is the engine
## instance id; `held_place` and `held_staged` describe the card now.
static func step_touches(
	step: BoardStep, held_id: int, held_place: Place, held_staged: bool
) -> bool:
	match step.kind:
		BoardStep.Kind.CLEAR_TABLE:
			return true
		BoardStep.Kind.PULSE:
			return step.seat == 0 and step.card == held_id
		BoardStep.Kind.TURN_START:
			return held_staged
		BoardStep.Kind.PLAYER_COMMIT:
			# The commit moves a held hand card and flips a held staged card on the row.
			var on_table: bool = held_place == Place.HAND or held_place == Place.ROW
			if step.seat != 0 or not on_table or step.source == null:
				return false
			var raw: Array = step.source.payload["cards"]
			var ids: Array[int] = []
			ids.assign(raw)
			return ids.has(held_id)
	return false
