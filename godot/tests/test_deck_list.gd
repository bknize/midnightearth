class_name TestDeckList
extends GdUnitTestSuite
## DeckList v3 (DC-13 T02; cycle 9 plan P5, spec R61, R64; canon R18, R58): the deck list
## loads, validate() checks each deck against the card pool and the Crew pool (exactly 40
## card ids, at most four copies of one id, every id in the pool, exactly three different
## Crew the Crew pool holds), and seeded_pick() draws a seat's deck from the match seed with
## its own derived stream. A 39-card deck, five copies of one id, two Crew, a repeated Crew
## and an unknown id each fail by name; both shipped decks pass.

const PICK_SEEDS: int = 10
const CREW: Array[String] = ["tallyman", "void", "engineer"]

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


## A legal 40-card list: the ten Greed cards, four copies each, in order.
func _ids() -> Array[String]:
	var out: Array[String] = []
	for index: int in range(10):
		for _copy: int in range(MatchRules.MAX_COPIES):
			out.append("gr%02d" % (index + 1))
	return out


func _deck(deck_id: String, card_ids: Array[String], crew: Array = CREW) -> Dictionary:
	return {
		"id": deck_id,
		"name": deck_id.capitalize(),
		"tag": "greed",
		"theme": "A theme.",
		"cards": card_ids,
		"crew": crew,
	}


func _list_json(decks: Array[Dictionary], version: int = DeckList.FORMAT_VERSION) -> String:
	return JSON.stringify({"version": version, "decks": decks})


## A list of one deck "d" holding `card_ids` and `crew`.
func _one(card_ids: Array[String], crew: Array = CREW) -> DeckList:
	var decks: Array[Dictionary] = [_deck("d", card_ids, crew)]
	return DeckList.from_json(_list_json(decks))


## Two decks over the shipped pool: "a" in order, "b" reversed.
func _pair() -> DeckList:
	var reversed: Array[String] = _ids()
	reversed.reverse()
	var decks: Array[Dictionary] = [_deck("a", _ids()), _deck("b", reversed)]
	return DeckList.from_json(_list_json(decks))


func _assert_invalid(decks: DeckList, prefix: String) -> void:
	assert_bool(decks.is_valid()).is_false()
	assert_str(decks.load_error()).starts_with(prefix)
	assert_int(decks.size()).is_equal(0)
	assert_array(decks.ids()).is_empty()


## `decks` loads but validate() fails with `prefix`.
func _assert_fails_validate(decks: DeckList, prefix: String) -> void:
	assert_bool(decks.is_valid()).override_failure_message(decks.load_error()).is_true()
	assert_str(decks.validate(_cards(), _crew())).starts_with(prefix)


# --- Loading and the shipped list -----------------------------------------------------


func test_both_shipped_decks_pass() -> void:
	var decks: DeckList = DeckList.load_default()
	assert_bool(decks.is_valid()).override_failure_message(decks.load_error()).is_true()
	assert_array(decks.ids()).is_equal(["greed", "ramp"])
	assert_str(decks.validate(_cards(), _crew())).is_empty()
	for deck_id: String in decks.ids():
		assert_int(decks.card_ids(deck_id).size()).is_equal(MatchRules.DECK_SIZE)
		assert_int(decks.crew_ids(deck_id).size()).is_equal(MatchRules.CREW_SIZE)


func test_a_legal_list_validates() -> void:
	assert_str(_one(_ids()).validate(_cards(), _crew())).is_empty()
	assert_str(_pair().validate(_cards(), _crew())).is_empty()


func test_deck_lookups() -> void:
	var decks: DeckList = DeckList.load_default()
	var greed: Dictionary = decks.deck("greed")
	var greed_name: String = greed["name"]
	var greed_tag: String = greed["tag"]
	assert_str(greed_name).is_equal("Greed")
	assert_str(greed_tag).is_equal("greed")
	assert_bool(decks.has_deck("ramp")).is_true()
	assert_bool(decks.has_deck("ruin")).is_false()
	assert_dict(decks.deck("nope")).is_empty()
	assert_array(decks.card_ids("nope")).is_empty()
	assert_array(decks.crew_ids("nope")).is_empty()


func test_malformed_lists_fail_to_load() -> void:
	_assert_invalid(DeckList.from_json("not json"), DeckList.ERR_JSON)
	_assert_invalid(DeckList.from_json("[]"), DeckList.ERR_SHAPE)
	var decks: Array[Dictionary] = [_deck("d", _ids())]
	_assert_invalid(DeckList.from_json(_list_json(decks, 2)), DeckList.ERR_VERSION)
	var no_tag: Dictionary = _deck("d", _ids())
	no_tag.erase("tag")
	var tagless: Array[Dictionary] = [no_tag]
	_assert_invalid(DeckList.from_json(_list_json(tagless)), DeckList.ERR_SHAPE)
	var twice: Array[Dictionary] = [_deck("d", _ids()), _deck("d", _ids())]
	_assert_invalid(DeckList.from_json(_list_json(twice)), DeckList.ERR_DUPLICATE_DECK)
	_assert_invalid(DeckList.load_from_path("res://no_such_decks.json"), DeckList.ERR_FILE)


