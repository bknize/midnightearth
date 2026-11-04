class_name DriftEffects
extends RefCounted
## The Drift deck's verbs (DC-07 T07; plan P5, P8, P11, P12; R26, R28, R29, R33-R35, C11,
## C17), split from EffectResolver as RuinEffects is. Pure: no nodes, no clock. A move picks
## nothing at random; only the copy's burst check may draw, from the engine stream passed in
## (R35), and a preview passes a policy and no stream (EffectResolver's preview seam).
##
## Moves (P11): every move, the DC-05 swap included, goes through place() or rewrite_row().
## rewrite_row() writes the row's new order, then emits one CARD_MOVED {seat, card,
## from_slot, to_slot} per card whose slot changed (the `lead` card first when it moved,
## then the rest in their new slot order), public for a revealed card and private to the
## row's seat for a face-down one, so the other seat sees which slots moved but never the
## face-down card's id (R30, R34). Then, on a snapshot of the moved cards that are revealed
## and live taken after the rewrite, each one's ON_MOVED effect fires once (EFFECT_FIRED,
## then the verb's events; R26). The walk's slot cursor does the rest (DC-06 R5-R11, R29): a
## card that lands on a slot its row's cursor has passed is not pulsed again this walk (and
## stays face down until a later walk if it is), one that lands ahead is pulsed when
## reached, and the pulse that ran the effect scores whichever card holds its slot after.
##
## Verbs:
## - MOVE_SELF_LEFT, MOVE_SELF_RIGHT (on reveal): the source to slot 0, or to the last slot.
## - SHIFT_OWN_LEFT (on reveal): the owner's other cards rotate left by one over the slots
##   the source does not hold; the source keeps its slot and the leftmost other card goes to
##   the far right ([A, B, S, C] becomes [B, C, S, A]).
## - REVERSE_OPPONENT_ROW (on reveal): the opponent's row in reverse order.
## - MOVE_OPPONENT_LEFT (prompt; Choice: OPPONENT_BOARD, every position but slot 0, face down
##   or destroyed included, by position): the chosen card is taken out and put at slot 0.
## - SWAP_OPPONENT_RIGHT (prompt; OPPONENT_BOARD, every position but the rightmost): the
##   chosen card and the card to its right exchange slots, the chosen card's CARD_MOVED first.
## - SWAP_PLACES (DC-05, prompt): the source and the chosen own card exchange slots, the
##   source's CARD_MOVED first, as before T07.
## - COPY_STATS (prompt; OPPONENT_BOARD, revealed live cards): the source takes the target's
##   effective flat and bonus at this moment as its new base (CardState `base_*`, P5, R34),
##   STATS_CHANGED (cause copy), then RuinEffects.check_burst() on the source (P10). Later
##   changes to the target do not follow. The base is the target's whole shown bonus: its
##   ×-part and its +-part both (`base_times`, `base_plus`; C22), so a target showing a
##   neighbour's ×1.25 on top of a printed +1, or a move's +2 next to a Lodestone, gives
##   both. The source's own positional ×-parts and modifiers (`flat_delta`, `no_bonus`,
##   `temp_plus`) still apply on top of the new base (P5).
## - PLUS_ON_MOVED (on moved, amount): `temp_plus += amount`, STATS_CHANGED (cause
##   temp_plus); ScoreWalk clears it when the walk ends (P5, R33).
## - NEIGHBOUR_TIMES, EDGE_LEFT_TIMES (ongoing): never fire; ScoreWalk.effective() reads them.

## STATS_CHANGED cause of a copy (DC-07 P5, events table).
const CAUSE_COPY: String = "copy"


