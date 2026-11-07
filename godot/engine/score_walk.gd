class_name ScoreWalk
extends RefCounted
## The pure, resumable Walk over a MatchState (cycle 9 plan P7; spec R25 to R29, R44). All
## of its progress lives in `state.walk`.
##
## begin() sets both walking totals to 0 (R25) and both cursors to slot 0; each step() then
## pulses one slot until no slot is left, when the Walk ends: each seat's Score is its
## walking total rounded once (Scoring.walk_score, R27) and WALK_ENDED {totals, scores}
## follows. The cursor (cycle 5 cursor rules, R44): one slot index per row,
## `walk.cursor[seat]`, the number of that row's slots already passed. The next pulse is the
## slot at the cursor of `walk.next_seat`'s row when that row has one left, else the other
## row's. A pulse at (seat, slot) sets `cursor[seat] = slot + 1` and flips `next_seat`.
##
## One pulse (resolution section 3): the reveal stage flips a face-down card
## (CARD_REVEALED {seat, card, slot, power, mult, add, statuses}) and runs its On reveal
## (reveal_stage(): Abilities.fire, the T02 stub; DC-13 T05 replaces it with the Batch and
## the D7 drain); then, when the card Scores (scores_now(); T04 adds Squelched), the score
## stage adds its Power to its Controller's walking total and multiplies the total by its
## Bonus value (Scoring.step_total, R26), CARD_SCORED {seat, card, slot, power, bonus_value,
## total, pass: 1}, and runs its On score (score_stage(); T05: the Batch and D8). Integer
## only, so every platform agrees.
##
## Events go to `sink` as sink.call(kind, payload) for the Walk's own public events and
## sink.call(kind, payload, owner) for an ability's events. A Walk with no valid sink emits
## nothing.

const MOMENT_REVEAL: String = "on_reveal"
const MOMENT_SCORE: String = "on_score"


## Starts a Walk on `state` (R25): both walking totals 0, both cursors at slot 0, nothing
## Scored, the Turn's first committer pulses first. The Scores keep the previous Walk's
## until this one ends (R77: the HUD shows the previous Score meanwhile).
static func begin(state: MatchState) -> void:
	state.totals[0] = 0
	state.totals[1] = 0
	var walk: MatchState.WalkState = state.walk
	walk.active = true
	walk.next_seat = state.first_seat
	walk.cursor[0] = 0
	walk.cursor[1] = 0
	walk.scored.clear()
	walk.scored_count[0] = 0
	walk.scored_count[1] = 0


## The next slot to pulse as (seat, slot), or (-1, -1) when the Walk is over or neither
## row has a slot the cursor has not passed.
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


