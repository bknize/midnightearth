class_name CrewEffects
extends RefCounted
## The eight Crew abilities and the Crew trigger queue (cycle 8 R45-R51, plan P13, P14;
## DC-11 T10). Pure: no nodes, no clock and no randomness (no Crew picks at random, R72).
## A Crew fires only in a match whose Crew pool fires (CrewPool.fires; MatchCards
## .has_crew_trigger), and only for its own seat.
##
## The queue (P13, MatchState.crew_queue): an effect that destroys a card
## (EffectResolver.destroy), moves one (DriftEffects.rewrite_row), returns one to a hand
## (EffectResolver.resolve_returns, a salvaged clear) or un-reveals one (EffectResolver
## .unreveal: a destroy un-revealed instead, the echo flip, Shade, Veil) pushes {trigger,
## seat, card, slot} for the card's controller, when one of that seat's Crew sits on the
## trigger. The queue drains only once the causing effect has resolved (R46): in the walk
## after each firing and before each resumed step (ScoreWalk), at turn start after each
## Crew (TurnStart), at turn end after the returns, the clear and the echo flip, and at round
## end (MatchEngine). Each entry fires the matching Crew of its seat in slot order; a Crew
## with no eligible target, or no use left, does not fire, counts nothing and emits
## nothing (R48). An optional Crew with at least one eligible target opens a Crew prompt
## (R49), even for one target: in the walk it pauses the pulse (resume "walk", the entry
## left at the head of the queue until the answer); at turn end and round end, and under a
## preview policy, it is declined unasked (no Crew there can open one: only a destroy,
## which none of those steps makes, opens a Crew prompt in a walk, and turn start opens
## its own through TurnStart).
##
## A Crew that fires emits CREW_FIRED {seat, slot, crew, verb, trigger, uses_left}
## (public; verb and trigger by their JSON names, uses_left after this firing, -1 when
## unlimited), then its ability's events. A prompting Crew fires when its prompt is
## answered with a choice (apply_choice: CHOICE_MADE, then CREW_FIRED, then the ability),
## counting its use then; a decline (EffectResolver.decline) counts nothing.
##
## The Crew (P14):
## - Quartermaster (turn start, `amount` the turn): draws QUARTERMASTER_DRAWS for its seat,
##   each burned at the hand cap (R12, R25), on that turn of every round.
## - Tallyman (ongoing): ScoreWalk.effective() calls tallied(): a card on its seat's row with
##   an even effective flat (0 included) gets ×`amount` (hundredths) after its board
##   changes, before the no-bonus mark.
## - Shade (turn start, `amount` the turn, optional): a prompt over its seat's revealed live
##   row cards (OWN_BOARD); the chosen card un-reveals in its slot (CARD_UNREVEALED).
## - Salvager (own destroyed, optional, once per round): a prompt over its seat's hand
##   (OWN_HAND, every position; an empty hand does not fire); the chosen hand card is
##   discarded (CARD_DISCARDED, private) and the destroyed card is marked `salvaged`, so the
##   turn-end clear sends it to its controller's hand (salvage()).
## - Veil (own destroyed, optional, once per match): a prompt over the destroyed card alone
##   (OWN_BOARD, its slot); accepting un-destroys it and un-reveals every revealed card of
##   its seat's row (it included; another card already destroyed stays destroyed), in slot
##   order, one CARD_UNREVEALED each. A face-down destroyed card is un-destroyed in place
##   and stays face down: its CARD_UNREVEALED is private to its seat (its id is hidden).
## - Navigator (own moved): the moved card, still live on its seat's row, gets `amount`
##   flat for the round (CardState.flat_delta), STATS_CHANGED cause CAUSE_CREW, private to
##   its seat while it is face down.
## - Gardener (round end): each live card of its seat's row grows `amount` flat for the
##   match (BloomEffects.grow; private for a face-down card).
## - Lookout (own returned or flipped face down): draws `amount` for its seat.
## Salvager and Veil need the destroyed card still destroyed on its row and not already
## salvaged, so a card Salvager took is not offered to Veil after it.

const KEY_TRIGGER: String = "trigger"
const KEY_SEAT: String = "seat"
const KEY_CARD: String = "card"
const KEY_SLOT: String = "slot"
## STATS_CHANGED `cause` of Navigator's flat (plan P14, events table).
const CAUSE_CREW: String = "crew"
## Quartermaster's draws (P14); its `amount` is the turn it fires on.
const QUARTERMASTER_DRAWS: int = 2
## The zone each prompting Crew verb chooses from (by CrewDef.Verb); a Crew prompt answered
## in another zone (a test's stand-in, StubCrew) applies nothing but CHOICE_MADE.
const PROMPT_ZONES: Dictionary[int, int] = {
	CrewDef.Verb.UNREVEAL_OWN_ONE: Choice.Zone.OWN_BOARD,
	CrewDef.Verb.SALVAGE_DESTROYED: Choice.Zone.OWN_HAND,
	CrewDef.Verb.UNREVEAL_ALL_OWN: Choice.Zone.OWN_BOARD,
}


