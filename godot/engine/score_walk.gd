class_name ScoreWalk
extends RefCounted
## The pure, resumable score walk over a MatchState (R11-R18, plan P3-P5). All of its
## progress lives in `state.walk`, so a walk can stop on a prompt and resume from the same
## state, and a preview can run it on a copy (MatchState.duplicate()).
##
## A walk: begin() resets both scores to 0 and both multipliers to 1 (R11), then each
## step() pulses one card until no card is left. The cursor (P5): the next pulse is the
## leftmost card of `walk.next_seat`'s row that is not in `walk.pulsed`; when that row has
## none, the other row's; when neither has one, the walk ends. Every pulse flips
## `next_seat`. Moved and destroyed cards are handled by the `pulsed` set, never by
## indices, so nothing is pulsed twice or skipped (R16).
##
## A pulse (P4, R13, R14): an unrevealed card is revealed first (CARD_REVEALED); then
## `mult[seat] += bonus`, `added = flat * mult[seat]`, `scores[seat] += added`
## (CARD_SCORED), with flat and bonus from effective().
##
## Effect hooks (P6, R13, R15, R18, R19; DC-05 T04), fired through EffectResolver:
## - at a reveal, right after CARD_REVEALED: the revealing seat's bonus-0 mark is spent on
##   the card (R22, STATS_CHANGED), then the card's ON_REVEAL effect fires, then every
##   already-revealed card of the other seat with an ON_OPPONENT_REVEAL effect fires, in
##   row order; all of it before the card scores (R13);
## - after CARD_SCORED, the card's ON_SCORE effect fires (R15), on every pulse (C3);
## - ONGOING effects never fire in a pulse: effective() reads them (no deck card changes
##   stats that way, the hook is kept) and turn end settles the energy carry
##   (EffectResolver.settle_energy, called by MatchEngine).
## A card an effect takes off the row before its score (a destroy on the opponent's reveal)
## is not scored (R23).
##
## Events go to `sink` as sink.call(kind, payload) for the walk's own public events and
## sink.call(kind, payload, owner) for an effect's events, which may be private (draws,
## burns, the destroy of a face-down card). A null `policy` is a live walk; a preview
## passes a PreviewPolicy and gets no events (the effects still change its state).
##
## Prompts and resuming (DC-05 T05): a pulse runs in Stages. A revealed card starts at
## SCORE; a card revealed by this pulse starts at REVEAL_EFFECT (its on-reveal effect),
## then WATCHERS (the other seat's on-opponent-reveal effects), then SCORE (its score and
## its on-score effect). A prompt stops the pulse after the firing that opened it and
## records the next stage in `walk.paused_*`; the next step() resumes there (step()).

## Where a pulse resumes after a prompt (WalkState.paused_stage). DONE: nothing is left.
enum Stage { REVEAL_EFFECT, WATCHERS, SCORE, DONE }


## Starts a walk on `state` (R11): both scores 0, both multipliers 1, nothing pulsed, the
## turn's first committer pulses first.
static func begin(state: MatchState) -> void:
	state.scores[0] = 0
	state.scores[1] = 0
	var walk: MatchState.WalkState = state.walk
	walk.active = true
	walk.next_seat = state.first_seat
	walk.pulsed.clear()
	walk.mult[0] = 1
	walk.mult[1] = 1
	walk.reveals = 0


## The instance id of the next card to pulse (P5), or -1 when the walk is over or the
## rows hold no unpulsed card.
static func next_card(state: MatchState) -> int:
	if not state.walk.active:
		return -1
	var seat: int = state.walk.next_seat
	var card: int = _leftmost_unpulsed(state, seat)
	if card >= 0:
		return card
	return _leftmost_unpulsed(state, 1 - seat)


## `card`'s shown stats as (flat, bonus) (P4): its definition's, then its CardState
## (`switched` exchanges them, `flat_delta` adds to the flat, `bonus_zero` zeroes the
## bonus), then ongoing modifiers from revealed cards (none in this deck; R18's hook).
## (0, 0) for a card with no definition.
static func effective(card: int, state: MatchState, cards: CardDb) -> Vector2i:
	if cards == null:
		return Vector2i.ZERO
	var def: CardDef = cards.card_at(card % MatchRules.DECK_SIZE)
	if def == null:
		return Vector2i.ZERO
	var flat: int = def.flat
	var bonus: int = def.bonus
	var held: CardState = state.card_state(card)
	if held != null:
		if held.switched:
			var swapped: int = flat
			flat = bonus
			bonus = swapped
		flat += held.flat_delta
		if held.bonus_zero:
			bonus = 0
	return Vector2i(flat, bonus)


