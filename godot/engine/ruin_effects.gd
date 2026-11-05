class_name RuinEffects
extends RefCounted
## The Ruin deck's verbs (DC-07 T06; plan P8-P10, P12; R26, R27, R30-R32, R35, C9, C10,
## C18), split from EffectResolver to keep it in bounds. Pure: no nodes, no clock; the only
## randomness is the engine stream passed in (a preview passes a policy and no stream, and
## EffectResolver.random_live then takes the policy's pick). Every destroy here goes through
## EffectResolver.destroy() (P9), so a revealed card carrying UNREVEAL_INSTEAD un-reveals
## instead and still counts.
##
## - DESTROY_LEFTMOST_OWN (on reveal): the leftmost live card of the owner's row other than
##   the source, face up or down, goes through destroy(); none fizzles (EFFECT_FIZZLED).
## - DESTROY_OWN_THEN_DRAW (amount), DESTROY_OWN_THEN_FLAT_UP: the prompt verbs'
##   consequences once EffectResolver.apply_choice has the target (Choice offers the
##   owner's live row cards but the source, P12). The draw burns at the hand cap as every
##   draw does (R25). The flat-up gains the target's effective flat read before the destroy,
##   since an un-reveal resets it.
## - BURST (on opponent score, P10, C10): ScoreWalk fires it for each revealed, live card of
##   the other seat after every CARD_SCORED: `flat_delta += 1`, STATS_CHANGED (cause
##   opponent_score), then check_burst().
## - check_burst(): when a revealed, live card carrying BURST has an effective flat of
##   MatchRules.BURST_FLAT or more, it goes through destroy() and then one random live card
##   of the other seat's row does (the engine stream, R35); no live card there, no second
##   destroy and no draw from the stream. It runs after every stat change of a burst card:
##   the opponent-score step here, and the copy (DC-07 T07) must call it too.

## STATS_CHANGED cause of the burst's +1 (DC-07 P10).
const CAUSE_OPPONENT_SCORE: String = "opponent_score"


## Whether `card` (an instance id) carries the effect verb `verb`, whatever its trigger.
static func carries(card: int, cards: MatchCards, verb: int) -> bool:
	var effect: CardEffect = EffectResolver.effect_of(card, cards)
	return effect != null and effect.verb == verb


## DESTROY_LEFTMOST_OWN for `card` on `seat`'s row (see the class comment).
static func destroy_leftmost(
	state: MatchState, cards: MatchCards, seat: int, card: int, outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	for held: int in piles.board:
		if held == card or state.is_destroyed(held):
			continue
		if EffectResolver.destroy(state, cards, held, outcome):
			return
	EffectResolver.fizzle(seat, card, CardEffect.Verb.DESTROY_LEFTMOST_OWN, outcome)


## DESTROY_OWN_THEN_DRAW's consequence: `target`, on `seat`'s row, goes through destroy();
## when it counts, `seat` draws `amount` (CARD_DRAWN, or CARD_BURNED at the cap; private).
static func destroy_then_draw(
	state: MatchState, cards: MatchCards, seat: int, target: int, amount: int
) -> Array[MatchEvent]:
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	if EffectResolver.destroy(state, cards, target, outcome):
		for _i: int in range(amount):
			var drawn: MatchEvent = EffectResolver.draw_card(state, seat)
			if drawn != null:
				outcome.events.append(drawn)
	return outcome.events


## DESTROY_OWN_THEN_FLAT_UP's consequence: `target`'s effective flat is read, `target` goes
## through destroy(), and when it counts `source` gains that flat (`flat_delta`,
## STATS_CHANGED cause flat_up).
static func destroy_then_flat_up(
	state: MatchState, cards: MatchCards, seat: int, source: int, target: int
) -> Array[MatchEvent]:
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	var gain: int = ScoreWalk.effective(target, state, cards).flat
	if EffectResolver.destroy(state, cards, target, outcome):
		state.card_state_for(source).flat_delta += gain
		outcome.events.append(
			EffectResolver.stats_changed(state, cards, seat, source, EffectResolver.CAUSE_FLAT_UP)
		)
	return outcome.events


## BURST for `card` on `seat`'s row (see the class comment).
static func burst(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	card: int,
	outcome: EffectResolver.Outcome
) -> void:
	state.card_state_for(card).flat_delta += 1
	if not outcome.quiet:
		outcome.events.append(
			EffectResolver.stats_changed(state, cards, seat, card, CAUSE_OPPONENT_SCORE)
		)
	if check_burst(state, cards, rng, policy, card, outcome):
		pass  # The destroys' events are on `outcome`; nothing else follows them.


## The burst threshold of `card` (see the class comment): true when it fired, its events on
## `outcome`. `rng` and `policy` are as EffectResolver.apply()'s.
static func check_burst(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	card: int,
	outcome: EffectResolver.Outcome
) -> bool:
	var seat: int = state.controller_of(card)
	if seat < 0 or state.is_destroyed(card) or not carries(card, cards, CardEffect.Verb.BURST):
		return false
	var piles: MatchState.SeatPiles = state.seats[seat]
	if not piles.board.has(card) or not piles.is_revealed(card):
		return false
	if ScoreWalk.effective(card, state, cards).flat < MatchRules.BURST_FLAT:
		return false
	var fired: bool = EffectResolver.destroy(state, cards, card, outcome)
	var victim: int = EffectResolver.random_live(state, cards, rng, policy, 1 - seat)
	if victim < 0:
		return fired
	var hit: bool = EffectResolver.destroy(state, cards, victim, outcome)
	return fired or hit