## Queues `trigger` (a CrewDef.Trigger) for `card` of `seat` (see the class comment), only
## when a Crew of `seat` sits on it and fires.
static func push(state: MatchState, cards: MatchCards, trigger: int, seat: int, card: int) -> void:
	if cards == null or seat < 0 or not cards.has_crew_trigger(trigger, seat):
		return
	state.crew_queue.append({KEY_TRIGGER: trigger, KEY_SEAT: seat, KEY_CARD: card, KEY_SLOT: 0})


## TurnStart.fire's shape (TurnStart; P11): fires Crew `slot` of `seat` at turn start when
## it sits on TURN_START and this is its turn. Quartermaster draws (its events, no prompt);
## Shade returns its prompt {zone, options} (TurnStart opens it). Null when it does not fire.
static func turn_start(
	state: MatchState, cards: MatchCards, _rng: MatchRng, seat: int, slot: int
) -> EffectResolver.Outcome:
	var def: CrewDef = cards.crew_def(seat, slot) if cards != null else null
	if def == null or def.trigger != CrewDef.Trigger.TURN_START:
		return null
	if not cards.has_crew_trigger(def.trigger, seat) or state.turn != def.amount:
		return null
	if not has_use(state, seat, slot):
		return null
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	if def.verb == CrewDef.Verb.DRAW_EXTRA and _can_draw(state, seat):
		_fired(state, seat, slot, def, outcome)
		_draws(state, seat, QUARTERMASTER_DRAWS, outcome)
		return outcome
	if def.verb == CrewDef.Verb.UNREVEAL_OWN_ONE:
		var options: Array[int] = _revealed_live(state, seat)
		if options.is_empty():
			return null
		outcome.prompt = {
			Choice.KEY_ZONE: Choice.Zone.OWN_BOARD, Choice.KEY_OPTIONS: MatchState.plain(options)
		}
		return outcome
	return null


## Drains the queue (see the class comment) onto `outcome`, which is quiet under a preview
## policy. True when a Crew prompt opened (state.prompt set, CHOICE_REQUESTED on `outcome`):
## only when `may_prompt` and on a live walk (`policy` null); otherwise an optional Crew
## with targets is declined unasked.
static func drain(
	state: MatchState,
	cards: MatchCards,
	policy: PreviewPolicy,
	may_prompt: bool,
	outcome: EffectResolver.Outcome
) -> bool:
	if cards == null:
		state.crew_queue.clear()
		return false
	while not state.crew_queue.is_empty():
		var entry: Dictionary = state.crew_queue[0]
		var slot: int = entry.get(KEY_SLOT, MatchRules.CREW_SIZE)
		if slot >= MatchRules.CREW_SIZE:
			state.crew_queue.remove_at(0)
			continue
		entry[KEY_SLOT] = slot + 1
		var seat: int = entry.get(KEY_SEAT, -1)
		var trigger: int = entry.get(KEY_TRIGGER, -1)
		var card: int = entry.get(KEY_CARD, -1)
		var def: CrewDef = cards.crew_def(seat, slot)
		if def == null or def.trigger != trigger or not has_use(state, seat, slot):
			continue
		var found: Dictionary = _fire_queued(state, cards, seat, slot, def, card, outcome)
		if found.is_empty() or not may_prompt or policy != null:
			continue
		open_prompt(state, seat, def, found, Choice.RESUME_WALK, outcome.events)
		return true
	return false


## The queue drained where no prompt may open (turn start, turn end, round end): the events.
static func drain_all(state: MatchState, cards: MatchCards) -> Array[MatchEvent]:
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	if not state.crew_queue.is_empty() and drain(state, cards, null, false, outcome):
		pass  # Never: no prompt opens when none may (see drain()).
	return outcome.events


