class_name TestCrewPool
extends GdUnitTestSuite
## CrewPool and CrewDef v2 (DC-13 T02; cycle 9 plan P4, spec R62, R64): the shipped Crew file
## loads the six milestone A Crew with the moment, verb, amounts and text of rules/crew-v2,
## and an entry whose moment or verb is not in the table (or a verb on another moment, an
## amount out of range, a non-bool `optional`, bad uses or scope) fails the load by name.

const IDS: Array[String] = ["tallyman", "void", "engineer", "navigator", "captain", "dredger"]
## The canon's rows (rules/crew-v2), as [id, name, tag, moment, verb, amount, amount_2, text].
const CANON: Array = [
	[
		"tallyman",
		"Tallyman",
		"greed",
		"ongoing",
		"tallyman_fifth",
		5,
		200,
		"Your 5th, 10th, 15th ... Scoring card in a Walk gets Mult ×2 for that Score."
	],
	[
		"void",
		"Void",
		"greed",
		"on_empty_draw",
		"void_grant",
		10,
		50,
		(
			"Your next Scoring card gets Power +10, Add +0.5 and Mult ×1.25 until it Scores or"
			+ " turn end."
		)
	],
	[
		"engineer",
		"Engineer",
		"evergreen",
		"ongoing",
		"engineer_energy",
		1,
		3,
		"From Turn 3 of each Round, your Budget is +1 Energy."
	],
	[
		"navigator",
		"Navigator",
		"ramp",
		"on_score",
		"navigator_second",
		2,
		2,
		(
			"The second of your cards to Score in a Walk gets Power +2 permanently, after it"
			+ " has Scored."
		)
	],
	[
		"captain",
		"Captain",
		"ramp",
		"on_score",
		"captain_leftmost",
		1,
		0,
		(
			"When the card in the leftmost slot of your row Scores, it gets Power +1 for the"
			+ " match, after it has Scored."
		)
	],
	[
		"dredger",
		"Dredger",
		"graveyard",
		"on_empty_draw",
		"dredge",
		0,
		0,
		"Shuffle your Pile into your Deck."
	],
]

# --- Helpers --------------------------------------------------------------------------


## A well-formed Crew entry: Void's shape.
func _entry() -> Dictionary:
	return {
		"id": "void",
		"name": "Void",
		"tag": "greed",
		"moment": "on_empty_draw",
		"verb": "void_grant",
		"amount": 10,
		"amount_2": 50,
		"optional": false,
		"uses": 0,
		"scope": "turn",
		"text": "Your next Scoring card gets a grant.",
	}


func _pool_of(entries: Array, version: int = CrewPool.FORMAT_VERSION) -> CrewPool:
	return CrewPool.from_json(JSON.stringify({"version": version, "crew": entries}))


## `_entry()` with `key` set to `value`, as a one-Crew pool.
func _with(key: String, value: Variant) -> CrewPool:
	var entry: Dictionary = _entry()
	entry[key] = value
	return _pool_of([entry])


func _assert_invalid(pool: CrewPool, prefix: String) -> void:
	assert_bool(pool.is_valid()).override_failure_message(prefix).is_false()
	assert_str(pool.load_error()).starts_with(prefix)
	assert_str(pool.validate()).starts_with(prefix)
	assert_int(pool.size()).is_equal(0)
	assert_array(pool.ids()).is_empty()


# --- The shipped file -----------------------------------------------------------------


func test_the_shipped_file_loads_the_six_crew() -> void:
	var pool: CrewPool = CrewPool.load_default()
	assert_bool(pool.is_valid()).override_failure_message(pool.load_error()).is_true()
	assert_str(pool.validate()).is_empty()
	assert_int(pool.size()).is_equal(6)
	assert_array(pool.ids()).is_equal(IDS)


func test_every_shipped_crew_matches_the_canon() -> void:
	var pool: CrewPool = CrewPool.load_default()
	for raw: Variant in CANON:
		var row: Array = raw
		var crew_id: String = row[0]
		var def: CrewDef = pool.crew_of(crew_id)
		assert_object(def).override_failure_message(crew_id).is_not_null()
		if def == null:
			continue
		var crew_name: String = row[1]
		var tag: String = row[2]
		var moment: String = row[3]
		var verb: String = row[4]
		var amount: int = row[5]
		var amount_2: int = row[6]
		var text: String = row[7]
		assert_str(def.name).is_equal(crew_name)
		assert_str(def.tag).is_equal(tag)
		assert_str(def.moment).is_equal(moment)
		assert_str(def.verb).is_equal(verb)
		assert_int(def.amount).override_failure_message(crew_id).is_equal(amount)
		assert_int(def.amount_2).override_failure_message(crew_id).is_equal(amount_2)
		assert_str(def.text).override_failure_message(crew_id).is_equal(text)
		# Every v2 Crew is unlimited and none prompts in milestone A (rules/crew-v2).
		assert_int(def.uses).is_equal(0)
		assert_int(def.initial_uses()).is_equal(CrewDef.UNLIMITED)
		assert_bool(def.optional).is_false()


