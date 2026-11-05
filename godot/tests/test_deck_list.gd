class_name TestDeckList
extends GdUnitTestSuite
## DeckList (DC-07 T01; R2, R3, R6, plan P2): the deck list loads, validate() checks each
## deck against a pool (exactly 20 ids, no repeat, every id in the pool), and
## seeded_pick() draws a seat's deck from the match seed with its own derived stream.
## DC-11 T08 (cycle 8 R40, R41, P12): version 2 adds each deck's `crew`, and validate()
## also checks it names exactly three distinct Crew the Crew pool holds.

const FIXTURE_CARDS: String = "res://tests/fixtures/dc05_cards.json"
const FIXTURE_DECKS: String = "res://tests/fixtures/dc05_decks.json"
const PICK_SEEDS: int = 10
const CREW: Array[String] = ["navigator", "gardener", "lookout"]

var _cached_cards: CardDb = null
var _cached_crew: CrewPool = null

# --- Helpers --------------------------------------------------------------------------


func _cards() -> CardDb:
	if _cached_cards == null:
		_cached_cards = CardDb.load_from_path(FIXTURE_CARDS)
	return _cached_cards


func _crew() -> CrewPool:
	if _cached_crew == null:
		_cached_crew = CrewPool.load_default()
	return _cached_crew


## The 20 fixture ids c01..c20, in order.
func _ids() -> Array[String]:
	var out: Array[String] = []
	for i: int in range(MatchRules.DECK_SIZE):
		out.append("c%02d" % (i + 1))
	return out


func _deck(deck_id: String, card_ids: Array[String], crew: Array = CREW) -> Dictionary:
	return {
		"id": deck_id,
		"name": deck_id.capitalize(),
		"theme": "A theme.",
		"cards": card_ids,
		"crew": crew,
	}


func _list_json(decks: Array[Dictionary], version: int = DeckList.FORMAT_VERSION) -> String:
	return JSON.stringify({"version": version, "decks": decks})


## A list of one deck "d" holding `card_ids`.
func _one(card_ids: Array[String]) -> DeckList:
	var decks: Array[Dictionary] = [_deck("d", card_ids)]
	return DeckList.from_json(_list_json(decks))


## Two decks over the fixture pool: "a" in file order, "b" reversed.
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


# --- Loading --------------------------------------------------------------------------


func test_the_fixture_list_loads_and_validates() -> void:
	var decks: DeckList = DeckList.load_from_path(FIXTURE_DECKS)
	assert_bool(decks.is_valid()).override_failure_message(decks.load_error()).is_true()
	var expected_ids: Array[String] = ["fixture"]
	assert_array(decks.ids()).is_equal(expected_ids)
	assert_str(decks.validate(_cards(), _crew())).is_empty()
	var deck: Dictionary = decks.deck("fixture")
	var deck_id: String = deck["id"]
	var deck_name: String = deck["name"]
	var theme: String = deck["theme"]
	assert_str(deck_id).is_equal("fixture")
	assert_str(deck_name).is_not_empty()
	assert_str(theme).is_not_empty()
	var listed: Array = deck["cards"]
	assert_array(listed).is_equal(_ids())
	assert_array(decks.card_ids("fixture")).is_equal(_ids())


func test_the_shipped_list_validates_against_the_shipped_pool() -> void:
	var decks: DeckList = DeckList.load_default()
	assert_bool(decks.is_valid()).override_failure_message(decks.load_error()).is_true()
	assert_int(decks.size()).is_greater(0)
	assert_str(decks.validate(CardDb.load_default(), CrewPool.load_default())).is_empty()


func test_deck_lookups() -> void:
	var decks: DeckList = _pair()
	var expected: Array[String] = ["a", "b"]
	assert_array(decks.ids()).is_equal(expected)
	assert_bool(decks.has_deck("b")).is_true()
	assert_bool(decks.has_deck("c")).is_false()
	assert_dict(decks.deck("c")).is_empty()
	assert_array(decks.card_ids("c")).is_empty()
	assert_str(decks.card_ids("b")[0]).is_equal("c20")
	# deck() hands out a copy.
	var copy: Dictionary = decks.deck("a")
	var listed: Array = copy["cards"]
	listed.clear()
	assert_int(decks.card_ids("a").size()).is_equal(MatchRules.DECK_SIZE)


