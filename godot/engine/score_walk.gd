class_name ScoreWalk
extends RefCounted
## The pure, resumable score walk over a MatchState (R11-R18, plan P3-P5). All of its
## progress lives in `state.walk`, so a walk can stop on a prompt and resume from the same
## state, and a preview can run it on a copy (MatchState.duplicate()).
##
## A walk: begin() resets both scores to 0 and both multipliers to 1 (R11), then each
## step() pulses one slot until no slot is left. The cursor (DC-06 R1-R4, P1): one slot
## index per row, `walk.cursor[seat]`, the number of that row's slots already passed, 0 for
## both rows at begin(). The next pulse is the slot at the cursor of `walk.next_seat`'s row
## when that row has one left, else the other row's, else the walk ends (next_slot()).
## A pulse at (seat, slot) first sets `cursor[seat] = slot + 1`, then flips `next_seat`,
## then runs on that slot: the slot counts as passed before any effect fired by the pulse
## resolves (R2). A walk therefore pulses each slot of both rows once (R4).
##
## Reveal, then score (DC-06 R5, R11, C23-C25, P2): a pulse's reveal stage belongs to the
## card on the slot when the pulse starts, its score stage to the slot. Once the reveal
## stage's effects resolve, the card holding the slot now is scored, whichever card that
## is: an unrevealed card first gets a full reveal of its own (CARD_REVEALED, the bonus-0
## spend, its on-reveal effect, the opponent's watchers; any may prompt), then scores; a
## revealed card scores, with `again` true when it already scored in this walk (R9,
## `walk.scored`, P3); a destroyed card flips if face down and scores nothing (R13, R14).
## A card an effect moved off the slot does not score in this pulse: the cursor reaches it
## later when its new slot is unpassed (R6), and not in this walk when it is passed (R7);
## face down there, it stays face down until a later walk (R8).
##
## The score (P4, R14): `mult[seat] += bonus`, `added = flat * mult[seat]`,
## `scores[seat] += added` (CARD_SCORED), with flat and bonus from effective().
##
## Effect hooks (P6, R13, R15, R18, R19; DC-05 T04), fired through EffectResolver:
## - at a reveal, right after CARD_REVEALED: the revealing seat's bonus-0 mark is spent on
##   the card (R22, STATS_CHANGED), then the card's ON_REVEAL effect fires, then every
##   already-revealed card of the other seat with an ON_OPPONENT_REVEAL effect fires, in
##   row order as snapshotted when the first of them is due (Pulse.watchers); all of it
##   before the card scores (R13);
## - after CARD_SCORED, the card's ON_SCORE effect fires (R15), each time it scores (C4);
## - ONGOING effects never fire in a pulse: effective() reads them (no deck card changes
##   stats that way, the hook is kept) and turn end settles the energy carry
##   (EffectResolver.settle_energy, called by MatchEngine).
## Destroyed cards (DC-06 R12-R15, P4): a destroy marks the card (CardState.destroyed) and
## leaves it in its slot, so the cursor still pulses that slot. The pulse of a destroyed
## card only reveals it when it is face down (CARD_REVEALED with `destroyed` true; every
## CARD_REVEALED carries the flag) and otherwise does nothing: no bonus-0 spend, no
## effect, no watcher, no score. A destroyed card never fires (Pulse._fire), never
## watches, and a card destroyed before its score in its own pulse is not scored.
##
## Events go to `sink` as sink.call(kind, payload) for the walk's own public events and
## sink.call(kind, payload, owner) for an effect's events, which may be private (draws,
## burns, the destroy of a face-down card). A null `policy` is a live walk; a preview
## passes a PreviewPolicy and gets no events (the effects still change its state).
##
## Prompts and resuming (DC-05 T05): a pulse runs in Stages. It starts at SCORE, which
## reads the slot: a card revealed there goes to REVEAL_EFFECT (its on-reveal effect), then
## WATCHERS (the other seat's on-opponent-reveal effects), then back to SCORE, which reads
## the slot again (the score and the on-score effect of its card, or the reveal of a card
## an effect put there). A prompt stops the pulse after the firing that opened it and
## records the card, the slot and the next stage in `walk.paused_*`; the next step()
## resumes there (step()).

## Where a pulse resumes after a prompt (WalkState.paused_stage). DONE: nothing is left.
enum Stage { REVEAL_EFFECT, WATCHERS, SCORE, DONE }


