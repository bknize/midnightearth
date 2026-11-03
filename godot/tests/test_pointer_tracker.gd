# gdlint: disable=max-public-methods
class_name TestPointerTracker
extends GdUnitTestSuite
## The pointer shim's state machine (R21-R25) and its hover rule (R28), tested on
## PointerTracker alone with synthesized mouse, emulated-mouse and screen-touch events.
## The PointerShim node (raycast, signals, focus notification) is verified in the running
## game, never here.

const START: Vector2 = Vector2(100.0, 100.0)
## Ten units from START: past the default 8-point threshold at 1 unit per point.
const FAR: Vector2 = Vector2(110.0, 100.0)
## Five units from START: inside the default threshold.
const NEAR: Vector2 = Vector2(105.0, 100.0)


func _mouse_button(position: Vector2, pressed: bool, touch: bool) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = position
	if touch:
		e.device = InputEvent.DEVICE_ID_EMULATION
	return e


func _mouse_motion(position: Vector2, touch: bool, mask: int = 0) -> InputEventMouseMotion:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = position
	e.button_mask = mask
	if touch:
		e.device = InputEvent.DEVICE_ID_EMULATION
	return e


func _screen_touch(
	position: Vector2, pressed: bool, index: int = 0, canceled: bool = false
) -> InputEventScreenTouch:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.position = position
	e.pressed = pressed
	e.index = index
	e.canceled = canceled
	return e


func _kinds(events: Array[PointerEvent]) -> Array[PointerEvent.Kind]:
	var out: Array[PointerEvent.Kind] = []
	for e: PointerEvent in events:
		out.append(e.kind)
	return out


func _expect(events: Array[PointerEvent], expected: Array[PointerEvent.Kind]) -> void:
	assert_array(_kinds(events)).is_equal(expected)


## Presses at START and returns the tracker, so a test starts with a held press.
func _held_tracker(touch: bool = false) -> PointerTracker:
	var tracker: PointerTracker = PointerTracker.new()
	var events: Array[PointerEvent] = tracker.feed(_mouse_button(START, true, touch))
	_expect(events, [PointerEvent.Kind.PRESS])
	return tracker


# R21 -------------------------------------------------------------------------------------


func test_press_drag_move_release_sequence() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	var press: Array[PointerEvent] = tracker.feed(_mouse_button(START, true, false))
	_expect(press, [PointerEvent.Kind.PRESS])
	assert_vector(press[0].position).is_equal(START)
	assert_bool(press[0].from_touch).is_false()
	assert_bool(tracker.is_held()).is_true()

	_expect(tracker.feed(_mouse_motion(FAR, false)), [PointerEvent.Kind.DRAG_START])
	var later: Vector2 = Vector2(150.0, 120.0)
	var moved: Array[PointerEvent] = tracker.feed(_mouse_motion(later, false))
	_expect(moved, [PointerEvent.Kind.DRAG_MOVE])
	assert_vector(moved[0].position).is_equal(later)
	_expect(tracker.feed(_mouse_motion(FAR, false)), [PointerEvent.Kind.DRAG_MOVE])

	var release: Array[PointerEvent] = tracker.feed(_mouse_button(FAR, false, false))
	_expect(release, [PointerEvent.Kind.RELEASE])
	assert_vector(release[0].position).is_equal(FAR)
	assert_bool(tracker.is_held()).is_false()


func test_emulated_mouse_marks_events_as_touch() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	var press: Array[PointerEvent] = tracker.feed(_mouse_button(START, true, true))
	assert_bool(press[0].from_touch).is_true()
	var start: Array[PointerEvent] = tracker.feed(_mouse_motion(FAR, true))
	assert_bool(start[0].from_touch).is_true()
	var moved: Array[PointerEvent] = tracker.feed(_mouse_motion(FAR + Vector2.ONE, true))
	assert_bool(moved[0].from_touch).is_true()
	var release: Array[PointerEvent] = tracker.feed(_mouse_button(FAR, false, true))
	assert_bool(release[0].from_touch).is_true()


func test_other_mouse_buttons_are_ignored() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	var right: InputEventMouseButton = _mouse_button(START, true, false)
	right.button_index = MOUSE_BUTTON_RIGHT
	_expect(tracker.feed(right), [])
	assert_bool(tracker.is_held()).is_false()


