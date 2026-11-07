class_name TestCardMemory
extends GdUnitTestSuite
## CardMemory (cycle 9 plan P8; DC-13 T03): a card instance's Memory for the match,
## {power, mult_add_steps, mult_times_steps, mult_cap, add_steps, cost_delta, uses_left,
## permanent_statuses} (the last from DC-13 T04).
## Its plain form round-trips; it is empty only while every growth is 0 or empty and
## `uses_left` is unread (-1); copies are independent. MatchState keeps it by instance id,
## creating an entry only through memory_for(). Scoring reads it (test_scoring.gd).


func _grown() -> CardMemory:
	var kept: CardMemory = CardMemory.new()
	kept.power = 2
	kept.mult_add_steps = 25
	kept.mult_times_steps.assign([120])
	kept.mult_cap = 250
	kept.add_steps = 50
	kept.cost_delta = -1
	kept.uses_left = 0
	return kept


func test_defaults_are_empty() -> void:
	var kept: CardMemory = CardMemory.new()
	assert_bool(kept.is_empty()).is_true()
	assert_bool(kept.grows_mult()).is_false()
	assert_dict(kept.to_dict()).is_equal(
		{
			"power": 0,
			"mult_add_steps": 0,
			"mult_times_steps": [],
			"mult_cap": 0,
			"add_steps": 0,
			"cost_delta": 0,
			"uses_left": -1,
			"permanent_statuses": [],
		}
	)


## Any one field off its default makes the Memory not empty, `uses_left` included.
func test_any_field_makes_it_not_empty() -> void:
	for field: String in ["power", "mult_add_steps", "mult_cap", "add_steps", "cost_delta"]:
		var kept: CardMemory = CardMemory.new()
		kept.set(field, 1)
		assert_bool(kept.is_empty()).override_failure_message(field).is_false()
	var stepped: CardMemory = CardMemory.new()
	stepped.mult_times_steps.append(120)
	assert_bool(stepped.is_empty()).is_false()
	assert_bool(stepped.grows_mult()).is_true()
	var counted: CardMemory = CardMemory.new()
	counted.uses_left = 0
	assert_bool(counted.is_empty()).is_false()


func test_to_dict_is_plain_data() -> void:
	var kept: CardMemory = _grown()
	var plain: Dictionary = kept.to_dict()
	assert_dict(plain).is_equal(
		{
			"power": 2,
			"mult_add_steps": 25,
			"mult_times_steps": [120],
			"mult_cap": 250,
			"add_steps": 50,
			"cost_delta": -1,
			"uses_left": 0,
			"permanent_statuses": [],
		}
	)
	plain["power"] = 9
	var steps: Array = plain["mult_times_steps"]
	steps.append(150)
	assert_int(kept.power).is_equal(2)
	assert_int(kept.mult_times_steps.size()).is_equal(1)


func test_copy_is_independent() -> void:
	var kept: CardMemory = _grown()
	var other: CardMemory = kept.copy()
	assert_dict(other.to_dict()).is_equal(kept.to_dict())
	other.power += 1
	other.mult_times_steps.append(150)
	other.uses_left = 5
	assert_int(kept.power).is_equal(2)
	assert_int(kept.mult_times_steps.size()).is_equal(1)
	assert_int(kept.uses_left).is_equal(0)


## MatchState: memory_of() never creates an entry, memory_for() creates one at its defaults,
## and the entry is in to_dict() under "memory" by instance id.
func test_match_state_memory_for_and_memory_of() -> void:
	var state: MatchState = MatchState.new(1)
	assert_object(state.memory_of(7)).is_null()
	assert_bool(state.memory.has(7)).is_false()
	var made: CardMemory = state.memory_for(7)
	assert_bool(made.is_empty()).is_true()
	assert_object(state.memory_of(7)).is_same(made)
	assert_object(state.memory_for(7)).is_same(made)
	made.power = 1
	var plain: Dictionary = state.to_dict()
	var memory: Dictionary = plain["memory"]
	assert_dict(memory).is_equal({7: made.to_dict()})
	assert_dict(MatchState.new(1).to_dict()["memory"]).is_empty()
