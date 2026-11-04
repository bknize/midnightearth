class_name TestScoreChips
extends GdUnitTestSuite
## ScoreChips (R31, R28, R36, plan P12) and RowTally's text: which chips a pulse shows, and how
## long the pulse step lasts because of them.

const EPSILON: float = 0.0001


func _pulse(bonus: int, mult: int, added: int, destroyed: bool = false) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.PULSE
	step.seat = 0
	step.bonus = bonus
	step.mult = mult
	step.added = added
	step.score = 5
	step.destroyed = destroyed
	return step


func test_a_bonus_card_shows_the_mult_chip_then_the_added_chip() -> void:
	var texts: Array[String] = ScoreChips.chip_texts(_pulse(2, 3, 9))
	assert_array(texts).is_equal(["×3", "+9"])


func test_a_bonus_zero_card_shows_only_the_added_chip() -> void:
	var texts: Array[String] = ScoreChips.chip_texts(_pulse(0, 1, 4))
	assert_array(texts).is_equal(["+4"])


func test_a_zero_add_still_shows() -> void:
	var texts: Array[String] = ScoreChips.chip_texts(_pulse(0, 1, 0))
	assert_array(texts).is_equal(["+0"])


func test_a_destroyed_pulse_shows_nothing() -> void:
	var step: BoardStep = _pulse(2, 3, 9, true)
	assert_array(ScoreChips.chip_texts(step)).is_empty()
	assert_float(ScoreChips.chips_time(step)).is_equal_approx(0.0, EPSILON)


func test_a_pulse_with_no_score_shows_nothing() -> void:
	var step: BoardStep = _pulse(0, 1, 0)
	step.score = -1
	assert_array(ScoreChips.chip_texts(step)).is_empty()


func test_chip_time_is_a_quarter_second_per_chip() -> void:
	assert_float(ScoreChips.chips_time(_pulse(2, 3, 9))).is_equal_approx(0.5, EPSILON)
	assert_float(ScoreChips.chips_time(_pulse(0, 1, 9))).is_equal_approx(0.25, EPSILON)


func test_tally_text_is_score_and_mult() -> void:
	assert_str(RowTally.tally_text(12, 3)).is_equal("12 ×3")
