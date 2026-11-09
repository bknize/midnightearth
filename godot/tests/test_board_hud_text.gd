class_name TestBoardHudText
extends GdUnitTestSuite
## BoardHud's PVP text and variants (cycle 12 P7, R25 to R28, R44 to R49): the waiting line, the
## opponent's name, the connection overlay, the pause menu without Decks, and the result panel
## with Leave only, including "Match abandoned".

const HUD_SCENE: PackedScene = preload("res://board/board_hud.tscn")


func _hud() -> BoardHud:
	var hud: BoardHud = HUD_SCENE.instantiate() as BoardHud
	auto_free(hud)
	add_child(hud)
	return hud


func test_the_waiting_line_names_the_opponent_and_clears() -> void:
	var hud: BoardHud = _hud()
	assert_str(hud.waiting_label_text()).is_empty()
	hud.set_waiting("Ana")
	assert_str(hud.waiting_label_text()).is_equal("Waiting for Ana…")
	hud.set_waiting("")
	assert_str(hud.waiting_label_text()).is_empty()


func test_the_opponent_name_replaces_the_default_and_restores_it() -> void:
	var hud: BoardHud = _hud()
	assert_str(hud.opponent_label_text()).is_equal("Opponent")
	hud.set_opponent_name("Ana")
	assert_str(hud.opponent_label_text()).is_equal("Ana")
	hud.set_opponent_name("")
	assert_str(hud.opponent_label_text()).is_equal("Opponent")


func test_the_result_wins_line_uses_the_opponent_name() -> void:
	var hud: BoardHud = _hud()
	hud.set_opponent_name("Ana")
	var wins: Array[int] = [4, 2]
	hud.show_result(0, wins, "wins", 6, true)
	var texts: Array[String] = hud.result_texts()
	assert_str(texts[0]).is_equal("You win")
	assert_str(texts[1]).is_equal("Rounds won: You 4 - 2 Ana")
	assert_str(texts[2]).is_equal("First to 4 round wins")


func test_the_connection_overlay_texts() -> void:
	assert_str(BoardHud.connection_text(MatchSource.STATE_RECONNECTING, "")).is_equal(
		"Reconnecting…"
	)
	assert_str(BoardHud.connection_text(MatchSource.STATE_OPPONENT_LOST, "Ana")).is_equal(
		"Connection with Ana lost; waiting up to 2 minutes"
	)
	assert_str(BoardHud.connection_text(MatchSource.STATE_OPPONENT_BACK, "Ana")).is_equal(
		"Ana is back"
	)
	assert_str(BoardHud.connection_text(MatchSource.STATE_RESTORED, "")).is_empty()


func test_the_connection_overlay_shows_and_hides() -> void:
	var hud: BoardHud = _hud()
	hud.show_connection(MatchSource.STATE_OPPONENT_LOST, "Ana")
	assert_str(hud.connection_label_text()).is_equal(
		"Connection with Ana lost; waiting up to 2 minutes"
	)
	hud.show_connection(MatchSource.STATE_RESTORED, "")
	assert_str(hud.connection_label_text()).is_empty()


func test_the_local_pause_menu_offers_decks_and_the_pvp_one_offers_leave() -> void:
	var hud: BoardHud = _hud()
	hud.show_pause(true)
	assert_bool(hud.pause_decks_visible()).is_true()
	assert_bool(hud.pause_leave_visible()).is_false()
	hud.show_pause(true, true)
	assert_bool(hud.pause_decks_visible()).is_false()
	assert_bool(hud.pause_leave_visible()).is_true()


func test_a_local_result_offers_rematch_and_a_pvp_result_offers_leave_only() -> void:
	var hud: BoardHud = _hud()
	var wins: Array[int] = [1, 4]
	hud.show_result(1, wins, "wins", 5)
	assert_bool(hud.result_rematch_visible()).is_true()
	assert_bool(hud.result_leave_visible()).is_false()
	hud.show_result(1, wins, "wins", 5, true)
	assert_bool(hud.result_rematch_visible()).is_false()
	assert_bool(hud.result_leave_visible()).is_true()
	assert_str(hud.result_texts()[0]).is_equal("Opponent wins")


func test_an_abandoned_match_reads_match_abandoned_with_leave() -> void:
	var hud: BoardHud = _hud()
	hud.set_opponent_name("Ana")
	hud.show_abandoned()
	var texts: Array[String] = hud.result_texts()
	assert_str(texts[0]).is_equal("Match abandoned")
	assert_str(texts[2]).is_equal("Ana left; the match is abandoned")
	assert_bool(hud.result_leave_visible()).is_true()
	assert_bool(hud.result_rematch_visible()).is_false()


func test_a_deck_note_survives_a_pile_update_and_the_count_still_changes() -> void:
	var hud: BoardHud = _hud()
	var counts: Array[int] = [2, 0]
	hud.set_piles(counts)
	hud.note_deck(0, "Deck empty", 5.0)
	assert_str(hud.pile_label_text(0)).is_equal("Pile 2 - Deck empty")
	counts = [3, 1]
	hud.set_piles(counts)
	assert_str(hud.pile_label_text(0)).is_equal("Pile 3 - Deck empty")
	assert_str(hud.pile_label_text(1)).is_equal("Pile 1")


func test_the_free_first_energy_text_names_the_free_card() -> void:
	var hud: BoardHud = _hud()
	hud.set_energy(4, 4, true)
	assert_str(hud.energy_label_text()).is_equal("Energy 4 / 4 - first card free")
	hud.set_energy(4, 4, false)
	assert_str(hud.energy_label_text()).is_equal("Energy 4 / 4")
