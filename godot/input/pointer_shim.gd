class_name PointerShim
extends Node
## Thin node around PointerTracker (R21-R25, R28): feeds it _input, turns app focus loss
## into a cancel, raycasts the camera and emits one signal per pointer event.
##
## Press, release, tap, move and hover hits are found with card_mask; call ray_hit() with
## drop_zone_mask for the drop zone under the pointer. No dependency on the board (C5).

signal pressed(position: Vector2, hit: Object)
signal drag_started(position: Vector2, from_touch: bool)
signal drag_moved(position: Vector2, hit: Object)
signal released(position: Vector2, hit: Object)
signal tapped(position: Vector2, hit: Object)
signal cancelled
## Real mouse only (R28).
signal hovered(hit: Object)

const RAY_LENGTH: float = 1000.0

@export var camera: Camera3D
@export_flags_3d_physics var card_mask: int = 1
@export_flags_3d_physics var drop_zone_mask: int = 2

## True when the latest pointer event came from touch rather than a real mouse.
var last_from_touch: bool:
	get:
		return _last_from_touch

## Viewport units per point, for lift offsets and thresholds.
var units_per_point: float:
	get:
		return _tracker.units_per_point

var _tracker: PointerTracker = PointerTracker.new()
var _last_from_touch: bool = false


func _ready() -> void:
	_update_units_per_point()
	var err: int = get_viewport().size_changed.connect(_update_units_per_point)
	if err != OK:
		push_warning("PointerShim: could not watch viewport size (%d)" % err)


func _input(event: InputEvent) -> void:
	_dispatch(_tracker.feed(event))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dispatch(_tracker.focus_lost())


## Ends any press in progress: the next release emits nothing and `cancelled` fires once.
func cancel() -> void:
	_dispatch(_tracker.cancel())


## The collider of the first body on mask under the viewport position, or null.
func ray_hit(position: Vector2, mask: int) -> Object:
	if camera == null or not camera.is_inside_tree():
		return null
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	if space == null:
		return null
	var from: Vector3 = camera.project_ray_origin(position)
	var to: Vector3 = from + camera.project_ray_normal(position) * RAY_LENGTH
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask)
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return null
	var collider: Object = result.get("collider")
	return collider


func _dispatch(events: Array[PointerEvent]) -> void:
	for e: PointerEvent in events:
		if e.kind != PointerEvent.Kind.CANCEL:
			_last_from_touch = e.from_touch
		match e.kind:
			PointerEvent.Kind.PRESS:
				pressed.emit(e.position, ray_hit(e.position, card_mask))
			PointerEvent.Kind.DRAG_START:
				drag_started.emit(e.position, e.from_touch)
			PointerEvent.Kind.DRAG_MOVE:
				drag_moved.emit(e.position, ray_hit(e.position, card_mask))
			PointerEvent.Kind.RELEASE:
				released.emit(e.position, ray_hit(e.position, card_mask))
			PointerEvent.Kind.TAP:
				tapped.emit(e.position, ray_hit(e.position, card_mask))
			PointerEvent.Kind.CANCEL:
				cancelled.emit()
			PointerEvent.Kind.HOVER:
				hovered.emit(ray_hit(e.position, card_mask))


func _update_units_per_point() -> void:
	var window: Window = get_window()
	var window_height: int = 0
	if window != null:
		window_height = window.size.y
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	if window_height <= 0 or viewport_height <= 0.0:
		_tracker.units_per_point = 1.0
		return
	_tracker.units_per_point = (
		DisplayServer.screen_get_scale() * viewport_height / float(window_height)
	)
