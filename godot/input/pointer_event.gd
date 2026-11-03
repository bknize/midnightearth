class_name PointerEvent
extends RefCounted
## One normalized pointer event, produced by PointerTracker (R21).
##
## Positions are viewport units. from_touch is true when the event comes from a touch
## (a mouse event emulated from the first finger), false for a real mouse.

enum Kind { PRESS, DRAG_START, DRAG_MOVE, RELEASE, TAP, CANCEL, HOVER }

var kind: Kind = Kind.PRESS
var position: Vector2 = Vector2.ZERO
var from_touch: bool = false


func _init(
	new_kind: Kind = Kind.PRESS, new_position: Vector2 = Vector2.ZERO, new_from_touch: bool = false
) -> void:
	kind = new_kind
	position = new_position
	from_touch = new_from_touch
