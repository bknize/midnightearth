class_name TestBotStamp
extends GdUnitTestSuite
## BotStamp (cycle 7 T03; R33, plan P8; cycle 8 R58, P15, DC-11 T11): "r<RULES_VERSION>-" and
## the first 16 hex digits of SHA-256 over cards.json, then decks.json, then crew.json. The
## pinned digest is over the frozen DC-05 test fixtures (cards, deck list and Crew pool), the
## same digits scripts/bot/records.py current_stamp() gives for those paths
## (scripts/bot/test_records.py pins the same value), so the cross-check never moves with the
## shipped data: a rules or data change only prints `stamp=MISMATCH` on the sweep line and
## leaves the gate green (R35; DC-08 T11).

const FIXTURE_CARDS: String = "res://tests/fixtures/dc05_cards.json"
const FIXTURE_DECKS: String = "res://tests/fixtures/dc05_decks.json"
## A frozen copy of the Crew pool as DC-11 T11 found it (engine/data/crew.json, version 1).
const FIXTURE_CREW: String = "res://tests/fixtures/dc05_crew.json"
## The first 16 hex digits of SHA-256 over the three fixtures, cards, decks then Crew, as
## records.py hashes them: `cat dc05_cards.json dc05_decks.json dc05_crew.json | shasum -a
## 256` (DC-11 T11; the two-file digest before it was 4cb8728fa00d5b9f).
const PINNED_DIGEST: String = "c8bbaeae375ceee6"
## A scratch Crew file for the Crew change test, which writes and removes it.
const CHANGED_CREW: String = "user://test_bot_stamp_crew.json"


func test_shape_is_rules_version_and_16_hex() -> void:
	var stamp: String = BotStamp.current()
	var shape: RegEx = RegEx.create_from_string("^r(\\d+)-[0-9a-f]{16}$")
	var found: RegExMatch = shape.search(stamp)
	assert_object(found).is_not_null()
	if found != null:
		assert_str(found.get_string(1)).is_equal(str(MatchRules.RULES_VERSION))


func test_fixture_stamp_equals_the_pinned_digest() -> void:
	var expected: String = "r%d-%s" % [MatchRules.RULES_VERSION, PINNED_DIGEST]
	var stamp: String = BotStamp.current(FIXTURE_CARDS, FIXTURE_DECKS, FIXTURE_CREW)
	assert_str(stamp).is_equal(expected)


## The defaults are the engine's data files, hashed cards, decks, then Crew.
func test_hashes_the_engine_files_cards_first() -> void:
	var stamp: String = BotStamp.current(
		CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, CrewPool.DEFAULT_PATH
	)
	assert_str(stamp).is_equal(BotStamp.current())
	var swapped: String = BotStamp.current(
		DeckList.DEFAULT_PATH, CardDb.DEFAULT_PATH, CrewPool.DEFAULT_PATH
	)
	assert_str(swapped).is_not_equal(stamp)
	var crew_first: String = BotStamp.current(
		CrewPool.DEFAULT_PATH, DeckList.DEFAULT_PATH, CardDb.DEFAULT_PATH
	)
	assert_str(crew_first).is_not_equal(stamp)


## Cycle 8 R58: a change to the Crew pool file alone changes the stamp; the same bytes under
## another path give the same stamp; a missing Crew file gives "".
func test_a_crew_change_changes_the_stamp() -> void:
	var shipped: PackedByteArray = FileAccess.get_file_as_bytes(CrewPool.DEFAULT_PATH)
	assert_bool(shipped.is_empty()).is_false()
	var stamp: String = BotStamp.current()
	assert_bool(_write(CHANGED_CREW, shipped)).is_true()
	var copied: String = BotStamp.current(CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, CHANGED_CREW)
	assert_str(copied).is_equal(stamp)
	var changed: PackedByteArray = shipped.duplicate()
	changed.append(0x0A)
	assert_bool(_write(CHANGED_CREW, changed)).is_true()
	var moved: String = BotStamp.current(CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, CHANGED_CREW)
	assert_str(moved).is_not_empty()
	assert_str(moved).is_not_equal(stamp)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHANGED_CREW))
	var missing: String = BotStamp.current(
		CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, "res://engine/data/none.json"
	)
	assert_str(missing).is_empty()


## Writes `bytes` to `path`; false when the file cannot be opened.
func _write(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var stored: bool = file.store_buffer(bytes)
	file.close()
	return stored


## Other data gives another stamp; a missing file gives "".
func test_other_data_changes_the_stamp() -> void:
	var fixture: String = BotStamp.current(FixtureDecks.CARDS_PATH, FixtureDecks.DECKS_PATH)
	assert_str(fixture).is_not_empty()
	assert_str(fixture).is_not_equal(BotStamp.current())
	assert_str(BotStamp.current("res://engine/data/none.json", DeckList.DEFAULT_PATH)).is_empty()


## Stable across calls.
func test_current_is_stable() -> void:
	assert_str(BotStamp.current()).is_equal(BotStamp.current())