## One pulse (P3). Returns true when the walk paused on a prompt. When no card is left the
## walk ends (`walk.active` becomes false) and nothing else changes. `rng` is the engine
## stream, for the random destroy (P11); `rng` and `policy` go to EffectResolver (see its
## preview seam).
##
## Prompts (DC-05 T05): an effect that needs a choice between two or more targets returns
## its prompt from EffectResolver.apply(); step() stores it in `state.prompt`, records
## where the pulse stopped (`walk.paused_*`) and returns true. The card is already in
## `walk.pulsed` and, for an on-reveal prompt, not yet scored. Once the choice has been
## applied (EffectResolver.answer clears the prompt), the next step() finishes that same
## pulse from where it stopped (the remaining reveal hooks, the score, the on-score
## effect) before the cursor moves on. A preview never pauses: its policy answers at once.
static func step(
	state: MatchState, cards: CardDb, rng: MatchRng, sink: Callable, policy: PreviewPolicy
) -> bool:
	var walk: MatchState.WalkState = state.walk
	# Still waiting for the choice: nothing moves until EffectResolver.answer() runs.
	if not state.prompt.is_empty():
		return true
	if walk.paused_card >= 0:
		var resumed: int = walk.paused_card
		var stage: int = walk.paused_stage
		var after: int = walk.paused_watcher
		walk.paused_card = -1
		walk.paused_stage = Stage.REVEAL_EFFECT
		walk.paused_watcher = -1
		var pulse: Pulse = Pulse.new(state, cards, rng, sink, policy)
		return pulse.run(_row_seat(state, resumed), resumed, stage, after)
	var card: int = next_card(state)
	if card < 0:
		walk.active = false
		return false
	var seat: int = _row_seat(state, card)
	walk.pulsed[card] = true
	walk.next_seat = 1 - walk.next_seat
	var live: bool = policy == null and sink.is_valid()
	var piles: MatchState.SeatPiles = state.seats[seat]
	var first_stage: int = Stage.SCORE
	if not piles.is_revealed(card):
		piles.revealed[card] = true
		if live:
			_emit_reveal(state, cards, sink, seat, card)
		walk.reveals += 1
		# The bonus-0 mark is spent on the reveal itself (R22), before any effect.
		_forward(EffectResolver.spend_bonus_zero(state, cards, seat, card), sink, policy)
		first_stage = Stage.REVEAL_EFFECT
	return Pulse.new(state, cards, rng, sink, policy).run(seat, card, first_stage, -1)


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
## seat's score gains its flat times the multiplier; CARD_SCORED on a live walk.
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
		}
		sink.call(MatchEvent.Kind.CARD_SCORED, scored)


## CARD_REVEALED for `card`, which has just been revealed on `seat`'s row. `order` counts
## the reveals of this walk from 0 (the board still reads it until DC-05 T08 and T11).
static func _emit_reveal(
	state: MatchState, cards: CardDb, sink: Callable, seat: int, card: int
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
	}
	sink.call(MatchEvent.Kind.CARD_REVEALED, revealed)


## The leftmost card of `seat`'s row not yet pulsed in this walk, or -1.
static func _leftmost_unpulsed(state: MatchState, seat: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[seat]
	for card: int in piles.board:
		if not state.walk.pulsed.has(card):
			return card
	return -1


## The seat whose row holds `card`, or -1 when neither row does.
static func _row_seat(state: MatchState, card: int) -> int:
	for seat: int in range(state.seats.size()):
		var piles: MatchState.SeatPiles = state.seats[seat]
		if piles.board.has(card):
			return seat
	return -1


## One pulse in progress (DC-05 T05): the walk's context, and the stages of `card`'s pulse
## from a given point (ScoreWalk.Stage). Pausing on a prompt stores the prompt in
## `state.prompt` and the resume point in `state.walk`.
class Pulse:
	extends RefCounted

	var state: MatchState = null
	var cards: CardDb = null
	var rng: MatchRng = null
	var sink: Callable = Callable()
	var policy: PreviewPolicy = null

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

	## Runs `card`'s pulse on `seat`'s row from `stage`. `after` is the watcher whose prompt
	## paused the WATCHERS stage (-1: start with the first watcher). True on a prompt.
	func run(seat: int, card: int, stage: int, after: int) -> bool:
		if seat < 0:
			return false
		var at: int = stage
		if at == ScoreWalk.Stage.REVEAL_EFFECT:
			if _fire(seat, card, CardEffect.Trigger.ON_REVEAL):
				_pause(card, ScoreWalk.Stage.WATCHERS, -1)
				return true
			at = ScoreWalk.Stage.WATCHERS
		if at == ScoreWalk.Stage.WATCHERS:
			if _watchers(seat, card, after):
				return true
			at = ScoreWalk.Stage.SCORE
		# A card an effect took off the row before its score is not scored (R23).
		if at != ScoreWalk.Stage.SCORE or not state.seats[seat].board.has(card):
			return false
		var live: bool = policy == null and sink.is_valid()
		ScoreWalk._score(state, cards, sink, live, seat, card)
		if _fire(seat, card, CardEffect.Trigger.ON_SCORE):
			_pause(card, ScoreWalk.Stage.DONE, -1)
			return true
		return false

	## The other seat's revealed cards with an ON_OPPONENT_REVEAL effect fire for `card`,
	## just revealed on `seat`'s row, in row order (P6), starting after `after` when it is
	## set. A watcher whose prompt paused the pulse is the resume point; if it has left the
	## row by then, no watcher is left to fire. True on a prompt.
	func _watchers(seat: int, card: int, after: int) -> bool:
		var other: int = 1 - seat
		var piles: MatchState.SeatPiles = state.seats[other]
		var watchers: Array[int] = []
		watchers.assign(piles.board)
		var first: int = 0
		if after >= 0:
			first = watchers.find(after) + 1
			if first == 0:
				first = watchers.size()
		for index: int in range(first, watchers.size()):
			var watcher: int = watchers[index]
			# An earlier firing may have taken it off the row; a face-down card does not watch.
			if not piles.board.has(watcher) or not piles.is_revealed(watcher):
				continue
			if _fire(other, watcher, CardEffect.Trigger.ON_OPPONENT_REVEAL):
				_pause(card, ScoreWalk.Stage.WATCHERS, watcher)
				return true
		return false

	## Fires `card`'s effect for `seat` when its trigger is `trigger`. True when it opened a
	## prompt, which is then `state.prompt`.
	func _fire(seat: int, card: int, trigger: int) -> bool:
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

	func _pause(card: int, stage: int, watcher: int) -> void:
		var walk: MatchState.WalkState = state.walk
		walk.paused_card = card
		walk.paused_stage = stage
		walk.paused_watcher = watcher
