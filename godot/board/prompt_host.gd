# gdlint: ignore=max-public-methods
class_name PromptHost
extends RefCounted
## The prompt on the table (R55-R57, plan P19): the banner, the glowing cards and the dim. The
## board hands in the collections, the lift and the HUD; the rules stay in PromptRules. It
## holds only the open prompt and the cards it lit.

## Alpha of the glow on an eligible card, and of the dim over the rest of the table.
const GLOW_ALPHA: float = 0.4
const DIM_ALPHA: float = 0.35
## The brighter glow of a card in the multi-select's set (R48).
const SELECTED_GLOW_ALPHA: float = 0.8

var player_hand: CardCollection3D = null
var player_row: CardCollection3D = null
var opponent_row: CardCollection3D = null
var opponent_hand: CardCollection3D = null
var card_lift: CardLift = null
var hud: BoardHud = null
## The board's zone-glow material, copied per card by BoardCard.set_glow.
var glow_material: Material = null
## The match's source (set per match): the action button and the confirm submit through it.
var source: MatchSource = null
## The engine seat the player holds; Pile seats in the strip are table seats (0 = the player).
var viewer: int = 0
## Where the deck strip is built, and the board's card factory.
var strip_parent: Node3D = null
var spawn: Callable = Callable()
## The Crew pool, for a Crew prompt's banner (cycle 8 R66); null reads every prompt as a card's.
var crew_pool: CrewPool = null
## The multi-select's chosen positions in the prompt's zone, ascending (R48).
var selected: Array[int] = []
## The Pile strip of a Pile prompt or a tap on a Pile count, or an idle one.
var strip: DeckStrip = DeckStrip.new()

## The lifted eligible card's option (a zone index); -1 when none is lifted (R47).
var lifted_option: int = -1

var _prompt: Dictionary = {}
## The open prompt with its seat rotated to a table seat (0 = the player), for the spots and
## taps on the table; its options are the engine's own, unchanged.
var _table_prompt: Dictionary = {}
var _lit: Array[BoardCard] = []
## The option each lit card stands for, parallel to _lit.
var _lit_options: Array[int] = []


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


## Opens the prompt: the banner shows `text` (or "Discard N" for the discard-down), each
## eligible card glows, the rest dim. A multi prompt also shows the confirm button, enabled only
## at the legal selection size (R48, R80); a Pile prompt lays out the Pile strip (R78).
## `view` is seat 0's view: its row size splits `both_boards` and its Piles fill the strip.
func open(prompt: Dictionary, text: String, view: SeatView) -> void:
	close()
	_prompt = prompt.duplicate(true)
	_table_prompt = table_prompt(_prompt, viewer)
	selected.clear()
	hud.show_prompt(PromptRules.banner_for(_prompt, text, _crew_name()))
	card_lift.set_rest_alpha(DIM_ALPHA)
	var own_size: int = view.own_board.size()
	var raw_options: Array = _prompt.get("options", [])
	var found: Array[CardSpot] = PromptRules.spots(_table_prompt, own_size)
	for i: int in range(found.size()):
		var spot: CardSpot = found[i]
		var card: BoardCard = card_at(spot)
		if card == null:
			push_warning("PromptHost: no card at seat %d slot %d" % [spot.seat, spot.slot])
			continue
		card.set_glow(glow_material, GLOW_ALPHA)
		_lit.append(card)
		var option: int = raw_options[i] if i < raw_options.size() else -1
		_lit_options.append(option)
	if _chooses_from_strip():
		_open_strip(view)
	if is_multi():
		hud.show_confirm(
			PromptRules.confirm_text(_prompt, 0), PromptRules.confirm_enabled(_prompt, 0)
		)
	if PromptRules.wants_skip(_prompt):
		hud.show_skip(is_multi())


