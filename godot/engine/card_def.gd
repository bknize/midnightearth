class_name CardDef
extends RefCounted
## One card definition from a pool file, format 5 (cycle 9 plan P2, spec R22). Immutable by
## convention.
##
## A card has an id, a name, a tag (one of TAGS), a printed Cost, a Power (which may be
## negative), at most one printed Bonus, zero or more abilities (CardAbility) and its rules
## text. The Bonus: `bonus_kind` NONE (bonus 0), MULT (a Mult, `bonus` in hundredths: 125,
## 150 or 200, MatchRules.MULT_VALUES) or ADD (an Add, `bonus` in hundredths: 25, 50 or 100,
## MatchRules.ADD_VALUES). JSON form of the Bonus: null, {"mult": 125} or {"add": 50}. A card
## with no abilities is a plain body (its text is empty).

enum BonusKind { NONE, MULT, ADD }

## JSON key of a MULT Bonus.
const KEY_MULT: String = "mult"
## JSON key of an ADD Bonus.
const KEY_ADD: String = "add"
## CardDef.lifetime of a Dross card removed from the Match at the end of the Round (the
## default; TurnFlow.expire_dross, rules 9, cycle 14 R10, C13).
const LIFETIME_ROUND: String = "round"
## CardDef.lifetime of a Dross card that lasts the Match: never removed (R11, C13).
const LIFETIME_MATCH: String = "match"
## Every legal `lifetime` (pool key, read only for a Dross card; rules 9, cycle 14 R9, C13).
const LIFETIMES: Array[String] = [LIFETIME_ROUND, LIFETIME_MATCH]
## The card tags (canon R59): the six strategies and `evergreen`.
const TAGS: Array[String] = [
	"evergreen", "greed", "combo", "disruption", "graveyard", "control", "ramp"
]

var id: String = ""
var name: String = ""
var tag: String = ""
var cost: int = 0
var power: int = 0
var bonus_kind: BonusKind = BonusKind.NONE
## Hundredths for MULT and ADD, 0 for NONE.
var bonus: int = 0
var abilities: Array[CardAbility] = []
var text: String = ""
## True for a definition only an ability makes, never in a Deck (the Dross card; pool key
## `created`, the name cards.json keeps, CardDb.KEY_DROSS).
var dross: bool = false
## The lifetime of a Dross card of this definition (pool key `lifetime`, read only for a
## `dross` definition, C13): LIFETIME_ROUND, removed from the Match at the end of the Round
## wherever it is (TurnFlow.expire_dross, DROSS_EXPIRED), or LIFETIME_MATCH, never removed.
## A Deck card's definition keeps the default, so a Dross copy of it (Twin's) lasts the
## Round; the Deck card itself is never Dross and never expires.
var lifetime: String = LIFETIME_ROUND


func _init(
	p_id: String = "",
	p_name: String = "",
	p_tag: String = "evergreen",
	p_cost: int = 0,
	p_power: int = 0,
	p_bonus_kind: BonusKind = BonusKind.NONE,
	p_bonus: int = 0,
	p_abilities: Array[CardAbility] = [],
	p_text: String = ""
) -> void:
	id = p_id
	name = p_name
	tag = p_tag
	cost = p_cost
	power = p_power
	bonus_kind = p_bonus_kind
	bonus = p_bonus
	abilities.assign(p_abilities)
	text = p_text


## Whether a Dross card of this definition (MatchCards.is_dross()) is removed at the end of
## the Round: its lifetime is LIFETIME_ROUND (rules 9, cycle 14 R10, C13). A Deck card never
## expires, whatever this says (TurnFlow.expire_dross asks only for a Dross instance).
func expires_at_round_end() -> bool:
	return lifetime == LIFETIME_ROUND


## Whether the card has no abilities: a plain body (Banner's "no rules text").
func is_plain() -> bool:
	return abilities.is_empty()


## The printed Mult in hundredths, or MatchRules.BONUS_ONE (×1) when it has none.
func printed_mult() -> int:
	return bonus if bonus_kind == BonusKind.MULT else MatchRules.BONUS_ONE


## The printed Add in hundredths, or 0 when it has none.
func printed_add() -> int:
	return bonus if bonus_kind == BonusKind.ADD else 0


## Whether some ability of the card has the verb `verb_name`.
func has_verb(verb_name: String) -> bool:
	for ability: CardAbility in abilities:
		if ability.verb == verb_name:
			return true
	return false


## The Bonus in its JSON form: null, {"mult": hundredths} or {"add": hundredths}.
func bonus_to_dict() -> Variant:
	match bonus_kind:
		BonusKind.MULT:
			return {KEY_MULT: bonus}
		BonusKind.ADD:
			return {KEY_ADD: bonus}
	return null


func to_dict() -> Dictionary:
	var listed: Array = []
	for ability: CardAbility in abilities:
		listed.append(ability.to_dict())
	var out: Dictionary = {
		"id": id,
		"name": name,
		"tag": tag,
		"cost": cost,
		"power": power,
		"bonus": bonus_to_dict(),
		"abilities": listed,
		"text": text,
	}
	if dross:
		out["created"] = true  # The pool key cards.json uses (CardDb.KEY_DROSS).
		if lifetime != LIFETIME_ROUND:
			out["lifetime"] = lifetime
	return out
