class_name CrewDef
extends RefCounted
## One Crew from the Crew pool file (cycle 8 R39, plan P12, P13): an id, a name, a trigger,
## a verb, an amount, an optional flag, a uses count, a scope and the rules text. Immutable
## by convention. A Crew is not a card: it has no cost, flat or bonus (R39, R42).
##
## JSON form, as in crew.json:
## {"id": "shade", "name": "Shade", "trigger": "turn_start", "verb": "unreveal_own_one",
##  "amount": 4, "optional": true, "uses": 0, "scope": "none", "text": "..."}
## Trigger, verb and scope names are the snake_case names in TRIGGER_NAMES, VERB_NAMES and
## SCOPE_NAMES, indexed by the enum values. A Crew of scope NONE is unlimited and carries
## uses 0; a ROUND or MATCH Crew carries uses > 0, its uses left resetting at round start
## (ROUND) or never (MATCH) (R43, MatchState.reset_crew_uses). `amount` is the verb's: the
## turn a TURN_START Crew fires on, a ×-part in hundredths, a flat step, or 0.
##
## Each verb belongs to one trigger (VERB_TRIGGER), which the loader checks. The abilities
## themselves land with DC-11 T10; this class is data only.

enum Trigger { TURN_START, ROUND_END, OWN_DESTROYED, OWN_MOVED, OWN_RETURNED, ONGOING }

enum Verb {
	DRAW_EXTRA,
	EVEN_FLAT_TIMES,
	UNREVEAL_OWN_ONE,
	SALVAGE_DESTROYED,
	UNREVEAL_ALL_OWN,
	MOVED_FLAT,
	GROW_ROW_FLAT,
	DRAW_ON_RETURN,
}

enum Scope { NONE, ROUND, MATCH }

## JSON names of Trigger, indexed by the enum value.
const TRIGGER_NAMES: Array[String] = [
	"turn_start", "round_end", "own_destroyed", "own_moved", "own_returned", "ongoing"
]
## JSON names of Verb, indexed by the enum value.
const VERB_NAMES: Array[String] = [
	"draw_extra",
	"even_flat_times",
	"unreveal_own_one",
	"salvage_destroyed",
	"unreveal_all_own",
	"moved_flat",
	"grow_row_flat",
	"draw_on_return",
]
## JSON names of Scope, indexed by the enum value.
const SCOPE_NAMES: Array[String] = ["none", "round", "match"]
## The one Trigger each Verb may sit on, indexed by the Verb value.
const VERB_TRIGGER: Array[int] = [
	Trigger.TURN_START,
	Trigger.ONGOING,
	Trigger.TURN_START,
	Trigger.OWN_DESTROYED,
	Trigger.OWN_DESTROYED,
	Trigger.OWN_MOVED,
	Trigger.ROUND_END,
	Trigger.OWN_RETURNED,
]
## The uses left of an unlimited Crew (scope NONE) in MatchState.crew_uses.
const UNLIMITED: int = -1

var id: String = ""
var name: String = ""
var trigger: Trigger = Trigger.TURN_START
var verb: Verb = Verb.DRAW_EXTRA
var amount: int = 0
var optional: bool = false
var uses: int = 0
var scope: Scope = Scope.NONE
var text: String = ""


func _init(
	p_id: String = "",
	p_name: String = "",
	p_trigger: Trigger = Trigger.TURN_START,
	p_verb: Verb = Verb.DRAW_EXTRA,
	p_amount: int = 0,
	p_optional: bool = false,
	p_uses: int = 0,
	p_scope: Scope = Scope.NONE,
	p_text: String = ""
) -> void:
	id = p_id
	name = p_name
	trigger = p_trigger
	verb = p_verb
	amount = p_amount
	optional = p_optional
	uses = p_uses
	scope = p_scope
	text = p_text


## The uses left this Crew holds at the start of a match (and of every round, for ROUND):
## `uses`, or UNLIMITED when its scope is NONE.
func initial_uses() -> int:
	if scope == Scope.NONE:
		return UNLIMITED
	return uses


## The Trigger value of a JSON name, or -1 when unknown.
static func trigger_from_name(trigger_name: String) -> int:
	return TRIGGER_NAMES.find(trigger_name)


## The Verb value of a JSON name, or -1 when unknown.
static func verb_from_name(verb_name: String) -> int:
	return VERB_NAMES.find(verb_name)


## The Scope value of a JSON name, or -1 when unknown.
static func scope_from_name(scope_name: String) -> int:
	return SCOPE_NAMES.find(scope_name)


## Whether `verb_value` (a Verb) may sit on `trigger_value` (a Trigger).
static func is_allowed_pair(trigger_value: int, verb_value: int) -> bool:
	if verb_value < 0 or verb_value >= VERB_TRIGGER.size():
		return false
	return VERB_TRIGGER[verb_value] == trigger_value


## The definition in its JSON form, as crew.json holds it.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"trigger": TRIGGER_NAMES[trigger],
		"verb": VERB_NAMES[verb],
		"amount": amount,
		"optional": optional,
		"uses": uses,
		"scope": SCOPE_NAMES[scope],
		"text": text,
	}
