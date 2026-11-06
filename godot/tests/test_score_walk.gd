# gdlint: disable=max-public-methods,max-file-lines
class_name TestScoreWalk
extends GdUnitTestSuite
## ScoreWalk (R11-R18, plan P3-P5) and CardState: the walk's math (C2; the hundredths mult
## of DC-07 P4, whose own cases live in test_score_walk_mult.gd), its cursor (C4),
## recomputation every turn (C3), the per-walk multiplier, effective stats from CardState,
## and a walk on a MatchState.duplicate() giving the live engine's scores (plan
## P12). DC-06 T01 (R1-R11): the slot cursor, one pulse per slot (n + m pulses),
## the score stage belonging to the slot through c12's swap (C23-C25: the card landing on
## the pulsed slot scores now, the moved card later or not this walk), a card swapped
## behind the cursor skipped (and left face down), a card swapped ahead of it scored again
## with `again`. More slot-occupant cases live in test_slot_occupant.gd.
##
## Most states are built directly: rows of vanilla cards from the default card list, so no
## effect fires once T04 and T05 add them. Card instance ids are seat * DECK_SIZE + index.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
const MAX_ACTIONS: int = 2000
# Definition indices (= seat-0 instance ids) of the cards the cases name.
const C04: int = 3
const C06_FLAT_UP: int = 5
const C08: int = 7
const C12_SWAP: int = 11

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## The fixture-vs-fixture definitions over _db() (DC-07 T02), for ScoreWalk,
## EffectResolver and RandomBot.
func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## The definition indices of the effect-free cards, in list order.
func _vanilla() -> Array[int]:
	var out: Array[int] = []
	for index: int in range(_db().size()):
		if _db().card_at(index).effect == null:
			out.append(index)
	return out


## `seat`'s instance of the first effect-free card with this flat and ×-part (hundredths,
## 100 for none; the fixture has no +bonus); -1 if none.
func _card_with(seat: int, flat: int, times: int) -> int:
	for index: int in _vanilla():
		var def: CardDef = _db().card_at(index)
		if def.flat == flat and _times_of(def) == times:
			return seat * MatchRules.DECK_SIZE + index
	return -1


## A definition's printed ×-part in hundredths: its ×-bonus, or 100 (×1.00) without one.
func _times_of(def: CardDef) -> int:
	if def.bonus_kind == CardDef.BonusKind.TIMES:
		return def.bonus
	return MatchRules.MULT_ONE


## A definition's printed +-part in whole units: its +bonus, or 0 without one.
func _plus_of(def: CardDef) -> int:
	if def.bonus_kind == CardDef.BonusKind.PLUS:
		return def.bonus
	return 0


## Effective stats as plain data, for comparisons.
func _eff(card: int, state: MatchState) -> Dictionary:
	return ScoreWalk.effective(card, state, _defs()).to_dict()


func _stats(flat: int, times: int, plus: int) -> Dictionary:
	return {"flat": flat, "times": times, "plus": plus}


## `seat`'s instances of the first `count` effect-free cards.
func _vanilla_cards(seat: int, count: int) -> Array[int]:
	var out: Array[int] = []
	var indices: Array[int] = _vanilla()
	for i: int in range(count):
		out.append(seat * MatchRules.DECK_SIZE + indices[i])
	return out


## A state with these rows (seat 0, seat 1), nothing revealed, `first` committing first.
func _state(row_0: Array[int], row_1: Array[int], first: int) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = first
	state.seats[0].board.assign(row_0)
	state.seats[1].board.assign(row_1)
	return state


## The P4 math on one row, from the definitions alone (no CardState; DC-07 P4): the
## multiplier starts at 100 (×1.00, in hundredths), is multiplied by each card's ×-part
## (rounded to the nearest hundredth) and gains its +-part before that card's flat is
## multiplied in, floored.
func _walk_score(row: Array[int]) -> int:
	var mult: int = 100
	var total: int = 0
	for card: int in row:
		var def: CardDef = _db().card_at(card % MatchRules.DECK_SIZE)
		mult = (mult * _times_of(def) + 50) / 100
		mult += _plus_of(def) * 100
		total += def.flat * mult / 100
	return total


## Runs the walk on `state` from begin() to its end, recording the events.
func _walk(state: MatchState, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < 100:
		var paused: bool = ScoreWalk.step(state, _defs(), null, recorder.record)
		assert_bool(paused).is_false()
		guard += 1


func _of_kind(events: Array[MatchEvent], kind: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == kind:
			out.append(event)
	return out


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _payload_ints(event: MatchEvent, key: String) -> Array[int]:
	var raw: Array = event.payload[key]
	return _typed(raw)


## The `card` of every event of `kind`, in order.
func _cards_of(events: Array[MatchEvent], kind: int) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, kind):
		out.append(_payload_int(event, "card"))
	return out


func _sorted(values: Array[int]) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	out.sort()
	return out


func _state_ints(state: Dictionary, key: String) -> Array[int]:
	var raw: Array = state[key]
	return _typed(raw)


# --- C2, R14: the math ----------------------------------------------------------------


## [flat 3 ×1.25] then [flat 4] scores floor(3 × 1.25) + floor(4 × 1.25) = 3 + 5 = 8;
## reversed, 4 + 3 = 7 (DC-07 P4; the DC-05 integer mult gave 14 and 10).
func test_bonus_card_left_of_the_flat_card_scores_8_and_reversed_7() -> void:
	var bonus_card: int = _card_with(0, 3, 125)
	var flat_card: int = _card_with(0, 4, 100)
	assert_int(bonus_card).is_greater_equal(0)
	assert_int(flat_card).is_greater_equal(0)
	var none: Array[int] = []
	var left: MatchState = _state(_typed([bonus_card, flat_card]), none, 0)
	var recorder: Recorder = Recorder.new()
	_walk(left, recorder)
	assert_array(left.scores).is_equal(_typed([8, 0]))
	assert_bool(left.walk.active).is_false()
	# Each CARD_SCORED carries the amounts and the running score (R14).
	var scored: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED)
	assert_int(scored.size()).is_equal(2)
	# [card, slot, flat, times, plus, mult, added, score]
	var expected: Array[Array] = [
		[bonus_card, 0, 3, 125, 0, 125, 3, 3], [flat_card, 1, 4, 100, 0, 125, 5, 8]
	]
	for i: int in range(2):
		var row: Array = expected[i]
		var want: Array[int] = _typed(row)
		assert_int(_payload_int(scored[i], "seat")).is_equal(0)
		assert_int(_payload_int(scored[i], "card")).is_equal(want[0])
		assert_int(_payload_int(scored[i], "slot")).is_equal(want[1])
		assert_int(_payload_int(scored[i], "flat")).is_equal(want[2])
		assert_int(_payload_int(scored[i], "times")).is_equal(want[3])
		assert_int(_payload_int(scored[i], "plus")).is_equal(want[4])
		assert_int(_payload_int(scored[i], "mult")).is_equal(want[5])
		assert_int(_payload_int(scored[i], "added")).is_equal(want[6])
		assert_int(_payload_int(scored[i], "score")).is_equal(want[7])
		assert_bool(scored[i].payload.has("bonus")).is_false()
		assert_int(scored[i].owner_seat).is_equal(MatchEvent.PUBLIC)
	var right: MatchState = _state(_typed([flat_card, bonus_card]), none, 0)
	_walk(right, Recorder.new())
	assert_array(right.scores).is_equal(_typed([7, 0]))