## `prompt` (an engine prompt, its seat an engine seat) with the seat rotated to a table seat
## for the player in engine seat `seat_held` (0 = the player). The options stay the engine's
## own values, so an answer goes back unchanged (R20).
static func table_prompt(prompt: Dictionary, seat_held: int) -> Dictionary:
	var out: Dictionary = prompt.duplicate(true)
	if prompt.is_empty():
		return out
	var seat: int = prompt.get("seat", 0)
	out["seat"] = BoardSteps.table_seat(seat, seat_held)
	return out


func is_multi() -> bool:
	var multi: bool = _prompt.get("multi", false)
	return multi


func strip_up() -> bool:
	return strip.is_up()


## Slides the strip away (PILE_HIDE).
func hide_strip(seconds: float) -> void:
	strip.hide(seconds)


## Forgets the prompt without touching any node, for the board leaving the tree.
func drop() -> void:
	_prompt = {}
	_table_prompt = {}
	lifted_option = -1
	selected.clear()
	_lit.clear()
	_lit_options.clear()
	strip.forget()


## Clears the banner, the glows, the selection and the dim (R57). The strip stays when
## `keep_strip` is set, for a choice that flies a card out of it; a PILE_HIDE step then
## clears it.
func close(keep_strip: bool = false) -> void:
	_prompt = {}
	_table_prompt = {}
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
		return PromptRules.on_tap(table, false, _table_prompt, own_size, lifted_option)
	if strip.has_card(card):
		return PromptRules.route(true, strip.option_of(card), not card.face_down, lifted_option)
	var spot: CardSpot = spot_of(card)
	return PromptRules.on_tap(spot, not card.face_down, _table_prompt, own_size, lifted_option)


## One tap while the prompt is open (R40-R44): lift, swap the lift, or put it down.
func handle_tap(card: BoardCard) -> void:
	var routed: PromptTap = tap(card, source.view().own_board.size())
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
	lift_ended()
	if card_lift != null and card_lift.is_holding():
		await card_lift.put_down(0.0 if instant else CardLift.PUT_DOWN_TIME)


## Forgets the lifted option after the lift ended by any route (R43, R47).
func lift_ended() -> void:
	lifted_option = -1
	if hud != null:
		hud.hide_action()
		hud.set_confirm_suspended(false)


## The action button was pressed (R42, R48): a multi prompt toggles the lifted card in the
## selection and sets it down (false returned); any other submits it and returns true. The
## source answers through its signals.
func press() -> bool:
	var routed: PromptTap = PromptRules.action_tap(_prompt, lifted_option)
	if not is_open() or source == null:
		return false
	if routed.kind == PromptRules.Tap.TOGGLE_SELECT:
		selected = PromptRules.toggled(selected, routed.index)
		_refresh_selection()
		put_down()
		return false
	if routed.kind != PromptRules.Tap.CHOOSE:
		return false
	if strip.is_up() and not strip.may_choose(routed.index):
		return false
	var zone: int = Choice.zone_of(_prompt)
	source.submit_choice(zone, routed.index)
	return true


## The confirm button was pressed (R48): submits the selected positions; false when no multi
## prompt is open or the selection is not the legal size (R80).
func confirm() -> bool:
	if not is_open() or not is_multi() or source == null:
		return false
	if not PromptRules.confirm_enabled(_prompt, selected.size()):
		return false
	var zone: int = Choice.zone_of(_prompt)
	var chosen: Array[int] = []
	chosen.assign(selected)
	source.submit_set(zone, chosen)
	return true


## The Skip button was pressed (R63): declines the open optional prompt; false when none is open.
func skip() -> bool:
	if not is_open() or source == null or not PromptRules.wants_skip(_prompt):
		return false
	source.submit_decline()
	return true


