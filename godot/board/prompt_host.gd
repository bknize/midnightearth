class_name PromptHost
extends RefCounted
## The prompt on the table (R55-R57, plan P19): the banner, the glowing cards and the dim. The
## board hands in the collections, the lift and the HUD; the rules stay in PromptRules. It
## holds only the open prompt and the cards it lit.

## Alpha of the glow on an eligible card, and of the dim over the rest of the table.
const GLOW_ALPHA: float = 0.55
const DIM_ALPHA: float = 0.35
## The brighter glow of a card in the multi-select's set (R48).
const SELECTED_GLOW_ALPHA: float = 0.95

var player_hand: CardCollection3D = null
var player_row: CardCollection3D = null
var opponent_row: CardCollection3D = null
var opponent_hand: CardCollection3D = null
var card_lift: CardLift = null
var hud: BoardHud = null
## The board's zone-glow material, copied per card by BoardCard.set_glow.
var glow_material: Material = null
## The match's driver (set per match): the action button and the confirm submit through it.
var driver: MatchDriver = null
## Where the deck strip is built, and the board's card factory.
var strip_parent: Node3D = null
var spawn: Callable = Callable()
## The Crew pool, for a Crew prompt's banner (cycle 8 R66); null reads every prompt as a card's.
var crew_pool: CrewPool = null
## The multi-select's chosen positions in the prompt's zone, ascending (R48).
var selected: Array[int] = []
## The deck strip of a recover prompt, or an idle one.
var strip: DeckStrip = DeckStrip.new()

## The lifted eligible card's option (a zone index); -1 when none is lifted (R47).
var lifted_option: int = -1

var _prompt: Dictionary = {}
var _lit: Array[BoardCard] = []
## The option each lit card stands for, parallel to _lit.
var _lit_options: Array[int] = []
## What the strip's callback submitted, for press() to hand back.
var _strip_result: ApplyResult = null


## Hands over the table: the four collections (hand, row, opponent row, opponent hand), the
## lift, the HUD and the zone-glow material.
func wire(table: Array[CardCollection3D], lift: CardLift, p_hud: BoardHud, glow: Material) -> void:
	player_hand = table[0]
	player_row = table[1]
	opponent_row = table[2]
	opponent_hand = table[3]
	card_lift = lift
	hud = p_hud
	glow_material = glow


func is_open() -> bool:
	return not _prompt.is_empty()


## The open prompt: `{seat, card, verb, zone, options}`, or {} when none is open.
func current() -> Dictionary:
	return _prompt


## Opens the prompt: the banner shows `text`, each eligible card glows, the rest dim. A multi
## prompt also shows the confirm button (R48), a pile prompt lays out the deck strip (R47).
## `view` is seat 0's view: its row size splits `both_boards` and its piles fill the strip.
func open(prompt: Dictionary, text: String, view: SeatView) -> void:
	close()
	_prompt = prompt.duplicate(true)
	selected.clear()
	hud.show_prompt(PromptRules.banner_text(text, _crew_name()))
	card_lift.set_rest_alpha(DIM_ALPHA)
	var own_size: int = view.own_board.size()
	for spot: CardSpot in PromptRules.spots(_prompt, own_size):
		var card: BoardCard = card_at(spot)
		if card == null:
			push_warning("PromptHost: no card at seat %d slot %d" % [spot.seat, spot.slot])
			continue
		card.set_glow(glow_material, GLOW_ALPHA)
		_lit.append(card)
		_lit_options.append(PromptRules.option_at(spot, _prompt, own_size))
	if Choice.zone_of(_prompt) == Choice.Zone.BOTH_PILES:
		_open_strip(view)
	if is_multi():
		hud.show_confirm(PromptRules.confirm_text(_prompt, 0))
	if PromptRules.wants_skip(_prompt):
		hud.show_skip(is_multi())


func is_multi() -> bool:
	var multi: bool = _prompt.get("multi", false)
	return multi


func strip_up() -> bool:
	return strip.is_up()


## The strip's collection for the effect player, or null while there is none.
func strip_collection() -> CardCollection3D:
	return strip.collection if strip.is_up() else null


## Slides the strip away (STRIP_HIDE).
func hide_strip(seconds: float) -> void:
	strip.hide(seconds)


## Forgets the prompt without touching any node, for the board leaving the tree.
func drop() -> void:
	_prompt = {}
	lifted_option = -1
	selected.clear()
	_lit.clear()
	_lit_options.clear()
	strip = DeckStrip.new()


## Clears the banner, the glows, the selection and the dim (R57). The strip stays when
## `keep_strip` is set, for the recovery that flies a card out of it; a STRIP_HIDE step then
## clears it.
func close(keep_strip: bool = false) -> void:
	_prompt = {}
	lifted_option = -1
	selected.clear()
	if hud != null:
		hud.hide_action()
		hud.hide_confirm()
		hud.hide_skip()
	for card: BoardCard in _lit:
		if is_instance_valid(card):
			card.set_selected(false)
			card.clear_glow()
	_lit.clear()
	_lit_options.clear()
	if not keep_strip:
		strip.hide(0.0)
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
	if strip.has_card(card):
		return PromptRules.route(true, strip.option_of(card), not card.face_down, lifted_option)
	var spot: CardSpot = spot_of(card)
	return PromptRules.on_tap(spot, not card.face_down, _prompt, own_size, lifted_option)


