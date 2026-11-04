class_name TestScoreChips
extends GdUnitTestSuite
## ScoreChips (R31, R28, R36, plan P12) and RowTally's text: which chips a pulse shows, and how
## long the pulse step lasts because of them.

const EPSILON: float = 0.0001


func _pulse(times: int, plus: int, mult: int, added: int, destroyed: bool = false) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.PULSE
	step.seat = 0
	step.times = times
	step.plus = plus
	step.mult = mult
	step.added = added
	step.score = 5
	step.destroyed = destroyed
	return step


func test_a_times_card_shows_the_mult_chip_then_the_added_chip() -> void:
	var texts: Array[String] = ScoreChips.chip_texts(_pulse(125, 0, 125, 9))
	assert_array(texts).is_equal(["×1.25", "+9"])


func test_a_plus_card_shows_the_mult_chip_then_the_added_chip() -> void:
	var texts: Array[String] = ScoreChips.chip_texts(_pulse(100, 1, 200, 8))
	assert_array(texts).is_equal(["×2.00", "+8"])


func test_the_chip_text_for_156_is_one_fifty_six() -> void:
	assert_str(ScoreChips.mult_text(156)).is_equal("×1.56")
	var texts: Array[String] = ScoreChips.chip_texts(_pulse(156, 0, 156, 3))
	assert_str(texts[0]).is_equal("×1.56")


func test_a_vanilla_card_shows_only_the_added_chip() -> void:
	var texts: Array[String] = ScoreChips.chip_texts(_pulse(100, 0, 100, 4))
	assert_array(texts).is_equal(["+4"])


func test_a_zero_add_still_shows() -> void:
	var texts: Array[String] = ScoreChips.chip_texts(_pulse(100, 0, 100, 0))
	assert_array(texts).is_equal(["+0"])


func test_a_destroyed_pulse_shows_nothing() -> void:
	var step: BoardStep = _pulse(200, 0, 200, 9, true)
	assert_array(ScoreChips.chip_texts(step)).is_empty()
	assert_float(ScoreChips.chips_time(step)).is_equal_approx(0.0, EPSILON)


func test_a_pulse_with_no_score_shows_nothing() -> void:
	var step: BoardStep = _pulse(100, 0, 100, 0)
	step.score = -1
	assert_array(ScoreChips.chip_texts(step)).is_empty()


func test_chip_time_is_a_quarter_second_per_chip() -> void:
	assert_float(ScoreChips.chips_time(_pulse(200, 0, 200, 9))).is_equal_approx(0.5, EPSILON)
	assert_float(ScoreChips.chips_time(_pulse(100, 0, 100, 9))).is_equal_approx(0.25, EPSILON)


func test_tally_text_is_score_and_mult_to_two_decimals() -> void:
	assert_str(RowTally.tally_text(12, 300)).is_equal("12 ×3.00")
	assert_str(RowTally.tally_text(12, 125)).is_equal("12 ×1.25")


func test_bonus_text_for_a_card_face() -> void:
	assert_str(BoardCard.bonus_text(125, 0)).is_equal("×1.25")
	assert_str(BoardCard.bonus_text(100, 1)).is_equal("+1")
	assert_str(BoardCard.bonus_text(100, 0)).is_equal("")