func test_each_seat_has_its_own_multiplier() -> void:
	var bonus_card: int = _card_with(0, 3, 125)
	var flat_card: int = _card_with(1, 4, 100)
	# Seat 0's bonus must not multiply seat 1's card, even though seat 1 pulses after it.
	var state: MatchState = _state(_typed([bonus_card]), _typed([flat_card]), 0)
	_walk(state, Recorder.new())
	assert_array(state.scores).is_equal(_typed([3, 4]))
	assert_array(state.walk.mult).is_equal(_typed([125, 100]))


# --- C4, R12: the cursor --------------------------------------------------------------


## Spec scenario: the first committer's row holds 3 cards and the second's 1: the pulse
## order is first-0, second-0, first-1, first-2.
func test_three_against_one_alternates_then_finishes_the_longer_row() -> void:
	for first: int in range(2):
		var long_row: Array[int] = _vanilla_cards(first, 3)
		var short_row: Array[int] = _vanilla_cards(1 - first, 1)
		var rows: Array[Array] = [[], []]
		rows[first] = long_row
		rows[1 - first] = short_row
		var state: MatchState = _state(_typed(rows[0]), _typed(rows[1]), first)
		var recorder: Recorder = Recorder.new()
		ScoreWalk.begin(state)
		var order: Array[int] = []
		while state.walk.active:
			var next: int = ScoreWalk.next_card(state)
			ScoreWalk.step(state, _defs(), null, recorder.record)
			if next >= 0:
				order.append(next)
		var expected: Array[int] = [long_row[0], short_row[0], long_row[1], long_row[2]]
		assert_array(order).is_equal(expected)
		assert_array(_cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)).is_equal(expected)
		var seats: Array[int] = []
		for event: MatchEvent in _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED):
			seats.append(_payload_int(event, "seat"))
		assert_array(seats).is_equal(_typed([first, 1 - first, first, first]))
		assert_int(ScoreWalk.next_card(state)).is_equal(-1)


func test_one_against_three_finishes_the_second_row() -> void:
	var short_row: Array[int] = _vanilla_cards(0, 1)
	var long_row: Array[int] = _vanilla_cards(1, 3)
	var state: MatchState = _state(short_row, long_row, 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var expected: Array[int] = [short_row[0], long_row[0], long_row[1], long_row[2]]
	assert_array(_cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)).is_equal(expected)


func test_an_empty_walk_ends_on_its_first_step() -> void:
	var none: Array[int] = []
	var state: MatchState = _state(none, none, 1)
	ScoreWalk.begin(state)
	assert_bool(state.walk.active).is_true()
	assert_int(state.walk.next_seat).is_equal(1)
	assert_int(ScoreWalk.next_card(state)).is_equal(-1)
	var recorder: Recorder = Recorder.new()
	assert_bool(ScoreWalk.step(state, _defs(), null, recorder.record)).is_false()
	assert_bool(state.walk.active).is_false()
	assert_array(recorder.events).is_empty()
	assert_array(state.scores).is_equal(_typed([0, 0]))


# --- R13: reveal before score ---------------------------------------------------------


func test_an_unrevealed_card_is_revealed_then_scored_and_a_revealed_one_only_scored() -> void:
	var row: Array[int] = _vanilla_cards(0, 2)
	var none: Array[int] = []
	var state: MatchState = _state(row, none, 0)
	state.seats[0].revealed[row[0]] = true
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var kinds: Array[int] = []
	for event: MatchEvent in recorder.events:
		kinds.append(event.kind)
	var expected_kinds: Array[int] = [
		MatchEvent.Kind.CARD_SCORED, MatchEvent.Kind.CARD_REVEALED, MatchEvent.Kind.CARD_SCORED
	]
	assert_array(kinds).is_equal(expected_kinds)
	var reveal: MatchEvent = recorder.events[1]
	var def: CardDef = _db().card_at(row[1] % MatchRules.DECK_SIZE)
	assert_int(_payload_int(reveal, "seat")).is_equal(0)
	assert_int(_payload_int(reveal, "card")).is_equal(row[1])
	var def_id: String = reveal.payload["def_id"]
	assert_str(def_id).is_equal(def.id)
	assert_int(_payload_int(reveal, "slot")).is_equal(1)
	assert_int(_payload_int(reveal, "flat")).is_equal(def.flat)
	assert_int(_payload_int(reveal, "times")).is_equal(_times_of(def))
	assert_int(_payload_int(reveal, "plus")).is_equal(_plus_of(def))
	assert_int(_payload_int(reveal, "order")).is_equal(0)
	# DC-09 T06 review (cycle 8 R7, R25): the effective cost and the grown mark, public.
	assert_int(_payload_int(reveal, "cost")).is_equal(def.cost)
	assert_bool(reveal.payload["grown"]).is_false()
	assert_bool(state.seats[0].is_revealed(row[1])).is_true()


# --- C3: recomputed every turn --------------------------------------------------------


