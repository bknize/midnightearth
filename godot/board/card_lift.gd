class_name CardLift
extends Node
## The card pick-up (R1-R11): a stand-in copy of the real card flies out of its slot to fill the
## view over a dimmed table, and flies back to the slot's current place when put down. The real
## card stays in its collection, hidden, so its slot stays open (P1).
##
## Motion is driven from _process, not tweens or timers, so a put-down always completes or is
## cut short by drop_now() / leaving the tree, and an awaiting caller never leaks.

## Emitted when a card is picked up.
signal lifted(card: BoardCard)
## Emitted when a put-down (or drop_now) has finished. The card is null if it was freed.
signal put_down_finished(card: BoardCard)
## Internal: a put-down ended; resumes anything awaiting put_down().
signal settled

enum Mode { IDLE, LIFTING, HOLDING, PUTTING }

const LIFT_TIME: float = 0.25
const PUT_DOWN_TIME: float = 0.2
const CARD_HEIGHT: float = 3.5
const LIFT_FILL: float = 0.9
const DIMMER_ALPHA: float = 0.6
## The dimmer sits this far behind the lift pose.
const DIMMER_GAP: float = 0.5
## The dimmer quad is this many view-heights wide and tall at its distance.
const DIMMER_COVER: float = 5.0

## The real card being held, or null.
var held: BoardCard = null

## The dimmer's alpha when nothing is held: 0, or the prompt's dim (R55) while one is open.
var _rest_alpha: float = 0.0
## The share of the view height the lifted card fills; smaller when a button sits under it.
var _fill: float = LIFT_FILL
var _mode: Mode = Mode.IDLE
var _stand_in: BoardCard = null
## True while the stand-in shows the face of a face-down card (R45).
var _flipped_up: bool = false
var _camera: Camera3D = null
var _loose: Node3D = null
var _dimmer: MeshInstance3D = null
var _spawn: Callable = Callable()
var _elapsed: float = 0.0
var _duration: float = 0.0
var _from: Transform3D = Transform3D()
var _alpha_from: float = 0.0
var _alpha_to: float = 0.0


func setup(camera: Camera3D, loose: Node3D, dimmer: MeshInstance3D, spawn: Callable) -> void:
	_camera = camera
	_loose = loose
	_dimmer = dimmer
	_spawn = spawn
	_set_alpha(0.0)


func _process(delta: float) -> void:
	if _mode != Mode.LIFTING and _mode != Mode.PUTTING:
		return
	_elapsed += delta
	var k: float = 1.0 if _duration <= 0.0 else minf(_elapsed / _duration, 1.0)
	var inv: float = 1.0 - k
	var eased: float = 1.0 - inv * inv * inv
	if _mode == Mode.PUTTING and not is_instance_valid(held):
		push_warning("CardLift: the held card was freed during a put-down")
		_finish()
		return
	if is_instance_valid(_stand_in):
		_stand_in.global_transform = _from.interpolate_with(_target(), eased)
	_set_alpha(lerpf(_alpha_from, _alpha_to, eased))
	if k >= 1.0:
		_arrived()


func _exit_tree() -> void:
	if _mode != Mode.IDLE:
		drop_now()


## Dims the table to `alpha` while no card is held, and a put-down fades back to it instead
## of to nothing (R55). 0 clears it. Safe mid-lift: the held card keeps the full dim.
func set_rest_alpha(alpha: float) -> void:
	_rest_alpha = alpha
	if _dimmer == null:
		return
	if alpha > 0.0:
		_place_dimmer()
	if _mode == Mode.IDLE:
		_set_alpha(alpha)


func is_holding() -> bool:
	return held != null


## Picks the card up. Does nothing if a card is already held. `show_face` turns a face-down
## card of the player's own face up in the lift (R45); it flips back down on put-down.
## `with_button` leaves room under the card for the prompt's action button (NSC-85).
func lift(card: BoardCard, show_face: bool = false, with_button: bool = false) -> void:
	if held != null or card == null or _camera == null or not _spawn.is_valid():
		return
	var made: Object = _spawn.call()
	var stand_in: BoardCard = made as BoardCard
	if stand_in == null:
		return
	_loose.add_child(stand_in)
	_fill = LiftLayout.fill_for(_view_size(), _safe(), LIFT_FILL, with_button)
	stand_in.copy_face_from(card)
	stand_in.disable_collision()
	stand_in.global_transform = card.global_transform
	_flipped_up = show_face and card.face_down
	if _flipped_up:
		stand_in.face_down = false
	_stand_in = stand_in
	held = card
	card.visible = false
	_place_dimmer()
	_begin(Mode.LIFTING, LIFT_TIME, stand_in.global_transform, DIMMER_ALPHA)
	lifted.emit(card)


