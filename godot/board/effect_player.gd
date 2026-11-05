class_name EffectPlayer
extends RefCounted
## Plays the walk and the effects on the table (R51, R53, plan P17, P18): the pulse lift,
## stats, destroy, move, return, discard, fizzle and the opponent's pick glowing. Also the card
## motions the board shares (flip, lift, sweep off, move between collections). It holds no
## state of its own: the board hands in the collections and the id
## dictionaries it owns (same objects, never reassigned).
##
## Every tween belongs to the card it moves, so a card freed mid-tween (a destroy, a new
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
## The deck strip of a recover prompt (T10 sets it); null while there is none.
var strip: CardCollection3D = null
## The board's zone-glow material, copied per card for CHOICE_SHOW (and T12's prompts).
var glow_material: Material = null
## Seat 0's cards by instance id, committed ids, and ids lying face down (board-owned).
var player_cards: Dictionary[int, BoardCard] = {}
var committed_ids: Dictionary[int, bool] = {}
var face_down_ids: Dictionary[int, bool] = {}
## The seat whose RECOVER played just before the current step; -1 when none.
var _recovered_seat: int = -1

# --- The walk ---------------------------------------------------------------------------


## The card a pulse step is about, once pulse() has run (the chips go above it), or null.
func card_for(step: BoardStep) -> BoardCard:
	if step.seat == 0:
		return _player_card(step.card)
	return _find_in_row(step.seat, step.card, step.slot)


## A pulse (R51): the card lifts and settles; a first reveal also flips it face up. A
## destroyed reveal only flips (no lift, R28); an `again` pulse is the short revealed pulse.
func pulse(step: BoardStep) -> void:
	if step.revealed:
		var seen: BoardCard = _find_in_row(step.seat, step.card, step.slot)
		if seen != null:
			_lift_and_settle(seen, step.duration)
		return
	var lift: bool = not step.destroyed
	# The flip keeps the reveal's own time; a scoring reveal's step is longer only so its
	# chips can follow the flip (chip_delay, R31).
	var flip_time: float = step.chip_delay if step.chip_delay > 0.0 else step.duration
	if step.seat == 0:
		var own: BoardCard = _player_card(step.card)
		if own == null:
			return
		if lift:
			_lift_and_settle(own, step.duration)
		if face_down_ids.erase(step.card):
			_flip_up(own, flip_time)
		return
	var card: BoardCard = _opponent_card_at(step.slot)
	if card == null:
		push_warning("Board: a reveal found no face-down card on the opponent's row")
		return
	card.instance_id = step.card
	show(card, step)
	if lift:
		_lift_and_settle(card, step.duration)
	_flip_up(card, flip_time)


# --- Effect steps (P18, R53) ---------------------------------------------------------------


## The source card lifts briefly.
func effect(step: BoardStep) -> void:
	var card: BoardCard = _find_in_row(step.seat, step.card, -1)
	if card != null:
		_lift_and_settle(card, step.duration)


## "no target" fades on the source card.
func fizzle(step: BoardStep) -> void:
	var card: BoardCard = _find_in_row(step.seat, step.card, -1)
	if card != null:
		card.flash_note("no target", step.duration)


## The numbers change and the one that changed pulses (R42).
func stats(step: BoardStep) -> void:
	var card: BoardCard = null
	if not step.in_hand:
		card = _find_in_row(step.seat, step.card, -1)
	if card == null:
		_restat_hand(step)
		return
	card.show_stats(step.flat, step.times, step.plus, step.cost, step.permanent)


## A change to a card in the player's hand plays on the hand's face (cycle 8 R24, R26).
func _restat_hand(step: BoardStep) -> void:
	var card: BoardCard = _player_card(step.card)
	if card != null:
		card.show_stats(step.flat, step.times, step.plus, step.cost, step.permanent)


## Redresses every face in the player's hand from the view (turn start, cycle 8 P16).
func _refresh_hand() -> void:
	for held: Card3D in player_hand.cards:
		var card: BoardCard = held as BoardCard
		var def: CardDef = null
		if card != null and match_cards != null and card.instance_id >= 0:
			def = match_cards.def_of(card.instance_id)
		if def != null:
			card.show_entry(def, BoardCard.entry_in(_hand_rows(), card.instance_id))


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


## The card is marked in place (R26): dim, tilt and crack fade in; it stays on its row,
## face up or down.
func destroy(step: BoardStep) -> void:
	var card: BoardCard = _find_in_row(step.seat, step.card, step.slot)
	if card == null:
		push_warning("Board: a destroy found no card on seat %d's row" % step.seat)
		return
	card.set_destroyed(true, _row_of(step.seat).cards.find(card), step.duration)


