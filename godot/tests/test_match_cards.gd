class_name TestMatchCards
extends GdUnitTestSuite
## MatchCards (DC-13 T02; cycle 9 plan P6, spec R69): instance `origin * DECK_SIZE + index`
## resolves to index `index` of its origin seat's deck, whichever decks the seats play, so
## the two Decks take 0 .. 79; created cards take ids from CREATED_BASE (80) up and answer
## def_of() and origin_of() once recorded. crew_for(seat) is that seat's deck's three Crew
## in slot order.

const CREW_A: Array[String] = ["tallyman", "void", "engineer"]
const CREW_B: Array[String] = ["navigator", "captain", "dredger"]

var _cached_cards: CardDb = null
var _cached_crew: CrewPool = null

# --- Helpers --------------------------------------------------------------------------


func _cards() -> CardDb:
	if _cached_cards == null:
		_cached_cards = CardDb.load_default()
	return _cached_cards


func _crew() -> CrewPool:
	if _cached_crew == null:
		_cached_crew = CrewPool.load_default()
	return _cached_crew


## 40 ids over the shipped pool: ev01..ev30 then gr01..gr10, each once.
func _ids() -> Array[String]:
	var out: Array[String] = []
	for i: int in range(30):
		out.append("ev%02d" % (i + 1))
	for i: int in range(10):
		out.append("gr%02d" % (i + 1))
	return out


func _deck(deck_id: String, card_ids: Array[String], crew: Array[String]) -> Dictionary:
	var crew_list: Array = []
	crew_list.assign(crew)
	return {
		"id": deck_id, "name": deck_id, "tag": "evergreen", "theme": "", "cards": card_ids,
		"crew": crew_list,
	}


## Two decks over the shipped pool: "a" in order, "b" reversed.
func _pair() -> DeckList:
	var reversed: Array[String] = _ids()
	reversed.reverse()
	var decks: Array[Dictionary] = [_deck("a", _ids(), CREW_A), _deck("b", reversed, CREW_B)]
	return DeckList.from_json(JSON.stringify({"version": DeckList.FORMAT_VERSION, "decks": decks}))


func _seats(first: String, second: String) -> Array[String]:
	var out: Array[String] = [first, second]
	return out


# --- Resolution -----------------------------------------------------------------------


func test_def_of_45_is_seat_1s_deck_index_5() -> void:
	var decks: DeckList = _pair()
	var cards: MatchCards = MatchCards.build(_cards(), decks, _seats("a", "b"), _crew())
	assert_bool(cards.is_valid()).override_failure_message(cards.build_error()).is_true()
	assert_int(cards.size()).is_equal(2 * MatchRules.DECK_SIZE)
	var expected_id: String = decks.card_ids("b")[5]
	assert_str(expected_id).is_equal("gr05")
	var instance: int = MatchRules.DECK_SIZE + 5
	var def: CardDef = cards.def_of(instance)
	assert_object(def).is_not_null()
	assert_str(def.id).is_equal(expected_id)
	assert_object(def).is_same(_cards().card_by_id(expected_id))
	assert_int(cards.origin_of(instance)).is_equal(1)
	assert_str(cards.def_of(5).id).is_equal(decks.card_ids("a")[5])
	assert_int(cards.origin_of(5)).is_equal(0)


func test_every_instance_resolves_through_its_origin_deck() -> void:
	var decks: DeckList = _pair()
	var cards: MatchCards = MatchCards.build(_cards(), decks, _seats("b", "a"), _crew())
	var expected: Array[String] = _seats("b", "a")
	assert_array(cards.deck_ids()).is_equal(expected)
	for seat: int in range(2):
		var listed: Array[String] = decks.card_ids(expected[seat])
		for index: int in range(MatchRules.DECK_SIZE):
			var instance: int = seat * MatchRules.DECK_SIZE + index
			assert_str(cards.def_of(instance).id).is_equal(listed[index])
			assert_int(cards.origin_of(instance)).is_equal(seat)


## The shipped decks hold copies: the four copies of a card are four instances sharing one
## definition.
func test_copies_are_instances_of_one_definition() -> void:
	var decks: DeckList = DeckList.load_default()
	var cards: MatchCards = MatchCards.build(_cards(), decks, _seats("greed", "ramp"), _crew())
	assert_bool(cards.is_valid()).override_failure_message(cards.build_error()).is_true()
	for copy: int in range(1, MatchRules.MAX_COPIES):
		assert_object(cards.def_of(copy)).is_same(cards.def_of(0))
	assert_str(cards.def_of(0).id).is_equal("gr01")
	assert_str(cards.def_of(MatchRules.DECK_SIZE).id).is_equal("ra01")
	assert_bool(cards.has_verb("discard_own")).is_true()
	assert_bool(cards.has_verb("cost_on_turn")).is_true()
	assert_bool(cards.has_verb("copy_stats")).is_false()


func test_out_of_range_instances_have_no_definition() -> void:
	var cards: MatchCards = MatchCards.build(_cards(), _pair(), _seats("a", "a"), _crew())
	assert_object(cards.def_of(-1)).is_null()
	assert_object(cards.def_of(2 * MatchRules.DECK_SIZE)).is_null()
	assert_int(cards.origin_of(-1)).is_equal(-1)
	assert_int(cards.origin_of(2 * MatchRules.DECK_SIZE)).is_equal(-1)


