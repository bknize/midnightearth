class_name CardDef
extends RefCounted
## One card definition from engine/data/cards.json format 2 (R1). Immutable by convention.
## `effect` is null for a vanilla card.

var id: String = ""
var name: String = ""
var cost: int = 0
var flat: int = 0
var bonus: int = 0
var effect: CardEffect = null


func _init(
	p_id: String = "",
	p_name: String = "",
	p_cost: int = 0,
	p_flat: int = 0,
	p_bonus: int = 0,
	p_effect: CardEffect = null
) -> void:
	id = p_id
	name = p_name
	cost = p_cost
	flat = p_flat
	bonus = p_bonus
	effect = p_effect


func to_dict() -> Dictionary:
	var effect_value: Variant = null
	if effect != null:
		effect_value = effect.to_dict()
	return {
		"id": id,
		"name": name,
		"cost": cost,
		"flat": flat,
		"bonus": bonus,
		"effect": effect_value,
	}
