class_name BoardCard
extends Card3D
## One card on the board (R9, R41): placeholder face with name, cost, flat, bonus and rules
## text, and a shared plain back. Inherits the Card3D addon scene unchanged. Physics picking
## is off; the pointer shim raycasts instead.

const PULSE_SCALE: float = 1.4
const PULSE_TIME: float = 0.2
const GLOW_SIZE: Vector2 = Vector2(2.9, 3.9)
const GLOW_PEAK_ALPHA: float = 0.6
## Drawn after the prompt's dimmer (render priority 1), so a glowing card stays lit.
const GLOW_PRIORITY: int = 2
## The glow and the note sit this far in front of the face.
const GLOW_Z: float = 0.05
const NOTE_Z: float = 0.1
## A selected card (multi-select prompt, R48) stands this far in front of its slot.
const SELECT_RAISE: float = 0.03
const NOTE_COLOR: Color = Color(0.75, 0.1, 0.1, 1.0)
const NOTE_FONT_SIZE: int = 44

## The Crew look (cycle 8 R59, R60): the face is dimmed to this brightness once spent.
const CREW_DIM_BRIGHTNESS: float = 0.5
const CREW_DIM_ALPHA: float = 0.45
const BADGE_POSITION: Vector3 = Vector3(0.0, -1.4, 0.01)
const BADGE_FONT_SIZE: int = 44
const BADGE_COLOR: Color = Color(0.1, 0.25, 0.7, 1.0)

## The status badge words (R79): stacked just under the name.
const STATUS_POSITION: Vector3 = Vector3(0.0, 0.12, 0.01)
const STATUS_FONT_SIZE: int = 24
const STATUS_COLOR: Color = Color(0.55, 0.1, 0.55, 1.0)

## Engine instance id; -1 for an unrevealed opponent card.
var instance_id: int = -1
## A Crew card's uses badge, built by show_crew(); null on every other card.
var badge: Label3D = null

var _flat_pulse: Tween = null
var _bonus_pulse: Tween = null
var _cost_pulse: Tween = null
var _glow: MeshInstance3D = null
var _selected: bool = false
## The stacked badge words under the name (R79), built on first use.
var _badges: Label3D = null

@onready var _name_label: Label3D = $CardMesh/NameLabel
@onready var _cost_label: Label3D = $CardMesh/CostLabel
@onready var _flat_label: Label3D = $CardMesh/FlatLabel
@onready var _bonus_label: Label3D = $CardMesh/BonusLabel
@onready var _text_label: Label3D = $CardMesh/TextLabel
@onready var _grown_mark: Label3D = $CardMesh/GrownMark


## Dresses the face from a view entry (SeatView `own_hand_row`, `own_row`, `opponent_row`;
## spec R76, R79, plan P15, P17): the effective cost and `power`, the Bonus as `mult` or `add`
## (hundredths; "×1.25" or "+0.50"), the badge words from `statuses` and the grown mark when
## the card carries memory. A key the entry lacks falls back to the printed value of `def`
## (printed_numbers). The rules text stays the card's own (cycle 6 C23).
func show_entry(def: CardDef, entry: Dictionary) -> void:
	_name_label.text = def.name
	var cost: int = entry.get("cost", def.cost)
	_cost_label.text = str(cost)
	var printed: Vector3i = printed_numbers(def)
	var power: int = entry.get("power", printed.x)
	var mult: int = entry.get("mult", printed.y)
	var add: int = entry.get("add", printed.z)
	_set_numbers(power, mult, add)
	_text_label.text = rules_text(def)
	var grown: bool = entry.get("grown", false)
	_grown_mark.visible = grown
	var raw: Array = entry.get("statuses", [])
	var words: Array[String] = []
	for word: Variant in raw:
		var named: String = word
		words.append(BoardSteps.status_word(named))
	set_badges(words)


## Dresses the face as a Crew (cycle 8 R59): its name and rules text, no cost, flat or bonus,
## and a uses badge under the text. A Crew is not a card and has no instance id.
func show_crew(crew_name: String, text: String) -> void:
	_name_label.text = crew_name
	_text_label.text = text
	_cost_label.text = ""
	_flat_label.text = ""
	_bonus_label.visible = false
	_grown_mark.visible = false
	if badge == null:
		badge = Label3D.new()
		badge.name = "Badge"
		badge.pixel_size = 0.01
		badge.double_sided = false
		badge.outline_size = 0
		badge.font_size = BADGE_FONT_SIZE
		badge.modulate = BADGE_COLOR
		badge.position = BADGE_POSITION
		var mesh: Node3D = $CardMesh as Node3D
		mesh.add_child(badge)


## Sets the badge text; an empty text hides it (an unlimited Crew shows none, R60).
func set_badge(text: String) -> void:
	if badge == null:
		return
	badge.text = text
	badge.visible = text != ""


