# gdlint: ignore=max-public-methods
class_name EffectPlayer
extends RefCounted
## Plays the walk and the effects on the table (R51, R53, plan P17, P18): the pulse lift,
## stats, status, exit, move, return, discard, fizzle, the opponent's pick glowing and the
## public hand trigger (C14: HandTelegraph). Also the card
## motions the board shares (flip, lift, sweep off, move between collections). It holds no
## state of its own: the board hands in the collections and the id
## dictionaries it owns (same objects, never reassigned).
##
## Every tween belongs to the card it moves, so a card freed mid-tween (an exit, a new
## match) takes its tweens along and nothing errors.

## Shortest tween the collections are given, so a zero-length step never divides or stalls.
const MIN_TWEEN_TIME: float = 0.01
const REVEAL_LIFT: float = 0.8

var player_hand: CardCollection3D = null
var player_row: CardCollection3D = null
var opponent_row: CardCollection3D = null
var opponent_hand: CardCollection3D = null
var loose: Node3D = null
var exit_marker: Node3D = null
## The match's definitions by instance id: the two seats may play different decks.
var match_cards: MatchCards = null
## Returns seat 0's current SeatView (cycle 8 P16): the hand faces read their effective cost
## and memory from it. Unset, faces show the printed card.
var view_source: Callable = Callable()
## The engine seat the local player holds. Steps carry table seats (0 = the player's side);
## only a seat read from a raw event needs this to be turned into one.
var viewer: int = 0
## The board's zone-glow material, copied per card for CHOICE_SHOW (and T12's prompts).
var glow_material: Material = null
## Seat 0's cards by instance id, committed ids, and ids lying face down (board-owned).
var player_cards: Dictionary[int, BoardCard] = {}
var committed_ids: Dictionary[int, bool] = {}
var face_down_ids: Dictionary[int, bool] = {}
# --- The walk ---------------------------------------------------------------------------


## The card a pulse step is about, once pulse() has run (the chips go above it), or null.
func card_for(step: BoardStep) -> BoardCard:
	if step.seat == BoardSteps.OWN_SIDE:
		return _player_card(step.card)
	return _find_in_row(step.seat, step.card, step.slot)


## A pulse (R51): the card lifts and settles; a first reveal also flips it face up; an `again`
## pulse is the short revealed pulse.
func pulse(step: BoardStep) -> void:
	if step.revealed:
		var seen: BoardCard = _find_in_row(step.seat, step.card, step.slot)
		if seen != null:
			_lift_and_settle(seen, step.duration)
		return
	# The flip keeps the reveal's own time; a scoring reveal's step is longer only so its
	# chips can follow the flip (chip_delay, R31).
	var flip_time: float = step.chip_delay if step.chip_delay > 0.0 else step.duration
	if step.seat == BoardSteps.OWN_SIDE:
		var own: BoardCard = _player_card(step.card)
		if own == null:
			return
		# The public payload dresses the face: a row card is not in the hand row's entries.
		show(own, step, reveal_entry(step))
		_lift_and_settle(own, step.duration)
		if face_down_ids.erase(step.card):
			_flip_up(own, flip_time)
		return
	var card: BoardCard = _opponent_card_at(step.slot)
	if card == null:
		push_warning("Board: a reveal found no face-down card on the opponent's row")
		return
	card.instance_id = step.card
	card.set_look_mark(false)
	show(card, step, reveal_entry(step))
	_lift_and_settle(card, step.duration)
	_flip_up(card, flip_time)


# --- Effect steps (P18, R53) ---------------------------------------------------------------


## The source card lifts briefly. A public hand trigger (C14) pulses the viewer's own card in
## its fan (`from_hand`), or shows the opponent's card above its hand (TELEGRAPH).
func effect(step: BoardStep) -> void:
	if step.kind == BoardStep.Kind.TELEGRAPH:
		if HandTelegraph.play(step, opponent_hand, loose, match_cards) == null:
			push_warning("Board: no telegraph for the opponent's hand card %d" % step.card)
		return
	var card: BoardCard = _trigger_card(step)
	if card == null:
		return
	_lift_and_settle(card, step.duration)
	if step.from_hand and glow_material != null:
		card.pulse_glow(glow_material, step.duration)


