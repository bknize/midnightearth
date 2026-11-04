class_name RowTally
extends Node3D
## The running tally beside each row (R32, R34, plan P13): one Label3D per seat reading
## "score ×mult", shown from the walk start to the turn end. At the turn end it flies to the
## seat's HUD score and hides. Pure view: the board feeds it the tracker's numbers.

const FLY_TIME: float = 0.3
const PIXEL_SIZE: float = 0.014
const FONT_SIZE: int = 96
const OUTLINE_SIZE: int = 24

var _labels: Array[Label3D] = []
var _tweens: Array[Tween] = []
## The turn end's count, started once the fly-in lands.
var _count: Tween = null
## Where each tally rests (world position).
var _homes: Dictionary[int, Vector3] = {}

@onready var _label_0: Label3D = $Tally0
@onready var _label_1: Label3D = $Tally1


func _ready() -> void:
	_labels.append(_label_0)
	_labels.append(_label_1)
	for seat: int in range(_labels.size()):
		var label: Label3D = _labels[seat]
		label.modulate = ScoreChips.seat_color(seat)
		label.pixel_size = PIXEL_SIZE
		label.font_size = FONT_SIZE
		label.outline_size = OUTLINE_SIZE
		label.no_depth_test = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.visible = false
		_tweens.append(null)


## The text of one tally.
static func tally_text(score: int, mult: int) -> String:
	return "%d ×%d" % [score, mult]


## Puts `seat`'s tally at a world position (the row's right end).
func place(seat: int, world_position: Vector3) -> void:
	_homes[seat] = world_position
	_labels[seat].global_position = world_position


## Shows both tallies with these numbers (the walk start, and each pulse).
func show_values(tally: Array[int], mults: Array[int]) -> void:
	for seat: int in range(_labels.size()):
		_stop(seat)
		_labels[seat].text = tally_text(tally[seat], mults[seat])
		_labels[seat].visible = true


## R34: flies each tally to its seat's HUD score, then the HUD counts from the total on show
## to `scores`. `speed` divides both durations (R36). The plane is that of the tallies.
func fly_in(scores: Array[int], hud: BoardHud, camera: Camera3D, speed: float) -> void:
	_kill_count()
	var targets: Array[Vector3] = []
	for seat: int in range(_labels.size()):
		targets.append(_anchor_world(camera, hud.score_anchor(seat), _labels[seat].global_position))
	var seconds: float = FLY_TIME / (speed if speed > 0.0 else 1.0)
	fly_to(targets, seconds)
	_count = create_tween()
	var wait: IntervalTweener = _count.tween_interval(seconds)
	assert(wait != null)
	for seat: int in range(_labels.size()):
		var total: int = scores[seat] if seat < scores.size() else 0
		var counted: CallbackTweener = _count.tween_callback(
			hud.count_to.bind(seat, total, seconds)
		)
		counted = counted.set_delay(0.0)


## Hides both tallies now.
func hide_all() -> void:
	_kill_count()
	for seat: int in range(_labels.size()):
		_stop(seat)
		_labels[seat].visible = false


## True while `seat`'s tally is shown.
func is_shown(seat: int) -> bool:
	return _labels[seat].visible


## The text of `seat`'s tally.
func text_of(seat: int) -> String:
	return _labels[seat].text


## Flies each shown tally to its world target over `seconds`, then hides it and returns it
## home. `targets` is one position per seat.
func fly_to(targets: Array[Vector3], seconds: float) -> void:
	for seat: int in range(_labels.size()):
		_stop(seat)
		var label: Label3D = _labels[seat]
		if not label.visible:
			continue
		var tween: Tween = label.create_tween()
		var move: PropertyTweener = tween.tween_property(
			label, "global_position", targets[seat], maxf(seconds, 0.01)
		)
		move = move.set_ease(Tween.EASE_IN)
		var done: CallbackTweener = tween.tween_callback(_finish.bind(seat))
		done = done.set_delay(0.0)
		_tweens[seat] = tween


func _finish(seat: int) -> void:
	_labels[seat].visible = false
	_return_home(seat)


func _stop(seat: int) -> void:
	var tween: Tween = _tweens[seat]
	if tween != null and tween.is_valid():
		tween.kill()
	_tweens[seat] = null
	_return_home(seat)


func _return_home(seat: int) -> void:
	if _homes.has(seat):
		_labels[seat].global_position = _homes[seat]


func _kill_count() -> void:
	if _count != null and _count.is_valid():
		_count.kill()
	_count = null


## The point on the tally's plane under a screen position.
func _anchor_world(camera: Camera3D, screen: Vector2, rest: Vector3) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var plane: Plane = Plane(Vector3.BACK, rest.z)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return rest
	var point: Vector3 = hit
	return point