## Round end (R45: after the last turn's end, before the round's winner is decided): each
## ROUND_END Crew fires in first-committer order (the first seat's slots, then the other
## seat's), then the queue drains. The events.
static func round_end(state: MatchState, cards: MatchCards) -> Array[MatchEvent]:
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	if cards == null:
		return outcome.events
	if cards.has_crew_trigger(CrewDef.Trigger.ROUND_END):
		for at: int in range(2 * MatchRules.CREW_SIZE):
			var seat: int = state.first_seat if at < MatchRules.CREW_SIZE else 1 - state.first_seat
			var slot: int = at % MatchRules.CREW_SIZE
			var def: CrewDef = cards.crew_def(seat, slot)
			if def == null or def.trigger != CrewDef.Trigger.ROUND_END:
				continue
			if not cards.has_crew_trigger(def.trigger, seat) or not has_use(state, seat, slot):
				continue
			if def.verb == CrewDef.Verb.GROW_ROW_FLAT:
				_grow_row(state, cards, seat, slot, def, outcome)
	outcome.events.append_array(drain_all(state, cards))
	return outcome.events


## Opens the Crew prompt of `def` (seat `seat`) from `found` ({zone, options}) with
## `resume` (Choice.RESUME_WALK or RESUME_TURN_START): MatchState.prompt {seat, card: -1,
## verb: the CrewDef.Verb, zone, options, multi, optional: the Crew's flag, resume, crew:
## its id}, announced by CHOICE_REQUESTED (EffectResolver.requested, with the Crew's verb
## name and rules text; public) on `out`.
static func open_prompt(
	state: MatchState,
	seat: int,
	def: CrewDef,
	found: Dictionary,
	resume: String,
	out: Array[MatchEvent]
) -> void:
	var prompt: Dictionary = found.duplicate(true)
	prompt[EffectResolver.KEY_SEAT] = seat
	prompt[EffectResolver.KEY_CARD] = -1
	prompt[EffectResolver.KEY_VERB] = def.verb
	prompt[Choice.KEY_MULTI] = Choice.is_multi_prompt(found)
	prompt[Choice.KEY_OPTIONAL] = def.optional
	prompt[Choice.KEY_RESUME] = resume
	prompt[Choice.KEY_CREW] = def.id
	state.prompt = prompt
	var verb: String = CrewDef.VERB_NAMES[def.verb]
	var requested: Dictionary = EffectResolver.requested(prompt, verb, def.text)
	out.append(MatchEvent.new(MatchEvent.Kind.CHOICE_REQUESTED, requested))


## A Crew prompt answered with the card `target` of its zone (EffectResolver.apply_choice,
## after CHOICE_MADE): CREW_FIRED with the use counted, then the ability (see the class
## comment). Nothing when the prompt names no Crew of its seat or was answered in a zone
## the Crew does not choose from. `policy` is non-null on a preview (no events built).
static func apply_choice(
	state: MatchState, cards: MatchCards, prompt: Dictionary, target: int, policy: PreviewPolicy
) -> Array[MatchEvent]:
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	outcome.quiet = policy != null
	var seat: int = prompt.get(EffectResolver.KEY_SEAT, -1)
	var zone: int = prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var slot: int = cards.crew_slot(seat, Choice.crew_of(prompt)) if cards != null else -1
	var def: CrewDef = cards.crew_def(seat, slot) if slot >= 0 else null
	if def == null or not PROMPT_ZONES.has(def.verb) or PROMPT_ZONES[def.verb] != zone:
		return outcome.events
	var destroyed: int = _queued_card(state)
	_fired(state, seat, slot, def, outcome)
	match def.verb:
		CrewDef.Verb.UNREVEAL_OWN_ONE:
			_flip(state, cards, seat, target, outcome)
		CrewDef.Verb.SALVAGE_DESTROYED:
			_discard(state, seat, target, outcome)
			if destroyed >= 0:
				state.card_state_for(destroyed).salvaged = true
		CrewDef.Verb.UNREVEAL_ALL_OWN:
			_veil(state, cards, seat, target, outcome)
	return outcome.events


## A salvaged destroyed `card` leaving `seat`'s row at turn end (EffectResolver
## .clear_destroyed, after its DESTROYED_CLEARED {pile: false, salvaged: true}): it goes to
## its controller's hand and queues OWN_RETURNED, or at the hand cap is burned (CARD_BURNED
## {seat, card} with `owner`, the clear's owner). The events.
static func salvage(
	state: MatchState, cards: MatchCards, seat: int, card: int, owner: int
) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var piles: MatchState.SeatPiles = state.seats[seat]
	if piles.hand.size() >= MatchRules.HAND_CAP:
		piles.burned.append(card)
		out.append(MatchEvent.new(MatchEvent.Kind.CARD_BURNED, {"seat": seat, "card": card}, owner))
		return out
	piles.hand.append(card)
	push(state, cards, CrewDef.Trigger.OWN_RETURNED, seat, card)
	return out