## "no target" or "exhausted" fades on the source card (R83), in the fan for the viewer's
## own hand trigger (`from_hand`, C14).
func fizzle(step: BoardStep) -> void:
	var card: BoardCard = _trigger_card(step)
	if card != null:
		card.flash_note(fizzle_note(step.reason), step.duration)


## The card a trigger step is about: the viewer's hand card for `from_hand`, else the row card.
func _trigger_card(step: BoardStep) -> BoardCard:
	if step.from_hand:
		return _player_card(step.card)
	return _find_in_row(step.seat, step.card, -1)


## The note a fizzle flashes: "spent" for a once-only effect, "exhausted" when the trigger
## budget ran out (R83), otherwise "no target".
static func fizzle_note(reason: String) -> String:
	if reason == "spent" or reason == "exhausted":
		return reason
	return "no target"


## The numbers change and the one that changed pulses (R42, R76). The row card with the
## step's id (either row; the event names no seat for a public change), else the hand card.
func stats(step: BoardStep) -> void:
	var card: BoardCard = null
	if not step.in_hand:
		card = _find_on_any_row(step.card)
	if card == null:
		_restat_hand(step)
		return
	card.show_stats(step.power, step.mult, step.add, step.cost, step.permanent)


## A change to a card in the player's hand plays on the hand's face (cycle 8 R24, R26).
func _restat_hand(step: BoardStep) -> void:
	var card: BoardCard = _player_card(step.card)
	if card != null:
		card.show_stats(step.power, step.mult, step.add, step.cost, step.permanent)


## A badge word appears on, or goes from, the card (R79). The card is found by id on either
## row, else in the player's hand.
func status(step: BoardStep) -> void:
	var card: BoardCard = _find_on_any_row(step.card)
	if card == null:
		card = _player_card(step.card)
	if card == null:
		return
	var words: Array[String] = card.badge_words()
	if step.old_word != "":
		words = BoardCard.badges_after(words, step.old_word, false)
	card.set_badges(BoardCard.badges_after(words, step.word, step.status_on))


## The exit pass resolves a card (R81): to its Owner's Pile it flies off its row, to its
## Owner's fan it returns, and a Fade card flips face down in its slot. The card is found by
## id on either row, since a card on a row it does not own exits too.
func exit_card(step: BoardStep) -> void:
	if step.card < 0:
		_exit_hidden(step)
		return
	var row_seat: int = _row_seat_of(step.card)
	if row_seat < 0:
		push_warning("Board: an exit found no card %d on either row" % step.card)
		return
	var card: BoardCard = _find_in_row(row_seat, step.card, -1)
	match step.exit_to:
		BoardStep.ExitTo.PILE:
			_sweep_off_row(row_seat, card, step.duration)
		BoardStep.ExitTo.HAND:
			var hand: CardCollection3D = _hand_of(step.seat)
			move_card(card, _row_of(row_seat), hand, step.duration)
			_hide_if_opponent(card, step.seat, step.duration)
			if step.seat == BoardSteps.OWN_SIDE:
				# Home again: a card the opponent held on its row is the player's once more.
				_forget_flags(step.card)
				player_cards[step.card] = card
			else:
				_forget(step.card)
		BoardStep.ExitTo.FACE_DOWN:
			flip_down(card, step.duration)
			if row_seat == BoardSteps.OWN_SIDE:
				face_down_ids[step.card] = true
			else:
				_hide_if_opponent(card, 1, step.duration)


## An exit the viewer may not name (a face-down card of the other seat, redacted to card -1):
## a Fade leaves it face down as it is, a Fleeting card goes back to its Owner's fan as a
## back. The event names the row (`from_seat`) and the card's slot before it left (DC-14
## T17); an event with no row falls back to the event's owner seat.
func _exit_hidden(step: BoardStep) -> void:
	if step.exit_to != BoardStep.ExitTo.HAND:
		return
	var row_seat: int = step.from_seat
	if row_seat < 0 and step.source != null:
		row_seat = BoardSteps.table_seat(step.source.owner_seat, viewer)
	if row_seat != 1:
		return
	var card: BoardCard = _opponent_card_at(step.slot)  # The slot, else the first back.
	if card == null:
		push_warning("Board: a hidden exit found no face-down card on the opponent's row")
		return
	move_card(card, opponent_row, _hand_of(step.seat), step.duration)
	_hide_if_opponent(card, 1, step.duration)


