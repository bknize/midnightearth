class_name TestBotWeights
extends GdUnitTestSuite
## BotWeights (cycle 13 T02; spec R4, R8, R9, plan P2, P15): the committed file loads clean
## with the current stamp and the defaults' weights; a file round-trips through to_json();
## every fault of R9 gives the defaults with `load_error`; vector() lays the weights out in
## BotFeatures order; stamp_matches() compares with BotStamp.current().

const MISSING_PATH: String = "res://engine/bot/data/no_such_weights.json"
const GOOD_TEXT: String = (
	'{"version": 2, "bot": "linear", "stamp": "r7-0123456789abcdef", "features": "f1",'
	+ ' "k": 30, "fit": {"id": "fit-1", "runs": ["run-a", "run-b"], "digest": "abc"},'
	+ ' "weights": {"committed_power": 250, "budget_left": -20, "card:greed_01": 7}}'
)


## The fields defaults() gives.
func _assert_defaults(weights: BotWeights) -> void:
	assert_int(weights.k).is_equal(BotWeights.DEFAULT_K)
	assert_str(weights.stamp).is_equal("")
	assert_str(weights.features).is_equal(BotFeatures.SET_VERSION)
	assert_dict(weights.weights).is_equal({"committed_power": 100})
	assert_str(weights.fit["id"]).is_equal("")


## A shipped card id for a `card:` weight (the first of the pool).
func _first_card_name() -> String:
	var names: Array[String] = BotWeights.known_names()
	return names[BotFeatures.COMPACT.size()]


func test_defaults_count_committed_power_once() -> void:
	var weights: BotWeights = BotWeights.defaults()
	assert_str(weights.load_error).is_equal("")
	assert_str(weights.bot).is_equal("linear")
	_assert_defaults(weights)


## P15: the committed file loads clean, stamped with the current stamp, on feature set f1,
## `k` 64, committed Power at 100 and nothing else weighed.
func test_committed_file_loads_with_the_current_stamp() -> void:
	var weights: BotWeights = BotWeights.load(BotWeights.DEFAULT_PATH)
	assert_str(weights.load_error).is_equal("")
	assert_str(weights.stamp).is_equal("r7-857b165d5a5d755e")
	assert_bool(weights.stamp_matches()).is_true()
	assert_int(weights.k).is_equal(64)
	assert_dict(weights.weights).is_equal({"committed_power": 100})


## The known names are BotFeatures.COMPACT then one `card:<id>` per shipped card.
func test_known_names_are_the_feature_set_over_the_shipped_pool() -> void:
	var names: Array[String] = BotWeights.known_names()
	var pool: CardDb = CardDb.load_default()
	assert_int(names.size()).is_equal(BotFeatures.COMPACT.size() + pool.size())
	assert_str(names[0]).is_equal("pass")
	assert_str(_first_card_name()).is_equal(BotFeatures.CARD_PREFIX + pool.card_at(0).id)


func test_good_text_reads_every_field() -> void:
	var text: String = GOOD_TEXT.replace("card:greed_01", _first_card_name())
	var weights: BotWeights = BotWeights.from_json(text)
	assert_str(weights.load_error).is_equal("")
	assert_str(weights.stamp).is_equal("r7-0123456789abcdef")
	assert_int(weights.k).is_equal(30)
	assert_str(weights.fit["id"]).is_equal("fit-1")
	assert_array(weights.fit["runs"]).is_equal(["run-a", "run-b"])
	assert_str(weights.fit["digest"]).is_equal("abc")
	var power: int = weights.weights["committed_power"]
	var left: int = weights.weights["budget_left"]
	var card: int = weights.weights[_first_card_name()]
	assert_int(power).is_equal(250)
	assert_int(left).is_equal(-20)
	assert_int(card).is_equal(7)
	assert_bool(weights.stamp_matches()).is_false()


## R8: to_json() reads back to the same fields.
func test_to_json_round_trips() -> void:
	var text: String = GOOD_TEXT.replace("card:greed_01", _first_card_name())
	var original: BotWeights = BotWeights.from_json(text)
	var copy: BotWeights = BotWeights.from_json(original.to_json())
	assert_str(copy.load_error).is_equal("")
	assert_str(copy.bot).is_equal(original.bot)
	assert_str(copy.stamp).is_equal(original.stamp)
	assert_str(copy.features).is_equal(original.features)
	assert_int(copy.k).is_equal(original.k)
	assert_dict(copy.fit).is_equal(original.fit)
	assert_dict(copy.weights).is_equal(original.weights)
	assert_str(copy.to_json()).is_equal(original.to_json())


