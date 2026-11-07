class_name HandTelegraph
extends RefCounted
## The telegraph of a public hand trigger of the opponent (cycle 9 spec C14, rules-v2 section
## 8): the opponent's fan is all backs, so a ghost of the card rises from the hand's centre
## toward the viewer, flipping face up to show its name and rules text, holds, then sinks
## back face down and is freed. The fan itself never changes. The ghost lives on the board's
## loose layer, so a table clear frees it with the rest; its tweens belong to it.

const CARD_SCENE: PackedScene = preload("res://board/board_card.tscn")
## Where the ghost holds, from the opponent hand's origin: down toward the table and toward
## the camera, so it sits in front of the opponent's row.
const SHOW_OFFSET: Vector3 = Vector3(0.0, -3.0, 3.0)
const SHOW_SCALE: float = 1.25
## Shares of the step's time: the rise (and flip up), and the return (and flip down); the
## rest is the hold.
const RISE_SHARE: float = 0.25
const BACK_SHARE: float = 0.2
const MIN_TIME: float = EffectPlayer.MIN_TWEEN_TIME


## Plays the telegraph of `step` (TELEGRAPH: `card`, `reason`) over `step.duration`. Returns
## the ghost, or null when the card has no definition or there is nowhere to show it.
static func play(
	step: BoardStep, hand: CardCollection3D, layer: Node3D, cards: MatchCards
) -> BoardCard:
	if hand == null or layer == null or cards == null or step.card < 0:
		return null
	var def: CardDef = cards.def_of(step.card)
	if def == null:
		return null
	var ghost: BoardCard = CARD_SCENE.instantiate() as BoardCard
	if ghost == null:
		return null
	layer.add_child(ghost)
	ghost.disable_collision()
	ghost.show_entry(def, {})
	var start: Vector3 = hand.global_position
	ghost.global_position = start
	ghost.face_down = true
	var total: float = maxf(step.duration, MIN_TIME)
	var rise: float = maxf(total * RISE_SHARE, MIN_TIME)
	var back: float = maxf(total * BACK_SHARE, MIN_TIME)
	var hold: float = maxf(total - rise - back, MIN_TIME)
	var mesh: Node3D = ghost.get_node("CardMesh") as Node3D
	var tween: Tween = ghost.create_tween()
	var shown: Vector3 = Vector3.ONE * SHOW_SCALE
	_step(tween, ghost, ^"global_position", start + SHOW_OFFSET, rise, false)
	_step(tween, ghost, ^"scale", shown, rise, true)
	_step(tween, mesh, ^"rotation:y", 0.0, rise, true)
	var waited: IntervalTweener = tween.tween_interval(hold)
	_step(tween, ghost, ^"global_position", start, back, false)
	_step(tween, ghost, ^"scale", Vector3.ONE, back, true)
	_step(tween, mesh, ^"rotation:y", PI, back, true)
	var err: int = tween.finished.connect(ghost.queue_free)
	if waited == null or err != OK:
		ghost.queue_free()
		return null
	if step.reason != "":
		ghost.flash_note(EffectPlayer.fizzle_note(step.reason), rise + hold)
	return ghost


## Adds one eased property step to `tween`, run alongside the previous one when `together`.
static func _step(
	tween: Tween, target: Object, property: NodePath, value: Variant, seconds: float, together: bool
) -> void:
	var chained: Tween = tween.parallel() if together else tween
	var tweener: PropertyTweener = chained.tween_property(target, property, value, seconds)
	tweener = tweener.set_trans(Tween.TRANS_SINE)
	tweener = tweener.set_ease(Tween.EASE_IN_OUT)