## Two turns in a real match, each seat playing one card per turn: the second turn's
## scores are the walk over both cards (not the first total plus the new card), the old
## cards are pulsed again without a second reveal, and every new card reveals once.
func test_the_score_is_recomputed_across_two_turns() -> void:
	var checked: bool = false
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
		engine.start()
		_pass_until_turn(engine, 3)
		var first_turn: ApplyResult = _both_play_one(engine)
		if first_turn == null:
			continue
		var old_rows: Array[Array] = [_board(engine, 0), _board(engine, 1)]
		var second_turn: ApplyResult = _both_play_one(engine)
		if second_turn == null:
			continue
		checked = true
		var events: Array[MatchEvent] = second_turn.events
		var ended: MatchEvent = _of_kind(events, MatchEvent.Kind.TURN_ENDED)[0]
		var scores: Array[int] = _payload_ints(ended, "scores")
		var walked_cards: Array[int] = []
		var new_cards: Array[int] = []
		for seat: int in range(2):
			var row: Array[int] = _board(engine, seat)
			assert_int(row.size()).is_equal(2)
			assert_int(scores[seat]).is_equal(_walk_score(row))
			walked_cards.append_array(row)
			for card: int in row:
				if not _typed(old_rows[seat]).has(card):
					new_cards.append(card)
		assert_int(_of_kind(events, MatchEvent.Kind.WALK_STARTED).size()).is_equal(1)
		var scored: Array[int] = _cards_of(events, MatchEvent.Kind.CARD_SCORED)
		assert_array(_sorted(scored)).is_equal(_sorted(walked_cards))
		var revealed: Array[int] = _cards_of(events, MatchEvent.Kind.CARD_REVEALED)
		assert_array(_sorted(revealed)).is_equal(_sorted(new_cards))
		break
	assert_bool(checked).override_failure_message("no seed gave two one-card turns").is_true()


func _board(engine: MatchEngine, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var boards: Array = state["board"]
	var raw: Array = boards[seat]
	return _typed(raw)


func _hand(engine: MatchEngine, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var hands: Array = state["hand"]
	var raw: Array = hands[seat]
	return _typed(raw)


func _pass_until_turn(engine: MatchEngine, turn: int) -> void:
	var none: Array[int] = []
	while engine.energy() < turn:
		if not engine.apply(EngineAction.commit(engine.awaited_seat(), none)).ok:
			return


## Each seat in turn commits its first legal single effect-free card; the second commit's
## result, or null when a seat has no such card (nothing is applied for that seat then,
## and the caller drops the engine).
func _both_play_one(engine: MatchEngine) -> ApplyResult:
	var result: ApplyResult = null
	for _commit: int in range(2):
		var seat: int = engine.awaited_seat()
		var card: int = _first_vanilla_affordable(_hand(engine, seat), engine.budget_for(seat))
		if card < 0:
			return null
		var cards: Array[int] = [card]
		result = engine.apply(EngineAction.commit(seat, cards))
		assert_bool(result.ok).is_true()
	return result


func _first_vanilla_affordable(hand: Array[int], budget: int) -> int:
	for card: int in hand:
		var def: CardDef = _db().card_at(card % MatchRules.DECK_SIZE)
		if def.effect == null and def.cost <= budget:
			return card
	return -1


# --- C2, R11: the multiplier resets per walk ------------------------------------------


func test_the_multiplier_resets_per_walk() -> void:
	var row: Array[int] = [_card_with(0, 3, 125), _card_with(0, 4, 100)]
	var other: Array[int] = [_card_with(1, 1, 125)]
	var state: MatchState = _state(row, other, 0)
	_walk(state, Recorder.new())
	var first_scores: Array[int] = []
	first_scores.assign(state.scores)
	assert_array(state.walk.mult).is_equal(_typed([125, 125]))
	# Each cursor passed its whole row; every card scored once (DC-06 P1, P3).
	var all_cards: Array[int] = []
	all_cards.append_array(row)
	all_cards.append_array(other)
	assert_array(state.walk.cursor).is_equal(_typed([2, 1]))
	assert_array(state.walk.scored_ids()).is_equal(_sorted(all_cards))
	var walk_dict: Dictionary = state.to_dict()["walk"]
	assert_array(_state_ints(walk_dict, "cursor")).is_equal(_typed([2, 1]))
	assert_array(_state_ints(walk_dict, "scored")).is_equal(_sorted(all_cards))
	assert_bool(walk_dict.has("pulsed")).is_false()
	ScoreWalk.begin(state)
	assert_array(state.walk.mult).is_equal(_typed([100, 100]))
	assert_array(state.scores).is_equal(_typed([0, 0]))
	assert_array(state.walk.cursor).is_equal(_typed([0, 0]))
	assert_array(state.walk.scored_ids()).is_empty()
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	# Same totals, not compounded by the first walk's multipliers.
	assert_array(state.scores).is_equal(first_scores)
	assert_array(state.scores).is_equal(_typed([_walk_score(row), _walk_score(other)]))
	var first_scored: MatchEvent = _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED)[0]
	assert_int(_payload_int(first_scored, "mult")).is_equal(125)
	# Every card was revealed by the first walk: the second reveals nothing.
	assert_array(_of_kind(recorder.events, MatchEvent.Kind.CARD_REVEALED)).is_empty()


# --- DC-06 R1-R11: the slot cursor ----------------------------------------------------


## The `again` flags of `events`' CARD_SCORED, in order.
func _again_flags(events: Array[MatchEvent]) -> Array[bool]:
	var out: Array[bool] = []
	for event: MatchEvent in _of_kind(events, MatchEvent.Kind.CARD_SCORED):
		var flag: bool = event.payload["again"]
		out.append(flag)
	return out


## Row edits made between steps (DC-06 R6, R7): the cursor follows slots, not cards. A
## scored card swapped ahead of the cursor scores again there (`again` true), a card
## swapped onto a passed slot is not reached, and a card taken off a row ahead of the
## cursor is simply absent.
func test_row_edits_between_steps_follow_the_slot_cursor() -> void:
	var own: Array[int] = _vanilla_cards(0, 4)
	var theirs: Array[int] = _vanilla_cards(1, 2)
	var state: MatchState = _state(own, theirs, 0)
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_vector(ScoreWalk.next_slot(state)).is_equal(Vector2i(0, 0))
	ScoreWalk.step(state, _defs(), null, recorder.record)
	assert_array(state.walk.cursor).is_equal(_typed([1, 0]))
	assert_vector(ScoreWalk.next_slot(state)).is_equal(Vector2i(1, 0))
	# Swap the scored slot-0 card with the slot-2 card: own[0] lands ahead of the cursor,
	# own[2] on the passed slot 0.
	var row: Array[int] = state.seats[0].board
	var held: int = row[0]
	row[0] = row[2]
	row[2] = held
	ScoreWalk.step(state, _defs(), null, recorder.record)
	ScoreWalk.step(state, _defs(), null, recorder.record)
	# Take seat 1's slot-1 card off its row before the cursor reaches it.
	var doomed: int = theirs[1]
	state.seats[1].board.erase(doomed)
	state.clear_card_state(doomed)
	# Swap own[1] (scored at slot 1) with own[3] (slot 3, ahead).
	var ahead: Array[int] = state.seats[0].board
	var b_at: int = ahead.find(own[1])
	var d_at: int = ahead.find(own[3])
	ahead[b_at] = own[3]
	ahead[d_at] = own[1]
	var guard: int = 0
	while state.walk.active and guard < 20:
		ScoreWalk.step(state, _defs(), null, recorder.record)
		guard += 1
	var scored: Array[int] = _cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)
	var expected: Array[int] = [own[0], theirs[0], own[1], own[0], own[1]]
	assert_array(scored).is_equal(expected)
	var want_again: Array[bool] = [false, false, false, true, true]
	assert_array(_again_flags(recorder.events)).is_equal(want_again)
	# own[2] and own[3] sat on passed slots and were never reached; nor was the taken card.
	for skipped: int in [own[2], own[3]]:
		assert_bool(scored.has(skipped)).is_false()
		assert_bool(state.seats[0].is_revealed(skipped)).is_false()
	assert_bool(scored.has(doomed)).is_false()
	assert_bool(state.seats[1].is_revealed(doomed)).is_false()
	assert_array(state.walk.cursor).is_equal(_typed([4, 1]))


