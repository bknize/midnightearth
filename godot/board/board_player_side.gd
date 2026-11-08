class_name BoardPlayerSide
extends RefCounted
## The player's side of the table, moved out of Board (R11-R20, R26, R1-R11): the staged cards
## against the energy, the drag feedback on the zone glows, and the card pick-up. It reads
## and drives the board it is built for; the board keeps the signal handlers and forwards.

var board: Board = null
## The drag in progress: the card, where it started, and whether the pointer was over the
## row's drop zone (R14).
var _drag_card: BoardCard = null
var _drag_from_hand: bool = false
var _over_row: bool = false
var _drag_cancelled: bool = false


func _init(p_board: Board) -> void:
	board = p_board


## Forgets the drag in progress (a new match).
func reset_drag() -> void:
	_drag_card = null
	_drag_from_hand = false
	_over_row = false
	_drag_cancelled = false


func make_strategy(role: BoardDragStrategy.Role) -> BoardDragStrategy:
	var strategy: BoardDragStrategy = BoardDragStrategy.new()
	strategy.role = role
	strategy.can_act = board.may_act
	strategy.is_locked = _is_locked
	strategy.can_afford = _card_affordable
	strategy.is_staged = _card_staged
	strategy.is_played = _card_played
	return strategy


func _is_locked() -> bool:
	return board._input_locked or board.card_lift.is_holding()


## True when the card (a seat-0 BoardCard; anything else is false) fits in the energy left
## this turn (R14).
func _card_affordable(card: Object) -> bool:
	var board_card: BoardCard = card as BoardCard
	if board_card == null:
		return false
	return board.staging.can_afford(cost_of(board_card.instance_id))


func _card_staged(card: Object) -> bool:
	var board_card: BoardCard = card as BoardCard
	if board_card == null:
		return false
	return board.staging.has(board_card.instance_id)


## True for a seat-0 card already played this round (committed): it never drags (R44).
func _card_played(card: Object) -> bool:
	var board_card: BoardCard = card as BoardCard
	if board_card == null:
		return false
	return board._committed_ids.has(board_card.instance_id)


## The cost of a card instance, from the match's own definitions (the seats' decks differ).
func cost_of(id: int) -> int:
	var def: CardDef = board.source.match_cards().def_of(id)
	return board.staging.cached_cost(id, board.source.view, 0 if def == null else def.cost)


func refresh_staging_ui() -> void:
	board.hud.set_energy(board.staging.energy_left(), board._turn_energy, board._free_first)
	board.hud.set_commit_label(not board.staging.cards().is_empty())
	board._refresh_commit_enabled()


## The uncommitted cards on the player's row, in row order.
func staged_cards() -> Array[BoardCard]:
	var out: Array[BoardCard] = []
	for card: Card3D in board.player_row.cards:
		var board_card: BoardCard = card as BoardCard
		if board_card != null and not board._committed_ids.has(board_card.instance_id):
			out.append(board_card)
	return out


## The instance ids of the player's row, in row order.
func row_ids() -> Array[int]:
	var out: Array[int] = []
	for card: Card3D in board.player_row.cards:
		var board_card: BoardCard = card as BoardCard
		out.append(board_card.instance_id if board_card != null else -1)
	return out


## How many played (committed) cards sit on the player's row: the first staged slot.
func _played_count() -> int:
	return board.player_row.cards.size() - staged_cards().size()


## Index of a staged card among the staged cards only: the staged cards before it on the row,
## wherever the played cards sit (R43).
func _staged_index(card: BoardCard) -> int:
	return RowSlots.staged_before(row_ids(), board._committed_ids, card.instance_id)


## Rebuilds staging from the row if it ever differs from it; any staged card that no longer
## fits goes back to the hand (R14). Then refreshes the energy readout and the button.
func _resync_staging() -> void:
	var staged: Array[BoardCard] = staged_cards()
	var expected: Array[int] = []
	for card: BoardCard in staged:
		expected.append(card.instance_id)
	if expected != board.staging.cards():
		board.staging.reset(
			board._turn_energy, board.player_row.cards.size() - staged.size(), board._free_first
		)
		var rejected: Array[BoardCard] = []
		var at_end: int = 0
		for card: BoardCard in staged:
			if board.staging.insert(card.instance_id, cost_of(card.instance_id), at_end):
				at_end += 1
			else:
				rejected.append(card)
		for card: BoardCard in rejected:
			board._fx.move_card(
				card, board.player_row, board.player_hand, Board.UNSTAGE_TIME / board.speed
			)
	board.staging.set_row(row_ids())
	refresh_staging_ui()


## Sends every staged card back to the hand and empties staging for this turn's energy.
func unstage_all() -> void:
	for card: BoardCard in staged_cards():
		board._fx.move_card(
			card, board.player_row, board.player_hand, Board.UNSTAGE_TIME / board.speed
		)
	board.staging.reset(board._turn_energy, _played_count(), board._free_first)
	refresh_staging_ui()