func test_malformed_lists_fail_to_load() -> void:
	var good: Array[Dictionary] = [_deck("a", _ids())]
	_assert_invalid(DeckList.from_json(_list_json(good, 1)), DeckList.ERR_VERSION)
	_assert_invalid(DeckList.from_json(_list_json(good, 3)), DeckList.ERR_VERSION)
	_assert_invalid(DeckList.from_json("not json"), DeckList.ERR_JSON)
	_assert_invalid(DeckList.from_json("[1]"), DeckList.ERR_SHAPE)
	_assert_invalid(DeckList.from_json('{"version": 2}'), DeckList.ERR_SHAPE)
	_assert_invalid(DeckList.from_json('{"decks": []}'), DeckList.ERR_SHAPE)
	for key: String in ["id", "name", "theme", "cards", "crew"]:
		var missing: Dictionary = _deck("a", _ids())
		missing.erase(key)
		var decks: Array[Dictionary] = [missing]
		_assert_invalid(DeckList.from_json(_list_json(decks)), DeckList.ERR_SHAPE)
	var not_strings: Array[Dictionary] = [
		{"id": "a", "name": "A", "theme": "", "cards": [1, 2], "crew": CREW}
	]
	_assert_invalid(DeckList.from_json(_list_json(not_strings)), DeckList.ERR_SHAPE)
	var crew_not_strings: Array[Dictionary] = [_deck("a", _ids(), [1, 2, 3])]
	_assert_invalid(DeckList.from_json(_list_json(crew_not_strings)), DeckList.ERR_SHAPE)
	var crew_not_list: Array[Dictionary] = [_deck("a", _ids(), [])]
	crew_not_list[0]["crew"] = "navigator"
	_assert_invalid(DeckList.from_json(_list_json(crew_not_list)), DeckList.ERR_SHAPE)
	var empty_id: Array[Dictionary] = [_deck("", _ids())]
	_assert_invalid(DeckList.from_json(_list_json(empty_id)), DeckList.ERR_SHAPE)
	var twice: Array[Dictionary] = [_deck("a", _ids()), _deck("a", _ids())]
	_assert_invalid(DeckList.from_json(_list_json(twice)), DeckList.ERR_DUPLICATE_DECK)
	_assert_invalid(DeckList.load_from_path("res://no_such_decks.json"), DeckList.ERR_FILE)


# --- validate (R2, R3) ----------------------------------------------------------------


func test_19_or_21_cards_fail_validate() -> void:
	var short: Array[String] = _ids()
	short.remove_at(19)
	var short_list: DeckList = _one(short)
	assert_bool(short_list.is_valid()).is_true()
	assert_str(short_list.validate(_cards(), _crew())).starts_with(DeckList.ERR_COUNT)

	var long: Array[String] = _ids()
	long.append("c01")
	assert_str(_one(long).validate(_cards(), _crew())).starts_with(DeckList.ERR_COUNT)

	assert_str(_one(_ids()).validate(_cards(), _crew())).is_empty()


func test_a_repeated_id_fails_validate() -> void:
	var repeated: Array[String] = _ids()
	repeated[19] = "c01"
	assert_str(_one(repeated).validate(_cards(), _crew())).starts_with(DeckList.ERR_REPEAT)


func test_an_unknown_id_fails_validate() -> void:
	var unknown: Array[String] = _ids()
	unknown[7] = "c99"
	assert_str(_one(unknown).validate(_cards(), _crew())).starts_with(DeckList.ERR_UNKNOWN)


func test_validate_needs_a_valid_pool_and_list() -> void:
	var bad_pool: CardDb = CardDb.from_json('{"version": 2, "cards": []}')
	assert_str(_one(_ids()).validate(bad_pool, _crew())).starts_with(DeckList.ERR_POOL)
	assert_str(_one(_ids()).validate(null, _crew())).starts_with(DeckList.ERR_POOL)
	var bad_list: DeckList = DeckList.from_json("not json")
	assert_str(bad_list.validate(_cards(), _crew())).starts_with(DeckList.ERR_JSON)
	var bad_crew: CrewPool = CrewPool.from_json('{"version": 1}')
	assert_str(_one(_ids()).validate(_cards(), bad_crew)).starts_with(DeckList.ERR_CREW_POOL)
	assert_str(_one(_ids()).validate(_cards(), null)).starts_with(DeckList.ERR_CREW_POOL)


