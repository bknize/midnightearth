class_name CardAbility
extends RefCounted
## One ability of a card (cycle 9 plan P3, spec R22): exactly one moment, a verb, its
## amounts, and the optional scope, watcher bracket, zone bracket, cap and uses, with the
## ability's rules text. Immutable by convention. Replaces the v6 CardEffect.
##
## JSON form, as in a pool file, format 5 (only `moment`, `verb` and `text` are required):
## {"moment": "on_score", "verb": "grow_self_mult_add", "amount": 25, "cap": 200,
##  "scope": "match", "text": "On score: ..."}
## with the optional keys `amount_2`, `scope` (SCOPES), `watch` (WATCHES, default "self"),
## `zone` (ZONES, default "row"), `cap` and `uses` (a whole number >= 0, 0 unlimited).
## Moments and verbs are kept by name: VERBS is the table of every card verb (milestones A
## and B), each with the moments it may sit on and the inclusive range of each amount it
## takes (a verb that takes no amount allows only 0, which an absent key is). The behaviour
## of a verb is Abilities' (DC-13 T06); a loaded ability is data only.

const KEY_MOMENT: String = "moment"
const KEY_VERB: String = "verb"
const KEY_AMOUNT: String = "amount"
const KEY_AMOUNT_2: String = "amount_2"
const KEY_SCOPE: String = "scope"
const KEY_WATCH: String = "watch"
const KEY_ZONE: String = "zone"
const KEY_CAP: String = "cap"
const KEY_USES: String = "uses"
const KEY_TEXT: String = "text"
## The keys a verb table entry may hold besides `moments`: the amounts with a range.
const RANGED_KEYS: Array[String] = [KEY_AMOUNT, KEY_AMOUNT_2, KEY_CAP]

## The trigger moments (plan P3; canon R42): the one place their names are written.
const MOMENT_REVEAL: String = "on_reveal"
const MOMENT_SCORE: String = "on_score"
const MOMENT_COMMIT: String = "on_commit"
const MOMENT_START: String = "on_start"
const MOMENT_DISCARD: String = "on_discard"
const MOMENT_SQUELCH: String = "on_squelch"
const MOMENT_EMPTY_DRAW: String = "on_empty_draw"
const MOMENT_MOVED: String = "on_moved"
const MOMENT_TURN_END_BEFORE: String = "at_turn_end_before"
const MOMENT_TURN_END_AFTER: String = "at_turn_end_after"
const MOMENT_ONGOING: String = "ongoing"
## The trigger moments in the canon's order.
const MOMENTS: Array[String] = [
	MOMENT_REVEAL,
	MOMENT_SCORE,
	MOMENT_COMMIT,
	MOMENT_START,
	MOMENT_DISCARD,
	MOMENT_SQUELCH,
	MOMENT_EMPTY_DRAW,
	MOMENT_MOVED,
	MOMENT_TURN_END_BEFORE,
	MOMENT_TURN_END_AFTER,
	MOMENT_ONGOING,
]
## The watcher bracket (plan P3): whose event the ability watches; "self" when absent.
const WATCH_SELF: String = "self"
const WATCH_OTHER_OWN: String = "other_own"
const WATCH_OPPOSING: String = "opposing"
const WATCH_ANY: String = "any"
const WATCHES: Array[String] = [WATCH_SELF, WATCH_OTHER_OWN, WATCH_OPPOSING, WATCH_ANY]
## The zone bracket (plan P3): where the card must be for the ability to fire; "row" when
## absent.
const ZONES: Array[String] = ["row", "hand"]
## The cessation of a change the ability makes (plan P3, canon R29); "" when absent.
const SCOPES: Array[String] = ["turn", "row", "match"]

