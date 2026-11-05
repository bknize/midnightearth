class_name ScoreWalk
extends RefCounted
## The pure, resumable score walk over a MatchState (R11-R18, plan P3-P5). All of its
## progress lives in `state.walk`, so a walk can stop on a prompt and resume from the same
## state, and a preview can run it on a copy (MatchState.duplicate()).
##
## A walk: begin() resets both scores to 0 and both multipliers to ×1.00 (R11; DC-07 R10,
## MatchRules.MULT_ONE in hundredths), then each
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
## The score (DC-07 P4, R10-R12): the mult is an integer in hundredths. With `flat`, `times`
## (hundredths) and `plus` (whole units) from effective(): `mult = (mult * times + 50) /
## 100` (times_hundredths: rounded to the nearest hundredth), then `mult += plus * 100`,
## then `added = flat * mult / 100` (floor) and `scores[seat] += added` (CARD_SCORED).
## Integer only, so every platform agrees. When the walk ends, every card's `temp_plus` is
## cleared (DC-07 P5).
##
## Effect hooks (P6, R13, R15, R18, R19; DC-05 T04), fired through EffectResolver:
## - at a reveal, right after CARD_REVEALED: the revealing seat's no-bonus mark is spent on
##   the card (R22, DC-07 R14, STATS_CHANGED), then the card's ON_REVEAL effect fires, then every
##   already-revealed card of the other seat with an ON_OPPONENT_REVEAL effect fires, in
##   row order as snapshotted when the first of them is due (Pulse.watchers), then every
##   other revealed, live card of the revealing seat with an ON_ALLY_REVEAL effect fires
##   (cycle 8 R15, P5), in row order as snapshotted when the first of them is due, skipped
##   outright in a match where no definition has that trigger (MatchCards.has_trigger); all
##   of it before the card scores (R13);
## - after CARD_SCORED, every revealed, live card of the other seat with an
##   ON_OPPONENT_SCORE effect fires (DC-07 P10, R26: the burst), in row order as snapshotted
##   right after the score (Pulse.watchers' rule; each entry still on its row, face up and
##   live when its turn comes); then, while the card is still face up and live, its ON_SCORE
##   effect fires (R15), each time it scores (C4). The burst opens no prompt, so its
##   snapshot never pauses; should a later on-opponent-score verb prompt, the pulse pauses
##   at DONE and the rest of the snapshot and the on-score effect are skipped;
## - ONGOING effects never fire in a pulse: effective() reads them (the Drift neighbour and
##   edge ×-parts, DC-07 T07) and turn end settles the energy carry
##   (EffectResolver.settle_energy, called by MatchEngine);
## - ON_MOVED effects fire inside the move that caused them (DriftEffects.rewrite_row), so
##   within the firing of whatever effect moved the card.
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
## WATCHERS (the other seat's on-opponent-reveal effects), then ALLY_WATCHERS (its own
## seat's on-ally-reveal effects, cycle 8 P5), then back to SCORE, which reads
## the slot again (the score and the on-score effect of its card, or the reveal of a card
## an effect put there). A prompt stops the pulse after the firing that opened it and
## records the card, the slot and the next stage in `walk.paused_*` (for WATCHERS and
## ALLY_WATCHERS with that stage's snapshot and next index); the next step() resumes there
## (step()).

## Where a pulse resumes after a prompt (WalkState.paused_stage). DONE: nothing is left.
enum Stage { REVEAL_EFFECT, WATCHERS, ALLY_WATCHERS, SCORE, DONE }

## Added before the division by 100 so a hundredths product rounds to the nearest (P4).
const HALF_HUNDREDTH: int = 50


## Starts a walk on `state` (R11): both scores 0, both multipliers ×1.00, both cursors at slot
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
	walk.mult[0] = MatchRules.MULT_ONE
	walk.mult[1] = MatchRules.MULT_ONE
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


