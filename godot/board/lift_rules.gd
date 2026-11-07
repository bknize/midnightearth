class_name LiftRules
extends RefCounted
## Pure rules for the card pick-up (R1, R2, R9, R11). No nodes, no scene access.

## CREW is a face-up Crew on a side's line: it lifts to read and never drags (cycle 8 R62).
enum Place { HAND, ROW, OPPONENT_ROW, OPPONENT_HAND, CREW }


## R1, R2, R11: may this card be lifted? Decided from the card's own state alone (its
## place and whether it is face up), so a later feature can widen the rule here without
## touching the board.
static func may_lift(_place: Place, face_up: bool) -> bool:
	return face_up


## The card a pointer hit stands for: the hit itself or its parent when that is a BoardCard.
static func card_from_hit(hit: Object) -> BoardCard:
	var node: Node = hit as Node
	if node == null:
		return null
	var card: BoardCard = node as BoardCard
	if card == null:
		card = node.get_parent() as BoardCard
	return card


## R9: would this step move, flip, mark, re-pulse or remove the held card? `held_id` is the engine
## instance id; `held_place` and `held_staged` describe the card now.
static func step_touches(
	step: BoardStep, held_id: int, held_place: Place, held_staged: bool
) -> bool:
	match step.kind:
		BoardStep.Kind.CLEAR_TABLE:
			return true
		BoardStep.Kind.PULSE:
			# Your own card's pulse; an opponent's card only on a re-pulse (`again`), since its
			# first reveal never touches a card being read (DC-04) (R37).
			return held_id >= 0 and step.card == held_id and (step.seat == 0 or step.again)
		BoardStep.Kind.STATS, BoardStep.Kind.STATUS:
			# Restat or re-badge: the step names the held card (R9).
			return held_id >= 0 and step.card == held_id
		BoardStep.Kind.UNREVEAL, BoardStep.Kind.EXIT:
			# Flip down, or leave the row for a Pile or a hand: the step names the held card.
			return held_id >= 0 and step.card == held_id
		BoardStep.Kind.RETURN, BoardStep.Kind.DISCARD:
			# Remove or send away: the step names the held card.
			return held_id >= 0 and step.card == held_id
		BoardStep.Kind.CREW_FIRE:
			# A Crew has no instance id: any firing sets a held Crew down first.
			return held_place == Place.CREW
		BoardStep.Kind.MOVE:
			return _moves_row_of(step, held_id, held_place)
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


## A swap reorders a whole row and its second half may name the other card, so any move on the
## row the held card sits on, or naming it, would move it.
static func _moves_row_of(step: BoardStep, held_id: int, held_place: Place) -> bool:
	if held_id >= 0 and (step.card == held_id or step.cards.has(held_id)):
		return true
	if step.seat == 0:
		return held_place == Place.ROW
	return held_place == Place.OPPONENT_ROW