## A note on the looked-at card (CARD_LOOKED): it glows and says "looked".
func look(step: BoardStep) -> void:
	var row: CardCollection3D = _row_of(step.from_seat)
	if step.slot < 0 or step.slot >= row.cards.size():
		return
	var card: BoardCard = row.cards[step.slot] as BoardCard
	if card == null:
		return
	if glow_material != null:
		card.pulse_glow(glow_material, step.duration)
	card.flash_note("looked", step.duration)
	card.set_look_mark(card.face_down)


## A card changes Controller (CONTROL_CHANGED): it moves to its new Controller's row at the
## step's slot, the Owner unchanged. The viewer's own row cards are the played ones, so a card
## gained is remembered as committed and one lost is forgotten.
func control(step: BoardStep) -> void:
	var card: BoardCard = _find_in_row(step.from_seat, step.card, -1)
	if card == null or step.seat == step.from_seat:
		push_warning("Board: a control change found no card %d to move" % step.card)
		return
	move_card(card, _row_of(step.from_seat), _row_of(step.seat), step.duration, step.slot)
	if step.seat == BoardSteps.OWN_SIDE:
		player_cards[step.card] = card
		committed_ids[step.card] = true
	else:
		_forget(step.card)


## The view's entry for card `id` on `seat`'s row (its Power, Mult, Add, statuses), or {}.
func row_entry(seat: int, id: int) -> Dictionary:
	var view: SeatView = _view()
	if view == null:
		return {}
	return BoardCard.entry_in(
		view.own_row if seat == BoardSteps.OWN_SIDE else view.opponent_row, id
	)


## Marks the opponent's face-down cards the viewer has looked at (SeatView.looked: row slot to
## card id) and clears the mark from the others.
func sync_looks() -> void:
	var view: SeatView = _view()
	if view == null:
		return
	for slot: int in range(opponent_row.cards.size()):
		var card: BoardCard = opponent_row.cards[slot] as BoardCard
		if card != null:
			card.set_look_mark(view.looked.has(slot) and card.face_down)


## Redresses every face in the player's hand from the view (turn start, cycle 8 P16).
func _refresh_hand() -> void:
	var rows: Array[Dictionary] = _hand_rows()
	for held: Card3D in player_hand.cards:
		var card: BoardCard = held as BoardCard
		var def: CardDef = null
		if card != null and match_cards != null and card.instance_id >= 0:
			def = match_cards.def_of(card.instance_id)
		if def != null:
			card.show_entry(def, BoardCard.entry_in(rows, card.instance_id))


func _view() -> SeatView:
	if not view_source.is_valid():
		return null
	var raw: Object = view_source.call()
	return raw as SeatView


func _hand_rows() -> Array[Dictionary]:
	var view: SeatView = _view()
	if view == null:
		var none: Array[Dictionary] = []
		return none
	return view.own_hand_row


## Tells the player which step just played: a turn start redresses the hand from the view.
func note_step(step: BoardStep) -> void:
	if step.kind == BoardStep.Kind.TURN_START:
		_refresh_hand()
		sync_looks()


## The row slides to its new order in one re-layout: every card of the step goes from its row
## index to its new one, the cards the step does not name keep their index.
func move(step: BoardStep) -> void:
	var row: CardCollection3D = _row_of(step.seat)
	var order: Array[Card3D] = grouped_order(row.cards, step.from_slots, step.slots_to)
	if order.is_empty():
		return
	row.card_move_tween_duration = maxf(step.duration, MIN_TWEEN_TIME)
	for i: int in range(order.size()):
		if row.cards[i] != order[i]:
			row.move_card(order[i], i)


## The row order after a grouped move: the card at each `from` index lands at the matching `to`
## index, the rest stay. Empty when an index is out of range or the targets collide.
static func grouped_order(
	current: Array[Card3D], from_slots: Array[int], to_slots: Array[int]
) -> Array[Card3D]:
	var order: Array[Card3D] = []
	order.append_array(current)
	var size: int = current.size()
	if from_slots.size() != to_slots.size():
		return []
	var taken: Dictionary[int, bool] = {}
	for i: int in range(from_slots.size()):
		var from: int = from_slots[i]
		var to: int = to_slots[i]
		if from < 0 or to < 0 or from >= size or to >= size or taken.has(to):
			return []
		taken[to] = true
		order[to] = current[from]
	var seen: Dictionary[Card3D, bool] = {}
	for card: Card3D in order:
		seen[card] = true
	if seen.size() != size:
		return []
	return order


