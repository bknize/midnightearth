class_name TestBoardCardMemory
extends GdUnitTestSuite
## BoardCard faces with card memory (cycle 8 P16, R24, R25): the effective cost, the grown
## mark and the bonus text. Node queries on the CostLabel, BonusLabel and GrownMark children.

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


func test_a_grown_card_shows_the_mark_and_its_bonus() -> void:
	var card: BoardCard = _card()
	var entry: Dictionary = {"cost": 3, "flat": 4, "times": 175, "plus": 0, "grown": true}
	card.show_entry(_def(), entry)
	assert_bool(_label(card, "GrownMark").visible).is_true()
	assert_str(_label(card, "BonusLabel").text).is_equal("×1.75")
	assert_str(_label(card, "FlatLabel").text).is_equal("4")


func test_a_reduced_card_shows_the_effective_cost() -> void:
	var card: BoardCard = _card()
	card.show_entry(_def(), {"cost": 2, "grown": true})
	assert_str(_label(card, "CostLabel").text).is_equal("2")


func test_a_printed_card_has_no_mark() -> void:
	var card: BoardCard = _card()
	card.show_entry(_def(), {"cost": 3, "flat": 2, "times": 100, "plus": 0, "grown": false})
	assert_bool(_label(card, "GrownMark").visible).is_false()
	assert_str(_label(card, "CostLabel").text).is_equal("3")
	card.show_entry(_def(), {})
	assert_bool(_label(card, "GrownMark").visible).is_false()


func test_entry_in_finds_a_card_by_id() -> void:
	var rows: Array[Dictionary] = [{"card": 5, "cost": 1}, {"card": 6, "cost": 2}]
	var found: Dictionary = BoardCard.entry_in(rows, 6)
	var cost: int = found.get("cost", -1)
	assert_int(cost).is_equal(2)
	assert_bool(BoardCard.entry_in(rows, 9).is_empty()).is_true()
