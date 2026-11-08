class_name AbilitiesGraveyardControl
extends RefCounted
## The Graveyard and Control card abilities (DC-14 T13; cycle 9 plan P3, P10, P12; canon
## [[rules/cards-v2]] sections 2.4 and 2.5). Pure: no nodes, no clock; every random pick is
## drawn from the engine stream (TriggerContext.rng, or the rng ScoreWalk passes in).
##
## Abilities.prepare() and resolve() hand every verb of VERBS to prepare() and resolve()
## here (the queue's protocol, TriggerContext). Triggered verbs:
## - `fuse` (Fuse, On score of an opposing card): Power +amount until it leaves the row;
##   then at Power `amount_2` or more it Condemns itself and one random opposing card. The
##   pick is drawn from the whole row; one that lands on a protected or already Condemned
##   card is a miss, a TRIGGER_FIZZLED `protected` / `already_marked` (rules 9, R3).
## - `tithe_energy` (Tithe, On discard of another card of yours): only for a Condemned card
##   Discarded by the exit pass (the D10 context, TurnFlow.on_discard); the seat's
##   `next_turn_grants` +amount, at most `cap` per Tithe per turn end (`spent` past it); on
##   the Round's last Turn there is no next Turn and it fizzles `no_target`.
## - `reliquary_mult` (Reliquary, On discard of another card of yours from your hand): its
##   Mult ×amount for the match (Memory), capped at `cap`, once per Turn (`spent` after).
## - `condemn_other_gain` (Glutton): Condemns one other card of its row (a prompt with two
##   or more) and gains that card's Power, read now, until it leaves the row.
## - `revive` (Revive): a card of its Controller's Pile is placed face down in the slot to
##   its right (Movement.place, Placement, so it is reached this Walk), CARD_PLACED {seat,
##   card, from: "pile", slot}; then Revive Condemns itself.
## - `exhume` (Exhume): up to `amount` cards of either Pile, each shuffled into its Owner's
##   Deck at a random position. Asked once (C15 2a): an optional multi-select over both
##   Piles with `min` 0 and `max` `amount` ("choose up to two"), so it always prompts and
##   a decline or an empty set chooses none. Each chosen card, in position order,
##   PILE_SHUFFLED_IN {seat, count: 1, pile_cards: [card]}.
## - `immolate` (Immolator): an optional-count multi-select over its other cards; each
##   chosen one is Condemned, then as many random opposing cards (distinct), each pick a
##   possible miss as Fuse's.
## - `reset_piles` (Reset): both Piles into their Decks (first seat's first, each Deck
##   shuffled after, PILE_SHUFFLED_IN {seat, count}), then Reset Condemns itself.
## - `moved_add` (Eddy, On moved): Add +amount until end of turn.
## - `pin` (Pin): a card on either row is Anchored until Pin leaves its row (cessation
##   condition Statuses.CONDITION_SOURCE_ON_ROW, sourced by Pin).
## - `swap_self` (Shepherd): swaps with another, not Anchored, card of its row.
## - `skip_next` (Skip): the next card revealed this Walk moves to a different random free
##   slot of its row once its On reveal Batch has drained (the reveal-stage hook: arm_skip()
##   at the reveal, skip_hook() after D7, its On moved Batch queued for D8).
## - `shake` (Shake, C28): in each row a random half of its cards (rounded down, Anchored
##   cards in the pool) step left together on the ring (shake_row()); a chosen Anchored card
##   does not move; every card that changed slot, on both rows, is one On moved Batch.
## - `reverse_opposing` (Tempest): Movement.reverse of the opposing row.
## - `cull` (Cull): each seat with more than `amount` cards on its row chooses `amount` of
##   them (the Controller first, then the opponent, Q9); every other card on those rows is
##   Condemned.
## Ongoing verbs, never queued, read where they apply:
## - `pile_power` (Boneyard) and `rightmost_mult` (Herald): its own stats (ongoing_stats(),
##   from Scoring.stats); `level_power` (Level): each revealed card on a row has the lowest
##   Power, read before any Level, among the revealed cards of its row (Scoring.stats); a
##   face-down card keeps its own (rules 9).
## - `fence` (Fence): fence_movers(), from Movement.step_set: a mover that would wrap the
##   ring is Condemned instead and does not move, so it wakes no On moved.
## - `wraith_fade` (Wraith): read once at the start of the exit pass (Statuses.exit_pass),
##   so a Condemned card of its Controller's row resolves as Fade. A Veil (T14, At turn end
##   before the exit pass) turns a Condemned card Fleeting first, so Wraith never sees it.
##
## "Once per Turn" and "per turn end" counts are kept on the card's Board changes as a
## CardState.granted entry of KIND_USED until "turn" (Scoring reads only Adds and Mults
## there), so they end at resolution step 14 with the other turn changes.