## The card verb table (plan P3, "Milestone A verb table", and the milestone B verbs of
## DC-14): verb name to
## {moments: the moments it may sit on, and for each amount it takes (`amount`, `amount_2`,
## `cap`) an inclusive [low, high] range}. A key without a range must be 0 (or absent).
## Amounts are in canon units: Power and Energy whole, a Mult growth step and a cap in
## hundredths (×1.2 is 120), an Add in hundredths.
const VERBS: Dictionary[String, Dictionary] = {
	"draw": {"moments": ["on_reveal", "on_score"], KEY_AMOUNT: [1, 3]},
	"opponent_draw": {"moments": ["on_score"], KEY_AMOUNT: [1, 3]},
	"discard_own": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 3]},
	"discard_hand": {"moments": ["on_reveal"]},
	"condemn_self": {"moments": ["on_reveal"]},
	"grow_self_power": {"moments": ["on_reveal", "on_score"], KEY_AMOUNT: [1, 5]},
	"grow_self_mult_add": {"moments": ["on_score"], KEY_AMOUNT: [25, 100], KEY_CAP: [125, 300]},
	"grow_right_mult_times":
	{"moments": ["on_score"], KEY_AMOUNT: [101, 200], KEY_CAP: [125, 300]},
	"grow_hand_power": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 5]},
	"right_power": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 5]},
	"others_power": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 5]},
	"plain_power": {"moments": ["ongoing"], KEY_AMOUNT: [1, 10]},
	"copy_stats": {"moments": ["on_reveal"]},
	"move_self_right": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 1]},
	"anchored_self": {"moments": ["ongoing"]},
	"cannot_condemn_self": {"moments": ["ongoing"]},
	"ward_mute": {"moments": ["on_score"]},
	"scapegoat": {"moments": ["on_squelch"]},
	"hand_size_add": {"moments": ["ongoing"], KEY_AMOUNT: [1, 3]},
	"delve": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 5]},
	"look_at_opposing": {"moments": ["on_reveal"]},
	"energy_grant": {"moments": ["on_start"], KEY_AMOUNT: [1, 3]},
	"cost_down_right": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 3]},
	"cost_down_self": {"moments": ["on_commit"], KEY_AMOUNT: [1, 3]},
	"cost_on_turn": {"moments": ["ongoing"], KEY_AMOUNT: [0, 7], KEY_AMOUNT_2: [1, 7]},
	"pass_power_add": {"moments": ["on_commit"], KEY_AMOUNT: [1, 5], KEY_AMOUNT_2: [25, 100]},
	"free_first_next_turn": {"moments": ["on_reveal"]},
	# Milestone B, Combo and Disruption (DC-14 T12, AbilitiesComboDisruption).
	"wick": {"moments": ["on_score"], KEY_AMOUNT: [1, 3]},
	"fade_other_own": {"moments": ["on_reveal"]},
	"fleeting_chosen": {"moments": ["on_reveal"]},
	"scrap": {"moments": ["on_reveal"], KEY_AMOUNT: [25, 100], KEY_CAP: [25, 300]},
	"copy_self_to_hand": {"moments": ["on_reveal"]},
	"scores_twice": {"moments": ["on_commit"]},
	"retrigger_reveals": {"moments": ["on_reveal"]},
	"reverb": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 5]},
	"finale": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 5]},
	"mute_opposing": {"moments": ["on_reveal"]},
	"squelch_opposing": {"moments": ["on_reveal"]},
	"create_dross": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 5]},
	"move_to_opposing": {"moments": ["on_reveal"]},
	"hex_choose": {"moments": ["on_reveal"]},
	"mute_chosen": {"moments": ["on_start"]},
	"mute_random_opposing": {"moments": ["on_score"]},
	"stasis": {"moments": ["ongoing"]},
	"gag": {"moments": ["on_commit"]},
	"quorum": {"moments": ["on_start"], KEY_AMOUNT: [1, 5]},
	"silence_opposing": {"moments": ["on_reveal"]},
	"dross_walk_end": {"moments": ["ongoing"], KEY_AMOUNT: [1, 99]},
	# Graveyard and Control (DC-14 T13, AbilitiesGraveyardControl).
	"fuse": {"moments": ["on_score"], KEY_AMOUNT: [1, 3], KEY_AMOUNT_2: [1, 10]},
	"tithe_energy": {"moments": ["on_discard"], KEY_AMOUNT: [1, 3], KEY_CAP: [1, 5]},
	"reliquary_mult": {"moments": ["on_discard"], KEY_AMOUNT: [101, 200], KEY_CAP: [125, 300]},
	"pile_power": {"moments": ["ongoing"], KEY_AMOUNT: [1, 3], KEY_AMOUNT_2: [1, 10]},
	"wraith_fade": {"moments": ["ongoing"]},
	"condemn_other_gain": {"moments": ["on_reveal"]},
	"revive": {"moments": ["on_reveal"]},
	"exhume": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 3]},
	"immolate": {"moments": ["on_reveal"]},
	"reset_piles": {"moments": ["on_reveal"]},
	"moved_add": {"moments": ["on_moved"], KEY_AMOUNT: [25, 100]},
	"pin": {"moments": ["on_reveal"]},
	"swap_self": {"moments": ["on_reveal"]},
	"skip_next": {"moments": ["on_reveal"]},
	"fence": {"moments": ["ongoing"]},
	"rightmost_mult": {"moments": ["ongoing"], KEY_AMOUNT: [125, 200]},
	"level_power": {"moments": ["ongoing"]},
	"shake": {"moments": ["on_reveal"]},
	"reverse_opposing": {"moments": ["on_reveal"]},
	"cull": {"moments": ["on_reveal"], KEY_AMOUNT: [1, 7]},
}
## The verb whose card may carry a printed Cost above MatchRules.MAX_PRINTED_COST (R12).
const COST_EXCEPTION_VERB: String = "cost_on_turn"