## At turn end the destroyed card sweeps off its row and leaves the collection (R29).
func clear_destroyed(step: BoardStep) -> void:
	var card: BoardCard = _find_in_row(step.seat, step.card, step.slot)
	if card == null:
		push_warning("Board: a clear found no card on seat %d's row" % step.seat)
		return
	_sweep_off_row(step.seat, card, step.duration)


## A burn of a card the board already holds: a returned card that found a full hand (on a row)
## or a recovered one that found a full hand (in the hand, R19). True when the card has swept
## off; false when it is a deck burn the board spawns itself.
func burn_from_row(step: BoardStep) -> bool:
	if step.card >= 0:
		var card: BoardCard = _find_in_row(step.seat, step.card, -1)
		if card != null and card.instance_id == step.card:
			_sweep_off_row(step.seat, card, step.duration)
			return true
	return _burn_from_hand(step)


## Tells the player which step just played, so a hidden burn right after the seat's RECOVER
## is known to be that recovered card (the opponent's id is hidden). A turn start redresses
## the hand from the view.
func note_step(step: BoardStep) -> void:
	if step.kind == BoardStep.Kind.RECOVER:
		_recovered_seat = step.seat
	elif step.kind != BoardStep.Kind.BURN:
		_recovered_seat = -1
	if step.kind == BoardStep.Kind.TURN_START:
		_refresh_hand()


## Which hand card a burn takes, by index into `hand_ids` (the instance id of each hand card,
## -1 for a back): the player's by its id; the opponent's hidden burn takes the last card when
## `recovered_seat` says its recovery came just before. -1 for a deck burn.
static func hand_burn_index(
	hand_ids: Array[int], step_card: int, seat: int, recovered_seat: int
) -> int:
	if step_card >= 0:
		return hand_ids.find(step_card) if seat == 0 else -1
	if seat != 0 and recovered_seat == seat and not hand_ids.is_empty():
		return hand_ids.size() - 1
	return -1


func _burn_from_hand(step: BoardStep) -> bool:
	var hand: CardCollection3D = _hand_of(step.seat)
	var ids: Array[int] = []
	for held: Card3D in hand.cards:
		var named: BoardCard = held as BoardCard
		ids.append(-1 if named == null else named.instance_id)
	var index: int = hand_burn_index(ids, step.card, step.seat, _recovered_seat)
	_recovered_seat = -1
	if index < 0:
		return false
	var card: BoardCard = hand.cards[index] as BoardCard
	var placed: Transform3D = card.global_transform
	hand.card_move_tween_duration = maxf(step.duration, MIN_TWEEN_TIME)
	var removed: Card3D = hand.remove_card(index)
	loose.add_child(removed)
	removed.global_transform = placed
	_forget(card.instance_id)
	fly_out(removed, step.duration)
	return true


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
	flip_down(card, step.duration)
	if step.seat == 0:
		face_down_ids[step.card] = true
		return
	card.instance_id = -1
	var wipe: Tween = card.create_tween()
	var wait: IntervalTweener = wipe.tween_interval(maxf(step.duration, MIN_TWEEN_TIME))
	var done: CallbackTweener = wipe.tween_callback(card.clear_def)
	if wait == null or done == null:
		card.clear_def()


## A card leaves the deck strip for `seat`'s hand. With no strip card to fly (the strip is
## not up) nothing moves here. The strip card is found by its id, else by the pile and place
## the engine names (a card the viewer had only as a back); a viewer's own recovery turns it up.
func recover(step: BoardStep) -> void:
	if strip == null:
		return
	var card: BoardCard = null
	var from_pile: BoardCard = null
	for candidate: Card3D in strip.cards:
		var named: BoardCard = candidate as BoardCard
		if named == null:
			continue
		if step.card >= 0 and named.instance_id == step.card:
			card = named
		var pile_seat: int = named.get_meta(DeckStrip.META_SEAT, -1)
		var pile_place: int = named.get_meta(DeckStrip.META_POSITION, -1)
		if pile_seat == step.from_seat and pile_place == step.slot:
			from_pile = named
	if card == null:
		card = from_pile
	if card == null:
		return
	if step.seat == 0:
		if card.face_down:
			show(card, step)
			_flip_up(card, step.duration)
		if step.card >= 0:
			player_cards[step.card] = card
	move_card(card, strip, _hand_of(step.seat), step.duration)


