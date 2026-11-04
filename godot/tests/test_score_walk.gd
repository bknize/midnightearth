class_name TestScoreWalk
extends GdUnitTestSuite
## ScoreWalk (R11-R18, plan P3-P5) and CardState: the walk's math (C2), its cursor (C4),
## recomputation every turn (C3), the per-walk multiplier, pulse-once under row edits
## (R16), effective stats from CardState, and a walk on a MatchState.duplicate() giving
## the live engine's scores (the preview's basis, P12).
##
## Most states are built directly: rows of vanilla cards from the default card list, so no
## effect fires once T04 and T05 add them. Card instance ids are seat * DECK_SIZE + index.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
const MAX_ACTIONS: int = 2000

var _cached_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


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


## `seat`'s instance of the first effect-free card with this flat and bonus; -1 if none.
func _card_with(seat: int, flat: int, bonus: int) -> int:
	for index: int in _vanilla():
		var def: CardDef = _db().card_at(index)
		if def.flat == flat and def.bonus == bonus:
			return seat * MatchRules.DECK_SIZE + index
	return -1


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


## The P4 math on one row, from the definitions alone (no CardState): the multiplier
## starts at 1 and gains each card's bonus before that card's flat is multiplied in.
func _walk_score(row: Array[int]) -> int:
	var mult: int = 1
	var total: int = 0
	for card: int in row:
		var def: CardDef = _db().card_at(card % MatchRules.DECK_SIZE)
		mult += def.bonus
		total += def.flat * mult
	return total


## Runs the walk on `state` from begin() to its end, recording the events.
func _walk(state: MatchState, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < 100:
		var paused: bool = ScoreWalk.step(state, _db(), null, recorder.record, null)
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


## Spec scenario: [flat 3, bonus 1] then [flat 4, bonus 0] scores 14; reversed, 10.
func test_bonus_card_left_of_the_flat_card_scores_14_and_reversed_10() -> void:
	var bonus_card: int = _card_with(0, 3, 1)
	var flat_card: int = _card_with(0, 4, 0)
	assert_int(bonus_card).is_greater_equal(0)
	assert_int(flat_card).is_greater_equal(0)
	var none: Array[int] = []
	var left: MatchState = _state(_typed([bonus_card, flat_card]), none, 0)
	var recorder: Recorder = Recorder.new()
	_walk(left, recorder)
	assert_array(left.scores).is_equal(_typed([14, 0]))
	assert_bool(left.walk.active).is_false()
	# Each CARD_SCORED carries the amounts and the running score (R14).
	var scored: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED)
	assert_int(scored.size()).is_equal(2)
	var expected: Array[Array] = [[bonus_card, 0, 3, 1, 2, 6, 6], [flat_card, 1, 4, 0, 2, 8, 14]]
	for i: int in range(2):
		var row: Array = expected[i]
		var want: Array[int] = _typed(row)
		assert_int(_payload_int(scored[i], "seat")).is_equal(0)
		assert_int(_payload_int(scored[i], "card")).is_equal(want[0])
		assert_int(_payload_int(scored[i], "slot")).is_equal(want[1])
		assert_int(_payload_int(scored[i], "flat")).is_equal(want[2])
		assert_int(_payload_int(scored[i], "bonus")).is_equal(want[3])
		assert_int(_payload_int(scored[i], "mult")).is_equal(want[4])
		assert_int(_payload_int(scored[i], "added")).is_equal(want[5])
		assert_int(_payload_int(scored[i], "score")).is_equal(want[6])
		assert_int(scored[i].owner_seat).is_equal(MatchEvent.PUBLIC)
	var right: MatchState = _state(_typed([flat_card, bonus_card]), none, 0)
	_walk(right, Recorder.new())
	assert_array(right.scores).is_equal(_typed([10, 0]))


func test_each_seat_has_its_own_multiplier() -> void:
	var bonus_card: int = _card_with(0, 3, 1)
	var flat_card: int = _card_with(1, 4, 0)
	# Seat 0's bonus must not multiply seat 1's card, even though seat 1 pulses after it.
	var state: MatchState = _state(_typed([bonus_card]), _typed([flat_card]), 0)
	_walk(state, Recorder.new())
	assert_array(state.scores).is_equal(_typed([6, 4]))
	assert_array(state.walk.mult).is_equal(_typed([2, 1]))


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
			ScoreWalk.step(state, _db(), null, recorder.record, null)
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
	assert_bool(ScoreWalk.step(state, _db(), null, recorder.record, null)).is_false()
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
	assert_int(_payload_int(reveal, "bonus")).is_equal(def.bonus)
	assert_int(_payload_int(reveal, "order")).is_equal(0)
	assert_bool(state.seats[0].is_revealed(row[1])).is_true()


# --- C3: recomputed every turn --------------------------------------------------------