# Error prefixes, stable so tests and callers can match on them (CardDb re-exports them).
const ERR_SHAPE: String = "bad shape"
const ERR_MOMENT: String = "unknown moment"
const ERR_VERB: String = "unknown verb"
const ERR_PAIR: String = "verb not allowed on moment"
const ERR_AMOUNT: String = "amount out of range"
const ERR_SCOPE: String = "unknown scope"
const ERR_WATCH: String = "unknown watch"
const ERR_ZONE: String = "unknown zone"
const ERR_USES: String = "bad uses"
const ERR_TEXT: String = "missing text"

var moment: String = ""
var verb: String = ""
var amount: int = 0
var amount_2: int = 0
## "" when absent, else one of SCOPES.
var scope: String = ""
var watch: String = "self"
var zone: String = "row"
## A growth cap in hundredths (Sapling ×2 is 200), 0 when absent.
var cap: int = 0
## How many times the ability may fire in a match; 0 is unlimited.
var uses: int = 0
var text: String = ""


## The ability of a JSON object already accepted by problem_of() (a missing optional key
## takes its default).
static func from_dict(d: Dictionary) -> CardAbility:
	var out: CardAbility = CardAbility.new()
	out.moment = _string_of(d, KEY_MOMENT, "")
	out.verb = _string_of(d, KEY_VERB, "")
	out.text = _string_of(d, KEY_TEXT, "")
	out.scope = _string_of(d, KEY_SCOPE, "")
	out.watch = _string_of(d, KEY_WATCH, WATCH_SELF)
	out.zone = _string_of(d, KEY_ZONE, ZONES[0])
	out.amount = _int_of(d, KEY_AMOUNT)
	out.amount_2 = _int_of(d, KEY_AMOUNT_2)
	out.cap = _int_of(d, KEY_CAP)
	out.uses = _int_of(d, KEY_USES)
	return out


## The first problem of an ability's JSON value, as "<error prefix>: <detail>", or "" when
## it is well formed: an object, string moment, verb and non-empty text, known names, the
## verb allowed on its moment, every amount whole and within the verb's range, optional
## names known and `uses` a whole number >= 0.
static func problem_of(value: Variant) -> String:
	if not value is Dictionary:
		return "%s: an ability must be an object" % ERR_SHAPE
	var d: Dictionary = value
	if not (d.get(KEY_MOMENT) is String and d.get(KEY_VERB) is String):
		return "%s: an ability needs a string moment and verb" % ERR_SHAPE
	if _string_of(d, KEY_TEXT, "") == "":
		return "%s: the ability has no rules text" % ERR_TEXT
	var name_problem: String = _name_problem(d)
	if name_problem != "":
		return name_problem
	var bracket_problem: String = _bracket_problem(d)
	if bracket_problem != "":
		return bracket_problem
	return _amount_problem(d)


## Whether `moment_name` is a known moment.
static func is_moment(moment_name: String) -> bool:
	return MOMENTS.has(moment_name)