## Tallyman (see the class comment): `times` with ×`amount` when `card` is on the row of a
## seat holding an EVEN_FLAT_TIMES Crew and `flat`, its effective flat, is even; else
## `times`. ScoreWalk.effective() calls it only when some seat's Crew sit on ONGOING.
static func tallied(card: int, state: MatchState, cards: MatchCards, flat: int, times: int) -> int:
	if flat % 2 != 0:
		return times
	var seat: int = -1
	for held: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[held]
		if piles.board.has(card):
			seat = held
			break
	if seat < 0 or not cards.has_crew_trigger(CrewDef.Trigger.ONGOING, seat):
		return times
	for slot: int in range(MatchRules.CREW_SIZE):
		var def: CrewDef = cards.crew_def(seat, slot)
		if def != null and def.verb == CrewDef.Verb.EVEN_FLAT_TIMES:
			return ScoreWalk.times_hundredths(times, def.amount)
	return times


## Whether Crew `slot` of `seat` has a use left (MatchState.crew_uses: -1 unlimited).
static func has_use(state: MatchState, seat: int, slot: int) -> bool:
	return uses_left(state, seat, slot) != 0


## The uses Crew `slot` of `seat` has left, CrewDef.UNLIMITED (-1) when unlimited or unknown.
static func uses_left(state: MatchState, seat: int, slot: int) -> int:
	if seat < 0 or seat >= state.crew_uses.size():
		return CrewDef.UNLIMITED
	var held: Array = state.crew_uses[seat]
	if slot < 0 or slot >= held.size():
		return CrewDef.UNLIMITED
	var left: int = held[slot]
	return left


# --- Firing ---------------------------------------------------------------------------


## Fires `def` (Crew `slot` of `seat`, with a use left) for the queued `card`: a Crew that
## needs no choice applies here (its events on `outcome`) and gives {}; a prompting Crew
## gives its prompt {zone, options} and emits nothing; one with no eligible target gives {}
## and does nothing.
static func _fire_queued(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	slot: int,
	def: CrewDef,
	card: int,
	outcome: EffectResolver.Outcome
) -> Dictionary:
	var none: Dictionary = {}
	match def.verb:
		CrewDef.Verb.MOVED_FLAT:
			_moved_flat(state, cards, seat, slot, def, card, outcome)
		CrewDef.Verb.DRAW_ON_RETURN:
			if _can_draw(state, seat):
				_fired(state, seat, slot, def, outcome)
				_draws(state, seat, def.amount, outcome)
		CrewDef.Verb.SALVAGE_DESTROYED:
			var hand: Array[int] = state.seats[seat].hand
			if _is_destroyed_on_row(state, seat, card) and not hand.is_empty():
				var options: Array = []
				for index: int in range(hand.size()):
					options.append(index)
				return {Choice.KEY_ZONE: Choice.Zone.OWN_HAND, Choice.KEY_OPTIONS: options}
		CrewDef.Verb.UNREVEAL_ALL_OWN:
			if _is_destroyed_on_row(state, seat, card):
				var piles: MatchState.SeatPiles = state.seats[seat]
				var at: Array = [piles.board.find(card)]
				return {Choice.KEY_ZONE: Choice.Zone.OWN_BOARD, Choice.KEY_OPTIONS: at}
	return none


## CREW_FIRED for Crew `slot` of `seat` (`def`), its use counted first (see the class
## comment).
static func _fired(
	state: MatchState, seat: int, slot: int, def: CrewDef, outcome: EffectResolver.Outcome
) -> void:
	var left: int = uses_left(state, seat, slot)
	if left > 0:
		left -= 1
		var held: Array = state.crew_uses[seat]
		held[slot] = left
	var payload: Dictionary = {
		"seat": seat,
		"slot": slot,
		"crew": def.id,
		"verb": CrewDef.VERB_NAMES[def.verb],
		"trigger": CrewDef.TRIGGER_NAMES[def.trigger],
		"uses_left": left,
	}
	outcome.add(MatchEvent.Kind.CREW_FIRED, payload)


## Whether `seat` has a card left to draw (a draw Crew with none does not fire).
static func _can_draw(state: MatchState, seat: int) -> bool:
	var piles: MatchState.SeatPiles = state.seats[seat]
	return not piles.deck.is_empty()


## `count` draws for `seat` (EffectResolver.draw_card: CARD_DRAWN, or CARD_BURNED at the
## hand cap; private to `seat`), none built when `outcome` is quiet.
static func _draws(
	state: MatchState, seat: int, count: int, outcome: EffectResolver.Outcome
) -> void:
	for _i: int in range(count):
		var drawn: MatchEvent = EffectResolver.draw_card(state, seat)
		if drawn != null and not outcome.quiet:
			outcome.events.append(drawn)


