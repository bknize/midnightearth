class_name TestBotWeights
extends GdUnitTestSuite
## BotWeights (cycle 7 T03; R10, R11, R34, plan P7): the shipped tuned file loads clean and
## carries the current stamp; every fault sets `load_error` and leaves the defaults in force;
## to_json() reads back to the same fields.

const SHIPPED_PATH: String = "res://engine/bot/data/tuned_weights.json"
const MISSING_PATH: String = "res://engine/bot/data/no_such_weights.json"
const GOOD_TEXT: String = (
	'{"version": 1, "bot": "tuned", "stamp": "r4-0123456789abcdef", "k": 30, "k_opp": 9,'
	+ ' "samples": 3, "rm_iterations": 150, "push_unit": 7,'
	+ ' "weights": {"score_diff": 100, "energy_left": -20}}'
)


## A default-valued object: the fields defaults() gives.
func _assert_defaults(weights: BotWeights) -> void:
	assert_int(weights.k).is_equal(24)
	assert_int(weights.k_opp).is_equal(12)
	assert_int(weights.samples).is_equal(4)
	assert_int(weights.rm_iterations).is_equal(200)
	assert_int(weights.push_unit).is_equal(10)
	assert_dict(weights.weights).is_equal({"score_diff": 100})
	assert_str(weights.stamp).is_equal("")


func test_defaults_have_k_24_and_score_diff() -> void:
	var weights: BotWeights = BotWeights.defaults("tuned")
	assert_str(weights.bot).is_equal("tuned")
	assert_str(weights.load_error).is_equal("")
	_assert_defaults(weights)


## R34: the shipped file loads with no error, for the tuned bot, carrying a stamp, with the
## plan's numbers and score_diff at 100, every other feature at 0. Whether that stamp is the
## current one is the sweep's printed check, never a failure (R35; DC-08 T11).
func test_shipped_file_loads_with_a_stamp() -> void:
	var weights: BotWeights = BotWeights.load(SHIPPED_PATH)
	assert_str(weights.load_error).is_equal("")
	assert_str(weights.bot).is_equal("tuned")
	assert_str(weights.stamp).is_not_empty()
	assert_int(weights.k).is_equal(24)
	assert_int(weights.k_opp).is_equal(12)
	assert_int(weights.samples).is_equal(4)
	assert_int(weights.rm_iterations).is_equal(200)
	assert_int(weights.push_unit).is_equal(10)
	assert_int(weights.weights.size()).is_equal(Evaluator.FEATURES.size())
	for feature: String in Evaluator.FEATURES:
		var weight: int = weights.weights[feature]
		assert_int(weight).is_equal(100 if feature == "score_diff" else 0)


## The registry's path for `tuned` is the shipped file.
func test_registry_path_is_the_shipped_file() -> void:
	assert_str(BotRegistry.default_weights_path("tuned")).is_equal(SHIPPED_PATH)


func test_good_text_reads_every_field() -> void:
	var weights: BotWeights = BotWeights.from_json(GOOD_TEXT)
	assert_str(weights.load_error).is_equal("")
	assert_str(weights.bot).is_equal("tuned")
	assert_str(weights.stamp).is_equal("r4-0123456789abcdef")
	assert_int(weights.k).is_equal(30)
	assert_int(weights.k_opp).is_equal(9)
	assert_int(weights.samples).is_equal(3)
	assert_int(weights.rm_iterations).is_equal(150)
	assert_int(weights.push_unit).is_equal(7)
	var score_diff: int = weights.weights["score_diff"]
	var energy_left: int = weights.weights["energy_left"]
	assert_int(score_diff).is_equal(100)
	assert_int(energy_left).is_equal(-20)
	assert_int(weights.weights.size()).is_equal(2)


## R11: a missing file sets load_error and leaves the defaults.
func test_missing_file_sets_load_error() -> void:
	var weights: BotWeights = BotWeights.load(MISSING_PATH)
	assert_str(weights.load_error).is_not_empty()
	_assert_defaults(weights)


## R11: a weight naming no feature sets load_error and leaves the defaults.
func test_unknown_feature_sets_load_error() -> void:
	var weights: BotWeights = BotWeights.from_json(
		'{"version": 1, "bot": "tuned", "k": 30, "weights": {"score_diff": 100, "luck": 5}}'
	)
	assert_str(weights.load_error).contains("luck")
	_assert_defaults(weights)


## R11: a weight that is not a whole number sets load_error and leaves the defaults.
func test_non_integer_weight_sets_load_error() -> void:
	var weights: BotWeights = BotWeights.from_json(
		'{"version": 1, "bot": "tuned", "weights": {"score_diff": 1.5}}'
	)
	assert_str(weights.load_error).is_not_empty()
	_assert_defaults(weights)
	var text: BotWeights = BotWeights.from_json(
		'{"version": 1, "bot": "tuned", "weights": {"score_diff": "100"}}'
	)
	assert_str(text.load_error).is_not_empty()
	_assert_defaults(text)


## Every other fault: bad JSON, not an object, a wrong or missing version, a non-integer
## or out-of-range cap, a weights entry that is not an object, a stamp that is not a string,
## a weight beyond BotWeights.MAX_WEIGHT either way (DC-08 T10).
func test_other_faults_set_load_error() -> void:
	var faults: Array[String] = [
		"{not json",
		"[1, 2]",
		'{"version": 2}',
		'{"bot": "tuned"}',
		'{"version": 1, "k": 4.5}',
		'{"version": 1, "k": 0}',
		'{"version": 1, "push_unit": -1}',
		'{"version": 1, "weights": [100]}',
		'{"version": 1, "stamp": 4}',
		'{"version": 1, "weights": {"score_diff": 100000000000}}',
		'{"version": 1, "weights": {"score_diff": -1000001}}',
	]
	for text: String in faults:
		var weights: BotWeights = BotWeights.from_json(text)
		assert_str(weights.load_error).is_not_empty()
		_assert_defaults(weights)


## A whole-number float (JSON's 48.0) is accepted as an int.
func test_whole_floats_are_ints() -> void:
	var weights: BotWeights = BotWeights.from_json(
		'{"version": 1.0, "k": 12.0, "weights": {"score_diff": 100.0}}'
	)
	assert_str(weights.load_error).is_equal("")
	assert_int(weights.k).is_equal(12)
	var score_diff: int = weights.weights["score_diff"]
	assert_int(score_diff).is_equal(100)


## to_json() reads back to the same fields.
func test_to_json_round_trips() -> void:
	var original: BotWeights = BotWeights.from_json(GOOD_TEXT)
	var copy: BotWeights = BotWeights.from_json(original.to_json())
	assert_str(copy.load_error).is_equal("")
	assert_str(copy.bot).is_equal(original.bot)
	assert_str(copy.stamp).is_equal(original.stamp)
	assert_int(copy.k).is_equal(original.k)
	assert_int(copy.k_opp).is_equal(original.k_opp)
	assert_int(copy.samples).is_equal(original.samples)
	assert_int(copy.rm_iterations).is_equal(original.rm_iterations)
	assert_int(copy.push_unit).is_equal(original.push_unit)
	assert_dict(copy.weights).is_equal(original.weights)
	var shipped: BotWeights = BotWeights.load(SHIPPED_PATH)
	var again: BotWeights = BotWeights.from_json(shipped.to_json())
	assert_dict(again.weights).is_equal(shipped.weights)
	assert_str(again.stamp).is_equal(shipped.stamp)