## Seat 0 [a (revealed c04), c12, b (face-down c08)] against seat 1's two face-down vanilla
## cards, seat 0 first. The walk pulses a, seat 1's slot 0, then reveals c12, whose swap
## prompts over a (slot 0) and b (slot 2).
func _swap_state() -> MatchState:
	var row: Array[int] = [C04, C12_SWAP, C08]
	var state: MatchState = _state(row, _vanilla_cards(1, 2), 0)
	state.seats[0].revealed[C04] = true
	return state


## Walks `state` from begin() to its end with the default cards, answering every prompt
## with position `answer` of its zone. Returns the number of pulses: the steps that passed
## a slot (a resumed pulse and the walk's last, empty step are not pulses).
func _walk_answering(state: MatchState, answer: int, recorder: Recorder) -> int:
	ScoreWalk.begin(state)
	var pulses: int = 0
	var guard: int = 0
	while state.walk.active and guard < 100:
		guard += 1
		if state.walk.paused_card < 0 and ScoreWalk.next_slot(state).x >= 0:
			pulses += 1
		if ScoreWalk.step(state, _defs(), null, recorder.record):
			recorder.events.append_array(EffectResolver.answer(state, _defs(), answer))
	return pulses


## The CARD_SCORED events of `events` for `card`, in order.
func _scores_of(events: Array[MatchEvent], card: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in _of_kind(events, MatchEvent.Kind.CARD_SCORED):
		if _payload_int(event, "card") == card:
			out.append(event)
	return out


## R4: whatever c12 swaps with, a walk over rows of n and m slots pulses n + m times, and
## both cursors end at their row's size. Each answer scores five times: a twice and b, or
## b and c12 once each (C23).
func test_a_walk_pulses_each_slot_once() -> void:
	for answer: int in [0, 2]:
		var state: MatchState = _swap_state()
		var sizes: Array[int] = [state.seats[0].board.size(), state.seats[1].board.size()]
		var recorder: Recorder = Recorder.new()
		var pulses: int = _walk_answering(state, answer, recorder)
		var where: String = "answer %d" % answer
		assert_int(pulses).override_failure_message(where).is_equal(sizes[0] + sizes[1])
		assert_array(state.walk.cursor).override_failure_message(where).is_equal(sizes)
		var scored: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED)
		assert_int(scored.size()).override_failure_message(where).is_equal(5)
		assert_bool(state.walk.active).is_false()
	# Rows of 3 and 1 with no effect: 4 pulses.
	var plain: MatchState = _state(_vanilla_cards(0, 3), _vanilla_cards(1, 1), 1)
	assert_int(_walk_answering(plain, 0, Recorder.new())).is_equal(4)


## C23, C25 (R5, R7, R9, R11; spec scenario 1): c12 at slot 1 swaps with a, already scored
## at slot 0. a, now on the pulsed slot 1, scores again in this pulse (`again`); c12, on the
## passed slot 0, does not score this walk; the cursor pulses b at slot 2 next.
func test_a_swap_behind_scores_the_card_now_on_the_slot_again() -> void:
	var theirs: Array[int] = _vanilla_cards(1, 2)
	var state: MatchState = _swap_state()
	var recorder: Recorder = Recorder.new()
	_walk_answering(state, 0, recorder)
	assert_array(state.seats[0].board).is_equal(_typed([C12_SWAP, C04, C08]))
	var expected: Array[int] = [C04, theirs[0], C04, theirs[1], C08]
	assert_array(_cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)).is_equal(expected)
	var want_again: Array[bool] = [false, false, true, false, false]
	assert_array(_again_flags(recorder.events)).is_equal(want_again)
	var a_scores: Array[MatchEvent] = _scores_of(recorder.events, C04)
	assert_int(_payload_int(a_scores[0], "slot")).is_equal(0)
	assert_int(_payload_int(a_scores[1], "slot")).is_equal(1)
	assert_int(_payload_int(a_scores[1], "added")).is_equal(3)
	# c12 revealed and swapped, and never scored this walk.
	assert_array(_scores_of(recorder.events, C12_SWAP)).is_empty()
	assert_bool(state.walk.scored.has(C12_SWAP)).is_false()
	var revealed: Array[int] = _cards_of(recorder.events, MatchEvent.Kind.CARD_REVEALED)
	assert_array(revealed).is_equal(_typed([theirs[0], C12_SWAP, theirs[1], C08]))
	# c04 3 twice + c08 4.
	assert_int(state.scores[0]).is_equal(10)


