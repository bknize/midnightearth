class_name CardDef
extends RefCounted
## One card definition from a pool file, format 3 (R1, plan P1). Immutable by convention.
## `effect` is null for a vanilla card.
##
## A card has at most one bonus (C6): `bonus_kind` NONE (bonus 0), TIMES (a ×-bonus,
## `bonus` in hundredths: 125, 150 or 200, MatchRules.TIMES_VALUES) or PLUS (a +bonus,
## `bonus` in whole units: 1 or 2, MatchRules.PLUS_VALUES). JSON form of the bonus: null,
## {"x": 125} or {"plus": 1}.

enum BonusKind { NONE, TIMES, PLUS }

## JSON key of a TIMES bonus.
const KEY_TIMES: String = "x"
## JSON key of a PLUS bonus.
const KEY_PLUS: String = "plus"

var id: String = ""
var name: String = ""
var cost: int = 0
var flat: int = 0
var bonus_kind: BonusKind = BonusKind.NONE
## Hundredths for TIMES, whole units for PLUS, 0 for NONE.
var bonus: int = 0
var effect: CardEffect = null


func _init(
	p_id: String = "",
	p_name: String = "",
	p_cost: int = 0,
	p_flat: int = 0,
	p_bonus_kind: BonusKind = BonusKind.NONE,
	p_bonus: int = 0,
	p_effect: CardEffect = null
) -> void:
	id = p_id
	name = p_name
	cost = p_cost
	flat = p_flat
	bonus_kind = p_bonus_kind
	bonus = p_bonus
	effect = p_effect


## The bonus in its JSON form: null, {"x": hundredths} or {"plus": units}.
func bonus_to_dict() -> Variant:
	match bonus_kind:
		BonusKind.TIMES:
			return {KEY_TIMES: bonus}
		BonusKind.PLUS:
			return {KEY_PLUS: bonus}
	return null


func to_dict() -> Dictionary:
	var effect_value: Variant = null
	if effect != null:
		effect_value = effect.to_dict()
	return {
		"id": id,
		"name": name,
		"cost": cost,
		"flat": flat,
		"bonus": bonus_to_dict(),
		"effect": effect_value,
	}
