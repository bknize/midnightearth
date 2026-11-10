class_name TestJsonLoad
extends GdUnitTestSuite
## JsonLoad (B-30): the file, JSON, top-level and version steps the three pool loaders
## share, each error message byte for byte, and through each loader with its own label.

const FORMAT: int = 7


func test_a_missing_file_is_named_with_the_label() -> void:
	var read: JsonLoad = JsonLoad.read("res://no/such.json", "some file")
	assert_str(read.error).is_equal("some file not found: res://no/such.json")
	assert_str(read.text).is_empty()


func test_a_shipped_file_reads() -> void:
	var read: JsonLoad = JsonLoad.read(CrewPool.DEFAULT_PATH, "some file")
	assert_str(read.error).is_empty()
	assert_str(read.text).is_not_empty()


func test_each_bad_top_level_has_its_message() -> void:
	assert_str(JsonLoad.parse("{oops", FORMAT).error).starts_with("bad JSON at line ")
	assert_str(JsonLoad.parse("[]", FORMAT).error).is_equal("bad shape: top level is not an object")
	var missing: String = "bad shape: missing or non-integer version"
	assert_str(JsonLoad.parse("{}", FORMAT).error).is_equal(missing)
	assert_str(JsonLoad.parse('{"version": "7"}', FORMAT).error).is_equal(missing)
	assert_str(JsonLoad.parse('{"version": 7.5}', FORMAT).error).is_equal(missing)
	assert_str(JsonLoad.parse('{"version": 6}', FORMAT).error).is_equal(
		"unsupported version: 6 (expected 7)"
	)


func test_a_good_top_level_gives_its_object() -> void:
	var parsed: JsonLoad = JsonLoad.parse('{"version": 7, "rows": []}', FORMAT)
	assert_str(parsed.error).is_empty()
	assert_bool(parsed.root.has("rows")).is_true()


func test_each_loader_reports_the_same_messages_with_its_own_file_label() -> void:
	assert_str(CardDb.load_from_path("res://nope.json").load_error()).is_equal(
		"card data file not found: res://nope.json"
	)
	assert_str(CrewPool.load_from_path("res://nope.json").load_error()).is_equal(
		"crew file not found: res://nope.json"
	)
	assert_str(DeckList.load_from_path("res://nope.json").load_error()).is_equal(
		"deck list file not found: res://nope.json"
	)
	assert_str(CardDb.from_json('{"version": 4}').load_error()).is_equal(
		"unsupported version: 4 (expected 5)"
	)
	assert_str(CrewPool.from_json('{"version": 1}').load_error()).is_equal(
		"unsupported version: 1 (expected 2)"
	)
	assert_str(DeckList.from_json('{"version": 2}').load_error()).is_equal(
		"unsupported version: 2 (expected 3)"
	)
	assert_str(CardDb.from_json('{"version": 5}').load_error()).is_equal(
		"bad shape: missing cards array"
	)
	assert_str(CrewPool.from_json('{"version": 2}').load_error()).is_equal(
		"bad shape: missing crew array"
	)
	assert_str(DeckList.from_json('{"version": 3}').load_error()).is_equal(
		"bad shape: missing decks array"
	)