## The card flies to its owner's hand: face up for the player, face down for the opponent.
func return_card(step: BoardStep) -> void:
	var card: BoardCard = _find_in_row(step.seat, step.card, step.slot)
	if card == null:
		push_warning("Board: a return found no card on seat %d's row" % step.seat)
		return
	var hand: CardCollection3D = _hand_of(step.seat)
	move_card(card, _row_of(step.seat), hand, step.duration)
	if step.seat == 0:
		_forget_flags(card.instance_id)
		return
	# The opponent's copy is a back again; forget which card it was.
	card.instance_id = -1
	flip_down(card, step.duration)
	var wipe: Tween = card.create_tween()
	var wait: IntervalTweener = wipe.tween_interval(maxf(step.duration, MIN_TWEEN_TIME))
	var done: CallbackTweener = wipe.tween_callback(card.clear_def)
	if wait == null or done == null:
		card.clear_def()


## The card leaves the hand off the exit side. The opponent's hand cards are all backs, so
## its discard takes the fan's last card.
func discard(step: BoardStep) -> void:
	var hand: CardCollection3D = _hand_of(step.seat)
	var card: BoardCard = null
	if step.seat == 0:
		card = _player_card(step.card)
	elif not hand.cards.is_empty():
		card = hand.cards[hand.cards.size() - 1] as BoardCard
	if card == null:
		return
	var index: int = hand.cards.find(card)
	if index < 0:
		return
	var placed: Transform3D = card.global_transform
	hand.card_move_tween_duration = maxf(step.duration, MIN_TWEEN_TIME)
	var removed: Card3D = hand.remove_card(index)
	loose.add_child(removed)
	removed.global_transform = placed
	_forget(card.instance_id)
	fly_out(removed, step.duration)


## The opponent's pick glows for the step's time (R53). The card is found by zone and index,
## since a private pick arrives without its id.
func choice_show(step: BoardStep) -> void:
	var own_size: int = _row_of(step.seat).cards.size()
	var spot: CardSpot = RowTargets.resolve(step.zone, step.seat, step.index, own_size)
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
	return player_row if seat == 0 else opponent_row


func _hand_of(seat: int) -> CardCollection3D:
	return player_hand if seat == 0 else opponent_hand


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


## Forgets the id books and the strip, for a new match or a table clear.
func reset() -> void:
	player_cards.clear()
	committed_ids.clear()
	face_down_ids.clear()
	strip = null


# --- Card motions (shared with the board) --------------------------------------------------


## Face text for a card the viewer may see. The card must be in the tree.
func show(card: BoardCard, step: BoardStep) -> void:
	card.instance_id = step.card
	var def: CardDef = null if match_cards == null else match_cards.def_of(step.card)
	if def == null:
		push_warning("Board: no card definition for card %d" % step.card)
		return
	card.show_entry(def, BoardCard.entry_in(_hand_rows(), step.card))


## Takes a card off a row, onto the loose layer where it is, and sweeps it off. The row
## closes the gap.
func _sweep_off_row(seat: int, card: BoardCard, duration: float) -> void:
	var row: CardCollection3D = _row_of(seat)
	var index: int = row.cards.find(card)
	if index < 0:
		return
	var placed: Transform3D = card.global_transform
	row.card_move_tween_duration = maxf(duration, MIN_TWEEN_TIME)
	var removed: Card3D = row.remove_card(index)
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
	_add_tween(tween, mesh, ^"rotation:y", PI, maxf(duration, MIN_TWEEN_TIME))
	var err: int = tween.finished.connect(_flag_face_down.bind(card))
	if err != OK:
		card.face_down = true


func _flip_up(card: BoardCard, duration: float) -> void:
	var mesh: Node3D = card.get_node("CardMesh") as Node3D
	var tween: Tween = card.create_tween()
	_add_tween(tween, mesh, ^"rotation:y", 0.0, maxf(duration, MIN_TWEEN_TIME))
	var err: int = tween.finished.connect(_unflag_face_down.bind(card))
	if err != OK:
		card.face_down = false


func _lift_and_settle(card: BoardCard, duration: float) -> void:
	var mesh: Node3D = card.get_node("CardMesh") as Node3D
	var half: float = maxf(duration, MIN_TWEEN_TIME) / 2.0
	var tween: Tween = card.create_tween()
	_add_tween(tween, mesh, ^"position:z", REVEAL_LIFT, half)
	_add_tween(tween, mesh, ^"position:z", 0.0, half)


## Sweeps a card from where it is to the exit marker and frees it.
func fly_out(card: Card3D, duration: float) -> void:
	_stop_card_tweens(card)
	var tween: Tween = card.create_tween()
	_add_tween(
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


func _add_tween(
	tween: Tween, target: Object, property: NodePath, value: Variant, duration: float
) -> void:
	var tweener: PropertyTweener = tween.tween_property(target, property, value, duration)
	tweener = tweener.set_trans(Tween.TRANS_SINE)
	tweener = tweener.set_ease(Tween.EASE_IN_OUT)
