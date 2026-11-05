class_name EchoEffects
extends RefCounted
## The Echo verbs (cycle 8 R15-R20, plan P5, P6, P8). Pure: no nodes, no clock, no
## randomness. EffectResolver.apply() dispatches here after EFFECT_FIRED (and after the uses
## countdown, EffectResolver.take_use) and passes its Outcome, which is quiet on a preview.
##
## No verb here takes a card off a row during a walk (R19): a return is a turn-end mark and
## the flip keeps the slot.
## - RETURN_SELF_AT_TURN_END (on_reveal, no prompt): marks the source (CardState
##   `return_marked`). EffectResolver.resolve_returns() sends a marked card to its row's seat's
##   hand at turn end (its controller: a recovered card goes back to the recoverer), burned at
##   the cap, its board changes gone and its memory kept; a destroyed marked card is cleared
##   instead (R17).
## - RETURN_OWN_AT_TURN_END (prompt, OWN_BOARD: live, not return-marked, the source excluded)
##   and RETURN_OPPONENT_AT_TURN_END (prompt, OPPONENT_BOARD: revealed, live, not
##   return-marked) are prompt verbs (Choice, P8): EffectResolver opens the prompt or
##   auto-chooses the one option, and its apply_choice() marks the chosen card
##   (mark_return).
## - UNREVEAL_AT_TURN_END (ongoing marker): never fires; EffectResolver.flip_echoes() un-reveals
##   every revealed live carrier at turn end (flippers(), R18).
## - COST_DOWN_RIGHT (on_reveal): the card at slot + 1 of the source's row, in any state,
##   costs `amount` less for the match (CardMemory.cost); none there fizzles (no_target).
##   COST_DOWN_SELF: the source itself. Both go through BloomEffects.grow (STAT_COST):
##   STATS_CHANGED {seat, card, flat, times, plus, cost, permanent: true, cause: "cost"},
##   public for a revealed row card, private to its seat for a face-down one (R8).
## - ALLY_REVEAL_FLAT (on_ally_reveal): `flat_delta += amount`, a board change for the round
##   (it ends when the card leaves its row or the round ends), STATS_CHANGED cause
##   CAUSE_ALLY_REVEAL, public (the watcher is revealed).
## DRAW_ONCE (on_reveal, `uses` 1) and DRAW on on_ally_reveal are EffectResolver's draw.

## STATS_CHANGED `cause` of ALLY_REVEAL_FLAT (cycle 8 P6).
const CAUSE_ALLY_REVEAL: String = "ally_reveal"
## The Echo verbs that fire with no target, through apply() (EffectResolver.apply's
## membership test, P6).
const UNTARGETED_VERBS: Array[int] = [
	CardEffect.Verb.RETURN_SELF_AT_TURN_END,
	CardEffect.Verb.COST_DOWN_RIGHT,
	CardEffect.Verb.COST_DOWN_SELF,
	CardEffect.Verb.ALLY_REVEAL_FLAT,
]


## Fires one of the Echo verbs that need no target, for `card` owned by `seat` (see the class
## comment). Any other verb does nothing.
static func apply(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	card: int,
	effect: CardEffect,
	outcome: EffectResolver.Outcome
) -> void:
	match effect.verb:
		CardEffect.Verb.RETURN_SELF_AT_TURN_END:
			mark_return(state, card)
		CardEffect.Verb.COST_DOWN_RIGHT:
			var right: int = right_of(state, seat, card)
			_cost_down(state, cards, seat, card, right, effect, outcome)
		CardEffect.Verb.COST_DOWN_SELF:
			_cost_down(state, cards, seat, card, card, effect, outcome)
		CardEffect.Verb.ALLY_REVEAL_FLAT:
			_ally_flat(state, cards, seat, card, effect.amount, outcome)


## Marks `card` to return to its controller's hand at turn end (R17): RETURN_SELF_AT_TURN_END
## on its source, and the consequence of the two prompt return verbs on the chosen card
## (EffectResolver.apply_choice; P6, P8).
static func mark_return(state: MatchState, card: int) -> void:
	state.card_state_for(card).return_marked = true


## Whether `card` is marked to return at turn end (P8: a marked card is not offered again).
static func is_return_marked(state: MatchState, card: int) -> bool:
	var held: CardState = state.card_state(card)
	return held != null and held.return_marked


## The card at slot + 1 of `card`'s slot on `seat`'s row, or -1 when `card` is on no slot of
## it or holds its last slot.
static func right_of(state: MatchState, seat: int, card: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var slot: int = piles.board.find(card)
	if slot < 0 or slot + 1 >= piles.board.size():
		return -1
	return piles.board[slot + 1]


## `seat`'s revealed, live cards carrying the ongoing UNREVEAL_AT_TURN_END, in slot order:
## the cards EffectResolver.flip_echoes() turns face down (R18). Empty outright in a match
## where no definition carries the verb.
static func flippers(state: MatchState, cards: MatchCards, seat: int) -> Array[int]:
	var out: Array[int] = []
	if cards == null or not cards.has_verb(CardEffect.Verb.UNREVEAL_AT_TURN_END):
		return out
	var piles: MatchState.SeatPiles = state.seats[seat]
	for card: int in piles.board:
		if not piles.is_revealed(card) or state.is_destroyed(card):
			continue
		var effect: CardEffect = EffectResolver.effect_of(card, cards)
		if effect == null or effect.trigger != CardEffect.Trigger.ONGOING:
			continue
		if effect.verb == CardEffect.Verb.UNREVEAL_AT_TURN_END:
			out.append(card)
	return out


## The cost reduction of `effect` on `target` for `card`'s `seat`, or a fizzle when there is
## no target (-1).
static func _cost_down(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	card: int,
	target: int,
	effect: CardEffect,
	outcome: EffectResolver.Outcome
) -> void:
	if target < 0:
		EffectResolver.fizzle(seat, card, effect.verb, outcome)
		return
	var targets: Array[int] = [target]
	BloomEffects.grow(state, cards, seat, targets, BloomEffects.STAT_COST, effect.amount, outcome)


## ALLY_REVEAL_FLAT: `card` gains `amount` flat for the round (its CardState).
static func _ally_flat(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	card: int,
	amount: int,
	outcome: EffectResolver.Outcome
) -> void:
	state.card_state_for(card).flat_delta += amount
	if outcome.quiet:
		return
	outcome.events.append(EffectResolver.stats_changed(state, cards, seat, card, CAUSE_ALLY_REVEAL))
