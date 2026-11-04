class_name BoardCard
extends Card3D
## One card on the board (R9, R41): placeholder face with name, cost, flat, bonus and rules
## text, and a shared plain back. Inherits the Card3D addon scene unchanged. Physics picking
## is off; the pointer shim raycasts instead.

const PULSE_SCALE: float = 1.4
const PULSE_TIME: float = 0.2

## Engine instance id; -1 for an unrevealed opponent card.
var instance_id: int = -1

var _flat_pulse: Tween = null
var _bonus_pulse: Tween = null

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
