class_name BloomEffects
extends RefCounted
## The Bloom grow verbs (cycle 8 R5, R6, R12-R14, R20, plan P4, P7, P8). Pure: no nodes, no
## clock, no randomness. EffectResolver.apply() dispatches here after EFFECT_FIRED (and after
## the uses countdown, EffectResolver.take_use) and passes its Outcome, which is quiet on a
## preview: the memory still grows on the preview's clone, so a preview equals live play.
##
## A growth writes the card's match memory (MatchState.memory_for, CardMemory): it survives
## round start, the hand, the deck, a return, an un-reveal and a recovery by the other seat,
## and ScoreWalk.effective() / effective_cost() read it for whichever seat controls the card
## (R14). The stat and the step come from the verb (CardEffect.GROW_STAT) and the effect's
## amount (one of MatchRules.GROW_STEPS, checked by the loader).
##
## Targets (R13, C10): the owner's row or hand only, never a deck.
## - GROW_SELF_FLAT, GROW_SELF_TIMES, GROW_SELF_PLUS, GROW_SELF_TIMES_ONCE: the source itself
##   (on_score: each time it scores; GROW_SELF_TIMES_ONCE carries `uses` 1, so the countdown
##   stops it after the first firing).
## - GROW_HAND_FLAT: every card of the owner's hand, in hand order.
## - GROW_ROW_FLAT, GROW_ROW_TIMES: every other live (not destroyed) card of the owner's row,
##   face up or down, in slot order.
## - GROW_OTHER_FLAT (OWN_BOARD, live, the source excluded) and GROW_HAND_ONE_TIMES
##   (OWN_HAND, every position) are prompt verbs (Choice, P8): EffectResolver opens the prompt
##   or auto-chooses the one option, and apply_choice() grows the chosen card.
## An empty target set fizzles (EFFECT_FIZZLED, reason no_target).
##
## Events: one STATS_CHANGED {seat, card, flat, times, plus, cost, permanent: true, cause}
## per grown card, in target order, with its effective stats after the growth; `cause` is
## CAUSE_GROW, or CAUSE_COST for a cost reduction (T03's verbs). Public for a revealed row
## card; private to the holder for a hand card or a face-down row card, so the other seat's
## copy hides `card` (MatchEvent redaction, R8). A growth on a hand card changes no board
## state, so the walk's cursor is untouched.

const CAUSE_GROW: String = "grow"
## A memory cost reduction (cycle 8 P6; the Echo verbs of DC-09 T03 grow `cost`).
const CAUSE_COST: String = "cost"
const STAT_FLAT: String = "flat"
const STAT_TIMES: String = "times"
const STAT_PLUS: String = "plus"
const STAT_COST: String = "cost"


## Fires one of the seven grow verbs that need no target, for `card` owned by `seat`:
## the targets (see the class comment), then grow(); none fizzles.
static func apply(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	card: int,
	effect: CardEffect,
	outcome: EffectResolver.Outcome
) -> void:
	var targets: Array[int] = targets_of(state, seat, card, effect.verb)
	if targets.is_empty():
		EffectResolver.fizzle(seat, card, effect.verb, outcome)
		return
	grow(state, cards, seat, targets, stat_of(effect.verb), effect.amount, outcome)


## A prompt grow verb's consequence (P8): `target`, chosen from `seat`'s row or hand, grows
## by the step of `source`'s effect. The STATS_CHANGED events, none built when `quiet` (a
## preview); empty when `source` has no grow effect.
static func apply_choice(
	state: MatchState, cards: MatchCards, seat: int, source: int, target: int, quiet: bool
) -> Array[MatchEvent]:
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	outcome.quiet = quiet
	var effect: CardEffect = EffectResolver.effect_of(source, cards)
	if effect == null or not CardEffect.GROW_STAT.has(effect.verb):
		return outcome.events
	var targets: Array[int] = [target]
	grow(state, cards, seat, targets, stat_of(effect.verb), effect.amount, outcome)
	return outcome.events


## The growth itself (P4): each card of `targets` gains `amount` of `stat` (STAT_FLAT,
## STAT_TIMES in hundredths, STAT_PLUS or STAT_COST) in its memory for the match, then
## STATS_CHANGED (see the class comment) on `outcome`, none built when it is quiet. An empty
## `targets` changes nothing: the caller decides whether that fizzles. `seat` is the seat the
## growth acts for; a card's event names the seat holding it (its controller).
static func grow(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	targets: Array[int],
	stat: String,
	amount: int,
	outcome: EffectResolver.Outcome
) -> void:
	var cause: String = CAUSE_COST if stat == STAT_COST else CAUSE_GROW
	for target: int in targets:
		var kept: CardMemory = state.memory_for(target)
		if stat == STAT_FLAT:
			kept.flat += amount
		elif stat == STAT_TIMES:
			kept.times += amount
		elif stat == STAT_PLUS:
			kept.plus += amount
		elif stat == STAT_COST:
			kept.cost += amount
		if outcome.quiet:
			continue
		var holder: int = state.controller_of(target)
		if holder < 0:
			holder = seat
		var owner: int = _owner(state, holder, target)
		outcome.events.append(
			EffectResolver.stats_changed(state, cards, holder, target, cause, true, owner)
		)


## The targets of a grow verb that needs no choice, fired by `card` for `seat` (see the
## class comment); empty for any other verb.
static func targets_of(state: MatchState, seat: int, card: int, verb: int) -> Array[int]:
	var out: Array[int] = []
	var piles: MatchState.SeatPiles = state.seats[seat]
	match verb:
		CardEffect.Verb.GROW_SELF_FLAT, CardEffect.Verb.GROW_SELF_TIMES:
			out.append(card)
		CardEffect.Verb.GROW_SELF_PLUS, CardEffect.Verb.GROW_SELF_TIMES_ONCE:
			out.append(card)
		CardEffect.Verb.GROW_HAND_FLAT:
			out.assign(piles.hand)
		CardEffect.Verb.GROW_ROW_FLAT, CardEffect.Verb.GROW_ROW_TIMES:
			for held: int in piles.board:
				if held != card and not state.is_destroyed(held):
					out.append(held)
	return out


## The CardMemory stat `verb` grows (CardEffect.GROW_STAT), or "" for a verb that grows none.
static func stat_of(verb: int) -> String:
	if not CardEffect.GROW_STAT.has(verb):
		return ""
	var stat: String = CardEffect.GROW_STAT[verb]
	return stat


## Who may see `card`'s growth: PUBLIC for a revealed card on `holder`'s row, else `holder`
## alone (a hand card, a face-down row card, any other pile), so its id stays hidden (R8).
static func _owner(state: MatchState, holder: int, card: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[holder]
	if piles.board.has(card) and piles.is_revealed(card):
		return MatchEvent.PUBLIC
	return holder
