class_name EffectResolver
extends RefCounted
## Applies one card effect to a MatchState (R19-R27, plan P6-P8, P11, P14). Pure: no
## nodes, no clock; the only randomness is the engine stream passed in.
##
## apply() handles one verb per branch and returns an Outcome: the events the firing caused,
## in order, always starting with EFFECT_FIRED {seat, card, verb, trigger} (verb and trigger
## as their CardEffect JSON names), and the prompt the verb needs (the seam for DC-05 T05;
## always empty here). ScoreWalk decides when an effect fires (the trigger hooks, P6) and
## forwards the events to its sink on a live walk; a preview drops them.
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
## - The prompt verbs (DRAW_THEN_DISCARD, SWAP_PLACES, SWITCH_STATS, RETURN_AT_TURN_END) are
##   DC-05 T05. Until then each emits EFFECT_FIRED then EFFECT_FIZZLED {seat, card, verb},
##   so deck cards c09, c12, c13 and c17 do nothing yet.
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
## non-null policy is a preview (plan P12, T06's rule): the opponent's lowest-flat card
## (effective flat, leftmost on a tie), with no stream. A live walk given no stream (`rng`
## null, as unit tests do) takes the preview's rule rather than fail.

const CAUSE_FLAT_UP: String = "flat_up"
const CAUSE_BONUS_ZERO: String = "bonus_zero"


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
	var effect: CardEffect = effect_of(card, cards)
	if effect == null:
		return outcome
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
		_:
			# DRAW_THEN_DISCARD, SWAP_PLACES, SWITCH_STATS, RETURN_AT_TURN_END need a prompt:
			# DC-05 T05 builds it here (Outcome.prompt). Until then they fizzle.
			_fizzle(seat, card, effect.verb, outcome)
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


# --- Verbs ----------------------------------------------------------------------------


static func _draw(state: MatchState, seat: int, amount: int, outcome: Outcome) -> void:
	for _i: int in range(amount):
		var drawn: MatchEvent = draw_card(state, seat)
		if drawn != null:
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
		slot = _lowest_flat_index(state, cards, piles.board)
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
	outcome.events.append(_stats_changed(state, cards, seat, card, CAUSE_FLAT_UP))


static func _carry(state: MatchState, seat: int, outcome: Outcome) -> void:
	var budget: int = state.turn + state.energy.carry[seat]
	var amount: int = maxi(budget - state.energy.spent[seat], 0)
	state.energy.carry[seat] = amount
	outcome.add(MatchEvent.Kind.ENERGY_CARRIED, {"seat": seat, "amount": amount})


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


## The index in `row` of its lowest effective flat, the leftmost on a tie (the preview's
## destroy rule, plan P12). 0 for an empty row.
static func _lowest_flat_index(state: MatchState, cards: CardDb, row: Array[int]) -> int:
	var best: int = 0
	var best_flat: int = 0
	for i: int in range(row.size()):
		var flat: int = ScoreWalk.effective(row[i], state, cards).x
		if i == 0 or flat < best_flat:
			best = i
			best_flat = flat
	return best


## What one firing caused: its events in order and, from DC-05 T05, the prompt it needs
## (plan P9: {seat, card, verb, zone, options}). An empty prompt means the effect resolved.
class Outcome:
	extends RefCounted

	var events: Array[MatchEvent] = []
	## Empty until T05: no verb here opens a prompt.
	var prompt: Dictionary = {}

	## Whether the walk must pause for a choice (always false before T05).
	func needs_prompt() -> bool:
		return not prompt.is_empty()

	func add(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
