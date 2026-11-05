class_name TestCardMemory
extends GdUnitTestSuite
## CardMemory (cycle 8 DC-09 T01; R2, R6, plan P2): a card instance's memory for the match,
## {flat, times, plus, cost, uses_left}. Its plain form round-trips; it is empty only while
## every delta is 0 and `uses_left` is unread (-1); copies are independent. MatchState keeps
## it by instance id, creating an entry only through memory_for().


func _grown() -> CardMemory:
	var kept: CardMemory = CardMemory.new()
	kept.flat = 2
	kept.times = 50
	kept.plus = 1
	kept.cost = 3
	kept.uses_left = 0
	return kept


func test_defaults_are_empty() -> void:
	var kept: CardMemory = CardMemory.new()
	assert_bool(kept.is_empty()).is_true()
	assert_dict(kept.to_dict()).is_equal(
		{"flat": 0, "times": 0, "plus": 0, "cost": 0, "uses_left": -1}
	)


## Any one field off its default makes the memory not empty, `uses_left` included (P2: an
## entry with uses_left set is not empty).
func test_any_field_makes_it_not_empty() -> void:
	for field: String in ["flat", "times", "plus", "cost"]:
		var kept: CardMemory = CardMemory.new()
		kept.set(field, 1)
		assert_bool(kept.is_empty()).override_failure_message(field).is_false()
	var counted: CardMemory = CardMemory.new()
	counted.uses_left = 0
	assert_bool(counted.is_empty()).is_false()
	var unread: CardMemory = CardMemory.new()
	unread.uses_left = 1
	assert_bool(unread.is_empty()).is_false()


func test_to_dict_from_dict_round_trips() -> void:
	var kept: CardMemory = _grown()
	var plain: Dictionary = kept.to_dict()
	assert_dict(plain).is_equal({"flat": 2, "times": 50, "plus": 1, "cost": 3, "uses_left": 0})
	var back: CardMemory = CardMemory.from_dict(plain)
	assert_dict(back.to_dict()).is_equal(plain)
	# Through JSON, whose numbers come back as floats.
	var parsed: Variant = JSON.parse_string(JSON.stringify(plain))
	assert_bool(parsed is Dictionary).is_true()
	var parsed_dict: Dictionary = parsed
	assert_dict(CardMemory.from_dict(parsed_dict).to_dict()).is_equal(plain)
	# The empty memory round-trips to an empty one.
	var empty: CardMemory = CardMemory.from_dict(CardMemory.new().to_dict())
	assert_bool(empty.is_empty()).is_true()


func test_copy_is_independent() -> void:
	var kept: CardMemory = _grown()
	var other: CardMemory = kept.copy()
	assert_dict(other.to_dict()).is_equal(kept.to_dict())
	other.flat += 1
	other.uses_left = 5
	assert_int(kept.flat).is_equal(2)
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
	made.flat = 1
	var plain: Dictionary = state.to_dict()
	var memory: Dictionary = plain["memory"]
	assert_dict(memory).is_equal({7: made.to_dict()})
	assert_dict(MatchState.new(1).to_dict()["memory"]).is_empty()
