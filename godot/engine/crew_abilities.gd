class_name CrewAbilities
extends RefCounted
## The ten Crew: milestone A's six (DC-13 T07) and milestone B's four (DC-14 T14) (cycle 9
## plan P4, P13; spec R18, R62; canon [[rules/crew-v2]], [[rules/resolution]] Q8, Q11, C29,
## steps 11 to 13). Pure: no node, no clock; the only randomness is the engine stream of the
## TriggerContext.
##
## Queued Crew (the TriggerQueue/TriggerContext protocol, VerbHandler): prepare() when the
## trigger comes up, resolve() when it acts. A Crew wakes once per subject on its own seat;
## one whose condition does not hold fizzles `no_target`. No A Crew prompts; every B Crew
## that targets prompts its seat, always (even over one option) and optionally (R52): a
## decline does nothing and spends nothing.
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
## - veil_fleeting (At turn end before the exit pass, D9): a prompt (own_board) over the
##   Condemned cards of the seat's row, face up or down; the chosen one's mark becomes
##   Fleeting (Statuses.mark_exit, EXIT_MARKED {replaced: condemned}), so the exit pass right
##   after sends it to its Owner's hand. Wraith changes Condemned only, so Veil beats it.
## - shade_unreveal (At turn end after the exit pass, D11): up to `amount` of the seat's
##   revealed row cards, picked at random with the engine stream (a shuffled copy of their
##   slots, the first `amount` kept, in slot order), are offered (own_board); the chosen one
##   is Un-revealed in place (Statuses.unreveal: Memory kept, Board changes gone,
##   CARD_UNREVEALED), so its On reveal fires again next Walk. None revealed: `no_target`.
## - salvager_cycle (On commit of its seat, D3/D5, before the discard-down): a prompt
##   (own_hand) over the seat's hand; the chosen card is Discarded (CARD_DISCARDED, reason
##   discard) and its On discard Batch queued, then the seat draws a card
##   (TriggerContext.draw, Q11 on an empty Deck). An empty hand fizzles `no_target`; a
##   decline neither Discards nor draws.
##
## Uses (rules 9, cycle 14 R6, R7, R13, plan P4, P7): MatchState.crew_uses[seat][slot]
## counts down from CrewDef.initial_uses() each time a limited Crew (`uses` above 0)
## resolves; CrewDef.UNLIMITED never counts. A Crew with none left fizzles `spent` when it
## comes up instead of firing. A Crew of scope `turn` gets its uses back at turn end
## (end_turn_uses()); any other scope counts for the match. After its verb resolves a Crew
## sends CREW_FIRED {seat, slot, crew, moment, verb, uses_left} (public; `uses_left` -1 when
## unlimited), besides the TRIGGER_FIRED the queue sent when it fired. Its stats changes go
## through Abilities.stats_changed() with the Crew id as `cause` (R14), so a card in a
## pending face-down Commit is told to the first committer only (R15).
##
## Ongoing reads (no queue entry and no event of their own; CARD_SCORED and the Budget
## show them):
## - tallyman_fifth: fifth_mult() for the Score that is the seat's `amount`th, 2×`amount`th
##   ... of the Walk (a Squelched card does not Score, so does not count; a card Scoring
##   twice counts twice): Mult `amount_2` for that Score only.
## - engineer_energy: budget_bonus(), +`amount` Energy from Turn `amount_2`.
## - quartermaster_hand: hand_size_set(), "your Hand size is `amount`" (TurnFlow.hand_size,
##   which adds Pantry's +N on top).

const VERB_TALLYMAN: String = "tallyman_fifth"
const VERB_VOID: String = "void_grant"
const VERB_ENGINEER: String = "engineer_energy"
const VERB_NAVIGATOR: String = "navigator_second"
const VERB_CAPTAIN: String = "captain_leftmost"
const VERB_DREDGE: String = "dredge"
const VERB_SHADE: String = "shade_unreveal"
const VERB_VEIL: String = "veil_fleeting"
const VERB_QUARTERMASTER: String = "quartermaster_hand"
const VERB_SALVAGER: String = "salvager_cycle"
## On score context keys (ScoreWalk.score_stage): the seat's Score count in the Walk right
## after that Score, and the slot the card Scored from.
const KEY_SCORED_COUNT: String = "scored_count"
const KEY_SLOT: String = "slot"


## The Crew trigger of `ctx` came up: it fizzles `no_target` when its condition does not
## hold (see the class comment), else it is left to resolve().
static func prepare(ctx: TriggerContext) -> void:
	if ctx.crew == null:
		ctx.fizzle(Abilities.REASON_NO_TARGET)
		return
	if uses_left(ctx.state, ctx.cards, ctx.seat, ctx.crew_slot) == 0:
		ctx.fizzle(Abilities.REASON_SPENT)  # Limited uses, none left in its scope (R6).
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
		VERB_SHADE:
			_ask(ctx, Choice.Zone.OWN_BOARD, _shade_offer(ctx))
		VERB_VEIL:
			_ask(ctx, Choice.Zone.OWN_BOARD, _condemned_slots(ctx))
		VERB_SALVAGER:
			_ask(ctx, Choice.Zone.OWN_HAND, _hand_positions(ctx))
		_:
			ctx.fizzle(Abilities.REASON_NO_TARGET)


