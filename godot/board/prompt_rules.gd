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
	"swap_places": "Swap",
	"draw_then_discard": "Discard",
	"return_at_turn_end": "Return",
	"discard_own": "Discard",
	"destroy_own_then_draw": "Destroy",
	"destroy_own_then_flat_up": "Destroy",
	"sacrifice_destroy": "Destroy",
	"copy_stats": "Copy",
	"move_opponent_left": "Move",
	"swap_opponent_right": "Swap",
	"recover_destroyed": "Recover",
}
const SELECT_LABEL: String = "Select"
const DESELECT_LABEL: String = "Deselect"


## The spots to glow, in option order (R55). `own_size` is the asker's row size, which splits
## `both_boards`. The opponent's hand is found by fan index; its cards glow as backs and are
## chosen by position (R30, C10). An unknown zone gives no spots.
static func spots(prompt: Dictionary, own_size: int) -> Array[CardSpot]:
	var out: Array[CardSpot] = []
	if prompt.is_empty():
		return out
	var asked: int = prompt.get("seat", 0)
	var zone_label: String = Choice.zone_name(Choice.zone_of(prompt))
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


## The HUD confirm button's text for a multi prompt with `count` cards selected (R48).
static func confirm_text(prompt: Dictionary, count: int) -> String:
	var label: String = action_label(verb_of(prompt))
	return "%s %d" % [label if label != "" else "Confirm", count]


## The verb name of a prompt (the engine holds it by name since DC-13 T02), "" when absent.
static func verb_of(prompt: Dictionary) -> String:
	var raw: Variant = prompt.get("verb", "")
	if not raw is String:
		return ""
	var verb: String = raw
	return verb


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
## (MatchEngine.open_prompt): its `verb` is the verb's name (R41).
static func action_label_for(prompt: Dictionary, selected: bool = false) -> String:
	var multi: bool = prompt.get("multi", false)
	return action_label(verb_of(prompt), multi, selected)


static func same_spot(a: CardSpot, b: CardSpot) -> bool:
	return a.seat == b.seat and a.in_hand == b.in_hand and a.slot == b.slot


## Whether the runner must stop on `step` until a choice is accepted (R55): a PROMPT step
## when the human answers. Under autoplay seat 0's bot answers through play_bot().
static func waits(step: BoardStep, autoplay: bool) -> bool:
	return step.kind == BoardStep.Kind.PROMPT and not autoplay
