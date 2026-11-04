class_name TestRulesText
extends GdUnitTestSuite
## The rules text of a card face (DC-07): the effect's text, or reminder text from the stats.


func _plain(kind: CardDef.BonusKind, amount: int) -> CardDef:
	return CardDef.new("x", "X", 1, 1, kind, amount)


func test_effect_card_keeps_its_effect_text() -> void:
	var effect: CardEffect = CardEffect.new(
		CardEffect.Trigger.ON_REVEAL, CardEffect.Verb.DRAW, 1, "Draw a card."
	)
	var def: CardDef = CardDef.new("x", "X", 1, 1, CardDef.BonusKind.NONE, 0, effect)
	assert_str(BoardCard.rules_text(def)).is_equal("Draw a card.")


func test_times_reminders() -> void:
	assert_str(BoardCard.rules_text(_plain(CardDef.BonusKind.TIMES, 125))).is_equal(
		"When this scores, your mult ×1.25."
	)
	assert_str(BoardCard.rules_text(_plain(CardDef.BonusKind.TIMES, 150))).is_equal(
		"When this scores, your mult ×1.5."
	)
	assert_str(BoardCard.rules_text(_plain(CardDef.BonusKind.TIMES, 200))).is_equal(
		"When this scores, your mult ×2."
	)


func test_plus_reminder() -> void:
	assert_str(BoardCard.rules_text(_plain(CardDef.BonusKind.PLUS, 1))).is_equal(
		"When this scores, your mult +1."
	)


func test_plain_reminder() -> void:
	assert_str(BoardCard.rules_text(_plain(CardDef.BonusKind.NONE, 0))).is_equal(
		"Scores its flat at your mult."
	)


func test_every_shipped_card_has_rules_text() -> void:
	var db: CardDb = CardDb.load_default()
	assert_bool(db.is_valid()).is_true()
	for def: CardDef in db.cards():
		assert_str(BoardCard.rules_text(def)).is_not_empty()
