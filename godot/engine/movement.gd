class_name Movement
extends RefCounted
## Moves and Placement on a row (cycle 9 plan P10; spec R40, R42 to R44; canon glossary
## Move, Placement, Ring, shift, swap, reverse, reorder). Static and pure over a MatchState:
## no node, no clock; reorder() draws only from the engine stream passed in. Events go to
## `sink` as sink.call(kind, payload, owner) when the sink is valid.
##
## - A Move is a change of slot made by an effect. Stepwise moves treat the row as a ring:
##   left of the leftmost slot is the rightmost (R42). An Anchored card
##   (Statuses.is_anchored) is never moved: the moving cards slide past it, a swap naming it
##   fizzles, a reverse or reorder leaves it in its slot and permutes the rest (R40).
## - Every move returns the cards whose slot it changed, in their new slot order: the one
##   On moved Batch the move wakes (DC-13 T05 hands them to TriggerQueue.wake), and emits
##   one CARD_MOVED {card, seat, from, to, cause} per card, private to the row's seat while
##   the card is face down. A move that changes nothing returns an empty list.
## - step_set() moves a set of cards one step on the ring of free (not Anchored) slots: each
##   mover takes the next free slot in the direction; a card that is not moving and is
##   displaced takes the slot left by the last mover of the run that pushed it, so a single
##   shift trades places with its next free neighbour and "every other card shifts left" is
##   a rotation of the free slots (canon scenario 8: A B C with B Anchored reads C B A).
## - move_to() moves one card to a given free slot, the others keeping their order (Skip).
## - place() is Placement (R43): the card is inserted at a slot, other cards' slot numbers
##   change, nothing is moved and no Anchor is broken.
## - The cursor (cycle 5 rules, R44): a Move keeps the row's length, so `walk.cursor` (the
##   slots passed) is unchanged: a card moved to a passed slot waits for the next Walk, one
##   moved ahead is reached later, one landing on the pulsed slot Scores now
##   (ScoreWalk.score_slot). A Placement during a Walk at a passed slot moves the cursor on
##   by one, so the passed cards stay passed and the placed card waits.

const LEFT: int = -1
const RIGHT: int = 1


## Moves `card` one slot in `dir` (LEFT or RIGHT) on the ring of its row (shift, Nudge).
## Empty when it is Anchored or on no row.
static func shift(
	state: MatchState, cards: MatchCards, card: int, dir: int, cause: String, sink: Callable
) -> Array[int]:
	var seat: int = Statuses.row_seat(state, card)
	var out: Array[int] = []
	if seat < 0:
		return out
	var movers: Array[int] = [card]
	return step_set(state, cards, seat, movers, dir, cause, sink)


## Moves each card of `movers` on `seat`'s row one slot in `dir` at once (see the class
## comment). Anchored cards and cards not on the row are left out. While a Fence is read
## (DC-14 T13), a mover that would wrap the ring is Condemned instead and stays
## (AbilitiesGraveyardControl.fence_movers).
static func step_set(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	movers: Array[int],
	dir: int,
	cause: String,
	sink: Callable
) -> Array[int]:
	var going: Array[int] = AbilitiesGraveyardControl.fence_movers(
		state, cards, seat, movers, dir, sink
	)
	var row: Array[int] = []
	row.assign(state.seats[seat].board)
	var free: Array[int] = free_slots(state, cards, seat)
	var count: int = free.size()
	var step: int = RIGHT if dir >= 0 else LEFT
	var moving: Array[bool] = []
	var placed: Array[int] = []
	for index: int in range(count):
		moving.append(going.has(row[free[index]]))
		placed.append(-1)
	for index: int in range(count):
		if moving[index]:
			placed[posmod(index + step, count)] = row[free[index]]
	for index: int in range(count):
		if moving[index]:
			continue
		if not moving[posmod(index - step, count)]:
			placed[index] = row[free[index]]
			continue
		# Displaced: it takes the slot of the last mover of the run behind it.
		var back: int = posmod(index - step, count)
		while moving[posmod(back - step, count)]:
			back = posmod(back - step, count)
		placed[back] = row[free[index]]
	var next: Array[int] = []
	next.assign(row)
	for index: int in range(count):
		next[free[index]] = placed[index]
	return _commit(state, seat, next, cause, sink)


## Moves every card of `movers` on `seat`'s row one slot left (Shake, milestone B).
static func step_left_set(
	state: MatchState,
	cards: MatchCards,
	seat: int,
	movers: Array[int],
	cause: String,
	sink: Callable
) -> Array[int]:
	return step_set(state, cards, seat, movers, LEFT, cause, sink)


