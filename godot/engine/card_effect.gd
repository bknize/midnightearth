class_name CardEffect
extends RefCounted
## The one effect a card may carry (R1, plan P1, P8): a trigger, a verb, an amount and the
## rules text. Immutable by convention. Vanilla cards have no CardEffect (null).
##
## JSON form, as in a pool file, format 3:
## {"trigger": "on_reveal", "verb": "draw", "amount": 1, "text": "Draw a card."}
## Trigger and verb names are the snake_case names in TRIGGER_NAMES and VERB_NAMES,
## indexed by the enum values; verbs that take no amount carry 0.
##
## DC-07 (plan P8): `switch_stats` is retired (C20) and `opponent_next_bonus_zero` is now
## `opponent_next_no_bonus` (R14). The triggers ON_OPPONENT_SCORE and ON_MOVED and the
## eighteen Ruin and Drift verbs after CARRY_ENERGY are known names, so the loader accepts
## them; their behaviour lands with DC-07 T05-T07.

enum Trigger { ON_REVEAL, ON_OPPONENT_REVEAL, ON_SCORE, ONGOING, ON_OPPONENT_SCORE, ON_MOVED }

enum Verb {
	DRAW,
	DRAW_THEN_DISCARD,
	FREE_FIRST_NEXT_TURN,
	SWAP_PLACES,
	OPPONENT_NEXT_NO_BONUS,
	RETURN_AT_TURN_END,
	DESTROY_RANDOM_OPPONENT,
	FLAT_UP_ON_SCORE,
	CARRY_ENERGY,
	DISCARD_OWN,
	DESTROY_LEFTMOST_OWN,
	DESTROY_OWN_THEN_DRAW,
	DESTROY_OWN_THEN_FLAT_UP,
	SACRIFICE_DESTROY,
	BURST,
	UNREVEAL_INSTEAD,
	RECOVER_DESTROYED,
	MOVE_SELF_LEFT,
	MOVE_SELF_RIGHT,
	COPY_STATS,
	NEIGHBOUR_TIMES,
	EDGE_LEFT_TIMES,
	MOVE_OPPONENT_LEFT,
	SHIFT_OWN_LEFT,
	REVERSE_OPPONENT_ROW,
	SWAP_OPPONENT_RIGHT,
	PLUS_ON_MOVED,
}

## JSON names of Trigger, indexed by the enum value.
const TRIGGER_NAMES: Array[String] = [
	"on_reveal",
	"on_opponent_reveal",
	"on_score",
	"ongoing",
	"on_opponent_score",
	"on_moved",
]
## JSON names of Verb, indexed by the enum value. FLAT_UP_ON_SCORE is "flat_up", as in
## the plan's card table (its trigger is already on_score).
const VERB_NAMES: Array[String] = [
	"draw",
	"draw_then_discard",
	"free_first_next_turn",
	"swap_places",
	"opponent_next_no_bonus",
	"return_at_turn_end",
	"destroy_random_opponent",
	"flat_up",
	"carry_energy",
	"discard_own",
	"destroy_leftmost_own",
	"destroy_own_then_draw",
	"destroy_own_then_flat_up",
	"sacrifice_destroy",
	"burst",
	"unreveal_instead",
	"recover_destroyed",
	"move_self_left",
	"move_self_right",
	"copy_stats",
	"neighbour_times",
	"edge_left_times",
	"move_opponent_left",
	"shift_own_left",
	"reverse_opponent_row",
	"swap_opponent_right",
	"plus_on_moved",
]

const KEY_TRIGGER: String = "trigger"
const KEY_VERB: String = "verb"
const KEY_AMOUNT: String = "amount"
const KEY_TEXT: String = "text"

var trigger: Trigger = Trigger.ON_REVEAL
var verb: Verb = Verb.DRAW
var amount: int = 0
var text: String = ""


func _init(
	p_trigger: Trigger = Trigger.ON_REVEAL,
	p_verb: Verb = Verb.DRAW,
	p_amount: int = 0,
	p_text: String = ""
) -> void:
	trigger = p_trigger
	verb = p_verb
	amount = p_amount
	text = p_text


## The JSON name of a trigger, or "" when out of range.
static func trigger_name(value: int) -> String:
	if value < 0 or value >= TRIGGER_NAMES.size():
		return ""
	return TRIGGER_NAMES[value]


## The JSON name of a verb, or "" when out of range.
static func verb_name(value: int) -> String:
	if value < 0 or value >= VERB_NAMES.size():
		return ""
	return VERB_NAMES[value]


## The Trigger for a JSON name, or -1 when unknown.
static func trigger_from_name(value: String) -> int:
	return TRIGGER_NAMES.find(value)


## The Verb for a JSON name, or -1 when unknown.
static func verb_from_name(value: String) -> int:
	return VERB_NAMES.find(value)


## Whether `d` has the four keys with the right types: string trigger and verb, a
## non-negative whole amount and a string text. Names are not checked here.
static func has_valid_shape(d: Dictionary) -> bool:
	if not (d.has(KEY_TRIGGER) and d.has(KEY_VERB) and d.has(KEY_AMOUNT) and d.has(KEY_TEXT)):
		return false
	if not (d[KEY_TRIGGER] is String and d[KEY_VERB] is String and d[KEY_TEXT] is String):
		return false
	var raw_amount: Variant = d[KEY_AMOUNT]
	if not _is_whole_number(raw_amount):
		return false
	return _as_int(raw_amount) >= 0


## Builds an effect from its JSON form, or null when the shape is wrong or the trigger
## or verb name is unknown.
static func from_dict(d: Dictionary) -> CardEffect:
	if not has_valid_shape(d):
		return null
	var trigger_text: String = d[KEY_TRIGGER]
	var verb_text: String = d[KEY_VERB]
	var trigger_value: int = trigger_from_name(trigger_text)
	var verb_value: int = verb_from_name(verb_text)
	if trigger_value < 0 or verb_value < 0:
		return null
	var rules_text: String = d[KEY_TEXT]
	return CardEffect.new(
		trigger_value as Trigger, verb_value as Verb, _as_int(d[KEY_AMOUNT]), rules_text
	)


func to_dict() -> Dictionary:
	return {
		KEY_TRIGGER: trigger_name(trigger),
		KEY_VERB: verb_name(verb),
		KEY_AMOUNT: amount,
		KEY_TEXT: text,
	}


## Converts a value already checked by _is_whole_number to int without an unsafe call.
static func _as_int(value: Variant) -> int:
	if value is int:
		var whole: int = value
		return whole
	var number: float = value
	return int(number)


## JSON numbers arrive as floats; accept ints and floats with no fractional part.
static func _is_whole_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var f: float = value
		return is_finite(f) and f == floorf(f)
	return false
