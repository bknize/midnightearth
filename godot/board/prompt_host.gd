class_name PromptHost
extends RefCounted
## The prompt on the table (R55-R57, plan P19): the banner, the glowing cards and the dim. The
## board hands in the collections, the lift and the HUD; the rules stay in PromptRules. It
## holds only the open prompt and the cards it lit.

## Alpha of the glow on an eligible card, and of the dim over the rest of the table.
const GLOW_ALPHA: float = 0.55
const DIM_ALPHA: float = 0.35

var player_hand: CardCollection3D = null
var player_row: CardCollection3D = null
var opponent_row: CardCollection3D = null
var opponent_hand: CardCollection3D = null
var card_lift: CardLift = null
var hud: BoardHud = null
## The board's zone-glow material, copied per card by BoardCard.set_glow.
var glow_material: Material = null

## The lifted eligible card's option (a zone index); -1 when none is lifted (R47).
var lifted_option: int = -1

var _prompt: Dictionary = {}
var _lit: Array[BoardCard] = []


func is_open() -> bool:
	return not _prompt.is_empty()


## The open prompt: `{seat, card, verb, zone, options}`, or {} when none is open.
func current() -> Dictionary:
	return _prompt


## Opens the prompt: the banner shows `text`, each eligible card glows, the rest dim.
func open(prompt: Dictionary, text: String, own_size: int) -> void:
	close()
	_prompt = prompt.duplicate(true)
	hud.show_prompt(text)
	card_lift.set_rest_alpha(DIM_ALPHA)
	for spot: CardSpot in PromptRules.spots(_prompt, own_size):
		var card: BoardCard = card_at(spot)
		if card == null:
			push_warning("PromptHost: no card at seat %d slot %d" % [spot.seat, spot.slot])
			continue
		card.set_glow(glow_material, GLOW_ALPHA)
		_lit.append(card)


## Forgets the prompt without touching any node, for the board leaving the tree.
func drop() -> void:
	_prompt = {}
	lifted_option = -1
	_lit.clear()


## Clears the banner, the glows and the dim (R57).
func close() -> void:
	_prompt = {}
	lifted_option = -1
	if hud != null:
		hud.hide_action()
	for card: BoardCard in _lit:
		if is_instance_valid(card):
			card.clear_glow()
	_lit.clear()
	if hud != null:
		hud.hide_prompt()
	if card_lift != null:
		card_lift.set_rest_alpha(0.0)


## The card at a spot, by position in the collection; null when none sits there.
func card_at(spot: CardSpot) -> BoardCard:
	var collection: CardCollection3D = _collection_of(spot.seat, spot.in_hand)
	if spot.slot < 0 or spot.slot >= collection.cards.size():
		return null
	return collection.cards[spot.slot] as BoardCard


## Where a card sits (absolute seat, hand or row, index), or an invalid spot.
func spot_of(card: BoardCard) -> CardSpot:
	for seat: int in range(2):
		var in_hand: int = _collection_of(seat, true).cards.find(card)
		if in_hand >= 0:
			return CardSpot.new(seat, true, in_hand)
		var on_row: int = _collection_of(seat, false).cards.find(card)
		if on_row >= 0:
			return CardSpot.new(seat, false, on_row)
	return CardSpot.new()


## What a tap on `card` does while the prompt is open. `own_size` is seat 0's row size.
func tap(card: BoardCard, own_size: int) -> PromptTap:
	if card == null:
		var table: CardSpot = CardSpot.new()
		return PromptRules.on_tap(table, false, _prompt, own_size, lifted_option)
	var spot: CardSpot = spot_of(card)
	return PromptRules.on_tap(spot, not card.face_down, _prompt, own_size, lifted_option)


## Acts on a routed tap (R40-R44): lifts the card with the button, lifts it to read, or puts
## the lift down. Awaitable; a put-down finishes first when one card replaces another.
func apply_tap(routed: PromptTap, card: BoardCard) -> void:
	match routed.kind:
		PromptRules.Tap.PUT_DOWN:
			await put_down()
		PromptRules.Tap.LIFT_ELIGIBLE, PromptRules.Tap.SWAP_LIFT:
			await put_down()
			_lift(card, routed.index)
		PromptRules.Tap.LIFT:
			await put_down()
			_lift(card, -1)


## Sets the lift down with the prompt still waiting: the button goes, the option is forgotten.
func put_down() -> void:
	lifted_option = -1
	if hud != null:
		hud.hide_action()
	if card_lift != null and card_lift.is_holding():
		await card_lift.put_down()


## Forgets the lifted option after the lift ended by any route (R43, R47).
func lift_ended() -> void:
	lifted_option = -1
	if hud != null:
		hud.hide_action()


func _lift(card: BoardCard, option: int) -> void:
	if card_lift.is_holding() or not is_open():
		return
	# Your own face-down card shows its face in the lift; an opponent's stays a back (R45, R46).
	card_lift.lift(card, card.face_down and spot_of(card).seat == 0)
	if option >= 0 and card_lift.is_holding():
		lifted_option = option
		hud.show_action(PromptRules.action_label_for(_prompt))


func _collection_of(seat: int, in_hand: bool) -> CardCollection3D:
	if seat == 0:
		return player_hand if in_hand else player_row
	return opponent_hand if in_hand else opponent_row
