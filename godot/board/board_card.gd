class_name BoardCard
extends Card3D
## One card on the board (R9): placeholder face text and a shared plain back. Inherits the
## Card3D addon scene unchanged. Physics picking is off; the pointer shim raycasts instead.

## Engine instance id; -1 for an unrevealed opponent card.
var instance_id: int = -1

@onready var _name_label: Label3D = $CardMesh/NameLabel
@onready var _cost_label: Label3D = $CardMesh/CostLabel
@onready var _power_label: Label3D = $CardMesh/PowerLabel
@onready var _rim: MeshInstance3D = $CardMesh/Rim


func show_def(def: CardDef) -> void:
	_name_label.text = def.name
	_cost_label.text = str(def.cost)
	_power_label.text = str(def.flat)


func clear_def() -> void:
	_name_label.text = ""
	_cost_label.text = ""
	_power_label.text = ""


func set_unseen(on: bool) -> void:
	_rim.visible = on


func is_unseen() -> bool:
	return _rim.visible


## Copies the face text, the face-up/down state and the rim from another card.
func copy_face_from(other: BoardCard) -> void:
	_name_label.text = other._name_label.text
	_cost_label.text = other._cost_label.text
	_power_label.text = other._power_label.text
	face_down = other.face_down
	instance_id = other.instance_id
	set_unseen(other.is_unseen())