## The DragController moved a card (R12, R13). Staging follows the row.
func on_drag_card_moved(
	card: Card3D,
	from_collection: CardCollection3D,
	to_collection: CardCollection3D,
	_from_index: int,
	_to_index: int
) -> void:
	var board_card: BoardCard = card as BoardCard
	if board_card == null:
		return
	var id: int = board_card.instance_id
	if from_collection == board.player_hand and to_collection == board.player_row:
		var inserted: bool = board.staging.insert(id, cost_of(id), _staged_index(board_card))
		if not inserted:
			push_warning("Board: staging refused card %d dropped on the row" % id)
	elif from_collection == board.player_row and to_collection == board.player_hand:
		board.staging.remove(id)
	elif from_collection == board.player_row and to_collection == board.player_row:
		board.staging.move(id, _staged_index(board_card))
	_resync_staging()


func on_drag_started(card: Card3D) -> void:
	_drag_card = card as BoardCard
	_drag_from_hand = board.player_hand.cards.has(card)
	_over_row = false
	_drag_cancelled = false
	# The row refuses an unaffordable card, so its drop zone would stay off; switch it on
	# so the release over the row can be told apart from a release elsewhere (R14).
	if _drag_from_hand and board.may_act() and not _card_affordable(card):
		board.player_row.enable_drop_zone()
	if _drag_card != null and board.may_act():
		BoardGlow.show(board._hand_glow, BoardGlow.Look.IDLE)
		BoardGlow.show(board._row_glow, _row_look(false))


## After every drag, refused or cancelled or not: flash on a refused drop (R14) and make
## sure staging matches the row (R26).
func on_drag_stopped(card: Card3D) -> void:
	var refused: bool = (
		_drag_from_hand
		and _over_row
		and not _drag_cancelled
		and board.player_hand.cards.has(card)
		and board.may_act()
		and not _card_affordable(card)
	)
	if refused:
		board.hud.flash_energy()
	hide_glows()
	_drag_card = null
	_drag_from_hand = false
	_over_row = false
	_drag_cancelled = false
	_resync_staging()


func on_row_zone_entered() -> void:
	_over_row = true
	if board._row_glow.visible:
		BoardGlow.show(board._row_glow, _row_look(true))


func on_row_zone_exited() -> void:
	_over_row = false
	if board._row_glow.visible:
		BoardGlow.show(board._row_glow, _row_look(false))


func on_hand_zone_entered() -> void:
	if board._hand_glow.visible:
		BoardGlow.show(board._hand_glow, BoardGlow.Look.HOVER)


func on_hand_zone_exited() -> void:
	if board._hand_glow.visible:
		BoardGlow.show(board._hand_glow, BoardGlow.Look.IDLE)


## The row panel's look: red when it would refuse the dragged card (R14), else idle/hover.
func _row_look(hovered: bool) -> BoardGlow.Look:
	if _drag_from_hand and _drag_card != null and not _card_affordable(_drag_card):
		return BoardGlow.Look.REFUSE
	return BoardGlow.Look.HOVER if hovered else BoardGlow.Look.IDLE


func hide_glows() -> void:
	board._hand_glow.visible = false
	board._row_glow.visible = false


func on_pointer_cancelled() -> void:
	_drag_cancelled = true


# --- Card pick-up (R1-R11) -----------------------------------------------------------------


## The LiftRules.Place of a card, or -1 if it is in no collection.
func place_of(card: Card3D) -> int:
	if board._crew_line.has_card(card):
		return LiftRules.Place.CREW
	if board.player_hand.cards.has(card):
		return LiftRules.Place.HAND
	if board.player_row.cards.has(card):
		return LiftRules.Place.ROW
	if board.opponent_row.cards.has(card):
		return LiftRules.Place.OPPONENT_ROW
	if board.opponent_hand.cards.has(card):
		return LiftRules.Place.OPPONENT_HAND
	return -1


## A tap puts a held card down and does nothing else (R5); otherwise it lifts the card under
## it if the rules allow (R1, R2), never during a drag or a pause (R7).
func on_pointer_tapped(_position: Vector2, hit: Object) -> void:
	if board._prompt.is_open() and not board._paused:
		board._prompt.handle_tap(LiftRules.card_from_hit(hit))
		return
	if board.card_lift.is_holding():
		board.card_lift.put_down()
		return
	if board._paused or _drag_card != null:
		return
	var card: BoardCard = LiftRules.card_from_hit(hit)
	if card == null:
		return
	var place: int = place_of(card)
	if place < 0:
		return
	if LiftRules.may_lift(place as LiftRules.Place, not card.face_down):
		board.card_lift.lift(card)


func on_card_lifted(_card: BoardCard) -> void:
	# The prompt's banner and the action button live in the HUD, so it stays up (R40).
	board.hud.visible = board._prompt.is_open()
	board.player_hand.hover_disabled = true
	board.player_row.hover_disabled = true
	board._refresh_commit_enabled()


func on_card_put_down(_card: BoardCard) -> void:
	board._prompt.lift_ended()
	board.hud.visible = true
	board.player_hand.hover_disabled = false
	board.player_row.hover_disabled = false
	board._refresh_commit_enabled()
