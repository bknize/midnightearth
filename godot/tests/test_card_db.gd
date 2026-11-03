class_name TestCardDb
extends GdUnitTestSuite
## CardDb and CardDef: R7 (load from JSON), R8 (validation), R10 (the plan's power table).

## The plan's card table (C6), in file order c01..c20.
const COSTS: Array[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 7]
const POWERS: Array[int] = [1, 2, 2, 3, 2, 3, 3, 4, 3, 4, 5, 4, 5, 6, 5, 7, 6, 8, 7, 9]


func _table() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(COSTS.size()):
		(
			out
			. append(
				{
					"id": "c%02d" % (i + 1),
					"name": "Placeholder %02d" % (i + 1),
					"cost": COSTS[i],
					"power": POWERS[i],
				}
			)
		)
	return out


func _json(cards: Array[Dictionary], version: int = 1) -> String:
	return JSON.stringify({"version": version, "cards": cards})


func _assert_fails_with(text: String, prefix: String) -> void:
	var db: CardDb = CardDb.from_json(text)
	assert_bool(db.is_valid()).is_false()
	assert_str(db.load_error()).starts_with(prefix)
	assert_int(db.size()).is_equal(0)
	assert_object(db.card_at(0)).is_null()


# --- R7, R10: the default file -------------------------------------------------------


func test_default_file_loads_valid() -> void:
	var db: CardDb = CardDb.load_default()
	assert_bool(db.is_valid()).is_true()
	assert_str(db.load_error()).is_empty()
	assert_int(db.size()).is_equal(CardDb.CARD_COUNT)


func test_default_file_matches_plan_table() -> void:
	var db: CardDb = CardDb.load_default()
	var total_cost: int = 0
	var total_power: int = 0
	for i: int in range(COSTS.size()):
		var def: CardDef = db.card_at(i)
		assert_object(def).is_not_null()
		assert_str(def.id).is_equal("c%02d" % (i + 1))
		assert_str(def.name).is_equal("Placeholder %02d" % (i + 1))
		assert_int(def.cost).is_equal(COSTS[i])
		assert_int(def.power).is_equal(POWERS[i])
		total_cost += def.cost
		total_power += def.power
	assert_int(total_cost).is_equal(69)
	assert_int(total_power).is_equal(89)


func test_default_file_cost_mix() -> void:
	var db: CardDb = CardDb.load_default()
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	for def: CardDef in db.cards():
		counts[def.cost] += 1
	var expected: Array[int] = [0, 4, 4, 3, 3, 2, 2, 2]
	assert_array(counts).is_equal(expected)


func test_lookup_by_index_and_id() -> void:
	var db: CardDb = CardDb.load_default()
	assert_int(db.index_of("c11")).is_equal(10)
	assert_int(db.card_by_id("c11").power).is_equal(5)
	assert_str(db.card_at(19).id).is_equal("c20")
	assert_int(db.card_by_id("c20").cost).is_equal(7)
	assert_int(db.index_of("c99")).is_equal(-1)
	assert_object(db.card_by_id("c99")).is_null()
	assert_object(db.card_at(-1)).is_null()
	assert_object(db.card_at(20)).is_null()
	# cards() hands out a copy.
	var copy: Array[CardDef] = db.cards()
	copy.clear()
	assert_int(db.size()).is_equal(20)


func test_in_memory_table_loads_valid() -> void:
	var db: CardDb = CardDb.from_json(_json(_table()))
	assert_bool(db.is_valid()).is_true()
	assert_str(db.load_error()).is_empty()
	assert_int(db.size()).is_equal(20)


# --- R8: each validation failure -----------------------------------------------------


func test_wrong_count_fails() -> void:
	var too_few: Array[Dictionary] = _table()
	too_few.remove_at(19)
	_assert_fails_with(_json(too_few), CardDb.ERR_COUNT)

	var too_many: Array[Dictionary] = _table()
	var extra: Dictionary = too_many[0].duplicate()
	extra["id"] = "c21"
	too_many.append(extra)
	_assert_fails_with(_json(too_many), CardDb.ERR_COUNT)

	var none: Array[Dictionary] = []
	_assert_fails_with(_json(none), CardDb.ERR_COUNT)


