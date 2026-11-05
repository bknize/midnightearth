class_name CardEffect
extends RefCounted
## The one effect a card may carry (R1, plan P1, P8): a trigger, a verb, an amount, the
## rules text and, since pool format 4, a uses count. Immutable by convention. Vanilla cards
## have no CardEffect (null).
##
## JSON form, as in a pool file, format 4:
## {"trigger": "on_reveal", "verb": "draw", "amount": 1, "text": "Draw a card."}
## with an optional "uses": n (a whole number >= 0; absent or 0 is unlimited, cycle 8 R9,
## plan P1). Trigger and verb names are the snake_case names in TRIGGER_NAMES and
## VERB_NAMES, indexed by the enum values; verbs that take no amount carry 0.
##
## DC-07 (plan P8): `switch_stats` is retired (C20) and `opponent_next_bonus_zero` is now
## `opponent_next_no_bonus` (R14). The triggers ON_OPPONENT_SCORE and ON_MOVED and the
## eighteen Ruin and Drift verbs after CARRY_ENERGY are known names, so the loader accepts
## them; their behaviour lands with DC-07 T05-T07.
##
## DC-09 T01 (cycle 8 plan P1, P4, P6): the trigger ON_ALLY_REVEAL and the seventeen Bloom
## and Echo verbs after PLUS_ON_MOVED are known names, checked by the loader against
## ALLOWED_TRIGGERS, ALLY_REVEAL_VERBS and GROW_STAT; their behaviour lands with DC-09 T02
## (Bloom) and T03 (Echo).

enum Trigger {
	ON_REVEAL,
	ON_OPPONENT_REVEAL,
	ON_SCORE,
	ONGOING,
	ON_OPPONENT_SCORE,
	ON_MOVED,
	ON_ALLY_REVEAL,
}

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
	GROW_SELF_FLAT,
	GROW_SELF_TIMES,
	GROW_SELF_PLUS,
	GROW_SELF_TIMES_ONCE,
	GROW_OTHER_FLAT,
	GROW_HAND_FLAT,
	GROW_HAND_ONE_TIMES,
	GROW_ROW_FLAT,
	GROW_ROW_TIMES,
	RETURN_SELF_AT_TURN_END,
	RETURN_OWN_AT_TURN_END,
	RETURN_OPPONENT_AT_TURN_END,
	UNREVEAL_AT_TURN_END,
	COST_DOWN_RIGHT,
	COST_DOWN_SELF,
	DRAW_ONCE,
	ALLY_REVEAL_FLAT,
}

## JSON names of Trigger, indexed by the enum value.
const TRIGGER_NAMES: Array[String] = [
	"on_reveal",
	"on_opponent_reveal",
	"on_score",
	"ongoing",
	"on_opponent_score",
	"on_moved",
	"on_ally_reveal",
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
	"grow_self_flat",
	"grow_self_times",
	"grow_self_plus",
	"grow_self_times_once",
	"grow_other_flat",
	"grow_hand_flat",
	"grow_hand_one_times",
	"grow_row_flat",
	"grow_row_times",
	"return_self_at_turn_end",
	"return_own_at_turn_end",
	"return_opponent_at_turn_end",
	"unreveal_at_turn_end",
	"cost_down_right",
	"cost_down_self",
	"draw_once",
	"ally_reveal_flat",
]

## The only triggers a verb listed here may use (cycle 8 R11, plan P1, P4, P6); a verb not
## listed keeps every trigger but ON_ALLY_REVEAL (see ALLY_REVEAL_VERBS). Keyed by Verb,
## each value an Array of Trigger values.
const ALLOWED_TRIGGERS: Dictionary[int, Array] = {
	Verb.GROW_SELF_FLAT: [Trigger.ON_SCORE, Trigger.ON_REVEAL],
	Verb.GROW_SELF_TIMES: [Trigger.ON_SCORE, Trigger.ON_REVEAL],
	Verb.GROW_SELF_PLUS: [Trigger.ON_SCORE, Trigger.ON_REVEAL],
	Verb.GROW_SELF_TIMES_ONCE: [Trigger.ON_SCORE, Trigger.ON_REVEAL],
	Verb.GROW_OTHER_FLAT: [Trigger.ON_REVEAL],
	Verb.GROW_HAND_FLAT: [Trigger.ON_REVEAL],
	Verb.GROW_HAND_ONE_TIMES: [Trigger.ON_REVEAL],
	Verb.GROW_ROW_FLAT: [Trigger.ON_REVEAL],
	Verb.GROW_ROW_TIMES: [Trigger.ON_REVEAL],
	Verb.RETURN_SELF_AT_TURN_END: [Trigger.ON_REVEAL],
	Verb.RETURN_OWN_AT_TURN_END: [Trigger.ON_REVEAL],
	Verb.RETURN_OPPONENT_AT_TURN_END: [Trigger.ON_REVEAL],
	Verb.UNREVEAL_AT_TURN_END: [Trigger.ONGOING],
	Verb.COST_DOWN_RIGHT: [Trigger.ON_REVEAL],
	Verb.COST_DOWN_SELF: [Trigger.ON_REVEAL],
	Verb.DRAW_ONCE: [Trigger.ON_REVEAL],
	Verb.ALLY_REVEAL_FLAT: [Trigger.ON_ALLY_REVEAL],
}
## The only verbs an ON_ALLY_REVEAL effect may carry (plan P1, P6): the round-scoped flat
## and the existing draw (Refrain and Relay).
const ALLY_REVEAL_VERBS: Array[int] = [Verb.ALLY_REVEAL_FLAT, Verb.DRAW]
## The CardMemory stat a memory-writing verb grows, keyed by Verb (plan P1, P4, P6): its
## amount must be one of MatchRules.GROW_STEPS[stat] (cycle 8 R5, R11).
const GROW_STAT: Dictionary[int, String] = {
	Verb.GROW_SELF_FLAT: "flat",
	Verb.GROW_SELF_TIMES: "times",
	Verb.GROW_SELF_PLUS: "plus",
	Verb.GROW_SELF_TIMES_ONCE: "times",
	Verb.GROW_OTHER_FLAT: "flat",
	Verb.GROW_HAND_FLAT: "flat",
	Verb.GROW_HAND_ONE_TIMES: "times",
	Verb.GROW_ROW_FLAT: "flat",
	Verb.GROW_ROW_TIMES: "times",
	Verb.COST_DOWN_RIGHT: "cost",
	Verb.COST_DOWN_SELF: "cost",
}