## A revealed card flips face down in its slot. The player keeps knowing it; the opponent's
## becomes a plain back again.
func unreveal(step: BoardStep) -> void:
	var card: BoardCard = _find_in_row(step.seat, step.card, step.slot)
	if card == null:
		push_warning("Board: an unreveal found no card on seat %d's row" % step.seat)
		return
	if step.seat == BoardSteps.OWN_SIDE:
		flip_down(card, step.duration)
		face_down_ids[step.card] = true
		return
	_hide_if_opponent(card, step.seat, step.duration)


## The card flies to its owner's hand: face up for the player, face down for the opponent.
func return_card(step: BoardStep) -> void:
	var row_seat: int = step.from_seat if step.from_seat >= 0 else step.seat
	var card: BoardCard = _find_in_row(row_seat, step.card, step.slot)
	if card == null:
		push_warning("Board: a return found no card on seat %d's row" % row_seat)
		return
	var hand: CardCollection3D = _hand_of(step.seat)
	move_card(card, _row_of(row_seat), hand, step.duration)
	if step.seat == BoardSteps.OWN_SIDE:
		_forget_flags(card.instance_id)
		return
	# The opponent's copy is a back again; forget which card it was.
	_hide_if_opponent(card, step.seat, step.duration)


## The card leaves the hand off the exit side. The opponent's hand cards are all backs, so
## its discard takes the fan's last card. A discard from a row (`from_row`: a Condemned card,
## a round-end clear) sweeps the card off its row when an EXIT or the table clear has not
## already taken it (R81).
func discard(step: BoardStep) -> void:
	if step.from_row:
		_sweep_off_any_row(step.card, step.duration)
		return
	var card: BoardCard = _hand_card(step.seat, step.card)
	if card != null:
		_sweep_off(_hand_of(step.seat), card, step.duration)


## DROSS_EXPIRED (R25): the card leaves the table with a fly-off, from the hand or a row. A
## card in a Pile or Deck, or one the board does not show, is a no-op; the Pile count stays.
func expire(step: BoardStep) -> void:
	if step.zone == "hand":
		var card: BoardCard = _hand_card(step.seat, step.card)
		if card != null:
			_sweep_off(_hand_of(step.seat), card, step.duration)
	elif step.zone == "row":
		_sweep_off_any_row(step.card, step.duration)


## The opponent's pick glows for the step's time (R53). The card is found by zone and index,
## since a private pick arrives without its id.
func choice_show(step: BoardStep) -> void:
	if step.index < 0:
		# A set answer (Quorum, Cull, Immolate): every kept or chosen position glows.
		for picked: int in step.options:
			_glow_choice(step, picked)
		return
	_glow_choice(step, step.index)


func _glow_choice(step: BoardStep, index: int) -> void:
	var own_size: int = _row_of(step.seat).cards.size()
	var spot: CardSpot = RowTargets.resolve(step.zone, step.seat, index, own_size)
	if not spot.is_valid() or glow_material == null:
		return
	var collection: CardCollection3D = _hand_of(spot.seat) if spot.in_hand else _row_of(spot.seat)
	if spot.slot >= collection.cards.size():
		return
	var card: BoardCard = collection.cards[spot.slot] as BoardCard
	if card != null:
		card.pulse_glow(glow_material, step.duration)


# --- Lookups ----------------------------------------------------------------------------


func _row_of(seat: int) -> CardCollection3D:
	return player_row if seat == BoardSteps.OWN_SIDE else opponent_row


func _hand_of(seat: int) -> CardCollection3D:
	return player_hand if seat == BoardSteps.OWN_SIDE else opponent_hand


## Seat 0's card with this instance id, or null.
func _player_card(id: int) -> BoardCard:
	if not player_cards.has(id):
		return null
	return player_cards[id]


## A card on `seat`'s row: the one with instance id `id` when given, else the one at `slot`.
## Null when neither names a card.
func _find_in_row(seat: int, id: int, slot: int) -> BoardCard:
	var row: CardCollection3D = _row_of(seat)
	if id >= 0:
		for candidate: Card3D in row.cards:
			var named: BoardCard = candidate as BoardCard
			if named != null and named.instance_id == id:
				return named
	if slot >= 0 and slot < row.cards.size():
		return row.cards[slot] as BoardCard
	return null


