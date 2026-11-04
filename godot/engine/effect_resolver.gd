class_name EffectResolver
extends RefCounted
## Applies one card effect to a MatchState (R19-R27, plan P6-P8, P11, P14). Pure: no
## nodes, no clock; the only randomness is the engine stream passed in.
##
## apply() handles one verb per branch and returns an Outcome: the events the firing caused,
## in order, always starting with EFFECT_FIRED {seat, card, verb, trigger} (verb and trigger
## as their CardEffect JSON names), and the prompt the verb needs (empty unless a prompt
## verb found two or more targets on a live walk). ScoreWalk decides when an effect fires
## (the trigger hooks, P6) and forwards the events to its sink on a live walk; a preview
## drops them.
##
## Verbs here:
## - DRAW (amount): draws for the owner; a draw at the hand cap is burned (R25). Same
##   events, owners and privacy as the turn-start draw (CARD_DRAWN, CARD_BURNED).
## - FREE_FIRST_NEXT_TURN: sets `energy.free_first[owner]`, FREE_FIRST_SET {seat}. It fires
##   during a walk, after both commits, so the owner's next commit is the next turn's; that
##   commit consumes it whether or not it uses it, so an unused free card is lost (P7).
## - OPPONENT_NEXT_NO_BONUS (DC-05's OPPONENT_NEXT_BONUS_ZERO, renamed at DC-07 T01):
##   sets `bonus_zero_pending[opponent]` (no stacking, R22), BONUS_ZERO_SET {seat: the
##   opponent}. spend_bonus_zero() spends it on that seat's next reveal, in this walk or a
##   later one.
## - DESTROY_RANDOM_OPPONENT: picks one live (not yet destroyed) card of the opponent's row
##   (P11, R27; DC-06 R16) and destroys it through destroy() (DC-07 P9). A row with no live
##   card fizzles (R26, DC-06 R17) and draws nothing from the stream. clear_destroyed()
##   takes a destroyed card to its owner's destroyed pile at turn end (DC-07 R16).
## - The Ruin verbs (DC-07 T06, P8, P10, P12, R26, R27): DESTROY_LEFTMOST_OWN and BURST are
##   RuinEffects' (no prompt); DISCARD_OWN, DESTROY_OWN_THEN_DRAW and
##   DESTROY_OWN_THEN_FLAT_UP are prompt verbs (below). UNREVEAL_INSTEAD is an ongoing
##   marker read by destroy(); it never fires.
## - FLAT_UP_ON_SCORE (amount): `flat_delta += amount`, STATS_CHANGED (cause flat_up).
## - CARRY_ENERGY (ongoing): `carry[owner] = budget - spent[owner]`, ENERGY_CARRIED
##   {seat, amount}. Only settle_energy() fires it, at turn end.
## - The prompt verbs (DC-05 T05; R20, R26, R28-R34, plan P9, P10). Choice.eligible() lists
##   the targets. With none the effect fizzles (EFFECT_FIZZLED {seat, card, verb}); with one
##   it is chosen at once (CHOICE_MADE with `auto` true) and applied; with two or more the
##   Outcome carries the prompt {seat, card, verb, zone, options, multi: false} and the
##   event CHOICE_REQUESTED {seat, card, verb, text, zone, options, multi} (zone by name,
##   options as positions: public). answer() applies the choice later. A preview (non-null
##   policy) never prompts: it takes the first option at once (plan P12).
## - The multi-select verb SACRIFICE_DESTROY (DC-07 P7, P12, R22-R25, R27): the same, but
##   the prompt and CHOICE_REQUESTED carry `multi` true, one eligible position still
##   prompts (the empty set is a legal answer), and answer_set() applies a set (apply_set).
##   A preview declines it (PreviewPolicy.set_for, the empty set): the effect fizzles.
##   - DRAW_THEN_DISCARD (amount): draws `amount` as DRAW does (burns at the cap), then
##     discards one card of the owner's hand to its burn pile: CARD_DISCARDED {seat, card},
##     private to the owner.
##   - SWAP_PLACES: the source and another card of the owner's row exchange slots: two
##     CARD_MOVED {seat, card, from_slot, to_slot}, the source's first. A face-down card's
##     move is private to its seat. The walk's slot cursor decides what scores next
##     (DC-06 R5-R11, C23): a card moved behind the cursor is not reached again this walk,
##     a card moved ahead of it is pulsed again there, and the pulse running the swap
##     scores the card that landed on its slot (revealing it first if face down), not the
##     source.
##   - DISCARD_OWN (DC-07 R27, C17): one card of the owner's hand to its burn pile, as
##     DRAW_THEN_DISCARD's discard (CARD_DISCARDED, private). An empty hand fizzles and the
##     card still scores. Every table row has amount 1: one choice, one discard.
##   - DESTROY_OWN_THEN_DRAW (amount), DESTROY_OWN_THEN_FLAT_UP: the chosen own card goes
##     through destroy(), then the owner draws `amount` (RuinEffects.destroy_then_draw) or
##     the source gains the target's effective flat as read before the destroy
##     (RuinEffects.destroy_then_flat_up; STATS_CHANGED cause flat_up).
##   - RETURN_AT_TURN_END: sets the target's CardState.return_marked; resolve_returns()
##     takes it back to its owner's hand at turn end, or burns it at the cap (R24, R25);
##     a marked card destroyed by then is discarded by clear_destroyed() instead (DC-06
##     R19).
##   - RECOVER_DESTROYED (DC-07 R19-R21, P12): the zone is BOTH_DESTROYED, every position.
##     The chosen card leaves its pile (and its public identity with it) for the chooser's
##     hand, with printed stats and no marks (its CardState went when it left the row):
##     CARD_RECOVERED {seat: the chooser, its new controller, card, from_seat, position},
##     `position` its index in `from_seat`'s pile. Public when the card's identity was
##     (`destroyed_known`), else private to the chooser, so the other seat sees the seat,
##     the pile and the position but not the card. At the hand cap the card is burned as a
##     draw at the cap is (R12, R25): CARD_RECOVERED (the card still leaves the pile) and
##     then CARD_BURNED {seat, card} with the same owner, the card in the chooser's burn
##     pile. A recovered opponent card plays and scores for the chooser (its controller,
##     MatchState.controller_of) and goes back to its origin's deck at round start.
##   CHOICE_MADE {seat, card, zone, index, target, auto} is private to the seat holding the
##   target when the zone is a hand or the target is face down (R30, R34); MatchEvent
##   redaction then hides `target` (only) from the other seat. In a destroyed-pile zone it
##   is private to the chooser unless the target's identity is public (as CARD_RECOVERED).
##
## The destroy pipeline (DC-07 P9, R30-R32, C9, C18): every destroy, random or chosen, own
## or opponent, goes through destroy(). A revealed, live card carrying the ongoing
## UNREVEAL_INSTEAD is un-revealed instead: it leaves the revealed set, its CardState goes
## (printed stats, no marks), STATS_CHANGED (cause unreveal) when that changed its shown
## stats, then CARD_UNREVEALED {seat, card, slot}, both public, and it stays in its slot,
## live. Any other card is marked destroyed in place (DC-06 R12) with CARD_DESTROYED. Both
## count as destroyed for the effect (true). The cursor treats an un-revealed card as any
## face-down card: ahead of the cursor it reveals in full when reached (DC-06 R5, C24),
## behind it it stays down until the next walk (R8). Only the carrier is protected (C18).
##
## Hidden information on destroy (orchestrator, DC-05 T04; DC-06 R20, R21): instance ids
## map to card definitions, so naming a face-down card would leak it. When the destroyed
## card is still unrevealed, CARD_DESTROYED is private to the card's seat: MatchEvent
## redaction hides `card` from the other seat while `seat` and `slot` stay visible. A
## revealed card's destroy is public. The card stays face down until the cursor reaches it,
## and DESTROYED_CLEARED follows the same rule at turn end: private while never revealed.
##
## Preview seam (orchestrator, DC-05 T04): a null `policy` is a live walk, which always picks
## the destroyed card with MatchRng.pick_index on the engine stream at the moment the effect
## fires; walk order is deterministic given the log, so a replay destroys the same card. A
## non-null policy is a preview (plan P12): PreviewPolicy.destroy_slot, the opponent's
## lowest-flat card (effective flat, leftmost on a tie), with no stream. A live walk given no
## stream (`rng` null, as unit tests do) takes the preview's rule rather than fail. A
## preview's prompt takes PreviewPolicy.option_for (its first option), and a preview's
## Outcome is quiet: the events a preview would drop are not built where avoidable.

