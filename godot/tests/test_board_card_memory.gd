class_name TestBoardCardMemory
extends GdUnitTestSuite
## BoardCard faces (spec R76, R79; cycle 8 P16 R24, R25): the effective cost, the grown mark,
## the Power and Bonus text ("×1.25", "+0.50") and the stacked badge words. Node queries on the
## CostLabel, BonusLabel, FlatLabel and GrownMark children.

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
	def.power = 2
	return def


func _label(card: BoardCard, node_name: String) -> Label3D:
	return card.get_node("CardMesh/%s" % node_name) as Label3D


func test_a_grown_card_shows_the_mark_and_its_mult() -> void:
	var card: BoardCard = _card()
	var entry: Dictionary = {"cost": 3, "power": 4, "mult": 175, "add": 0, "grown": true}
	card.show_entry(_def(), entry)
	assert_bool(_label(card, "GrownMark").visible).is_true()
	assert_str(_label(card, "BonusLabel").text).is_equal("×1.75")
	assert_str(_label(card, "FlatLabel").text).is_equal("4")


func test_a_face_with_add_fifty_reads_plus_zero_fifty() -> void:
	var card: BoardCard = _card()
	card.show_entry(_def(), {"cost": 3, "power": 2, "mult": 0, "add": 50})
	assert_str(_label(card, "BonusLabel").text).is_equal("+0.50")
	assert_bool(_label(card, "BonusLabel").visible).is_true()


func test_a_face_with_no_bonus_hides_the_bonus_label() -> void:
	var card: BoardCard = _card()
	card.show_entry(_def(), {"power": 2, "mult": 0, "add": 0})
	assert_bool(_label(card, "BonusLabel").visible).is_false()


func test_a_reduced_card_shows_the_effective_cost() -> void:
	var card: BoardCard = _card()
	card.show_entry(_def(), {"cost": 2, "grown": true})
	assert_str(_label(card, "CostLabel").text).is_equal("2")


func test_a_printed_card_has_no_mark() -> void:
	var card: BoardCard = _card()
	card.show_entry(_def(), {"cost": 3, "power": 2, "mult": 0, "add": 0, "grown": false})
	assert_bool(_label(card, "GrownMark").visible).is_false()
	assert_str(_label(card, "CostLabel").text).is_equal("3")
	card.show_entry(_def(), {})
	assert_bool(_label(card, "GrownMark").visible).is_false()


func test_badges_stack_the_status_words_under_the_name() -> void:
	var card: BoardCard = _card()
	card.show_entry(_def(), {"statuses": ["condemned", "anchored"]})
	assert_array(card.badge_words()).is_equal(["Condemned", "Anchored"])
	assert_str(_label(card, "Badges").text).is_equal("Condemned\nAnchored")
	card.show_entry(_def(), {})
	assert_array(card.badge_words()).is_empty()


func test_muted_and_squelched_together_read_silenced() -> void:
	var muted: Array[String] = BoardCard.badges_after([], "Muted", true)
	assert_array(muted).is_equal(["Muted"])
	var both: Array[String] = BoardCard.badges_after(muted, "Squelched", true)
	assert_array(both).is_equal(["Silenced"])
	var back: Array[String] = BoardCard.badges_after(both, "Muted", false)
	assert_array(back).is_equal(["Squelched"])
	assert_array(BoardCard.badges_after(back, "Squelched", false)).is_empty()


func test_entry_in_finds_a_card_by_id() -> void:
	var rows: Array[Dictionary] = [{"card": 5, "cost": 1}, {"card": 6, "cost": 2}]
	var found: Dictionary = BoardCard.entry_in(rows, 6)
	var cost: int = found.get("cost", -1)
	assert_int(cost).is_equal(2)
	assert_bool(BoardCard.entry_in(rows, 9).is_empty()).is_true()