# --- validate: Crew (DC-11 T08; cycle 8 R40, R41) -----------------------------------


## A one-deck list naming `crew`, over the fixture's 20 cards.
func _crewed(crew: Array) -> DeckList:
	var decks: Array[Dictionary] = [_deck("d", _ids(), crew)]
	return DeckList.from_json(_list_json(decks))


func test_the_deck_crew_reads_back_in_order() -> void:
	var decks: DeckList = _crewed(CREW)
	var expected: Array[String] = ["navigator", "gardener", "lookout"]
	assert_array(decks.crew_ids("d")).is_equal(expected)
	assert_array(decks.crew_ids("none")).is_empty()
	var deck: Dictionary = decks.deck("d")
	var listed: Array = deck["crew"]
	assert_array(listed).is_equal(expected)


func test_two_or_four_crew_fail_validate() -> void:
	var two: DeckList = _crewed(["navigator", "gardener"])
	assert_bool(two.is_valid()).is_true()
	assert_str(two.validate(_cards(), _crew())).starts_with(DeckList.ERR_CREW_COUNT)
	var four: DeckList = _crewed(["navigator", "gardener", "lookout", "veil"])
	assert_str(four.validate(_cards(), _crew())).starts_with(DeckList.ERR_CREW_COUNT)
	assert_str(_crewed([]).validate(_cards(), _crew())).starts_with(DeckList.ERR_CREW_COUNT)


func test_a_repeated_crew_fails_validate() -> void:
	var repeated: DeckList = _crewed(["navigator", "gardener", "navigator"])
	assert_str(repeated.validate(_cards(), _crew())).starts_with(DeckList.ERR_CREW_REPEAT)


func test_an_unknown_crew_fails_validate() -> void:
	var unknown: DeckList = _crewed(["navigator", "gardener", "captain"])
	var problem: String = unknown.validate(_cards(), _crew())
	assert_str(problem).starts_with(DeckList.ERR_CREW_UNKNOWN)
	assert_str(problem).contains("captain")


## A Crew may serve more than one deck (R40).
func test_a_crew_may_serve_two_decks() -> void:
	var decks: Array[Dictionary] = [
		_deck("a", _ids(), ["veil", "navigator", "tallyman"]),
		_deck("b", _ids(), ["veil", "salvager", "quartermaster"]),
	]
	var shared: DeckList = DeckList.from_json(_list_json(decks))
	assert_str(shared.validate(_cards(), _crew())).is_empty()


## Each shipped deck names the plan's three Crew (P12).
func test_the_shipped_decks_name_the_plans_crew() -> void:
	var decks: DeckList = DeckList.load_default()
	var expected: Dictionary = {
		"ruin": ["salvager", "veil", "quartermaster"],
		"drift": ["navigator", "veil", "tallyman"],
		"bloom": ["gardener", "tallyman", "quartermaster"],
		"echo": ["shade", "lookout", "quartermaster"],
	}
	for deck_id: String in decks.ids():
		assert_bool(expected.has(deck_id)).override_failure_message(deck_id).is_true()
		var want: Array = expected.get(deck_id, [])
		var have: Array = []
		have.append_array(decks.crew_ids(deck_id))
		assert_array(have).override_failure_message(deck_id).is_equal(want)


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


func test_seeded_pick_varies_with_the_seed() -> void:
	var decks: DeckList = _pair()
	var seed_2: Array[String] = [decks.seeded_pick(2, 0), decks.seeded_pick(2, 1)]
	var differs: bool = false
	for match_seed: int in range(1, PICK_SEEDS + 1):
		for seat: int in range(2):
			if decks.seeded_pick(match_seed, seat) != seed_2[seat]:
				differs = true
	assert_bool(differs).is_true()


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
	await assert_error(func() -> void: DeckList.load_from_path(FIXTURE_DECKS)).is_success()
	await assert_error(func() -> void: DeckList.from_json("not json")).is_success()
	await (
		assert_error(func() -> void: DeckList.load_from_path("res://no_such_decks.json"))
		. is_success()
	)