## Two turns in a real match, each seat playing one card per turn: the second turn's
## scores are the walk over both cards (not the first total plus the new card), the old
## cards are pulsed again without a second reveal, and every new card reveals once.
func test_the_score_is_recomputed_across_two_turns() -> void:
	var checked: bool = false
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = MatchEngine.create(match_seed, _db())
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
	var row: Array[int] = [_card_with(0, 3, 1), _card_with(0, 4, 0)]
	var other: Array[int] = [_card_with(1, 1, 1)]
	var state: MatchState = _state(row, other, 0)
	_walk(state, Recorder.new())
	var first_scores: Array[int] = []
	first_scores.assign(state.scores)
	assert_array(state.walk.mult).is_equal(_typed([2, 2]))
	ScoreWalk.begin(state)
	assert_array(state.walk.mult).is_equal(_typed([1, 1]))
	assert_array(state.scores).is_equal(_typed([0, 0]))
	assert_array(state.walk.pulsed_ids()).is_empty()
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	# Same totals, not compounded by the first walk's multipliers.
	assert_array(state.scores).is_equal(first_scores)
	assert_array(state.scores).is_equal(_typed([_walk_score(row), _walk_score(other)]))
	var first_scored: MatchEvent = _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED)[0]
	assert_int(_payload_int(first_scored, "mult")).is_equal(2)
	# Every card was revealed by the first walk: the second reveals nothing.
	assert_array(_of_kind(recorder.events, MatchEvent.Kind.CARD_REVEALED)).is_empty()


# --- R16: each card pulses once, whatever moves ---------------------------------------


## A swap that moves a pulsed card right past unpulsed ones and a destroy of an unpulsed
## card, both made between steps: the moved card is not pulsed again, the cards it jumped
## are, and the destroyed card never is.
func test_swap_and_destroy_mid_walk_never_pulse_a_card_twice() -> void:
	var own: Array[int] = _vanilla_cards(0, 4)
	var theirs: Array[int] = _vanilla_cards(1, 2)
	var state: MatchState = _state(own, theirs, 0)
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	ScoreWalk.step(state, _db(), null, recorder.record, null)
	# Swap the pulsed slot-0 card with the unpulsed slot-2 card (swap behind).
	var row: Array[int] = state.seats[0].board
	var held: int = row[0]
	row[0] = row[2]
	row[2] = held
	ScoreWalk.step(state, _db(), null, recorder.record, null)
	ScoreWalk.step(state, _db(), null, recorder.record, null)
	# Destroy seat 1's unpulsed card before its turn comes (destroy ahead).
	var doomed: int = theirs[1]
	state.seats[1].board.erase(doomed)
	state.clear_card_state(doomed)
	# Swap seat 0's two unpulsed cards (swap ahead): order follows the row as it is now.
	var ahead: Array[int] = state.seats[0].board
	var b_at: int = ahead.find(own[1])
	var d_at: int = ahead.find(own[3])
	ahead[b_at] = own[3]
	ahead[d_at] = own[1]
	var guard: int = 0
	while state.walk.active and guard < 20:
		ScoreWalk.step(state, _db(), null, recorder.record, null)
		guard += 1
	var pulsed: Array[int] = _cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)
	var expected: Array[int] = [own[0], theirs[0], own[2], own[3], own[1]]
	assert_array(pulsed).is_equal(expected)
	for card: int in pulsed:
		assert_int(pulsed.count(card)).is_equal(1)
	assert_bool(pulsed.has(doomed)).is_false()
	assert_array(state.walk.pulsed_ids()).is_equal(_sorted(expected))


# --- P4: effective stats from CardState -----------------------------------------------


func test_effective_applies_switch_then_flat_delta_then_bonus_zero() -> void:
	var card: int = _card_with(0, 3, 1)
	var none: Array[int] = []
	var state: MatchState = _state(_typed([card]), none, 0)
	assert_object(state.card_state(card)).is_null()
	assert_vector(ScoreWalk.effective(card, state, _db())).is_equal(Vector2i(3, 1))
	var held: CardState = state.card_state_for(card)
	assert_bool(held.is_default()).is_true()
	held.switched = true
	assert_vector(ScoreWalk.effective(card, state, _db())).is_equal(Vector2i(1, 3))
	held.flat_delta = 2
	assert_vector(ScoreWalk.effective(card, state, _db())).is_equal(Vector2i(3, 3))
	held.bonus_zero = true
	assert_vector(ScoreWalk.effective(card, state, _db())).is_equal(Vector2i(3, 0))
	held.switched = false
	assert_vector(ScoreWalk.effective(card, state, _db())).is_equal(Vector2i(5, 0))
	held.return_marked = true
	assert_vector(ScoreWalk.effective(card, state, _db())).is_equal(Vector2i(5, 0))
	assert_bool(held.is_default()).is_false()
	assert_bool(state.clear_card_state(card)).is_true()
	assert_vector(ScoreWalk.effective(card, state, _db())).is_equal(Vector2i(3, 1))


