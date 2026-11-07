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
## (reveal_stage(): its On reveal Batch and the D7 drain, TriggerQueue, DC-13 T05); then
## the score stage belongs to the card in the slot once the reveal
## stage has resolved (score_slot(), cycle 5 C23): a card that landed there by a Move Scores
## now (revealing in full first when face down), the pulsed card moved ahead is reached
## later, one moved behind the cursor waits for the next Walk (R44; Movement keeps the row's
## length, so the cursor does not change). When that card Scores (scores_now(): revealed and
## not Squelched or Silenced, R33), the score stage adds its Power to its Controller's
## walking total and multiplies the total by its Bonus value (Scoring.step_total, R26),
## CARD_SCORED {seat, card, slot, power, bonus_value, total, pass}, and wakes its On score
## (score_stage(): twice under Scores twice, then the D8 drain). Each pulse starts a new
## trigger budget (`walk.resolutions`, Q4); a drain paused on a prompt returns true from
## step() and the engine resumes it (TriggerQueue.answer, then resume_pulse() after a D7).
## Integer only, so every platform agrees. reveal() records each reveal in
## `walk.revealed_this_turn` (Finale, DC-14 T12).
##
## Events go to `sink` as sink.call(kind, payload) for the Walk's own public events and
## sink.call(kind, payload, owner) for an ability's events. A Walk with no valid sink emits
## nothing.

const MOMENT_REVEAL: String = "on_reveal"
const MOMENT_SCORE: String = "on_score"
## The Walk's two drain points (resolution section 2).
const STEP_REVEAL: String = "D7"
const STEP_SCORE: String = "D8"


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
	walk.hook_pending = 0
	walk.hook_card = -1
	walk.hook_moves = 0


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
		finish(state, sink, cards)
		return false
	var seat: int = at.x
	# The slot is passed before anything the pulse fires resolves.
	walk.cursor[seat] = at.y + 1
	walk.next_seat = 1 - walk.next_seat
	# A new pulse: a new budget of 50 (Q4).
	walk.resolutions = 0
	walk.pulse_seat = seat
	walk.pulse_slot = at.y
	walk.pulse_twice = walk.scores_twice
	var piles: MatchState.SeatPiles = state.seats[seat]
	var card: int = piles.board[at.y]
	if not piles.is_revealed(card):
		reveal(state, cards, sink, seat, card)
		if reveal_stage(state, cards, rng, sink, seat, card):
			return true
	return score_slot(state, cards, rng, sink, seat, at.y)


## The score stage of the pulse on `slot` of `seat`'s row (cycle 5 C23, C24; R44): it
## belongs to the card in the slot now, after the reveal stage resolved. A face-down card
## that landed there reveals in full first; then it Scores when scores_now(). True when a
## stage paused on a prompt.
static func score_slot(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, seat: int, slot: int
) -> bool:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if slot < 0 or slot >= piles.board.size():
		return false
	var card: int = piles.board[slot]
	if not piles.is_revealed(card):
		reveal(state, cards, sink, seat, card)
		if reveal_stage(state, cards, rng, sink, seat, card):
			return true
	if scores_now(state, seat, card):
		return score_stage(state, cards, rng, sink, seat, card)
	if not state.queue.is_empty():
		# A reveal-stage hook's On moved Batch still drains in D8 (Skip, DC-14 T13).
		return TriggerQueue.drain(state, cards, rng, sink, STEP_SCORE)
	return false


## Resumes the pulse whose D7 drain paused on a prompt, once that drain has finished: the
## reveal-stage hook (Skip, AbilitiesGraveyardControl.skip_hook), then its score stage
## (score_slot() on `walk.pulse_seat`, `walk.pulse_slot`). True when it paused again.
static func resume_pulse(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable
) -> bool:
	var walk: MatchState.WalkState = state.walk
	AbilitiesGraveyardControl.skip_hook(state, cards, rng, sink)
	return score_slot(state, cards, rng, sink, walk.pulse_seat, walk.pulse_slot)


