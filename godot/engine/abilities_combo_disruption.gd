class_name AbilitiesComboDisruption
extends RefCounted
## The Combo and Disruption card abilities (DC-14 T12; cycle 9 plan P3, P6, P11, P12; canon
## [[rules/cards-v2]] sections 2.2 and 2.3). Abilities dispatches every verb of VERBS here
## (handles(), then prepare() and resolve() as its own); pure like it: no node, no clock,
## every random pick from the engine stream (TriggerContext.rng).
##
## Combo:
## - `wick` (Wick, On score): draws `amount`, then Power -`amount` as a Board change; then,
##   with its Power read now 0 or less (Q5), it gets Fleeting.
## - `fade_other_own` (Swell): another card of the Controller's row, chosen (Q9), gets Fade.
## - `fleeting_chosen` (Reprieve): a card on either row (zone both_boards), chosen, gets
##   Fleeting; its Controller does not change.
## - `scrap` (Scrap): a hand card, chosen, is Discarded (its own On discard Batch); this card
##   gets Add +N until end of turn, N = `amount` per point of that card's Cost read now,
##   at most `cap`.
## - `copy_self_to_hand` (Twin): a created copy of this card (base values, no Memory) goes to
##   the Controller's hand, Owned by that seat (create(), CARD_CREATED).
## - `scores_twice` (Reprise, On commit): every later score stage this Turn runs twice (Q7).
## - `retrigger_reveals` (Encore): the Controller's other On reveals resolve twice this Turn
##   (TriggerQueue.add_retrigger, Q6).
## - `reverb` (Reverb): Fleeting, and Cost -`amount` for the match (Memory).
## - `finale` (Finale): Power +`amount` until end of turn for each other card of the
##   Controller's row revealed this Turn, counted now (Q5: cards to its right are not yet).
## Disruption:
## - `mute_opposing` (Hush), `squelch_opposing` (Muzzle), `silence_opposing` (Eclipse): an
##   opposing card, chosen by slot (face down too), gets the status until end of turn; a
##   Squelch half lasts while a read Stasis of the Controller stays on its row instead
##   (squelch_cessation()). Silence applies the Mute half first, so a Ward's "cannot be
##   Muted" leaves a Squelch alone, which wakes On squelch (C24).
## - `create_dross` (Litter): `amount` Dross created in the opponent's hand, Owned by it.
## - `move_to_opposing` (Saboteur): this card moves to the rightmost slot of the other row
##   (a Move of an unanchored card: On moved wakes for it); its Owner is kept, its Controller
##   is the row's seat (CONTROL_CHANGED). It Scores for that seat when the Walk reaches it
##   and goes to its Owner's Pile at Round end (TurnFlow.to_pile reads the Owner).
## - `hex_choose` (Hex, On reveal): a card on either row is chosen and kept in
##   MatchState.chosen until either card leaves its row or is Un-revealed; `mute_chosen`
##   (Hex, On start) Mutes the kept card until end of turn.
## - `mute_random_opposing` (Jam, On score): N = this card's Power now; N random opposing
##   cards (all of them when fewer) are Muted until end of turn.
## - `stasis` (Stasis): Ongoing, read by squelch_cessation().
## - `gag` (Gag, On commit): an opposing card, chosen, is Squelched permanently (Memory),
##   then this card is Condemned.
## - `quorum` (Quorum, On start): each seat with more than `amount` revealed cards chooses
##   `amount` of them, the Turn's first seat first, then the second (two prompts in one
##   resolution: the second opens from resolve()); then every other revealed card on both
##   rows is Muted until end of turn.
## - `dross_walk_end` (Dross, Ongoing while in hand): at Walk end, before rounding, the
##   holder's walking total is multiplied by `amount` hundredths per Dross
##   (walk_end_total(), called by ScoreWalk.finish).
##
## Created cards (plan P6): create() takes the next id from MatchState.next_created_id,
## records the definition and Owner in MatchState.created and MatchCards.record_created, so
## def_of() and origin_of() answer; CARD_CREATED {seat, card, def, owner, to, slot} is
## public (the creation is public; the card in a hand is then that seat's hidden card).

