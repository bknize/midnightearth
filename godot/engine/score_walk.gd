class_name ScoreWalk
extends RefCounted
## The pure, resumable score walk over a MatchState (DC-06 cursor, R11-R18). All of its
## progress lives in `state.walk`.
##
## DC-13 T02 interim walk (cycle 9 plan, wave 2): the v6 structure with the v2 card anatomy
## and every ability inert. begin() resets both scores to 0 and both multipliers to ×1.00
## (MatchRules.BONUS_ONE in hundredths), then each step() pulses one slot until no slot is
## left. The cursor (DC-06 R1-R4, P1): one slot index per row, `walk.cursor[seat]`, the
## number of that row's slots already passed. The next pulse is the slot at the cursor of
## `walk.next_seat`'s row when that row has one left, else the other row's, else the walk
## ends (next_slot()). A pulse at (seat, slot) sets `cursor[seat] = slot + 1`, flips
## `next_seat`, then runs on the card there: a face-down card is revealed (CARD_REVEALED,
## then Abilities.fire on `on_reveal`), then it scores (CARD_SCORED, then Abilities.fire on
## `on_score`). Abilities.fire is T02's stub: it fizzles each ability and moves nothing, so
## a pulse never pauses and the cursor never follows a moved card.
##
## The score reads effective(): the card's Power (its printed `power`, plus its memory and
## board flat deltas, which no T02 ability writes) with a ×1 Bonus, so the multiplier stays
## ×1.00 and a card adds its Power to its seat's score. T03 replaces this with the walking
## total (Scoring, plan P7). Integer only, so every platform agrees.
##
## Events go to `sink` as sink.call(kind, payload) for the walk's own public events and
## sink.call(kind, payload, owner) for an ability's events. A walk with no valid sink emits
## nothing.

## Added before the division by 100 so a hundredths product rounds to the nearest.
const HALF_HUNDREDTH: int = 50
const MOMENT_REVEAL: String = "on_reveal"
const MOMENT_SCORE: String = "on_score"


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
	walk.mult[0] = MatchRules.BONUS_ONE
	walk.mult[1] = MatchRules.BONUS_ONE
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


## `card`'s shown stats (T02): `flat` its Power (the printed `power`, or a copied base once
## a CardState holds one, plus the memory's and the board's flat deltas), `times` ×1.00 and
## `plus` 0, so every card scores with a ×1 Bonus until T03. Flat 0 for a card with no
## definition. Every reader (the walk, SeatView, the board's view entries) goes through it.
static func effective(card: int, state: MatchState, cards: MatchCards) -> Effective:
	var out: Effective = Effective.new()
	var def: CardDef = _definition(card, cards)
	if def == null:
		return out
	var held: CardState = state.card_state(card)
	out.flat = held.base_flat if held != null and held.has_base else def.power
	var kept: CardMemory = state.memory_of(card)
	if kept != null:
		out.flat += kept.flat
	if held != null:
		out.flat += held.flat_delta
	return out


## `card`'s effective cost: its printed cost less its memory's cost reduction, never below
## MatchRules.MIN_COST; -1 when the card has no definition (an unpriced card, as
## LegalPlays.cost_of reports it). Every budget check reads this.
static func effective_cost(card: int, state: MatchState, cards: MatchCards) -> int:
	var def: CardDef = _definition(card, cards)
	if def == null:
		return -1
	var kept: CardMemory = state.memory_of(card) if state != null else null
	if kept == null:
		return def.cost
	return maxi(def.cost - kept.cost, MatchRules.MIN_COST)


## The effective costs of `hand`, in its order (effective_cost each).
static func effective_costs(hand: Array[int], state: MatchState, cards: MatchCards) -> Array[int]:
	var out: Array[int] = []
	for card: int in hand:
		out.append(effective_cost(card, state, cards))
	return out


## The uses `card`'s first limited ability has left, as a view shows them: -1 when none of
## its abilities is limited (every milestone A card), the ability's `uses` until the memory
## has read them, then the memory's `uses_left`.
static func uses_left(card: int, state: MatchState, cards: MatchCards) -> int:
	var def: CardDef = _definition(card, cards)
	if def == null:
		return -1
	for ability: CardAbility in def.abilities:
		if ability.uses <= 0:
			continue
		var kept: CardMemory = state.memory_of(card)
		if kept == null or kept.uses_left < 0:
			return ability.uses
		return kept.uses_left
	return -1


## Whether `card` carries a memory that is not empty (cycle 8 R7: the grown mark).
static func is_grown(card: int, state: MatchState) -> bool:
	var kept: CardMemory = state.memory_of(card)
	return kept != null and not kept.is_empty()