## The Crew trigger of `ctx` resolves, reading its amounts now (Q5); a prompting Crew
## resolves only once answered (a decline never reaches here, TriggerQueue.answer). Then
## fire() counts the use and sends CREW_FIRED.
static func resolve(ctx: TriggerContext) -> void:
	if ctx.crew == null:
		return
	match ctx.verb:
		VERB_NAVIGATOR, VERB_CAPTAIN:
			_grow_power(ctx, ctx.subject, ctx.crew.amount)
		VERB_VOID:
			if ctx.seat >= 0 and ctx.seat < ctx.state.void_grants.size():
				ctx.state.void_grants[ctx.seat] += 1
		VERB_DREDGE:
			_dredge(ctx)
		VERB_SHADE:
			_shade(ctx)
		VERB_VEIL:
			_veil(ctx)
		VERB_SALVAGER:
			_salvage(ctx)
	fire(ctx)


## After `ctx`'s Crew verb has resolved (R13): one use is counted (a limited Crew) and
## CREW_FIRED {seat, slot, crew, moment, verb, uses_left} goes out, public, `uses_left` the
## uses left after this one (CrewDef.UNLIMITED, -1, for an unlimited Crew).
static func fire(ctx: TriggerContext) -> void:
	var left: int = _count_use(ctx.state, ctx.cards, ctx.seat, ctx.crew_slot)
	var fired: Dictionary = {
		"seat": ctx.seat,
		"slot": ctx.crew_slot,
		"crew": ctx.crew.id,
		"moment": ctx.moment,
		"verb": ctx.verb,
		"uses_left": left,
	}
	ctx.emit(MatchEvent.Kind.CREW_FIRED, fired)


## The uses `seat`'s Crew in `slot` has left (MatchState.crew_uses): CrewDef.UNLIMITED for
## an unlimited Crew; its CrewDef.initial_uses() when the counts are not filled yet.
static func uses_left(state: MatchState, cards: MatchCards, seat: int, slot: int) -> int:
	if state == null or seat < 0 or seat >= state.crew_uses.size() or slot < 0:
		return CrewDef.UNLIMITED
	var held: Array = state.crew_uses[seat]
	if slot < held.size():
		var left: int = held[slot]
		return left
	var crew: CrewDef = cards.crew_def(seat, slot) if cards != null else null
	return crew.initial_uses() if crew != null else CrewDef.UNLIMITED


## Turn end (TurnFlow.continue_end_turn, before the Turn settles): every Crew of scope
## `turn` gets its uses back (CrewDef.initial_uses()); the others keep their counts.
static func end_turn_uses(state: MatchState, cards: MatchCards) -> void:
	if state == null or cards == null:
		return
	for seat: int in range(state.crew_uses.size()):
		var held: Array = state.crew_uses[seat]
		for slot: int in range(held.size()):
			var crew: CrewDef = cards.crew_def(seat, slot)
			if crew != null and crew.scope == Abilities.SCOPE_TURN:
				held[slot] = crew.initial_uses()


## Counts one use of `seat`'s limited Crew in `slot` (filling the seat's counts first when
## they are not); returns the uses left after it, CrewDef.UNLIMITED for an unlimited Crew.
static func _count_use(state: MatchState, cards: MatchCards, seat: int, slot: int) -> int:
	var left: int = uses_left(state, cards, seat, slot)
	if left == CrewDef.UNLIMITED:
		return left
	var held: Array = state.crew_uses[seat]
	if slot >= held.size():
		state.reset_crew_uses(cards)
		held = state.crew_uses[seat]
	if slot >= held.size():
		return left
	left = maxi(left - 1, 0)
	held[slot] = left
	return left


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


## Quartermaster: the Hand size `seat`'s Crew set ("your Hand size is N"), or 0 when none
## sets one (TurnFlow.hand_size).
static func hand_size_set(cards: MatchCards, seat: int) -> int:
	var quartermaster: CrewDef = crew_with(cards, seat, VERB_QUARTERMASTER)
	if quartermaster == null:
		return 0
	return quartermaster.amount