func test_unrelated_events_produce_nothing() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(InputEventKey.new()), [])
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.position = START
	_expect(tracker.feed(drag), [])


# R22 -------------------------------------------------------------------------------------


func test_motion_with_mask_zero_while_held_still_drags() -> void:
	var tracker: PointerTracker = _held_tracker()
	_expect(tracker.feed(_mouse_motion(FAR, false, 0)), [PointerEvent.Kind.DRAG_START])
	_expect(tracker.feed(_mouse_motion(FAR + Vector2.ONE, false, 0)), [PointerEvent.Kind.DRAG_MOVE])


func test_motion_with_mask_set_while_unheld_does_not_drag() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	var events: Array[PointerEvent] = tracker.feed(
		_mouse_motion(FAR, false, MOUSE_BUTTON_MASK_LEFT)
	)
	_expect(events, [PointerEvent.Kind.HOVER])
	assert_bool(tracker.is_held()).is_false()


func test_release_without_press_is_ignored() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(_mouse_button(START, false, false)), [])


# R23 -------------------------------------------------------------------------------------


func test_emulated_press_then_raw_touch_duplicate_yields_one_press() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	var events: Array[PointerEvent] = []
	events.append_array(tracker.feed(_mouse_button(START, true, true)))
	events.append_array(tracker.feed(_screen_touch(START, true)))
	_expect(events, [PointerEvent.Kind.PRESS])
	assert_bool(tracker.is_held()).is_true()


func test_emulated_release_then_raw_touch_duplicate_yields_one_tap() -> void:
	var tracker: PointerTracker = _held_tracker(true)
	var events: Array[PointerEvent] = []
	events.append_array(tracker.feed(_mouse_button(START, false, true)))
	events.append_array(tracker.feed(_screen_touch(START, false)))
	_expect(events, [PointerEvent.Kind.TAP])
	assert_bool(tracker.is_held()).is_false()


func test_raw_touch_never_presses_moves_or_releases() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(_screen_touch(START, true)), [])
	assert_bool(tracker.is_held()).is_false()
	_expect(tracker.feed(_screen_touch(START, false)), [])

	var held: PointerTracker = _held_tracker(true)
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.position = FAR
	_expect(held.feed(drag), [])
	_expect(held.feed(_screen_touch(FAR, false)), [])
	assert_bool(held.is_held()).is_true()


# R24 -------------------------------------------------------------------------------------


func test_release_before_threshold_is_a_tap() -> void:
	var tracker: PointerTracker = _held_tracker()
	_expect(tracker.feed(_mouse_motion(NEAR, false)), [])
	var release: Array[PointerEvent] = tracker.feed(_mouse_button(NEAR, false, false))
	_expect(release, [PointerEvent.Kind.TAP])
	assert_vector(release[0].position).is_equal(NEAR)
	assert_bool(tracker.is_held()).is_false()


func test_release_after_threshold_is_a_release_not_a_tap() -> void:
	var tracker: PointerTracker = _held_tracker()
	tracker.feed(_mouse_motion(FAR, false))
	_expect(tracker.feed(_mouse_button(NEAR, false, false)), [PointerEvent.Kind.RELEASE])


func test_threshold_is_more_than_not_equal() -> void:
	var tracker: PointerTracker = _held_tracker()
	_expect(tracker.feed(_mouse_motion(START + Vector2(8.0, 0.0), false)), [])
	_expect(
		tracker.feed(_mouse_motion(START + Vector2(8.5, 0.0), false)),
		[PointerEvent.Kind.DRAG_START]
	)


func test_threshold_scales_with_units_per_point() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	tracker.units_per_point = 3.0
	tracker.feed(_mouse_button(START, true, true))
	# 20 units is past 8 points at 1x but inside 8 points at 3x (24 units).
	_expect(tracker.feed(_mouse_motion(START + Vector2(20.0, 0.0), true)), [])
	_expect(
		tracker.feed(_mouse_motion(START + Vector2(25.0, 0.0), true)),
		[PointerEvent.Kind.DRAG_START]
	)


func test_threshold_uses_drag_threshold_points() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	tracker.drag_threshold_points = 2.0
	tracker.feed(_mouse_button(START, true, false))
	_expect(
		tracker.feed(_mouse_motion(START + Vector2(3.0, 0.0), false)),
		[PointerEvent.Kind.DRAG_START]
	)