const VERB_FUSE: String = "fuse"
const VERB_TITHE: String = "tithe_energy"
const VERB_RELIQUARY: String = "reliquary_mult"
const VERB_BONEYARD: String = "pile_power"
const VERB_WRAITH: String = "wraith_fade"
const VERB_GLUTTON: String = "condemn_other_gain"
const VERB_REVIVE: String = "revive"
const VERB_EXHUME: String = "exhume"
const VERB_IMMOLATE: String = "immolate"
const VERB_RESET: String = "reset_piles"
const VERB_EDDY: String = "moved_add"
const VERB_PIN: String = "pin"
const VERB_SHEPHERD: String = "swap_self"
const VERB_SKIP: String = "skip_next"
const VERB_FENCE: String = "fence"
const VERB_HERALD: String = "rightmost_mult"
const VERB_LEVEL: String = "level_power"
const VERB_SHAKE: String = "shake"
const VERB_TEMPEST: String = "reverse_opposing"
const VERB_CULL: String = "cull"
## The triggered verbs this module prepares and resolves (Abilities dispatches them here).
const VERBS: Array[String] = [
	VERB_FUSE,
	VERB_TITHE,
	VERB_RELIQUARY,
	VERB_GLUTTON,
	VERB_REVIVE,
	VERB_EXHUME,
	VERB_IMMOLATE,
	VERB_RESET,
	VERB_EDDY,
	VERB_PIN,
	VERB_SHEPHERD,
	VERB_SKIP,
	VERB_SHAKE,
	VERB_TEMPEST,
	VERB_CULL,
]
## CardState.granted kind of a use counted until end of turn (Tithe, Reliquary).
const KIND_USED: String = "used"
## On discard context keys (TurnFlow.on_discard): where the card came from and why.
const KEY_FROM: String = "from"
const KEY_REASON: String = "reason"
## CARD_PLACED `from` (the pinned milestone B payload).
const FROM_PILE: String = "pile"
## PILE_SHUFFLED_IN key listing the Pile cards an Exhume shuffled in (public: Pile cards).
const KEY_PILE_CARDS: String = "pile_cards"
## ctx.data keys: the seat Cull asked last; the cards each seat kept from a Cull.
const DATA_ASKED: String = "asked"
const DATA_KEPT: Array[String] = ["kept_0", "kept_1"]

# --- The queue's protocol ---------------------------------------------------------------


## Whether `verb` is one of this module's triggered verbs.
static func handles(verb: String) -> bool:
	return VERBS.has(verb)