const CAUSE_FLAT_UP: String = "flat_up"
const CAUSE_BONUS_ZERO: String = "bonus_zero"
## A card's `temp_plus` changed (DC-07 P5): cleared at the walk's end.
const CAUSE_TEMP_PLUS: String = "temp_plus"
## A card's CardState went with an un-reveal (DC-07 P9): printed stats again.
const CAUSE_UNREVEAL: String = "unreveal"
const KEY_SEAT: String = "seat"
const KEY_CARD: String = "card"
const KEY_VERB: String = "verb"
const PUBLIC: int = MatchEvent.PUBLIC


## The effect of `card` (an instance id, MatchCards.def_of), or null for a vanilla card or
## unknown id.
static func effect_of(card: int, cards: MatchCards) -> CardEffect:
	if cards == null or card < 0:
		return null
	var def: CardDef = cards.def_of(card)
	if def == null:
		return null
	return def.effect


## Fires `card`'s effect for its owner `seat`: EFFECT_FIRED, then the verb's own events. An
## empty Outcome when the card has no effect. `rng` is the engine stream (a live walk) and
## `policy` is null on a live walk (see the class comment).
static func apply(
	state: MatchState, cards: MatchCards, rng: MatchRng, policy: PreviewPolicy, seat: int, card: int
) -> Outcome:
	var outcome: Outcome = Outcome.new()
	# A preview drops every event, so it builds none it can avoid (DC-05 T06).
	outcome.quiet = policy != null
	var effect: CardEffect = effect_of(card, cards)
	if effect == null:
		return outcome
	if not outcome.quiet:
		var fired: Dictionary = {
			"seat": seat,
			"card": card,
			"verb": CardEffect.verb_name(effect.verb),
			"trigger": CardEffect.trigger_name(effect.trigger),
		}
		outcome.add(MatchEvent.Kind.EFFECT_FIRED, fired)
	match effect.verb:
		CardEffect.Verb.DRAW:
			_draw(state, seat, effect.amount, outcome)
		CardEffect.Verb.FREE_FIRST_NEXT_TURN:
			_free_first(state, seat, outcome)
		CardEffect.Verb.OPPONENT_NEXT_NO_BONUS:
			_mark_bonus_zero(state, seat, outcome)
		CardEffect.Verb.DESTROY_RANDOM_OPPONENT:
			_destroy_random(state, cards, rng, policy, seat, card, outcome)
		CardEffect.Verb.FLAT_UP_ON_SCORE:
			_flat_up(state, cards, seat, card, effect.amount, outcome)
		CardEffect.Verb.CARRY_ENERGY:
			_carry(state, seat, outcome)
		CardEffect.Verb.DRAW_THEN_DISCARD:
			_draw(state, seat, effect.amount, outcome)
			_ask(state, cards, policy, seat, card, effect, outcome)
		CardEffect.Verb.SWAP_PLACES, CardEffect.Verb.RETURN_AT_TURN_END:
			# A target, then the verb.
			_ask(state, cards, policy, seat, card, effect, outcome)
		CardEffect.Verb.DISCARD_OWN, CardEffect.Verb.DESTROY_OWN_THEN_DRAW:
			# A card of the owner's hand or row (DC-07 P12), then the verb.
			_ask(state, cards, policy, seat, card, effect, outcome)
		CardEffect.Verb.DESTROY_OWN_THEN_FLAT_UP:
			_ask(state, cards, policy, seat, card, effect, outcome)
		CardEffect.Verb.DESTROY_LEFTMOST_OWN:
			RuinEffects.destroy_leftmost(state, cards, seat, card, outcome)
		CardEffect.Verb.BURST:
			RuinEffects.burst(state, cards, rng, policy, seat, card, outcome)
		CardEffect.Verb.RECOVER_DESTROYED:
			# A card from either destroyed pile (DC-07 P12), then the recovery.
			_ask(state, cards, policy, seat, card, effect, outcome)
		CardEffect.Verb.SACRIFICE_DESTROY:
			# A set of own live cards (DC-07 P7, P12), then as many random destroys.
			_ask_set(state, cards, rng, policy, seat, card, effect, outcome)
		_:
			# UNREVEAL_INSTEAD (read by destroy()) and the Drift verbs until T07 gives them
			# behaviour: EFFECT_FIRED and nothing else.
			pass
	return outcome


