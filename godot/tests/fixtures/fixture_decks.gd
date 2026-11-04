class_name FixtureDecks
extends RefCounted
## The DC-05 fixture for the suites (DC-07 T02, plan P1, R4): the 20 fixture cards and the
## one-deck list `fixture`, played on both seats. Every suite written before DC-07 runs on
## it, so its instance ids still mean `seat * 20 + index into c01..c20`, and it does not
## depend on the shipped pool or deck list. Not a suite: builders only, nothing cached.

const CARDS_PATH: String = "res://tests/fixtures/dc05_cards.json"
const DECKS_PATH: String = "res://tests/fixtures/dc05_decks.json"
const DECK_ID: String = "fixture"
## The fixture card the multi-select suites give sacrifice_destroy in memory (DC-07 T05):
## c02 (cost 1, flat 2, vanilla in the file).
const C02_SACRIFICE: int = 1
const SACRIFICE_TEXT: String = (
	"Destroy any number of your cards: destroy that many enemy cards at random."
)


## The fixture pool (format 3).
static func cards() -> CardDb:
	return CardDb.load_from_path(CARDS_PATH)


## The fixture deck list: the single deck `fixture`, c01..c20 in order.
static func decks() -> DeckList:
	return DeckList.load_from_path(DECKS_PATH)


## The fixture deck on both seats.
static func ids() -> Array[String]:
	var out: Array[String] = [DECK_ID, DECK_ID]
	return out


## A match on `match_seed` with the fixture deck on both seats over `pool` (the fixture
## pool, or a suite's edited copy of it holding the same ids).
static func engine(match_seed: int, pool: CardDb) -> MatchEngine:
	return MatchEngine.create(match_seed, pool, decks(), ids())


## The definitions of a fixture-vs-fixture match over `pool`, for the engine modules that
## take MatchCards (ScoreWalk, EffectResolver, LegalPlays, SeatView, GreedyBot).
static func defs(pool: CardDb) -> MatchCards:
	return MatchCards.build(pool, decks(), ids())


## The fixture pool with definition `index` given the effect {trigger, verb, amount 0,
## text} (in-memory JSON), for a verb no fixture card carries; null if the file is unread.
static func cards_with_effect(index: int, trigger: String, verb: String, text: String) -> CardDb:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARDS_PATH))
	if not parsed is Dictionary:
		return null
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	var entry: Dictionary = entries[index]
	entry["effect"] = {"trigger": trigger, "verb": verb, "amount": 0, "text": text}
	return CardDb.from_json(JSON.stringify(root))


## The fixture pool with c02 carrying an on-reveal sacrifice_destroy (DC-07 T05, P12).
static func sacrifice_cards() -> CardDb:
	return cards_with_effect(C02_SACRIFICE, "on_reveal", "sacrifice_destroy", SACRIFICE_TEXT)


## Sets both rows of the started `engine` by hand (`own` for seat 0, `theirs` for seat 1;
## instance ids, face down), taking each card out of its seat's deck, hand and burn pile
## (the suites' table shortcut, as test_destroyed_piles.gd), then both seats pass: the walk
## runs to its end or to its first prompt. False when a pass is rejected.
static func play_table(engine: MatchEngine, own: Array[int], theirs: Array[int]) -> bool:
	for seat: int in range(MatchEngine.SEATS):
		var row: Array[int] = []
		if seat == 0:
			row.assign(own)
		else:
			row.assign(theirs)
		var piles: MatchState.SeatPiles = engine._state.seats[seat]
		for card: int in row:
			piles.deck.erase(card)
			piles.hand.erase(card)
			piles.burned.erase(card)
		piles.board.assign(row)
	var none: Array[int] = []
	for _step: int in range(MatchEngine.SEATS):
		if not engine.apply(EngineAction.commit(engine.awaited_seat(), none)).ok:
			return false
	return true