func test_the_walk_scores_effective_stats() -> void:
	var bonus_card: int = _card_with(0, 3, 1)
	var flat_card: int = _card_with(0, 4, 0)
	var none: Array[int] = []
	var state: MatchState = _state(_typed([bonus_card, flat_card]), none, 0)
	# Switched to (1, 3): mult 4, then 1 * 4; the flat card +1: 5 * 4. Total 24.
	state.card_state_for(bonus_card).switched = true
	state.card_state_for(flat_card).flat_delta = 1
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_array(state.scores).is_equal(_typed([24, 0]))
	var reveals: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_REVEALED)
	assert_int(_payload_int(reveals[0], "flat")).is_equal(1)
	assert_int(_payload_int(reveals[0], "bonus")).is_equal(3)
	# Bonus zero on the bonus card: (3, 0) then (4, 0), no multiplier.
	var plain: MatchState = _state(_typed([bonus_card, flat_card]), none, 0)
	plain.card_state_for(bonus_card).bonus_zero = true
	_walk(plain, Recorder.new())
	assert_array(plain.scores).is_equal(_typed([7, 0]))


func test_card_states_are_in_the_full_state_and_cleared_at_round_start() -> void:
	var card: int = _card_with(0, 3, 1)
	var none: Array[int] = []
	var state: MatchState = _state(_typed([card]), none, 0)
	state.card_state_for(card).flat_delta = 2
	var plain: Dictionary = state.to_dict()
	var states: Dictionary = plain["card_states"]
	assert_bool(states.has(card)).is_true()
	var entry: Dictionary = states[card]
	assert_dict(entry).is_equal(
		{"flat_delta": 2, "switched": false, "bonus_zero": false, "return_marked": false}
	)
	assert_bool(plain.has("walk")).is_true()
	# Nothing in the engine sets a modifier before DC-05 T04, so one is written into the
	# engine's state directly; the next round start clears it.
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	engine.start()
	engine._state.card_state_for(card).bonus_zero = true
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
	var engine: MatchEngine = MatchEngine.create(match_seed, _db())
	engine.start()
	return engine


## The first legal set of exactly `size` cards, or an empty list when none exists.
func _find_set(hand: Array[int], energy: int, size: int) -> Array[int]:
	for s: Array in LegalPlays.enumerate(hand, energy, _db()):
		if s.size() == size:
			return _typed(s)
	var none: Array[int] = []
	return none


func _flat(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).flat


func _bonus(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).bonus


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
		assert_int(_payload_int(reveals[i], "bonus")).is_equal(_bonus(expected_cards[i]))
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
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 4)
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
		var bonus: int = entry["bonus"]
		var revealed: bool = entry["revealed"]
		assert_int(card).is_equal(row[0])
		assert_int(flat).is_equal(_flat(row[0]))
		assert_int(bonus).is_equal(_bonus(row[0]))
		assert_bool(revealed).is_true()
		assert_int(view.opponent_row.size()).is_equal(_board(engine, 1 - seat).size())
		# One card per row: each multiplier ends at 1 plus that card's bonus.
		var mults: Array[int] = [1, 1]
		mults[first] += _bonus(a[0])
		mults[second] += _bonus(b[0])
		assert_array(view.mults).is_equal(mults)


# --- P12: a walk on a copy equals the live walk ---------------------------------------


## A seed-1 bot match: after every turn that does not end a round, a walk run to the end
## on a MatchState.duplicate() of the engine's state (with a PreviewPolicy, no sink and no
## stream) gives the live TURN_ENDED scores, emits nothing and leaves the engine alone.
func test_a_walk_on_a_copy_gives_the_live_scores() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	assert_bool(engine.start().ok).is_true()
	var bots: Array[GreedyBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(GreedyBot.new(GreedyBot.seed_for(SEED, seat), _db()))
	var compared: int = 0
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var awaited: int = engine.awaited_seat()
		var result: ApplyResult = engine.apply(bots[awaited].choose(engine.view_for(awaited)))
		assert_bool(result.ok).is_true()
		actions += 1
		var ended: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.TURN_ENDED)
		if ended.is_empty():
			continue
		if not _of_kind(result.events, MatchEvent.Kind.ROUND_STARTED).is_empty():
			continue
		if engine.is_over():
			continue
		var live: Dictionary = engine.full_state()
		var copy: MatchState = engine._state.duplicate()
		assert_dict(copy.to_dict()).is_equal(live)
		var recorder: Recorder = Recorder.new()
		ScoreWalk.begin(copy)
		var paused: bool = ScoreWalk.run(copy, _db(), null, recorder.record, PreviewPolicy.new())
		assert_bool(paused).is_false()
		assert_array(copy.scores).is_equal(_payload_ints(ended[0], "scores"))
		assert_array(copy.scores).is_equal(_state_ints(live, "scores"))
		assert_array(recorder.events).is_empty()
		assert_dict(engine.full_state()).is_equal(live)
		compared += 1
	assert_bool(engine.is_over()).is_true()
	assert_int(compared).is_greater(0)


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
	copy.walk.pulsed.clear()
	copy.scores[0] = 99
	copy.result["winner"] = 1
	assert_dict(state.to_dict()).is_equal(before)


## Records what a walk sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary) -> void:
		events.append(MatchEvent.new(kind, payload))
