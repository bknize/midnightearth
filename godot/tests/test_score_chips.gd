class_name TestScoreChips
extends GdUnitTestSuite
## ScoreChips (R31, R76, R77, plan P17) and RowTally's text: the walking total as "4.38" or
## "16", the face's Bonus text, and which chips a pulse shows.

const EPSILON: float = 0.0001


func _pulse(power: int, bonus_value: int, scored: bool = true) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.PULSE
	step.seat = 0
	step.power = power
	step.bonus_value = bonus_value
	step.scored = scored
	return step


func test_a_fractional_total_reads_two_decimals_rounded_half_up() -> void:
	assert_str(ScoreChips.total_text(43750)).is_equal("4.38")
	assert_str(ScoreChips.total_text(12500)).is_equal("1.25")
	assert_str(ScoreChips.total_text(10049)).is_equal("1.00")
	assert_str(ScoreChips.total_text(5000)).is_equal("0.50")


func test_a_whole_total_reads_without_decimals() -> void:
	assert_str(ScoreChips.total_text(160000)).is_equal("16")
	assert_str(ScoreChips.total_text(0)).is_equal("0")
	assert_str(ScoreChips.total_text(-20000)).is_equal("-2")


func test_a_negative_fractional_total_keeps_its_sign_and_decimals() -> void:
	assert_str(ScoreChips.total_text(-15000)).is_equal("-1.50")
	assert_str(ScoreChips.total_text(-5000)).is_equal("-0.50")


func test_the_hud_score_is_the_total_rounded_half_up() -> void:
	assert_int(ScoreChips.score_of(43750)).is_equal(4)
	assert_int(ScoreChips.score_of(45000)).is_equal(5)
	assert_int(ScoreChips.score_of(160000)).is_equal(16)
	assert_int(ScoreChips.score_of(-5000)).is_equal(0)


func test_the_row_tally_reads_the_walking_total() -> void:
	assert_str(RowTally.tally_text(43750)).is_equal("4.38")


func test_mult_and_add_texts_use_two_decimals() -> void:
	assert_str(ScoreChips.mult_text(156)).is_equal("×1.56")
	assert_str(ScoreChips.add_text(50)).is_equal("+0.50")
	assert_str(ScoreChips.add_text(100)).is_equal("+1.00")
	assert_str(ScoreChips.add_text(-25)).is_equal("-0.25")


func test_a_pulse_with_a_bonus_shows_the_power_chip_then_the_bonus_chip() -> void:
	assert_array(ScoreChips.chip_texts(_pulse(4, 12500))).is_equal(["+4", "×1.25"])
	assert_array(ScoreChips.chip_texts(_pulse(-2, 20000))).is_equal(["-2", "×2.00"])


func test_a_plain_pulse_shows_only_the_power_chip() -> void:
	assert_array(ScoreChips.chip_texts(_pulse(4, ScoreChips.SCALE))).is_equal(["+4"])


func test_a_pulse_with_no_score_shows_nothing() -> void:
	var step: BoardStep = _pulse(4, 12500, false)
	assert_array(ScoreChips.chip_texts(step)).is_empty()
	assert_float(ScoreChips.chips_time(step)).is_equal_approx(0.0, EPSILON)


func test_chip_time_is_a_quarter_second_per_chip() -> void:
	assert_float(ScoreChips.chips_time(_pulse(4, 12500))).is_equal_approx(0.5, EPSILON)
	assert_float(ScoreChips.chips_time(_pulse(4, ScoreChips.SCALE))).is_equal_approx(0.25, EPSILON)


func test_a_face_reads_its_mult_or_its_add() -> void:
	assert_str(BoardCard.bonus_text(125, 0)).is_equal("×1.25")
	assert_str(BoardCard.bonus_text(0, 50)).is_equal("+0.50")
	assert_str(BoardCard.bonus_text(100, 0)).is_equal("")
	assert_str(BoardCard.bonus_text(0, 0)).is_equal("")
	assert_str(BoardCard.bonus_text(125, 50)).is_equal("×1.25 +0.50")