## Starts a walk on `state` (R11): both scores 0, both multipliers 1, both cursors at slot
## 0, nothing scored, the turn's first committer pulses first.
static func begin(state: MatchState) -> void:
	state.scores[0] = 0
	state.scores[1] = 0
	var walk: MatchState.WalkState = state.walk
	walk.active = true
	walk.next_seat = state.first_seat
	walk.cursor[0] = 0
	walk.cursor[1] = 0
	walk.scored.clear()
	walk.mult[0] = 1
	walk.mult[1] = 1
	walk.reveals = 0


## The next slot to pulse as (seat, slot) (DC-06 P1, R3), or (-1, -1) when the walk is over
## or neither row has a slot the cursor has not passed: `next_seat`'s row when its cursor
## is short of the row's size, else the other row's.
static func next_slot(state: MatchState) -> Vector2i:
	var walk: MatchState.WalkState = state.walk
	if not walk.active:
		return Vector2i(-1, -1)
	var seat: int = walk.next_seat
	for candidate: int in [seat, 1 - seat]:
		var piles: MatchState.SeatPiles = state.seats[candidate]
		if walk.cursor[candidate] < piles.board.size():
			return Vector2i(candidate, walk.cursor[candidate])
	return Vector2i(-1, -1)


## The instance id of the card on next_slot(), or -1 when there is none.
static func next_card(state: MatchState) -> int:
	var at: Vector2i = next_slot(state)
	if at.x < 0:
		return -1
	var piles: MatchState.SeatPiles = state.seats[at.x]
	return piles.board[at.y]


## `card`'s shown stats as (flat, bonus) (P4): its CardState's (_held_stats: the base, the
## definition's until a switch stores one, then `flat_delta` adds to the flat and
## `bonus_zero` zeroes the bonus), then ongoing modifiers from revealed cards (none in this
## deck; R18's hook, which would go here and is never folded by a switch). (0, 0) for a
## card with no definition. Every reader (the walk, previews, SeatView, STATS_CHANGED, the
## destroy's preview rule) goes through this one function.
static func effective(card: int, state: MatchState, cards: CardDb) -> Vector2i:
	return _held_stats(card, state, cards)


## The switch (R20; DC-05 T13, Ben's ruling 1a): `card`'s stats as they stand now, flat-ups
## and the bonus-0 mark included, are exchanged and stored as its new base
## (CardState.apply_switch). Later modifiers apply to the switched stats; a second switch
## exchanges what is current then. Nothing happens for a card with no definition.
static func switch_stats(card: int, state: MatchState, cards: CardDb) -> void:
	if _definition(card, cards) == null:
		return
	var current: Vector2i = _held_stats(card, state, cards)
	state.card_state_for(card).apply_switch(current)


## `card`'s stats from its definition and its CardState alone (see effective()).
static func _held_stats(card: int, state: MatchState, cards: CardDb) -> Vector2i:
	var def: CardDef = _definition(card, cards)
	if def == null:
		return Vector2i.ZERO
	var flat: int = def.flat
	# The integer mult reads the DC-05 bonus until DC-07 T03's hundredths mult.
	var bonus: int = def.legacy_bonus()
	var held: CardState = state.card_state(card)
	if held != null:
		if held.has_base:
			flat = held.base_flat
			bonus = held.base_bonus
		flat += held.flat_delta
		if held.bonus_zero:
			bonus = 0
	return Vector2i(flat, bonus)


## The definition of `card` (an instance id), or null.
static func _definition(card: int, cards: CardDb) -> CardDef:
	if cards == null:
		return null
	return cards.card_at(card % MatchRules.DECK_SIZE)