## Navigator: the moved `card`, still live on `seat`'s row, gets `def.amount` flat for the
## round; nothing (no firing) otherwise.
static func _moved_flat(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	slot: int,
	def: CrewDef,
	card: int,
	outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if not piles.board.has(card) or state.is_destroyed(card):
		return
	_fired(state, seat, slot, def, outcome)
	state.card_state_for(card).flat_delta += def.amount
	if outcome.quiet:
		return
	var owner: int = MatchEvent.PUBLIC if piles.is_revealed(card) else seat
	outcome.events.append(
		EffectResolver.stats_changed(state, cards, seat, card, CAUSE_CREW, false, owner)
	)


## Gardener: every live card of `seat`'s row grows `def.amount` flat for the match; an
## empty row does not fire.
static func _grow_row(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	slot: int,
	def: CrewDef,
	outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var targets: Array[int] = []
	for card: int in piles.board:
		if not state.is_destroyed(card):
			targets.append(card)
	if targets.is_empty():
		return
	_fired(state, seat, slot, def, outcome)
	BloomEffects.grow(state, cards, seat, targets, BloomEffects.STAT_FLAT, def.amount, outcome)


# --- Prompted abilities ---------------------------------------------------------------


## Shade: `target`, a revealed live card of `seat`'s row, un-reveals in its slot.
static func _flip(
	state: MatchState, cards: MatchCards, seat: int, target: int, outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var slot: int = piles.board.find(target)
	if slot < 0 or not piles.is_revealed(target) or state.is_destroyed(target):
		return
	var payload: Dictionary = {"seat": seat, "card": target, "slot": slot}
	EffectResolver.unreveal(state, cards, seat, target, outcome)
	outcome.add(MatchEvent.Kind.CARD_UNREVEALED, payload)


## Salvager's discard: `card` leaves `seat`'s hand for its burn pile, CARD_DISCARDED
## {seat, card}, private to `seat`.
static func _discard(
	state: MatchState, seat: int, card: int, outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if not piles.hand.has(card):
		return
	piles.hand.erase(card)
	piles.burned.append(card)
	outcome.add(MatchEvent.Kind.CARD_DISCARDED, {"seat": seat, "card": card}, seat)


## Veil (see the class comment): `target`, the destroyed card, is un-destroyed; then every
## revealed card of `seat`'s row that is live (it included) un-reveals, in slot order.
static func _veil(
	state: MatchState, cards: MatchCards, seat: int, target: int, outcome: EffectResolver.Outcome
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var at: int = piles.board.find(target)
	if at < 0:
		return
	state.card_state_for(target).destroyed = false
	if not piles.is_revealed(target):
		var hidden: Dictionary = {"seat": seat, "card": target, "slot": at}
		outcome.add(MatchEvent.Kind.CARD_UNREVEALED, hidden, seat)
	var row: Array[int] = []
	row.assign(piles.board)
	for card: int in row:
		if not piles.is_revealed(card) or state.is_destroyed(card):
			continue
		var payload: Dictionary = {"seat": seat, "card": card, "slot": piles.board.find(card)}
		EffectResolver.unreveal(state, cards, seat, card, outcome)
		outcome.add(MatchEvent.Kind.CARD_UNREVEALED, payload)


# --- Targets --------------------------------------------------------------------------


## The positions of `seat`'s revealed, live row cards, ascending (Shade's options).
static func _revealed_live(state: MatchState, seat: int) -> Array[int]:
	var out: Array[int] = []
	var piles: MatchState.SeatPiles = state.seats[seat]
	for slot: int in range(piles.board.size()):
		var card: int = piles.board[slot]
		if piles.is_revealed(card) and not state.is_destroyed(card):
			out.append(slot)
	return out


## Whether `card` is still destroyed on `seat`'s row and not already salvaged (Salvager's
## and Veil's condition).
static func _is_destroyed_on_row(state: MatchState, seat: int, card: int) -> bool:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if not piles.board.has(card) or not state.is_destroyed(card):
		return false
	return not state.card_state_for(card).salvaged


## The card of the queue's head entry when it is an OWN_DESTROYED one (the destroyed card a
## Salvager prompt opened over), else -1.
static func _queued_card(state: MatchState) -> int:
	if state.crew_queue.is_empty():
		return -1
	var head: Dictionary = state.crew_queue[0]
	var trigger: int = head.get(KEY_TRIGGER, -1)
	if trigger != CrewDef.Trigger.OWN_DESTROYED:
		return -1
	var card: int = head.get(KEY_CARD, -1)
	return card