## `card`'s shown stats (DC-07 P5, R13, R14): the base (the definition's, or the CardState's
## `base_*` once a copy stored one), plus the card's match memory (cycle 8 R3, P3:
## CardMemory `flat`, `times` added to the ×-part in hundredths, `plus`), then the
## positional ×-parts (DC-07 T07, R28: ×amount
## for each adjacent revealed, live card carrying the ongoing NEIGHBOUR_TIMES, Lodestone;
## ×amount when the card itself carries the ongoing EDGE_LEFT_TIMES, Herald, and holds slot
## 0 of its row), each step times_hundredths(); then `flat_delta` adds to the flat and
## `temp_plus` to the +-part, then `no_bonus` makes the ×-part 100 and the +-part 0. Flat 0,
## ×1.00 and +0 for a card with no definition. Every reader (the walk, previews, SeatView,
## STATS_CHANGED, the destroy's preview rule) goes through this one function, so it stays
## cheap: the positional parts look at the card's two neighbours and its own slot only, and
## are skipped outright in a match where no definition carries either positional verb
## (MatchCards.has_verb), since every lookup would then leave the ×-part as it is.
## A copied base (R34, C22) holds the target's whole shown bonus, a ×-part and a +-part at
## once when it showed both; the copier's own positional parts, `flat_delta`, `temp_plus`
## and `no_bonus` apply on top of it as on a printed base (P5).
static func effective(card: int, state: MatchState, cards: MatchCards) -> Effective:
	var out: Effective = Effective.new()
	var def: CardDef = _definition(card, cards)
	if def == null:
		return out
	var held: CardState = state.card_state(card)
	if held != null and held.has_base:
		out.flat = held.base_flat
		out.times = held.base_times
		out.plus = held.base_plus
	else:
		out.flat = def.flat
		if def.bonus_kind == CardDef.BonusKind.TIMES:
			out.times = def.bonus
		elif def.bonus_kind == CardDef.BonusKind.PLUS:
			out.plus = def.bonus
	var kept: CardMemory = state.memory_of(card)
	if kept != null:
		out.flat += kept.flat
		out.times += kept.times
		out.plus += kept.plus
	if _has_positional(cards):
		out.times = _positional_times(card, state, cards, def, out.times)
	if held != null:
		out.flat += held.flat_delta
		out.plus += held.temp_plus
		if held.no_bonus:
			out.times = MatchRules.MULT_ONE
			out.plus = 0
	return out


## `card`'s effective cost (cycle 8 R4, P3): its printed cost less its memory's cost
## reduction, never below MatchRules.MIN_COST; -1 when the card has no definition (an
## unpriced card, as LegalPlays.cost_of reports it). Every budget check reads this.
static func effective_cost(card: int, state: MatchState, cards: MatchCards) -> int:
	var def: CardDef = _definition(card, cards)
	if def == null:
		return -1
	var kept: CardMemory = state.memory_of(card) if state != null else null
	if kept == null:
		return def.cost
	return maxi(def.cost - kept.cost, MatchRules.MIN_COST)


## The effective costs of `hand`, in its order (effective_cost each; P3).
static func effective_costs(hand: Array[int], state: MatchState, cards: MatchCards) -> Array[int]:
	var out: Array[int] = []
	for card: int in hand:
		out.append(effective_cost(card, state, cards))
	return out


## The uses `card`'s limited ability has left, as a view shows them (cycle 8 R6, P7): -1
## when its effect is unlimited (or it has none), the effect's `uses` until the memory has
## read them, then the memory's `uses_left`.
static func uses_left(card: int, state: MatchState, cards: MatchCards) -> int:
	var def: CardDef = _definition(card, cards)
	if def == null or def.effect == null or def.effect.uses <= 0:
		return -1
	var kept: CardMemory = state.memory_of(card)
	if kept == null or kept.uses_left < 0:
		return def.effect.uses
	return kept.uses_left


## Whether `card` carries a memory that is not empty (cycle 8 R7: the grown mark).
static func is_grown(card: int, state: MatchState) -> bool:
	var kept: CardMemory = state.memory_of(card)
	return kept != null and not kept.is_empty()


