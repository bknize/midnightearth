class_name TestSeatViewDict
extends FullMatchHarness
## SeatView.from_dict() (cycle 12 plan P3, T01): every view of both seats over the whole
## seed-1 match survives to_dict() -> from_dict() -> to_dict(), directly and through JSON
## text (numbers as floats, `looked` keys as text), and every malformed shape reads as null.

const SEED: int = 1
# Two forms compare as PvpTable.sorted_json() text, key order aside.


## The seed-1 start view of seat 0, as to_dict() gives it: the base of the malformed cases.
func _base() -> Dictionary:
	var engine: MatchEngine = _new_engine(SEED)
	var result: ApplyResult = engine.start()
	assert_bool(result.ok).is_true()
	return engine.view_for(0).to_dict()


## `base` with `key` set to `value`.
func _with(base: Dictionary, key: String, value: Variant) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	out[key] = value
	return out


func _assert_null(d: Dictionary, what: String) -> void:
	var view: SeatView = SeatView.from_dict(d)
	assert_object(view).override_failure_message("not null: " + what).is_null()


# --- Round trips ------------------------------------------------------------------------


func test_every_seed_1_view_round_trips() -> void:
	var played: PlayedSteps = _played_steps(SEED)
	assert_bool(played.over).is_true()
	assert_int(played.views.size()).is_equal((played.actions + 1) * MatchEngine.SEATS)
	var problems: Array[String] = []
	for at: int in range(played.views.size()):
		var dict: Dictionary = played.views[at].to_dict()
		var back: SeatView = SeatView.from_dict(dict)
		if back == null:
			problems.append("view %d: from_dict gave null" % at)
			continue
		if PvpTable.sorted_json(back.to_dict()) != PvpTable.sorted_json(dict):
			problems.append("view %d: round trip differs" % at)
	_assert_none(problems, "seed 1 views")


func test_every_seed_1_view_round_trips_through_json() -> void:
	var played: PlayedSteps = _played_steps(SEED)
	assert_bool(played.over).is_true()
	var problems: Array[String] = []
	for at: int in range(played.views.size()):
		var dict: Dictionary = played.views[at].to_dict()
		var parsed: Variant = JSON.parse_string(JSON.stringify(dict))
		if not parsed is Dictionary:
			problems.append("view %d: JSON did not parse" % at)
			continue
		var json_dict: Dictionary = parsed
		var back: SeatView = SeatView.from_dict(json_dict)
		if back == null:
			problems.append("view %d: from_dict gave null" % at)
			continue
		if PvpTable.sorted_json(back.to_dict()) != PvpTable.sorted_json(dict):
			problems.append("view %d: JSON round trip differs" % at)
	_assert_none(problems, "seed 1 views through JSON")


func test_rebuilt_view_has_typed_fields() -> void:
	var dict: Dictionary = _base()
	var parsed: Variant = JSON.parse_string(JSON.stringify(dict))
	assert_bool(parsed is Dictionary).is_true()
	if not parsed is Dictionary:
		return
	var json_dict: Dictionary = parsed
	var view: SeatView = SeatView.from_dict(json_dict)
	assert_object(view).is_not_null()
	if view == null:
		return
	assert_int(view.seat).is_equal(0)
	assert_int(view.opponent).is_equal(1)
	assert_int(typeof(view.own_hand[0])).is_equal(TYPE_INT)
	assert_int(view.own_hand.get_typed_builtin()).is_equal(TYPE_INT)
	assert_int(view.deck_ids.get_typed_builtin()).is_equal(TYPE_STRING)
	assert_int(typeof(view.totals[1])).is_equal(TYPE_INT)


func test_looked_and_pile_entries_rebuild_by_key() -> void:
	var dict: Dictionary = _base()
	dict["looked"] = {"2": 40.0, 0: 41}
	dict["pile_entries"] = [{"card": 7.0, "power": 3.0}, {"card": 3, "power": 1}]
	var view: SeatView = SeatView.from_dict(dict)
	assert_object(view).is_not_null()
	if view == null:
		return
	assert_int(view.looked[2]).is_equal(40)
	assert_int(view.looked[0]).is_equal(41)
	assert_int(view.pile_entries.size()).is_equal(2)
	var entry: Dictionary = view.pile_entries[7]
	assert_int(typeof(entry["power"])).is_equal(TYPE_INT)
	var other: Dictionary = view.pile_entries[3]
	var power: int = other["power"]
	assert_int(power).is_equal(1)


# --- Malformed shapes -------------------------------------------------------------------