## Adds to `stats` (the effective stats of `seat`'s card about to Score, Scoring.stats)
## what `seat`'s Crew give that Score, the `count`th of the seat's Walk: every Void grant
## held (Power, then an Add and a Mult each), then Tallyman's Mult.
static func score_grants(
	stats: Scoring.Stats, state: MatchState, cards: MatchCards, seat: int, count: int
) -> void:
	if state == null or seat < 0 or seat >= state.void_grants.size():
		return
	var grants: int = state.void_grants[seat]
	var void_crew: CrewDef = crew_with(cards, seat, VERB_VOID) if grants > 0 else null
	if void_crew != null:
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
	for slot: int in range(MatchRules.CREW_SIZE):
		var crew: CrewDef = cards.crew_def(seat, slot)
		if crew != null and crew.verb == verb:
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
	if not _seat_ok(ctx):
		return -1
	return ctx.state.seats[ctx.seat].board.find(ctx.subject)


## Whether `ctx`'s seat is one of the state's seats.
static func _seat_ok(ctx: TriggerContext) -> bool:
	return ctx.seat >= 0 and ctx.seat < ctx.state.seats.size()


static func _pile_of(ctx: TriggerContext) -> Array[int]:
	if not _seat_ok(ctx):
		var none: Array[int] = []
		return none
	return ctx.state.seats[ctx.seat].pile


## Power +`amount` for the match on `card` (Memory), then STATS_CHANGED as a card ability's
## (Abilities.stats_changed: the same keys, cost clamp and routing, R14, R15), `cause` the
## Crew id.
static func _grow_power(ctx: TriggerContext, card: int, amount: int) -> void:
	if card < 0:
		return
	ctx.state.memory_for(card).power += amount
	Abilities.stats_changed(ctx, card, true, ctx.crew.id)


## Dredger: the seat's Pile goes into its Deck, which is shuffled with the engine stream;
## PILE_SHUFFLED_IN {seat, count}, public.
static func _dredge(ctx: TriggerContext) -> void:
	AbilitiesGraveyardControl.pile_into_deck(ctx, ctx.seat)


# --- Milestone B ----------------------------------------------------------------------


## Asks the Crew's seat over `options` (positions in `zone`): none fizzles `no_target`, any
## other count prompts, optionally (TriggerContext.choose: a Crew always asks).
static func _ask(ctx: TriggerContext, zone: int, options: Array[int]) -> void:
	if ctx.choose(zone, options, false, 1, 1, true):
		pass  # A Crew never chooses by itself: the prompt is open.


## Shade's offer: up to `amount` random slots among the seat's revealed row cards (a copy of
## their slots shuffled with the engine stream, the first `amount` kept), in slot order.
static func _shade_offer(ctx: TriggerContext) -> Array[int]:
	if not _seat_ok(ctx):
		var none: Array[int] = []
		return none
	var slots: Array[int] = AbilitiesComboDisruption.revealed_slots(ctx.state, ctx.seat)
	if slots.size() > ctx.crew.amount and ctx.rng != null:
		ctx.rng.shuffle_in_place(slots)
	var offered: Array[int] = slots.slice(0, maxi(ctx.crew.amount, 0))
	offered.sort()
	return offered


## Veil's options: the slots of the seat's row whose card is Condemned.
static func _condemned_slots(ctx: TriggerContext) -> Array[int]:
	var slots: Array[int] = []
	if not _seat_ok(ctx):
		return slots
	var row: Array[int] = ctx.state.seats[ctx.seat].board
	for slot: int in range(row.size()):
		if Statuses.exit_mark_of(ctx.state, row[slot]) == Statuses.CONDEMNED:
			slots.append(slot)
	return slots


## Salvager's options: every position of the seat's hand.
static func _hand_positions(ctx: TriggerContext) -> Array[int]:
	if not _seat_ok(ctx):
		var none: Array[int] = []
		return none
	return Abilities.positions(ctx.state.seats[ctx.seat].hand.size())


## Shade: the chosen revealed card of the seat's row is Un-revealed in place.
static func _shade(ctx: TriggerContext) -> void:
	var card: int = ctx.chosen_card()
	var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
	if card < 0 or not piles.is_revealed(card):
		return
	if Statuses.unreveal(ctx.state, ctx.seat, card, ctx.sink):
		pass  # Face down in its slot: Memory kept, Board changes gone.


## Veil: the chosen Condemned card of the seat's row gets Fleeting instead.
static func _veil(ctx: TriggerContext) -> void:
	var card: int = ctx.chosen_card()
	if card < 0 or Statuses.exit_mark_of(ctx.state, card) != Statuses.CONDEMNED:
		return
	if Abilities.mark(ctx, card, Statuses.FLEETING):
		pass  # The exit pass sends it to its Owner's hand.


## Salvager: the chosen hand card goes to its Owner's Pile as a Discard (its On discard
## Batch queued, Q1), then the seat draws a card.
static func _salvage(ctx: TriggerContext) -> void:
	var card: int = ctx.chosen_card()
	var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
	if card < 0 or not piles.hand.has(card):
		return
	Abilities.discard(ctx, card)
	if ctx.draw(ctx.seat) < 0:
		pass  # An empty Deck: DRAW_EMPTY, its On empty draw Batch queued (Q11).
