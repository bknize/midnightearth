class_name PromptRules
extends RefCounted
## Pure rules for the prompt UI (R30, R55, R56, C10, C16, plan P19). It works on positions,
## never nodes: a prompt's options are positions in its zone (a hand in hand order, a row in
## slot order, `both_boards` the asker's row then the other's), mapped to table spots through
## RowTargets. The board maps spots to cards. The prompt is seat 0's own.

## What a tap does while a prompt is open.
enum Tap { NOTHING, CHOOSE, LIFT }


## The spots to glow, in option order (R55). `own_size` is the asker's row size, which splits
## `both_boards`. The opponent's hand is found by fan index; its cards glow as backs and are
## chosen by position (R30, C10). An unknown zone gives no spots.
static func spots(prompt: Dictionary, own_size: int) -> Array[CardSpot]:
	var out: Array[CardSpot] = []
	if prompt.is_empty():
		return out
	var asked: int = prompt.get("seat", 0)
	var zone: int = prompt.get("zone", Choice.NO_ZONE)
	var zone_label: String = Choice.zone_name(zone)
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


## What a tap on the card at `hit` does (R56, C16). A glowing card chooses, face up or down.
## Any other face-up card lifts so it can be read. Everything else, a miss or a face-down
## card that is not eligible, does nothing. The prompt keeps waiting either way.
static func on_tap(hit: CardSpot, face_up: bool, prompt: Dictionary, own_size: int) -> PromptTap:
	if hit == null or not hit.is_valid():
		return PromptTap.new()
	var raw: Array = prompt.get("options", [])
	var found: Array[CardSpot] = spots(prompt, own_size)
	for i: int in range(found.size()):
		if same_spot(found[i], hit) and i < raw.size():
			var option: int = raw[i]
			return PromptTap.new(Tap.CHOOSE, option)
	if face_up:
		return PromptTap.new(Tap.LIFT)
	return PromptTap.new()


static func same_spot(a: CardSpot, b: CardSpot) -> bool:
	return a.seat == b.seat and a.in_hand == b.in_hand and a.slot == b.slot


## Whether the runner must stop on `step` until a choice is accepted (R55): a PROMPT step
## when the human answers. Under autoplay seat 0's bot answers through play_bot().
static func waits(step: BoardStep, autoplay: bool) -> bool:
	return step.kind == BoardStep.Kind.PROMPT and not autoplay
