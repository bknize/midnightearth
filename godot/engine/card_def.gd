class_name CardDef
extends RefCounted
## One card definition from engine/data/cards.json (R7). Immutable by convention.

var id: String = ""
var name: String = ""
var cost: int = 0
var power: int = 0


func _init(p_id: String = "", p_name: String = "", p_cost: int = 0, p_power: int = 0) -> void:
	id = p_id
	name = p_name
	cost = p_cost
	power = p_power


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "cost": cost, "power": power}