## Moves `card` to position `target` among the free (not Anchored) slots of its row, the
## other free cards keeping their order around it (Skip, DC-14 T13). Empty when it is
## Anchored, on no row, already there or `target` is out of range.
static func move_to(
	state: MatchState, cards: MatchCards, card: int, target: int, cause: String, sink: Callable
) -> Array[int]:
	var out: Array[int] = []
	var seat: int = Statuses.row_seat(state, card)
	if seat < 0 or Statuses.is_anchored(state, cards, card):
		return out
	var row: Array[int] = state.seats[seat].board
	var free: Array[int] = free_slots(state, cards, seat)
	var order: Array[int] = []
	for slot: int in free:
		order.append(row[slot])
	var from: int = order.find(card)
	if target < 0 or target >= order.size() or target == from:
		return out
	order.remove_at(from)
	if order.insert(target, card) != OK:
		return out
	var next: Array[int] = []
	next.assign(row)
	for index: int in range(free.size()):
		next[free[index]] = order[index]
	return _commit(state, seat, next, cause, sink)


## Trades the slots of `a` and `b` on one row. Fizzles (empty) when either is Anchored, they
## are the same card, or they are not on the same row.
static func swap(
	state: MatchState, cards: MatchCards, a: int, b: int, cause: String, sink: Callable
) -> Array[int]:
	var out: Array[int] = []
	var seat: int = Statuses.row_seat(state, a)
	if a == b or seat < 0 or Statuses.row_seat(state, b) != seat:
		return out
	if Statuses.is_anchored(state, cards, a) or Statuses.is_anchored(state, cards, b):
		return out
	var next: Array[int] = []
	next.assign(state.seats[seat].board)
	var slot_a: int = next.find(a)
	var slot_b: int = next.find(b)
	next[slot_a] = b
	next[slot_b] = a
	return _commit(state, seat, next, cause, sink)


## Flips the order of `seat`'s row; Anchored cards keep their slots and the others are
## reversed around them.
static func reverse(
	state: MatchState, cards: MatchCards, seat: int, cause: String, sink: Callable
) -> Array[int]:
	var free: Array[int] = free_slots(state, cards, seat)
	var row: Array[int] = state.seats[seat].board
	var next: Array[int] = []
	next.assign(row)
	var count: int = free.size()
	for index: int in range(count):
		next[free[index]] = row[free[count - 1 - index]]
	return _commit(state, seat, next, cause, sink)


## Permutes `seat`'s row at random with the engine stream `rng`; Anchored cards keep their
## slots.
static func reorder(
	state: MatchState, cards: MatchCards, seat: int, rng: MatchRng, cause: String, sink: Callable
) -> Array[int]:
	var free: Array[int] = free_slots(state, cards, seat)
	var row: Array[int] = state.seats[seat].board
	var shuffled: Array[int] = []
	for slot: int in free:
		shuffled.append(row[slot])
	rng.shuffle_in_place(shuffled)
	var next: Array[int] = []
	next.assign(row)
	for index: int in range(free.size()):
		next[free[index]] = shuffled[index]
	return _commit(state, seat, next, cause, sink)


## Placement (R43): inserts `card` into `seat`'s row at `slot` (clamped to the row), face
## down unless the caller reveals it. Other cards' slot numbers change but none is moved,
## so no CARD_MOVED and no On moved; an Anchored card is not moved by it either. During a
## Walk a slot the cursor has passed moves the cursor on by one (the class comment).
## Returns the slot used.
static func place(state: MatchState, seat: int, card: int, slot: int) -> int:
	var row: Array[int] = state.seats[seat].board
	var at: int = clampi(slot, 0, row.size())
	if row.insert(at, card) != OK:
		return -1
	var walk: MatchState.WalkState = state.walk
	if walk.active and at < walk.cursor[seat]:
		walk.cursor[seat] += 1
	return at


## The slots of `seat`'s row whose card is not Anchored, ascending.
static func free_slots(state: MatchState, cards: MatchCards, seat: int) -> Array[int]:
	var out: Array[int] = []
	var row: Array[int] = state.seats[seat].board
	for slot: int in range(row.size()):
		if not Statuses.is_anchored(state, cards, row[slot]):
			out.append(slot)
	return out


## Writes `next` as `seat`'s row and reports every card whose slot changed: one CARD_MOVED
## each, in new slot order; returns them in that order.
static func _commit(
	state: MatchState, seat: int, next: Array[int], cause: String, sink: Callable
) -> Array[int]:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var before: Array[int] = []
	before.assign(piles.board)
	piles.board.assign(next)
	var moved: Array[int] = []
	for slot: int in range(next.size()):
		var card: int = next[slot]
		var from: int = before.find(card)
		if from == slot:
			continue
		moved.append(card)
		if sink.is_valid():
			var payload: Dictionary = {
				"card": card, "seat": seat, "from": from, "to": slot, "cause": cause
			}
			var owner: int = MatchEvent.PUBLIC if piles.is_revealed(card) else seat
			sink.call(MatchEvent.Kind.CARD_MOVED, payload, owner)
	return moved