## C23, C24 (R5, R6, R11; spec scenario 2): c12 at slot 1 swaps with b, face down at slot 2.
## b, now on the pulsed slot 1, reveals in full after the move and scores in this pulse; c12
## scores once, when the cursor reaches slot 2 (`again` false).
func test_a_swap_ahead_reveals_the_card_now_on_the_slot_and_scores_the_mover_later() -> void:
	var theirs: Array[int] = _vanilla_cards(1, 2)
	var state: MatchState = _swap_state()
	var recorder: Recorder = Recorder.new()
	_walk_answering(state, 2, recorder)
	assert_array(state.seats[0].board).is_equal(_typed([C04, C08, C12_SWAP]))
	var expected: Array[int] = [C04, theirs[0], C08, theirs[1], C12_SWAP]
	assert_array(_cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)).is_equal(expected)
	var want_again: Array[bool] = [false, false, false, false, false]
	assert_array(_again_flags(recorder.events)).is_equal(want_again)
	var b_scores: Array[MatchEvent] = _scores_of(recorder.events, C08)
	assert_int(_payload_int(b_scores[0], "slot")).is_equal(1)
	var c12_scores: Array[MatchEvent] = _scores_of(recorder.events, C12_SWAP)
	assert_int(c12_scores.size()).is_equal(1)
	assert_int(_payload_int(c12_scores[0], "slot")).is_equal(2)
	assert_int(_payload_int(c12_scores[0], "added")).is_equal(4)
	# b's reveal follows the move, at slot 1, and precedes its score; c12 reveals once.
	var revealed: Array[int] = _cards_of(recorder.events, MatchEvent.Kind.CARD_REVEALED)
	assert_array(revealed).is_equal(_typed([theirs[0], C12_SWAP, C08, theirs[1]]))
	var moved_at: int = -1
	var b_revealed_at: int = -1
	var b_scored_at: int = -1
	for i: int in range(recorder.events.size()):
		var event: MatchEvent = recorder.events[i]
		if event.kind == MatchEvent.Kind.CARD_MOVED:
			moved_at = i
		elif event.kind == MatchEvent.Kind.CARD_REVEALED:
			if _payload_int(event, "card") == C08:
				b_revealed_at = i
				assert_int(_payload_int(event, "slot")).is_equal(1)
		elif event.kind == MatchEvent.Kind.CARD_SCORED:
			if _payload_int(event, "card") == C08:
				b_scored_at = i
	assert_int(b_revealed_at).is_greater(moved_at)
	assert_int(b_scored_at).is_greater(b_revealed_at)
	# c04 3 + c08 4 + c12 4.
	assert_int(state.scores[0]).is_equal(11)
	assert_bool(state.walk.scored.has(C12_SWAP)).is_true()
	assert_bool(state.walk.scored.has(C08)).is_true()


## C5, R8: a face-down card moved behind the cursor (here by a row edit between steps:
## c12's swap now reveals the card it puts on the pulsed slot, C24) stays face down for the
## rest of the walk with no reveal event, and the next walk reveals it in slot order and
## scores it.
func test_a_face_down_card_swapped_behind_reveals_in_the_next_walk() -> void:
	var row: Array[int] = _vanilla_cards(0, 3)
	var none: Array[int] = []
	var state: MatchState = _state(row, none, 0)
	var first: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	ScoreWalk.step(state, _defs(), null, first.record)
	# row[0] scored at slot 0; it swaps with row[2], face down at slot 2.
	state.seats[0].board.assign([row[2], row[1], row[0]])
	var guard: int = 0
	while state.walk.active and guard < 10:
		ScoreWalk.step(state, _defs(), null, first.record)
		guard += 1
	assert_bool(_cards_of(first.events, MatchEvent.Kind.CARD_REVEALED).has(row[2])).is_false()
	assert_bool(state.seats[0].is_revealed(row[2])).is_false()
	var first_scored: Array[int] = _cards_of(first.events, MatchEvent.Kind.CARD_SCORED)
	assert_array(first_scored).is_equal(_typed([row[0], row[1], row[0]]))
	var second: Recorder = Recorder.new()
	_walk(state, second)
	# The others are face up now: row[2] reveals once, at slot 0, and scores.
	var revealed: Array[MatchEvent] = _of_kind(second.events, MatchEvent.Kind.CARD_REVEALED)
	assert_int(revealed.size()).is_equal(1)
	assert_int(_payload_int(revealed[0], "card")).is_equal(row[2])
	assert_int(_payload_int(revealed[0], "slot")).is_equal(0)
	var second_scored: Array[int] = _cards_of(second.events, MatchEvent.Kind.CARD_SCORED)
	assert_array(second_scored).is_equal(_typed([row[2], row[1], row[0]]))
	assert_bool(state.seats[0].is_revealed(row[2])).is_true()


## C4, R9: c06 (on-score flat-up, printed flat 1) scored at slot 0, then moved ahead of the
## cursor by a scripted swap: its second pulse scores the flat it gained (base + 1) and
## fires its on-score effect again, leaving it at base + 2.
func test_an_on_score_card_scored_twice_gains_twice() -> void:
	var card: int = C06_FLAT_UP
	var other: int = _vanilla_cards(0, 1)[0]
	var none: Array[int] = []
	var state: MatchState = _state(_typed([card, other]), none, 0)
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	ScoreWalk.step(state, _defs(), null, recorder.record)
	# Swap c06 (slot 0, passed) with the card at slot 1 (ahead).
	state.seats[0].board.assign([other, card])
	var guard: int = 0
	while state.walk.active and guard < 10:
		ScoreWalk.step(state, _defs(), null, recorder.record)
		guard += 1
	assert_array(_cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)).is_equal(
		_typed([card, card])
	)
	var scores: Array[MatchEvent] = _scores_of(recorder.events, card)
	assert_int(_payload_int(scores[0], "flat")).is_equal(1)
	assert_int(_payload_int(scores[1], "flat")).is_equal(2)
	var want_again: Array[bool] = [false, true]
	assert_array(_again_flags(recorder.events)).is_equal(want_again)
	assert_int(_of_kind(recorder.events, MatchEvent.Kind.STATS_CHANGED).size()).is_equal(2)
	assert_int(state.card_state(card).flat_delta).is_equal(2)
	assert_dict(_eff(card, state)).is_equal(_stats(3, 100, 0))


# --- P4: effective stats from CardState -----------------------------------------------


## DC-07 P5: the base (printed, or `base_*` once a copy stored one, both bonus parts at once
## since C22), then `flat_delta` and `temp_plus`, then `no_bonus` clearing both bonus parts.
## The switch retired (C20).
func test_effective_reads_the_base_then_flat_delta_temp_plus_and_no_bonus() -> void:
	var card: int = _card_with(0, 3, 125)
	var none: Array[int] = []
	var state: MatchState = _state(_typed([card]), none, 0)
	assert_object(state.card_state(card)).is_null()
	assert_dict(_eff(card, state)).is_equal(_stats(3, 125, 0))
	var held: CardState = state.card_state_for(card)
	assert_bool(held.is_default()).is_true()
	# A stored base (a copy, DC-07 T07) replaces the printed stats, both bonus parts
	# included (R34, C22): ×1.50 and +2 at once, then a +-part only.
	held.has_base = true
	held.base_flat = 1
	held.base_times = 150
	held.base_plus = 2
	assert_bool(held.is_default()).is_false()
	assert_dict(_eff(card, state)).is_equal(_stats(1, 150, 2))
	held.base_times = MatchRules.MULT_ONE
	assert_dict(_eff(card, state)).is_equal(_stats(1, 100, 2))
	held.flat_delta = 2
	assert_dict(_eff(card, state)).is_equal(_stats(3, 100, 2))
	held.temp_plus = 1
	assert_dict(_eff(card, state)).is_equal(_stats(3, 100, 3))
	held.no_bonus = true
	assert_dict(_eff(card, state)).is_equal(_stats(3, 100, 0))
	held.return_marked = true
	assert_dict(_eff(card, state)).is_equal(_stats(3, 100, 0))
	# A copy carries every field.
	var copy: MatchState = state.duplicate()
	assert_dict(copy.to_dict()).is_equal(state.to_dict())
	assert_dict(_eff(card, copy)).is_equal(_stats(3, 100, 0))
	assert_bool(state.clear_card_state(card)).is_true()
	assert_dict(_eff(card, state)).is_equal(_stats(3, 125, 0))


