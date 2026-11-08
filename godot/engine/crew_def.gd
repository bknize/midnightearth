class_name CrewDef
extends RefCounted
## One Crew from the Crew pool file, v2 (cycle 9 plan P4, spec R62): an id, a name, a tag,
## a moment, a verb, up to two amounts, an optional flag, a uses count, a scope and the rules
## text. Immutable by convention. A Crew is not a card: it has no Cost, Power or Bonus.
##
## JSON form, as in crew.json:
## {"id": "void", "name": "Void", "tag": "greed", "moment": "on_empty_draw",
##  "verb": "void_grant", "amount": 10, "amount_2": 50, "optional": false, "uses": 0,
##  "scope": "turn", "text": "..."}
## Moments are CardAbility.MOMENTS. VERBS is the Crew table (milestone A, and B since DC-14
## T14): each verb with the one moment it sits on and the inclusive range of each amount it
## takes (a verb without a range for a key allows only 0). The amounts, by verb:
## - tallyman_fifth (ongoing): every `amount`th Scoring card of the seat's Walk gets a Mult
##   of `amount_2` hundredths for that Score (5, ×2 = 200);
## - void_grant (on_empty_draw): the seat's next Scoring card gets Power +`amount`, Add
##   +`amount_2` hundredths and Mult ×VOID_MULT until it Scores or turn end (10, 50);
## - engineer_energy (ongoing): Budget +`amount` from Turn `amount_2` (1, 3);
## - navigator_second (on_score): the seat's `amount_2`th Scoring card of the Walk gets Power
##   +`amount` for the match after it Scores (2, 2);
## - captain_leftmost (on_score): the card in the seat's leftmost slot gets Power +`amount`
##   for the match after it Scores (1);
## - dredge (on_empty_draw): the seat's Pile is shuffled into its Deck (no amount);
## - shade_unreveal (at_turn_end_after): up to `amount` random revealed cards of the seat's
##   row are offered, the chosen one is Un-revealed (3);
## - veil_fleeting (at_turn_end_before): a Condemned card of the seat's row gets Fleeting
##   instead (no amount);
## - quartermaster_hand (ongoing): the seat's Hand size is `amount` (7);
## - salvager_cycle (on_commit): the seat may Discard a card from its hand, then draws (no
##   amount).
## `uses` 0 is unlimited (every v2 Crew); `scope` is the cessation of the change it gives
## (CardAbility.SCOPES, or "" for none) and, for a limited Crew, the scope its uses count in
## (`turn` comes back at turn end, any other for the match; rules 9, cycle 14 R6). The
## behaviour is CrewAbilities' (DC-13 T07, T14); this class is data only.

## The Crew verbs (plan P4; milestone B's four from DC-14 T14): verb name to {moment, and
## for `amount` and `amount_2` an inclusive [low, high] range when the verb takes it}.
const VERBS: Dictionary[String, Dictionary] = {
	"tallyman_fifth": {"moment": "ongoing", "amount": [2, 10], "amount_2": [101, 400]},
	"void_grant": {"moment": "on_empty_draw", "amount": [0, 20], "amount_2": [0, 100]},
	"engineer_energy": {"moment": "ongoing", "amount": [1, 3], "amount_2": [1, 7]},
	"navigator_second": {"moment": "on_score", "amount": [1, 5], "amount_2": [1, 7]},
	"captain_leftmost": {"moment": "on_score", "amount": [1, 5]},
	"dredge": {"moment": "on_empty_draw"},
	"shade_unreveal": {"moment": "at_turn_end_after", "amount": [1, 5]},
	"veil_fleeting": {"moment": "at_turn_end_before"},
	"quartermaster_hand": {"moment": "ongoing", "amount": [1, 10]},
	"salvager_cycle": {"moment": "on_commit"},
}
## Void's granted Mult, in hundredths (×1.25, canon crew-v2 C31): the third number of the
## grant, which has no amount key of its own.
const VOID_MULT: int = 125
## The uses left of an unlimited Crew (uses 0) in MatchState.crew_uses.
const UNLIMITED: int = -1

var id: String = ""
var name: String = ""
var tag: String = ""
var moment: String = ""
var verb: String = ""
var amount: int = 0
var amount_2: int = 0
var optional: bool = false
var uses: int = 0
var scope: String = ""
var text: String = ""


func _init(
	p_id: String = "",
	p_name: String = "",
	p_moment: String = "",
	p_verb: String = "",
	p_text: String = ""
) -> void:
	id = p_id
	name = p_name
	moment = p_moment
	verb = p_verb
	text = p_text


## The uses left this Crew holds at the start of a match: `uses`, or UNLIMITED when 0.
func initial_uses() -> int:
	return UNLIMITED if uses <= 0 else uses


## Whether `verb_name` is a known Crew verb (VERBS).
static func is_verb(verb_name: String) -> bool:
	return VERBS.has(verb_name)


## Whether the known `verb_name` sits on `moment_name` (its one moment in VERBS).
static func is_allowed_pair(moment_name: String, verb_name: String) -> bool:
	if not VERBS.has(verb_name):
		return false
	var entry: Dictionary = VERBS[verb_name]
	var own: String = entry["moment"]
	return own == moment_name


## The inclusive [low, high] range of `key` ("amount" or "amount_2") for `verb_name`, or
## [0, 0] when the verb takes no such amount (or is unknown).
static func range_of(verb_name: String, key: String) -> Array[int]:
	var out: Array[int] = [0, 0]
	if not VERBS.has(verb_name):
		return out
	var entry: Dictionary = VERBS[verb_name]
	if entry.has(key):
		var listed: Array = entry[key]
		out.assign(listed)
	return out


## The definition in its JSON form, as crew.json holds it.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"tag": tag,
		"moment": moment,
		"verb": verb,
		"amount": amount,
		"amount_2": amount_2,
		"optional": optional,
		"uses": uses,
		"scope": scope,
		"text": text,
	}
