class_name BoardDragStrategy
extends DragStrategy
## Who may drag what on the board (R11-R14, R18, R19). One instance per collection, each
## with a role. The board supplies the questions as callables, so this holds no board
## reference:
##   can_act()        -> bool   the player may act now (R18)
##   is_locked()      -> bool   a step is queued or running
##   can_afford(card) -> bool   the card fits in the energy left (R14)
##   is_staged(card)  -> bool   the card is staged, not yet committed
## An unset callable answers false (is_locked answers true).

enum Role { PLAYER_HAND, PLAYER_ROW, OPPONENT }

var role: Role = Role.OPPONENT
var can_act: Callable = Callable()
var is_locked: Callable = Callable()
var can_afford: Callable = Callable()
var is_staged: Callable = Callable()


func can_select_card(card: Variant, _to_collection: CardCollection3D) -> bool:
	match role:
		Role.PLAYER_HAND:
			return _act()
		Role.PLAYER_ROW:
			return _act() and _staged(card)
	return false


## The target of a drag is not passed here, so "row back to hand only" is enforced by the
## hand's can_insert_card.
func can_remove_card(_card: Variant, _to_collection: CardCollection3D) -> bool:
	match role:
		Role.PLAYER_HAND, Role.PLAYER_ROW:
			return _act()
	return false


func can_reorder_card(card: Variant, _to_collection: CardCollection3D) -> bool:
	match role:
		Role.PLAYER_HAND:
			return not _locked()
		Role.PLAYER_ROW:
			# A hand card that cannot be afforded gets no gap on the row (R14).
			return _act() and (_staged(card) or _affordable(card))
	return false


func can_insert_card(
	card: Variant, _to_collection: CardCollection3D, from_collection: CardCollection3D
) -> bool:
	var from_role: Role = _role_of(from_collection)
	match role:
		Role.PLAYER_HAND:
			return from_role == Role.PLAYER_ROW and _act()
		Role.PLAYER_ROW:
			return from_role == Role.PLAYER_HAND and _act() and _affordable(card)
	return false


func _role_of(collection: CardCollection3D) -> Role:
	if collection == null:
		return Role.OPPONENT
	var other: BoardDragStrategy = collection.drag_strategy as BoardDragStrategy
	if other == null:
		return Role.OPPONENT
	return other.role


func _act() -> bool:
	if can_act.is_null():
		return false
	var ok: bool = can_act.call()
	return ok


func _locked() -> bool:
	if is_locked.is_null():
		return true
	var locked: bool = is_locked.call()
	return locked


func _affordable(card: Variant) -> bool:
	if can_afford.is_null():
		return false
	var ok: bool = can_afford.call(card)
	return ok


func _staged(card: Variant) -> bool:
	if is_staged.is_null():
		return false
	var ok: bool = is_staged.call(card)
	return ok
