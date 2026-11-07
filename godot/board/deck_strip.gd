class_name DeckStrip
extends RefCounted
## A temporary line of cards above the rows for viewing and choosing from an off-screen
## collection (DC-07 R47, C19, plan P16; spec R78, plan P17): a Pile face up, in Pile order,
## when a prompt targets it or its count is tapped; the opponent's Pile is public too. It is
## built from a list of entries (an instance id, or MatchEvent.HIDDEN_CARD for a card the
## viewer may not see, shown as a back), the entries that may be chosen, and a callback; it
## knows nothing of the verb that opened it. The DC-06 reader and
## its action button sit on top of it as for any other eligible card.

## The strip rests on the opponent's Crew level, right of its Crew line and left of the HUD's
## top-right buttons, so it covers neither row, either Crew line nor the HUD (NSC-163). It may
## cover the opponent's hand, which is all backs. World units; the camera sits 30 from the
## table with a 45 degree vertical fov, so its half width is aspect * VIEW_HALF_HEIGHT.
const REST_Y: float = 8.8
const REST_Z: float = 0.5
const CARD_HEIGHT: float = 3.5
## Left of this x the opponent's Crew line (x -11.75 to -3.25) sits.
const LEFT_EDGE: float = -2.5
const MAX_RIGHT_EDGE: float = 17.0
## The HUD's top-right Pause button reaches this far in from the view's edge.
const HUD_MARGIN: float = 4.2
const VIEW_HALF_HEIGHT: float = 12.43
const DEFAULT_ASPECT: float = 16.0 / 9.0
const MIN_WIDTH: float = 6.0
## The strip slides in from, and out to, this far above its resting place.
const SLIDE: Vector3 = Vector3(0.0, 9.0, 0.0)
const GLOW_ALPHA: float = 0.55
## Meta keys on a strip card: its entry's index, and (for a pile) the pile and place it came
## from, so a hidden entry can be found when the engine names it by position.
const META_ENTRY: StringName = &"strip_entry"
const META_SEAT: StringName = &"strip_seat"
const META_POSITION: StringName = &"strip_position"
const COLLECTION_SCENE: PackedScene = preload("res://addons/card_3d/scenes/card_collection_3d.tscn")

var collection: CardCollection3D = null
## The viewport's width over height when the strip is next shown (sets its width).
var aspect: float = DEFAULT_ASPECT

var _rest: Vector3 = Vector3.ZERO
var _eligible: Array[int] = []
var _on_choose: Callable = Callable()


## The strip's world rectangle (x, y of its corner and size) for a viewport of `ratio`
## (width / height): from LEFT_EDGE to the narrower of MAX_RIGHT_EDGE and the HUD's margin, at
## the opponent Crew's height.
static func rect_for(ratio: float) -> Rect2:
	var half_width: float = (ratio if ratio > 0.0 else DEFAULT_ASPECT) * VIEW_HALF_HEIGHT
	var right: float = minf(MAX_RIGHT_EDGE, half_width - HUD_MARGIN)
	right = maxf(right, LEFT_EDGE + MIN_WIDTH)
	return Rect2(LEFT_EDGE, REST_Y - CARD_HEIGHT / 2.0, right - LEFT_EDGE, CARD_HEIGHT)


func is_up() -> bool:
	return collection != null and is_instance_valid(collection)