## One tap while the prompt is open (R40-R44): lift, swap the lift, or put it down.
func handle_tap(card: BoardCard) -> void:
	var routed: PromptTap = tap(card, driver.view().own_board.size())
	await apply_tap(routed, card)


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
## `instant` drops it with no flight, for a card whose strip is about to go.
func put_down(instant: bool = false) -> void:
	lifted_option = -1
	if hud != null:
		hud.hide_action()
		hud.set_confirm_suspended(false)
	if card_lift != null and card_lift.is_holding():
		await card_lift.put_down(0.0 if instant else CardLift.PUT_DOWN_TIME)


## Forgets the lifted option after the lift ended by any route (R43, R47).
func lift_ended() -> void:
	lifted_option = -1
	if hud != null:
		hud.hide_action()
		hud.set_confirm_suspended(false)


## The action button was pressed (R42, R48): a multi prompt toggles the lifted card in the
## selection and sets it down (null returned); any other submits it and returns the result.
func press() -> ApplyResult:
	var routed: PromptTap = PromptRules.action_tap(_prompt, lifted_option)
	if not is_open() or driver == null:
		return null
	if routed.kind == PromptRules.Tap.TOGGLE_SELECT:
		selected = PromptRules.toggled(selected, routed.index)
		_refresh_selection()
		put_down()
		return null
	if routed.kind != PromptRules.Tap.CHOOSE:
		return null
	if strip.is_up():
		# A strip entry is picked through the strip's callback, which submits it.
		_strip_result = null
		if not strip.choose(routed.index):
			return null
		return _strip_result
	return driver.submit_choice(Choice.zone_of(_prompt), routed.index)


## The confirm button was pressed (R48): submits the selected positions; null when no multi
## prompt is open.
func confirm() -> ApplyResult:
	if not is_open() or not is_multi() or driver == null:
		return null
	var chosen: Array[int] = []
	chosen.assign(selected)
	return driver.submit_set(Choice.zone_of(_prompt), chosen)


## The Skip button was pressed (R63): declines the open optional prompt; null when none is open.
func skip() -> ApplyResult:
	if not is_open() or driver == null or not PromptRules.wants_skip(_prompt):
		return null
	return driver.submit_decline()


## The open prompt's Crew name, or "" for a card prompt (R66).
func _crew_name() -> String:
	var crew_id: String = _prompt.get("crew", "")
	if crew_id == "" or crew_pool == null:
		return ""
	var def: CrewDef = crew_pool.crew_of(crew_id)
	return "" if def == null else def.name


func _refresh_selection() -> void:
	for i: int in range(_lit.size()):
		var card: BoardCard = _lit[i]
		if not is_instance_valid(card):
			continue
		var chosen: bool = selected.has(_lit_options[i])
		card.set_selected(chosen)
		card.set_glow(glow_material, SELECTED_GLOW_ALPHA if chosen else GLOW_ALPHA)
	hud.show_confirm(PromptRules.confirm_text(_prompt, selected.size()))


## Builds the deck strip from a Pile prompt: seat 0's Pile then the opponent's (R47).
func _open_strip(view: SeatView) -> void:
	var entries: Array[int] = []
	var piles: Array[Vector2i] = []
	for i: int in range(view.own_pile.size()):
		entries.append(view.own_pile[i])
		piles.append(Vector2i(0, i))
	for i: int in range(view.opponent_pile.size()):
		entries.append(view.opponent_pile[i])
		piles.append(Vector2i(1, i))
	var options: Array[int] = []
	var raw: Array = _prompt.get("options", [])
	for entry: Variant in raw:
		var option: int = entry
		options.append(option)
	var def_of: Callable = Callable()
	if driver != null:
		def_of = driver.match_cards().def_of
	strip.show(
		strip_parent,
		entries,
		options,
		spawn,
		def_of,
		glow_material,
		_on_strip_choice,
		0.25,
		piles,
		_pile_entry.bind(view)
	)


## The view's entry of a pile card (cost, stats, grown), or an empty dictionary.
static func _pile_entry(id: int, view: SeatView) -> Dictionary:
	var found: Variant = view.pile_entries.get(id, {})
	if found is Dictionary:
		var entry: Dictionary = found
		return entry
	return {}


func _on_strip_choice(index: int) -> void:
	_strip_result = driver.submit_choice(Choice.zone_of(_prompt), index)


func _lift(card: BoardCard, option: int) -> void:
	if card_lift.is_holding() or not is_open():
		return
	# Your own face-down card shows its face in the lift; an opponent's stays a back (R45, R46).
	var own_hidden: bool = card.face_down and not strip.has_card(card) and spot_of(card).seat == 0
	card_lift.lift(card, own_hidden, option >= 0)
	if option >= 0 and card_lift.is_holding():
		lifted_option = option
		hud.set_confirm_suspended(true)
		hud.show_action(
			PromptRules.action_label_for(_prompt, selected.has(option)), card_lift.button_rect()
		)


func _collection_of(seat: int, in_hand: bool) -> CardCollection3D:
	if seat == 0:
		return player_hand if in_hand else player_row
	return opponent_hand if in_hand else opponent_row