## Runs the Walk from its current point to its end or to a prompt; true on a prompt.
static func run(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> bool:
	while state.walk.active:
		if step(state, cards, rng, sink):
			return true
	return false


## Ends the Walk (R27): at Walk end, before rounding, each seat's walking total takes its
## hand's Dross multiplies (AbilitiesComboDisruption.walk_end_total, DC-14 T12; none without
## `cards`), then each seat's Score is its walking total rounded once, then WALK_ENDED
## {totals, scores, dross} (`dross` the Dross counted per seat).
static func finish(state: MatchState, sink: Callable, cards: MatchCards = null) -> void:
	state.walk.active = false
	var dross: Array[int] = [0, 0]
	for seat: int in range(state.totals.size()):
		dross[seat] = AbilitiesComboDisruption.dross_in_hand(state, cards, seat)
		state.totals[seat] = AbilitiesComboDisruption.walk_end_total(state, cards, seat)
		state.scores[seat] = Scoring.walk_score(state.totals[seat])
		state.match_scores[seat] += state.scores[seat]
	if sink.is_valid():
		var ended: Dictionary = {
			"totals": MatchState.plain(state.totals),
			"scores": MatchState.plain(state.scores),
			"dross": MatchState.plain(dross),
		}
		sink.call(MatchEvent.Kind.WALK_ENDED, ended)


## Flips `card` face up on `seat`'s row: it joins the revealed set, leaves every seat's
## `looked`, and CARD_REVEALED {seat, card, slot, power, mult, add, statuses} is public
## (`statuses` the badge words it shows, Statuses.badges).
static func reveal(
	state: MatchState, cards: MatchCards, sink: Callable, seat: int, card: int
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.revealed[card] = true
	state.walk.revealed_this_turn[card] = true
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
		"statuses": _plain_words(Statuses.badges(state, cards, card)),
	}
	sink.call(MatchEvent.Kind.CARD_REVEALED, revealed)


## The reveal stage's abilities (DC-13 T05): `card`'s On reveal wakes a Batch
## (TriggerQueue.wake) and the queue drains (D7) on the pulse's budget; true when the drain
## paused on a prompt. DC-14 T13: a waiting Skip arms on `card` as it is revealed and its
## move runs once D7 has drained (the reveal-stage hook; resume_pulse() after a pause).
static func reveal_stage(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, _seat: int, card: int
) -> bool:
	AbilitiesGraveyardControl.arm_skip(state, card)
	var subjects: Array[int] = [card]
	if TriggerQueue.wake(state, cards, MOMENT_REVEAL, subjects).is_empty():
		pass  # Nothing watches this reveal: the drain is empty.
	if TriggerQueue.drain(state, cards, rng, sink, STEP_REVEAL):
		return true
	AbilitiesGraveyardControl.skip_hook(state, cards, rng, sink)
	return false


## Whether `card` on `seat`'s row Scores this pulse (R33): it is revealed and not Squelched
## (nor Silenced, which holds the Squelched half). A Muted or exit-marked card Scores (R39).
static func scores_now(state: MatchState, seat: int, card: int) -> bool:
	var piles: MatchState.SeatPiles = state.seats[seat]
	return piles.is_revealed(card) and not Statuses.has(state, card, Statuses.SQUELCHED)


## The Score of `card` on `seat`'s row (R26, R28, R29): its Controller's walking total gains
## its Power, then is multiplied by its Bonus value; `walk.scored_count[seat]` counts it;
## CARD_SCORED {seat, card, slot, power, bonus_value, total, pass} is public, `pass` 2 for
## the second run of a score stage under Scores twice (Q7).
static func score(
	state: MatchState,
	cards: MatchCards,
	sink: Callable,
	seat: int,
	card: int,
	pass_number: int = 1
) -> void:
	var walk: MatchState.WalkState = state.walk
	var piles: MatchState.SeatPiles = state.seats[seat]
	var count: int = walk.scored_count[seat] + 1
	var stats: Scoring.Stats = Scoring.score_stats(card, state, cards, seat, count)
	var bonus: int = stats.bonus_value()
	state.totals[seat] = Scoring.step_total(state.totals[seat], stats.power, bonus)
	walk.scored[card] = true
	walk.scored_count[seat] = count
	CrewAbilities.spend_grants(state, seat)
	if not sink.is_valid():
		return
	var scored: Dictionary = {
		"seat": seat,
		"card": card,
		"slot": piles.board.find(card),
		"power": stats.power,
		"bonus_value": bonus,
		"total": state.totals[seat],
		"pass": pass_number,
	}
	sink.call(MatchEvent.Kind.CARD_SCORED, scored)


## The score stage of `card` (DC-13 T05): it Scores (score()) and its On score wakes a
## Batch; when Scores twice applied as the pulse started (`walk.pulse_twice`: Q7, the
## pulses after the one that set it) it Scores again (pass 2) and wakes a second Batch;
## then the queue drains (D8) on the pulse's budget. True when the drain paused on a prompt.
static func score_stage(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, seat: int, card: int
) -> bool:
	var subjects: Array[int] = [card]
	var runs: int = 2 if state.walk.pulse_twice else 1
	for pass_index: int in range(runs):
		score(state, cards, sink, seat, card, pass_index + 1)
		# What the Score's Crew read as it was then (Navigator's count, Captain's slot; T07).
		var context: Dictionary = {
			CrewAbilities.KEY_SCORED_COUNT: state.walk.scored_count[seat],
			CrewAbilities.KEY_SLOT: state.seats[seat].board.find(card),
		}
		if TriggerQueue.wake(state, cards, MOMENT_SCORE, subjects, -1, context).is_empty():
			pass  # Nothing watches this Score.
	return TriggerQueue.drain(state, cards, rng, sink, STEP_SCORE)


## An untyped copy of `words`, so a payload holds plain data.
static func _plain_words(words: Array[String]) -> Array:
	var out: Array = []
	out.assign(words)
	return out