## Fires `card`'s Drift verb for `seat` when the verb needs no target (see the class
## comment). EffectResolver.apply() has already added EFFECT_FIRED to `outcome`.
static func apply(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	card: int,
	effect: CardEffect,
	outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	match effect.verb:
		CardEffect.Verb.MOVE_SELF_LEFT:
			place(state, cards, rng, policy, seat, card, 0, outcome)
		CardEffect.Verb.MOVE_SELF_RIGHT:
			place(state, cards, rng, policy, seat, card, piles.board.size() - 1, outcome)
		CardEffect.Verb.SHIFT_OWN_LEFT:
			_shift_left(state, cards, rng, policy, seat, card, outcome)
		CardEffect.Verb.REVERSE_OPPONENT_ROW:
			_reverse(state, cards, rng, policy, 1 - seat, outcome)
		CardEffect.Verb.PLUS_ON_MOVED:
			_plus(state, cards, seat, card, effect.amount, outcome)


## The consequence of a Drift prompt verb (and SWAP_PLACES) once EffectResolver.apply_choice
## has the target: `seat` is the prompted seat (the source's), `holder` the seat whose row
## holds `target`. The events in order; none built under a preview policy.
static func apply_choice(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	verb: int,
	seat: int,
	holder: int,
	source: int,
	target: int
) -> Array[MatchEvent]:
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	outcome.quiet = policy != null
	match verb:
		CardEffect.Verb.SWAP_PLACES:
			swap(state, cards, rng, policy, holder, source, target, outcome)
		CardEffect.Verb.MOVE_OPPONENT_LEFT:
			place(state, cards, rng, policy, holder, target, 0, outcome)
		CardEffect.Verb.SWAP_OPPONENT_RIGHT:
			var right: int = _right_of(state, holder, target)
			if right >= 0:
				swap(state, cards, rng, policy, holder, target, right, outcome)
		CardEffect.Verb.COPY_STATS:
			_copy(state, cards, rng, policy, seat, source, target, outcome)
	return outcome.events


## Moves `card` on `seat`'s row to `to_slot` (clamped to the row): it is taken out and put
## back there, the cards between shifting by one (P11). Nothing when it is not on that row.
static func place(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	card: int,
	to_slot: int,
	outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var from_slot: int = piles.board.find(card)
	if from_slot < 0:
		return
	var order: Array[int] = []
	order.assign(piles.board)
	order.remove_at(from_slot)
	if order.insert(clampi(to_slot, 0, order.size()), card) != OK:
		return  # The slot is clamped into range, so the insert cannot fail.
	rewrite_row(state, cards, rng, policy, seat, order, outcome, card)


## Exchanges the slots of `first` and `second` on `seat`'s row, `first`'s CARD_MOVED first.
## Nothing when either is not on that row or they are the same card.
static func swap(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	first: int,
	second: int,
	outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var first_slot: int = piles.board.find(first)
	var second_slot: int = piles.board.find(second)
	if first_slot < 0 or second_slot < 0 or first == second:
		return
	var order: Array[int] = []
	order.assign(piles.board)
	order[first_slot] = second
	order[second_slot] = first
	rewrite_row(state, cards, rng, policy, seat, order, outcome, first)


## Writes `new_order` (a reordering of `seat`'s row) as that row, then the CARD_MOVED events
## and the ON_MOVED firings (see the class comment). `lead`, when it moved, has its
## CARD_MOVED and its firing first. Nothing when `new_order` is not the row's size.
static func rewrite_row(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	new_order: Array[int],
	outcome: EffectResolver.Outcome,
	lead: int = -1
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if new_order.size() != piles.board.size():
		return  # Not a reordering of this row: every caller passes one.
	var before: Array[int] = []
	before.assign(piles.board)
	piles.board.assign(new_order)
	var moved: Array[int] = []
	if lead >= 0 and before.find(lead) != new_order.find(lead):
		moved.append(lead)
	for slot: int in range(new_order.size()):
		var card: int = new_order[slot]
		if card != before[slot] and card != lead:
			moved.append(card)
	if not outcome.quiet:
		for card: int in moved:
			var from_slot: int = before.find(card)
			var to_slot: int = new_order.find(card)
			outcome.events.append(_moved_event(piles, seat, card, from_slot, to_slot))
	_fire_on_moved(state, cards, rng, policy, seat, moved, outcome)


## The ON_MOVED firings of `moved` (cards of `seat`'s row, in CARD_MOVED order): the ones
## revealed and live once the row is rewritten are snapshotted, then each fires its ON_MOVED
## effect once, while still on the row, face up and live.
static func _fire_on_moved(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	moved: Array[int],
	outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var firing: Array[int] = []
	for card: int in moved:
		if _is_live_face_up(state, piles, card) and _fires_on_moved(card, cards):
			firing.append(card)
	for card: int in firing:
		if not piles.board.has(card) or not _is_live_face_up(state, piles, card):
			continue
		var fired: EffectResolver.Outcome = EffectResolver.apply(
			state, cards, rng, policy, seat, card
		)
		if not outcome.quiet:
			outcome.events.append_array(fired.events)
		# PLUS_ON_MOVED is the only ON_MOVED verb and it never prompts, so `fired.prompt`
		# stays empty and nothing has to pause here.


static func _is_live_face_up(state: MatchState, piles: MatchState.SeatPiles, card: int) -> bool:
	return piles.is_revealed(card) and not state.is_destroyed(card)


## Whether `card` carries an ON_MOVED effect.
static func _fires_on_moved(card: int, cards: MatchCards) -> bool:
	var effect: CardEffect = EffectResolver.effect_of(card, cards)
	return effect != null and effect.trigger == CardEffect.Trigger.ON_MOVED


## CARD_MOVED for `card` on `seat`'s row: public when it is revealed, else private to `seat`.
static func _moved_event(
	piles: MatchState.SeatPiles, seat: int, card: int, from_slot: int, to_slot: int
) -> MatchEvent:
	var owner: int = MatchEvent.PUBLIC if piles.is_revealed(card) else seat
	var payload: Dictionary = {
		"seat": seat, "card": card, "from_slot": from_slot, "to_slot": to_slot
	}
	return MatchEvent.new(MatchEvent.Kind.CARD_MOVED, payload, owner)


## The card right of `card` on `seat`'s row, or -1 when it is the rightmost or not there.
static func _right_of(state: MatchState, seat: int, card: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var slot: int = piles.board.find(card)
	if slot < 0 or slot + 1 >= piles.board.size():
		return -1
	return piles.board[slot + 1]


## SHIFT_OWN_LEFT for `card` on `seat`'s row (see the class comment).
static func _shift_left(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	card: int,
	outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var slot: int = piles.board.find(card)
	if slot < 0:
		return
	var order: Array[int] = []
	order.assign(piles.board)
	order.remove_at(slot)
	if order.size() < 2:
		return  # One other card or none: the rotation moves nothing.
	var leftmost: int = order[0]
	order.remove_at(0)
	order.append(leftmost)
	if order.insert(slot, card) != OK:
		return  # `slot` was the source's own slot, so it is in range.
	rewrite_row(state, cards, rng, policy, seat, order, outcome)


## REVERSE_OPPONENT_ROW: `seat` is the row reversed (the opponent of the source).
static func _reverse(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var order: Array[int] = []
	order.assign(piles.board)
	order.reverse()
	rewrite_row(state, cards, rng, policy, seat, order, outcome)


## PLUS_ON_MOVED: `temp_plus += amount` on `card`, STATS_CHANGED (cause temp_plus).
static func _plus(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	card: int,
	amount: int,
	outcome: EffectResolver.Outcome
) -> void:
	state.card_state_for(card).temp_plus += amount
	if not outcome.quiet:
		outcome.events.append(
			EffectResolver.stats_changed(state, cards, seat, card, EffectResolver.CAUSE_TEMP_PLUS)
		)


## COPY_STATS: `source`, of `seat`, takes `target`'s effective flat, ×-part and +-part as
## its base (see the class comment), then its burst check runs.
static func _copy(
	state: MatchState,
	cards: MatchCards,
	rng: MatchRng,
	policy: PreviewPolicy,
	seat: int,
	source: int,
	target: int,
	outcome: EffectResolver.Outcome
) -> void:
	var stats: ScoreWalk.Effective = ScoreWalk.effective(target, state, cards)
	var held: CardState = state.card_state_for(source)
	held.has_base = true
	held.base_flat = stats.flat
	held.base_times = stats.times
	held.base_plus = stats.plus
	if not outcome.quiet:
		outcome.events.append(EffectResolver.stats_changed(state, cards, seat, source, CAUSE_COPY))
	if RuinEffects.check_burst(state, cards, rng, policy, source, outcome):
		pass  # A copy to BURST_FLAT or more burst the source; its destroys are on `outcome`.
