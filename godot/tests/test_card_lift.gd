class_name TestCardLift
extends GdUnitTestSuite
## CardLift (NSC-58, R23): lift, put-down, drop_now, a freed held card; and the Board's tap and
## drag paths over a real Board, which refuse once the match is closed or over.

const CARD_SCENE: PackedScene = preload("res://board/board_card.tscn")
const BOARD_SCENE: PackedScene = preload("res://board/board.tscn")

var _lift: CardLift = null
var _loose: Node3D = null


func before_test() -> void:
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	_loose = auto_free(Node3D.new())
	add_child(_loose)
	var dimmer: MeshInstance3D = auto_free(MeshInstance3D.new())
	dimmer.material_override = StandardMaterial3D.new()
	add_child(dimmer)
	_lift = auto_free(CardLift.new())
	add_child(_lift)
	_lift.setup(camera, _loose, dimmer, _spawn)


func _spawn() -> Object:
	return CARD_SCENE.instantiate()


func _card() -> BoardCard:
	var card: BoardCard = CARD_SCENE.instantiate() as BoardCard
	add_child(card)
	card.global_position = Vector3(2.0, 0.0, -5.0)
	return card


func test_lift_hides_the_real_card_and_holds_it() -> void:
	var card: BoardCard = auto_free(_card())
	_lift.lift(card)
	assert_bool(_lift.is_holding()).is_true()
	assert_object(_lift.held).is_same(card)
	assert_bool(card.visible).is_false()
	assert_int(_loose.get_child_count()).is_equal(1)


func test_a_second_lift_does_nothing_while_a_card_is_held() -> void:
	var card: BoardCard = auto_free(_card())
	var other: BoardCard = auto_free(_card())
	_lift.lift(card)
	_lift.lift(other)
	assert_object(_lift.held).is_same(card)
	assert_bool(other.visible).is_true()


func test_put_down_with_no_time_shows_the_card_again() -> void:
	var card: BoardCard = auto_free(_card())
	_lift.lift(card)
	_lift.put_down(0.0)
	assert_bool(_lift.is_holding()).is_false()
	assert_bool(card.visible).is_true()


func test_put_down_with_nothing_held_does_nothing() -> void:
	_lift.put_down(0.0)
	assert_bool(_lift.is_holding()).is_false()


func test_drop_now_ends_a_lift_at_once() -> void:
	var card: BoardCard = auto_free(_card())
	_lift.lift(card)
	_lift.drop_now()
	assert_bool(_lift.is_holding()).is_false()
	assert_bool(card.visible).is_true()


func test_a_freed_held_card_is_dropped_without_error() -> void:
	var card: BoardCard = _card()
	_lift.lift(card)
	card.free()
	_lift.drop_now()
	assert_bool(_lift.is_holding()).is_false()


## A real Board over a started fixture match, one face-up card in the player's hand, input open.
func _live_board() -> Board:
	var board: Board = BOARD_SCENE.instantiate() as Board
	auto_free(board)
	add_child(board)
	var driver: MatchDriver = MatchDriver.create(
		1,
		FixtureDecks.cards(),
		FixtureDecks.decks(),
		FixtureDecks.ids(),
		false,
		"random",
		FixtureDecks.crew()
	)
	var opening: Array[MatchEvent] = driver.begin()
	assert_bool(opening.is_empty()).is_false()
	board.source = driver
	board._phase = Board.InputPhase.AWAITING
	return board


func _hand_card(board: Board) -> BoardCard:
	var card: BoardCard = CARD_SCENE.instantiate() as BoardCard
	board.player_hand.append_card(card)
	return card


func test_a_tap_on_a_live_board_lifts_a_hand_card() -> void:
	var board: Board = _live_board()
	var card: BoardCard = _hand_card(board)
	assert_bool(board.may_act()).is_true()
	board._on_pointer_tapped(Vector2.ZERO, card)
	assert_bool(board.card_lift.is_holding()).is_true()


func test_a_tap_after_the_match_is_closed_does_not_lift() -> void:
	var board: Board = _live_board()
	var card: BoardCard = _hand_card(board)
	board._on_match_closed(MatchSource.CLOSED_ABANDONED)
	board._on_pointer_tapped(Vector2.ZERO, card)
	assert_bool(board.card_lift.is_holding()).is_false()
	assert_bool(card.visible).is_true()
	assert_bool(board.may_act()).is_false()


func test_a_tap_after_the_match_is_over_does_not_lift() -> void:
	var board: Board = _live_board()
	var card: BoardCard = _hand_card(board)
	var driver: MatchDriver = board.source as MatchDriver
	var conceded: ApplyResult = driver.submit_player(EngineAction.concede(driver.player_seat))
	assert_bool(conceded.ok).is_true()
	assert_bool(driver.is_over()).is_true()
	board._on_pointer_tapped(Vector2.ZERO, card)
	assert_bool(board.card_lift.is_holding()).is_false()
	assert_bool(board.may_act()).is_false()


func test_a_paused_board_refuses_the_tap_and_the_drag() -> void:
	var board: Board = _live_board()
	var card: BoardCard = _hand_card(board)
	board._paused = true
	board._on_pointer_tapped(Vector2.ZERO, card)
	assert_bool(board.card_lift.is_holding()).is_false()
	assert_bool(board.may_act()).is_false()