## Whether some definition of the match carries a positional ×-part (the ongoing
## NEIGHBOUR_TIMES or EDGE_LEFT_TIMES), so effective() has positions to look at.
static func _has_positional(cards: MatchCards) -> bool:
	return (
		cards.has_verb(CardEffect.Verb.NEIGHBOUR_TIMES)
		or cards.has_verb(CardEffect.Verb.EDGE_LEFT_TIMES)
	)


## `times` with `card`'s positional ×-parts (see effective()), `def` being its definition.
## Unchanged for a card on neither row. The left neighbour's part applies before the right
## one's, then the edge part.
static func _positional_times(
	card: int, state: MatchState, cards: MatchCards, def: CardDef, times: int
) -> int:
	var piles: MatchState.SeatPiles = state.seats[0]
	var slot: int = piles.board.find(card)
	if slot < 0:
		piles = state.seats[1]
		slot = piles.board.find(card)
	if slot < 0:
		return times
	var out: int = times
	if slot > 0:
		var left: int = _neighbour_times(piles.board[slot - 1], piles, state, cards)
		if left != MatchRules.MULT_ONE:
			out = times_hundredths(out, left)
	if slot + 1 < piles.board.size():
		var right: int = _neighbour_times(piles.board[slot + 1], piles, state, cards)
		if right != MatchRules.MULT_ONE:
			out = times_hundredths(out, right)
	if slot == 0:
		var edge: int = _ongoing_amount(def.effect, CardEffect.Verb.EDGE_LEFT_TIMES)
		if edge > 0:
			out = times_hundredths(out, edge)
	return out


## The ×-part `neighbour` (on the row `piles`) lends each adjacent card: its NEIGHBOUR_TIMES
## amount while it is revealed and live, else ×1.00.
static func _neighbour_times(
	neighbour: int, piles: MatchState.SeatPiles, state: MatchState, cards: MatchCards
) -> int:
	if not piles.is_revealed(neighbour) or state.is_destroyed(neighbour):
		return MatchRules.MULT_ONE
	var effect: CardEffect = EffectResolver.effect_of(neighbour, cards)
	var amount: int = _ongoing_amount(effect, CardEffect.Verb.NEIGHBOUR_TIMES)
	return amount if amount > 0 else MatchRules.MULT_ONE


## `effect`'s amount when it is the ongoing `verb`, else 0.
static func _ongoing_amount(effect: CardEffect, verb: int) -> int:
	if effect == null or effect.trigger != CardEffect.Trigger.ONGOING or effect.verb != verb:
		return 0
	return effect.amount


