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

## Engine instance id; -1 for an unrevealed opponent card.
var instance_id: int = -1

var _flat_pulse: Tween = null
var _bonus_pulse: Tween = null
var _glow: MeshInstance3D = null

@onready var _name_label: Label3D = $CardMesh/NameLabel
@onready var _cost_label: Label3D = $CardMesh/CostLabel
@onready var _flat_label: Label3D = $CardMesh/FlatLabel
@onready var _bonus_label: Label3D = $CardMesh/BonusLabel
@onready var _text_label: Label3D = $CardMesh/TextLabel


func show_def(def: CardDef) -> void:
	_name_label.text = def.name
	_cost_label.text = str(def.cost)
	_set_numbers(def.flat, def.bonus)
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


func clear_def() -> void:
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