## Flies the stand-in back to the real card's current place, then shows the real card.
## Awaitable; returns at once when nothing is held.
func put_down(duration: float = PUT_DOWN_TIME) -> void:
	if held == null:
		return
	if not is_inside_tree():
		_finish()
		return
	if _mode != Mode.PUTTING:
		if not is_instance_valid(held):
			push_warning("CardLift: the held card was freed before the put-down")
			_finish()
			return
		var start: Transform3D = _stand_in.global_transform
		if _flipped_up:
			_stand_in.face_down = true
			_flipped_up = false
		_begin(Mode.PUTTING, duration, start, _rest_alpha)
		if duration <= 0.0:
			_finish()
			return
	await settled


## R10: ends everything at once, with no motion.
func drop_now() -> void:
	if _mode == Mode.IDLE and held == null and _stand_in == null:
		return
	_finish()


func _begin(mode: Mode, duration: float, from: Transform3D, alpha_to: float) -> void:
	_mode = mode
	_elapsed = 0.0
	_duration = duration
	_from = from
	_alpha_from = _current_alpha()
	_alpha_to = alpha_to


func _arrived() -> void:
	if _mode == Mode.LIFTING:
		_mode = Mode.HOLDING
		_set_alpha(_alpha_to)
		return
	_finish()


## Where the stand-in is heading: the lift pose, or the real card's place right now.
func _target() -> Transform3D:
	if _mode == Mode.PUTTING and is_instance_valid(held):
		return held.global_transform
	return _lift_pose()


## Where the action button goes under the held card, in viewport pixels (NSC-85).
func button_rect() -> Rect2:
	return LiftLayout.button_rect(_view_size(), _safe(), _fill)


func _view_size() -> Vector2:
	if _camera == null or _camera.get_viewport() == null:
		return Vector2(1280.0, 720.0)
	return _camera.get_viewport().get_visible_rect().size


func _safe() -> Rect2:
	return LiftLayout.safe_rect(
		_view_size(), DisplayServer.screen_get_size(), DisplayServer.get_display_safe_area()
	)


func _lift_pose() -> Transform3D:
	var half_fov: float = deg_to_rad(_camera.fov) / 2.0
	var d: float = CARD_HEIGHT / (_fill * 2.0 * tan(half_fov))
	return _camera.global_transform * Transform3D(Basis(), Vector3(0.0, 0.0, -d))


## Parks the dimmer just behind the lift pose and sizes it to cover the view there.
func _place_dimmer() -> void:
	var half_fov: float = deg_to_rad(_camera.fov) / 2.0
	var d: float = CARD_HEIGHT / (_fill * 2.0 * tan(half_fov))
	var dist: float = d + DIMMER_GAP
	_dimmer.position = Vector3(0.0, 0.0, -dist)
	var view_height: float = 2.0 * dist * tan(half_fov)
	_dimmer.scale = Vector3(view_height * DIMMER_COVER, view_height * DIMMER_COVER, 1.0)


func _current_alpha() -> float:
	var mat: StandardMaterial3D = _dimmer.material_override as StandardMaterial3D
	if mat == null:
		return 0.0
	return mat.albedo_color.a


func _set_alpha(alpha: float) -> void:
	if _dimmer == null:
		return
	var mat: StandardMaterial3D = _dimmer.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.0, 0.0, 0.0, alpha)
	_dimmer.visible = alpha > 0.0


## Frees the stand-in, shows the real card, resets the dimmer, wakes any awaiter.
func _finish() -> void:
	var card: BoardCard = held if is_instance_valid(held) else null
	if card != null:
		card.visible = true
	if is_instance_valid(_stand_in):
		_stand_in.queue_free()
	_stand_in = null
	_flipped_up = false
	held = null
	_mode = Mode.IDLE
	_set_alpha(_rest_alpha)
	put_down_finished.emit(card)
	settled.emit()