func test_null_on_each_missing_key() -> void:
	var base: Dictionary = _base()
	assert_object(SeatView.from_dict(base)).is_not_null()
	for key: Variant in base.keys():
		var cut: Dictionary = base.duplicate(true)
		cut.erase(key)
		_assert_null(cut, "missing %s" % key)


func test_null_on_an_empty_dictionary() -> void:
	_assert_null({}, "empty")


func test_null_on_bad_seats() -> void:
	var base: Dictionary = _base()
	_assert_null(_with(base, "seat", 2), "seat 2")
	_assert_null(_with(base, "seat", -1), "seat -1")
	_assert_null(_with(base, "seat", "0"), "seat as text")
	_assert_null(_with(base, "seat", 0.5), "seat 0.5")
	_assert_null(_with(base, "opponent", 0), "opponent is the seat")
	_assert_null(_with(base, "awaited_seat", 2), "awaited 2")
	_assert_null(_with(base, "awaited_seat", -2), "awaited -2")
	_assert_null(_with(base, "first_seat", -1), "first seat -1")


func test_null_on_bad_enums_and_counts() -> void:
	var base: Dictionary = _base()
	_assert_null(_with(base, "phase", MatchState.Phase.size()), "phase past the enum")
	_assert_null(_with(base, "phase", -1), "phase -1")
	_assert_null(_with(base, "phase", "OVER"), "phase as text")
	_assert_null(_with(base, "opponent_hand_count", -1), "negative hand count")
	_assert_null(_with(base, "opponent_pending_count", -3), "negative pending count")
	_assert_null(_with(base, "round", -1), "negative round")
	_assert_null(_with(base, "turn", 1.5), "fractional turn")
	_assert_null(_with(base, "energy", null), "null energy")


func test_null_on_bad_lists() -> void:
	var base: Dictionary = _base()
	_assert_null(_with(base, "own_hand", "1,2"), "hand as text")
	_assert_null(_with(base, "own_hand", [1, 2.5]), "fractional card id")
	_assert_null(_with(base, "own_board", [1, "x"]), "text in a row")
	_assert_null(_with(base, "deck_top", {}), "deck top as a dictionary")
	_assert_null(_with(base, "deck_ids", ["greed"]), "one deck id")
	_assert_null(_with(base, "deck_ids", ["greed", 3]), "a deck id not text")
	_assert_null(_with(base, "deck_counts", [1, 2, 3]), "three deck counts")
	_assert_null(_with(base, "scores", [0]), "one score")
	_assert_null(_with(base, "totals", [0, "1"]), "a total as text")
	_assert_null(_with(base, "budgets", []), "no budgets")
	_assert_null(_with(base, "hand_sizes", null), "null hand sizes")


func test_null_on_bad_entries() -> void:
	var base: Dictionary = _base()
	_assert_null(_with(base, "own_row", [5]), "row entry not a dictionary")
	_assert_null(_with(base, "opponent_row", [{"power": 1}]), "row entry without card")
	_assert_null(_with(base, "own_hand_row", [{"card": "3"}]), "hand entry card as text")
	_assert_null(_with(base, "pile_entries", [{"power": 1}]), "pile entry without card")
	var twice: Array = [{"card": 4}, {"card": 4.0}]
	_assert_null(_with(base, "pile_entries", twice), "pile entry twice")
	_assert_null(_with(base, "pile_entries", {}), "pile entries as a dictionary")


func test_null_on_bad_maps_and_flags() -> void:
	var base: Dictionary = _base()
	_assert_null(_with(base, "looked", []), "looked as a list")
	_assert_null(_with(base, "looked", {"x": 3}), "looked key not a number")
	_assert_null(_with(base, "looked", {1: "3"}), "looked card as text")
	_assert_null(_with(base, "looked", {1.5: 3}), "fractional looked slot")
	_assert_null(_with(base, "prompt", []), "prompt as a list")
	_assert_null(_with(base, "free_first", 1), "free first as a number")
	_assert_null(_with(base, "sudden_death", "false"), "sudden death as text")


func test_null_on_bad_crew() -> void:
	var base: Dictionary = _base()
	_assert_null(_with(base, "crew", [[]]), "one seat's crew")
	_assert_null(_with(base, "crew", [[], 3]), "a crew not a list")
	_assert_null(_with(base, "crew", [["a"], [4]]), "a crew id not text")
	_assert_null(_with(base, "crew_uses", [[1], [1], [1]]), "three seats' uses")
	_assert_null(_with(base, "crew_uses", [[1], ["1"]]), "a use as text")
	_assert_null(_with(base, "crew_uses", "none"), "uses as text")
