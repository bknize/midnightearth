class_name TestMatchCards
extends GdUnitTestSuite
## MatchCards (DC-07 T01; R5, R8, plan P3): instance `origin * 20 + index` resolves to
## index `index` of its origin seat's deck, whichever decks the seats play.

const FIXTURE_CARDS: String = "res://tests/fixtures/dc05_cards.json"
const FIXTURE_DECKS: String = "res://tests/fixtures/dc05_decks.json"

var _cached_cards: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _cards() -> CardDb:
	if _cached_cards == null:
		_cached_cards = CardDb.load_from_path(FIXTURE_CARDS)
	return _cached_cards


## The 20 fixture ids c01..c20, in order.
func _ids() -> Array[String]:
	var out: Array[String] = []
	for i: int in range(MatchRules.DECK_SIZE):
		out.append("c%02d" % (i + 1))
	return out


## Two decks over the fixture pool: "a" in file order, "b" reversed.
func _pair() -> DeckList:
	var reversed: Array[String] = _ids()
	reversed.reverse()
	var decks: Array[Dictionary] = [
		{"id": "a", "name": "A", "theme": "File order.", "cards": _ids()},
		{"id": "b", "name": "B", "theme": "Reversed.", "cards": reversed},
	]
	return DeckList.from_json(JSON.stringify({"version": 1, "decks": decks}))


func _seats(first: String, second: String) -> Array[String]:
	var out: Array[String] = [first, second]
	return out


# --- Resolution -----------------------------------------------------------------------


func test_def_of_25_is_seat_1s_deck_index_5() -> void:
	var decks: DeckList = _pair()
	var cards: MatchCards = MatchCards.build(_cards(), decks, _seats("a", "b"))
	assert_bool(cards.is_valid()).override_failure_message(cards.build_error()).is_true()
	assert_int(cards.size()).is_equal(2 * MatchRules.DECK_SIZE)
	var expected_id: String = decks.card_ids("b")[5]
	assert_str(expected_id).is_equal("c15")
	var def: CardDef = cards.def_of(25)
	assert_object(def).is_not_null()
	assert_str(def.id).is_equal(expected_id)
	assert_object(def).is_same(_cards().card_by_id(expected_id))
	assert_int(cards.origin_of(25)).is_equal(1)
	# Seat 0's index 5 comes from deck "a".
	assert_str(cards.def_of(5).id).is_equal(decks.card_ids("a")[5])
	assert_int(cards.origin_of(5)).is_equal(0)


func test_every_instance_resolves_through_its_origin_deck() -> void:
	var decks: DeckList = _pair()
	var cards: MatchCards = MatchCards.build(_cards(), decks, _seats("b", "a"))
	var expected: Array[String] = _seats("b", "a")
	assert_array(cards.deck_ids()).is_equal(expected)
	for seat: int in range(2):
		var listed: Array[String] = decks.card_ids(expected[seat])
		for index: int in range(MatchRules.DECK_SIZE):
			var instance: int = seat * MatchRules.DECK_SIZE + index
			assert_str(cards.def_of(instance).id).is_equal(listed[index])


func test_two_seats_on_the_same_deck_resolve_to_equal_definitions() -> void:
	var decks: DeckList = DeckList.load_from_path(FIXTURE_DECKS)
	var cards: MatchCards = MatchCards.build(_cards(), decks, _seats("fixture", "fixture"))
	assert_bool(cards.is_valid()).override_failure_message(cards.build_error()).is_true()
	for index: int in range(MatchRules.DECK_SIZE):
		var own: CardDef = cards.def_of(index)
		var other: CardDef = cards.def_of(MatchRules.DECK_SIZE + index)
		assert_object(own).is_not_null()
		assert_dict(other.to_dict()).is_equal(own.to_dict())
		assert_object(other).is_same(own)
	# The fixture deck is the pool in file order, so instances keep the DC-05 numbering.
	for instance: int in range(2 * MatchRules.DECK_SIZE):
		var by_index: CardDef = _cards().card_at(instance % MatchRules.DECK_SIZE)
		assert_object(cards.def_of(instance)).is_same(by_index)


func test_out_of_range_instances_have_no_definition() -> void:
	var cards: MatchCards = MatchCards.build(_cards(), _pair(), _seats("a", "a"))
	assert_object(cards.def_of(-1)).is_null()
	assert_object(cards.def_of(2 * MatchRules.DECK_SIZE)).is_null()
	assert_int(cards.origin_of(-1)).is_equal(-1)
	assert_int(cards.origin_of(2 * MatchRules.DECK_SIZE)).is_equal(-1)


# --- Failed builds --------------------------------------------------------------------


func test_a_bad_build_holds_no_definitions() -> void:
	var unknown: MatchCards = MatchCards.build(_cards(), _pair(), _seats("a", "zzz"))
	assert_bool(unknown.is_valid()).is_false()
	assert_str(unknown.build_error()).contains("zzz")
	assert_int(unknown.size()).is_equal(0)
	assert_object(unknown.def_of(0)).is_null()

	var one: Array[String] = ["a"]
	assert_bool(MatchCards.build(_cards(), _pair(), one).is_valid()).is_false()

	var short: Array[String] = _ids()
	short.remove_at(0)
	var short_decks: Array[Dictionary] = [{"id": "s", "name": "S", "theme": "", "cards": short}]
	var bad_list: DeckList = DeckList.from_json(
		JSON.stringify({"version": 1, "decks": short_decks})
	)
	var invalid: MatchCards = MatchCards.build(_cards(), bad_list, _seats("s", "s"))
	assert_bool(invalid.is_valid()).is_false()
	assert_str(invalid.build_error()).starts_with(DeckList.ERR_COUNT)

	assert_bool(MatchCards.build(null, _pair(), _seats("a", "a")).is_valid()).is_false()
	assert_bool(MatchCards.build(_cards(), null, _seats("a", "a")).is_valid()).is_false()
