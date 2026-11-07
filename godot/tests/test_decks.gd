class_name TestDecks
extends GdUnitTestSuite
## The shipped decks (DC-13 T02, DC-14 T14; cycle 9 plan P5, spec R61; rules/test-decks):
## the shipped list holds the six strategy decks, each the ten cards of its strategy four
## times (40 cards), with the canon's Cost sums (Greed 136, Ramp 152 with Colossus at its
## printed 12, Combo 144, Disruption 144, Graveyard 144, Control 156) and the Crew the canon
## lists. Every pairing starts. The v6 decks are gone (cycle 9 R63).

const GREED: String = "greed"
const RAMP: String = "ramp"
const COMBO: String = "combo"
const DISRUPTION: String = "disruption"
const GRAVEYARD: String = "graveyard"
const CONTROL: String = "control"
## Milestone A's two, then milestone B's four, in file order.
const SHIPPED: Array[String] = [GREED, RAMP, COMBO, DISRUPTION, GRAVEYARD, CONTROL]
## Per deck: [Cost sum over 40, the three Crew, the ten card names] (rules/test-decks).
const CANON: Dictionary[String, Array] = {
	GREED:
	[
		136,
		["tallyman", "void", "engineer"],
		["Ember", "Pip", "Flare", "Skim", "Cinder", "Courier", "Banner", "Bounty", "Gilt", "Jackpot"],
	],
	RAMP:
	[
		152,
		["navigator", "captain", "dredger"],
		[
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
		],
	],
	COMBO:
	[
		144,
		["shade", "quartermaster", "engineer"],
		[
			"Wick",
			"Refrain",
			"Swell",
			"Reprieve",
			"Scrap",
			"Twin",
			"Reprise",
			"Encore",
			"Reverb",
			"Finale",
		],
	],
	DISRUPTION:
	[
		144,
		["engineer", "salvager", "quartermaster"],
		["Hush", "Muzzle", "Litter", "Saboteur", "Hex", "Jam", "Stasis", "Gag", "Quorum", "Eclipse"],
	],
	GRAVEYARD:
	[
		144,
		["veil", "salvager", "dredger"],
		[
			"Fuse",
			"Tithe",
			"Reliquary",
			"Boneyard",
			"Wraith",
			"Glutton",
			"Revive",
			"Exhume",
			"Immolator",
			"Reset",
		],
	],
	CONTROL:
	[
		156,
		["captain", "engineer", "quartermaster"],
		["Eddy", "Pin", "Shepherd", "Skip", "Fence", "Herald", "Level", "Shake", "Tempest", "Cull"],
	],
}

var _cached_cards: CardDb = null
var _cached_decks: DeckList = null
var _cached_crew: CrewPool = null

# --- Helpers --------------------------------------------------------------------------


func _cards() -> CardDb:
	if _cached_cards == null:
		_cached_cards = CardDb.load_default()
	return _cached_cards


func _decks() -> DeckList:
	if _cached_decks == null:
		_cached_decks = DeckList.load_default()
	return _cached_decks


func _crew() -> CrewPool:
	if _cached_crew == null:
		_cached_crew = CrewPool.load_default()
	return _cached_crew


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


func _plain(values: Array[String]) -> Array:
	var out: Array = []
	out.assign(values)
	return out


# --- Tests ----------------------------------------------------------------------------


func test_the_shipped_list_holds_the_six_decks() -> void:
	assert_bool(_decks().is_valid()).override_failure_message(_decks().load_error()).is_true()
	assert_array(_decks().ids()).is_equal(SHIPPED)
	assert_str(_decks().validate(_cards(), _crew())).is_empty()


## Each deck is 40 cards with the canon's Cost sum (and so its average, sum / 40) and Crew.
func test_each_deck_has_40_cards_its_cost_sum_and_its_crew() -> void:
	for deck_id: String in SHIPPED:
		var row: Array = CANON[deck_id]
		var cost: int = row[0]
		var crew: Array = row[1]
		assert_int(_decks().card_ids(deck_id).size()).override_failure_message(deck_id).is_equal(
			MatchRules.DECK_SIZE
		)
		assert_int(_cost_sum(deck_id)).override_failure_message(deck_id).is_equal(cost)
		assert_array(_plain(_decks().crew_ids(deck_id))).is_equal(crew)
		for crew_id: String in _decks().crew_ids(deck_id):
			assert_bool(_crew().has_id(crew_id)).override_failure_message(crew_id).is_true()


## The canon's deck averages (Cost sum / 40): 3.4, 3.8, 3.6, 3.6, 3.6, 3.9, in tenths.
func test_average_costs_match_the_canon() -> void:
	var tenths: Dictionary[String, int] = {
		GREED: 34, RAMP: 38, COMBO: 36, DISRUPTION: 36, GRAVEYARD: 36, CONTROL: 39
	}
	for deck_id: String in SHIPPED:
		var average: int = tenths[deck_id]
		assert_int(_cost_sum(deck_id) * 10).override_failure_message(deck_id).is_equal(
			average * MatchRules.DECK_SIZE
		)


## Each deck is its strategy's ten cards, four copies each, every one tagged for the deck,
## and none of them created-only (Dross).
func test_each_deck_is_its_ten_cards_four_times() -> void:
	for deck_id: String in SHIPPED:
		var row: Array = CANON[deck_id]
		var names: Array = row[2]
		var copies: Dictionary[String, int] = _copies_by_name(deck_id)
		assert_int(copies.size()).override_failure_message(deck_id).is_equal(names.size())
		for raw: Variant in names:
			var card_name: String = raw
			var count: int = copies.get(card_name, 0)
			assert_int(count).override_failure_message(card_name).is_equal(MatchRules.MAX_COPIES)
		for card_id: String in _decks().card_ids(deck_id):
			var def: CardDef = _cards().card_by_id(card_id)
			assert_str(def.tag).override_failure_message(card_id).is_equal(deck_id)
			assert_bool(def.created).override_failure_message(card_id).is_false()


func test_every_pairing_starts() -> void:
	for first: String in SHIPPED:
		for second: String in SHIPPED:
			var ids: Array[String] = [first, second]
			var engine: MatchEngine = MatchEngine.create(1, _cards(), _decks(), ids, _crew())
			var started: ApplyResult = engine.start()
			var label: String = "%s/%s" % [first, second]
			assert_bool(started.ok).override_failure_message(label).is_true()
			assert_array(engine.deck_ids()).is_equal(ids)
			var cards: MatchCards = engine.match_cards()
			assert_array(cards.crew_ids(0)).is_equal(_plain(_decks().crew_ids(first)))
			assert_array(cards.crew_ids(1)).is_equal(_plain(_decks().crew_ids(second)))