## Checks `ctx`'s verb's eligibility (fizzle) or targets it (Q9); see the class comment.
static func prepare(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_FUSE, VERB_RESET, VERB_SKIP, VERB_EDDY:
			Abilities.need(ctx, Statuses.row_seat(ctx.state, ctx.card) >= 0)
		VERB_TITHE:
			_prepare_tithe(ctx)
		VERB_RELIQUARY:
			_prepare_reliquary(ctx)
		VERB_GLUTTON:
			_choose_own(ctx, _condemnable_others(ctx), false)
		VERB_IMMOLATE:
			_choose_own(ctx, _condemnable_others(ctx), true)
		VERB_SHEPHERD:
			_prepare_shepherd(ctx)
		VERB_REVIVE:
			var pile: Array[int] = ctx.state.seats[ctx.seat].pile
			if ctx.choose(Choice.Zone.OWN_PILE, Abilities.positions(pile.size())):
				pass  # One card in the Pile: chosen at once.
		VERB_EXHUME:
			_prepare_exhume(ctx)
		VERB_PIN:
			var both: int = Choice.zone_cards(ctx.state, ctx.seat, Choice.Zone.BOTH_BOARDS).size()
			if ctx.choose(Choice.Zone.BOTH_BOARDS, Abilities.positions(both)):
				pass  # One card on the rows: chosen at once.
		VERB_SHAKE:
			var widest: int = maxi(ctx.state.seats[0].board.size(), ctx.state.seats[1].board.size())
			Abilities.need(ctx, widest >= 2)
		VERB_TEMPEST:
			Abilities.need(ctx, ctx.state.seats[1 - ctx.seat].board.size() >= 2)
		VERB_CULL:
			_prepare_cull(ctx)
		_:
			ctx.fizzle(Abilities.REASON_NO_TARGET)


## Applies `ctx`'s verb (after prepare(), or after its prompt's answer), every amount read
## now (Q5).
static func resolve(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_FUSE:
			_fuse(ctx)
		VERB_TITHE:
			_tithe(ctx)
		VERB_RELIQUARY:
			_reliquary(ctx)
		VERB_GLUTTON:
			_glutton(ctx)
		VERB_REVIVE:
			_revive(ctx)
		VERB_EXHUME:
			_exhume(ctx)
		VERB_IMMOLATE:
			_immolate(ctx)
		VERB_RESET:
			_reset(ctx)
		_:
			_resolve_control(ctx)


# --- Ongoing reads ----------------------------------------------------------------------


## Adds to `out` (the stats of `card`, Scoring.stats) what this module's Ongoings give it:
## Boneyard's Power from both Piles and Herald's Mult in the rightmost slot (its own, while
## read), then, when `levelled`, Level's Power (level_power()).
static func ongoing_stats(
	out: Scoring.Stats, card: int, state: MatchState, cards: MatchCards, levelled: bool
) -> void:
	if state == null or cards == null:
		return
	var boneyard: CardAbility = own_ongoing(state, cards, card, VERB_BONEYARD)
	if boneyard != null and boneyard.amount_2 > 0:
		var piled: int = state.seats[0].pile.size() + state.seats[1].pile.size()
		@warning_ignore("integer_division")
		var steps: int = piled / boneyard.amount_2
		out.power += steps * boneyard.amount
	var herald: CardAbility = own_ongoing(state, cards, card, VERB_HERALD)
	if herald != null:
		var row: Array[int] = state.seats[Statuses.row_seat(state, card)].board
		var rightmost: int = row[row.size() - 1]
		if rightmost == card:
			out.mults.append(herald.amount)
	if levelled:
		level_power(out, card, state, cards)


## Level (read at Score, Q5): while a Level is read on either row, `card` on a row has the
## lowest Power among the revealed cards of its row, each read before any Level applies
## (Scoring.stats with `levelled` false; `out` is `card`'s own). A row with no revealed card
## changes nothing. Only a revealed `card` is levelled (rules 9, cycle 14 R4, C3 3a): a
## face-down one keeps its own Power until its reveal; which cards supply the lowest Power
## is unchanged (R5).
static func level_power(
	out: Scoring.Stats, card: int, state: MatchState, cards: MatchCards
) -> void:
	if not _read_anywhere(state, cards, VERB_LEVEL):
		return
	var seat: int = Statuses.row_seat(state, card)
	if seat < 0:
		return
	var piles: MatchState.SeatPiles = state.seats[seat]
	if not piles.is_revealed(card):
		return
	var found: bool = false
	var lowest: int = 0
	for other: int in piles.board:
		if not piles.is_revealed(other):
			continue
		var power: int = out.power
		if other != card:
			power = Scoring.stats(other, state, cards, false).power
		if not found or power < lowest:
			lowest = power
		found = true
	if found:
		out.power = lowest


## Fence (an "instead" effect, read when a stepwise move is made): `movers` of `seat`'s row
## less every one that would step `dir` over the edge of the ring of free slots, which is
## Condemned instead (EXIT_MARKED) and does not move. `movers` unchanged with no Fence read,
## and on a row with no ring (fewer than two non-Anchored slots, C15 3a): there a step
## changes nothing, so Fence Condemns nothing.
static func fence_movers(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	movers: Array[int],
	dir: int,
	sink: Callable
) -> Array[int]:
	if not _read_anywhere(state, cards, VERB_FENCE):
		return movers
	var row: Array[int] = state.seats[seat].board
	var free: Array[int] = Movement.free_slots(state, cards, seat)
	if free.size() < 2:
		return movers  # No ring to step off (C15 3a).
	var out: Array[int] = []
	for index: int in range(free.size()):
		var card: int = row[free[index]]
		if not movers.has(card):
			continue
		var target: int = index + (Movement.RIGHT if dir >= 0 else Movement.LEFT)
		if target < 0 or target >= free.size():
			if Statuses.mark_exit(state, cards, card, Statuses.CONDEMNED, sink):
				pass  # Condemned instead of moving (it still Scores this Walk, Q10).
			continue
		out.append(card)
	return out


# --- The reveal-stage hook (Skip) -------------------------------------------------------


## A new Walk (ScoreWalk.begin): no Skip waits or is armed.
static func clear_skip(walk: MatchState.WalkState) -> void:
	walk.hook_pending = 0
	walk.hook_card = -1
	walk.hook_moves = 0


## At a reveal in the Walk (ScoreWalk.reveal_stage): the Skips waiting for the next reveal
## now apply to `card`, after its On reveal Batch drains (skip_hook()).
static func arm_skip(state: MatchState, card: int) -> void:
	var walk: MatchState.WalkState = state.walk
	if walk.hook_pending <= 0:
		return
	walk.hook_card = card
	walk.hook_moves = walk.hook_pending
	walk.hook_pending = 0


## The reveal-stage hook (resolution step 10), after D7 and before the score stage: the
## armed card moves to a different random free slot of its row once per Skip
## (Movement.move_to); each move's On moved Batch is queued for D8. An Anchored card does
## not move. Nothing when no card is armed.
static func skip_hook(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> void:
	var walk: MatchState.WalkState = state.walk
	var card: int = walk.hook_card
	var moves: int = walk.hook_moves
	walk.hook_card = -1
	walk.hook_moves = 0
	if card < 0 or rng == null:
		return
	for _move: int in range(moves):
		var seat: int = Statuses.row_seat(state, card)
		if seat < 0 or Statuses.is_anchored(state, cards, card, seat):
			return
		var free: Array[int] = Movement.free_slots(state, cards, seat)
		var from: int = free.find(state.seats[seat].board.find(card))
		if free.size() < 2 or from < 0:
			return
		var pick: int = rng.pick_index(free.size() - 1)
		if pick >= from:
			pick += 1
		var moved: Array[int] = Movement.move_to(state, cards, card, pick, VERB_SKIP, sink)
		if moved.is_empty():
			continue
		if TriggerQueue.wake(state, cards, CardAbility.MOMENT_MOVED, moved).is_empty():
			pass  # Nothing watches the move.


## Shake on one row: each card of `chosen` on `seat`'s row steps one slot left together on
## the ring (Movement.step_left_set, through Fence); a chosen Anchored card stays and a
## mover passes over an Anchored card. Returns the cards whose slot changed.
static func shake_row(
	state: MatchState, cards: MatchCards, seat: int, chosen: Array[int], sink: Callable
) -> Array[int]:
	return Movement.step_left_set(state, cards, seat, chosen, VERB_SHAKE, sink)


# --- Preparing --------------------------------------------------------------------------


## Tithe: a Condemned card Discarded by the exit pass, a next Turn in the Round, and fewer
## than `cap` grants from this Tithe this turn end.
static func _prepare_tithe(ctx: TriggerContext) -> void:
	var reason: String = ctx.context.get(KEY_REASON, "")
	if reason != TurnFlow.REASON_CONDEMNED or ctx.state.turn >= MatchRules.TURNS:
		ctx.fizzle(Abilities.REASON_NO_TARGET)
	elif ctx.ability.cap > 0 and _used(ctx.state, ctx.card) >= ctx.ability.cap:
		ctx.fizzle(Abilities.REASON_SPENT)


## Reliquary: a card that came from the hand (an exit-pass or Round-end Discard comes from a
## row), its first time this Turn, a Mult below its cap.
static func _prepare_reliquary(ctx: TriggerContext) -> void:
	var from: String = ctx.context.get(KEY_FROM, TurnFlow.FROM_HAND)
	if from != TurnFlow.FROM_HAND:
		ctx.fizzle(Abilities.REASON_NO_TARGET)
	elif _used(ctx.state, ctx.card) > 0:
		ctx.fizzle(Abilities.REASON_SPENT)
	elif ctx.ability.cap > 0:
		var mult: int = Scoring.stats(ctx.card, ctx.state, ctx.cards).mult()
		Abilities.need(ctx, mult < ctx.ability.cap)


## The row positions of `ctx`'s other cards that can be Condemned (Glutton, Immolator).
static func _condemnable_others(ctx: TriggerContext) -> Array[int]:
	var out: Array[int] = []
	var row: Array[int] = ctx.state.seats[ctx.seat].board
	for slot: int in range(row.size()):
		var other: int = row[slot]
		if other == ctx.card:
			continue
		if not Statuses.is_protected(ctx.state, ctx.cards, other, Statuses.CONDEMNED):
			out.append(slot)
	return out


## Targets `options` of the Controller's row: one card (`multi` false), or an optional
## count of any size (`multi` true, always a prompt, Q9).
static func _choose_own(ctx: TriggerContext, options: Array[int], multi: bool) -> void:
	if multi:
		if ctx.choose(Choice.Zone.OWN_BOARD, options, true, Choice.ANY_SIZE, 0):
			pass  # An optional count always prompts.
	elif ctx.choose(Choice.Zone.OWN_BOARD, options):
		pass  # One card: chosen at once.


## Shepherd: fizzles when it is Anchored; else targets another not Anchored card of its row.
static func _prepare_shepherd(ctx: TriggerContext) -> void:
	if Statuses.is_anchored(ctx.state, ctx.cards, ctx.card):
		ctx.fizzle(Abilities.REASON_NO_TARGET)
		return
	var options: Array[int] = []
	var row: Array[int] = ctx.state.seats[ctx.seat].board
	for slot: int in range(row.size()):
		var other: int = row[slot]
		if other != ctx.card and not Statuses.is_anchored(ctx.state, ctx.cards, other):
			options.append(slot)
	_choose_own(ctx, options, false)


## Exhume: one optional "up to `amount`" multi-select over both Piles (C15 2a), `min` 0
## so it always prompts; both Piles empty fizzles.
static func _prepare_exhume(ctx: TriggerContext) -> void:
	var count: int = Choice.zone_cards(ctx.state, ctx.seat, Choice.Zone.BOTH_PILES).size()
	var most: int = maxi(ctx.ability.amount, 0)
	if ctx.choose(
		Choice.Zone.BOTH_PILES,
		Abilities.positions(count),
		true,
		Choice.ANY_SIZE,
		0,
		true,
		-1,
		"",
		most
	):
		pass  # An optional count: never chosen at once.


## Cull: the first seat (Controller, then opponent) whose row is over the kept count chooses;
## none fizzles.
static func _prepare_cull(ctx: TriggerContext) -> void:
	var first: int = _cull_next(ctx, -1)
	if first < 0:
		ctx.fizzle(Abilities.REASON_NO_TARGET)
		return
	_cull_ask(ctx, first)


## The next seat after `after` (-1 for the start) in the order Controller, opponent whose
## row holds more than Cull's `amount` cards; -1 when none.
static func _cull_next(ctx: TriggerContext, after: int) -> int:
	var order: Array[int] = [ctx.seat, 1 - ctx.seat]
	var start: int = order.find(after) + 1
	for at: int in range(start, order.size()):
		if ctx.state.seats[order[at]].board.size() > ctx.ability.amount:
			return order[at]
	return -1


## Asks `by_seat` to choose exactly Cull's `amount` cards of its own row.
static func _cull_ask(ctx: TriggerContext, by_seat: int) -> void:
	var keep: int = ctx.ability.amount
	ctx.data[DATA_ASKED] = by_seat
	var options: Array[int] = Abilities.positions(ctx.state.seats[by_seat].board.size())
	if ctx.choose(Choice.Zone.OWN_BOARD, options, true, keep, keep, false, by_seat):
		pass  # Never: the row holds more than `keep` cards, so this always prompts.


# --- Resolving: Graveyard ---------------------------------------------------------------


## Fuse: Power +amount until it leaves the row; then at `amount_2` or more Power it Condemns
## itself and one random opposing card, drawn from the whole row (a miss: _condemn_pick()).
static func _fuse(ctx: TriggerContext) -> void:
	ctx.state.card_state_for(ctx.card).power_delta += ctx.ability.amount
	Abilities.stats_changed(ctx, ctx.card, false)
	if Scoring.stats(ctx.card, ctx.state, ctx.cards).power < ctx.ability.amount_2:
		return
	_condemn(ctx, ctx.card)
	var enemy: Array[int] = ctx.state.seats[1 - ctx.seat].board
	if enemy.is_empty() or ctx.rng == null:
		return
	_condemn_pick(ctx, enemy[ctx.rng.pick_index(enemy.size())])


## Tithe: +amount Energy next Turn for the seat (`next_turn_grants`, moved in at turn end),
## counted against the cap; ENERGY_GRANTED {seat, amount, source, next_turn: true}.
static func _tithe(ctx: TriggerContext) -> void:
	var amount: int = ctx.ability.amount
	ctx.state.energy.next_turn_grants[ctx.seat] += amount
	_use(ctx.state, ctx.card)
	var granted: Dictionary = {
		"seat": ctx.seat, "amount": amount, "source": ctx.card, "next_turn": true
	}
	ctx.emit(MatchEvent.Kind.ENERGY_GRANTED, granted)


## Reliquary: Mult ×amount for the match (Memory), capped at `cap`; used for this Turn.
static func _reliquary(ctx: TriggerContext) -> void:
	_use(ctx.state, ctx.card)
	var kept: CardMemory = ctx.state.memory_for(ctx.card)
	kept.mult_times_steps.append(ctx.ability.amount)
	kept.mult_cap = maxi(kept.mult_cap, ctx.ability.cap)
	Abilities.stats_changed(ctx, ctx.card, true)


## Glutton: the chosen card is Condemned; Glutton gains its Power (read now) until it
## leaves the row.
static func _glutton(ctx: TriggerContext) -> void:
	var target: int = ctx.chosen_card()
	if target < 0 or not ctx.state.seats[ctx.seat].board.has(target):
		return
	var gained: int = Scoring.stats(target, ctx.state, ctx.cards).power
	_condemn(ctx, target)
	ctx.state.card_state_for(ctx.card).power_delta += gained
	Abilities.stats_changed(ctx, ctx.card, false)


## Revive: the chosen Pile card is placed face down in the slot right of Revive (Placement:
## no On moved, the cursor rules reach it this Walk), CARD_PLACED; then Revive Condemns
## itself.
static func _revive(ctx: TriggerContext) -> void:
	var target: int = ctx.chosen_card()
	var piles: MatchState.SeatPiles = ctx.state.seats[ctx.seat]
	var own: int = piles.board.find(ctx.card)
	if target < 0 or not piles.pile.has(target) or own < 0:
		return
	piles.pile.erase(target)
	if ctx.state.clear_card_state(target):
		pass  # No Board change survives the Pile.
	var slot: int = Movement.place(ctx.state, ctx.seat, target, own + 1)
	var placed: Dictionary = {"seat": ctx.seat, "card": target, "from": FROM_PILE, "slot": slot}
	ctx.emit(MatchEvent.Kind.CARD_PLACED, placed)
	_condemn(ctx, ctx.card)


## Exhume: each chosen card (all read before any moves, since a shuffle-in shifts the Pile
## positions after it) goes into its Owner's Deck at a random position, in position order.
static func _exhume(ctx: TriggerContext) -> void:
	for card: int in ctx.chosen_cards():
		_shuffle_in(ctx, card)


## Puts `card` from its Pile into its Owner's Deck at a random position drawn from the
## stream (glossary "shuffle into"), PILE_SHUFFLED_IN {seat, count: 1, pile_cards}.
static func _shuffle_in(ctx: TriggerContext, card: int) -> void:
	var holder: int = -1
	for seat: int in range(ctx.state.seats.size()):
		if ctx.state.seats[seat].pile.has(card):
			holder = seat
	if card < 0 or holder < 0:
		return
	ctx.state.seats[holder].pile.erase(card)
	var owner: int = ctx.cards.origin_of(card)
	if owner < 0:
		owner = holder
	Abilities.insert_at_random(ctx.state.seats[owner].deck, card, ctx.rng)
	var shuffled: Dictionary = {"seat": owner, "count": 1, KEY_PILE_CARDS: [card]}
	ctx.emit(MatchEvent.Kind.PILE_SHUFFLED_IN, shuffled)


## Immolator: each chosen card is Condemned, then as many distinct random opposing cards,
## drawn from the whole row; a pick that misses (_condemn_pick()) still counts as one.
static func _immolate(ctx: TriggerContext) -> void:
	var count: int = 0
	for card: int in ctx.chosen_cards():
		if card >= 0 and _condemned(ctx, card):
			count += 1
	var pool: Array[int] = []
	pool.assign(ctx.state.seats[1 - ctx.seat].board)
	if ctx.rng == null:
		return
	for _pick: int in range(mini(count, pool.size())):
		var at: int = ctx.rng.pick_index(pool.size())
		_condemn_pick(ctx, pool[at])
		pool.remove_at(at)


## Reset: each seat's Pile into its Deck, which is shuffled (first seat's first); then Reset
## Condemns itself.
static func _reset(ctx: TriggerContext) -> void:
	for seat: int in [ctx.state.first_seat, 1 - ctx.state.first_seat]:
		pile_into_deck(ctx, seat)
	_condemn(ctx, ctx.card)


## `seat`'s whole Pile goes into its Deck, which is then shuffled with the stream;
## PILE_SHUFFLED_IN {seat, count}, public. Nothing for an empty Pile (Reset, Dredger).
static func pile_into_deck(ctx: TriggerContext, seat: int) -> void:
	var piles: MatchState.SeatPiles = ctx.state.seats[seat]
	var count: int = piles.pile.size()
	if count == 0:
		return
	piles.deck.append_array(piles.pile)
	piles.pile.clear()
	if ctx.rng != null:
		ctx.rng.shuffle_in_place(piles.deck)
	ctx.emit(MatchEvent.Kind.PILE_SHUFFLED_IN, {"seat": seat, "count": count})


# --- Resolving: Control -----------------------------------------------------------------


## The Control verbs.
static func _resolve_control(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_EDDY:
			var add: int = ctx.ability.amount
			ctx.state.card_state_for(ctx.card).grant(CardState.KIND_ADD, add, Abilities.SCOPE_TURN)
			Abilities.stats_changed(ctx, ctx.card, false)
		VERB_PIN:
			var target: int = ctx.chosen_card()
			var cease: Dictionary = Statuses.cessation(
				Statuses.CEASE_CONDITION, Statuses.CONDITION_SOURCE_ON_ROW, ctx.card
			)
			var applied: Statuses.Applied = Statuses.apply(
				ctx.state, ctx.cards, target, Statuses.ANCHORED, cease, ctx.verb, ctx.sink
			)
			if not applied.ok():
				pass  # A card on no row takes nothing.
		VERB_SHEPHERD:
			var other: int = ctx.chosen_card()
			ctx.wake_moved(Movement.swap(ctx.state, ctx.cards, ctx.card, other, ctx.verb, ctx.sink))
		VERB_SKIP:
			ctx.state.walk.hook_pending += 1
		VERB_SHAKE:
			_shake(ctx)
		VERB_TEMPEST:
			var opposing: int = 1 - ctx.seat
			ctx.wake_moved(Movement.reverse(ctx.state, ctx.cards, opposing, ctx.verb, ctx.sink))
		VERB_CULL:
			_cull(ctx)


## Shake: per row (first seat's first) a random half of its cards, rounded down, drawn from
## the stream, step left together (shake_row()); one On moved Batch for both rows.
static func _shake(ctx: TriggerContext) -> void:
	if ctx.rng == null:
		return
	var moved: Array[int] = []
	for seat: int in [ctx.state.first_seat, 1 - ctx.state.first_seat]:
		var pool: Array[int] = []
		pool.assign(ctx.state.seats[seat].board)
		@warning_ignore("integer_division")
		var half: int = pool.size() / 2
		var chosen: Array[int] = []
		for _pick: int in range(half):
			var at: int = ctx.rng.pick_index(pool.size())
			chosen.append(pool[at])
			pool.remove_at(at)
		if not chosen.is_empty():
			moved.append_array(shake_row(ctx.state, ctx.cards, seat, chosen, ctx.sink))
	ctx.wake_moved(moved)


## Cull: records the answering seat's kept cards, asks the next seat over the count, and
## once every such seat has chosen Condemns every card those rows did not keep.
static func _cull(ctx: TriggerContext) -> void:
	var asked: int = ctx.data.get(DATA_ASKED, -1)
	if asked < 0 or asked > 1:
		return
	var kept: Array = MatchState.plain(ctx.chosen_cards())
	ctx.data[DATA_KEPT[asked]] = kept
	var next: int = _cull_next(ctx, asked)
	if next >= 0:
		_cull_ask(ctx, next)  # Always a prompt: the row holds more than `amount` cards.
		return
	for seat: int in [ctx.seat, 1 - ctx.seat]:
		if not ctx.data.has(DATA_KEPT[seat]):
			continue
		var keeping: Array = ctx.data[DATA_KEPT[seat]]
		var row: Array[int] = []
		row.assign(ctx.state.seats[seat].board)
		for card: int in row:
			if not keeping.has(card):
				_condemn(ctx, card)


# --- Helpers ----------------------------------------------------------------------------


## Condemns `card` (a protection may block it: Bastion); true when the mark landed. A
## Condemned card still Scores and fires this Walk (Q10).
static func _condemned(ctx: TriggerContext, card: int) -> bool:
	return Statuses.mark_exit(ctx.state, ctx.cards, card, Statuses.CONDEMNED, ctx.sink)


## Condemns `card`, whether or not a protection blocks it (_condemned()).
static func _condemn(ctx: TriggerContext, card: int) -> void:
	if _condemned(ctx, card):
		pass  # Marked: it leaves at turn end.


## Condemns the random pick `card` (Fuse, Immolator; rules 9, cycle 14 R3, C2 2b): a card
## already holding the Condemned mark, or one a protection keeps from it (Bastion), is a
## visible miss, one TRIGGER_FIZZLED for this pick with reason `already_marked` or
## `protected` (TriggerQueue.missed()); the trigger itself has fired and its draw is spent.
static func _condemn_pick(ctx: TriggerContext, card: int) -> void:
	if Statuses.exit_mark_of(ctx.state, card) == Statuses.CONDEMNED:
		TriggerQueue.missed(ctx, Abilities.REASON_ALREADY_MARKED)
	elif not _condemned(ctx, card):
		TriggerQueue.missed(ctx, Abilities.REASON_PROTECTED)


## The uses `card` has counted this Turn (KIND_USED entries of its Board changes).
static func _used(state: MatchState, card: int) -> int:
	var held: CardState = state.card_state(card)
	if held == null:
		return 0
	var total: int = 0
	for value: int in held.granted_of(KIND_USED):
		total += value
	return total


## Counts one use of `card` until end of turn.
static func _use(state: MatchState, card: int) -> void:
	state.card_state_for(card).grant(KIND_USED, 1, Abilities.SCOPE_TURN)


## `card`'s own Ongoing ability with `verb` while it is read (a revealed row card, not
## Squelched), or null. `known_seat`: its row seat when the caller knows it.
static func own_ongoing(
	state: MatchState,
	cards: MatchCards,
	card: int,
	verb: String,
	known_seat: int = Statuses.SEAT_UNKNOWN
) -> CardAbility:
	if not cards.has_verb(verb):
		return null
	var def: CardDef = cards.def_of(card) if card >= 0 else null
	if def == null or not def.has_verb(verb):
		return null
	var seat: int = known_seat
	if seat == Statuses.SEAT_UNKNOWN:
		seat = Statuses.row_seat(state, card)
	if seat < 0 or not state.seats[seat].is_revealed(card):
		return null
	if not Scoring.reads_ongoing(state, card):
		return null
	for ability: CardAbility in def.abilities:
		if ability.moment == CardAbility.MOMENT_ONGOING and ability.verb == verb:
			return ability
	return null


## Whether an Ongoing with `verb` is read on either row now.
static func _read_anywhere(state: MatchState, cards: MatchCards, verb: String) -> bool:
	if cards == null or not cards.has_verb(verb):
		return false
	for seat: int in range(state.seats.size()):
		if not Scoring.ongoing_on_row(state, cards, seat, verb).is_empty():
			return true
	return false


