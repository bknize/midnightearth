class_name ScoreChips
extends Node3D
## The chips above a scoring card (R31, plan P12): a gold "×M" when the card's bonus is not 0,
## then a "+N" in the seat's colour, each rising and fading over CHIP_TIME. A destroyed pulse,
## or one the engine sent no score for, shows nothing. The text and timing are pure statics;
## spawn() makes the Label3Ds as children, each owning its tween.

const CHIP_TIME: float = 0.25
const RISE: float = 1.2
## Where a chip starts, relative to the card's centre: above it and toward the camera.
const START_OFFSET: Vector3 = Vector3(0.0, 2.6, 1.5)
const MULT_COLOR: Color = Color(1.0, 0.85, 0.3, 1.0)
const SEAT_COLORS: Array[Color] = [Color(0.5, 0.85, 1.0, 1.0), Color(1.0, 0.55, 0.5, 1.0)]
const PIXEL_SIZE: float = 0.012
const FONT_SIZE: int = 96
const OUTLINE_SIZE: int = 24


## The chip texts of a pulse step, in order: ["×M", "+N"], ["+N"], or [] (R31, R28).
static func chip_texts(step: BoardStep) -> Array[String]:
	var texts: Array[String] = []
	if step.destroyed or step.score < 0:
		return texts
	if step.bonus != 0:
		texts.append("×%d" % step.mult)
	texts.append("+%d" % step.added)
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
		var is_mult: bool = step.bonus != 0 and i == 0
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
