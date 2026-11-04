class_name BoardCard
extends Card3D
## One card on the board (R9, R41): placeholder face with name, cost, flat, bonus and rules
## text, and a shared plain back. Inherits the Card3D addon scene unchanged. Physics picking
## is off; the pointer shim raycasts instead.

const PULSE_SCALE: float = 1.4
const PULSE_TIME: float = 0.2
const GLOW_SIZE: Vector2 = Vector2(2.9, 3.9)
const GLOW_PEAK_ALPHA: float = 0.6
## Drawn after the prompt's dimmer (render priority 1), so a glowing card stays lit.
const GLOW_PRIORITY: int = 2
## The glow and the note sit this far in front of the face.
const GLOW_Z: float = 0.05
const NOTE_Z: float = 0.1
const NOTE_COLOR: Color = Color(0.75, 0.1, 0.1, 1.0)
const NOTE_FONT_SIZE: int = 44

## The destroyed look (R26, plan P8): brightness at the DC-04 dimmer level, a fixed tilt that
## flips sign with slot parity, and a crack quad on both faces.
const DESTROYED_BRIGHTNESS: float = 0.4
const TILT_Z_DEGREES: float = 9.0
const TILT_X_DEGREES: float = 4.0
const CRACK_SIZE: Vector2 = Vector2(2.5, 3.5)
const CRACK_Z: float = 0.02
const CRACK_IMAGE_SIZE: Vector2i = Vector2i(128, 180)
const CRACK_SEED: int = 7

## The crack image from `godot/art/` when the file exists (ADR 0003 manifest); otherwise the
## placeholder built in code. One path, so a later `/art` image drops in with no code change.
@export var crack_texture_path: String = "res://art/destroyed/crack.png"

## Engine instance id; -1 for an unrevealed opponent card.
var instance_id: int = -1

var _flat_pulse: Tween = null
var _bonus_pulse: Tween = null
var _glow: MeshInstance3D = null
var _crack: MeshInstance3D = null
var _crack_material: StandardMaterial3D = null
var _destroyed: bool = false
## 0 (intact) to 1 (fully marked); the dim, tilt and crack alpha follow it.
var _amount: float = 0.0
var _tilt: Vector3 = Vector3.ZERO
var _tilt_suspended: bool = false
var _fade: Tween = null
var _base_colors: Dictionary[Label3D, Color] = {}
var _base_back: Color = Color.WHITE
var _base_face: Color = Color.WHITE

@onready var _name_label: Label3D = $CardMesh/NameLabel
@onready var _cost_label: Label3D = $CardMesh/CostLabel
@onready var _flat_label: Label3D = $CardMesh/FlatLabel
@onready var _bonus_label: Label3D = $CardMesh/BonusLabel
@onready var _text_label: Label3D = $CardMesh/TextLabel


func show_def(def: CardDef) -> void:
	_name_label.text = def.name
	_cost_label.text = str(def.cost)
	_set_numbers(def.flat, def.legacy_bonus())
	if def.effect != null:
		_text_label.text = def.effect.text
	else:
		_text_label.text = ""


## Updates the shown flat and bonus and pulses the label that changed (R42). The tweens are
## owned by the labels, so a card freed mid-pulse takes them along.
func show_stats(flat: int, bonus: int) -> void:
	var flat_changed: bool = _flat_label.text != str(flat)
	var bonus_changed: bool = _bonus_label.text != _bonus_text(bonus)
	_set_numbers(flat, bonus)
	if flat_changed:
		_flat_pulse = _pulse(_flat_label, _flat_pulse)
	if bonus_changed:
		_bonus_pulse = _pulse(_bonus_label, _bonus_pulse)


## Shows the shared `Glow` child (the DC-04 ZoneGlow look, T12 prompts use it too) at `alpha`.
## `source` is the board's zone-glow material; each card keeps its own copy to fade.
func set_glow(source: Material, alpha: float) -> void:
	if _glow == null:
		_glow = MeshInstance3D.new()
		_glow.name = "Glow"
		var quad: QuadMesh = QuadMesh.new()
		quad.size = GLOW_SIZE
		_glow.mesh = quad
		_glow.position = Vector3(0.0, 0.0, GLOW_Z)
		add_child(_glow)
	var material: StandardMaterial3D = _glow.material_override as StandardMaterial3D
	if material == null:
		material = source.duplicate() as StandardMaterial3D
		if material == null:
			return
		material.render_priority = GLOW_PRIORITY
		_glow.material_override = material
	material.albedo_color = Color(material.albedo_color, alpha)
	_glow.visible = alpha > 0.0


func clear_glow() -> void:
	if _glow != null:
		_glow.visible = false