## The seat whose row holds the card with this id, or -1.
func _row_seat_of(id: int) -> int:
	if id < 0:
		return -1
	for seat: int in range(2):
		if _find_in_row(seat, id, -1) != null:
			return seat
	return -1


## The card with this id on either row, or null.
func _find_on_any_row(id: int) -> BoardCard:
	var seat: int = _row_seat_of(id)
	return null if seat < 0 else _find_in_row(seat, id, -1)


## The hand card a step names: the viewer's own by id; the opponent's hand is all backs, so
## its card is the fan's last. Null when there is none.
func _hand_card(seat: int, id: int) -> BoardCard:
	if seat == BoardSteps.OWN_SIDE:
		return _player_card(id)
	var hand: CardCollection3D = _hand_of(seat)
	if hand.cards.is_empty():
		return null
	return hand.cards[hand.cards.size() - 1] as BoardCard


## Sweeps the card with this id off whichever row holds it; a no-op when neither does.
func _sweep_off_any_row(id: int, duration: float) -> void:
	var row_seat: int = _row_seat_of(id)
	if row_seat >= 0:
		_sweep_off_row(row_seat, _find_in_row(row_seat, id, -1), duration)


## The opponent's copy is a back again: forget which card it was once the move ends.
func _hide_if_opponent(card: BoardCard, seat: int, duration: float) -> void:
	if seat == BoardSteps.OWN_SIDE:
		return
	card.instance_id = -1
	flip_down(card, duration)
	var wipe: Tween = card.create_tween()
	var wait: IntervalTweener = wipe.tween_interval(maxf(duration, MIN_TWEEN_TIME))
	var done: CallbackTweener = wipe.tween_callback(card.clear_def)
	if wait == null or done == null:
		card.clear_def()


## The face-down opponent card to reveal at a row slot; the first one without an id when the
## slot does not name one.
func _opponent_card_at(slot: int) -> BoardCard:
	if slot >= 0 and slot < opponent_row.cards.size():
		var named: BoardCard = opponent_row.cards[slot] as BoardCard
		if named != null and named.instance_id == -1:
			return named
	for card: Card3D in opponent_row.cards:
		var candidate: BoardCard = card as BoardCard
		if candidate != null and candidate.instance_id == -1:
			return candidate
	return null


## Drops a card id from the board's id books.
func _forget_flags(id: int) -> void:
	@warning_ignore("return_value_discarded")
	committed_ids.erase(id)
	@warning_ignore("return_value_discarded")
	face_down_ids.erase(id)


func _forget(id: int) -> void:
	@warning_ignore("return_value_discarded")
	player_cards.erase(id)
	@warning_ignore("return_value_discarded")
	committed_ids.erase(id)
	@warning_ignore("return_value_discarded")
	face_down_ids.erase(id)


## Forgets the id books, for a new match or a table clear.
func reset() -> void:
	player_cards.clear()
	committed_ids.clear()
	face_down_ids.clear()


## A new Round clears the rows only: hands persist (rules 7), so the player's hand cards keep
## their ids; the committed and face-down books are dropped.
func reset_rows() -> void:
	var stale: Array[int] = []
	for id: int in player_cards.keys():
		if not player_hand.cards.has(player_cards[id]):
			stale.append(id)
	for id: int in stale:
		_forget(id)
	committed_ids.clear()
	face_down_ids.clear()


# --- Card motions (shared with the board) --------------------------------------------------


## Face text for a card the viewer may see. The card must be in the tree.
func show(card: BoardCard, step: BoardStep, entry: Dictionary = {}) -> void:
	card.instance_id = step.card
	var def: CardDef = null if match_cards == null else match_cards.def_of(step.card)
	if def == null:
		push_warning("Board: no card definition for card %d" % step.card)
		return
	var face: Dictionary = entry
	if face.is_empty():
		face = BoardCard.entry_in(_hand_rows(), step.card)
	card.show_entry(def, face)


## The face entry a reveal step carries (CARD_REVEALED: Power, Mult, Add and the status words
## are public). The effective cost is not on the event, so the face keeps the printed one.
static func reveal_entry(step: BoardStep) -> Dictionary:
	var entry: Dictionary = {
		"card": step.card,
		"power": step.power,
		"mult": step.mult,
		"add": step.add,
		"statuses": step.statuses,
	}
	return entry


