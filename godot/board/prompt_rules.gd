class_name PromptRules
extends RefCounted
## Pure rules for the prompt UI (R30, R55, R56, C10, C16, plan P19). It works on positions,
## never nodes: a prompt's options are positions in its zone (a hand in hand order, a row in
## slot order, `both_boards` the asker's row then the other's), mapped to table spots through
## RowTargets. The board maps spots to cards. The prompt is seat 0's own.

## What a tap does while a prompt is open.
## CHOOSE is the button path (the lifted option submitted); the others route a tap (R40-R44).
## TOGGLE_SELECT is the button path of a multi prompt: the lifted option joins or leaves the
## selection (R48).
enum Tap { NOTHING, CHOOSE, LIFT, LIFT_ELIGIBLE, SWAP_LIFT, PUT_DOWN, TOGGLE_SELECT }

## The action button's text for each prompt verb (R41, R49), by the verb's JSON name.
const ACTION_LABELS: Dictionary[String, String] = {
	"discard_own": "Discard",
	"discard_down": "Discard",
	"copy_stats": "Copy",
	"look_at_opposing": "Look",
	"delve": "Take",
}
## The `resume` of a discard-down prompt (plan P12, P14): it opens after an accepted Commit.
const RESUME_COMMIT: String = "commit"
const SELECT_LABEL: String = "Select"
const DESELECT_LABEL: String = "Deselect"


## The name of a prompt's zone ("own_hand", "opponent_pile"). The one place the board reads
## the prompt's `zone`: a String as the v7 prompt (plan P12) carries it; an int is today's
## Choice.Zone, named through Choice (drop that branch with Choice).
static func zone_name_of(prompt: Dictionary) -> String:
	var raw: Variant = prompt.get("zone", "")
	if raw is String:
		var named: String = raw
		return named
	if raw is int:
		var zone: int = raw
		return Choice.zone_name(zone)
	return ""


## Whether a zone name is a Pile ("own_pile", "opponent_pile", "both_piles"): the board lays
## the Pile strip out for such a prompt (R78).
static func is_pile_zone(zone_label: String) -> bool:
	return zone_label.contains("pile")


## The seats whose Piles a Pile zone shows, in strip order, for the asked seat: an "own"
## zone the asked seat's, an "opponent" zone the other's, "both" the asked seat's then the
## other's. Empty for a zone that is not a Pile.
static func pile_seats(zone_label: String, asked: int) -> Array[int]:
	var out: Array[int] = []
	if not is_pile_zone(zone_label):
		return out
	if zone_label.begins_with("own"):
		out.append(asked)
	elif zone_label.begins_with("opponent"):
		out.append(1 - asked)
	else:
		out.append(asked)
		out.append(1 - asked)
	return out


## The verb name of a prompt: a String (plan P12), or today's CardEffect.Verb int named through
## CardEffect (drop that branch with CardEffect).
static func verb_name_of(prompt: Dictionary) -> String:
	var raw: Variant = prompt.get("verb", "")
	if raw is String:
		var named: String = raw
		return named
	if raw is int:
		var verb: int = raw
		return CardEffect.verb_name(verb)
	return ""


## The set size a multi-select prompt requires: its `exact` (the discard-down's excess), or
## -1 when any size up to the options is legal (plan P12).
static func exact_of(prompt: Dictionary) -> int:
	var exact: int = prompt.get("exact", -1)
	return exact


## Whether the prompt is the discard-down (R80): its verb says so, or it resumes at the
## Commit as a multi-select.
static func is_discard_down(prompt: Dictionary) -> bool:
	var multi: bool = prompt.get("multi", false)
	var resume: String = prompt.get("resume", "")
	return verb_name_of(prompt) == "discard_down" or (multi and resume == RESUME_COMMIT)


## Whether Confirm is on with `count` cards selected (R80): the count equals `exact` when the
## prompt has one; otherwise it is at least `min` and at most the options.
static func confirm_enabled(prompt: Dictionary, count: int) -> bool:
	var exact: int = exact_of(prompt)
	if exact >= 0:
		return count == exact
	var raw: Array = prompt.get("options", [])
	var least: int = prompt.get("min", 0)
	return count >= least and count <= raw.size()


## The banner for an open prompt: "Discard N" for the discard-down (R80), else the prompt's
## own text with a Crew's name in front (banner_text).
static func banner_for(prompt: Dictionary, text: String, crew_name: String) -> String:
	if is_discard_down(prompt):
		return "Discard %d" % maxi(exact_of(prompt), 0)
	return banner_text(text, crew_name)


## The spots to glow, in option order (R55). `own_size` is the asker's row size, which splits
## `both_boards`. The opponent's hand is found by fan index; its cards glow as backs and are
## chosen by position (R30, C10). An unknown zone gives no spots.
static func spots(prompt: Dictionary, own_size: int) -> Array[CardSpot]:
	var out: Array[CardSpot] = []
	if prompt.is_empty():
		return out
	var asked: int = prompt.get("seat", 0)
	var zone_label: String = zone_name_of(prompt)
	var raw: Array = prompt.get("options", [])
	for entry: Variant in raw:
		var option: int = entry
		var spot: CardSpot = RowTargets.resolve(zone_label, asked, option, own_size)
		if spot.is_valid():
			out.append(spot)
	return out