## Glows and fades out over `seconds` (the opponent's pick, R53). The tween belongs to the
## glow node, so a card freed mid-glow takes it along.
func pulse_glow(source: Material, seconds: float) -> void:
	set_glow(source, GLOW_PEAK_ALPHA)
	var material: StandardMaterial3D = _glow.material_override as StandardMaterial3D
	if material == null:
		return
	var tween: Tween = _glow.create_tween()
	var fade: MethodTweener = tween.tween_method(
		_fade_glow.bind(source), GLOW_PEAK_ALPHA, 0.0, maxf(seconds, 0.01)
	)
	if fade == null:
		clear_glow()


## Shows `text` on the card and fades it over `seconds` (FIZZLE, R53). The label and its tween
## are children of the card.
func flash_note(text: String, seconds: float) -> void:
	var note: Label3D = Label3D.new()
	note.text = text
	note.pixel_size = 0.01
	note.font_size = NOTE_FONT_SIZE
	note.modulate = NOTE_COLOR
	note.outline_size = 0
	note.position = Vector3(0.0, 0.0, NOTE_Z)
	add_child(note)
	var tween: Tween = note.create_tween()
	var fade: PropertyTweener = tween.tween_property(
		note, "modulate:a", 0.0, maxf(seconds, 0.01)
	)
	if fade == null:
		note.queue_free()
		return
	var err: int = tween.finished.connect(note.queue_free)
	if err != OK:
		note.queue_free()


## The tilt of a destroyed card at row `slot`, in radians as (x, 0, z): the same size for every
## card, the sign alternating with slot parity so neighbours do not match.
static func tilt_for_slot(slot: int) -> Vector3:
	var sign_of: float = 1.0 if slot % 2 == 0 else -1.0
	return Vector3(
		deg_to_rad(TILT_X_DEGREES) * -sign_of, 0.0, deg_to_rad(TILT_Z_DEGREES) * sign_of
	)


## Marks or unmarks the card as destroyed (R26). The dim, tilt and crack fade in over
## `seconds`; 0 applies at once. `slot` picks the tilt sign. The card stays where it is.
func set_destroyed(on: bool, slot: int = 0, seconds: float = 0.0) -> void:
	if on == _destroyed and not (on and seconds <= 0.0):
		return
	_destroyed = on
	if on:
		_tilt = tilt_for_slot(slot)
		_capture_look()
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var target: float = 1.0 if on else 0.0
	if seconds <= 0.0:
		_apply_amount(target)
		return
	_fade = create_tween()
	var step: MethodTweener = _fade.tween_method(_apply_amount, _amount, target, seconds)
	if step == null:
		_apply_amount(target)


func is_destroyed() -> bool:
	return _destroyed


## The tilt is off while the card is held (the DC-04 lift) and back on put-down (R37).
func set_tilt_suspended(suspended: bool) -> void:
	_tilt_suspended = suspended
	_refresh_look()


func clear_def() -> void:
	set_destroyed(false)
	_name_label.text = ""
	_cost_label.text = ""
	_flat_label.text = ""
	_bonus_label.text = ""
	_bonus_label.visible = false
	_text_label.text = ""


## Copies the face text and the face-up/down state from another card.
func copy_face_from(other: BoardCard) -> void:
	_name_label.text = other._name_label.text
	_cost_label.text = other._cost_label.text
	_flat_label.text = other._flat_label.text
	_bonus_label.text = other._bonus_label.text
	_bonus_label.visible = other._bonus_label.visible
	_text_label.text = other._text_label.text
	face_down = other.face_down
	instance_id = other.instance_id


func _fade_glow(alpha: float, source: Material) -> void:
	set_glow(source, alpha)


func _set_numbers(flat: int, bonus: int) -> void:
	_flat_label.text = str(flat)
	_bonus_label.text = _bonus_text(bonus)
	_bonus_label.visible = bonus != 0


func _bonus_text(bonus: int) -> String:
	if bonus == 0:
		return ""
	return "+%d" % bonus


func _pulse(label: Label3D, running: Tween) -> Tween:
	if running != null and running.is_valid():
		running.kill()
	label.scale = Vector3.ONE
	var tween: Tween = label.create_tween()
	var up: PropertyTweener = tween.tween_property(
		label, "scale", Vector3.ONE * PULSE_SCALE, PULSE_TIME * 0.5
	)
	var down: PropertyTweener = tween.tween_property(label, "scale", Vector3.ONE, PULSE_TIME * 0.5)
	if up == null or down == null:
		label.scale = Vector3.ONE
	return tween


# --- The destroyed look ---------------------------------------------------------------------


## Gives this card its own face and back materials (the scene's are shared) and remembers the
## colours the dim starts from, once; builds the `Crack` quad on first use.
func _capture_look() -> void:
	if _crack != null:
		return
	var back: MeshInstance3D = $CardMesh/CardBackMesh as MeshInstance3D
	var front: MeshInstance3D = $CardMesh/CardFrontMesh as MeshInstance3D
	var back_mat: StandardMaterial3D = back.material_override as StandardMaterial3D
	var face_mat: StandardMaterial3D = front.material_override as StandardMaterial3D
	if back_mat != null:
		back_mat = back_mat.duplicate() as StandardMaterial3D
		back.material_override = back_mat
		_base_back = back_mat.albedo_color
	if face_mat != null:
		face_mat = face_mat.duplicate() as StandardMaterial3D
		front.material_override = face_mat
		_base_face = face_mat.albedo_color
	for label: Label3D in [_name_label, _cost_label, _flat_label, _bonus_label, _text_label]:
		_base_colors[label] = label.modulate
	_build_crack()