## A card with no definition shows flat 0 and no bonus.
func test_effective_of_an_unknown_card_is_flat_0_and_no_bonus() -> void:
	var none: Array[int] = []
	var state: MatchState = _state(none, none, 0)
	assert_dict(_eff(-1, state)).is_equal(_stats(0, 100, 0))
	assert_dict(_eff(999, state)).is_equal(_stats(0, 100, 0))


func test_the_walk_scores_effective_stats() -> void:
	var bonus_card: int = _card_with(0, 3, 125)
	var flat_card: int = _card_with(0, 4, 100)
	var none: Array[int] = []
	var state: MatchState = _state(_typed([bonus_card, flat_card]), none, 0)
	# A stored base of (1, +2): mult 100 + 200 = 300, then 1 * 3; the flat card +1: 5 * 3.
	# Total 3 + 15 = 18.
	var held: CardState = state.card_state_for(bonus_card)
	held.has_base = true
	held.base_flat = 1
	held.base_times = MatchRules.MULT_ONE
	held.base_plus = 2
	state.card_state_for(flat_card).flat_delta = 1
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_array(state.scores).is_equal(_typed([18, 0]))
	assert_array(state.walk.mult).is_equal(_typed([300, 100]))
	var reveals: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_REVEALED)
	assert_int(_payload_int(reveals[0], "flat")).is_equal(1)
	assert_int(_payload_int(reveals[0], "times")).is_equal(100)
	assert_int(_payload_int(reveals[0], "plus")).is_equal(2)
	# No bonus on the bonus card: 3 then 4, the multiplier stays ×1.00.
	var plain: MatchState = _state(_typed([bonus_card, flat_card]), none, 0)
	plain.card_state_for(bonus_card).no_bonus = true
	_walk(plain, Recorder.new())
	assert_array(plain.scores).is_equal(_typed([7, 0]))
	assert_array(plain.walk.mult).is_equal(_typed([100, 100]))


func test_card_states_are_in_the_full_state_and_cleared_at_round_start() -> void:
	var card: int = _card_with(0, 3, 125)
	var none: Array[int] = []
	var state: MatchState = _state(_typed([card]), none, 0)
	state.card_state_for(card).flat_delta = 2
	var plain: Dictionary = state.to_dict()
	var states: Dictionary = plain["card_states"]
	assert_bool(states.has(card)).is_true()
	var entry: Dictionary = states[card]
	var expected: Dictionary = {
		"has_base": false,
		"base_flat": 0,
		"base_times": MatchRules.MULT_ONE,
		"base_plus": 0,
		"flat_delta": 2,
		"no_bonus": false,
		"temp_plus": 0,
		"return_marked": false,
		"destroyed": false,
		"salvaged": false,  # DC-11 T10.
	}
	assert_dict(entry).is_equal(expected)
	assert_bool(plain.has("walk")).is_true()
	# A modifier is written into the engine's state directly (both seats only pass here);
	# the next round start clears it.
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	engine.start()
	engine._state.card_state_for(card).no_bonus = true
	var marked: Dictionary = engine.full_state()
	var marked_states: Dictionary = marked["card_states"]
	assert_int(marked_states.size()).is_equal(1)
	_pass_until_round(engine, 2)
	var started: Dictionary = engine.full_state()
	assert_int(_state_int(started, "round")).is_equal(2)
	var engine_states: Dictionary = started["card_states"]
	assert_dict(engine_states).is_empty()


func _pass_until_round(engine: MatchEngine, round_number: int) -> void:
	var none: Array[int] = []
	var guard: int = 0
	while engine.view_for(0).round_number < round_number and guard < 100:
		if not engine.apply(EngineAction.commit(engine.awaited_seat(), none)).ok:
			return
		guard += 1


func _state_int(state: Dictionary, key: String) -> int:
	var value: int = state[key]
	return value


# --- The live walk in MatchEngine (moved from test_turn.gd) ---------------------------


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	engine.start()
	return engine


## The first legal set of exactly `size` effect-free cards, or an empty list when none
## exists. Effect-free since DC-05 T04: an effect (a destroy, a bonus-0 mark, a flat-up)
## would change the reveals and scores these cases predict from the definitions.
func _find_set(hand: Array[int], energy: int, size: int) -> Array[int]:
	for s: Array in LegalPlays.enumerate(hand, energy, _defs()):
		if s.size() == size and _all_vanilla(_typed(s)):
			return _typed(s)
	var none: Array[int] = []
	return none


func _all_vanilla(cards: Array[int]) -> bool:
	for card: int in cards:
		if _db().card_at(card % MatchRules.DECK_SIZE).effect != null:
			return false
	return true


func _flat(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).flat


func _times(card: int) -> int:
	return _times_of(_db().card_at(card % MatchRules.DECK_SIZE))


func _plus(card: int) -> int:
	return _plus_of(_db().card_at(card % MatchRules.DECK_SIZE))


func _pending(engine: MatchEngine) -> Array[int]:
	return _state_ints(engine.full_state(), "pending")


func _scores(engine: MatchEngine) -> Array[int]:
	return _state_ints(engine.full_state(), "scores")


## A seed whose turn-7 hands let the first committer play `first_size` cards and the
## second `second_size`, after both pass turns 1-6; -1 when none in the search range.
func _seed_with_sets(first_size: int, second_size: int) -> int:
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _started(match_seed)
		_pass_until_turn(engine, MatchRules.TURNS)
		var first: int = engine.awaited_seat()
		var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), first_size)
		var b: Array[int] = _find_set(_hand(engine, 1 - first), engine.energy(), second_size)
		if not a.is_empty() and not b.is_empty():
			return match_seed
	return -1