# --- Created cards (P6) ---------------------------------------------------------------


func test_created_ids_start_after_both_decks() -> void:
	assert_int(MatchCards.CREATED_BASE).is_equal(2 * MatchRules.DECK_SIZE)
	assert_int(MatchCards.CREATED_BASE).is_equal(80)
	assert_bool(MatchCards.is_created(MatchCards.CREATED_BASE)).is_true()
	assert_bool(MatchCards.is_created(MatchCards.CREATED_BASE - 1)).is_false()


## A created card answers def_of() and origin_of() (its Owner) once recorded, without
## touching a Deck card; a second record of the id, an id in the Deck range, no definition
## or no seat is refused.
func test_a_recorded_created_card_resolves() -> void:
	var cards: MatchCards = MatchCards.build(_cards(), _pair(), _seats("a", "b"), _crew())
	var created: int = MatchCards.CREATED_BASE
	assert_object(cards.def_of(created)).is_null()
	assert_int(cards.origin_of(created)).is_equal(-1)
	var copy: CardDef = _cards().card_by_id("ev05")
	assert_bool(cards.record_created(created, copy, 1)).is_true()
	assert_object(cards.def_of(created)).is_same(copy)
	assert_int(cards.origin_of(created)).is_equal(1)
	assert_bool(cards.record_created(created, copy, 0)).is_false()
	assert_int(cards.origin_of(created)).is_equal(1)
	assert_bool(cards.record_created(5, copy, 0)).is_false()
	assert_str(cards.def_of(5).id).is_equal("ev06")
	assert_bool(cards.record_created(created + 1, null, 0)).is_false()
	assert_bool(cards.record_created(created + 1, copy, 2)).is_false()
	assert_object(cards.def_of(created + 1)).is_null()
	assert_int(cards.size()).is_equal(2 * MatchRules.DECK_SIZE)


# --- Failed builds --------------------------------------------------------------------


func test_a_bad_build_holds_no_definitions() -> void:
	var unknown: MatchCards = MatchCards.build(_cards(), _pair(), _seats("a", "zzz"), _crew())
	assert_bool(unknown.is_valid()).is_false()
	assert_str(unknown.build_error()).contains("zzz")
	assert_int(unknown.size()).is_equal(0)
	assert_object(unknown.def_of(0)).is_null()

	var one: Array[String] = ["a"]
	assert_bool(MatchCards.build(_cards(), _pair(), one, _crew()).is_valid()).is_false()

	var short: Array[String] = _ids()
	short.remove_at(0)
	var short_decks: Array[Dictionary] = [_deck("s", short, CREW_A)]
	var bad_list: DeckList = DeckList.from_json(
		JSON.stringify({"version": DeckList.FORMAT_VERSION, "decks": short_decks})
	)
	var invalid: MatchCards = MatchCards.build(_cards(), bad_list, _seats("s", "s"), _crew())
	assert_bool(invalid.is_valid()).is_false()
	assert_str(invalid.build_error()).starts_with(DeckList.ERR_COUNT)

	assert_bool(MatchCards.build(null, _pair(), _seats("a", "a"), _crew()).is_valid()).is_false()
	assert_bool(MatchCards.build(_cards(), null, _seats("a", "a"), _crew()).is_valid()).is_false()
	var no_crew: MatchCards = MatchCards.build(_cards(), _pair(), _seats("a", "a"), null)
	assert_bool(no_crew.is_valid()).is_false()
	assert_array(no_crew.crew_for(0)).is_empty()
	var bad_crew: MatchCards = MatchCards.build(
		_cards(), _pair(), _seats("a", "a"), CrewPool.from_json("{}")
	)
	assert_str(bad_crew.build_error()).starts_with(DeckList.ERR_CREW_POOL)
	assert_array(unknown.crew_for(0)).is_empty()


# --- Crew ----------------------------------------------------------------------------


## Each seat holds its own deck's three Crew in slot order: the pool's own definitions.
func test_crew_for_is_each_seats_deck_crew_in_slot_order() -> void:
	var cards: MatchCards = MatchCards.build(_cards(), _pair(), _seats("b", "a"), _crew())
	assert_bool(cards.is_valid()).override_failure_message(cards.build_error()).is_true()
	var expected: Array[Array] = [CREW_B, CREW_A]
	for seat: int in range(2):
		var defs: Array[CrewDef] = cards.crew_for(seat)
		assert_int(defs.size()).is_equal(MatchRules.CREW_SIZE)
		var listed: Array = expected[seat]
		for slot: int in range(MatchRules.CREW_SIZE):
			var crew_id: String = listed[slot]
			assert_object(defs[slot]).is_same(_crew().crew_of(crew_id))
			assert_int(cards.crew_slot(seat, crew_id)).is_equal(slot)
			assert_object(cards.crew_def(seat, slot)).is_same(defs[slot])
		var plain: Array = []
		plain.append_array(listed)
		assert_array(cards.crew_ids(seat)).is_equal(plain)
	assert_array(cards.crew_for(-1)).is_empty()
	assert_array(cards.crew_for(2)).is_empty()
	assert_int(cards.crew_slot(0, "gardener")).is_equal(-1)
	# A new array each call: changing it changes nothing held.
	var taken: Array[CrewDef] = cards.crew_for(0)
	taken.clear()
	assert_int(cards.crew_for(0).size()).is_equal(MatchRules.CREW_SIZE)