func _build_crack() -> void:
	_crack_material = StandardMaterial3D.new()
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_material.albedo_texture = _crack_texture()
	_crack_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = CRACK_SIZE
	_crack = MeshInstance3D.new()
	_crack.name = "Crack"
	_crack.mesh = quad
	_crack.material_override = _crack_material
	_crack.position = Vector3(0.0, 0.0, CRACK_Z)
	_crack.visible = false
	# The back shows the same crack, so a face-down destroyed card carries the look too.
	var behind: MeshInstance3D = MeshInstance3D.new()
	behind.name = "CrackBack"
	behind.mesh = quad
	behind.material_override = _crack_material
	behind.position = Vector3(0.0, 0.0, -2.0 * CRACK_Z)
	behind.rotation = Vector3(0.0, PI, 0.0)
	_crack.add_child(behind)
	var mesh: Node3D = $CardMesh as Node3D
	mesh.add_child(_crack)


func _crack_texture() -> Texture2D:
	if crack_texture_path != "" and ResourceLoader.exists(crack_texture_path):
		var loaded: Texture2D = load(crack_texture_path) as Texture2D
		if loaded != null:
			return loaded
	# Built per card on its first destroy, not cached in a static var: a static Resource
	# keeps the GDScript classes alive at exit and the boot stage reports them as leaked.
	return _make_crack_placeholder()


## Jagged white lines on alpha, from a fixed seed so every run draws the same crack.
static func _make_crack_placeholder() -> ImageTexture:
	var image: Image = Image.create(
		CRACK_IMAGE_SIZE.x, CRACK_IMAGE_SIZE.y, false, Image.FORMAT_RGBA8
	)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = CRACK_SEED
	var size: Vector2 = Vector2(CRACK_IMAGE_SIZE)
	var origin: Vector2 = Vector2(size.x * 0.55, size.y * 0.4)
	for branch: int in range(5):
		var at: Vector2 = origin
		var heading: float = TAU * float(branch) / 5.0 + rng.randf_range(-0.4, 0.4)
		for _segment: int in range(7):
			heading += rng.randf_range(-0.7, 0.7)
			var next: Vector2 = at + Vector2.from_angle(heading) * rng.randf_range(8.0, 22.0)
			next = next.clamp(Vector2.ZERO, size - Vector2.ONE)
			_draw_line(image, at, next)
			at = next
	return ImageTexture.create_from_image(image)


static func _draw_line(image: Image, from: Vector2, to: Vector2) -> void:
	var steps: int = maxi(int(from.distance_to(to)), 1)
	for i: int in range(steps + 1):
		var point: Vector2 = from.lerp(to, float(i) / float(steps))
		for dx: int in range(2):
			for dy: int in range(2):
				var x: int = clampi(int(point.x) + dx, 0, image.get_width() - 1)
				var y: int = clampi(int(point.y) + dy, 0, image.get_height() - 1)
				image.set_pixel(x, y, Color.WHITE)


func _apply_amount(amount: float) -> void:
	_amount = amount
	_refresh_look()


## Applies `_amount` to the dim, the tilt (off while held) and the crack.
func _refresh_look() -> void:
	if _crack == null:
		return
	var shade: float = lerpf(1.0, DESTROYED_BRIGHTNESS, _amount)
	var back: MeshInstance3D = $CardMesh/CardBackMesh as MeshInstance3D
	var front: MeshInstance3D = $CardMesh/CardFrontMesh as MeshInstance3D
	var back_mat: StandardMaterial3D = back.material_override as StandardMaterial3D
	var face_mat: StandardMaterial3D = front.material_override as StandardMaterial3D
	if back_mat != null:
		back_mat.albedo_color = _shaded(_base_back, shade)
	if face_mat != null:
		face_mat.albedo_color = _shaded(_base_face, shade)
	for label: Label3D in _base_colors:
		label.modulate = _shaded(_base_colors[label], shade)
	var mesh: Node3D = $CardMesh as Node3D
	var held_off: float = 0.0 if _tilt_suspended else _amount
	mesh.rotation.x = _tilt.x * held_off
	mesh.rotation.z = _tilt.z * held_off
	_crack_material.albedo_color = Color(1.0, 1.0, 1.0, _amount)
	_crack.visible = _amount > 0.0


func _shaded(base: Color, shade: float) -> Color:
	return Color(base.r * shade, base.g * shade, base.b * shade, base.a)
