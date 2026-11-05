class_name TestBoardReviewMemory
extends GdUnitTestSuite
## The T06 review fixes on the board (cycle 8 R7, R25): the reveal's public cost and grown
## mark reach the step and the opponent's face, a hidden row burn names its slot, a spent
## fizzle says so, and the recover strip dresses pile cards from the view's entries.

const CARD_SCENE: PackedScene = preload("res://board/board_card.tscn")


func _card() -> BoardCard:
	var node: Node = CARD_SCENE.instantiate()
	var card: BoardCard = node as BoardCard
	auto_free(card)
	add_child(card)
	return card


func _def() -> CardDef:
	var def: CardDef = CardDef.new()
	def.name = "Sapling"
	def.cost = 3
	def.flat = 2
	return def


func _label(card: BoardCard, node_name: String) -> Label3D:
	return card.get_node("CardMesh/%s" % node_name) as Label3D


func _steps(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> Array[BoardStep]:
	var events: Array[MatchEvent] = [MatchEvent.new(kind, payload, owner)]
	return BoardSteps.from_events(events, 1.0, 0)


func test_a_reveal_step_carries_cost_and_grown() -> void:
	var payload: Dictionary = {
		"seat": 1, "card": 25, "slot": 0, "order": 0, "cost": 2, "grown": true, "flat": 4,
		"times": 175, "plus": 0,
	}
	var steps: Array[BoardStep] = _steps(MatchEvent.Kind.CARD_REVEALED, payload)
	assert_int(steps.size()).is_equal(1)
	assert_int(steps[0].cost).is_equal(2)
	assert_bool(steps[0].grown).is_true()
	var entry: Dictionary = EffectPlayer.reveal_entry(steps[0])
	var times: int = entry.get("times", 0)
	assert_int(times).is_equal(175)


func test_a_reveal_without_a_cost_gives_no_entry() -> void:
	var payload: Dictionary = {"seat": 1, "card": 25, "slot": 0, "order": 0}
	var steps: Array[BoardStep] = _steps(MatchEvent.Kind.CARD_REVEALED, payload)
	assert_bool(EffectPlayer.reveal_entry(steps[0]).is_empty()).is_true()


func test_an_opponent_reveal_entry_shows_the_mark_and_bonus() -> void:
	var payload: Dictionary = {
		"seat": 1, "card": 25, "slot": 0, "order": 0, "cost": 2, "grown": true, "flat": 4,
		"times": 175, "plus": 0,
	}
	var steps: Array[BoardStep] = _steps(MatchEvent.Kind.CARD_REVEALED, payload)
	var card: BoardCard = _card()
	card.show_entry(_def(), EffectPlayer.reveal_entry(steps[0]))
	assert_bool(_label(card, "GrownMark").visible).is_true()
	assert_str(_label(card, "BonusLabel").text).is_equal("×1.75")
	assert_str(_label(card, "CostLabel").text).is_equal("2")


func test_a_redacted_row_burn_keeps_its_row_and_slot() -> void:
	var payload: Dictionary = {"seat": 1, "card": -1, "slot": 2, "row_seat": 1}
	var steps: Array[BoardStep] = _steps(MatchEvent.Kind.CARD_BURNED, payload)
	assert_int(steps.size()).is_equal(1)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.BURN)
	assert_int(steps[0].row_seat).is_equal(1)
	assert_int(steps[0].slot).is_equal(2)
	var hand: Array[BoardStep] = _steps(MatchEvent.Kind.CARD_BURNED, {"seat": 1, "card": -1})
	assert_int(hand[0].row_seat).is_equal(-1)


func test_a_spent_fizzle_keeps_its_reason() -> void:
	var payload: Dictionary = {"seat": 0, "card": 5, "verb": "draw_once", "reason": "spent"}
	var steps: Array[BoardStep] = _steps(MatchEvent.Kind.EFFECT_FIZZLED, payload)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.FIZZLE)
	assert_str(steps[0].reason).is_equal("spent")
	assert_str(EffectPlayer.fizzle_note(steps[0].reason)).is_equal("spent")
	assert_str(EffectPlayer.fizzle_note("no_target")).is_equal("no target")
	assert_str(EffectPlayer.fizzle_note("")).is_equal("no target")


func test_the_strip_dresses_a_pile_card_from_its_entry() -> void:
	var parent: Node3D = Node3D.new()
	auto_free(parent)
	add_child(parent)
	var made: Array[BoardCard] = []
	var spawn: Callable = func() -> BoardCard:
		var fresh: BoardCard = _card()
		made.append(fresh)
		return fresh
	var def: CardDef = _def()
	var def_of: Callable = func(_id: int) -> CardDef: return def
	var grown: Dictionary = {"cost": 2, "flat": 4, "times": 175, "plus": 0, "grown": true}
	var entry_of: Callable = func(_id: int) -> Dictionary: return grown
	var strip: DeckStrip = DeckStrip.new()
	var ids: Array[int] = [7]
	var none: Array[int] = []
	strip.show(parent, ids, none, spawn, def_of, null, Callable(), 0.0, [], entry_of)
	assert_int(made.size()).is_equal(1)
	assert_bool(_label(made[0], "GrownMark").visible).is_true()
	assert_str(_label(made[0], "BonusLabel").text).is_equal("×1.75")
	strip.hide(0.0)