func test_threshold_is_measured_from_the_press_not_the_last_motion() -> void:
	var tracker: PointerTracker = _held_tracker()
	_expect(tracker.feed(_mouse_motion(START + Vector2(5.0, 0.0), false)), [])
	_expect(tracker.feed(_mouse_motion(START + Vector2(7.0, 0.0), false)), [])
	_expect(
		tracker.feed(_mouse_motion(START + Vector2(9.0, 0.0), false)),
		[PointerEvent.Kind.DRAG_START]
	)


func test_a_new_press_after_a_drag_starts_fresh() -> void:
	var tracker: PointerTracker = _held_tracker()
	tracker.feed(_mouse_motion(FAR, false))
	tracker.feed(_mouse_button(FAR, false, false))
	_expect(tracker.feed(_mouse_button(START, true, false)), [PointerEvent.Kind.PRESS])
	_expect(tracker.feed(_mouse_motion(NEAR, false)), [])
	_expect(tracker.feed(_mouse_button(NEAR, false, false)), [PointerEvent.Kind.TAP])


# R25 -------------------------------------------------------------------------------------


func test_second_finger_press_cancels() -> void:
	var tracker: PointerTracker = _held_tracker(true)
	_expect(tracker.feed(_screen_touch(FAR, true, 1)), [PointerEvent.Kind.CANCEL])
	assert_bool(tracker.is_held()).is_false()
	# The first finger lifting afterwards is not a release.
	_expect(tracker.feed(_mouse_button(START, false, true)), [])


func test_second_finger_press_cancels_a_drag_in_progress() -> void:
	var tracker: PointerTracker = _held_tracker(true)
	tracker.feed(_mouse_motion(FAR, true))
	_expect(tracker.feed(_screen_touch(FAR, true, 1)), [PointerEvent.Kind.CANCEL])
	assert_bool(tracker.is_held()).is_false()
	_expect(tracker.feed(_mouse_motion(FAR + Vector2.ONE, true)), [])


func test_first_finger_raw_press_does_not_cancel() -> void:
	var tracker: PointerTracker = _held_tracker(true)
	_expect(tracker.feed(_screen_touch(START, true, 0)), [])
	assert_bool(tracker.is_held()).is_true()


func test_raw_release_at_minus_one_cancels() -> void:
	var tracker: PointerTracker = _held_tracker(true)
	_expect(tracker.feed(_screen_touch(Vector2(-1.0, -1.0), false)), [PointerEvent.Kind.CANCEL])
	assert_bool(tracker.is_held()).is_false()


func test_mouse_release_at_minus_one_cancels() -> void:
	var tracker: PointerTracker = _held_tracker(true)
	var events: Array[PointerEvent] = []
	events.append_array(tracker.feed(_mouse_button(Vector2(-1.0, -1.0), false, true)))
	events.append_array(tracker.feed(_screen_touch(Vector2(-1.0, -1.0), false)))
	_expect(events, [PointerEvent.Kind.CANCEL])
	assert_bool(tracker.is_held()).is_false()


func test_canceled_flag_cancels() -> void:
	var tracker: PointerTracker = _held_tracker(true)
	_expect(tracker.feed(_screen_touch(START, false, 0, true)), [PointerEvent.Kind.CANCEL])
	assert_bool(tracker.is_held()).is_false()


func test_focus_lost_while_held_cancels() -> void:
	var tracker: PointerTracker = _held_tracker()
	_expect(tracker.focus_lost(), [PointerEvent.Kind.CANCEL])
	assert_bool(tracker.is_held()).is_false()
	_expect(tracker.feed(_mouse_button(START, false, false)), [])


func test_focus_lost_while_dragging_cancels() -> void:
	var tracker: PointerTracker = _held_tracker()
	tracker.feed(_mouse_motion(FAR, false))
	_expect(tracker.focus_lost(), [PointerEvent.Kind.CANCEL])
	assert_bool(tracker.is_held()).is_false()


func test_focus_lost_when_not_held_is_empty() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.focus_lost(), [])