## R9: a missing file gives the defaults with load_error.
func test_missing_file_gives_the_defaults() -> void:
	var weights: BotWeights = BotWeights.load(MISSING_PATH)
	assert_str(weights.load_error).contains("not found")
	_assert_defaults(weights)


## R9: every other fault gives the defaults with load_error: malformed JSON, not an object,
## another or no format version, another or no feature set, an unknown feature, a weight
## that is not whole (a fraction, a string), a weight out of range either way, and fields of
## the wrong shape (`k` below 1 or fractional, `stamp`, `fit`, `weights`).
func test_every_fault_gives_the_defaults_with_load_error() -> void:
	var faults: Array[String] = [
		"{not json",
		"[1, 2]",
		'{"features": "f1"}',
		'{"version": 1, "features": "f1"}',
		'{"version": 2}',
		'{"version": 2, "features": "f0"}',
		'{"version": 2, "features": "f1", "weights": {"luck": 5}}',
		'{"version": 2, "features": "f1", "weights": {"card:no_such_card": 5}}',
		'{"version": 2, "features": "f1", "weights": {"committed_power": 1.5}}',
		'{"version": 2, "features": "f1", "weights": {"committed_power": "100"}}',
		'{"version": 2, "features": "f1", "weights": {"committed_power": 1000001}}',
		'{"version": 2, "features": "f1", "weights": {"committed_power": -1000001}}',
		'{"version": 2, "features": "f1", "weights": [100]}',
		'{"version": 2, "features": "f1", "k": 0}',
		'{"version": 2, "features": "f1", "k": 4.5}',
		'{"version": 2, "features": "f1", "stamp": 4}',
		'{"version": 2, "features": "f1", "fit": []}',
		'{"version": 2, "features": "f1", "fit": {"runs": [1]}}',
	]
	for text: String in faults:
		var weights: BotWeights = BotWeights.from_json(text)
		if weights.load_error == "":
			fail("no load_error for %s" % text)
		_assert_defaults(weights)


## A whole-number float (JSON's 48.0) is accepted as an int; a file with no weights keeps
## the defaults' table with no error.
func test_whole_floats_and_absent_weights() -> void:
	var weights: BotWeights = BotWeights.from_json(
		'{"version": 2.0, "features": "f1", "k": 12.0, "weights": {"committed_power": 300.0}}'
	)
	assert_str(weights.load_error).is_equal("")
	assert_int(weights.k).is_equal(12)
	var power: int = weights.weights["committed_power"]
	assert_int(power).is_equal(300)
	var bare: BotWeights = BotWeights.from_json('{"version": 2, "features": "f1"}')
	assert_str(bare.load_error).is_equal("")
	assert_dict(bare.weights).is_equal({"committed_power": 100})


## vector() lays the weights out in the given order, 0 for a name not weighed.
func test_vector_follows_the_names() -> void:
	var weights: BotWeights = BotWeights.from_json(
		'{"version": 2, "features": "f1", "weights": {"pass": -5, "committed_power": 100}}'
	)
	var names: Array[String] = ["committed_power", "turn", "pass", "card:x"]
	var vector: PackedInt64Array = weights.vector(names)
	assert_int(vector.size()).is_equal(4)
	assert_int(vector[0]).is_equal(100)
	assert_int(vector[1]).is_equal(0)
	assert_int(vector[2]).is_equal(-5)
	assert_int(vector[3]).is_equal(0)


## stamp_matches(): true only for the current stamp; false for another or none.
func test_stamp_matches() -> void:
	var current: String = BotStamp.current()
	assert_str(current).is_not_empty()
	var weights: BotWeights = BotWeights.defaults()
	assert_bool(weights.stamp_matches()).is_false()
	weights.stamp = current
	assert_bool(weights.stamp_matches()).is_true()
	weights.stamp = "r7-0000000000000000"
	assert_bool(weights.stamp_matches()).is_false()


## cached() parses a path once: the same object on the second call; "" is DEFAULT_PATH.
func test_cached_parses_once_per_path() -> void:
	var first: BotWeights = BotWeights.cached(BotWeights.DEFAULT_PATH)
	assert_object(BotWeights.cached(BotWeights.DEFAULT_PATH)).is_same(first)
	assert_object(BotWeights.cached("")).is_same(first)
	var missing: BotWeights = BotWeights.cached(MISSING_PATH)
	assert_str(missing.load_error).is_not_empty()
	assert_object(BotWeights.cached(MISSING_PATH)).is_same(missing)
