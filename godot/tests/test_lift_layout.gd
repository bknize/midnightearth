class_name TestLiftLayout
extends GdUnitTestSuite
## LiftLayout (B-11): the reader's action button sits under the lifted card, never over it,
## and stays inside the safe area.

const BASE: float = 0.9
const VIEWS: Array[Vector2] = [
	Vector2(1280.0, 720.0), Vector2(844.0, 390.0), Vector2(390.0, 844.0), Vector2(1024.0, 768.0)
]


func _safe_of(view: Vector2) -> Rect2:
	# A notch and a home bar: some inset on every side.
	return Rect2(Vector2(20.0, 10.0), view - Vector2(40.0, 30.0))


func test_the_button_never_overlaps_the_card_and_stays_inside_the_safe_area() -> void:
	for view: Vector2 in VIEWS:
		var safe: Rect2 = _safe_of(view)
		var fill: float = LiftLayout.fill_for(view, safe, BASE, true)
		var card: Rect2 = LiftLayout.card_rect(view, fill)
		var button: Rect2 = LiftLayout.button_rect(view, safe, fill)
		assert_bool(card.intersects(button)).is_false()
		assert_bool(safe.encloses(button)).is_true()
		assert_float(button.position.y).is_greater_equal(card.end.y)


func test_with_the_whole_view_safe_the_same_holds() -> void:
	for view: Vector2 in VIEWS:
		var safe: Rect2 = Rect2(Vector2.ZERO, view)
		var fill: float = LiftLayout.fill_for(view, safe, BASE, true)
		var card: Rect2 = LiftLayout.card_rect(view, fill)
		var button: Rect2 = LiftLayout.button_rect(view, safe, fill)
		assert_bool(card.intersects(button)).is_false()
		assert_bool(safe.encloses(button)).is_true()


func test_without_a_button_the_card_keeps_its_full_fill() -> void:
	var view: Vector2 = Vector2(1280.0, 720.0)
	assert_float(LiftLayout.fill_for(view, Rect2(Vector2.ZERO, view), BASE, false)).is_equal(BASE)


func test_the_fill_shrinks_only_as_far_as_needed() -> void:
	var view: Vector2 = Vector2(1280.0, 720.0)
	var fill: float = LiftLayout.fill_for(view, Rect2(Vector2.ZERO, view), BASE, true)
	assert_float(fill).is_less(BASE)
	assert_float(fill).is_greater_equal(LiftLayout.MIN_FILL)


func test_the_card_is_centred() -> void:
	var view: Vector2 = Vector2(1280.0, 720.0)
	var card: Rect2 = LiftLayout.card_rect(view, 0.8)
	assert_vector(card.get_center()).is_equal_approx(view / 2.0, Vector2(0.01, 0.01))
	assert_float(card.size.y).is_equal_approx(576.0, 0.01)


func test_safe_rect_takes_the_display_insets_scaled_to_the_view() -> void:
	var safe: Rect2 = LiftLayout.safe_rect(
		Vector2(1000.0, 500.0), Vector2i(2000, 1000), Rect2i(100, 40, 1800, 900)
	)
	assert_float(safe.position.x).is_equal_approx(50.0, 0.01)
	assert_float(safe.position.y).is_equal_approx(20.0, 0.01)
	assert_float(safe.end.x).is_equal_approx(950.0, 0.01)
	assert_float(safe.end.y).is_equal_approx(470.0, 0.01)
	var whole: Rect2 = LiftLayout.safe_rect(Vector2(640.0, 360.0), Vector2i.ZERO, Rect2i())
	assert_float(whole.size.x).is_equal_approx(640.0, 0.01)
