class_name TestMatchWorkerRecords
extends GdUnitTestSuite
## The bot worker's record shapes (cycle 11 T02, R7-R8, plan P2): every
## field the plan lists is present, the field names are the ones scripts/bot/records.py
## reads (t, points_a, us, rejected, overruns, replay_mismatches, slowest_us, stamp,
## first_won), and a pair's points follow the seat games.

const DECKS: Array[String] = ["ruin", "drift"]


func _keys(record: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key: Variant in record:
		var name: String = key
		out.append(name)
	return out


func test_decision_record_has_every_field() -> void:
	var action: Dictionary = EngineAction.concede(0).to_dict()
	var record: Dictionary = MatchWorkerRecords.decision(7, 2, 3, 4, 1, "random", 14, action, 123)
	assert_array(_keys(record)).contains_exactly(MatchWorkerRecords.DECISION_FIELDS)
	assert_str(record["t"]).is_equal("d")
	assert_int(record["us"]).is_equal(123)
	assert_int(record["legal"]).is_equal(14)
	for field: String in ["level", "previewed", "best", "second", "chosen", "push"]:
		assert_int(record[field]).is_equal(-1)
	assert_int(record["push"]).is_equal(-1)
	assert_dict(record["action"]).is_equal(action)


func test_game_record_has_every_field() -> void:
	var margins: Array[int] = [3, -2]
	var record: Dictionary = MatchWorkerRecords.game(7, 1, 1, DECKS, 1, 5, margins, 0, 88, true)
	assert_array(_keys(record)).contains_exactly(MatchWorkerRecords.GAME_FIELDS)
	assert_str(record["t"]).is_equal("g")
	assert_bool(record["first_won"]).is_false()
	assert_bool(record["replay_ok"]).is_true()


func test_end_record_has_the_fields_records_py_reads() -> void:
	var record: Dictionary = MatchWorkerRecords.end(
		20, 0, 1, 2, 3, 300, 900, "r4-0123456789abcdef", MatchWorkerRecords.WEIGHTS_MATCH
	)
	assert_array(_keys(record)).contains_exactly(MatchWorkerRecords.END_FIELDS)
	assert_str(record["t"]).is_equal("end")
	assert_int(record["rejected"]).is_equal(0)
	assert_int(record["overruns"]).is_equal(3)
	assert_int(record["overruns_a"]).is_equal(1)
	assert_int(record["overruns_b"]).is_equal(2)
	assert_int(record["replay_mismatches"]).is_equal(3)
	assert_int(record["slowest_us"]).is_equal(900)
	assert_str(record["stamp"]).is_equal("r4-0123456789abcdef")
	assert_str(record["weights_stamp"]).is_equal("match")


func test_game_points_win_draw_loss() -> void:
	assert_float(MatchWorkerRecords.game_points(0, 0)).is_equal(1.0)
	assert_float(MatchWorkerRecords.game_points(1, 0)).is_equal(0.0)
	assert_float(MatchWorkerRecords.game_points(1, 1)).is_equal(1.0)
	assert_float(MatchWorkerRecords.game_points(-1, 1)).is_equal(0.5)


func test_pair_points_two_one_and_half() -> void:
	var win_both: float = MatchWorkerRecords.pair_points(
		MatchWorkerRecords.game_points(0, 0), MatchWorkerRecords.game_points(1, 1)
	)
	assert_float(win_both).is_equal(2.0)
	var split: float = MatchWorkerRecords.pair_points(
		MatchWorkerRecords.game_points(0, 0), MatchWorkerRecords.game_points(0, 1)
	)
	assert_float(split).is_equal(1.0)
	var draw_and_loss: float = MatchWorkerRecords.pair_points(
		MatchWorkerRecords.game_points(-1, 0), MatchWorkerRecords.game_points(0, 1)
	)
	assert_float(draw_and_loss).is_equal(0.5)
	var lose_both: float = MatchWorkerRecords.pair_points(0.0, 0.0)
	assert_float(lose_both).is_equal(0.0)


func test_pair_record_and_deck_swapped_seeds_give_two() -> void:
	var swapped: Array[String] = [DECKS[1], DECKS[0]]
	var records: Array[Dictionary] = [
		MatchWorkerRecords.pair(5, DECKS, 1.5), MatchWorkerRecords.pair(5, swapped, 0.5)
	]
	for record: Dictionary in records:
		assert_array(_keys(record)).contains_exactly(MatchWorkerRecords.PAIR_FIELDS)
		assert_str(record["t"]).is_equal("p")
	assert_float(records[0]["points_a"]).is_equal(1.5)
	assert_float(records[1]["points_a"]).is_equal(0.5)


func test_percentile_is_nearest_rank() -> void:
	var values: PackedInt64Array = PackedInt64Array([5, 1, 3, 2, 4])
	assert_int(MatchWorkerRecords.percentile(values, 0.95)).is_equal(5)
	assert_int(MatchWorkerRecords.percentile(values, 0.5)).is_equal(3)
	assert_int(MatchWorkerRecords.percentile(PackedInt64Array(), 0.95)).is_equal(0)
