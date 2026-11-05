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
## A selected card (multi-select prompt, R48) stands this far in front of its slot.
const SELECT_RAISE: float = 0.03
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

## The Crew look (cycle 8 R59, R60): the face is dimmed to this brightness once spent.
const CREW_DIM_BRIGHTNESS: float = 0.5
const CREW_DIM_ALPHA: float = 0.45
const BADGE_POSITION: Vector3 = Vector3(0.0, -1.4, 0.01)
const BADGE_FONT_SIZE: int = 44
const BADGE_COLOR: Color = Color(0.1, 0.25, 0.7, 1.0)

## The crack image from `godot/art/` when the file exists (ADR 0003 manifest); otherwise the
## placeholder built in code. One path, so a later `/art` image drops in with no code change.
@export var crack_texture_path: String = "res://art/destroyed/crack.png"

## Engine instance id; -1 for an unrevealed opponent card.
var instance_id: int = -1
## A Crew card's uses badge, built by show_crew(); null on every other card.
var badge: Label3D = null

var _flat_pulse: Tween = null
var _bonus_pulse: Tween = null
var _cost_pulse: Tween = null
var _glow: MeshInstance3D = null
var _crack: MeshInstance3D = null
var _crack_material: StandardMaterial3D = null
var _destroyed: bool = false
var _selected: bool = false
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
@onready var _grown_mark: Label3D = $CardMesh/GrownMark


## Dresses the face from a view entry (SeatView `own_hand_row`, `own_row`, `opponent_row`;
## cycle 8 P16, R24, R25): the effective cost, flat and bonus, and the grown mark when the
## card carries memory. A key the entry lacks falls back to the printed value of `def`. The
## rules text stays the card's own (cycle 6 C23).
func show_entry(def: CardDef, entry: Dictionary) -> void:
	_name_label.text = def.name
	var cost: int = entry.get("cost", def.cost)
	_cost_label.text = str(cost)
	var times: int = ScoreTracker.MULT_ONE
	var plus: int = 0
	if def.bonus_kind == CardDef.BonusKind.TIMES:
		times = def.bonus
	elif def.bonus_kind == CardDef.BonusKind.PLUS:
		plus = def.bonus
	var flat: int = entry.get("flat", def.flat)
	times = entry.get("times", times)
	plus = entry.get("plus", plus)
	_set_numbers(flat, times, plus)
	_text_label.text = rules_text(def)
	var grown: bool = entry.get("grown", false)
	_grown_mark.visible = grown


## Dresses the face as a Crew (cycle 8 R59): its name and rules text, no cost, flat or bonus,
## and a uses badge under the text. A Crew is not a card and has no instance id.
func show_crew(crew_name: String, text: String) -> void:
	_name_label.text = crew_name
	_text_label.text = text
	_cost_label.text = ""
	_flat_label.text = ""
	_bonus_label.visible = false
	_grown_mark.visible = false
	if badge == null:
		badge = Label3D.new()
		badge.name = "Badge"
		badge.pixel_size = 0.01
		badge.double_sided = false
		badge.outline_size = 0
		badge.font_size = BADGE_FONT_SIZE
		badge.modulate = BADGE_COLOR
		badge.position = BADGE_POSITION
		var mesh: Node3D = $CardMesh as Node3D
		mesh.add_child(badge)


## Sets the badge text; an empty text hides it (an unlimited Crew shows none, R60).
func set_badge(text: String) -> void:
	if badge == null:
		return
	badge.text = text
	badge.visible = text != ""


## Dims a spent Crew (R60): the face darkens and the labels fade. Own materials, made once.
func set_dim(on: bool) -> void:
	var shade: float = CREW_DIM_BRIGHTNESS if on else 1.0
	for part: String in ["CardBackMesh", "CardFrontMesh"]:
		var mesh: MeshInstance3D = get_node_or_null("CardMesh/" + part) as MeshInstance3D
		if mesh == null:
			continue
		var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if material == null:
			continue
		if not material.has_meta(&"crew_base"):
			material = material.duplicate() as StandardMaterial3D
			material.set_meta(&"crew_base", material.albedo_color)
			mesh.material_override = material
		var base: Color = material.get_meta(&"crew_base")
		material.albedo_color = Color(base.r * shade, base.g * shade, base.b * shade, base.a)
	for label: Label3D in [_name_label, _text_label, badge]:
		if label != null:
			label.modulate.a = CREW_DIM_ALPHA if on else 1.0


