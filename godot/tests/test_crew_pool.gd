class_name TestCrewPool
extends GdUnitTestSuite
## CrewPool and CrewDef (DC-11 T08; cycle 8 R39-R41, plan P12): the shipped Crew file loads
## with the plan's eight Crew, and a malformed entry (an unknown trigger or verb, a verb on
## another trigger, a non-bool `optional`, a bad scope or uses) fails the load silently.

const NAMES: Array[String] = [
	"quartermaster", "tallyman", "shade", "salvager", "veil", "navigator", "gardener", "lookout"
]

# --- Helpers --------------------------------------------------------------------------


## A well-formed Crew entry: Shade's shape, unlimited.
func _entry() -> Dictionary:
	return {
		"id": "shade",
		"name": "Shade",
		"trigger": "turn_start",
		"verb": "unreveal_own_one",
		"amount": 4,
		"optional": true,
		"uses": 0,
		"scope": "none",
		"text": "You may flip one revealed card of yours face down.",
	}


func _pool_of(entries: Array) -> CrewPool:
	return CrewPool.from_json(JSON.stringify({"version": CrewPool.FORMAT_VERSION, "crew": entries}))


## `_entry()` with `key` set to `value`, as a one-Crew pool.
func _with(key: String, value: Variant) -> CrewPool:
	var entry: Dictionary = _entry()
	entry[key] = value
	return _pool_of([entry])


func _assert_invalid(pool: CrewPool, prefix: String) -> void:
	assert_bool(pool.is_valid()).is_false()
	assert_str(pool.load_error()).starts_with(prefix)
	assert_str(pool.validate()).starts_with(prefix)
	assert_int(pool.size()).is_equal(0)
	assert_array(pool.ids()).is_empty()


# --- The shipped file -----------------------------------------------------------------


func test_the_shipped_file_loads_with_the_eight_crew() -> void:
	var pool: CrewPool = CrewPool.load_default()
	assert_bool(pool.is_valid()).override_failure_message(pool.load_error()).is_true()
	assert_str(pool.validate()).is_empty()
	assert_int(pool.size()).is_equal(8)
	assert_array(pool.ids()).is_equal(NAMES)
	for crew_id: String in NAMES:
		var def: CrewDef = pool.crew_of(crew_id)
		assert_object(def).is_not_null()
		if def == null:
			continue
		assert_str(def.id).is_equal(crew_id)
		assert_str(def.name).is_not_empty()
		assert_str(def.text).is_not_empty()
	assert_object(pool.crew_of("captain")).is_null()
	assert_bool(pool.has_id("veil")).is_true()
	assert_bool(pool.has_id("captain")).is_false()


## The plan's table (P12, P14): triggers, optional flags and the two limited Crew.
func test_the_shipped_crew_match_the_plans_table() -> void:
	var pool: CrewPool = CrewPool.load_default()
	var rows: Array[Array] = [
		["quartermaster", CrewDef.Trigger.TURN_START, false, 0, CrewDef.Scope.NONE],
		["tallyman", CrewDef.Trigger.ONGOING, false, 0, CrewDef.Scope.NONE],
		["shade", CrewDef.Trigger.TURN_START, true, 0, CrewDef.Scope.NONE],
		["salvager", CrewDef.Trigger.OWN_DESTROYED, true, 1, CrewDef.Scope.ROUND],
		["veil", CrewDef.Trigger.OWN_DESTROYED, true, 1, CrewDef.Scope.MATCH],
		["navigator", CrewDef.Trigger.OWN_MOVED, false, 0, CrewDef.Scope.NONE],
		["gardener", CrewDef.Trigger.ROUND_END, false, 0, CrewDef.Scope.NONE],
		["lookout", CrewDef.Trigger.OWN_RETURNED, false, 0, CrewDef.Scope.NONE],
	]
	for row: Array in rows:
		var crew_id: String = row[0]
		var trigger: int = row[1]
		var optional: bool = row[2]
		var uses: int = row[3]
		var scope: int = row[4]
		var def: CrewDef = pool.crew_of(crew_id)
		assert_object(def).override_failure_message(crew_id).is_not_null()
		if def == null:
			continue
		assert_int(def.trigger).override_failure_message(crew_id).is_equal(trigger)
		assert_bool(def.optional).override_failure_message(crew_id).is_equal(optional)
		assert_int(def.uses).override_failure_message(crew_id).is_equal(uses)
		assert_int(def.scope).override_failure_message(crew_id).is_equal(scope)
	assert_int(pool.crew_of("shade").amount).is_equal(4)
	assert_int(pool.crew_of("quartermaster").amount).is_equal(1)
	assert_int(pool.crew_of("salvager").initial_uses()).is_equal(1)
	assert_int(pool.crew_of("navigator").initial_uses()).is_equal(CrewDef.UNLIMITED)