## Lays `entries` out under `parent`, sliding in over `seconds`. `eligible` lists the entry
## indices that may be chosen (they glow); `make_card` returns a fresh BoardCard; `def_of`
## takes an instance id and returns its CardDef; `on_choose` takes the chosen entry index.
## `piles` optionally names, per entry, the pile `[seat, position]` it came from. `memory_of`
## optionally takes an instance id and returns its view entry (cost, stats, grown: card
## memory, cycle 8 R25), so the strip's faces carry the mark; without it they show printed.
func show(
	parent: Node3D,
	entries: Array[int],
	eligible: Array[int],
	make_card: Callable,
	def_of: Callable,
	glow: Material,
	on_choose: Callable,
	seconds: float = 0.0,
	piles: Array[Vector2i] = [],
	memory_of: Callable = Callable()
) -> void:
	hide(0.0)
	_eligible = eligible.duplicate()
	_on_choose = on_choose
	var made: CardCollection3D = COLLECTION_SCENE.instantiate() as CardCollection3D
	if made == null:
		push_warning("DeckStrip: could not build the collection")
		return
	var layout: LineCardLayout = LineCardLayout.new()
	var area: Rect2 = rect_for(aspect)
	layout.max_width = area.size.x
	made.card_layout_strategy = layout
	_rest = Vector3(area.position.x + area.size.x / 2.0, REST_Y, REST_Z)
	made.position = _rest + SLIDE
	parent.add_child(made)
	var zone: Area3D = made.get_node_or_null("DropZone") as Area3D
	if zone != null:
		zone.input_ray_pickable = false
	collection = made
	made.card_move_tween_duration = EffectPlayer.MIN_TWEEN_TIME
	for index: int in range(entries.size()):
		var raw: Object = make_card.call()
		var card: BoardCard = raw as BoardCard
		if card == null:
			continue
		made.append_card(card)
		card.set_meta(META_ENTRY, index)
		if index < piles.size():
			card.set_meta(META_SEAT, piles[index].x)
			card.set_meta(META_POSITION, piles[index].y)
		_dress(card, entries[index], def_of, memory_of)
		if _eligible.has(index) and glow != null:
			card.set_glow(glow, GLOW_ALPHA)
	_slide(made, _rest, seconds, false)


## Slides the strip away over `seconds` and frees it. No-op when it is not up.
func hide(seconds: float) -> void:
	if not is_up():
		collection = null
		return
	var gone: CardCollection3D = collection
	collection = null
	_eligible.clear()
	_on_choose = Callable()
	_slide(gone, _rest + SLIDE, seconds, true)


## Whether `card` is one of the strip's cards.
func has_card(card: Card3D) -> bool:
	return is_up() and collection.cards.has(card)


## The entry index of a strip card, or -1.
func entry_of(card: Card3D) -> int:
	if not has_card(card):
		return -1
	var index: int = card.get_meta(META_ENTRY, -1)
	return index


## The entry index of a strip card if it may be chosen, else -1.
func option_of(card: Card3D) -> int:
	var index: int = entry_of(card)
	return index if _eligible.has(index) else -1


## The strip card that came from `seat`'s pile at `position`, or null.
func card_from(seat: int, position: int) -> Card3D:
	if not is_up():
		return null
	for card: Card3D in collection.cards:
		var from_seat: int = card.get_meta(META_SEAT, -1)
		var from_position: int = card.get_meta(META_POSITION, -1)
		if from_seat == seat and from_position == position:
			return card
	return null


## Picks entry `index`: calls the callback with it. False when the entry may not be chosen.
func choose(index: int) -> bool:
	if not _eligible.has(index) or not _on_choose.is_valid():
		return false
	_on_choose.call(index)
	return true


static func _dress(card: BoardCard, entry: int, def_of: Callable, memory_of: Callable) -> void:
	if entry == MatchEvent.HIDDEN_CARD:
		card.face_down = true
		return
	card.instance_id = entry
	var raw: Object = def_of.call(entry)
	var def: CardDef = raw as CardDef
	if def == null:
		return
	var memory: Dictionary = {}
	if memory_of.is_valid():
		var found: Variant = memory_of.call(entry)
		if found is Dictionary:
			memory = found
	card.show_entry(def, memory)


static func _slide(node: Node3D, to: Vector3, seconds: float, free_after: bool) -> void:
	if seconds <= 0.0 or not node.is_inside_tree():
		node.position = to
		if free_after:
			node.queue_free()
		return
	var tween: Tween = node.create_tween()
	var step: PropertyTweener = tween.tween_property(node, "position", to, seconds)
	if step == null:
		node.position = to
	if free_after:
		var done: CallbackTweener = tween.tween_callback(node.queue_free)
		if done == null:
			node.queue_free()