## The entry of card `id` in a view's rows, or an empty dictionary when it is not listed.
static func entry_in(rows: Array[Dictionary], id: int) -> Dictionary:
	for entry: Dictionary in rows:
		var named: int = entry.get("card", MatchEvent.HIDDEN_CARD)
		if named == id:
			return entry
	return {}


## Updates the shown flat and bonus and pulses the label that changed (R42). The tweens are
## owned by the labels, so a card freed mid-pulse takes them along. A `cost` of 0 or more
## also updates the cost label, and `permanent` shows the grown mark (cycle 8 R25, R26).
func show_stats(flat: int, times: int, plus: int, cost: int = -1, permanent: bool = false) -> void:
	var flat_changed: bool = _flat_label.text != str(flat)
	var bonus_changed: bool = _bonus_label.text != bonus_text(times, plus)
	_set_numbers(flat, times, plus)
	var cost_changed: bool = cost >= 0 and _cost_label.text != str(cost)
	if cost >= 0:
		_cost_label.text = str(cost)
	if permanent:
		_grown_mark.visible = true
	if cost_changed:
		_cost_pulse = _pulse(_cost_label, _cost_pulse)
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


## Raises the card to show it is in the prompt's selection, or sets it back (R48).
func set_selected(on: bool) -> void:
	_selected = on
	var mesh: Node3D = get_node_or_null("CardMesh") as Node3D
	if mesh != null:
		mesh.position.z = SELECT_RAISE if on else 0.0


func is_selected() -> bool:
	return _selected


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
	var fade: PropertyTweener = tween.tween_property(note, "modulate:a", 0.0, maxf(seconds, 0.01))
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
	return Vector3(deg_to_rad(TILT_X_DEGREES) * -sign_of, 0.0, deg_to_rad(TILT_Z_DEGREES) * sign_of)


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
	_grown_mark.visible = false


## Copies the face text and the face-up/down state from another card.
func copy_face_from(other: BoardCard) -> void:
	_name_label.text = other._name_label.text
	_cost_label.text = other._cost_label.text
	_flat_label.text = other._flat_label.text
	_bonus_label.text = other._bonus_label.text
	_bonus_label.visible = other._bonus_label.visible
	_text_label.text = other._text_label.text
	_grown_mark.visible = other._grown_mark.visible
	face_down = other.face_down
	instance_id = other.instance_id


func _fade_glow(alpha: float, source: Material) -> void:
	set_glow(source, alpha)


func _set_numbers(flat: int, times: int, plus: int) -> void:
	_flat_label.text = str(flat)
	_bonus_label.text = bonus_text(times, plus)
	_bonus_label.visible = _bonus_label.text != ""


## The rules text of a face: the effect's text, or reminder text built from the printed stats.
static func rules_text(def: CardDef) -> String:
	if def.effect != null:
		return def.effect.text
	if def.bonus_kind == CardDef.BonusKind.TIMES:
		return "When this scores, your mult %s." % ScoreChips.mult_text(def.bonus)
	if def.bonus_kind == CardDef.BonusKind.PLUS:
		return "When this scores, your mult +%d." % def.bonus
	return "Scores its flat at your mult."


## The face's bonus text from a hundredths `times` and whole `plus`: "×1.25", "+1", "×1.25 +1"
## when a card carries both, and "" for a vanilla card (R44).
static func bonus_text(times: int, plus: int) -> String:
	var parts: Array[String] = []
	if times != ScoreTracker.MULT_ONE:
		parts.append(ScoreChips.mult_text(times))
	if plus != 0:
		parts.append("+%d" % plus)
	return " ".join(parts)


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
	for label: Label3D in [
		_name_label, _cost_label, _flat_label, _bonus_label, _text_label, _grown_mark
	]:
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