func test_reveal_three_against_one() -> void:
	var match_seed: int = _seed_with_sets(3, 1)
	assert_int(match_seed).is_greater(0)
	if match_seed < 0:
		return
	var engine: MatchEngine = _started(match_seed)
	_pass_until_turn(engine, MatchRules.TURNS)
	var first: int = engine.awaited_seat()
	var second: int = 1 - first
	var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), 3)
	var b: Array[int] = _find_set(_hand(engine, second), engine.energy(), 1)
	# Commit out of hand order with no slots: the append default places the cards in the
	# order given, and the walk follows the row (R5, R12).
	a.reverse()
	engine.apply(EngineAction.commit(first, a))
	var result: ApplyResult = engine.apply(EngineAction.commit(second, b))
	assert_bool(result.ok).is_true()
	var started: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.WALK_STARTED)
	assert_int(started.size()).is_equal(1)
	assert_int(_payload_int(started[0], "round")).is_equal(1)
	assert_int(_payload_int(started[0], "turn")).is_equal(MatchRules.TURNS)
	assert_int(_payload_int(started[0], "first_seat")).is_equal(first)
	var reveals: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.CARD_REVEALED)
	var expected_cards: Array[int] = [a[0], b[0], a[1], a[2]]
	var expected_seats: Array[int] = [first, second, first, first]
	# Rows were empty (every earlier turn passed) and turn 7 ends the round, clearing them,
	# so the slots are the append positions rather than a look-up after the fact.
	var expected_slots: Array[int] = [0, 0, 1, 2]
	assert_int(reveals.size()).is_equal(4)
	for i: int in range(reveals.size()):
		assert_int(_payload_int(reveals[i], "card")).is_equal(expected_cards[i])
		assert_int(_payload_int(reveals[i], "seat")).is_equal(expected_seats[i])
		assert_int(_payload_int(reveals[i], "order")).is_equal(i)
		assert_int(_payload_int(reveals[i], "flat")).is_equal(_flat(expected_cards[i]))
		assert_int(_payload_int(reveals[i], "times")).is_equal(_times(expected_cards[i]))
		assert_int(_payload_int(reveals[i], "plus")).is_equal(_plus(expected_cards[i]))
		assert_int(_payload_int(reveals[i], "slot")).is_equal(expected_slots[i])
		assert_int(reveals[i].owner_seat).is_equal(MatchEvent.PUBLIC)
	# Each reveal is followed by its card's score, in the same order.
	var scored: Array[int] = _cards_of(result.events, MatchEvent.Kind.CARD_SCORED)
	assert_array(scored).is_equal(expected_cards)
	# Scoring: each side's walk total (P4); the higher board wins the turn (R17).
	var expected_scores: Array[int] = [0, 0]
	expected_scores[first] = _walk_score(a)
	expected_scores[second] = _walk_score(b)
	var ended: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.TURN_ENDED)
	assert_int(ended.size()).is_equal(1)
	assert_array(_payload_ints(ended[0], "scores")).is_equal(expected_scores)
	var expected_winner: int = -1
	if expected_scores[0] > expected_scores[1]:
		expected_winner = 0
	elif expected_scores[1] > expected_scores[0]:
		expected_winner = 1
	assert_int(_payload_int(ended[0], "winner")).is_equal(expected_winner)


func test_reveal_one_against_three() -> void:
	var match_seed: int = _seed_with_sets(1, 3)
	assert_int(match_seed).is_greater(0)
	if match_seed < 0:
		return
	var engine: MatchEngine = _started(match_seed)
	_pass_until_turn(engine, MatchRules.TURNS)
	var first: int = engine.awaited_seat()
	var second: int = 1 - first
	var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), 1)
	var b: Array[int] = _find_set(_hand(engine, second), engine.energy(), 3)
	engine.apply(EngineAction.commit(first, a))
	var result: ApplyResult = engine.apply(EngineAction.commit(second, b))
	var reveals: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.CARD_REVEALED)
	var expected_cards: Array[int] = [a[0], b[0], b[1], b[2]]
	var expected_seats: Array[int] = [first, second, second, second]
	assert_int(reveals.size()).is_equal(4)
	for i: int in range(reveals.size()):
		assert_int(_payload_int(reveals[i], "card")).is_equal(expected_cards[i])
		assert_int(_payload_int(reveals[i], "seat")).is_equal(expected_seats[i])


func test_reveal_puts_cards_on_boards_and_scores_in_state() -> void:
	# The first seed whose turn-4 hands both hold an affordable effect-free card (DC-05 T04).
	var engine: MatchEngine = null
	for match_seed: int in range(SEED, SEED + SEARCH_SEEDS):
		var candidate: MatchEngine = _started(match_seed)
		_pass_until_turn(candidate, 4)
		var awaited: int = candidate.awaited_seat()
		var mine: Array[int] = _find_set(_hand(candidate, awaited), candidate.energy(), 1)
		var theirs: Array[int] = _find_set(_hand(candidate, 1 - awaited), candidate.energy(), 1)
		if not mine.is_empty() and not theirs.is_empty():
			engine = candidate
			break
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var first: int = engine.awaited_seat()
	var second: int = 1 - first
	var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), 1)
	var b: Array[int] = _find_set(_hand(engine, second), engine.energy(), 1)
	engine.apply(EngineAction.commit(first, a))
	engine.apply(EngineAction.commit(second, b))
	assert_array(_board(engine, first)).is_equal(a)
	assert_array(_board(engine, second)).is_equal(b)
	assert_array(_pending(engine)).is_empty()
	var scores: Array[int] = _scores(engine)
	assert_int(scores[first]).is_equal(_walk_score(a))
	assert_int(scores[second]).is_equal(_walk_score(b))
	# The walk is over and both rows are revealed; each view shows the shown stats.
	var state: Dictionary = engine.full_state()
	var walk: Dictionary = state["walk"]
	var active: bool = walk["active"]
	assert_bool(active).is_false()
	for seat: int in range(2):
		var view: SeatView = engine.view_for(seat)
		var row: Array[int] = _board(engine, seat)
		assert_int(view.own_row.size()).is_equal(row.size())
		var entry: Dictionary = view.own_row[0]
		var card: int = entry["card"]
		var flat: int = entry["flat"]
		var times: int = entry["times"]
		var plus: int = entry["plus"]
		var revealed: bool = entry["revealed"]
		assert_int(card).is_equal(row[0])
		assert_int(flat).is_equal(_flat(row[0]))
		assert_int(times).is_equal(_times(row[0]))
		assert_int(plus).is_equal(_plus(row[0]))
		assert_bool(revealed).is_true()
		assert_int(view.opponent_row.size()).is_equal(_board(engine, 1 - seat).size())
		# One card per row: each multiplier ends at ×1.00 times that card's ×-part, plus
		# its +-part (hundredths).
		var mults: Array[int] = [100, 100]
		mults[first] = _times(a[0]) + _plus(a[0]) * 100
		mults[second] = _times(b[0]) + _plus(b[0]) * 100
		assert_array(view.mults).is_equal(mults)


# --- P12: a walk on a copy equals the live walk ---------------------------------------