## The open prompt's Crew name, or "" for a card prompt (R66).
## Whether the open prompt's options are in the strip (a Pile or the top of a Deck).
func _chooses_from_strip() -> bool:
	var zone: int = Choice.zone_of(_prompt)
	return PromptRules.is_pile_zone(zone) or PromptRules.is_deck_top_zone(zone)


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
	hud.show_confirm(
		PromptRules.confirm_text(_prompt, selected.size()),
		PromptRules.confirm_enabled(_prompt, selected.size())
	)


## Builds the strip from a Pile prompt (R78): the Piles its zone names in order, each face up,
## the prompt's options glowing. A Delve prompt (own_deck_top) lays out the looked-at top
## cards the same way, read from the view's private `deck_top`.
func _open_strip(view: SeatView) -> void:
	var asked: int = _prompt.get("seat", 0)
	var zone: int = Choice.zone_of(_prompt)
	var seats: Array[int] = PromptRules.pile_seats(zone, asked)
	var options: Array[int] = []
	var raw: Array = _prompt.get("options", [])
	for entry: Variant in raw:
		var option: int = entry
		options.append(option)
	if PromptRules.is_deck_top_zone(zone):
		_show_entries(view.deck_top, options, view)
		return
	_show_piles(seats, options, view)


## The Pile of table seat `seat` face up in the strip with nothing to choose (a tap on its
## count, R78).
## A second tap on the same Pile, or any tap while another strip is up, puts the strip away.
## Nothing while an open prompt chooses from the strip (a Pile or Deck-top zone): hiding it
## would leave that prompt with nothing to choose.
func toggle_pile(seat: int, view: SeatView) -> void:
	if is_open() and _chooses_from_strip():
		return
	if strip.is_up():
		strip.hide(0.25)
		return
	var none: Array[int] = []
	# With two seats the rotation is its own inverse: table seat to engine seat.
	_show_piles([BoardSteps.table_seat(seat, viewer)], none, view)


func _show_piles(seats: Array[int], eligible: Array[int], view: SeatView) -> void:
	var entries: Array[int] = []
	for seat: int in seats:
		entries.append_array(view.pile_of(seat))
	_show_entries(entries, eligible, view)


func _show_entries(entries: Array[int], eligible: Array[int], view: SeatView) -> void:
	var def_of: Callable = Callable()
	if source != null:
		def_of = source.match_cards().def_of
	strip.aspect = _aspect()
	strip.show(
		strip_parent, entries, eligible, spawn, def_of, glow_material, 0.25, _pile_entry.bind(view)
	)


## The viewport's width over height, for the strip's width.
func _aspect() -> float:
	if strip_parent == null or not strip_parent.is_inside_tree():
		return DeckStrip.DEFAULT_ASPECT
	var size: Vector2 = strip_parent.get_viewport().get_visible_rect().size
	return size.x / size.y if size.y > 0.0 else DeckStrip.DEFAULT_ASPECT


## The view's entry of a pile card (cost, stats, grown), or an empty dictionary.
static func _pile_entry(id: int, view: SeatView) -> Dictionary:
	var found: Variant = view.pile_entries.get(id, {})
	if found is Dictionary:
		var entry: Dictionary = found
		return entry
	return {}


func _lift(card: BoardCard, option: int) -> void:
	if card_lift.is_holding() or not is_open():
		return
	# Your own face-down card shows its face in the lift; an opponent's stays a back (R45, R46).
	var own_hidden: bool = (
		card.face_down and not strip.has_card(card) and spot_of(card).seat == BoardSteps.OWN_SIDE
	)
	card_lift.lift(card, own_hidden, option >= 0)
	if option >= 0 and card_lift.is_holding():
		lifted_option = option
		hud.set_confirm_suspended(true)
		hud.show_action(
			PromptRules.action_label_for(_prompt, selected.has(option)), card_lift.button_rect()
		)


func _collection_of(seat: int, in_hand: bool) -> CardCollection3D:
	if seat == BoardSteps.OWN_SIDE:
		return player_hand if in_hand else player_row
	return opponent_hand if in_hand else opponent_row
