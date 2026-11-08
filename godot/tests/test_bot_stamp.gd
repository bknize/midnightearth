class_name TestBotStamp
extends GdUnitTestSuite
## BotStamp (cycle 11 R1, plan P1, T01): "r<RULES_VERSION>-" and the first 16 hex digits of
## SHA-256 over cards.json, then decks.json, then crew.json. The pinned digest is over a frozen
## copy of the three data files as T01 found them (tests/fixtures/stamp/), the same digits
## scripts/bot/records.py current_stamp() gives for those paths (scripts/bot/test_records.py
## pins the same value), so the cross-check never moves with the shipped data.

const FIXTURE_CARDS: String = "res://tests/fixtures/stamp/cards.json"
const FIXTURE_DECKS: String = "res://tests/fixtures/stamp/decks.json"
const FIXTURE_CREW: String = "res://tests/fixtures/stamp/crew.json"
## The first 16 hex digits of SHA-256 over the three fixtures, cards, decks then Crew:
## `cat cards.json decks.json crew.json | shasum -a 256`.
const PINNED_DIGEST: String = "857b165d5a5d755e"
## A scratch Crew file for the Crew change test, which writes and removes it.
const CHANGED_CREW: String = "user://test_bot_stamp_crew.json"
const MISSING: String = "res://engine/data/none.json"


## Rules 9 since DC-20 T03 (cycle 14 R12).
func test_shape_is_r9_and_16_lowercase_hex() -> void:
	var stamp: String = BotStamp.current()
	var shape: RegEx = RegEx.create_from_string("^r(\\d+)-[0-9a-f]{16}$")
	var found: RegExMatch = shape.search(stamp)
	assert_object(found).is_not_null()
	if found != null:
		assert_str(found.get_string(1)).is_equal(str(MatchRules.RULES_VERSION))
	assert_str(stamp.substr(0, 3)).is_equal("r9-")


func test_fixture_stamp_equals_the_pinned_digest() -> void:
	var expected: String = "r%d-%s" % [MatchRules.RULES_VERSION, PINNED_DIGEST]
	var stamp: String = BotStamp.current(FIXTURE_CARDS, FIXTURE_DECKS, FIXTURE_CREW)
	assert_str(stamp).is_equal(expected)


## The defaults are the engine's data files, hashed cards, decks, then Crew.
func test_hashes_the_engine_files_in_order() -> void:
	var stamp: String = BotStamp.current(
		CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, CrewPool.DEFAULT_PATH
	)
	assert_str(stamp).is_equal(BotStamp.current())
	var swapped: String = BotStamp.current(
		DeckList.DEFAULT_PATH, CardDb.DEFAULT_PATH, CrewPool.DEFAULT_PATH
	)
	assert_str(swapped).is_not_equal(stamp)


## A change to the Crew pool file alone changes the stamp; the same bytes under another path
## give the same stamp.
func test_a_crew_byte_change_changes_the_stamp() -> void:
	var shipped: PackedByteArray = FileAccess.get_file_as_bytes(CrewPool.DEFAULT_PATH)
	assert_bool(shipped.is_empty()).is_false()
	var stamp: String = BotStamp.current()
	assert_bool(_write(CHANGED_CREW, shipped)).is_true()
	var copied: String = BotStamp.current(CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, CHANGED_CREW)
	assert_str(copied).is_equal(stamp)
	var changed: PackedByteArray = shipped.duplicate()
	changed[0] = (changed[0] + 1) % 256
	assert_bool(_write(CHANGED_CREW, changed)).is_true()
	var moved: String = BotStamp.current(CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, CHANGED_CREW)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHANGED_CREW))
	assert_str(moved).is_not_empty()
	assert_str(moved).is_not_equal(stamp)


## Any one missing file gives "".
func test_a_missing_file_gives_empty() -> void:
	assert_str(BotStamp.current(MISSING, DeckList.DEFAULT_PATH, CrewPool.DEFAULT_PATH)).is_empty()
	assert_str(BotStamp.current(CardDb.DEFAULT_PATH, MISSING, CrewPool.DEFAULT_PATH)).is_empty()
	assert_str(BotStamp.current(CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, MISSING)).is_empty()


## Rules 9 (DC-20 T03, cycle 14 R12): the shipped data's stamp, the digest unchanged since
## cards.json, decks.json and crew.json are not edited.
func test_current_is_the_rules_9_stamp() -> void:
	assert_str(BotStamp.current()).is_equal("r9-857b165d5a5d755e")


## Stable across calls.
func test_current_is_stable() -> void:
	assert_str(BotStamp.current()).is_equal(BotStamp.current())


## Writes `bytes` to `path`; false when the file cannot be opened.
func _write(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var stored: bool = file.store_buffer(bytes)
	file.close()
	return stored