# --- validate ---------------------------------------------------------------------------


func test_39_cards_fail_validate() -> void:
	var short: Array[String] = _ids()
	short.resize(MatchRules.DECK_SIZE - 1)
	_assert_fails_validate(_one(short), DeckList.ERR_COUNT)
	var long: Array[String] = _ids()
	long.append("ev01")
	_assert_fails_validate(_one(long), DeckList.ERR_COUNT)


func test_five_copies_of_one_id_fail_validate() -> void:
	var listed: Array[String] = _ids()
	# 40 cards still: gr02's first copy becomes a fifth gr01.
	listed[MatchRules.MAX_COPIES] = "gr01"
	_assert_fails_validate(_one(listed), DeckList.ERR_COPIES)
	assert_str(DeckList.ERR_COPIES).is_equal("too many copies")


func test_an_unknown_id_fails_validate() -> void:
	var listed: Array[String] = _ids()
	listed[0] = "c01"
	_assert_fails_validate(_one(listed), DeckList.ERR_UNKNOWN)


func test_two_crew_fail_validate() -> void:
	_assert_fails_validate(_one(_ids(), ["tallyman", "void"]), DeckList.ERR_CREW_COUNT)
	var four: Array = ["tallyman", "void", "engineer", "captain"]
	_assert_fails_validate(_one(_ids(), four), DeckList.ERR_CREW_COUNT)


func test_a_repeated_crew_fails_validate() -> void:
	_assert_fails_validate(_one(_ids(), ["void", "void", "engineer"]), DeckList.ERR_CREW_REPEAT)


func test_an_unknown_crew_fails_validate() -> void:
	var unknown: Array = ["void", "gardener", "engineer"]
	_assert_fails_validate(_one(_ids(), unknown), DeckList.ERR_CREW_UNKNOWN)


func test_validate_needs_a_valid_pool_and_list() -> void:
	var decks: DeckList = _one(_ids())
	assert_str(decks.validate(null, _crew())).starts_with(DeckList.ERR_POOL)
	assert_str(decks.validate(CardDb.from_json("{}"), _crew())).starts_with(DeckList.ERR_POOL)
	assert_str(decks.validate(_cards(), null)).starts_with(DeckList.ERR_CREW_POOL)
	var broken: DeckList = DeckList.from_json("not json")
	assert_str(broken.validate(_cards(), _crew())).starts_with(DeckList.ERR_JSON)


func test_a_crew_may_serve_two_decks() -> void:
	assert_str(_pair().validate(_cards(), _crew())).is_empty()
	assert_array(_pair().crew_ids("a")).is_equal(_pair().crew_ids("b"))


# --- seeded_pick (R6, C15) ------------------------------------------------------------


func test_seeded_pick_is_stable_across_calls_and_instances() -> void:
	var decks: DeckList = _pair()
	var first_0: String = decks.seeded_pick(1, 0)
	var first_1: String = decks.seeded_pick(1, 1)
	assert_bool(decks.ids().has(first_0)).is_true()
	assert_bool(decks.ids().has(first_1)).is_true()
	for _repeat: int in range(3):
		assert_str(decks.seeded_pick(1, 0)).is_equal(first_0)
		assert_str(decks.seeded_pick(1, 1)).is_equal(first_1)
		assert_str(_pair().seeded_pick(1, 0)).is_equal(first_0)
		assert_str(_pair().seeded_pick(1, 1)).is_equal(first_1)


func test_seeded_pick_uses_its_own_derived_stream() -> void:
	var decks: DeckList = _pair()
	for match_seed: int in range(1, PICK_SEEDS + 1):
		for seat: int in range(2):
			var parts: Array[int] = [MatchRules.DECK_TAG, seat]
			var rng: MatchRng = MatchRng.new(MatchRng.derive_seed(match_seed, parts))
			var expected: String = decks.ids()[rng.pick_index(decks.size())]
			assert_str(decks.seeded_pick(match_seed, seat)).is_equal(expected)


func test_seeded_pick_on_one_deck_and_on_none() -> void:
	var one: DeckList = _one(_ids())
	for match_seed: int in range(1, PICK_SEEDS + 1):
		assert_str(one.seeded_pick(match_seed, 0)).is_equal("d")
		assert_str(one.seeded_pick(match_seed, 1)).is_equal("d")
	var none: DeckList = DeckList.from_json("not json")
	assert_str(none.seeded_pick(1, 0)).is_empty()


# --- Silent failure -------------------------------------------------------------------


func test_loading_logs_no_errors() -> void:
	await assert_error(func() -> void: DeckList.load_default()).is_success()
	await assert_error(func() -> void: DeckList.from_json("not json")).is_success()
	await (
		assert_error(func() -> void: DeckList.load_from_path("res://no_such_decks.json"))
		. is_success()
	)