## Whether `verb_name` is a known verb (VERBS).
static func is_verb(verb_name: String) -> bool:
	return VERBS.has(verb_name)


## Whether the known `verb_name` may sit on `moment_name` (VERBS `moments`).
static func is_allowed_pair(moment_name: String, verb_name: String) -> bool:
	return VerbTable.is_allowed_pair(VERBS, moment_name, verb_name)


## The inclusive [low, high] range of `key` for `verb_name`, or [0, 0] when the verb takes
## no such amount (or is unknown).
static func range_of(verb_name: String, key: String) -> Array[int]:
	return VerbTable.range_of(VERBS, verb_name, key)


## The JSON form: the required keys, and each optional key only when it is not its default.
func to_dict() -> Dictionary:
	var out: Dictionary = {KEY_MOMENT: moment, KEY_VERB: verb}
	if amount != 0:
		out[KEY_AMOUNT] = amount
	if amount_2 != 0:
		out[KEY_AMOUNT_2] = amount_2
	if scope != "":
		out[KEY_SCOPE] = scope
	if watch != WATCH_SELF:
		out[KEY_WATCH] = watch
	if zone != ZONES[0]:
		out[KEY_ZONE] = zone
	if cap != 0:
		out[KEY_CAP] = cap
	if uses != 0:
		out[KEY_USES] = uses
	out[KEY_TEXT] = text
	return out


## The moment and verb problem of `d` (both strings), or "".
static func _name_problem(d: Dictionary) -> String:
	var moment_name: String = d[KEY_MOMENT]
	var verb_name: String = d[KEY_VERB]
	if not is_moment(moment_name):
		return '%s: "%s"' % [ERR_MOMENT, moment_name]
	if not is_verb(verb_name):
		return '%s: "%s"' % [ERR_VERB, verb_name]
	if not is_allowed_pair(moment_name, verb_name):
		return '%s: "%s" on "%s"' % [ERR_PAIR, verb_name, moment_name]
	return ""


## The scope, watch, zone and uses problem of `d`, or "": each absent or a known word, and
## uses absent or a whole number >= 0.
static func _bracket_problem(d: Dictionary) -> String:
	if not _word_ok(d, KEY_SCOPE, SCOPES):
		return "%s: %s" % [ERR_SCOPE, JSON.stringify(d[KEY_SCOPE])]
	if not _word_ok(d, KEY_WATCH, WATCHES):
		return "%s: %s" % [ERR_WATCH, JSON.stringify(d[KEY_WATCH])]
	if not _word_ok(d, KEY_ZONE, ZONES):
		return "%s: %s" % [ERR_ZONE, JSON.stringify(d[KEY_ZONE])]
	var raw_uses: Variant = d.get(KEY_USES, 0)
	if not VerbTable.is_uses(raw_uses):
		return "%s: %s (a whole number >= 0)" % [ERR_USES, JSON.stringify(raw_uses)]
	return ""


## The amount problem of `d` (whose verb is known), or "": `amount`, `amount_2` and `cap`
## each whole and within the verb's range (absent counts as 0).
static func _amount_problem(d: Dictionary) -> String:
	var verb_name: String = d[KEY_VERB]
	return VerbTable.amount_problem(
		d,
		VERBS,
		verb_name,
		RANGED_KEYS,
		"%s: %%s %%s is not a whole number" % ERR_AMOUNT,
		"%s: " % ERR_AMOUNT
	)


## Whether `d[key]` is absent or a string in `words`.
static func _word_ok(d: Dictionary, key: String, words: Array[String]) -> bool:
	if not d.has(key):
		return true
	var raw: Variant = d[key]
	if not raw is String:
		return false
	var word: String = raw
	return words.has(word)


## `d[key]` as a String, or `fallback` when absent or not a string.
static func _string_of(d: Dictionary, key: String, fallback: String) -> String:
	var raw: Variant = d.get(key, fallback)
	if not raw is String:
		return fallback
	var word: String = raw
	return word


## `d[key]` as an int, 0 when absent or not a whole number.
static func _int_of(d: Dictionary, key: String) -> int:
	var raw: Variant = d.get(key, 0)
	if not EngineAction.is_whole_number(raw):
		return 0
	return EngineAction.as_int(raw)