## The same for a seat view: `view.own_board` gives the asker's row size.
static func glow_set(prompt: Dictionary, view: SeatView) -> Array[CardSpot]:
	var own_size: int = 0 if view == null else view.own_board.size()
	return spots(prompt, own_size)


## What a tap on the card at `hit` does (R40-R44, C20). `lifted_option` is the lifted eligible
## card's option, -1 when nothing eligible is lifted. With nothing lifted, a glowing card lifts
## with the action button (LIFT_ELIGIBLE) and any other face-up card lifts to be read (LIFT).
## With an eligible card lifted, the same card or the table puts it down, another glowing card
## takes the lift (SWAP_LIFT) and another face-up card lifts to read. The prompt keeps waiting.
static func on_tap(
	hit: CardSpot, face_up: bool, prompt: Dictionary, own_size: int, lifted_option: int = -1
) -> PromptTap:
	var valid: bool = hit != null and hit.is_valid()
	var option: int = option_at(hit, prompt, own_size) if valid else -1
	return route(valid, option, face_up, lifted_option)


## The routing of on_tap for a tap that already knows its option (-1 when the target does not
## glow): the deck strip's entries come in this way. A multi prompt routes the same; only its
## button differs (action_tap).
static func route(valid: bool, option: int, face_up: bool, lifted_option: int = -1) -> PromptTap:
	if lifted_option >= 0:
		if not valid or option == lifted_option:
			return PromptTap.new(Tap.PUT_DOWN)
		if option >= 0:
			return PromptTap.new(Tap.SWAP_LIFT, option)
		return PromptTap.new(Tap.LIFT if face_up else Tap.PUT_DOWN)
	if option >= 0:
		return PromptTap.new(Tap.LIFT_ELIGIBLE, option)
	if valid and face_up:
		return PromptTap.new(Tap.LIFT)
	return PromptTap.new()


## What the action button does with the lifted option: a multi prompt toggles it in the
## selection, any other submits it (R42, R48).
static func action_tap(prompt: Dictionary, lifted_option: int) -> PromptTap:
	if lifted_option < 0:
		return PromptTap.new()
	var multi: bool = prompt.get("multi", false)
	return PromptTap.new(Tap.TOGGLE_SELECT if multi else Tap.CHOOSE, lifted_option)


## `selected` with `option` added, or removed when it was in (R48). Kept in ascending order.
static func toggled(selected: Array[int], option: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(selected)
	var at: int = out.find(option)
	if at >= 0:
		out.remove_at(at)
	else:
		out.append(option)
		out.sort()
	return out


## Whether the prompt shows the Skip button: only an optional prompt does (cycle 8 R63).
static func wants_skip(prompt: Dictionary) -> bool:
	var optional: bool = prompt.get("optional", false)
	return optional


## The banner text: a Crew prompt reads "<Crew name>: <rules text>" (R66), any other prompt its
## own text. An empty `crew_name` is a card prompt.
static func banner_text(text: String, crew_name: String) -> String:
	if crew_name == "":
		return text
	return "%s: %s" % [crew_name, text]


## The HUD confirm button's text for a multi prompt with `count` cards selected (R48, R80):
## "Discard 2" for the discard-down, "<Verb> <count>" for the rest.
static func confirm_text(prompt: Dictionary, count: int) -> String:
	var label: String = action_label(verb_name_of(prompt))
	if is_discard_down(prompt):
		label = "Discard"
	return "%s %d" % [label if label != "" else "Confirm", count]


## The option position the card at `hit` stands for, or -1 when it does not glow.
static func option_at(hit: CardSpot, prompt: Dictionary, own_size: int) -> int:
	var raw: Array = prompt.get("options", [])
	var found: Array[CardSpot] = spots(prompt, own_size)
	for i: int in range(found.size()):
		if same_spot(found[i], hit) and i < raw.size():
			var option: int = raw[i]
			return option
	return -1


## The action button's text for a prompt verb (R41, R49); empty for an unknown verb. A multi
## prompt's button names the toggle instead: "Select", or "Deselect" once the card is in.
static func action_label(verb: String, multi: bool = false, selected: bool = false) -> String:
	if multi and ACTION_LABELS.has(verb):
		return DESELECT_LABEL if selected else SELECT_LABEL
	var label: String = ACTION_LABELS.get(verb, "")
	return label


## The action button's text for an open prompt as the engine holds it
## (MatchEngine.open_prompt) (R41).
static func action_label_for(prompt: Dictionary, selected: bool = false) -> String:
	var multi: bool = prompt.get("multi", false)
	return action_label(verb_name_of(prompt), multi, selected)


static func same_spot(a: CardSpot, b: CardSpot) -> bool:
	return a.seat == b.seat and a.in_hand == b.in_hand and a.slot == b.slot


## Whether the runner must stop on `step` until a choice is accepted (R55): a PROMPT step
## when the human answers. Under autoplay seat 0's bot answers through play_bot().
static func waits(step: BoardStep, autoplay: bool) -> bool:
	return step.kind == BoardStep.Kind.PROMPT and not autoplay