## `a * b` for two hundredths values, rounded to the nearest hundredth (DC-07 P4): the
## mult times a ×-part, and one ×-part times another.
static func times_hundredths(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return (a * b + HALF_HUNDREDTH) / MatchRules.MULT_ONE


## The definition of `card` (an instance id, read through its origin's deck), or null.
static func _definition(card: int, cards: MatchCards) -> CardDef:
	if cards == null:
		return null
	return cards.def_of(card)


## One pulse (P3). Returns true when the walk paused on a prompt. When no card is left the
## walk ends (`walk.active` becomes false) and nothing else changes. `rng` is the engine
## stream, for the random destroy (P11); `rng` and `policy` go to EffectResolver (see its
## preview seam).
##
## Prompts (DC-05 T05): an effect that needs a choice between two or more targets returns
## its prompt from EffectResolver.apply(); step() stores it in `state.prompt`, records
## where the pulse stopped (`walk.paused_*`, with the watcher snapshot and index for the
## WATCHERS and ALLY_WATCHERS stages) and returns true. The card's slot is already passed
## and, for an on-reveal prompt, the card is not yet scored. Once the choice has been applied
## (EffectResolver.answer clears the prompt), the next step() finishes that same pulse from
## where it stopped (the paused card's remaining reveal hooks, then the score stage of the
## paused slot, `walk.paused_slot`, whatever card the choice left there) before the cursor
## moves on. A preview never pauses: its policy answers at once.
static func step(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, policy: PreviewPolicy
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
		_clear_temp_plus(state, cards, sink, policy)
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
	state: MatchState, cards: MatchCards, sink: Callable, live: bool, seat: int, card: int
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
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, policy: PreviewPolicy
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


## The score of `card` on `seat`'s row (DC-07 P4, R11): the multiplier is multiplied by
## the card's ×-part (rounded to the nearest hundredth), then gains its +-part in whole
## units, then the seat's score gains the flat times the multiplier, floored. CARD_SCORED
## on a live walk, its `slot` looked up by id (the pulsed slot, which the card holds) and
## `again` true when the card already scored in this walk (DC-06 R9, P3).
static func _score(
	state: MatchState, cards: MatchCards, sink: Callable, live: bool, seat: int, card: int
) -> void:
	var walk: MatchState.WalkState = state.walk
	var piles: MatchState.SeatPiles = state.seats[seat]
	var stats: Effective = effective(card, state, cards)
	var mult: int = times_hundredths(walk.mult[seat], stats.times)
	mult += stats.plus * MatchRules.MULT_ONE
	walk.mult[seat] = mult
	@warning_ignore("integer_division")
	var added: int = stats.flat * mult / MatchRules.MULT_ONE
	state.scores[seat] += added
	var again: bool = walk.scored.has(card)
	walk.scored[card] = true
	if live:
		var scored: Dictionary = {
			"seat": seat,
			"card": card,
			"slot": piles.board.find(card),
			"flat": stats.flat,
			"times": stats.times,
			"plus": stats.plus,
			"mult": mult,
			"added": added,
			"score": state.scores[seat],
			"again": again,
		}
		sink.call(MatchEvent.Kind.CARD_SCORED, scored)


## The walk's end (DC-07 P5): every card's `temp_plus` goes back to 0. On a live walk a
## revealed card still on a row gets STATS_CHANGED (cause temp_plus) for it, public, in
## ascending card id. A preview (or a walk with no sink) emits nothing, and zeroing one
## entry reads no other, so the order cannot matter: it clears the entries in place,
## unsorted.
static func _clear_temp_plus(
	state: MatchState, cards: MatchCards, sink: Callable, policy: PreviewPolicy
) -> void:
	var live: bool = policy == null and sink.is_valid()
	if not live:
		for card: int in state.card_states:
			var quiet: CardState = state.card_states[card]
			quiet.temp_plus = 0
		return
	var ids: Array[int] = []
	ids.assign(state.card_states.keys())
	ids.sort()
	for card: int in ids:
		var held: CardState = state.card_states[card]
		if held.temp_plus == 0:
			continue
		held.temp_plus = 0
		var seat: int = _row_seat(state, card)
		if seat < 0:
			continue
		var piles: MatchState.SeatPiles = state.seats[seat]
		if piles.is_revealed(card):
			var changed: MatchEvent = EffectResolver.stats_changed(
				state, cards, seat, card, EffectResolver.CAUSE_TEMP_PLUS
			)
			sink.call(changed.kind, changed.payload, changed.owner_seat)


## CARD_REVEALED for `card`, which has just been revealed on `seat`'s row. `order` counts
## the reveals of this walk from 0 (the board still reads it until DC-05 T08 and T11);
## `destroyed` is true when the card was destroyed before the cursor reached it (DC-06 R14).
## `cost` is its effective cost and `grown` whether its memory is not empty (cycle 8 R7,
## R25): public, as the card now is.
static func _emit_reveal(
	state: MatchState, cards: MatchCards, sink: Callable, seat: int, card: int, destroyed: bool
) -> void:
	var def: CardDef = null
	if cards != null:
		def = cards.def_of(card)
	var def_id: String = ""
	if def != null:
		def_id = def.id
	var stats: Effective = effective(card, state, cards)
	var piles: MatchState.SeatPiles = state.seats[seat]
	var revealed: Dictionary = {
		"seat": seat,
		"card": card,
		"def_id": def_id,
		"slot": piles.board.find(card),
		"flat": stats.flat,
		"times": stats.times,
		"plus": stats.plus,
		"order": state.walk.reveals,
		"destroyed": destroyed,
		"cost": maxi(effective_cost(card, state, cards), 0),
		"grown": is_grown(card, state),
	}
	sink.call(MatchEvent.Kind.CARD_REVEALED, revealed)


## The seat whose row holds `card`, or -1 when neither row does.
static func _row_seat(state: MatchState, card: int) -> int:
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		if piles.board.has(card):
			return seat
	return -1


## A card's effective stats (DC-07 P5): `flat`, `times` (the ×-part in hundredths, 100 for
## none) and `plus` (the +-part in whole units). ScoreWalk.effective() builds them.
class Effective:
	extends RefCounted

	var flat: int = 0
	var times: int = MatchRules.MULT_ONE
	var plus: int = 0

	## The stats as plain data: {flat, times, plus}.
	func to_dict() -> Dictionary:
		return {"flat": flat, "times": times, "plus": plus}


## One pulse in progress (DC-05 T05): the walk's context, and the stages of the pulse of one
## slot from a given point (ScoreWalk.Stage). Pausing on a prompt stores the prompt in
## `state.prompt` and the resume point in `state.walk`.
class Pulse:
	extends RefCounted

	var state: MatchState = null
	var cards: MatchCards = null
	var rng: MatchRng = null
	var sink: Callable = Callable()
	var policy: PreviewPolicy = null
	## The watcher snapshot of the card revealing now (DC-05 T13): the other row's revealed
	## cards with an ON_OPPONENT_REVEAL effect, in row order, taken when the WATCHERS stage
	## first runs for the card; then, emptied as that stage ends, the own row's other revealed
	## cards with an ON_ALLY_REVEAL effect, taken when the ALLY_WATCHERS stage first runs
	## (cycle 8 P5). Empty until then, and emptied when another card reveals in the same
	## pulse; a resumed pulse gets it back from `walk.paused_watchers`.
	var watchers: Array[int] = []
	## The snapshot index the WATCHERS or ALLY_WATCHERS stage goes on from.
	var watcher_at: int = 0

	func _init(
		p_state: MatchState,
		p_cards: MatchCards,
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
	## reveal stages run (REVEAL_EFFECT, WATCHERS, ALLY_WATCHERS; -1 for a pulse starting at
	## SCORE). A resumed WATCHERS or ALLY_WATCHERS stage goes on from `watchers` and
	## `watcher_at` (set by ScoreWalk.step). The SCORE stage reads the slot (DC-06 P2,
	## C23-C25): a live face-down card there is revealed and its own reveal stages run, then
	## the slot is read again; otherwise the card there scores, or only flips when destroyed.
	## Each pass through SCORE that does not score reveals one more card, so the loop ends.
	## True on a prompt.
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
			elif at == ScoreWalk.Stage.WATCHERS or at == ScoreWalk.Stage.ALLY_WATCHERS:
				if _watcher_stages(seat, slot, revealer, at):
					return true
				at = ScoreWalk.Stage.SCORE
			else:
				var occupant: int = _occupant(seat, slot)
				if not _needs_reveal(seat, occupant):
					return _score_slot(seat, slot, occupant)
				if occupant == revealer:
					# Un-revealed during its own reveal stages (DC-07 P9): it stays face down
					# until a later pulse reaches it (R30), and the loop still ends.
					return false
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
	## scores, then the other seat's on-opponent-score cards fire (DC-07 P10), then, while
	## the card is still face up (a burst may have destroyed or un-revealed it), its on-score
	## effect (R15). True when an effect opened a prompt.
	func _score_slot(seat: int, slot: int, card: int) -> bool:
		if card < 0:
			return false
		var live: bool = policy == null and sink.is_valid()
		if state.is_destroyed(card):
			ScoreWalk._pulse_destroyed(state, cards, sink, live, seat, card)
			return false
		ScoreWalk._score(state, cards, sink, live, seat, card)
		if _opponent_score(seat):
			_pause(card, slot, ScoreWalk.Stage.DONE)
			return true
		var piles: MatchState.SeatPiles = state.seats[seat]
		if not piles.is_revealed(card):
			return false
		if _fire(seat, card, CardEffect.Trigger.ON_SCORE):
			_pause(card, slot, ScoreWalk.Stage.DONE)
			return true
		return false

	## The other seat's revealed, live cards with an ON_OPPONENT_SCORE effect fire after a
	## card of `seat` scored (DC-07 P10, R26), in row order as snapshotted now; an entry no
	## longer on that row, face up and live by its turn is skipped (_fire skips a destroyed
	## one). True when one opened a prompt (none does: see the class comment).
	## The snapshot is skipped outright in a match where no definition has that trigger
	## (MatchCards.has_trigger): it could hold no card, so nothing would fire.
	func _opponent_score(seat: int) -> bool:
		if cards == null or not cards.has_trigger(CardEffect.Trigger.ON_OPPONENT_SCORE):
			return false
		var other: int = 1 - seat
		var piles: MatchState.SeatPiles = state.seats[other]
		for watcher: int in _watcher_snapshot(other, CardEffect.Trigger.ON_OPPONENT_SCORE):
			if not piles.board.has(watcher) or not piles.is_revealed(watcher):
				continue
			if _fire(other, watcher, CardEffect.Trigger.ON_OPPONENT_SCORE):
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
			watchers = _watcher_snapshot(other, CardEffect.Trigger.ON_OPPONENT_REVEAL)
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

	## The watcher stages of `card`, just revealed on `seat`'s row, from `stage`: WATCHERS
	## (_watchers), then ALLY_WATCHERS (_ally_watchers) with a snapshot of its own (P5). True
	## on a prompt.
	func _watcher_stages(seat: int, slot: int, card: int, stage: int) -> bool:
		if stage == ScoreWalk.Stage.WATCHERS:
			if _watchers(seat, slot, card):
				return true
			watchers.clear()
			watcher_at = 0
		return _ally_watchers(seat, slot, card)

	## `seat`'s other revealed, live cards with an ON_ALLY_REVEAL effect fire for `card`, just
	## revealed on `seat`'s row (cycle 8 R15, P5), exactly as _watchers() fires the other
	## seat's: a snapshot in row order taken the first time this stage runs for the card
	## (`card` itself left out), an entry no longer revealed on the row by its turn skipped,
	## a prompt pausing with the snapshot and the next index in `state.walk`. Skipped outright
	## in a match where no definition has the trigger (MatchCards.has_trigger). True on a
	## prompt.
	func _ally_watchers(seat: int, slot: int, card: int) -> bool:
		if cards == null or not cards.has_trigger(CardEffect.Trigger.ON_ALLY_REVEAL):
			return false
		var piles: MatchState.SeatPiles = state.seats[seat]
		if watchers.is_empty():
			watchers = _watcher_snapshot(seat, CardEffect.Trigger.ON_ALLY_REVEAL)
			watchers.erase(card)
			watcher_at = 0
		while watcher_at < watchers.size():
			var watcher: int = watchers[watcher_at]
			watcher_at += 1
			if not piles.board.has(watcher) or not piles.is_revealed(watcher):
				continue
			if _fire(seat, watcher, CardEffect.Trigger.ON_ALLY_REVEAL):
				_pause(card, slot, ScoreWalk.Stage.ALLY_WATCHERS)
				return true
		return false

	## `seat`'s revealed, live (not destroyed) cards with a `trigger` effect
	## (ON_OPPONENT_REVEAL, ON_OPPONENT_SCORE or ON_ALLY_REVEAL), in row order.
	func _watcher_snapshot(seat: int, trigger: int) -> Array[int]:
		var out: Array[int] = []
		var piles: MatchState.SeatPiles = state.seats[seat]
		for watcher: int in piles.board:
			if not piles.is_revealed(watcher) or state.is_destroyed(watcher):
				continue
			var effect: CardEffect = EffectResolver.effect_of(watcher, cards)
			if effect != null and effect.trigger == trigger:
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
	## `stage`, and for WATCHERS and ALLY_WATCHERS the snapshot and next index (an empty
	## snapshot when no watcher has run yet).
	func _pause(card: int, slot: int, stage: int) -> void:
		var walk: MatchState.WalkState = state.walk
		walk.paused_card = card
		walk.paused_slot = slot
		walk.paused_stage = stage
		walk.paused_watchers.assign(watchers)
		walk.paused_watcher_at = watcher_at
