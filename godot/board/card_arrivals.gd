class_name CardArrivals
extends RefCounted
## Cards that arrive on the table (split out of Board at DC-14 T15): a deal or draw into a fan,
## the opponent's and the player's commit onto a row, and milestone B's created cards (Dross
## into a hand, Twin's copy on a row) and a Pile card placed on a row (Revive). It plays on the
## EffectPlayer's collections and id books; it owns nothing.

## Seconds at 1x for a player commit to slide onto the row when it is not already there.
const PLAYER_COMMIT_TIME: float = 0.25

var fx: EffectPlayer = null
## The Pile strip, owned by the prompt host.
var strip: DeckStrip = null
## Where cards enter from.
var entry_marker: Marker3D = null
## Returns a fresh BoardCard.
var spawn: Callable = Callable()


## A DEAL or DRAW (and a created card going to a hand): the card sweeps from the entry into
## the fan. The viewer's shows its face; the opponent's is a back (a count).
func deal(step: BoardStep) -> void:
	var hand: CardCollection3D = (
		fx.player_hand if step.seat == BoardSteps.OWN_SIDE else fx.opponent_hand
	)
	var card: BoardCard = _make()
	if card == null:
		return
	hand.card_move_tween_duration = maxf(step.duration, EffectPlayer.MIN_TWEEN_TIME)
	hand.append_card(card)
	card.global_position = entry_marker.global_position
	if step.seat == BoardSteps.OWN_SIDE:
		fx.show(card, step)
		fx.player_cards[step.card] = card
	else:
		card.face_down = true


## The opponent's commit: backs slide from its fan onto its row, in slot order (R47).
func opponent_commit(step: BoardStep) -> void:
	var each: float = step.duration / float(maxi(step.count, 1))
	for k: int in RowSlots.order_by_slot(step.slots, step.count):
		if fx.opponent_hand.cards.is_empty():
			push_warning("Board: the opponent committed more cards than its fan holds")
			return
		var card: Card3D = fx.opponent_hand.cards[fx.opponent_hand.cards.size() - 1]
		var at: int = step.slots[k] if k < step.slots.size() else -1
		fx.move_card(card, fx.opponent_hand, fx.opponent_row, each, at)


## Autoplay: the committed cards are still in the hand and slide to their slots. Player mode:
## they were staged on the row already. Either way every one flips face down in place (R46)
## and is remembered, so the walk's flip pulse turns it up again.
func player_commit(step: BoardStep, speed: float) -> void:
	var raw: Array = step.source.payload["cards"]
	var ids: Array[int] = []
	ids.assign(raw)
	for k: int in RowSlots.order_by_slot(step.slots, ids.size()):
		var id: int = ids[k]
		fx.committed_ids[id] = true
		if not fx.player_cards.has(id):
			continue
		var card: BoardCard = fx.player_cards[id]
		if not fx.player_row.cards.has(card):
			var at: int = step.slots[k] if k < step.slots.size() else -1
			fx.move_card(card, fx.player_hand, fx.player_row, PLAYER_COMMIT_TIME / speed, at)
		fx.face_down_ids[id] = true
		fx.flip_down(card, step.duration)


## CARD_CREATED onto a row (Twin's copy): a face-up card appears at its slot. The viewer's own
## is remembered as played, so it never drags or counts as staged.
func create_on_row(step: BoardStep) -> void:
	var card: BoardCard = _land(step, entry_marker.global_position)
	if card == null:
		return
	card.instance_id = step.card
	if step.seat == BoardSteps.OWN_SIDE:
		fx.player_cards[step.card] = card
		fx.committed_ids[step.card] = true
	fx.show(card, step, fx.row_entry(step.seat, step.card))


## CARD_PLACED (Revive): the Pile card lands face down on the row at its slot, flying from the
## strip if it is up (the strip card goes), else from the exit side. The viewer's own is
## remembered as committed and face down, so its reveal flips it up.
func place(step: BoardStep) -> void:
	var start: Vector3 = fx.exit_marker.global_position
	var from_strip: Card3D = _strip_card(step.card)
	if from_strip != null:
		start = from_strip.global_position
		strip.drop_card(from_strip)
	var card: BoardCard = _land(step, start)
	if card == null:
		return
	card.face_down = true
	if step.seat == BoardSteps.OWN_SIDE:
		card.instance_id = step.card
		fx.player_cards[step.card] = card
		fx.committed_ids[step.card] = true
		fx.face_down_ids[step.card] = true
		fx.show(card, step, fx.row_entry(0, step.card))
	else:
		card.instance_id = -1


## PILE_SHUFFLED_IN with `pile_cards` (Exhume): the Pile strip's cards that went into the
## Deck leave the strip, so the prompt that follows (the next pick) lists what is left.
func shuffle_in(step: BoardStep) -> void:
	for id: int in step.cards:
		var held: Card3D = _strip_card(id)
		if held == null:
			continue
		strip.drop_card(held)


## A new card inserted at the step's slot of its seat's row, starting at `start`.
func _land(step: BoardStep, start: Vector3) -> BoardCard:
	var row: CardCollection3D = (
		fx.player_row if step.seat == BoardSteps.OWN_SIDE else fx.opponent_row
	)
	var card: BoardCard = _make()
	if card == null:
		return null
	row.card_move_tween_duration = maxf(step.duration, EffectPlayer.MIN_TWEEN_TIME)
	if step.slot < 0:
		row.append_card(card)
	else:
		row.insert_card(card, RowSlots.insert_index(step.slot, row.cards.size()))
	card.global_position = start
	return card


## The Pile strip's card showing instance `id`, or null.
func _strip_card(id: int) -> Card3D:
	return null if strip == null else strip.card_of(id)


func _make() -> BoardCard:
	var raw: Object = spawn.call()
	return raw as BoardCard