## A seed-1 bot match: after every turn that does not end a round, a walk run to the end
## on a MatchState.duplicate() of the engine's state (no sink and no stream) gives the live
## TURN_ENDED scores and leaves the engine alone.
## Turns whose walk changed a scored card after it scored (a flat-up, a destroy) are
## skipped (DC-05 T04): re-walking the turn's end state is then a different walk. So are
## turns with a choice (DC-05 T05): a swap reorders the row, a return takes a scored card
## off the row at turn end. A turn's events are
## gathered across every action of its walk, since a prompt splits the walk over two or
## more applies; every such live walk is also checked for its `again` flags and for no
## unmoved card left unscored (DC-06 R4, P3).
func test_a_walk_on_a_copy_gives_the_live_scores() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_bool(engine.start().ok).is_true()
	var bots: Array[RandomBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(RandomBot.new(BotRegistry.seed_for(SEED, seat), _defs()))
	var compared: int = 0
	var actions: int = 0
	var turn_events: Array[MatchEvent] = []
	while not engine.is_over() and actions < MAX_ACTIONS:
		var awaited: int = engine.awaited_seat()
		var action: EngineAction = bots[awaited].choose(engine.view_for(awaited), engine)
		var result: ApplyResult = engine.apply(action)
		assert_bool(result.ok).is_true()
		actions += 1
		turn_events.append_array(result.events)
		var ended: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.TURN_ENDED)
		if ended.is_empty():
			continue
		var walk_events: Array[MatchEvent] = _this_walk(turn_events)
		turn_events.clear()
		var scored: Dictionary = _assert_again_flags(walk_events)
		if not _of_kind(result.events, MatchEvent.Kind.ROUND_STARTED).is_empty():
			continue
		if engine.is_over():
			continue
		_assert_no_card_skipped(engine, walk_events, scored)
		if _changed_the_walk(walk_events):
			continue
		var live: Dictionary = engine.full_state()
		var copy: MatchState = engine._state.duplicate()
		assert_dict(copy.to_dict()).is_equal(live)
		ScoreWalk.begin(copy)
		var paused: bool = ScoreWalk.run(copy, _defs(), null, Callable())
		assert_bool(paused).is_false()
		assert_array(copy.scores).is_equal(_payload_ints(ended[0], "scores"))
		assert_array(copy.scores).is_equal(_state_ints(live, "scores"))
		assert_dict(engine.full_state()).is_equal(live)
		compared += 1
	assert_bool(engine.is_over()).is_true()
	assert_int(compared).is_greater(0)


## The events from the last WALK_STARTED up to and including the first TURN_ENDED after
## it: one turn's walk and turn end, however many applies it took.
func _this_walk(events: Array[MatchEvent]) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == MatchEvent.Kind.WALK_STARTED:
			out.clear()
		out.append(event)
		if event.kind == MatchEvent.Kind.TURN_ENDED:
			break
	return out


## DC-06 P3 on the live walk, prompts included: a card scores twice in one walk only when
## a swap moved it ahead of the cursor or onto the slot being pulsed (C25), and every
## CARD_SCORED's `again` says whether the card had already scored in this walk. A card no
## CARD_MOVED names scores at most once.
## Returns the scored cards as a set.
func _assert_again_flags(walk_events: Array[MatchEvent]) -> Dictionary:
	var moved: Array[int] = _cards_of(walk_events, MatchEvent.Kind.CARD_MOVED)
	var seen: Dictionary = {}
	for event: MatchEvent in _of_kind(walk_events, MatchEvent.Kind.CARD_SCORED):
		var card: int = _payload_int(event, "card")
		var again: bool = event.payload["again"]
		var message: String = "card %d again=%s" % [card, again]
		assert_bool(again).override_failure_message(message).is_equal(seen.has(card))
		if again:
			assert_bool(moved.has(card)).override_failure_message(message).is_true()
		seen[card] = true
	return seen


## No pulse lost (R4): every card still on a row after the turn, and every card a return
## took off at turn end, was scored in the walk, except a card a swap moved (it may have
## landed on a slot the cursor had passed, DC-06 R7, R11).
func _assert_no_card_skipped(
	engine: MatchEngine, walk_events: Array[MatchEvent], seen: Dictionary
) -> void:
	var moved: Array[int] = _cards_of(walk_events, MatchEvent.Kind.CARD_MOVED)
	var expected: Array[int] = []
	for seat: int in range(MatchEngine.SEATS):
		expected.append_array(_board(engine, seat))
	expected.append_array(_cards_of(walk_events, MatchEvent.Kind.CARD_RETURNED))
	for event: MatchEvent in _of_kind(walk_events, MatchEvent.Kind.CARD_BURNED):
		if not event.is_private():
			expected.append(_payload_int(event, "card"))
	for card: int in expected:
		if moved.has(card):
			continue
		assert_bool(seen.has(card)).override_failure_message("card %d not scored" % card).is_true()


## Whether a turn's events hold a flat-up, a destroy or a choice (DC-05 T05), after which
## the turn's end state no longer walks to the turn's scores.
func _changed_the_walk(events: Array[MatchEvent]) -> bool:
	if not _of_kind(events, MatchEvent.Kind.CARD_DESTROYED).is_empty():
		return true
	if not _of_kind(events, MatchEvent.Kind.CHOICE_MADE).is_empty():
		return true
	for event: MatchEvent in _of_kind(events, MatchEvent.Kind.STATS_CHANGED):
		var cause: String = event.payload["cause"]
		if cause == EffectResolver.CAUSE_FLAT_UP:
			return true
	return false


func test_duplicate_is_deep() -> void:
	var row: Array[int] = _vanilla_cards(0, 2)
	var other: Array[int] = _vanilla_cards(1, 1)
	var state: MatchState = _state(row, other, 1)
	state.seats[0].hand.append(row[0] + 5)
	state.card_state_for(row[0]).flat_delta = 1
	state.energy.carry[1] = 2
	state.result = {"winner": 0}
	_walk(state, Recorder.new())
	var before: Dictionary = state.to_dict()
	var copy: MatchState = state.duplicate()
	assert_dict(copy.to_dict()).is_equal(before)
	copy.seats[0].board.clear()
	copy.seats[0].hand.clear()
	copy.seats[0].revealed.clear()
	copy.card_state_for(row[0]).flat_delta = 9
	copy.energy.carry[1] = 0
	copy.walk.mult[0] = 7
	copy.walk.cursor[0] = 9
	copy.walk.scored.clear()
	copy.scores[0] = 99
	copy.result["winner"] = 1
	assert_dict(state.to_dict()).is_equal(before)


## Records what a walk sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	## The walk sends effect events with their owner (DC-05 T04), its own without.
	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
