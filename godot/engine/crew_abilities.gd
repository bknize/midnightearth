class_name CrewAbilities
extends RefCounted
## The six milestone A Crew (DC-13 T07; cycle 9 plan P4, P13; spec R18, R62; canon
## [[rules/crew-v2]], [[rules/resolution]] Q8, Q11, C29). Pure: no node, no clock; the only
## randomness is the engine stream of the TriggerContext.
##
## Queued Crew (the TriggerQueue/TriggerContext protocol, VerbHandler): prepare() when the
## trigger comes up, resolve() when it acts. A Crew wakes once per subject on its own seat;
## one whose condition does not hold fizzles `no_target`. No A Crew prompts.
## - navigator_second (On score): the Score was the seat's `amount_2`th of the Walk (read
##   when it Scored: the On score context's KEY_SCORED_COUNT, else the Walk's count now);
##   its card gets Power +`amount` as Memory, after it has Scored (STATS_CHANGED).
## - captain_leftmost (On score): the card Scored from slot 0 of its row (the context's
##   KEY_SLOT, else its slot now); it gets Power +`amount` as Memory (STATS_CHANGED).
## - void_grant (On empty draw): one more grant on `MatchState.void_grants[seat]`; the
##   seat's next Scoring card gets, per grant, Power +`amount`, Add +`amount_2` and Mult
##   ×CrewDef.VOID_MULT (score_grants()), and the grants end once it has Scored
##   (spend_grants()) or at turn end (end_turn()). Grants stack.
## - dredge (On empty draw): the seat's Pile is shuffled into its Deck with the engine
##   stream, PILE_SHUFFLED_IN {seat, count}, public; an empty Pile fizzles `no_target`. The
##   denied draw resumes after the Batch (Q11: TurnFlow.resumed_draw for a turn-start
##   draw, TriggerQueue's `then_draw` for an effect's draw), with no second On empty draw.
##
## Ongoing reads (no queue entry and no event of their own; CARD_SCORED and the Budget
## show them):
## - tallyman_fifth: fifth_mult() for the Score that is the seat's `amount`th, 2×`amount`th
##   ... of the Walk (a Squelched card does not Score, so does not count; a card Scoring
##   twice counts twice): Mult `amount_2` for that Score only.
## - engineer_energy: budget_bonus(), +`amount` Energy from Turn `amount_2`.

const VERB_TALLYMAN: String = "tallyman_fifth"
const VERB_VOID: String = "void_grant"
const VERB_ENGINEER: String = "engineer_energy"
const VERB_NAVIGATOR: String = "navigator_second"
const VERB_CAPTAIN: String = "captain_leftmost"
const VERB_DREDGE: String = "dredge"
## On score context keys (ScoreWalk.score_stage): the seat's Score count in the Walk right
## after that Score, and the slot the card Scored from.
const KEY_SCORED_COUNT: String = "scored_count"
const KEY_SLOT: String = "slot"
## STATS_CHANGED `cause` and PILE_SHUFFLED_IN keys.
const KEY_CAUSE: String = "cause"
const KEY_COUNT: String = "count"


## The Crew trigger of `ctx` came up: it fizzles `no_target` when its condition does not
## hold (see the class comment), else it is left to resolve().
static func prepare(ctx: TriggerContext) -> void:
	if ctx.crew == null:
		ctx.fizzle(Abilities.REASON_NO_TARGET)
		return
	match ctx.verb:
		VERB_NAVIGATOR:
			if _scored_count(ctx) != ctx.crew.amount_2 or ctx.subject < 0:
				ctx.fizzle(Abilities.REASON_NO_TARGET)
		VERB_CAPTAIN:
			if _scored_slot(ctx) != 0 or ctx.subject < 0:
				ctx.fizzle(Abilities.REASON_NO_TARGET)
		VERB_DREDGE:
			if _pile_of(ctx).is_empty():
				ctx.fizzle(Abilities.REASON_NO_TARGET)
		VERB_VOID:
			pass  # Always acts, with no re-check of the Deck (C29).
		_:
			ctx.fizzle(Abilities.REASON_NO_TARGET)