## A definition writes back the JSON entry it was read from.
func test_a_definition_round_trips_to_its_entry() -> void:
	var pool: CrewPool = _pool_of([_entry()])
	assert_bool(pool.is_valid()).override_failure_message(pool.load_error()).is_true()
	assert_dict(pool.crew_of("shade").to_dict()).is_equal(_entry())
	var whole: CrewPool = _with("amount", 4.0)
	assert_bool(whole.is_valid()).is_true()


# --- Malformed entries (R41) ----------------------------------------------------------


func test_an_unknown_trigger_fails() -> void:
	_assert_invalid(_with("trigger", "on_dawn"), CrewPool.ERR_TRIGGER)


func test_an_unknown_verb_fails() -> void:
	_assert_invalid(_with("verb", "summon"), CrewPool.ERR_VERB)


func test_a_verb_on_another_trigger_fails() -> void:
	_assert_invalid(_with("trigger", "round_end"), CrewPool.ERR_PAIR)


func test_a_non_bool_optional_fails() -> void:
	for bad: Variant in [1, 0, "true", null]:
		_assert_invalid(_with("optional", bad), CrewPool.ERR_OPTIONAL)


func test_a_bad_scope_fails() -> void:
	_assert_invalid(_with("scope", "turn"), CrewPool.ERR_SCOPE)
	_assert_invalid(_with("scope", ""), CrewPool.ERR_SCOPE)
	_assert_invalid(_with("scope", 1), CrewPool.ERR_SHAPE)
	_assert_invalid(_with("scope", null), CrewPool.ERR_SHAPE)


## Uses: whole and >= 0; 0 exactly for scope "none", > 0 for "round" and "match".
func test_bad_uses_fail() -> void:
	_assert_invalid(_with("uses", 1.5), CrewPool.ERR_USES)
	_assert_invalid(_with("uses", "1"), CrewPool.ERR_USES)
	_assert_invalid(_with("uses", 1), CrewPool.ERR_USES)
	var round_none: Dictionary = _entry()
	round_none["scope"] = "round"
	_assert_invalid(_pool_of([round_none]), CrewPool.ERR_USES)
	round_none["uses"] = -1
	_assert_invalid(_pool_of([round_none]), CrewPool.ERR_USES)
	round_none["uses"] = 2
	assert_bool(_pool_of([round_none]).is_valid()).is_true()


func test_malformed_files_fail() -> void:
	_assert_invalid(CrewPool.from_json("not json"), CrewPool.ERR_JSON)
	_assert_invalid(CrewPool.from_json("[1]"), CrewPool.ERR_SHAPE)
	_assert_invalid(CrewPool.from_json('{"crew": []}'), CrewPool.ERR_SHAPE)
	_assert_invalid(CrewPool.from_json('{"version": 2, "crew": []}'), CrewPool.ERR_VERSION)
	_assert_invalid(CrewPool.from_json('{"version": 1}'), CrewPool.ERR_SHAPE)
	_assert_invalid(_pool_of([_entry(), _entry()]), CrewPool.ERR_DUPLICATE)
	_assert_invalid(_pool_of([1]), CrewPool.ERR_SHAPE)
	for key: String in CrewPool.ALL_KEYS:
		var missing: Dictionary = _entry()
		missing.erase(key)
		_assert_invalid(_pool_of([missing]), CrewPool.ERR_SHAPE)
	_assert_invalid(_with("id", ""), CrewPool.ERR_SHAPE)
	_assert_invalid(_with("amount", -1), CrewPool.ERR_SHAPE)
	_assert_invalid(_with("amount", 0.5), CrewPool.ERR_SHAPE)
	_assert_invalid(CrewPool.load_from_path("res://no_such_crew.json"), CrewPool.ERR_FILE)


func test_loading_logs_no_errors() -> void:
	await assert_error(func() -> void: CrewPool.load_default()).is_success()
	await assert_error(func() -> void: CrewPool.from_json("not json")).is_success()
	await (
		assert_error(func() -> void: CrewPool.load_from_path("res://no_such_crew.json"))
		. is_success()
	)