const VERB_WICK: String = "wick"
const VERB_FADE_OTHER_OWN: String = "fade_other_own"
const VERB_FLEETING_CHOSEN: String = "fleeting_chosen"
const VERB_SCRAP: String = "scrap"
const VERB_COPY_SELF: String = "copy_self_to_hand"
const VERB_SCORES_TWICE: String = "scores_twice"
const VERB_RETRIGGER: String = "retrigger_reveals"
const VERB_REVERB: String = "reverb"
const VERB_FINALE: String = "finale"
const VERB_MUTE_OPPOSING: String = "mute_opposing"
const VERB_SQUELCH_OPPOSING: String = "squelch_opposing"
const VERB_SILENCE_OPPOSING: String = "silence_opposing"
const VERB_CREATE_DROSS: String = "create_dross"
const VERB_MOVE_TO_OPPOSING: String = "move_to_opposing"
const VERB_HEX_CHOOSE: String = "hex_choose"
const VERB_MUTE_CHOSEN: String = "mute_chosen"
const VERB_MUTE_RANDOM: String = "mute_random_opposing"
const VERB_STASIS: String = "stasis"
const VERB_GAG: String = "gag"
const VERB_QUORUM: String = "quorum"
const VERB_DROSS: String = "dross_walk_end"
## Every verb this module handles (the Ongoing ones are read, never queued).
const VERBS: Array[String] = [
	VERB_WICK,
	VERB_FADE_OTHER_OWN,
	VERB_FLEETING_CHOSEN,
	VERB_SCRAP,
	VERB_COPY_SELF,
	VERB_SCORES_TWICE,
	VERB_RETRIGGER,
	VERB_REVERB,
	VERB_FINALE,
	VERB_MUTE_OPPOSING,
	VERB_SQUELCH_OPPOSING,
	VERB_SILENCE_OPPOSING,
	VERB_CREATE_DROSS,
	VERB_MOVE_TO_OPPOSING,
	VERB_HEX_CHOOSE,
	VERB_MUTE_CHOSEN,
	VERB_MUTE_RANDOM,
	VERB_GAG,
	VERB_QUORUM,
]
## The pool id of Dross (cards.json, `"created": true`).
const DROSS_ID: String = "dross"
## CARD_CREATED `to`.
const TO_HAND: String = "hand"
const TO_ROW: String = "row"
## MatchState.created keys.
const KEY_DEF: String = "def"
const KEY_OWNER: String = "owner"
## ctx.data keys of Quorum's two prompts: the position in the commit order being asked,
## and the cards kept so far.
const DATA_STAGE: String = "stage"
const DATA_KEPT: String = "kept"
const MOMENT_ONGOING: String = "ongoing"

# --- The dispatch -------------------------------------------------------------------------


## Whether `verb` is one of this module's queued verbs.
static func handles(verb: String) -> bool:
	return VERBS.has(verb)