## Dims a spent Crew (R60): the face darkens and the labels fade. Own materials, made once.
func set_dim(on: bool) -> void:
	var shade: float = CREW_DIM_BRIGHTNESS if on else 1.0
	for part: String in ["CardBackMesh", "CardFrontMesh"]:
		var mesh: MeshInstance3D = get_node_or_null("CardMesh/" + part) as MeshInstance3D
		if mesh == null:
			continue
		var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if material == null:
			continue
		if not material.has_meta(&"crew_base"):
			material = material.duplicate() as StandardMaterial3D
			material.set_meta(&"crew_base", material.albedo_color)
			mesh.material_override = material
		var base: Color = material.get_meta(&"crew_base")
		material.albedo_color = Color(base.r * shade, base.g * shade, base.b * shade, base.a)
	for label: Label3D in [_name_label, _text_label, badge]:
		if label != null:
			label.modulate.a = CREW_DIM_ALPHA if on else 1.0


## The entry of card `id` in a view's rows, or an empty dictionary when it is not listed.
static func entry_in(rows: Array[Dictionary], id: int) -> Dictionary:
	for entry: Dictionary in rows:
		var named: int = entry.get("card", MatchEvent.HIDDEN_CARD)
		if named == id:
			return entry
	return {}


## Updates the shown Power and Bonus and pulses the label that changed (R76). The tweens are
## owned by the labels, so a card freed mid-pulse takes them along. A `cost` of 0 or more
## also updates the cost label, and `permanent` shows the grown mark (cycle 8 R25, R26).
func show_stats(
	power: int, mult: int, add: int, cost: int = -1, permanent: bool = false
) -> void:
	var power_changed: bool = _flat_label.text != str(power)
	var bonus_changed: bool = _bonus_label.text != bonus_text(mult, add)
	_set_numbers(power, mult, add)
	var cost_changed: bool = cost >= 0 and _cost_label.text != str(cost)
	if cost >= 0:
		_cost_label.text = str(cost)
	if permanent:
		_grown_mark.visible = true
	if cost_changed:
		_cost_pulse = _pulse(_cost_label, _cost_pulse)
	if power_changed:
		_flat_pulse = _pulse(_flat_label, _flat_pulse)
	if bonus_changed:
		_bonus_pulse = _pulse(_bonus_label, _bonus_pulse)


## Shows the status words stacked under the name, one per line (R79); an empty list hides it.
func set_badges(words: Array[String]) -> void:
	if _badges == null:
		if words.is_empty():
			return
		_badges = Label3D.new()
		_badges.name = "Badges"
		_badges.pixel_size = 0.01
		_badges.double_sided = false
		_badges.outline_size = 0
		_badges.font_size = STATUS_FONT_SIZE
		_badges.modulate = STATUS_COLOR
		_badges.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_badges.position = STATUS_POSITION
		var mesh: Node3D = $CardMesh as Node3D
		mesh.add_child(_badges)
	_badges.text = "\n".join(words)
	_badges.visible = not words.is_empty()


## The words after `word` is set (`on`) or ended on a card showing `words` (R79): Muted and
## Squelched together read Silenced, and ending one half of a Silenced card leaves the other.
static func badges_after(words: Array[String], word: String, on: bool) -> Array[String]:
	var out: Array[String] = []
	out.assign(words)
	if on:
		if word == "Silenced":
			out.erase("Muted")
			out.erase("Squelched")
		if not out.has(word):
			out.append(word)
		if out.has("Muted") and out.has("Squelched"):
			out.erase("Muted")
			out.erase("Squelched")
			out.append("Silenced")
		return out
	if out.has("Silenced") and (word == "Muted" or word == "Squelched"):
		out.erase("Silenced")
		out.append("Squelched" if word == "Muted" else "Muted")
		return out
	out.erase(word)
	return out


## The badge words on show, top to bottom (R79).
func badge_words() -> Array[String]:
	var out: Array[String] = []
	if _badges == null or not _badges.visible:
		return out
	out.assign(_badges.text.split("\n"))
	return out


## Shows the shared `Glow` child (the DC-04 ZoneGlow look, T12 prompts use it too) at `alpha`.
## `source` is the board's zone-glow material; each card keeps its own copy to fade.
func set_glow(source: Material, alpha: float) -> void:
	if _glow == null:
		_glow = MeshInstance3D.new()
		_glow.name = "Glow"
		var quad: QuadMesh = QuadMesh.new()
		quad.size = GLOW_SIZE
		_glow.mesh = quad
		_glow.position = Vector3(0.0, 0.0, GLOW_Z)
		add_child(_glow)
	var material: StandardMaterial3D = _glow.material_override as StandardMaterial3D
	if material == null:
		material = source.duplicate() as StandardMaterial3D
		if material == null:
			return
		material.render_priority = GLOW_PRIORITY
		_glow.material_override = material
	material.albedo_color = Color(material.albedo_color, alpha)
	_glow.visible = alpha > 0.0


