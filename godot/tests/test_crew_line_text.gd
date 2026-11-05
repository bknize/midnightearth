class_name TestCrewLineText
extends GdUnitTestSuite
## CrewLine badge text and the spent look (cycle 8 R60): pure, no nodes.


func test_badge_text_counts_the_uses_left() -> void:
	assert_str(CrewLine.badge_text(2)).is_equal("2 left")
	assert_str(CrewLine.badge_text(1)).is_equal("1 left")
	assert_str(CrewLine.badge_text(0)).is_equal("spent")


func test_an_unlimited_crew_has_no_badge() -> void:
	assert_str(CrewLine.badge_text(-1)).is_equal("")


func test_only_zero_uses_is_spent() -> void:
	assert_bool(CrewLine.is_spent(0)).is_true()
	assert_bool(CrewLine.is_spent(1)).is_false()
	assert_bool(CrewLine.is_spent(-1)).is_false()