func test_wrong_cost_mix_fails() -> void:
	# c20 becomes a cost-1 card with a legal power: five 1s and one 7.
	var shifted: Array[Dictionary] = _table()
	shifted[19]["cost"] = 1
	shifted[19]["power"] = 2
	_assert_fails_with(_json(shifted), CardDb.ERR_COST_MIX)

	# A cost outside 1..7, with a power inside its own range.
	var out_of_range: Array[Dictionary] = _table()
	out_of_range[19]["cost"] = 8
	out_of_range[19]["power"] = 9
	_assert_fails_with(_json(out_of_range), CardDb.ERR_COST_MIX)


func test_duplicate_id_fails() -> void:
	var cards: Array[Dictionary] = _table()
	cards[1]["id"] = "c01"
	_assert_fails_with(_json(cards), CardDb.ERR_DUPLICATE)


func test_power_out_of_range_fails() -> void:
	var above: Array[Dictionary] = _table()
	above[0]["power"] = 4  # cost 1 allows 1..3
	_assert_fails_with(_json(above), CardDb.ERR_POWER)

	var below: Array[Dictionary] = _table()
	below[19]["power"] = 6  # cost 7 allows 7..9
	_assert_fails_with(_json(below), CardDb.ERR_POWER)

	# Both edges are legal: c01 (cost 1) raised to 3, c19 (cost 7) left at 7.
	var edges: Array[Dictionary] = _table()
	edges[0]["power"] = 3
	assert_bool(CardDb.from_json(_json(edges)).is_valid()).is_true()


func test_bad_json_fails() -> void:
	_assert_fails_with('{"version": 1, "cards": [', CardDb.ERR_JSON)
	_assert_fails_with("not json at all", CardDb.ERR_JSON)
	_assert_fails_with("", CardDb.ERR_JSON)


func test_wrong_top_level_shape_fails() -> void:
	_assert_fails_with("[1, 2, 3]", CardDb.ERR_SHAPE)
	_assert_fails_with('{"version": 1}', CardDb.ERR_SHAPE)
	_assert_fails_with('{"cards": []}', CardDb.ERR_SHAPE)
	_assert_fails_with('{"version": 1, "cards": {}}', CardDb.ERR_SHAPE)


func test_bad_card_entry_fails() -> void:
	var missing_power: Array[Dictionary] = _table()
	missing_power[3].erase("power")
	_assert_fails_with(_json(missing_power), CardDb.ERR_SHAPE)

	var string_cost: Array[Dictionary] = _table()
	string_cost[3]["cost"] = "1"
	_assert_fails_with(_json(string_cost), CardDb.ERR_SHAPE)

	var fractional_power: Array[Dictionary] = _table()
	fractional_power[3]["power"] = 2.5
	_assert_fails_with(_json(fractional_power), CardDb.ERR_SHAPE)

	var empty_id: Array[Dictionary] = _table()
	empty_id[3]["id"] = ""
	_assert_fails_with(_json(empty_id), CardDb.ERR_SHAPE)

	_assert_fails_with('{"version": 1, "cards": [7]}', CardDb.ERR_SHAPE)


func test_unsupported_version_fails() -> void:
	_assert_fails_with(_json(_table(), 2), CardDb.ERR_VERSION)


func test_missing_file_fails() -> void:
	var db: CardDb = CardDb.load_from_path("res://engine/data/no_such_file.json")
	assert_bool(db.is_valid()).is_false()
	assert_str(db.load_error()).starts_with(CardDb.ERR_FILE)
	assert_int(db.size()).is_equal(0)


# --- Silent failure: nothing printed, pushed or asserted ------------------------------


func test_failures_log_no_errors() -> void:
	var too_few: Array[Dictionary] = _table()
	too_few.remove_at(0)
	var dup_ids: Array[Dictionary] = _table()
	dup_ids[1]["id"] = "c01"
	var texts: Array[String] = [
		'{"version": 1, "cards": [',
		"",
		"[1, 2, 3]",
		_json(too_few),
		_json(dup_ids),
		_json(_table(), 2),
	]
	for text: String in texts:
		await assert_error(func() -> void: CardDb.from_json(text)).is_success()
	await (
		assert_error(func() -> void: CardDb.load_from_path("res://engine/data/no_such_file.json"))
		. is_success()
	)


func test_default_load_logs_no_errors() -> void:
	await assert_error(func() -> void: CardDb.load_default()).is_success()
