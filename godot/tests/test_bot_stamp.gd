class_name TestBotStamp
extends GdUnitTestSuite
## BotStamp (cycle 7 T03; R33, plan P8): "r<RULES_VERSION>-" and the first 16 hex digits of
## SHA-256 over cards.json then decks.json. The pinned digest is over the frozen DC-05 test
## fixtures, the same digits scripts/bot/records.py current_stamp() gives for those paths, so
## the cross-check never moves with the shipped data: a rules or data change only prints
## `stamp=MISMATCH` on the sweep line and leaves the gate green (R35; DC-08 T11).

const FIXTURE_CARDS: String = "res://tests/fixtures/dc05_cards.json"
const FIXTURE_DECKS: String = "res://tests/fixtures/dc05_decks.json"
## The first 16 hex digits of SHA-256 over the two fixtures, cards first (shasum -a 256).
const PINNED_DIGEST: String = "c5eb3b461a81e9be"


func test_shape_is_rules_version_and_16_hex() -> void:
	var stamp: String = BotStamp.current()
	var shape: RegEx = RegEx.create_from_string("^r(\\d+)-[0-9a-f]{16}$")
	var found: RegExMatch = shape.search(stamp)
	assert_object(found).is_not_null()
	if found != null:
		assert_str(found.get_string(1)).is_equal(str(MatchRules.RULES_VERSION))


func test_fixture_stamp_equals_the_pinned_digest() -> void:
	var expected: String = "r%d-%s" % [MatchRules.RULES_VERSION, PINNED_DIGEST]
	assert_str(BotStamp.current(FIXTURE_CARDS, FIXTURE_DECKS)).is_equal(expected)


## The defaults are the engine's data files, hashed cards first.
func test_hashes_the_engine_files_cards_first() -> void:
	var stamp: String = BotStamp.current(CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH)
	assert_str(stamp).is_equal(BotStamp.current())
	var swapped: String = BotStamp.current(DeckList.DEFAULT_PATH, CardDb.DEFAULT_PATH)
	assert_str(swapped).is_not_equal(stamp)


## Other data gives another stamp; a missing file gives "".
func test_other_data_changes_the_stamp() -> void:
	var fixture: String = BotStamp.current(FixtureDecks.CARDS_PATH, FixtureDecks.DECKS_PATH)
	assert_str(fixture).is_not_empty()
	assert_str(fixture).is_not_equal(BotStamp.current())
	assert_str(BotStamp.current("res://engine/data/none.json", DeckList.DEFAULT_PATH)).is_empty()


## Stable across calls.
func test_current_is_stable() -> void:
	assert_str(BotStamp.current()).is_equal(BotStamp.current())