## Raises the card to show it is in the prompt's selection, or sets it back (R48).
func set_selected(on: bool) -> void:
	_selected = on
	var mesh: Node3D = get_node_or_null("CardMesh") as Node3D
	if mesh != null:
		mesh.position.z = SELECT_RAISE if on else 0.0


func is_selected() -> bool:
	return _selected


func clear_glow() -> void:
	if _glow != null:
		_glow.visible = false


## Glows and fades out over `seconds` (the opponent's pick, R53). The tween belongs to the
## glow node, so a card freed mid-glow takes it along.
func pulse_glow(source: Material, seconds: float) -> void:
	set_glow(source, GLOW_PEAK_ALPHA)
	var material: StandardMaterial3D = _glow.material_override as StandardMaterial3D
	if material == null:
		return
	var tween: Tween = _glow.create_tween()
	var fade: MethodTweener = tween.tween_method(
		_fade_glow.bind(source), GLOW_PEAK_ALPHA, 0.0, maxf(seconds, 0.01)
	)
	if fade == null:
		clear_glow()


## Shows `text` on the card and fades it over `seconds` (FIZZLE, R53). The label and its tween
## are children of the card.
func flash_note(text: String, seconds: float) -> void:
	var note: Label3D = Label3D.new()
	note.text = text
	note.pixel_size = 0.01
	note.font_size = NOTE_FONT_SIZE
	note.modulate = NOTE_COLOR
	note.outline_size = 0
	note.position = Vector3(0.0, 0.0, NOTE_Z)
	add_child(note)
	var tween: Tween = note.create_tween()
	var fade: PropertyTweener = tween.tween_property(note, "modulate:a", 0.0, maxf(seconds, 0.01))
	if fade == null:
		note.queue_free()
		return
	var err: int = tween.finished.connect(note.queue_free)
	if err != OK:
		note.queue_free()


func clear_def() -> void:
	set_badges([])
	_name_label.text = ""
	_cost_label.text = ""
	_flat_label.text = ""
	_bonus_label.text = ""
	_bonus_label.visible = false
	_text_label.text = ""
	_grown_mark.visible = false


## Copies the face text and the face-up/down state from another card.
func copy_face_from(other: BoardCard) -> void:
	_name_label.text = other._name_label.text
	_cost_label.text = other._cost_label.text
	_flat_label.text = other._flat_label.text
	_bonus_label.text = other._bonus_label.text
	_bonus_label.visible = other._bonus_label.visible
	_text_label.text = other._text_label.text
	_grown_mark.visible = other._grown_mark.visible
	set_badges(other.badge_words())
	face_down = other.face_down
	instance_id = other.instance_id


func _fade_glow(alpha: float, source: Material) -> void:
	set_glow(source, alpha)


func _set_numbers(power: int, mult: int, add: int) -> void:
	_flat_label.text = str(power)
	_bonus_label.text = bonus_text(mult, add)
	_bonus_label.visible = _bonus_label.text != ""


## The printed Power, Mult (hundredths; 100 is none) and Add (hundredths) of a definition as
## (x, y, z), the fallback for a view entry that lacks a key.
static func printed_numbers(def: CardDef) -> Vector3i:
	return Vector3i(def.power, def.printed_mult(), def.printed_add())


## The rules text of a face: the card's printed text, empty for a plain body (cycle 9 R22).
static func rules_text(def: CardDef) -> String:
	return def.text


## Whether a face `mult` (hundredths) names a Mult: 0 and 100 both mean none.
static func has_mult(mult: int) -> bool:
	return mult != 0 and mult != ScoreChips.HUNDRED


## The face's Bonus text from a hundredths `mult` and a hundredths `add`: "×1.25", "+0.50",
## "×1.25 +0.50" when a card carries both, and "" for a card with neither (R76).
static func bonus_text(mult: int, add: int) -> String:
	var parts: Array[String] = []
	if has_mult(mult):
		parts.append(ScoreChips.mult_text(mult))
	if add != 0:
		parts.append(ScoreChips.add_text(add))
	return " ".join(parts)


func _pulse(label: Label3D, running: Tween) -> Tween:
	if running != null and running.is_valid():
		running.kill()
	label.scale = Vector3.ONE
	var tween: Tween = label.create_tween()
	var up: PropertyTweener = tween.tween_property(
		label, "scale", Vector3.ONE * PULSE_SCALE, PULSE_TIME * 0.5
	)
	var down: PropertyTweener = tween.tween_property(label, "scale", Vector3.ONE, PULSE_TIME * 0.5)
	if up == null or down == null:
		label.scale = Vector3.ONE
	return tween
