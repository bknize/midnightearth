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
## - OPPONENT_NEXT_BONUS_ZERO: sets `bonus_zero_pending[opponent]` (no stacking, R22),
##   BONUS_ZERO_SET {seat: the opponent}. spend_bonus_zero() spends it on that seat's next
##   reveal, in this walk or a later one.
## - DESTROY_RANDOM_OPPONENT: picks one card of the opponent's row (P11, R27), takes it off
##   the row at once (R23) into its owner's burn pile, CARD_DESTROYED {seat, card, slot}.
##   An empty row fizzles (R26) and draws nothing from the stream.
## - FLAT_UP_ON_SCORE (amount): `flat_delta += amount`, STATS_CHANGED (cause flat_up).
## - CARRY_ENERGY (ongoing): `carry[owner] = budget - spent[owner]`, ENERGY_CARRIED
##   {seat, amount}. Only settle_energy() fires it, at turn end.
## - The prompt verbs (DC-05 T05; R20, R26, R28-R34, plan P9, P10). Choice.eligible() lists
##   the targets. With none the effect fizzles (EFFECT_FIZZLED {seat, card, verb}); with one
##   it is chosen at once (CHOICE_MADE with `auto` true) and applied; with two or more the
##   Outcome carries the prompt {seat, card, verb, zone, options} and the event
##   CHOICE_REQUESTED {seat, card, verb, text, zone, options} (zone by name, options as
##   positions: public). answer() applies the choice later. A preview (non-null policy)
##   never prompts: it takes the first option at once (plan P12).
##   - DRAW_THEN_DISCARD (amount): draws `amount` as DRAW does (burns at the cap), then
##     discards one card of the owner's hand to its burn pile: CARD_DISCARDED {seat, card},
##     private to the owner.
##   - SWAP_PLACES: the source and another card of the owner's row exchange slots: two
##     CARD_MOVED {seat, card, from_slot, to_slot}, the source's first. A face-down card's
##     move is private to its seat. The walk's slot cursor decides what scores next
##     (DC-06 R5-R11): a card moved behind the cursor is not reached again this walk, a
##     card moved ahead of it is pulsed again there; the source's own pulse scores it
##     wherever it landed.
##   - SWITCH_STATS: exchanges the target's current flat and bonus, flat-ups and the
##     bonus-0 mark included (ScoreWalk.switch_stats; Ben's ruling 1a): STATS_CHANGED
##     (cause switch).
##   - RETURN_AT_TURN_END: sets the target's CardState.return_marked; resolve_returns()
##     takes it back to its owner's hand at turn end, or burns it at the cap (R24, R25).
##   CHOICE_MADE {seat, card, zone, index, target, auto} is private to the seat holding the
##   target when the zone is a hand or the target is face down (R30, R34); MatchEvent
##   redaction then hides `target` (only) from the other seat.
##
## Hidden information on destroy (orchestrator, DC-05 T04): instance ids map to card
## definitions, so naming a face-down card would leak it. When the destroyed card is still
## unrevealed, CARD_DESTROYED is private to the card's seat: MatchEvent redaction hides
## `card` from the other seat while `seat` and `slot` stay visible. A revealed card's
## destroy is public.
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
const CAUSE_SWITCH: String = "switch"
const KEY_SEAT: String = "seat"
const KEY_CARD: String = "card"
const KEY_VERB: String = "verb"
const PUBLIC: int = MatchEvent.PUBLIC


## The effect of `card` (an instance id), or null for a vanilla card or unknown id.
static func effect_of(card: int, cards: CardDb) -> CardEffect:
	if cards == null or card < 0:
		return null
	var def: CardDef = cards.card_at(card % MatchRules.DECK_SIZE)
	if def == null:
		return null
	return def.effect


