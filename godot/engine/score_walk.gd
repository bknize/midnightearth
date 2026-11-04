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
## Events go to `sink` as sink.call(kind, payload), every one public. A null `policy` is a
## live walk; a preview passes a PreviewPolicy and gets no events.


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


## One pulse (P3). Returns true when the walk paused on a prompt (never before DC-05 T05).
## When no card is left the walk ends (`walk.active` becomes false) and nothing else
## changes. `_rng` is the engine stream, for effects that draw from it (T05).
static func step(
	state: MatchState, cards: CardDb, _rng: MatchRng, sink: Callable, policy: PreviewPolicy
) -> bool:
	var card: int = next_card(state)
	if card < 0:
		state.walk.active = false
		return false
	var seat: int = _row_seat(state, card)
	var walk: MatchState.WalkState = state.walk
	walk.pulsed[card] = true
	walk.next_seat = 1 - walk.next_seat
	var live: bool = policy == null and sink.is_valid()
	var piles: MatchState.SeatPiles = state.seats[seat]
	if not piles.is_revealed(card):
		piles.revealed[card] = true
		if live:
			_emit_reveal(state, cards, sink, seat, card)
		walk.reveals += 1
		# On-reveal effects fire here, before scoring (R13; DC-05 T04, T05).
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
	# On-score effects fire here, after CARD_SCORED (R15; DC-05 T04).
	return false


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