## Takes a card off a row, onto the loose layer where it is, and sweeps it off. The row
## closes the gap.
func _sweep_off_row(seat: int, card: BoardCard, duration: float) -> void:
	_sweep_off(_row_of(seat), card, duration)


## Takes `card` out of `collection` (a row or a hand), onto the loose layer where it is, and
## sweeps it off; nothing when the card is not there.
func _sweep_off(collection: CardCollection3D, card: BoardCard, duration: float) -> void:
	var index: int = collection.cards.find(card)
	if index < 0:
		return
	var placed: Transform3D = card.global_transform
	collection.card_move_tween_duration = maxf(duration, MIN_TWEEN_TIME)
	var removed: Card3D = collection.remove_card(index)
	loose.add_child(removed)
	removed.global_transform = placed
	_forget(card.instance_id)
	fly_out(removed, duration)


## Moves a card between collections, keeping its place on screen so the new layout tweens
## it over from there. `at` is the target index (a slot); negative appends.
func move_card(
	card: Card3D, source: CardCollection3D, target: CardCollection3D, duration: float, at: int = -1
) -> void:
	var index: int = source.cards.find(card)
	if index < 0:
		return
	var placed: Transform3D = card.global_transform
	var moved: Card3D = source.remove_card(index)
	target.card_move_tween_duration = maxf(duration, MIN_TWEEN_TIME)
	if at < 0:
		target.append_card(moved)
	else:
		target.insert_card(moved, RowSlots.insert_index(at, target.cards.size()))
	moved.global_transform = placed


## R46: turns a card face down in place; the flag is set when the turn ends.
func flip_down(card: BoardCard, duration: float) -> void:
	var mesh: Node3D = card.get_node("CardMesh") as Node3D
	var tween: Tween = card.create_tween()
	add_tween(tween, mesh, ^"rotation:y", PI, maxf(duration, MIN_TWEEN_TIME))
	var err: int = tween.finished.connect(_flag_face_down.bind(card))
	if err != OK:
		card.face_down = true


func _flip_up(card: BoardCard, duration: float) -> void:
	var mesh: Node3D = card.get_node("CardMesh") as Node3D
	var tween: Tween = card.create_tween()
	add_tween(tween, mesh, ^"rotation:y", 0.0, maxf(duration, MIN_TWEEN_TIME))
	var err: int = tween.finished.connect(_unflag_face_down.bind(card))
	if err != OK:
		card.face_down = false


func _lift_and_settle(card: BoardCard, duration: float) -> void:
	var mesh: Node3D = card.get_node("CardMesh") as Node3D
	var half: float = maxf(duration, MIN_TWEEN_TIME) / 2.0
	var tween: Tween = card.create_tween()
	add_tween(tween, mesh, ^"position:z", REVEAL_LIFT, half)
	add_tween(tween, mesh, ^"position:z", 0.0, half)


## Sweeps a card from where it is to the exit marker and frees it.
func fly_out(card: Card3D, duration: float) -> void:
	_stop_card_tweens(card)
	var tween: Tween = card.create_tween()
	add_tween(
		tween, card, ^"global_position", exit_marker.global_position, maxf(duration, MIN_TWEEN_TIME)
	)
	var err: int = tween.finished.connect(card.queue_free)
	if err != OK:
		card.queue_free()


func _flag_face_down(card: BoardCard) -> void:
	if is_instance_valid(card):
		card.face_down = true


func _unflag_face_down(card: BoardCard) -> void:
	if is_instance_valid(card):
		card.face_down = false


func _stop_card_tweens(card: Card3D) -> void:
	for running: Tween in [card.position_tween, card.rotate_tween, card.hover_tween]:
		if running != null and running.is_valid():
			running.kill()


## Adds one sine-eased property step to `tween` (HandTelegraph shares it).
static func add_tween(
	tween: Tween, target: Object, property: NodePath, value: Variant, duration: float
) -> void:
	var tweener: PropertyTweener = tween.tween_property(target, property, value, duration)
	tweener = tweener.set_trans(Tween.TRANS_SINE)
	tweener = tweener.set_ease(Tween.EASE_IN_OUT)
