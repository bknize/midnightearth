class_name CrewLine
extends RefCounted
## Each side's three face-up Crew on the table (cycle 8 R59-R62, plan P17): a short Card3D line
## left of each hand, built from the match's SeatView (`crew` ids, `crew_uses`) and the Crew
## pool (names and rules text). A Crew shows a uses badge ("2 left", "spent"; none for an
## unlimited Crew), lifts and settles when its ability fires, and never drags: its collection
## sits outside the DragController and its strategy refuses every question.

## Where each seat's line rests: left of that seat's hand (index = seat).
const ORIGINS: Array[Vector3] = [Vector3(-26.0, -8.5, 0.0), Vector3(-26.0, 8.5, 0.0)]
const MAX_WIDTH: float = 11.0
## How far a firing Crew lifts toward the camera, and for how long at least.
const LIFT: float = 1.2
const MIN_TIME: float = 0.02
const CARD_SCENE: PackedScene = preload("res://board/board_card.tscn")
const COLLECTION_SCENE: PackedScene = preload("res://addons/card_3d/scenes/card_collection_3d.tscn")

## Per seat, the line's collection (null until built).
var _collections: Array[CardCollection3D] = [null, null]
## Per seat, the Crew cards in slot order.
var _cards: Array[Array] = [[], []]
## Per seat, the CrewDefs in slot order.
var _defs: Array[Array] = [[], []]


## The badge text for `uses_left` uses: "2 left", "1 left", "spent" at 0 and "" for the
## unlimited -1 (R60).
static func badge_text(uses_left: int) -> String:
	if uses_left < 0:
		return ""
	if uses_left == 0:
		return "spent"
	return "%d left" % uses_left


## Whether a Crew with `uses_left` uses is spent and dimmed.
static func is_spent(uses_left: int) -> bool:
	return uses_left == 0


## Lays out three Crew per seat under `parent` from `view` (its `crew` ids and `crew_uses`)
## and `pool` (names and text); frees any earlier line first. An id the pool lacks is skipped.
func build(parent: Node3D, view: SeatView, pool: CrewPool) -> void:
	clear()
	for seat: int in range(ORIGINS.size()):
		var made: CardCollection3D = COLLECTION_SCENE.instantiate() as CardCollection3D
		if made == null:
			push_warning("CrewLine: could not build the collection")
			return
		var layout: LineCardLayout = LineCardLayout.new()
		layout.max_width = MAX_WIDTH
		made.card_layout_strategy = layout
		var strategy: BoardDragStrategy = BoardDragStrategy.new()
		strategy.role = BoardDragStrategy.Role.CREW
		made.drag_strategy = strategy
		made.name = "CrewLine%d" % seat
		made.position = ORIGINS[seat]
		made.card_move_tween_duration = 0.01
		parent.add_child(made)
		var zone: Area3D = made.get_node_or_null("DropZone") as Area3D
		if zone != null:
			zone.input_ray_pickable = false
		_collections[seat] = made
		_fill(seat, made, view, pool)


## Frees both lines.
func clear() -> void:
	for seat: int in range(_collections.size()):
		var made: CardCollection3D = _collections[seat]
		if made != null and is_instance_valid(made):
			made.queue_free()
		_collections[seat] = null
		_cards[seat] = []
		_defs[seat] = []


## Whether `card` is one of the Crew cards.
func has_card(card: Card3D) -> bool:
	for seat: int in range(_cards.size()):
		if _cards[seat].has(card):
			return true
	return false


## The Crew card of `seat` at `slot`, or null.
func card_at(seat: int, slot: int) -> BoardCard:
	if seat < 0 or seat >= _cards.size() or slot < 0 or slot >= _cards[seat].size():
		return null
	var raw: Object = _cards[seat][slot]
	if not is_instance_valid(raw):
		return null
	return raw as BoardCard


## The badge text on `seat`'s Crew at `slot` ("" when none or unlimited).
func badge_of(seat: int, slot: int) -> String:
	var card: BoardCard = card_at(seat, slot)
	if card == null or card.badge == null:
		return ""
	return card.badge.text


## Whether `seat`'s Crew at `slot` is dimmed as spent.
func is_dimmed(seat: int, slot: int) -> bool:
	var card: BoardCard = card_at(seat, slot)
	return card != null and card.has_meta(&"crew_dim")


## Shows `uses_left` on `seat`'s Crew at `slot`: the badge text, and the dim when spent.
func set_uses(seat: int, slot: int, uses_left: int) -> void:
	var card: BoardCard = card_at(seat, slot)
	if card == null:
		return
	card.set_badge(badge_text(uses_left))
	var spent: bool = is_spent(uses_left)
	card.set_dim(spent)
	if spent:
		card.set_meta(&"crew_dim", true)
	elif card.has_meta(&"crew_dim"):
		card.remove_meta(&"crew_dim")


## Plays what a step means for the Crew: CREW_FIRE lifts the Crew and updates its badge, and
## CLEAR_TABLE (a new round) refills the per-round badges.
func note_step(step: BoardStep) -> void:
	if step.kind == BoardStep.Kind.CREW_FIRE:
		fire(step.seat, step.slot, step.uses_left, step.duration)
	elif step.kind == BoardStep.Kind.CLEAR_TABLE:
		new_round()


## A round starts: a per-round Crew's badge returns to its full uses (R60). A match-scope
## Crew keeps what is left.
func new_round() -> void:
	for seat: int in range(_defs.size()):
		for slot: int in range(_defs[seat].size()):
			var raw: Object = _defs[seat][slot]
			var def: CrewDef = raw as CrewDef
			if def != null and def.scope == CrewDef.Scope.ROUND:
				set_uses(seat, slot, def.uses)


## A Crew fires (CREW_FIRE, R61): it lifts toward the camera and settles over `seconds`, and
## its badge follows `uses_left`.
func fire(seat: int, slot: int, uses_left: int, seconds: float) -> void:
	set_uses(seat, slot, uses_left)
	var card: BoardCard = card_at(seat, slot)
	if card == null:
		return
	var mesh: Node3D = card.get_node("CardMesh") as Node3D
	var half: float = maxf(seconds, MIN_TIME) / 2.0
	var tween: Tween = card.create_tween()
	var up: PropertyTweener = tween.tween_property(mesh, "position:z", LIFT, half)
	var down: PropertyTweener = tween.tween_property(mesh, "position:z", 0.0, half)
	if up == null or down == null:
		mesh.position.z = 0.0


func _fill(seat: int, made: CardCollection3D, view: SeatView, pool: CrewPool) -> void:
	var ids: Array = view.crew[seat] if seat < view.crew.size() else []
	var uses: Array = view.crew_uses[seat] if seat < view.crew_uses.size() else []
	for slot: int in range(ids.size()):
		var crew_id: String = ids[slot]
		var def: CrewDef = pool.crew_of(crew_id)
		if def == null:
			push_warning("CrewLine: no Crew '%s' in the pool" % crew_id)
			continue
		var card: BoardCard = CARD_SCENE.instantiate() as BoardCard
		if card == null:
			continue
		made.append_card(card)
		card.show_crew(def.name, def.text)
		_cards[seat].append(card)
		_defs[seat].append(def)
		var left: int = uses[slot] if slot < uses.size() else -1
		set_uses(seat, _cards[seat].size() - 1, left)
