class_name TestRulesText
extends GdUnitTestSuite
## The rules text of a card face (DC-13 T02, cycle 9 R22): the card's printed text, and no
## text for a plain body (the v6 reminder text went with the v6 anatomy).


func test_a_card_with_an_ability_shows_its_text() -> void:
	var def: CardDef = CardDef.new("x", "X", "evergreen", 2, 2)
	def.text = "On reveal: draw a card."
	assert_str(BoardCard.rules_text(def)).is_equal("On reveal: draw a card.")


func test_a_plain_body_shows_no_text() -> void:
	var mult: CardDef = CardDef.new("x", "X", "evergreen", 1, 1, CardDef.BonusKind.MULT, 125)
	assert_str(BoardCard.rules_text(mult)).is_empty()
	var plain: CardDef = CardDef.new("y", "Y", "evergreen", 1, 2)
	assert_str(BoardCard.rules_text(plain)).is_empty()


## Every shipped card with an ability shows that card's printed text; every plain body none.
func test_every_shipped_card_shows_its_printed_text() -> void:
	var db: CardDb = CardDb.load_default()
	assert_bool(db.is_valid()).is_true()
	for def: CardDef in db.cards():
		assert_str(BoardCard.rules_text(def)).is_equal(def.text)
		if def.is_plain():
			assert_str(BoardCard.rules_text(def)).override_failure_message(def.id).is_empty()
		else:
			assert_str(BoardCard.rules_text(def)).override_failure_message(def.id).is_not_empty()