## One pulse (P3). Returns true when the walk paused on a prompt. When no card is left the
## walk ends (`walk.active` becomes false) and nothing else changes. `rng` is the engine
## stream, for the random destroy (P11); `rng` and `policy` go to EffectResolver (see its
## preview seam).
##
## Prompts (DC-05 T05): an effect that needs a choice between two or more targets returns
## its prompt from EffectResolver.apply(); step() stores it in `state.prompt`, records
## where the pulse stopped (`walk.paused_*`, with the watcher snapshot and index for the
## WATCHERS stage) and returns true. The card's slot is already passed and, for an
## on-reveal prompt, the card is not yet scored. Once the choice has been applied
## (EffectResolver.answer clears the prompt), the next step() finishes that same pulse from
## where it stopped (the paused card's remaining reveal hooks, then the score stage of the
## paused slot, `walk.paused_slot`, whatever card the choice left there) before the cursor
## moves on. A preview never pauses: its policy answers at once.
static func step(
	state: MatchState, cards: CardDb, rng: MatchRng, sink: Callable, policy: PreviewPolicy
) -> bool:
	var walk: MatchState.WalkState = state.walk
	# Still waiting for the choice: nothing moves until EffectResolver.answer() runs.
	if not state.prompt.is_empty():
		return true
	if walk.paused_card >= 0:
		var resumed: int = walk.paused_card
		var slot: int = walk.paused_slot
		var stage: int = walk.paused_stage
		var pulse: Pulse = Pulse.new(state, cards, rng, sink, policy)
		pulse.watchers.assign(walk.paused_watchers)
		pulse.watcher_at = walk.paused_watcher_at
		walk.paused_card = -1
		walk.paused_slot = -1
		walk.paused_stage = Stage.REVEAL_EFFECT
		walk.paused_watchers.clear()
		walk.paused_watcher_at = 0
		# The paused card is on the pulse's row: a swap moves a card only within its row.
		return pulse.run(_row_seat(state, resumed), slot, resumed, stage)
	var at: Vector2i = next_slot(state)
	if at.x < 0:
		walk.active = false
		return false
	var seat: int = at.x
	# The slot is passed before anything the pulse fires resolves (R2).
	walk.cursor[seat] = at.y + 1
	walk.next_seat = 1 - walk.next_seat
	# The score stage reads the slot: it reveals, scores or flips its card (DC-06 P2).
	return Pulse.new(state, cards, rng, sink, policy).run(seat, at.y, -1, Stage.SCORE)


