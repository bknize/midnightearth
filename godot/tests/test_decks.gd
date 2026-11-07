class_name TestDecks
extends GdUnitTestSuite
## The shipped decks (DC-13 T02; cycle 9 plan P5, spec R61; rules/test-decks): the shipped
## list holds exactly `greed` and `ramp`, each the ten cards of its strategy four times
## (40 cards), `greed` summing to Cost 136 and `ramp` to 152 (Colossus at its printed 12),
## with the Crew the canon lists (Greed: Tallyman, Void, Engineer; Ramp: Navigator,
## Captain, Dredger). Every pairing starts. The v6 decks are gone (cycle 9 R63).

const GREED: String = "greed"
const RAMP: String = "ramp"
const SHIPPED: Array[String] = [GREED, RAMP]
const GREED_CREW: Array[String] = ["tallyman", "void", "engineer"]
const RAMP_CREW: Array[String] = ["navigator", "captain", "dredger"]
const GREED_COST: int = 136
const RAMP_COST: int = 152
## The canon's cards of each deck (rules/test-decks), by name.
const GREED_NAMES: Array[String] = [
	"Ember", "Pip", "Flare", "Skim", "Cinder", "Courier", "Banner", "Bounty", "Gilt", "Jackpot"
]
const RAMP_NAMES: Array[String] = [
	"Whisper",
	"Sapling",
	"Rain",
	"Dynamo",
	"Tinker",
	"Idler",
	"Lantern",
	"Graft",
	"Layaway",
	"Colossus",
]

var _cached_cards: CardDb = null
var _cached_decks: DeckList = null

# --- Helpers --------------------------------------------------------------------------


func _cards() -> CardDb:
	if _cached_cards == null:
		_cached_cards = CardDb.load_default()
	return _cached_cards


func _decks() -> DeckList:
	if _cached_decks == null:
		_cached_decks = DeckList.load_default()
	return _cached_decks


## The sum of the printed Costs of `deck_id`'s 40 cards.
func _cost_sum(deck_id: String) -> int:
	var total: int = 0
	for card_id: String in _decks().card_ids(deck_id):
		total += _cards().card_by_id(card_id).cost
	return total


## Each distinct card name of `deck_id` with its number of copies.
func _copies_by_name(deck_id: String) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	for card_id: String in _decks().card_ids(deck_id):
		var card_name: String = _cards().card_by_id(card_id).name
		out[card_name] = out.get(card_name, 0) + 1
	return out


# --- Tests ----------------------------------------------------------------------------


func test_the_shipped_list_holds_greed_and_ramp() -> void:
	assert_bool(_decks().is_valid()).override_failure_message(_decks().load_error()).is_true()
	assert_array(_decks().ids()).is_equal(SHIPPED)
	assert_str(_decks().validate(_cards(), CrewPool.load_default())).is_empty()


func test_greed_sums_to_136_over_40_with_its_crew() -> void:
	var listed: Array[String] = _decks().card_ids(GREED)
	assert_int(listed.size()).is_equal(MatchRules.DECK_SIZE)
	assert_int(_cost_sum(GREED)).is_equal(GREED_COST)
	assert_array(_decks().crew_ids(GREED)).is_equal(GREED_CREW)


func test_ramp_sums_to_152_over_40_with_its_crew() -> void:
	var listed: Array[String] = _decks().card_ids(RAMP)
	assert_int(listed.size()).is_equal(MatchRules.DECK_SIZE)
	assert_int(_cost_sum(RAMP)).is_equal(RAMP_COST)
	assert_array(_decks().crew_ids(RAMP)).is_equal(RAMP_CREW)


## Each deck is its strategy's ten cards, four copies each, every one tagged for the deck.
func test_each_deck_is_its_ten_cards_four_times() -> void:
	var cases: Dictionary[String, Array] = {GREED: GREED_NAMES, RAMP: RAMP_NAMES}
	for deck_id: String in cases:
		var names: Array = cases[deck_id]
		var copies: Dictionary[String, int] = _copies_by_name(deck_id)
		assert_int(copies.size()).override_failure_message(deck_id).is_equal(names.size())
		for raw: Variant in names:
			var card_name: String = raw
			var count: int = copies.get(card_name, 0)
			assert_int(count).override_failure_message(card_name).is_equal(MatchRules.MAX_COPIES)
		for card_id: String in _decks().card_ids(deck_id):
			assert_str(_cards().card_by_id(card_id).tag).is_equal(deck_id)


func test_every_pairing_starts() -> void:
	for first: String in SHIPPED:
		for second: String in SHIPPED:
			var ids: Array[String] = [first, second]
			var engine: MatchEngine = MatchEngine.create(
				1, _cards(), _decks(), ids, CrewPool.load_default()
			)
			var started: ApplyResult = engine.start()
			var label: String = "%s/%s" % [first, second]
			assert_bool(started.ok).override_failure_message(label).is_true()
			assert_array(engine.deck_ids()).is_equal(ids)
			var cards: MatchCards = engine.match_cards()
			assert_array(cards.crew_ids(0)).is_equal(_plain(_decks().crew_ids(first)))
			assert_array(cards.crew_ids(1)).is_equal(_plain(_decks().crew_ids(second)))


func _plain(values: Array[String]) -> Array:
	var out: Array = []
	out.assign(values)
	return out


## The canon's deck averages (Cost sum / 40): 3.4 and 3.8, in tenths.
func test_average_costs_match_the_canon() -> void:
	assert_int(_cost_sum(GREED) * 10).is_equal(34 * MatchRules.DECK_SIZE)
	assert_int(_cost_sum(RAMP) * 10).is_equal(38 * MatchRules.DECK_SIZE)