## The Crew trigger of `ctx` resolves, reading its amounts now (Q5).
static func resolve(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_NAVIGATOR, VERB_CAPTAIN:
			_grow_power(ctx, ctx.subject, ctx.crew.amount)
		VERB_VOID:
			if ctx.seat >= 0 and ctx.seat < ctx.state.void_grants.size():
				ctx.state.void_grants[ctx.seat] += 1
		VERB_DREDGE:
			_dredge(ctx)


# --- Ongoing reads --------------------------------------------------------------------


## Tallyman: the Mult in hundredths `seat`'s Crew give the Score that is its `count`th of
## the Walk (1 for the first), or 0 when none applies.
static func fifth_mult(cards: MatchCards, seat: int, count: int) -> int:
	var tallyman: CrewDef = crew_with(cards, seat, VERB_TALLYMAN)
	if tallyman == null or tallyman.amount <= 0 or count <= 0:
		return 0
	if count % tallyman.amount != 0:
		return 0
	return tallyman.amount_2


## Engineer: the Energy `seat`'s Crew add to its Budget this Turn (TurnFlow.budget).
static func budget_bonus(state: MatchState, cards: MatchCards, seat: int) -> int:
	var engineer: CrewDef = crew_with(cards, seat, VERB_ENGINEER)
	if engineer == null or state == null or state.turn < engineer.amount_2:
		return 0
	return engineer.amount


## Adds to `stats` (the effective stats of `seat`'s card about to Score, Scoring.stats)
## what `seat`'s Crew give that Score, the `count`th of the seat's Walk: every Void grant
## held (Power, then an Add and a Mult each), then Tallyman's Mult.
static func score_grants(
	stats: Scoring.Stats, state: MatchState, cards: MatchCards, seat: int, count: int
) -> void:
	if state == null or seat < 0 or seat >= state.void_grants.size():
		return
	var grants: int = state.void_grants[seat]
	var void_crew: CrewDef = crew_with(cards, seat, VERB_VOID)
	if grants > 0 and void_crew != null:
		for _grant: int in range(grants):
			stats.power += void_crew.amount
			stats.adds.append(void_crew.amount_2)
			stats.mults.append(CrewDef.VOID_MULT)
	var doubled: int = fifth_mult(cards, seat, count)
	if doubled > 0:
		stats.mults.append(doubled)


## `seat`'s Void grants end: its next Scoring card has Scored (ScoreWalk.score).
static func spend_grants(state: MatchState, seat: int) -> void:
	if state != null and seat >= 0 and seat < state.void_grants.size():
		state.void_grants[seat] = 0


## Turn end (TurnFlow.settle_turn): every Void grant no card used ends.
static func end_turn(state: MatchState) -> void:
	for seat: int in range(state.void_grants.size()):
		state.void_grants[seat] = 0


## `seat`'s first Crew whose verb is `verb`, or null (a deck lists three different Crew).
static func crew_with(cards: MatchCards, seat: int, verb: String) -> CrewDef:
	if cards == null:
		return null
	for crew: CrewDef in cards.crew_for(seat):
		if crew.verb == verb:
			return crew
	return null


# --- Helpers --------------------------------------------------------------------------


## The seat's Score count in the Walk right after the Score that woke `ctx`.
static func _scored_count(ctx: TriggerContext) -> int:
	if ctx.context.has(KEY_SCORED_COUNT):
		var counted: int = ctx.context[KEY_SCORED_COUNT]
		return counted
	if ctx.seat < 0 or ctx.seat >= ctx.state.walk.scored_count.size():
		return -1
	return ctx.state.walk.scored_count[ctx.seat]


## The slot the card that woke `ctx` Scored from (its slot now when the context has none).
static func _scored_slot(ctx: TriggerContext) -> int:
	if ctx.context.has(KEY_SLOT):
		var slot: int = ctx.context[KEY_SLOT]
		return slot
	if ctx.seat < 0 or ctx.seat >= ctx.state.seats.size():
		return -1
	return ctx.state.seats[ctx.seat].board.find(ctx.subject)


static func _pile_of(ctx: TriggerContext) -> Array[int]:
	if ctx.seat < 0 or ctx.seat >= ctx.state.seats.size():
		var none: Array[int] = []
		return none
	return ctx.state.seats[ctx.seat].pile


## Power +`amount` for the match on `card` (Memory), then STATS_CHANGED {card, power, mult,
## add, cost, permanent, cause}, private to the seat holding it while it is hidden.
static func _grow_power(ctx: TriggerContext, card: int, amount: int) -> void:
	if card < 0:
		return
	ctx.state.memory_for(card).power += amount
	var shown: Dictionary = Scoring.stats(card, ctx.state, ctx.cards).to_dict()
	shown["card"] = card
	shown["cost"] = Scoring.effective_cost(card, ctx.state, ctx.cards)
	shown["permanent"] = true
	shown[KEY_CAUSE] = ctx.crew.id
	ctx.emit(MatchEvent.Kind.STATS_CHANGED, shown, _holder_if_hidden(ctx.state, card))


## The seat that may see `card` when it is hidden (in a hand, a Deck, or face down on a
## row), else MatchEvent.PUBLIC (revealed on a row, or in a Pile).
static func _holder_if_hidden(state: MatchState, card: int) -> int:
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		if piles.pile.has(card):
			return MatchEvent.PUBLIC
		if piles.board.has(card):
			return MatchEvent.PUBLIC if piles.is_revealed(card) else seat
		if piles.hand.has(card) or piles.deck.has(card):
			return seat
	return MatchEvent.PUBLIC


## Dredger: the seat's Pile goes into its Deck, which is shuffled with the engine stream;
## PILE_SHUFFLED_IN {seat, count}, public.
static func _dredge(ctx: TriggerContext) -> void:
	var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
	var count: int = piles.pile.size()
	if count == 0:
		return
	piles.deck.append_array(piles.pile)
	piles.pile.clear()
	if ctx.rng != null:
		ctx.rng.shuffle_in_place(piles.deck)
	ctx.emit(MatchEvent.Kind.PILE_SHUFFLED_IN, {"seat": ctx.seat, KEY_COUNT: count})