## The pulse of a destroyed `card` on `seat`'s row (DC-06 R13, R14, P4): face down, it is
## revealed (CARD_REVEALED with `destroyed` true) and nothing more, so no bonus-0 spend,
## no on-reveal effect, no watcher and no score; face up, the pulse ends with no event. The
## same holds for a destroyed card an effect put on the pulsed slot (C25).
static func _pulse_destroyed(
	state: MatchState, cards: CardDb, sink: Callable, live: bool, seat: int, card: int
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if piles.is_revealed(card):
		return
	piles.revealed[card] = true
	if live:
		_emit_reveal(state, cards, sink, seat, card, true)
	state.walk.reveals += 1


## Runs the walk from its current point to its end or to a prompt; true on a prompt. The
## preview's loop (plan P12); the live engine loops step() itself so it can stop between
## pulses.
static func run(
	state: MatchState, cards: CardDb, rng: MatchRng, sink: Callable, policy: PreviewPolicy
) -> bool:
	while state.walk.active:
		if step(state, cards, rng, sink, policy):
			return true
	return false


## Sends an effect's events to `sink` with their owners, on a live walk only.
static func _forward(events: Array[MatchEvent], sink: Callable, policy: PreviewPolicy) -> void:
	if policy != null or not sink.is_valid():
		return
	for event: MatchEvent in events:
		sink.call(event.kind, event.payload, event.owner_seat)


## The score of `card` on `seat`'s row (P4, R14): the multiplier gains its bonus, then the
## seat's score gains its flat times the multiplier; CARD_SCORED on a live walk, its `slot`
## looked up by id (the pulsed slot, which the card holds) and `again` true when the card
## already scored in this walk (DC-06 R9, P3).
static func _score(
	state: MatchState, cards: CardDb, sink: Callable, live: bool, seat: int, card: int
) -> void:
	var walk: MatchState.WalkState = state.walk
	var piles: MatchState.SeatPiles = state.seats[seat]
	var stats: Vector2i = effective(card, state, cards)
	walk.mult[seat] += stats.y
	var mult: int = walk.mult[seat]
	var added: int = stats.x * mult
	state.scores[seat] += added
	var again: bool = walk.scored.has(card)
	walk.scored[card] = true
	if live:
		var scored: Dictionary = {
			"seat": seat,
			"card": card,
			"slot": piles.board.find(card),
			"flat": stats.x,
			"bonus": stats.y,
			"mult": mult,
			"added": added,
			"score": state.scores[seat],
			"again": again,
		}
		sink.call(MatchEvent.Kind.CARD_SCORED, scored)


## CARD_REVEALED for `card`, which has just been revealed on `seat`'s row. `order` counts
## the reveals of this walk from 0 (the board still reads it until DC-05 T08 and T11);
## `destroyed` is true when the card was destroyed before the cursor reached it (DC-06 R14).
static func _emit_reveal(
	state: MatchState, cards: CardDb, sink: Callable, seat: int, card: int, destroyed: bool
) -> void:
	var def: CardDef = null
	if cards != null:
		def = cards.card_at(card % MatchRules.DECK_SIZE)
	var def_id: String = ""
	if def != null:
		def_id = def.id
	var stats: Vector2i = effective(card, state, cards)
	var piles: MatchState.SeatPiles = state.seats[seat]
	var revealed: Dictionary = {
		"seat": seat,
		"card": card,
		"def_id": def_id,
		"slot": piles.board.find(card),
		"flat": stats.x,
		"bonus": stats.y,
		"order": state.walk.reveals,
		"destroyed": destroyed,
	}
	sink.call(MatchEvent.Kind.CARD_REVEALED, revealed)


## The seat whose row holds `card`, or -1 when neither row does.
static func _row_seat(state: MatchState, card: int) -> int:
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		if piles.board.has(card):
			return seat
	return -1


## One pulse in progress (DC-05 T05): the walk's context, and the stages of the pulse of one
## slot from a given point (ScoreWalk.Stage). Pausing on a prompt stores the prompt in
## `state.prompt` and the resume point in `state.walk`.
class Pulse:
	extends RefCounted

	var state: MatchState = null
	var cards: CardDb = null
	var rng: MatchRng = null
	var sink: Callable = Callable()
	var policy: PreviewPolicy = null
	## The watcher snapshot of the card revealing now (DC-05 T13): the other row's revealed
	## cards with an ON_OPPONENT_REVEAL effect, in row order, taken when the WATCHERS stage
	## first runs for the card. Empty until then, and emptied when another card reveals in
	## the same pulse; a resumed pulse gets it back from `walk.paused_watchers`.
	var watchers: Array[int] = []
	## The snapshot index the WATCHERS stage goes on from.
	var watcher_at: int = 0

	func _init(
		p_state: MatchState,
		p_cards: CardDb,
		p_rng: MatchRng,
		p_sink: Callable,
		p_policy: PreviewPolicy
	) -> void:
		state = p_state
		cards = p_cards
		rng = p_rng
		sink = p_sink
		policy = p_policy

	## Runs the pulse of `slot` on `seat`'s row from `stage`, `card` being the card whose
	## reveal stages run (REVEAL_EFFECT, WATCHERS; -1 for a pulse starting at SCORE). A
	## resumed WATCHERS stage goes on from `watchers` and `watcher_at` (set by
	## ScoreWalk.step). The SCORE stage reads the slot (DC-06 P2, C23-C25): a live face-down
	## card there is revealed and its own reveal stages run, then the slot is read again;
	## otherwise the card there scores, or only flips when destroyed. Each pass through
	## SCORE that does not score reveals one more card, so the loop ends. True on a prompt.
	func run(seat: int, slot: int, card: int, stage: int) -> bool:
		if seat < 0:
			return false
		var revealer: int = card
		var at: int = stage
		while at != ScoreWalk.Stage.DONE:
			if at == ScoreWalk.Stage.REVEAL_EFFECT:
				if _fire(seat, revealer, CardEffect.Trigger.ON_REVEAL):
					_pause(revealer, slot, ScoreWalk.Stage.WATCHERS)
					return true
				at = ScoreWalk.Stage.WATCHERS
			elif at == ScoreWalk.Stage.WATCHERS:
				if _watchers(seat, slot, revealer):
					return true
				at = ScoreWalk.Stage.SCORE
			else:
				var occupant: int = _occupant(seat, slot)
				if not _needs_reveal(seat, occupant):
					return _score_slot(seat, slot, occupant)
				_reveal(seat, occupant)
				revealer = occupant
				at = ScoreWalk.Stage.REVEAL_EFFECT
		return false

	## The card on `slot` of `seat`'s row, or -1 when the row is shorter.
	func _occupant(seat: int, slot: int) -> int:
		var piles: MatchState.SeatPiles = state.seats[seat]
		if slot < 0 or slot >= piles.board.size():
			return -1
		return piles.board[slot]

	## Whether `card`, on `seat`'s row, is live and still face down, so the score stage
	## reveals it first (DC-06 C24).
	func _needs_reveal(seat: int, card: int) -> bool:
		if card < 0 or state.is_destroyed(card):
			return false
		var piles: MatchState.SeatPiles = state.seats[seat]
		return not piles.is_revealed(card)

	## Reveals `card` on `seat`'s row (R13): CARD_REVEALED on a live walk, then the seat's
	## bonus-0 mark is spent on it (R22), before any of its effects. Its reveal stages start
	## with a fresh watcher snapshot.
	func _reveal(seat: int, card: int) -> void:
		var piles: MatchState.SeatPiles = state.seats[seat]
		piles.revealed[card] = true
		if policy == null and sink.is_valid():
			ScoreWalk._emit_reveal(state, cards, sink, seat, card, false)
		state.walk.reveals += 1
		var spent: Array[MatchEvent] = EffectResolver.spend_bonus_zero(state, cards, seat, card)
		ScoreWalk._forward(spent, sink, policy)
		watchers.clear()
		watcher_at = 0

	## The end of the score stage for `card`, the card on `slot` of `seat`'s row (none when
	## -1): a destroyed card only flips if face down (DC-06 R13, R14, C25); a live card
	## scores, then fires its on-score effect (R15). True when that effect opened a prompt.
	func _score_slot(seat: int, slot: int, card: int) -> bool:
		if card < 0:
			return false
		var live: bool = policy == null and sink.is_valid()
		if state.is_destroyed(card):
			ScoreWalk._pulse_destroyed(state, cards, sink, live, seat, card)
			return false
		ScoreWalk._score(state, cards, sink, live, seat, card)
		if _fire(seat, card, CardEffect.Trigger.ON_SCORE):
			_pause(card, slot, ScoreWalk.Stage.DONE)
			return true
		return false

	## The other seat's revealed cards with an ON_OPPONENT_REVEAL effect fire for `card`,
	## just revealed on `seat`'s row, in row order (P6). The order is a snapshot taken the
	## first time this stage runs for the card (DC-05 T13), so a swap or a move made by one
	## watcher neither skips nor repeats another; a prompt pauses with the snapshot and the
	## next index in `state.walk`. A snapshot entry no longer revealed on that row by its
	## turn is skipped. True on a prompt.
	func _watchers(seat: int, slot: int, card: int) -> bool:
		var other: int = 1 - seat
		var piles: MatchState.SeatPiles = state.seats[other]
		if watchers.is_empty():
			watchers = _watcher_snapshot(other)
			watcher_at = 0
		while watcher_at < watchers.size():
			var watcher: int = watchers[watcher_at]
			watcher_at += 1
			# An earlier firing may have taken it off the row or turned it face down.
			if not piles.board.has(watcher) or not piles.is_revealed(watcher):
				continue
			if _fire(other, watcher, CardEffect.Trigger.ON_OPPONENT_REVEAL):
				_pause(card, slot, ScoreWalk.Stage.WATCHERS)
				return true
		return false

	## `seat`'s revealed, live (not destroyed) cards with an ON_OPPONENT_REVEAL effect, in
	## row order.
	func _watcher_snapshot(seat: int) -> Array[int]:
		var out: Array[int] = []
		var piles: MatchState.SeatPiles = state.seats[seat]
		for watcher: int in piles.board:
			if not piles.is_revealed(watcher) or state.is_destroyed(watcher):
				continue
			var effect: CardEffect = EffectResolver.effect_of(watcher, cards)
			if effect != null and effect.trigger == CardEffect.Trigger.ON_OPPONENT_REVEAL:
				out.append(watcher)
		return out

	## Fires `card`'s effect for `seat` when its trigger is `trigger`. A destroyed card fires
	## nothing, by any trigger (DC-06 R15). True when it opened a prompt, which is then
	## `state.prompt`.
	func _fire(seat: int, card: int, trigger: int) -> bool:
		if state.is_destroyed(card):
			return false
		var effect: CardEffect = EffectResolver.effect_of(card, cards)
		if effect == null or effect.trigger != trigger:
			return false
		var outcome: EffectResolver.Outcome = EffectResolver.apply(
			state, cards, rng, policy, seat, card
		)
		ScoreWalk._forward(outcome.events, sink, policy)
		if not outcome.needs_prompt():
			return false
		state.prompt = outcome.prompt
		return true

	## Records where the pulse of `slot` resumes: `card`, the card whose stage was running,
	## `stage`, and for WATCHERS the snapshot and next index (an empty snapshot when no
	## watcher has run yet).
	func _pause(card: int, slot: int, stage: int) -> void:
		var walk: MatchState.WalkState = state.walk
		walk.paused_card = card
		walk.paused_slot = slot
		walk.paused_stage = stage
		walk.paused_watchers.assign(watchers)
		walk.paused_watcher_at = watcher_at
