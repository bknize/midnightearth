class_name TestResultText
extends GdUnitTestSuite
## BoardHud.reason_text: the end reason as a phrase (R23).


func test_wins() -> void:
	assert_str(BoardHud.reason_text("wins", 0, 5)).is_equal("First to 4 round wins")


func test_rounds() -> void:
	assert_str(BoardHud.reason_text("rounds", 0, 7)).is_equal("Most round wins after 7 rounds")


func test_sudden_death() -> void:
	assert_str(BoardHud.reason_text("sudden_death", 1, 9)).is_equal("Won in sudden death")


## Every stalemate comes after a tied sudden-death Round, whichever condition ended it (C15).
func test_stalemate_with_a_winner() -> void:
	assert_str(BoardHud.reason_text("stalemate", 1, 10)).is_equal(
		"Sudden death deadlocked: higher total Score"
	)


func test_stalemate_drawn() -> void:
	assert_str(BoardHud.reason_text("stalemate", -1, 10)).is_equal(
		"Sudden death deadlocked: total Scores level"
	)


func test_concede_by_you() -> void:
	assert_str(BoardHud.reason_text("concede", 1, 2)).is_equal("You conceded")


func test_concede_by_opponent() -> void:
	assert_str(BoardHud.reason_text("concede", 0, 2)).is_equal("Opponent conceded")


func test_unknown_reason_falls_back_to_raw() -> void:
	assert_str(BoardHud.reason_text("mystery", 0, 1)).is_equal("mystery")