## One pulse. Returns true when the Walk is paused on an open prompt (none opens before
## DC-13 T05). When no slot is left the Walk ends (finish()). `rng` is the engine stream.
static func step(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> bool:
	if not state.prompt.is_empty():
		return true
	var walk: MatchState.WalkState = state.walk
	var at: Vector2i = next_slot(state)
	if at.x < 0:
		finish(state, sink)
		return false
	var seat: int = at.x
	# The slot is passed before anything the pulse fires resolves.
	walk.cursor[seat] = at.y + 1
	walk.next_seat = 1 - walk.next_seat
	var piles: MatchState.SeatPiles = state.seats[seat]
	var card: int = piles.board[at.y]
	if not piles.is_revealed(card):
		reveal(state, cards, sink, seat, card)
		if reveal_stage(state, cards, rng, sink, seat, card):
			return true
	if scores_now(state, seat, card):
		score(state, cards, sink, seat, card)
		return score_stage(state, cards, rng, sink, seat, card)
	return false


## Runs the Walk from its current point to its end or to a prompt; true on a prompt.
static func run(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> bool:
	while state.walk.active:
		if step(state, cards, rng, sink):
			return true
	return false


## Ends the Walk (R27): each seat's Score is its walking total rounded once, then
## WALK_ENDED {totals, scores}.
static func finish(state: MatchState, sink: Callable) -> void:
	state.walk.active = false
	for seat: int in range(state.totals.size()):
		state.scores[seat] = Scoring.walk_score(state.totals[seat])
	if sink.is_valid():
		var ended: Dictionary = {
			"totals": MatchState.plain(state.totals),
			"scores": MatchState.plain(state.scores),
		}
		sink.call(MatchEvent.Kind.WALK_ENDED, ended)


## Flips `card` face up on `seat`'s row: it joins the revealed set, leaves every seat's
## `looked`, and CARD_REVEALED {seat, card, slot, power, mult, add, statuses} is public
## (`statuses` the status words, T04).
static func reveal(
	state: MatchState, cards: MatchCards, sink: Callable, seat: int, card: int
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.revealed[card] = true
	for watcher: MatchState.SeatPiles in state.seats:
		if watcher.looked.erase(card):
			pass  # A revealed card is public: no seat needs to remember it.
	if not sink.is_valid():
		return
	var shown: Scoring.Stats = Scoring.stats(card, state, cards)
	var revealed: Dictionary = {
		"seat": seat,
		"card": card,
		"slot": piles.board.find(card),
		"power": shown.power,
		"mult": shown.mult(),
		"add": shown.add(),
		"statuses": [],
	}
	sink.call(MatchEvent.Kind.CARD_REVEALED, revealed)


## The reveal stage's abilities (hook): the T02 stub fires `card`'s On reveal through
## Abilities.fire. DC-13 T05 wakes the On reveal Batch here and drains D7; true when the
## drain paused on a prompt.
static func reveal_stage(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, seat: int, card: int
) -> bool:
	_forward(Abilities.fire(state, cards, rng, seat, card, MOMENT_REVEAL), sink)
	return false


## Whether `card` on `seat`'s row Scores this pulse (R33): it is revealed; DC-13 T04 adds
## that a Squelched or Silenced card does not.
static func scores_now(state: MatchState, seat: int, card: int) -> bool:
	var piles: MatchState.SeatPiles = state.seats[seat]
	return piles.is_revealed(card)


## The Score of `card` on `seat`'s row (R26, R28, R29): its Controller's walking total gains
## its Power, then is multiplied by its Bonus value; `walk.scored_count[seat]` counts it;
## CARD_SCORED {seat, card, slot, power, bonus_value, total, pass: 1} is public.
static func score(
	state: MatchState, cards: MatchCards, sink: Callable, seat: int, card: int
) -> void:
	var walk: MatchState.WalkState = state.walk
	var piles: MatchState.SeatPiles = state.seats[seat]
	var stats: Scoring.Stats = Scoring.stats(card, state, cards)
	var bonus: int = stats.bonus_value()
	state.totals[seat] = Scoring.step_total(state.totals[seat], stats.power, bonus)
	walk.scored[card] = true
	walk.scored_count[seat] += 1
	if not sink.is_valid():
		return
	var scored: Dictionary = {
		"seat": seat,
		"card": card,
		"slot": piles.board.find(card),
		"power": stats.power,
		"bonus_value": bonus,
		"total": state.totals[seat],
		"pass": 1,
	}
	sink.call(MatchEvent.Kind.CARD_SCORED, scored)


## The score stage's abilities (hook): the T02 stub fires `card`'s On score through
## Abilities.fire. DC-13 T05 wakes the On score Batch here and drains D8; true when the
## drain paused on a prompt.
static func score_stage(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, seat: int, card: int
) -> bool:
	_forward(Abilities.fire(state, cards, rng, seat, card, MOMENT_SCORE), sink)
	return false


## Sends an ability's events to `sink` with their owners, when the sink is valid.
static func _forward(events: Array[MatchEvent], sink: Callable) -> void:
	if not sink.is_valid():
		return
	for event: MatchEvent in events:
		sink.call(event.kind, event.payload, event.owner_seat)