## The turn-start and effect draw (R12, R25): the top of `seat`'s deck goes to its hand, or
## to its burn pile when the hand is at the cap. The private CARD_DRAWN or CARD_BURNED
## {seat, card} owned by `seat`, or null when the deck is empty (nothing changes then).
static func draw_card(state: MatchState, seat: int) -> MatchEvent:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if piles.deck.is_empty():
		return null
	var card: int = piles.deck[0]
	piles.deck.remove_at(0)
	if piles.hand.size() >= MatchRules.HAND_CAP:
		piles.burned.append(card)
		return MatchEvent.new(MatchEvent.Kind.CARD_BURNED, {"seat": seat, "card": card}, seat)
	piles.hand.append(card)
	return MatchEvent.new(MatchEvent.Kind.CARD_DRAWN, {"seat": seat, "card": card}, seat)


## The no-bonus mark on `seat` (R22; DC-07 R14), at the reveal of its `card`: when the mark
## is set, the card has no bonus (×1.00, +0) while it stays on the board
## (CardState.no_bonus), the mark is spent and STATS_CHANGED (cause bonus_zero) is
## returned. Empty when no mark is set.
## ScoreWalk calls it right after CARD_REVEALED, before the card's effects and its score.
static func spend_bonus_zero(
	state: MatchState, cards: MatchCards, seat: int, card: int
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	if not state.bonus_zero_pending[seat]:
		return out
	state.bonus_zero_pending[seat] = false
	state.card_state_for(card).no_bonus = true
	out.append(stats_changed(state, cards, seat, card, CAUSE_BONUS_ZERO))
	return out


## Per-seat energy at turn end (plan P7, P14): for each seat, when a revealed, live card
## with the ongoing CARRY_ENERGY effect is on its row, that card fires (EFFECT_FIRED, then
## ENERGY_CARRIED) and `carry[seat] = budget - spent[seat]`; otherwise `carry[seat] = 0`.
## One firing per seat however many such cards it holds (the leftmost fires). A destroyed
## or returned carry card is gone from the row by now, so it carries nothing (DC-06 R15).
static func settle_energy(state: MatchState, cards: MatchCards) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for seat: int in range(state.seats.size()):
		var carrier: int = _carrier(state, cards, seat)
		if carrier < 0:
			state.energy.carry[seat] = 0
			continue
		out.append_array(apply(state, cards, null, null, seat, carrier).events)
	return out


## Answers the open prompt of `state` with position `index` of its zone (plan P3, R32):
## clears the prompt, then applies the choice (apply_choice, `auto` false). The caller has
## checked the index is one of the options (Choice.is_offered). Empty when no prompt is
## open. The walk resumes with the next ScoreWalk.step().
static func answer(state: MatchState, cards: MatchCards, index: int) -> Array[MatchEvent]:
	var prompt: Dictionary = state.prompt
	state.prompt = {}
	if prompt.is_empty():
		var none: Array[MatchEvent] = []
		return none
	return apply_choice(state, cards, prompt, index, false)


## Applies `prompt`'s verb to position `index` of its zone: CHOICE_MADE, then the verb's
## own events (see the class comment). Empty when the position names no card.
static func apply_choice(
	state: MatchState, cards: MatchCards, prompt: Dictionary, index: int, auto: bool
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var seat: int = prompt.get(KEY_SEAT, -1)
	var source: int = prompt.get(KEY_CARD, -1)
	var verb: int = prompt.get(KEY_VERB, -1)
	var zone: int = prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var target: int = Choice.resolve(state, seat, zone, index)
	var holder: int = Choice.seat_at(state, seat, zone, index)
	if target < 0 or holder < 0:
		return out
	var owner: int = _choice_owner(state, seat, zone, holder, target)
	var made: Dictionary = {
		"seat": seat,
		"card": source,
		"zone": Choice.zone_name(zone),
		"index": index,
		"target": target,
		"auto": auto,
	}
	out.append(MatchEvent.new(MatchEvent.Kind.CHOICE_MADE, made, owner))
	match verb:
		CardEffect.Verb.DRAW_THEN_DISCARD:
			out.append(_discard(state, holder, target))
		CardEffect.Verb.SWAP_PLACES:
			out.append_array(_swap(state, holder, source, target))
		CardEffect.Verb.RETURN_AT_TURN_END:
			state.card_state_for(target).return_marked = true
		CardEffect.Verb.RECOVER_DESTROYED:
			var position: int = Choice.local_index(state, seat, zone, index)
			out.append_array(_recover(state, seat, holder, target, position))
		CardEffect.Verb.DISCARD_OWN:
			out.append(_discard(state, holder, target))
		CardEffect.Verb.DESTROY_OWN_THEN_DRAW:
			var amount: int = _amount_of(source, cards)
			out.append_array(RuinEffects.destroy_then_draw(state, cards, holder, target, amount))
		CardEffect.Verb.DESTROY_OWN_THEN_FLAT_UP:
			out.append_array(RuinEffects.destroy_then_flat_up(state, cards, holder, source, target))
	return out


## Answers the open multi-select prompt of `state` with the set `indices` of its zone
## (DC-07 P7, R24): clears the prompt, then applies the set (apply_set). The caller has
## checked the set (Choice.is_valid_set). `rng` and `policy` are as apply()'s: the engine
## stream on a live walk, the preview policy (and no stream) on a preview. Empty when no
## prompt is open. The walk resumes with the next ScoreWalk.step().
static func answer_set(
	state: MatchState, cards: MatchCards, rng: MatchRng, policy: PreviewPolicy, indices: Array[int]
) -> Array[MatchEvent]:
	var prompt: Dictionary = state.prompt
	state.prompt = {}
	if prompt.is_empty():
		var none: Array[MatchEvent] = []
		return none
	return apply_set(state, cards, rng, policy, prompt, indices)


## Applies the multi-select `prompt`'s verb to the set `indices` of its zone (DC-07 P7):
## CHOICE_MADE {seat, card, zone, index: -1, indices, target: -1, auto: false}, public since
## it names positions only, then the verb's events. The empty set declines: EFFECT_FIZZLED
## follows and nothing else (R24).
## - SACRIFICE_DESTROY (P12, R27): each chosen own card goes through destroy() (in row
##   order), then as many random live opponent cards, each picked as
##   DESTROY_RANDOM_OPPONENT picks (the engine stream on a live walk, R35;
##   PreviewPolicy.destroy_slot on a preview); with fewer live opponent cards than that, all
##   of them. A chosen card un-revealed instead still counts (P9, R32).
static func apply_set(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	prompt: Dictionary,
	indices: Array[int]
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var seat: int = prompt.get(KEY_SEAT, -1)
	var source: int = prompt.get(KEY_CARD, -1)
	var verb: int = prompt.get(KEY_VERB, -1)
	var zone: int = prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	if seat < 0 or seat > 1:
		return out
	var made: Dictionary = {
		"seat": seat,
		"card": source,
		"zone": Choice.zone_name(zone),
		"index": -1,
		"indices": MatchState.plain(indices),
		"target": -1,
		"auto": false,
	}
	out.append(MatchEvent.new(MatchEvent.Kind.CHOICE_MADE, made))
	if indices.is_empty():
		var fizzled: Dictionary = {"seat": seat, "card": source, "verb": CardEffect.verb_name(verb)}
		out.append(MatchEvent.new(MatchEvent.Kind.EFFECT_FIZZLED, fizzled))
		return out
	if verb == CardEffect.Verb.SACRIFICE_DESTROY:
		out.append_array(_sacrifice(state, cards, rng, policy, seat, zone, indices))
	return out


## CHOICE_MADE's owner (see the class comment): PUBLIC for a face-up row card or a pile card
## whose identity is public; else the holder of a hand or face-down row card, or the
## chooser of a pile card.
static func _choice_owner(state: MatchState, seat: int, zone: int, holder: int, target: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[holder]
	if Choice.is_pile(zone):
		return PUBLIC if piles.is_destroyed_known(target) else seat
	if Choice.is_hand(zone) or not piles.is_revealed(target):
		return holder
	return PUBLIC


## Turn end's return marks (R24, R25, plan P14), before the destroyed cards clear and
## energy settles (DC-06 P6): for each seat in turn, each marked card on its row in slot
## order leaves the row (its modifiers go) for its owner's hand, CARD_RETURNED {seat, card,
## slot}, public since the card was revealed. When that hand already holds HAND_CAP cards
## the card is burned instead: CARD_BURNED {seat, card}, the draw's burn event, made public
## for the same reason (both boards need to see the card leave its row). A marked card that
## is destroyed is skipped: clear_destroyed() discards it (DC-06 R19).
static func resolve_returns(state: MatchState) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		var row: Array[int] = []
		row.assign(piles.board)
		for card: int in row:
			var held: CardState = state.card_state(card)
			if held == null or not held.return_marked or held.destroyed:
				continue
			var slot: int = piles.board.find(card)
			if state.take_from_row(seat, card):
				pass  # Only revealed cards are ever marked; the event is public either way.
			if piles.hand.size() >= MatchRules.HAND_CAP:
				piles.burned.append(card)
				var burned: Dictionary = {"seat": seat, "card": card}
				out.append(MatchEvent.new(MatchEvent.Kind.CARD_BURNED, burned))
				continue
			piles.hand.append(card)
			var returned: Dictionary = {"seat": seat, "card": card, "slot": slot}
			out.append(MatchEvent.new(MatchEvent.Kind.CARD_RETURNED, returned))
	return out


## Turn end's clear of destroyed cards (DC-06 R18, R19, R21, P6), after the return marks
## resolve and before energy settles: for each seat in turn, each destroyed card on its row
## in slot order leaves the row (its modifiers and the mark go) for the end of that seat's
## destroyed pile (DC-07 R16, P6; the row's seat is the card's controller), DESTROYED_CLEARED
## {seat, card, slot, pile: true}, `slot` the card's slot as it leaves. The event is public
## when the card was revealed, and its identity in the pile is public too
## (`destroyed_known`, R18); it is private to its seat when the card never was, so the
## other seat sees the slot and not the card. Round end burns the piles
## (MatchState.burn_destroyed_piles).
static func clear_destroyed(state: MatchState) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		var row: Array[int] = []
		row.assign(piles.board)
		for card: int in row:
			if not state.is_destroyed(card):
				continue
			var slot: int = piles.board.find(card)
			var was_revealed: bool = state.take_from_row(seat, card)
			piles.destroyed.append(card)
			if was_revealed:
				piles.destroyed_known[card] = true
			var cleared: Dictionary = {"seat": seat, "card": card, "slot": slot, "pile": true}
			var owner: int = PUBLIC if was_revealed else seat
			out.append(MatchEvent.new(MatchEvent.Kind.DESTROYED_CLEARED, cleared, owner))
	return out


# --- Verbs ----------------------------------------------------------------------------


static func _draw(state: MatchState, seat: int, amount: int, outcome: Outcome) -> void:
	for _i: int in range(amount):
		var drawn: MatchEvent = draw_card(state, seat)
		if drawn != null and not outcome.quiet:
			outcome.events.append(drawn)


static func _free_first(state: MatchState, seat: int, outcome: Outcome) -> void:
	state.energy.free_first[seat] = true
	outcome.add(MatchEvent.Kind.FREE_FIRST_SET, {"seat": seat})


## Sets the mark on the opponent; already set, it stays one mark (R22: no stacking).
static func _mark_bonus_zero(state: MatchState, seat: int, outcome: Outcome) -> void:
	var opponent: int = 1 - seat
	state.bonus_zero_pending[opponent] = true
	outcome.add(MatchEvent.Kind.BONUS_ZERO_SET, {"seat": opponent})


static func _destroy_random(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	card: int,
	outcome: Outcome
) -> void:
	var opponent: int = 1 - seat
	var target: int = random_live(state, cards, rng, policy, opponent)
	if target < 0:
		_fizzle(seat, card, CardEffect.Verb.DESTROY_RANDOM_OPPONENT, outcome)
		return
	if not destroy(state, cards, target, outcome):
		return  # random_live only offers live row cards; destroy() accepts every one.


## A random live card of `seat`'s row, or -1 when it holds none (nothing is drawn then).
## Only live cards may be picked (DC-06 R16, R17), in row order as the row stands now: one
## MatchRng.pick_index on the engine stream on a live walk (P11, R35), else
## PreviewPolicy.destroy_slot (a preview, or a live walk given no stream).
static func random_live(
	state: MatchState, cards: MatchCards, rng: MatchRng, policy: PreviewPolicy, seat: int
) -> int:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var live: Array[int] = []
	for held: int in piles.board:
		if not state.is_destroyed(held):
			live.append(held)
	if live.is_empty():
		return -1
	var pick: int = 0
	if policy == null and rng != null:
		pick = rng.pick_index(live.size())
	else:
		pick = PreviewPolicy.destroy_slot(state, cards, live)
	return live[pick]


## The one destroy (DC-07 P9; see the class comment): `card`, live on its controller's
## row, is un-revealed when it is revealed and carries UNREVEAL_INSTEAD, else marked
## destroyed in place (DC-06 R12): it keeps its slot and stays face up or face down,
## CARD_DESTROYED {seat, card, slot}, public when the card is revealed, else private to its
## seat. The events go to `outcome` (none built when it is quiet). True in both cases, so a
## sacrifice counts the card (R32); false, changing nothing, when the card is on no row or
## already destroyed.
static func destroy(state: MatchState, cards: MatchCards, card: int, outcome: Outcome) -> bool:
	var seat: int = state.controller_of(card)
	if seat < 0 or state.is_destroyed(card):
		return false
	var piles: MatchState.SeatPiles = state.seats[seat]
	var slot: int = piles.board.find(card)
	if slot < 0:
		return false
	var payload: Dictionary = {"seat": seat, "card": card, "slot": slot}
	var revealed: bool = piles.is_revealed(card)
	if revealed and RuinEffects.carries(card, cards, CardEffect.Verb.UNREVEAL_INSTEAD):
		_unreveal(state, cards, seat, card, outcome)
		outcome.add(MatchEvent.Kind.CARD_UNREVEALED, payload)
		return true
	state.card_state_for(card).destroyed = true
	outcome.add(MatchEvent.Kind.CARD_DESTROYED, payload, PUBLIC if revealed else seat)
	return true


## The un-reveal's state change (P9, R30, C9): `card`'s CardState goes, so it shows its
## printed stats with no marks (STATS_CHANGED, cause unreveal, while it is still face up and
## only when that changed its shown stats), then it leaves `seat`'s revealed set.
static func _unreveal(
	state: MatchState, cards: MatchCards, seat: int, card: int, outcome: Outcome
) -> void:
	var before: Dictionary = ScoreWalk.effective(card, state, cards).to_dict()
	if state.clear_card_state(card):
		var after: Dictionary = ScoreWalk.effective(card, state, cards).to_dict()
		if after != before and not outcome.quiet:
			outcome.events.append(stats_changed(state, cards, seat, card, CAUSE_UNREVEAL))
	var piles: MatchState.SeatPiles = state.seats[seat]
	if not piles.revealed.erase(card):
		return  # destroy() un-reveals only revealed cards; nothing to undo otherwise.


## SACRIFICE_DESTROY's set (see apply_set): the chosen own cards of `seat`, in row order,
## each through destroy(), then one random live opponent card per own card counted,
## stopping when the opponent's row has no live card left.
static func _sacrifice(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	zone: int,
	indices: Array[int]
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var ordered: Array[int] = []
	ordered.assign(indices)
	ordered.sort()
	# Resolved before any destroy: a mark in place moves nothing, but the set is read once.
	var chosen: Array[int] = []
	for index: int in ordered:
		var target: int = Choice.resolve(state, seat, zone, index)
		if target >= 0 and not state.is_destroyed(target):
			chosen.append(target)
	var outcome: Outcome = Outcome.new()
	var count: int = 0
	for target: int in chosen:
		if destroy(state, cards, target, outcome):
			count += 1
	var opponent: int = 1 - seat
	for _i: int in range(count):
		var victim: int = random_live(state, cards, rng, policy, opponent)
		if victim < 0 or not destroy(state, cards, victim, outcome):
			break
	out.append_array(outcome.events)
	return out


static func _flat_up(
	state: MatchState, cards: MatchCards, seat: int, card: int, amount: int, outcome: Outcome
) -> void:
	state.card_state_for(card).flat_delta += amount
	if not outcome.quiet:
		outcome.events.append(stats_changed(state, cards, seat, card, CAUSE_FLAT_UP))


static func _carry(state: MatchState, seat: int, outcome: Outcome) -> void:
	var budget: int = state.turn + state.energy.carry[seat]
	var amount: int = maxi(budget - state.energy.spent[seat], 0)
	state.energy.carry[seat] = amount
	outcome.add(MatchEvent.Kind.ENERGY_CARRIED, {"seat": seat, "amount": amount})


## A prompt verb's target (see the class comment): fizzle, choose the only one, or open a
## prompt.
static func _ask(
	state: MatchState,
	cards: MatchCards,
	policy: PreviewPolicy,
	seat: int,
	card: int,
	effect: CardEffect,
	outcome: Outcome
) -> void:
	var found: Dictionary = Choice.eligible(state, seat, effect.verb, card)
	var zone: int = found[Choice.KEY_ZONE]
	var options: Array[int] = Choice.options_of(found)
	if options.is_empty():
		_fizzle(seat, card, effect.verb, outcome)
		return
	var prompt: Dictionary = _prompt(seat, card, effect.verb, zone, options)
	if options.size() == 1 or policy != null:
		var auto: bool = options.size() == 1
		var picked: int = options[0]
		if policy != null:
			picked = policy.option_for(options)
		var made: Array[MatchEvent] = apply_choice(state, cards, prompt, picked, auto)
		if not outcome.quiet:
			outcome.events.append_array(made)
		return
	_open(prompt, effect, outcome)


## A multi-select verb's targets (DC-07 P7, R22, R25): no eligible position fizzles; one or
## more opens the prompt (never auto-chosen, since the empty set is a legal answer). A
## preview declines it at once (PreviewPolicy.set_for), so its walk never pauses.
static func _ask_set(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	card: int,
	effect: CardEffect,
	outcome: Outcome
) -> void:
	var found: Dictionary = Choice.eligible(state, seat, effect.verb, card)
	var zone: int = found[Choice.KEY_ZONE]
	var options: Array[int] = Choice.options_of(found)
	if options.is_empty():
		_fizzle(seat, card, effect.verb, outcome)
		return
	var prompt: Dictionary = _prompt(seat, card, effect.verb, zone, options)
	if policy != null:
		var declined: Array[MatchEvent] = apply_set(
			state, cards, rng, policy, prompt, policy.set_for(options)
		)
		if not outcome.quiet:
			outcome.events.append_array(declined)
		return
	_open(prompt, effect, outcome)


## The prompt dictionary (plan P9, DC-07 P7): {seat, card, verb, zone, options, multi}.
static func _prompt(seat: int, card: int, verb: int, zone: int, options: Array[int]) -> Dictionary:
	return {
		KEY_SEAT: seat,
		KEY_CARD: card,
		KEY_VERB: verb,
		Choice.KEY_ZONE: zone,
		Choice.KEY_OPTIONS: MatchState.plain(options),
		Choice.KEY_MULTI: Choice.is_multi(verb),
	}


## Opens `prompt` on `outcome`: the walk pauses on it, and CHOICE_REQUESTED {seat, card,
## verb, text, zone, options, multi} announces it (public: positions only).
static func _open(prompt: Dictionary, effect: CardEffect, outcome: Outcome) -> void:
	outcome.prompt = prompt
	var seat: int = prompt[KEY_SEAT]
	var card: int = prompt[KEY_CARD]
	var zone: int = prompt[Choice.KEY_ZONE]
	var requested: Dictionary = {
		"seat": seat,
		"card": card,
		"verb": CardEffect.verb_name(effect.verb),
		"text": effect.text,
		"zone": Choice.zone_name(zone),
		"options": MatchState.plain(Choice.options_of(prompt)),
		"multi": Choice.is_multi_prompt(prompt),
	}
	outcome.add(MatchEvent.Kind.CHOICE_REQUESTED, requested)


## Discards `card` from `seat`'s hand to its burn pile (out of play for the round, so every
## card stays in exactly one pile): CARD_DISCARDED, private to `seat`.
static func _discard(state: MatchState, seat: int, card: int) -> MatchEvent:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.hand.erase(card)
	piles.burned.append(card)
	return MatchEvent.new(MatchEvent.Kind.CARD_DISCARDED, {"seat": seat, "card": card}, seat)


## Takes `card` from position `position` of `from_seat`'s destroyed pile for `seat`'s hand,
## or its burn pile at the hand cap (see the class comment): CARD_RECOVERED, then
## CARD_BURNED at the cap, both public when the card's identity was, else private to `seat`.
static func _recover(
	state: MatchState, seat: int, from_seat: int, card: int, position: int
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var pile: MatchState.SeatPiles = state.seats[from_seat]
	if position < 0 or position >= pile.destroyed.size() or pile.destroyed[position] != card:
		return out
	var known: bool = pile.is_destroyed_known(card)
	pile.destroyed.remove_at(position)
	if pile.destroyed_known.erase(card):
		pass  # Its identity was public in the pile; the events say where it goes now.
	# Printed stats, no marks (R19): its modifiers went when it left the row.
	if state.clear_card_state(card):
		pass  # A pile card holds none; cleared in case.
	var owner: int = PUBLIC if known else seat
	var recovered: Dictionary = {
		"seat": seat, "card": card, "from_seat": from_seat, "position": position
	}
	out.append(MatchEvent.new(MatchEvent.Kind.CARD_RECOVERED, recovered, owner))
	var dest: MatchState.SeatPiles = state.seats[seat]
	if dest.hand.size() >= MatchRules.HAND_CAP:
		dest.burned.append(card)
		var burned: Dictionary = {"seat": seat, "card": card}
		out.append(MatchEvent.new(MatchEvent.Kind.CARD_BURNED, burned, owner))
		return out
	dest.hand.append(card)
	return out


## Exchanges the slots of `source` and `target` on `seat`'s row: two CARD_MOVED, the
## source's first; a face-down card's move is private to `seat`.
static func _swap(state: MatchState, seat: int, source: int, target: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var piles: MatchState.SeatPiles = state.seats[seat]
	var from_slot: int = piles.board.find(source)
	var to_slot: int = piles.board.find(target)
	if from_slot < 0 or to_slot < 0:
		return out
	piles.board[from_slot] = target
	piles.board[to_slot] = source
	out.append(_moved(piles, seat, source, from_slot, to_slot))
	out.append(_moved(piles, seat, target, to_slot, from_slot))
	return out


static func _moved(
	piles: MatchState.SeatPiles, seat: int, card: int, from_slot: int, to_slot: int
) -> MatchEvent:
	var owner: int = PUBLIC if piles.is_revealed(card) else seat
	var payload: Dictionary = {
		"seat": seat, "card": card, "from_slot": from_slot, "to_slot": to_slot
	}
	return MatchEvent.new(MatchEvent.Kind.CARD_MOVED, payload, owner)


## The amount of `card`'s effect, or 0 when it has none.
static func _amount_of(card: int, cards: MatchCards) -> int:
	var effect: CardEffect = effect_of(card, cards)
	if effect == null:
		return 0
	return effect.amount


static func _fizzle(seat: int, card: int, verb: int, outcome: Outcome) -> void:
	outcome.add(
		MatchEvent.Kind.EFFECT_FIZZLED,
		{"seat": seat, "card": card, "verb": CardEffect.verb_name(verb)}
	)


# --- Helpers --------------------------------------------------------------------------


## STATS_CHANGED for `card` with its effective stats after the change (R21; DC-07 P5):
## {seat, card, flat, times, plus, cause}, public.
static func stats_changed(
	state: MatchState, cards: MatchCards, seat: int, card: int, cause: String
) -> MatchEvent:
	var stats: ScoreWalk.Effective = ScoreWalk.effective(card, state, cards)
	var payload: Dictionary = {
		"seat": seat,
		"card": card,
		"flat": stats.flat,
		"times": stats.times,
		"plus": stats.plus,
		"cause": cause,
	}
	return MatchEvent.new(MatchEvent.Kind.STATS_CHANGED, payload)


## The leftmost revealed, live (not destroyed, DC-06 R15) card on `seat`'s row with the
## ongoing CARRY_ENERGY effect, or -1.
static func _carrier(state: MatchState, cards: MatchCards, seat: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[seat]
	for card: int in piles.board:
		if not piles.is_revealed(card) or state.is_destroyed(card):
			continue
		var effect: CardEffect = effect_of(card, cards)
		if effect == null:
			continue
		if (
			effect.trigger == CardEffect.Trigger.ONGOING
			and effect.verb == CardEffect.Verb.CARRY_ENERGY
		):
			return card
	return -1


## What one firing caused: its events in order and the prompt it needs (plan P9: {seat,
## card, verb, zone, options}, as MatchState.prompt). An empty prompt means it resolved.
class Outcome:
	extends RefCounted

	var events: Array[MatchEvent] = []
	## Empty unless a prompt verb found two or more targets (a multi-select verb: one or
	## more) on a live walk.
	var prompt: Dictionary = {}
	## True under a preview policy: add() then builds nothing, since the walk drops every
	## event of a preview (DC-05 T06, cost).
	var quiet: bool = false

	## Whether the walk must pause for a choice.
	func needs_prompt() -> bool:
		return not prompt.is_empty()

	func add(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		if quiet:
			return
		events.append(MatchEvent.new(kind, payload, owner))
