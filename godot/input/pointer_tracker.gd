class_name PointerTracker
extends RefCounted
## Pure pointer state machine (R21-R25, R28): turns Godot input events into PointerEvents.
##
## Source stream: mouse button 1 and mouse motion only. A mouse event whose device is
## InputEvent.DEVICE_ID_EMULATION is touch (from_touch = true); any other is a real mouse.
## Raw InputEventScreenTouch / InputEventScreenDrag never move the pointer (R23): Godot
## sends the emulated mouse event first and the raw duplicate after it. Raw touch is read
## only to cancel a held press (R25).
##
## Held state comes from press and release events, never from button_mask (R22), so
## motion with mask 0 while held still drags.

## Touch position Godot reports when iOS cancels a touch (R25).
const CANCEL_POSITION: Vector2 = Vector2(-1.0, -1.0)

## Viewport units per point; the shim sets it from the screen scale (R24).
var units_per_point: float = 1.0
## Distance in points the pointer must move from the press before a drag starts (R24).
var drag_threshold_points: float = 8.0

var _held: bool = false
var _dragging: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _press_from_touch: bool = false
## A press the GUI took: it and the motion and release after it emit nothing (R25).
var _blocked: bool = false


func is_held() -> bool:
	return _held


## Feeds one input event; returns the pointer events it produces, in order. The shim passes
## gui_blocked = true for a press over a Control that takes the mouse (R25).
func feed(event: InputEvent, gui_blocked: bool = false) -> Array[PointerEvent]:
	var out: Array[PointerEvent] = []
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		_feed_button(button, gui_blocked, out)
		return out
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if not _blocked:
			_feed_motion(motion, out)
		return out
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and gui_blocked:
			_blocked = true
		elif not _blocked:
			_feed_raw_touch(touch, out)
	# InputEventScreenDrag and everything else never produce events.
	return out


## The application lost focus: a held press is cancelled (R25).
func focus_lost() -> Array[PointerEvent]:
	var out: Array[PointerEvent] = []
	if _held:
		_cancel(Vector2.ZERO, out)
	return out


## Cancels a held press from code (a pause menu opening, say); empty when not held.
func cancel() -> Array[PointerEvent]:
	var out: Array[PointerEvent] = []
	if _held:
		_cancel(Vector2.ZERO, out)
	return out


func _feed_button(
	event: InputEventMouseButton, gui_blocked: bool, out: Array[PointerEvent]
) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_feed_press(event, gui_blocked, out)
		return
	if _blocked:
		_blocked = false
		return
	if not _held:
		return
	if event.position == CANCEL_POSITION:
		_cancel(event.position, out)
		return
	var kind: PointerEvent.Kind = PointerEvent.Kind.TAP
	if _dragging:
		kind = PointerEvent.Kind.RELEASE
	out.append(PointerEvent.new(kind, event.position, _press_from_touch))
	_clear()


## A left-button press: starts a gesture, or blocks it when the GUI took the press (R25).
func _feed_press(
	event: InputEventMouseButton, gui_blocked: bool, out: Array[PointerEvent]
) -> void:
	if _held:
		return
	_blocked = gui_blocked
	if _blocked:
		return
	var touch: bool = event.device == InputEvent.DEVICE_ID_EMULATION
	_held = true
	_dragging = false
	_press_position = event.position
	_press_from_touch = touch
	out.append(PointerEvent.new(PointerEvent.Kind.PRESS, event.position, touch))


func _feed_motion(event: InputEventMouseMotion, out: Array[PointerEvent]) -> void:
	var touch: bool = event.device == InputEvent.DEVICE_ID_EMULATION
	if not _held:
		if not touch:
			out.append(PointerEvent.new(PointerEvent.Kind.HOVER, event.position, false))
		return
	if _dragging:
		out.append(PointerEvent.new(PointerEvent.Kind.DRAG_MOVE, event.position, _press_from_touch))
		return
	var threshold: float = drag_threshold_points * units_per_point
	if event.position.distance_to(_press_position) > threshold:
		_dragging = true
		out.append(
			PointerEvent.new(PointerEvent.Kind.DRAG_START, event.position, _press_from_touch)
		)


func _feed_raw_touch(event: InputEventScreenTouch, out: Array[PointerEvent]) -> void:
	if not _held:
		return
	var second_finger: bool = event.pressed and event.index != 0
	var os_release: bool = not event.pressed and event.position == CANCEL_POSITION
	if second_finger or os_release or event.canceled:
		_cancel(event.position, out)


func _cancel(position: Vector2, out: Array[PointerEvent]) -> void:
	out.append(PointerEvent.new(PointerEvent.Kind.CANCEL, position, _press_from_touch))
	_clear()


func _clear() -> void:
	_held = false
	_dragging = false