func test_a_crew_round_trips_through_to_dict() -> void:
	var pool: CrewPool = CrewPool.load_default()
	var entries: Array = []
	for def: CrewDef in pool.all():
		entries.append(def.to_dict())
	var again: CrewPool = _pool_of(entries)
	assert_bool(again.is_valid()).override_failure_message(again.load_error()).is_true()
	for crew_id: String in IDS:
		assert_dict(again.crew_of(crew_id).to_dict()).is_equal(pool.crew_of(crew_id).to_dict())


# --- The checks -----------------------------------------------------------------------


func test_a_moment_not_in_the_table_fails() -> void:
	_assert_invalid(_with("moment", "turn_start"), CrewPool.ERR_MOMENT)
	_assert_invalid(_with("moment", "on_tuesday"), CrewPool.ERR_MOMENT)


func test_a_verb_not_in_the_table_fails() -> void:
	# A v6 Crew verb is no longer known (cycle 9 R63), nor a card verb.
	_assert_invalid(_with("verb", "unreveal_own_one"), CrewPool.ERR_VERB)
	_assert_invalid(_with("verb", "draw"), CrewPool.ERR_VERB)


func test_a_verb_on_another_moment_fails() -> void:
	_assert_invalid(_with("moment", "on_score"), CrewPool.ERR_PAIR)
	_assert_invalid(_with("moment", "ongoing"), CrewPool.ERR_PAIR)


func test_every_verb_loads_on_its_own_moment_with_amounts_in_range() -> void:
	for verb: String in CrewDef.VERBS:
		var row: Dictionary = CrewDef.VERBS[verb]
		var moment: String = row["moment"]
		var entry: Dictionary = _entry()
		entry["verb"] = verb
		entry["moment"] = moment
		for key: String in ["amount", "amount_2"]:
			var bounds: Array[int] = CrewDef.range_of(verb, key)
			entry[key] = bounds[0]
		var pool: CrewPool = _pool_of([entry])
		assert_bool(pool.is_valid()).override_failure_message(pool.load_error()).is_true()
		for key: String in ["amount", "amount_2"]:
			var bounds: Array[int] = CrewDef.range_of(verb, key)
			var wrong: Dictionary = entry.duplicate()
			wrong[key] = bounds[1] + 1
			_assert_invalid(_pool_of([wrong]), CrewPool.ERR_AMOUNT)


func test_bad_optional_uses_scope_tag_and_shape_fail() -> void:
	_assert_invalid(_with("optional", "yes"), CrewPool.ERR_OPTIONAL)
	_assert_invalid(_with("uses", -1), CrewPool.ERR_USES)
	_assert_invalid(_with("uses", 1.5), CrewPool.ERR_USES)
	_assert_invalid(_with("scope", "round"), CrewPool.ERR_SCOPE)
	_assert_invalid(_with("tag", "Greed"), CrewPool.ERR_TAG)
	_assert_invalid(_with("text", ""), CrewPool.ERR_SHAPE)
	_assert_invalid(_with("id", 3), CrewPool.ERR_SHAPE)


func test_a_duplicate_id_old_version_and_bad_json_fail() -> void:
	_assert_invalid(_pool_of([_entry(), _entry()]), CrewPool.ERR_DUPLICATE)
	_assert_invalid(_pool_of([_entry()], 1), CrewPool.ERR_VERSION)
	_assert_invalid(CrewPool.from_json("{oops"), CrewPool.ERR_JSON)
	_assert_invalid(CrewPool.from_json('{"version": 2}'), CrewPool.ERR_SHAPE)
	_assert_invalid(CrewPool.load_from_path("res://no/such/crew.json"), CrewPool.ERR_FILE)


func test_lookups() -> void:
	var pool: CrewPool = CrewPool.load_default()
	assert_bool(pool.has_id("dredger")).is_true()
	assert_bool(pool.has_id("gardener")).is_false()
	assert_object(pool.crew_of("nope")).is_null()
	assert_int(pool.all().size()).is_equal(6)