func test_cancel_while_held_emits_one_cancel_then_release_is_silent() -> void:
	var tracker: PointerTracker = _held_tracker()
	tracker.feed(_mouse_motion(FAR, false))
	_expect(tracker.cancel(), [PointerEvent.Kind.CANCEL])
	assert_bool(tracker.is_held()).is_false()
	_expect(tracker.feed(_mouse_button(FAR, false, false)), [])


func test_cancel_when_not_held_is_empty() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.cancel(), [])


func test_cancel_events_for_stray_touch_when_not_held_are_ignored() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(_screen_touch(START, true, 1)), [])
	_expect(tracker.feed(_screen_touch(Vector2(-1.0, -1.0), false)), [])
	_expect(tracker.feed(_screen_touch(START, false, 0, true)), [])


func test_press_after_a_cancel_works() -> void:
	var tracker: PointerTracker = _held_tracker(true)
	tracker.focus_lost()
	_expect(tracker.feed(_mouse_button(START, true, true)), [PointerEvent.Kind.PRESS])
	assert_bool(tracker.is_held()).is_true()


# R28 -------------------------------------------------------------------------------------


func test_real_mouse_motion_while_unheld_hovers() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	var events: Array[PointerEvent] = tracker.feed(_mouse_motion(FAR, false))
	_expect(events, [PointerEvent.Kind.HOVER])
	assert_vector(events[0].position).is_equal(FAR)
	assert_bool(events[0].from_touch).is_false()


func test_emulated_motion_while_unheld_never_hovers() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(_mouse_motion(FAR, true)), [])


func test_real_mouse_motion_while_held_does_not_hover() -> void:
	var tracker: PointerTracker = _held_tracker()
	_expect(tracker.feed(_mouse_motion(NEAR, false)), [])
	tracker.feed(_mouse_motion(FAR, false))
	_expect(tracker.feed(_mouse_motion(FAR + Vector2.ONE, false)), [PointerEvent.Kind.DRAG_MOVE])


func test_hover_resumes_after_release() -> void:
	var tracker: PointerTracker = _held_tracker()
	tracker.feed(_mouse_button(START, false, false))
	_expect(tracker.feed(_mouse_motion(FAR, false)), [PointerEvent.Kind.HOVER])


func test_blocked_press_emits_nothing_through_release() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(_mouse_button(START, true, false), true), [])
	assert_bool(tracker.is_held()).is_false()
	_expect(tracker.feed(_mouse_motion(FAR, false)), [])
	_expect(tracker.feed(_mouse_button(FAR, false, false)), [])


func test_press_after_blocked_press_works_normally() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	var blocked: Array[PointerEvent] = tracker.feed(_mouse_button(START, true, false), true)
	_expect(blocked, [])
	_expect(tracker.feed(_mouse_button(START, false, false)), [])
	_expect(tracker.feed(_mouse_button(START, true, false)), [PointerEvent.Kind.PRESS])
	_expect(tracker.feed(_mouse_motion(FAR, false)), [PointerEvent.Kind.DRAG_START])
	_expect(tracker.feed(_mouse_button(FAR, false, false)), [PointerEvent.Kind.RELEASE])
	_expect(tracker.feed(_mouse_button(START, true, false)), [PointerEvent.Kind.PRESS])
	_expect(tracker.feed(_mouse_button(START, false, false)), [PointerEvent.Kind.TAP])


func test_touch_duplicate_of_blocked_press_is_blocked() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(_mouse_button(START, true, true), true), [])
	_expect(tracker.feed(_screen_touch(START, true)), [])
	_expect(tracker.feed(_mouse_motion(FAR, true)), [])
	_expect(tracker.feed(_mouse_button(FAR, false, true)), [])
	_expect(tracker.feed(_screen_touch(FAR, false)), [])
	assert_bool(tracker.is_held()).is_false()


func test_focus_lost_clears_a_blocked_press() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(_mouse_button(START, true, false), true), [])
	_expect(tracker.focus_lost(), [])
	_expect(tracker.feed(_mouse_motion(FAR, false)), [PointerEvent.Kind.HOVER])


func test_cancel_clears_a_blocked_press() -> void:
	var tracker: PointerTracker = PointerTracker.new()
	_expect(tracker.feed(_mouse_button(START, true, false), true), [])
	_expect(tracker.cancel(), [])
	_expect(tracker.feed(_mouse_motion(FAR, false)), [PointerEvent.Kind.HOVER])
