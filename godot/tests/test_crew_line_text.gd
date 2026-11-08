class_name TestCrewLineText
extends GdUnitTestSuite
## CrewLine badge text and the spent look (cycle 8 R60): pure, no nodes.


func test_badge_text_counts_the_uses_left() -> void:
	assert_str(CrewLine.badge_text(2)).is_equal("2 left")
	assert_str(CrewLine.badge_text(1)).is_equal("1 left")
	assert_str(CrewLine.badge_text(0)).is_equal("spent")


func test_an_unlimited_crew_has_no_badge() -> void:
	assert_str(CrewLine.badge_text(-1)).is_equal("")


## The joiner (engine seat 1) sees its own Crew on its own line (table seat 0) and the host's
## on the far line (NSC-226 S2).
func test_a_seat_one_player_reads_its_own_crew_on_its_own_line() -> void:
	var per_seat: Array[Array] = [["host_a", "host_b"], ["join_a"]]
	assert_array(CrewLine.seat_entries(per_seat, 0, 1)).is_equal(["join_a"])
	assert_array(CrewLine.seat_entries(per_seat, 1, 1)).is_equal(["host_a", "host_b"])
	assert_array(CrewLine.seat_entries(per_seat, 0, 0)).is_equal(["host_a", "host_b"])
	var uses: Array[Array] = [[2, 0], [1]]
	assert_array(CrewLine.seat_entries(uses, 0, 1)).is_equal([1])
	var none: Array[Array] = []
	assert_array(CrewLine.seat_entries(none, 0, 1)).is_empty()


func test_only_zero_uses_is_spent() -> void:
	assert_bool(CrewLine.is_spent(0)).is_true()
	assert_bool(CrewLine.is_spent(1)).is_false()
	assert_bool(CrewLine.is_spent(-1)).is_false()
