class_name ScoreChips
extends Node3D
## The chips above a scoring card (R31, plan P12, P17): a "+P" for its Power in the seat's
## colour, then a gold "×B" when its Bonus value is not 1, each rising and fading over
## CHIP_TIME. A pulse the engine sent no score for shows nothing. The text and timing are
## pure statics; spawn() makes the Label3Ds as children, each owning its tween.

const CHIP_TIME: float = 0.25
const RISE: float = 1.2
## Where a chip starts, relative to the card's centre: above it and toward the camera.
const START_OFFSET: Vector3 = Vector3(0.0, 2.6, 1.5)
const MULT_COLOR: Color = Color(1.0, 0.85, 0.3, 1.0)
const SEAT_COLORS: Array[Color] = [Color(0.5, 0.85, 1.0, 1.0), Color(1.0, 0.55, 0.5, 1.0)]
const PIXEL_SIZE: float = 0.012
const FONT_SIZE: int = 96
const OUTLINE_SIZE: int = 24


## Ten-thousandths in one whole (mirrors MatchRules.SCALE, spec P1; the walking total, the
## Bonus value and the HUD Score all count in it).
const SCALE: int = 10000
## Hundredths in one whole (the face's Bonus and the Bonus chip).
const HUNDRED: int = 100
## Ten-thousandths in one hundredth.
const PER_HUNDREDTH: int = 100


## `value / divisor` rounded half up, on ints: 437.5 reads 438 and -149.5 reads -149 (P7).
static func half_up(value: int, divisor: int) -> int:
	return floori(float(2 * value + divisor) / float(2 * divisor))


## The mult as text, two decimals, from hundredths: 156 reads "×1.56" (R45).
static func mult_text(mult: int) -> String:
	return "×%.2f" % (float(mult) / float(HUNDRED))


## An add as text, two decimals, from hundredths: 50 reads "+0.50", -25 reads "-0.25" (R76).
static func add_text(add: int) -> String:
	var sign_text: String = "-" if add < 0 else "+"
	return "%s%.2f" % [sign_text, float(absi(add)) / float(HUNDRED)]


## A walking total (ten-thousandths) as text: "4.38" while it has a fraction (two decimals,
## rounded half up), "16" when it has none, "-1.50" below zero (R77, round 3 3a).
static func total_text(total: int) -> String:
	if total % SCALE == 0:
		return str(floori(float(total) / float(SCALE)))
	var hundredths: int = half_up(total, PER_HUNDREDTH)
	var sign_text: String = "-" if hundredths < 0 else ""
	return "%s%.2f" % [sign_text, float(absi(hundredths)) / float(HUNDRED)]


## The rounded Score of a walking total (the HUD shows it at Walk end): 43750 reads 4.
static func score_of(total: int) -> int:
	return half_up(total, SCALE)


## Whether the pulse's Bonus value changed the total: anything but SCALE.
static func has_bonus(step: BoardStep) -> bool:
	return step.bonus_value != SCALE


## The chip texts of a pulse step, in order: ["+P", "×B"] or ["+P"], or [] when the engine
## sent no CARD_SCORED for the card (R31): the Power rises first, then the Bonus multiplies.
static func chip_texts(step: BoardStep) -> Array[String]:
	var texts: Array[String] = []
	if not step.scored:
		return texts
	texts.append("%+d" % step.power)
	if has_bonus(step):
		texts.append(mult_text(half_up(step.bonus_value, PER_HUNDREDTH)))
	return texts


## Seconds at 1x the chips of `step` take.
static func chips_time(step: BoardStep) -> float:
	return CHIP_TIME * float(chip_texts(step).size())


## The colour of a seat's "+N" chip and tally.
static func seat_color(seat: int) -> Color:
	return SEAT_COLORS[clampi(seat, 0, SEAT_COLORS.size() - 1)]


## Spawns the chips for `step` above `card`. `speed` divides every duration (R36).
func spawn(card: Node3D, step: BoardStep, speed: float) -> void:
	var texts: Array[String] = chip_texts(step)
	var divisor: float = speed if speed > 0.0 else 1.0
	for i: int in range(texts.size()):
		var is_mult: bool = has_bonus(step) and i == 1
		var color: Color = MULT_COLOR if is_mult else seat_color(step.seat)
		var delay: float = step.chip_delay + float(i) * CHIP_TIME / divisor
		_chip(texts[i], color, card.global_position, delay, divisor)


## Frees every chip now.
func clear() -> void:
	for child: Node in get_children():
		child.queue_free()


func _chip(text: String, color: Color, origin: Vector3, delay: float, divisor: float) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = PIXEL_SIZE
	label.font_size = FONT_SIZE
	label.outline_size = OUTLINE_SIZE
	label.render_priority = 2
	label.outline_render_priority = 1
	label.visible = false
	add_child(label)
	var start: Vector3 = origin + START_OFFSET
	label.global_position = start
	var seconds: float = CHIP_TIME / divisor
	var tween: Tween = label.create_tween()
	tween = tween.set_parallel(true)
	var shown: CallbackTweener = tween.tween_callback(label.show)
	shown = shown.set_delay(delay)
	var rise: PropertyTweener = tween.tween_property(
		label, "global_position:y", start.y + RISE, seconds
	)
	rise = rise.set_delay(delay)
	var fade: PropertyTweener = tween.tween_property(label, "modulate:a", 0.0, seconds)
	fade = fade.set_delay(delay)
	var done: CallbackTweener = tween.chain().tween_callback(label.queue_free)
	assert(done != null)
