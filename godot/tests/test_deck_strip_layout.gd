class_name TestDeckStripLayout
extends GdUnitTestSuite
## NSC-163: the Pile strip's world rectangle clears both rows, both Crew lines and the HUD's
## top-right buttons at 1280 x 720 and on narrower aspects.

const ROW_SIZE: Vector2 = Vector2(26.0, 4.0)
const CREW_SIZE: Vector2 = Vector2(8.5, 3.5)
const WIDE: float = 1280.0 / 720.0
const NARROW: float = 4.0 / 3.0
const SQUARE: float = 1.0


func _centered(center: Vector3, size: Vector2) -> Rect2:
	return Rect2(center.x - size.x / 2.0, center.y - size.y / 2.0, size.x, size.y)


func _obstacles() -> Array[Rect2]:
	return [
		_centered(Vector3(0.0, -3.0, 0.0), ROW_SIZE),
		_centered(Vector3(0.0, 3.0, 0.0), ROW_SIZE),
		_centered(CrewLine.ORIGINS[0], CREW_SIZE),
		_centered(CrewLine.ORIGINS[1], CREW_SIZE),
	]


func test_the_strip_overlaps_no_row_or_crew_line() -> void:
	for ratio: float in [WIDE, NARROW, SQUARE]:
		var area: Rect2 = DeckStrip.rect_for(ratio)
		for blocked: Rect2 in _obstacles():
			assert_bool(area.intersects(blocked)).is_false()


func test_the_strip_stays_clear_of_the_hud_edge_and_is_wide_enough_to_read() -> void:
	for ratio: float in [WIDE, NARROW, SQUARE]:
		var area: Rect2 = DeckStrip.rect_for(ratio)
		var half_width: float = ratio * DeckStrip.VIEW_HALF_HEIGHT
		assert_float(area.end.x).is_less_equal(half_width - DeckStrip.HUD_MARGIN + 0.001)
		assert_float(area.size.x).is_greater_equal(DeckStrip.MIN_WIDTH)