## `a * b` for two hundredths values, rounded to the nearest hundredth.
static func times_hundredths(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return (a * b + HALF_HUNDREDTH) / MatchRules.BONUS_ONE


## One pulse. Returns true when the walk is paused on an open prompt (only a hand-made one:
## no T02 ability prompts). When no card is left the walk ends (`walk.active` becomes false)
## and nothing else changes. `rng` is the engine stream, passed to Abilities.fire.
static func step(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> bool:
	if not state.prompt.is_empty():
		return true
	var walk: MatchState.WalkState = state.walk
	var at: Vector2i = next_slot(state)
	if at.x < 0:
		walk.active = false
		return false
	var seat: int = at.x
	# The slot is passed before anything the pulse fires resolves (R2).
	walk.cursor[seat] = at.y + 1
	walk.next_seat = 1 - walk.next_seat
	var piles: MatchState.SeatPiles = state.seats[seat]
	var card: int = piles.board[at.y]
	var live: bool = sink.is_valid()
	if state.is_destroyed(card):
		_pulse_destroyed(state, cards, sink, live, seat, card)
		return false
	if not piles.is_revealed(card):
		piles.revealed[card] = true
		if live:
			_emit_reveal(state, cards, sink, seat, card, false)
		walk.reveals += 1
		_forward(Abilities.fire(state, cards, rng, seat, card, MOMENT_REVEAL), sink)
	_score(state, cards, sink, live, seat, card)
	if piles.is_revealed(card):
		_forward(Abilities.fire(state, cards, rng, seat, card, MOMENT_SCORE), sink)
	return false


## Runs the walk from its current point to its end or to a prompt; true on a prompt. The
## engine loops step() itself so it can stop between pulses.
static func run(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> bool:
	while state.walk.active:
		if step(state, cards, rng, sink):
			return true
	return false


## The definition of `card` (an instance id, read through its origin's deck), or null.
static func _definition(card: int, cards: MatchCards) -> CardDef:
	if cards == null:
		return null
	return cards.def_of(card)


## The pulse of a destroyed `card` on `seat`'s row (DC-06 R13, R14): face down, it is
## revealed (CARD_REVEALED with `destroyed` true) and nothing more; face up, nothing. No T02
## ability destroys, so only a hand-made state reaches it.
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


## Sends an ability's events to `sink` with their owners, when the sink is valid.
static func _forward(events: Array[MatchEvent], sink: Callable) -> void:
	if not sink.is_valid():
		return
	for event: MatchEvent in events:
		sink.call(event.kind, event.payload, event.owner_seat)


## The score of `card` on `seat`'s row: the multiplier is multiplied by the card's ×-part
## (×1.00 in T02) and gains its +-part (0), then the seat's score gains the flat times the
## multiplier, floored. CARD_SCORED on a live walk, `again` true when the card already
## scored in this walk (DC-06 R9, P3).
static func _score(
	state: MatchState, cards: MatchCards, sink: Callable, live: bool, seat: int, card: int
) -> void:
	var walk: MatchState.WalkState = state.walk
	var piles: MatchState.SeatPiles = state.seats[seat]
	var stats: Effective = effective(card, state, cards)
	var mult: int = times_hundredths(walk.mult[seat], stats.times)
	mult += stats.plus * MatchRules.BONUS_ONE
	walk.mult[seat] = mult
	@warning_ignore("integer_division")
	var added: int = stats.flat * mult / MatchRules.BONUS_ONE
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


## CARD_REVEALED for `card`, which has just been revealed on `seat`'s row. `order` counts
## the reveals of this walk from 0; `destroyed` is true when the card was destroyed before
## the cursor reached it (DC-06 R14). `cost` is its effective cost and `grown` whether its
## memory is not empty (cycle 8 R7, R25): public, as the card now is.
static func _emit_reveal(
	state: MatchState, cards: MatchCards, sink: Callable, seat: int, card: int, destroyed: bool
) -> void:
	var def: CardDef = _definition(card, cards)
	var def_id: String = def.id if def != null else ""
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


## A card's effective stats: `flat` (its Power), `times` (the ×-part in hundredths, 100 for
## none) and `plus` (the +-part in whole units). ScoreWalk.effective() builds them.
class Effective:
	extends RefCounted

	var flat: int = 0
	var times: int = MatchRules.BONUS_ONE
	var plus: int = 0

	## The stats as plain data: {flat, times, plus}.
	func to_dict() -> Dictionary:
		return {"flat": flat, "times": times, "plus": plus}