const KEY_TRIGGER: String = "trigger"
const KEY_VERB: String = "verb"
const KEY_AMOUNT: String = "amount"
const KEY_TEXT: String = "text"
## Optional since format 4 (cycle 8 R9): how many times the effect may fire in a match.
const KEY_USES: String = "uses"

var trigger: Trigger = Trigger.ON_REVEAL
var verb: Verb = Verb.DRAW
var amount: int = 0
var text: String = ""
## How many times the effect may fire in a match; 0 is unlimited (cycle 8 R6, plan P7).
var uses: int = 0


func _init(
	p_trigger: Trigger = Trigger.ON_REVEAL,
	p_verb: Verb = Verb.DRAW,
	p_amount: int = 0,
	p_text: String = "",
	p_uses: int = 0
) -> void:
	trigger = p_trigger
	verb = p_verb
	amount = p_amount
	text = p_text
	uses = p_uses


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
## non-negative whole amount and a string text, and a valid optional uses (has_valid_uses).
## Names are not checked here.
static func has_valid_shape(d: Dictionary) -> bool:
	if not (d.has(KEY_TRIGGER) and d.has(KEY_VERB) and d.has(KEY_AMOUNT) and d.has(KEY_TEXT)):
		return false
	if not (d[KEY_TRIGGER] is String and d[KEY_VERB] is String and d[KEY_TEXT] is String):
		return false
	var raw_amount: Variant = d[KEY_AMOUNT]
	if not _is_whole_number(raw_amount):
		return false
	return _as_int(raw_amount) >= 0 and has_valid_uses(d)


## Whether `d`'s optional uses is absent or a whole number >= 0 (cycle 8 R11, plan P1).
static func has_valid_uses(d: Dictionary) -> bool:
	if not d.has(KEY_USES):
		return true
	var raw_uses: Variant = d[KEY_USES]
	return _is_whole_number(raw_uses) and _as_int(raw_uses) >= 0


## Whether `verb_value` may sit on `trigger_value` (cycle 8 R11, plan P1): a verb in
## ALLOWED_TRIGGERS only on the triggers it lists, and ON_ALLY_REVEAL only with a verb in
## ALLY_REVEAL_VERBS.
static func is_allowed_pair(trigger_value: int, verb_value: int) -> bool:
	if ALLOWED_TRIGGERS.has(verb_value):
		var allowed: Array = ALLOWED_TRIGGERS[verb_value]
		if not allowed.has(trigger_value):
			return false
	if trigger_value == Trigger.ON_ALLY_REVEAL:
		return ALLY_REVEAL_VERBS.has(verb_value)
	return true


## Whether `amount_value` is a legal amount for `verb_value` (cycle 8 R5, R11): one of
## MatchRules.GROW_STEPS for a verb in GROW_STAT, any amount for every other verb.
static func is_allowed_amount(verb_value: int, amount_value: int) -> bool:
	if not GROW_STAT.has(verb_value):
		return true
	var stat: String = GROW_STAT[verb_value]
	var steps: Array = MatchRules.GROW_STEPS[stat]
	return steps.has(amount_value)


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
	var uses_value: int = 0
	if d.has(KEY_USES):
		uses_value = _as_int(d[KEY_USES])
	return CardEffect.new(
		trigger_value as Trigger, verb_value as Verb, _as_int(d[KEY_AMOUNT]), rules_text, uses_value
	)


## The JSON form; `uses` only when the effect is limited (> 0), so an unlimited effect
## writes the format-3 keys alone.
func to_dict() -> Dictionary:
	var out: Dictionary = {
		KEY_TRIGGER: trigger_name(trigger),
		KEY_VERB: verb_name(verb),
		KEY_AMOUNT: amount,
		KEY_TEXT: text,
	}
	if uses > 0:
		out[KEY_USES] = uses
	return out


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
