class_name TestBoardCardDestroyed
extends GdUnitTestSuite
## BoardCard destroyed look (R26, plan P8): the pure tilt rule.


func test_tilt_is_about_nine_by_four_degrees() -> void:
	var tilt: Vector3 = BoardCard.tilt_for_slot(0)
	assert_float(absf(rad_to_deg(tilt.z))).is_equal_approx(9.0, 0.001)
	assert_float(absf(rad_to_deg(tilt.x))).is_equal_approx(4.0, 0.001)
	assert_float(tilt.y).is_equal(0.0)


func test_neighbours_tilt_opposite_ways() -> void:
	var even: Vector3 = BoardCard.tilt_for_slot(2)
	var odd: Vector3 = BoardCard.tilt_for_slot(3)
	assert_float(even.z * odd.z).is_less(0.0)
	assert_float(even.x * odd.x).is_less(0.0)


func test_same_parity_tilts_match() -> void:
	assert_vector(BoardCard.tilt_for_slot(1)).is_equal(BoardCard.tilt_for_slot(3))