## Abilities.prepare() for this module's verbs: fizzles with no eligible target, targets
## through ctx.choose() (Q9), or leaves the verb to resolve().
static func prepare(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_FADE_OTHER_OWN:
			_choose_own_other(ctx)
		VERB_FLEETING_CHOSEN, VERB_HEX_CHOOSE:
			_choose_either_row(ctx)
		VERB_SCRAP:
			_choose_hand(ctx)
		VERB_MUTE_OPPOSING, VERB_SQUELCH_OPPOSING, VERB_SILENCE_OPPOSING, VERB_GAG:
			_choose_opposing(ctx)
		VERB_WICK, VERB_COPY_SELF, VERB_REVERB, VERB_FINALE:
			Abilities.need(ctx, Statuses.row_seat(ctx.state, ctx.card) >= 0)
		VERB_MOVE_TO_OPPOSING:
			Abilities.need(ctx, _can_cross(ctx))
		VERB_CREATE_DROSS:
			Abilities.need(ctx, ctx.cards.pool_def(DROSS_ID) != null)
		VERB_MUTE_CHOSEN:
			Abilities.need(ctx, kept_choice(ctx.state, ctx.card) >= 0)
		VERB_MUTE_RANDOM:
			Abilities.need(ctx, _jam_count(ctx) > 0)
		VERB_QUORUM:
			_prepare_quorum(ctx)
		VERB_SCORES_TWICE, VERB_RETRIGGER:
			pass  # Always ready.
		_:
			ctx.fizzle(Abilities.REASON_NO_TARGET)


## Abilities.resolve() for this module's verbs: the effect, every amount read now (Q5).
static func resolve(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_WICK:
			_wick(ctx)
		VERB_FADE_OTHER_OWN:
			_mark(ctx, ctx.chosen_card(), Statuses.FADE)
		VERB_FLEETING_CHOSEN:
			_mark(ctx, ctx.chosen_card(), Statuses.FLEETING)
		VERB_SCRAP:
			_scrap(ctx)
		VERB_COPY_SELF:
			_twin(ctx)
		VERB_SCORES_TWICE:
			ctx.state.walk.scores_twice = true
		VERB_RETRIGGER:
			TriggerQueue.add_retrigger(ctx.state, ctx.seat, ctx.card)
		VERB_REVERB:
			_reverb(ctx)
		VERB_FINALE:
			_finale(ctx)
		_:
			_resolve_disruption(ctx)


# --- Reads --------------------------------------------------------------------------------


## The card `source` chose and keeps (Hex), or -1 when it keeps none or the chosen card is
## on no row.
static func kept_choice(state: MatchState, source: int) -> int:
	if not state.chosen.has(source):
		return -1
	var target: int = state.chosen[source]
	return target if Statuses.row_seat(state, target) >= 0 else -1


## The cessation of a Squelch applied by an effect of `seat` (Stasis): while a read Stasis
## is on that seat's row, the Squelch lasts until that Stasis leaves its row (a condition
## sourced on it, Statuses.CONDITION_SOURCE_ON_ROW); else until end of turn.
static func squelch_cessation(state: MatchState, cards: MatchCards, seat: int) -> Dictionary:
	var stasis: int = _read_stasis(state, cards, seat)
	if stasis < 0:
		return Statuses.cessation(Statuses.CEASE_TURN)
	return Statuses.cessation(
		Statuses.CEASE_CONDITION, Statuses.CONDITION_SOURCE_ON_ROW, stasis
	)


## How many Dross (a hand card with the Ongoing `dross_walk_end`) `seat` holds now; 0 with
## no `cards` or when no card of the match has the verb.
static func dross_in_hand(state: MatchState, cards: MatchCards, seat: int) -> int:
	return _dross_amounts(state, cards, seat).size()


## `seat`'s walking total at Walk end before rounding (canon cards-v2 section 1, C32): its
## total multiplied by each of its hand's Dross amounts in turn (×0.75 each), each multiply
## rounded to the ten-thousandth (Scoring.round_half_up, P7).
static func walk_end_total(state: MatchState, cards: MatchCards, seat: int) -> int:
	var total: int = state.totals[seat]
	for amount: int in _dross_amounts(state, cards, seat):
		total = Scoring.round_half_up(total * amount, MatchRules.BONUS_ONE)
	return total


# --- Created cards ------------------------------------------------------------------------


## Creates a card of `def` Owned by `owner` (plan P6): the next created id, recorded in
## MatchState.created and MatchCards.record_created. Returns the id; nowhere yet (the
## caller places it). -1 when `def` is null.
static func create(state: MatchState, cards: MatchCards, def: CardDef, owner: int) -> int:
	if def == null:
		return -1
	var made: int = state.next_created_id
	state.next_created_id += 1
	if cards != null and not cards.record_created(made, def, owner):
		pass  # Already recorded (a copied state on the same definitions): same id, same card.
	state.created[made] = {KEY_DEF: def.id, KEY_OWNER: owner}
	return made


## Creates a card of `def` into `seat`'s hand, Owned by `seat`: CARD_CREATED {seat, card,
## def, owner, to: hand, slot: -1}, public. Returns its id (-1 for a null `def`).
static func create_in_hand(ctx: TriggerContext, def: CardDef, seat: int) -> int:
	var made: int = create(ctx.state, ctx.cards, def, seat)
	if made < 0:
		return -1
	ctx.state.seats[seat].hand.append(made)
	var payload: Dictionary = {
		"seat": seat, "card": made, "def": def.id, "owner": seat, "to": TO_HAND, "slot": -1
	}
	ctx.emit(MatchEvent.Kind.CARD_CREATED, payload)
	return made


# --- Preparing ----------------------------------------------------------------------------


## Swell: the Controller's other cards on its row (Q9).
static func _choose_own_other(ctx: TriggerContext) -> void:
	var row: Array[int] = ctx.state.seats[ctx.seat].board
	var options: Array[int] = []
	for slot: int in range(row.size()):
		if row[slot] != ctx.card:
			options.append(slot)
	if ctx.choose(Choice.Zone.OWN_BOARD, options):
		pass  # One card: chosen at once.


## Reprieve, Hex: every card on either row (zone both_boards, the Controller's row first).
static func _choose_either_row(ctx: TriggerContext) -> void:
	var count: int = ctx.state.seats[0].board.size() + ctx.state.seats[1].board.size()
	if ctx.choose(Choice.Zone.BOTH_BOARDS, Abilities.positions(count)):
		pass  # One card: chosen at once.


## Scrap: one card of the Controller's hand.
static func _choose_hand(ctx: TriggerContext) -> void:
	var options: Array[int] = Abilities.positions(ctx.state.seats[ctx.seat].hand.size())
	if ctx.choose(Choice.Zone.OWN_HAND, options):
		pass  # One card: chosen at once.


## Hush, Muzzle, Eclipse, Gag: every opposing card, face up or down, by slot.
static func _choose_opposing(ctx: TriggerContext) -> void:
	var options: Array[int] = Abilities.positions(ctx.state.seats[1 - ctx.seat].board.size())
	if ctx.choose(Choice.Zone.OPPONENT_BOARD, options):
		pass  # One card: chosen at once.


## Saboteur can move: it is on a row and not Anchored.
static func _can_cross(ctx: TriggerContext) -> bool:
	if Statuses.row_seat(ctx.state, ctx.card) < 0:
		return false
	return not Statuses.is_anchored(ctx.state, ctx.cards, ctx.card)


## Jam's N, capped by the opposing row: 0 when there is nothing to Mute.
static func _jam_count(ctx: TriggerContext) -> int:
	var power: int = Scoring.stats(ctx.card, ctx.state, ctx.cards).power
	return mini(maxi(power, 0), ctx.state.seats[1 - ctx.seat].board.size())


## Quorum: the first seat in commit order with more than `amount` revealed cards is asked;
## none fizzles (no card would be Muted).
static func _prepare_quorum(ctx: TriggerContext) -> void:
	var kept: Array = []
	ctx.data[DATA_KEPT] = kept
	var stage: int = _quorum_next(ctx, 0)
	if stage < 0:
		ctx.fizzle(Abilities.REASON_NO_TARGET)
		return
	_ask_quorum(ctx, stage)


## The first position from `from` in the commit order whose seat has more than `amount`
## revealed cards, or -1.
static func _quorum_next(ctx: TriggerContext, from: int) -> int:
	var order: Array[int] = _commit_order(ctx.state)
	for at: int in range(from, order.size()):
		if _revealed_slots(ctx.state, order[at]).size() > _quorum_size(ctx):
			return at
	return -1


## Opens Quorum's prompt for the seat at `stage` of the commit order: a set of exactly
## `amount` of its revealed cards (zone own_board for that seat, not optional).
static func _ask_quorum(ctx: TriggerContext, stage: int) -> void:
	ctx.data[DATA_STAGE] = stage
	var asked: int = _commit_order(ctx.state)[stage]
	var options: Array[int] = _revealed_slots(ctx.state, asked)
	var size: int = _quorum_size(ctx)
	if ctx.choose(Choice.Zone.OWN_BOARD, options, true, size, size, false, asked):
		pass  # More options than `amount`: always a prompt.


# --- Resolving: Combo ---------------------------------------------------------------------


## Wick: draws, Power -amount (until it leaves the row), then Fleeting at Power 0 or less.
static func _wick(ctx: TriggerContext) -> void:
	var amount: int = maxi(ctx.ability.amount, 1)
	for _draw: int in range(amount):
		if ctx.draw(ctx.seat) < 0:
			pass  # Empty: DRAW_EMPTY, its On empty draw Batch queued (Q11).
	ctx.state.card_state_for(ctx.card).power_delta -= amount
	Abilities.stats_changed(ctx, ctx.card, false)
	if Scoring.stats(ctx.card, ctx.state, ctx.cards).power <= 0:
		_mark(ctx, ctx.card, Statuses.FLEETING)


## Gives `card` (on a row) the exit mark `mark` (a newer mark replaces an older, Q10).
static func _mark(ctx: TriggerContext, card: int, mark: String) -> void:
	if card < 0:
		return
	if Statuses.mark_exit(ctx.state, ctx.cards, card, mark, ctx.sink):
		pass  # Resolved in the exit pass at turn end.


## Scrap: the chosen hand card's Cost is read, it is Discarded, then this card gets Add +N
## until end of turn (N = amount per point of Cost, at most cap; none for Cost 0).
static func _scrap(ctx: TriggerContext) -> void:
	var discarded: int = ctx.chosen_card()
	if discarded < 0 or not ctx.state.seats[ctx.seat].hand.has(discarded):
		return
	var cost: int = maxi(Scoring.effective_cost(discarded, ctx.state, ctx.cards), 0)
	Abilities.discard(ctx, discarded)
	var add: int = ctx.ability.amount * cost
	if ctx.ability.cap > 0:
		add = mini(add, ctx.ability.cap)
	if add <= 0 or Statuses.row_seat(ctx.state, ctx.card) < 0:
		return
	ctx.state.card_state_for(ctx.card).grant(CardState.KIND_ADD, add, Abilities.SCOPE_TURN)
	Abilities.stats_changed(ctx, ctx.card, false)


## Twin: a created copy of this card's definition (base values, no Memory) into the
## Controller's hand.
static func _twin(ctx: TriggerContext) -> void:
	var def: CardDef = ctx.cards.def_of(ctx.card)
	if create_in_hand(ctx, def, ctx.seat) < 0:
		pass  # No definition: nothing to copy.


## Reverb: Fleeting, then Cost -amount for the match (Memory, floor 0 at the read).
static func _reverb(ctx: TriggerContext) -> void:
	_mark(ctx, ctx.card, Statuses.FLEETING)
	ctx.state.memory_for(ctx.card).cost_delta -= ctx.ability.amount
	Abilities.stats_changed(ctx, ctx.card, true)


## Finale: Power +amount until end of turn per other card of the Controller's row revealed
## this Turn (read now, Q5).
static func _finale(ctx: TriggerContext) -> void:
	var count: int = 0
	var revealed: Dictionary[int, bool] = ctx.state.walk.revealed_this_turn
	for other: int in ctx.state.seats[ctx.seat].board:
		if other != ctx.card and revealed.has(other):
			count += 1
	var gain: int = ctx.ability.amount * count
	if gain <= 0:
		return
	var held: CardState = ctx.state.card_state_for(ctx.card)
	held.power_delta += gain
	held.grant(Abilities.KIND_POWER, gain, Abilities.SCOPE_TURN)
	Abilities.stats_changed(ctx, ctx.card, false)


# --- Resolving: Disruption ----------------------------------------------------------------


## The Disruption verbs.
static func _resolve_disruption(ctx: TriggerContext) -> void:
	match ctx.verb:
		VERB_MUTE_OPPOSING:
			_mute(ctx, ctx.chosen_card())
		VERB_SQUELCH_OPPOSING:
			_squelch(ctx, ctx.chosen_card(), squelch_cessation(ctx.state, ctx.cards, ctx.seat))
		VERB_SILENCE_OPPOSING:
			_silence(ctx, ctx.chosen_card())
		VERB_CREATE_DROSS:
			_litter(ctx)
		VERB_MOVE_TO_OPPOSING:
			_saboteur(ctx)
		VERB_HEX_CHOOSE:
			var target: int = ctx.chosen_card()
			if target >= 0:
				ctx.state.chosen[ctx.card] = target
		VERB_MUTE_CHOSEN:
			_mute(ctx, kept_choice(ctx.state, ctx.card))
		VERB_MUTE_RANDOM:
			_jam(ctx)
		VERB_GAG:
			_gag(ctx)
		VERB_QUORUM:
			_resolve_quorum(ctx)


## Mutes `card` until end of turn (a Ward-like protection drops it, R37).
static func _mute(ctx: TriggerContext, card: int) -> void:
	if card < 0:
		return
	var cease: Dictionary = Statuses.cessation(Statuses.CEASE_TURN)
	var applied: Statuses.Applied = Statuses.apply(
		ctx.state, ctx.cards, card, Statuses.MUTED, cease, ctx.verb, ctx.sink
	)
	ctx.wake_squelch(card, applied)


## Squelches `card` with `cease`; On squelch wakes when it lands alone (R34).
static func _squelch(ctx: TriggerContext, card: int, cease: Dictionary) -> void:
	if card < 0:
		return
	var applied: Statuses.Applied = Statuses.apply(
		ctx.state, ctx.cards, card, Statuses.SQUELCHED, cease, ctx.verb, ctx.sink
	)
	ctx.wake_squelch(card, applied)


## Eclipse: Silence until end of turn as its two halves, the Mute half first (so a blocked
## Mute leaves a lone Squelch that wakes On squelch, C24); the Squelch half follows Stasis.
static func _silence(ctx: TriggerContext, card: int) -> void:
	if card < 0:
		return
	_mute(ctx, card)
	_squelch(ctx, card, squelch_cessation(ctx.state, ctx.cards, ctx.seat))


## Litter: `amount` Dross created in the opponent's hand, each Owned by that seat.
static func _litter(ctx: TriggerContext) -> void:
	var dross: CardDef = ctx.cards.pool_def(DROSS_ID)
	var opponent: int = 1 - ctx.seat
	for _made: int in range(maxi(ctx.ability.amount, 1)):
		if create_in_hand(ctx, dross, opponent) < 0:
			return


## Saboteur: off its row (a removal behind the pulsed slot moves the cursor back by one so
## no card is skipped; the pulsed slot itself keeps it, so the card sliding in Scores now),
## then onto the rightmost slot of the other row (Movement.place: ahead of that row's
## cursor, reached later this Walk), face up as it was. CONTROL_CHANGED {card, owner,
## controller, from_seat, slot}, public; On moved wakes for it.
static func _saboteur(ctx: TriggerContext) -> void:
	var from_seat: int = Statuses.row_seat(ctx.state, ctx.card)
	if from_seat < 0:
		return
	var to_seat: int = 1 - from_seat
	var from_piles: MatchState.SeatPiles = ctx.state.seats[from_seat]
	var slot: int = from_piles.board.find(ctx.card)
	var was_revealed: bool = from_piles.revealed.erase(ctx.card)
	from_piles.board.remove_at(slot)
	var walk: MatchState.WalkState = ctx.state.walk
	if walk.active and slot < walk.cursor[from_seat] - 1:
		walk.cursor[from_seat] -= 1
	var to_piles: MatchState.SeatPiles = ctx.state.seats[to_seat]
	var at: int = Movement.place(ctx.state, to_seat, ctx.card, to_piles.board.size())
	if was_revealed:
		to_piles.revealed[ctx.card] = true
	var changed: Dictionary = {
		"card": ctx.card,
		"owner": ctx.cards.origin_of(ctx.card),
		"controller": to_seat,
		"from_seat": from_seat,
		"slot": at,
	}
	ctx.emit(MatchEvent.Kind.CONTROL_CHANGED, changed)
	var moved: Array[int] = [ctx.card]
	ctx.wake_moved(moved)


## Jam: N random opposing cards (N its Power now, all of them when fewer), each Muted until
## end of turn, in the order picked from the engine stream.
static func _jam(ctx: TriggerContext) -> void:
	var count: int = _jam_count(ctx)
	var pool: Array[int] = []
	pool.assign(ctx.state.seats[1 - ctx.seat].board)
	for _pick: int in range(count):
		if pool.is_empty():
			return
		var at: int = ctx.rng.pick_index(pool.size()) if ctx.rng != null else 0
		var target: int = pool[at]
		pool.remove_at(at)
		_mute(ctx, target)


## Gag: the chosen opposing card is Squelched permanently (Memory), then Gag is Condemned.
static func _gag(ctx: TriggerContext) -> void:
	var target: int = ctx.chosen_card()
	if target < 0:
		return
	_squelch(ctx, target, Statuses.cessation(Statuses.CEASE_PERMANENT))
	_mark(ctx, ctx.card, Statuses.CONDEMNED)


## Quorum after an answer: the answering seat's cards are kept; the next seat with more
## than `amount` revealed cards is asked (a second prompt), else every other revealed card
## on both rows of an affected seat is Muted until end of turn.
static func _resolve_quorum(ctx: TriggerContext) -> void:
	var kept: Array = ctx.data.get(DATA_KEPT, [])
	for at: int in range(ctx.indices.size()):
		kept.append(ctx.chosen_card(at))
	ctx.data[DATA_KEPT] = kept
	var stage: int = ctx.data.get(DATA_STAGE, -1)
	var next: int = _quorum_next(ctx, stage + 1)
	if next >= 0:
		_ask_quorum(ctx, next)
		return
	for seat: int in _commit_order(ctx.state):
		var piles: MatchState.SeatPiles = ctx.state.seats[seat]
		var slots: Array[int] = _revealed_slots(ctx.state, seat)
		if slots.size() <= _quorum_size(ctx):
			continue
		var row: Array[int] = []
		row.assign(piles.board)
		for slot: int in slots:
			if not kept.has(row[slot]):
				_mute(ctx, row[slot])


# --- Helpers ------------------------------------------------------------------------------


## The Turn's commit order: the first seat, then the second.
static func _commit_order(state: MatchState) -> Array[int]:
	var order: Array[int] = [state.first_seat, 1 - state.first_seat]
	return order


## The slots of `seat`'s revealed row cards, ascending.
static func _revealed_slots(state: MatchState, seat: int) -> Array[int]:
	var out: Array[int] = []
	var piles: MatchState.SeatPiles = state.seats[seat]
	for slot: int in range(piles.board.size()):
		if piles.is_revealed(piles.board[slot]):
			out.append(slot)
	return out


## Quorum's kept count per seat (its `amount`, 2).
static func _quorum_size(ctx: TriggerContext) -> int:
	return maxi(ctx.ability.amount, 1)


## The first read Stasis on `seat`'s row (revealed, not Squelched), or -1.
static func _read_stasis(state: MatchState, cards: MatchCards, seat: int) -> int:
	if cards == null or not cards.has_verb(VERB_STASIS):
		return -1
	var piles: MatchState.SeatPiles = state.seats[seat]
	for card: int in piles.board:
		if not piles.is_revealed(card) or not Scoring.reads_ongoing(state, card):
			continue
		for ability: CardAbility in Abilities.on_moment(card, cards, MOMENT_ONGOING):
			if ability.verb == VERB_STASIS:
				return card
	return -1


## The `dross_walk_end` amounts of `seat`'s hand cards, in hand order (one per Dross).
static func _dross_amounts(state: MatchState, cards: MatchCards, seat: int) -> Array[int]:
	var out: Array[int] = []
	if cards == null or not cards.has_verb(VERB_DROSS):
		return out
	for card: int in state.seats[seat].hand:
		for ability: CardAbility in Abilities.on_moment(card, cards, MOMENT_ONGOING):
			if ability.verb == VERB_DROSS and ability.zone == TriggerContext.ZONE_HAND:
				out.append(ability.amount)
	return out


