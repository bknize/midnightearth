class_name FixtureDecks
extends RefCounted
## The DC-05 fixture for the suites (DC-07 T02, plan P1, R4): the 20 fixture cards and the
## one-deck list `fixture`, played on both seats. Every suite written before DC-07 runs on
## it, so its instance ids still mean `seat * 20 + index into c01..c20`, and it does not
## depend on the shipped pool or deck list. Not a suite: builders only, nothing cached.

const CARDS_PATH: String = "res://tests/fixtures/dc05_cards.json"
const DECKS_PATH: String = "res://tests/fixtures/dc05_decks.json"
const DECK_ID: String = "fixture"


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