## Fires `card`'s effect for its owner `seat`: EFFECT_FIRED, then the verb's own events. An
## empty Outcome when the card has no effect. `rng` is the engine stream (a live walk) and
## `policy` is null on a live walk (see the class comment).
static func apply(
	state: MatchState, cards: CardDb, rng: MatchRng, policy: PreviewPolicy, seat: int, card: int
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
		CardEffect.Verb.OPPONENT_NEXT_BONUS_ZERO:
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
		_:
			# SWAP_PLACES, SWITCH_STATS, RETURN_AT_TURN_END: a target, then the verb.
			_ask(state, cards, policy, seat, card, effect, outcome)
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


## The bonus-0 mark on `seat` (R22), at the reveal of its `card`: when the mark is set, the
## card's bonus becomes 0 for the rest of the round (CardState.bonus_zero), the mark is
## spent and STATS_CHANGED (cause bonus_zero) is returned. Empty when no mark is set.
## ScoreWalk calls it right after CARD_REVEALED, before the card's effects and its score.
static func spend_bonus_zero(
	state: MatchState, cards: CardDb, seat: int, card: int
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	if not state.bonus_zero_pending[seat]:
		return out
	state.bonus_zero_pending[seat] = false
	state.card_state_for(card).bonus_zero = true
	out.append(_stats_changed(state, cards, seat, card, CAUSE_BONUS_ZERO))
	return out


## Per-seat energy at turn end (plan P7, P14): for each seat, when a revealed card with the
## ongoing CARRY_ENERGY effect is on its row, that card fires (EFFECT_FIRED, then
## ENERGY_CARRIED) and `carry[seat] = budget - spent[seat]`; otherwise `carry[seat] = 0`.
## One firing per seat however many such cards it holds (the leftmost fires). A destroyed
## or returned carry card is gone from the row by now, so it carries nothing.
static func settle_energy(state: MatchState, cards: CardDb) -> Array[MatchEvent]:
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
static func answer(state: MatchState, cards: CardDb, index: int) -> Array[MatchEvent]:
	var prompt: Dictionary = state.prompt
	state.prompt = {}
	if prompt.is_empty():
		var none: Array[MatchEvent] = []
		return none
	return apply_choice(state, cards, prompt, index, false)


## Applies `prompt`'s verb to position `index` of its zone: CHOICE_MADE, then the verb's
## own events (see the class comment). Empty when the position names no card.
static func apply_choice(
	state: MatchState, cards: CardDb, prompt: Dictionary, index: int, auto: bool
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
	var hidden: bool = Choice.is_hand(zone) or not state.seats[holder].is_revealed(target)
	var made: Dictionary = {
		"seat": seat,
		"card": source,
		"zone": Choice.zone_name(zone),
		"index": index,
		"target": target,
		"auto": auto,
	}
	out.append(MatchEvent.new(MatchEvent.Kind.CHOICE_MADE, made, holder if hidden else PUBLIC))
	match verb:
		CardEffect.Verb.DRAW_THEN_DISCARD:
			out.append(_discard(state, holder, target))
		CardEffect.Verb.SWAP_PLACES:
			out.append_array(_swap(state, holder, source, target))
		CardEffect.Verb.SWITCH_STATS:
			ScoreWalk.switch_stats(target, state, cards)
			out.append(_stats_changed(state, cards, holder, target, CAUSE_SWITCH))
		CardEffect.Verb.RETURN_AT_TURN_END:
			state.card_state_for(target).return_marked = true
	return out


## Turn end's return marks (R24, R25, plan P14), before energy settles: for each seat in
## turn, each marked card on its row in slot order leaves the row (its modifiers go) for
## its owner's hand, CARD_RETURNED {seat, card, slot}, public since the card was revealed.
## When that hand already holds HAND_CAP cards the card is burned instead: CARD_BURNED
## {seat, card}, the draw's burn event, made public for the same reason (both boards need
## to see the card leave its row).
static func resolve_returns(state: MatchState) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		var row: Array[int] = []
		row.assign(piles.board)
		for card: int in row:
			var held: CardState = state.card_state(card)
			if held == null or not held.return_marked:
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
	cards: CardDb,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	card: int,
	outcome: Outcome
) -> void:
	var opponent: int = 1 - seat
	var piles: MatchState.SeatPiles = state.seats[opponent]
	if piles.board.is_empty():
		_fizzle(seat, card, CardEffect.Verb.DESTROY_RANDOM_OPPONENT, outcome)
		return
	# The slot in the row as it stands when the effect fires.
	var slot: int = 0
	if policy == null and rng != null:
		slot = rng.pick_index(piles.board.size())
	else:
		slot = PreviewPolicy.destroy_slot(state, cards, piles.board)
	var target: int = piles.board[slot]
	var was_revealed: bool = state.take_from_row(opponent, target)
	# Out of play for the rest of the round, so every card stays in exactly one pile.
	piles.burned.append(target)
	var owner: int = MatchEvent.PUBLIC if was_revealed else opponent
	outcome.add(
		MatchEvent.Kind.CARD_DESTROYED, {"seat": opponent, "card": target, "slot": slot}, owner
	)


static func _flat_up(
	state: MatchState, cards: CardDb, seat: int, card: int, amount: int, outcome: Outcome
) -> void:
	state.card_state_for(card).flat_delta += amount
	if not outcome.quiet:
		outcome.events.append(_stats_changed(state, cards, seat, card, CAUSE_FLAT_UP))


static func _carry(state: MatchState, seat: int, outcome: Outcome) -> void:
	var budget: int = state.turn + state.energy.carry[seat]
	var amount: int = maxi(budget - state.energy.spent[seat], 0)
	state.energy.carry[seat] = amount
	outcome.add(MatchEvent.Kind.ENERGY_CARRIED, {"seat": seat, "amount": amount})


## A prompt verb's target (see the class comment): fizzle, choose the only one, or open a
## prompt.
static func _ask(
	state: MatchState,
	cards: CardDb,
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
	var prompt: Dictionary = {
		KEY_SEAT: seat,
		KEY_CARD: card,
		KEY_VERB: effect.verb,
		Choice.KEY_ZONE: zone,
		Choice.KEY_OPTIONS: MatchState.plain(options),
	}
	if options.size() == 1 or policy != null:
		var auto: bool = options.size() == 1
		var picked: int = options[0]
		if policy != null:
			picked = policy.option_for(options)
		var made: Array[MatchEvent] = apply_choice(state, cards, prompt, picked, auto)
		if not outcome.quiet:
			outcome.events.append_array(made)
		return
	outcome.prompt = prompt
	var requested: Dictionary = {
		"seat": seat,
		"card": card,
		"verb": CardEffect.verb_name(effect.verb),
		"text": effect.text,
		"zone": Choice.zone_name(zone),
		"options": MatchState.plain(options),
	}
	outcome.add(MatchEvent.Kind.CHOICE_REQUESTED, requested)


## Discards `card` from `seat`'s hand to its burn pile (out of play for the round, so every
## card stays in exactly one pile): CARD_DISCARDED, private to `seat`.
static func _discard(state: MatchState, seat: int, card: int) -> MatchEvent:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.hand.erase(card)
	piles.burned.append(card)
	return MatchEvent.new(MatchEvent.Kind.CARD_DISCARDED, {"seat": seat, "card": card}, seat)


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


static func _fizzle(seat: int, card: int, verb: int, outcome: Outcome) -> void:
	outcome.add(
		MatchEvent.Kind.EFFECT_FIZZLED,
		{"seat": seat, "card": card, "verb": CardEffect.verb_name(verb)}
	)


# --- Helpers --------------------------------------------------------------------------


## STATS_CHANGED for `card` with its effective stats after the change (R21).
static func _stats_changed(
	state: MatchState, cards: CardDb, seat: int, card: int, cause: String
) -> MatchEvent:
	var stats: Vector2i = ScoreWalk.effective(card, state, cards)
	return MatchEvent.new(
		MatchEvent.Kind.STATS_CHANGED,
		{"seat": seat, "card": card, "flat": stats.x, "bonus": stats.y, "cause": cause}
	)


## The leftmost revealed card on `seat`'s row with the ongoing CARRY_ENERGY effect, or -1.
static func _carrier(state: MatchState, cards: CardDb, seat: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[seat]
	for card: int in piles.board:
		if not piles.is_revealed(card):
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
	## Empty unless a prompt verb found two or more targets on a live walk.
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
