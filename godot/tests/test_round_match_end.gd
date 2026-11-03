# gdlint: disable=max-public-methods
class_name TestRoundMatchEnd
extends GdUnitTestSuite
## MatchEngine round and match end: R18 (turn-1 order per C9, coin flip only before the
## first won round), R19 (round winner, ties award nothing), R20 (4 wins), R21 (end after
## round 7 or into sudden death), R22 (sudden-death chains), R23 (concede out of turn),
## R24 (round-end payload), R25 (match-end payload), and MATCH_OVER after the end.
##
## Round outcomes come from real actions: both seats pass turns 1-6, and on turn 7 the
## chosen winner commits one card (any card is affordable at 7 energy and has power >= 1)
## while the other passes. A round where everyone passes is a 0-0 tie.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
const TIE: int = -1

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


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = MatchEngine.create(match_seed, _db())
	engine.start()
	return engine


func _seat_list(engine: MatchEngine, key: String, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var per_seat: Array = state[key]
	var raw: Array = per_seat[seat]
	return _typed(raw)


func _hand(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "hand", seat)


func _board(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "board", seat)


func _state_ints(engine: MatchEngine, key: String) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state[key]
	return _typed(raw)


func _state_int(engine: MatchEngine, key: String) -> int:
	var state: Dictionary = engine.full_state()
	var value: int = state[key]
	return value


func _state_bool(engine: MatchEngine, key: String) -> bool:
	var state: Dictionary = engine.full_state()
	var value: bool = state[key]
	return value


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _payload_bool(event: MatchEvent, key: String) -> bool:
	var value: bool = event.payload[key]
	return value


func _payload_str(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


func _payload_ints(event: MatchEvent, key: String) -> Array[int]:
	var raw: Array = event.payload[key]
	return _typed(raw)


func _pass(engine: MatchEngine) -> ApplyResult:
	var none: Array[int] = []
	return engine.apply(EngineAction.commit(engine.awaited_seat(), none))


func _kinds(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		out.append(event.kind)
	return out


func _of_kind(events: Array[MatchEvent], kind: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == kind:
			out.append(event)
	return out


## The last event of a kind; fails the test (and returns a blank event) when none exists.
func _last(events: Array[MatchEvent], kind: int) -> MatchEvent:
	var found: Array[MatchEvent] = _of_kind(events, kind)
	if found.is_empty():
		fail("no event of kind %d" % kind)
		return MatchEvent.new()
	return found[found.size() - 1]


func _ids(seat: int) -> Array[int]:
	var out: Array[int] = []
	for index: int in range(MatchRules.DECK_SIZE):
		out.append(seat * MatchRules.DECK_SIZE + index)
	return out


## Plays one round to its end with real actions (see the suite comment); `winner` TIE
## makes every seat pass every turn. Returns every event of the round's 14 actions.
func _play_round(engine: MatchEngine, winner: int) -> Array[MatchEvent]:
	var seen: Array[MatchEvent] = []
	for _step: int in range(2 * MatchRules.TURNS):
		var seat: int = engine.awaited_seat()
		var cards: Array[int] = []
		if seat == winner and engine.energy() == MatchRules.TURNS:
			cards.append(_hand(engine, seat)[0])
		var result: ApplyResult = engine.apply(EngineAction.commit(seat, cards))
		if not result.ok:
			fail("round action rejected with code %d" % result.error)
			return seen
		seen.append_array(result.events)
	assert_int(_of_kind(seen, MatchEvent.Kind.ROUND_ENDED).size()).is_equal(1)
	var ended: MatchEvent = _last(seen, MatchEvent.Kind.ROUND_ENDED)
	assert_int(_payload_int(ended, "winner")).is_equal(winner)
	return seen


## Plays one round per outcome, in order; returns every event on the way.
func _play_rounds(engine: MatchEngine, outcomes: Array[int]) -> Array[MatchEvent]:
	var seen: Array[MatchEvent] = []
	for winner: int in outcomes:
		seen.append_array(_play_round(engine, winner))
	return seen


## A started match plus its start() events and the events of the given rounds.
func _match_events(engine: MatchEngine, outcomes: Array[int]) -> Array[MatchEvent]:
	var seen: Array[MatchEvent] = []
	seen.append_array(engine.start().events)
	seen.append_array(_play_rounds(engine, outcomes))
	return seen


## Checks the MATCH_ENDED payload, the full-state result and that the match is over.
func _assert_match_ended(
	engine: MatchEngine,
	events: Array[MatchEvent],
	winner: int,
	reason: String,
	wins: Array[int],
	rounds_played: int
) -> void:
	assert_int(_of_kind(events, MatchEvent.Kind.MATCH_ENDED).size()).is_equal(1)
	var ended: MatchEvent = _last(events, MatchEvent.Kind.MATCH_ENDED)
	assert_int(ended.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_int(_payload_int(ended, "winner")).is_equal(winner)
	assert_str(_payload_str(ended, "reason")).is_equal(reason)
	assert_array(_payload_ints(ended, "wins")).is_equal(wins)
	assert_int(_payload_int(ended, "rounds_played")).is_equal(rounds_played)
	# MATCH_ENDED is the last event of the match.
	assert_int(events[events.size() - 1].kind).is_equal(MatchEvent.Kind.MATCH_ENDED)
	assert_bool(engine.is_over()).is_true()
	assert_int(engine.awaited_seat()).is_equal(-1)
	assert_array(_state_ints(engine, "wins")).is_equal(wins)
	var state: Dictionary = engine.full_state()
	var expected_result: Dictionary = {
		"winner": winner, "reason": reason, "rounds_played": rounds_played
	}
	var result: Dictionary = state["result"]
	assert_dict(result).is_equal(expected_result)


## Every action fails with MATCH_OVER and changes nothing (R26 after the end).
func _assert_all_rejected_as_over(engine: MatchEngine) -> void:
	var none: Array[int] = []
	var actions: Array[EngineAction] = [
		EngineAction.commit(0, none),
		EngineAction.commit(1, none),
		EngineAction.concede(0),
		EngineAction.concede(1),
		null,
	]
	for action: EngineAction in actions:
		var before: Dictionary = engine.full_state()
		var count: int = engine.accepted_action_count()
		var result: ApplyResult = engine.apply(action)
		assert_bool(result.ok).is_false()
		assert_int(result.error).is_equal(EngineError.Code.MATCH_OVER)
		assert_array(result.events).is_empty()
		assert_dict(engine.full_state()).is_equal(before)
		assert_int(engine.accepted_action_count()).is_equal(count)


# --- R19, R24: round end ----------------------------------------------------------------


func test_won_round_payload_and_flow_into_the_next_round() -> void:
	var engine: MatchEngine = _started(SEED)
	var events: Array[MatchEvent] = _play_round(engine, 1)
	var reveals: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CARD_REVEALED)
	assert_int(reveals.size()).is_equal(1)
	var power: int = _payload_int(reveals[0], "power")
	assert_int(power).is_greater(0)
	var ended: MatchEvent = _last(events, MatchEvent.Kind.ROUND_ENDED)
	assert_int(ended.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_int(_payload_int(ended, "round")).is_equal(1)
	assert_array(_payload_ints(ended, "scores")).is_equal(_typed([0, power]))
	assert_int(_payload_int(ended, "winner")).is_equal(1)
	assert_array(_payload_ints(ended, "wins")).is_equal(_typed([0, 1]))
	assert_array(_state_ints(engine, "wins")).is_equal(_typed([0, 1]))
	assert_int(_state_int(engine, "last_round_winner")).is_equal(1)
	# Order: turn 7 ends, the round ends, then round 2 starts and runs to turn 1.
	var kinds: Array[int] = _kinds(events)
	var at: int = kinds.rfind(MatchEvent.Kind.ROUND_ENDED)
	assert_int(kinds[at - 1]).is_equal(MatchEvent.Kind.TURN_ENDED)
	var turn_ended: MatchEvent = events[at - 1]
	assert_int(_payload_int(turn_ended, "turn")).is_equal(MatchRules.TURNS)
	assert_array(_payload_ints(turn_ended, "scores")).is_equal(_typed([0, power]))
	var expected_tail: Array[int] = [MatchEvent.Kind.ROUND_STARTED]
	for _i: int in range(2 * MatchRules.OPENING_HAND):
		expected_tail.append(MatchEvent.Kind.CARD_DEALT)
	expected_tail.append(MatchEvent.Kind.TURN_STARTED)
	expected_tail.append(MatchEvent.Kind.CARD_DRAWN)
	expected_tail.append(MatchEvent.Kind.CARD_DRAWN)
	assert_array(_typed(kinds.slice(at + 1))).is_equal(expected_tail)
	assert_int(_state_int(engine, "round")).is_equal(2)
	assert_int(_state_int(engine, "turn")).is_equal(1)
	assert_array(_state_ints(engine, "scores")).is_equal(_typed([0, 0]))


func test_tied_round_awards_no_win() -> void:
	var engine: MatchEngine = _started(SEED)
	var events: Array[MatchEvent] = _play_round(engine, TIE)
	var ended: MatchEvent = _last(events, MatchEvent.Kind.ROUND_ENDED)
	assert_int(_payload_int(ended, "round")).is_equal(1)
	assert_array(_payload_ints(ended, "scores")).is_equal(_typed([0, 0]))
	assert_int(_payload_int(ended, "winner")).is_equal(-1)
	assert_array(_payload_ints(ended, "wins")).is_equal(_typed([0, 0]))
	assert_int(_state_int(engine, "last_round_winner")).is_equal(-1)
	assert_int(_state_int(engine, "round")).is_equal(2)


func test_higher_board_wins_when_both_seats_play() -> void:
	# Turn 7: the first committer plays its strongest card, the second its weakest.
	var checked: int = 0
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _started(match_seed)
		while engine.energy() < MatchRules.TURNS:
			_pass(engine)
		var first: int = engine.awaited_seat()
		var second: int = 1 - first
		var strong: int = _strongest(_hand(engine, first))
		var weak: int = _weakest(_hand(engine, second))
		if _power(strong) == _power(weak):
			continue
		var a: Array[int] = [strong]
		var b: Array[int] = [weak]
		engine.apply(EngineAction.commit(first, a))
		var result: ApplyResult = engine.apply(EngineAction.commit(second, b))
		assert_bool(result.ok).is_true()
		var expected_scores: Array[int] = [0, 0]
		expected_scores[first] = _power(strong)
		expected_scores[second] = _power(weak)
		var expected_winner: int = 0 if expected_scores[0] > expected_scores[1] else 1
		var ended: MatchEvent = _last(result.events, MatchEvent.Kind.ROUND_ENDED)
		assert_array(_payload_ints(ended, "scores")).is_equal(expected_scores)
		assert_int(_payload_int(ended, "winner")).is_equal(expected_winner)
		var expected_wins: Array[int] = [0, 0]
		expected_wins[expected_winner] = 1
		assert_array(_payload_ints(ended, "wins")).is_equal(expected_wins)
		checked += 1
		if checked >= 3:
			break
	assert_int(checked).is_greater(0)


func _power(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).power


func _strongest(hand: Array[int]) -> int:
	var best: int = hand[0]
	for card: int in hand:
		if _power(card) > _power(best):
			best = card
	return best


func _weakest(hand: Array[int]) -> int:
	var worst: int = hand[0]
	for card: int in hand:
		if _power(card) < _power(worst):
			worst = card
	return worst


func test_round_end_clears_boards_and_hands() -> void:
	# Observable once the match ends, since no new round re-deals.
	var engine: MatchEngine = _started(SEED)
	var outcomes: Array[int] = [0, 0, 0, 0]
	_play_rounds(engine, outcomes)
	assert_bool(engine.is_over()).is_true()
	for seat: int in range(2):
		assert_array(_hand(engine, seat)).is_empty()
		assert_array(_board(engine, seat)).is_empty()
	assert_array(_state_ints(engine, "pending")).is_empty()
	assert_array(_state_ints(engine, "scores")).is_equal(_typed([0, 0]))


# --- R18, C9: turn-1 order --------------------------------------------------------------


func test_round_winner_commits_second_on_turn_1() -> void:
	for winner: int in range(2):
		var engine: MatchEngine = _started(SEED)
		var events: Array[MatchEvent] = _play_round(engine, winner)
		var started: MatchEvent = _last(events, MatchEvent.Kind.ROUND_STARTED)
		assert_int(_payload_int(started, "round")).is_equal(2)
		assert_int(_payload_int(started, "first_seat")).is_equal(1 - winner)
		assert_bool(_payload_bool(started, "first_by_coin")).is_false()
		var turn_started: MatchEvent = _last(events, MatchEvent.Kind.TURN_STARTED)
		assert_int(_payload_int(turn_started, "turn")).is_equal(1)
		assert_int(_payload_int(turn_started, "first_seat")).is_equal(1 - winner)
		assert_int(engine.awaited_seat()).is_equal(1 - winner)


func test_won_round_then_tie_looks_past_the_tie() -> void:
	# Spec scenario: seat 1 won round 2 and round 3 tied, so seat 0 commits first on turn
	# 1 of round 4. Seat 0 won round 1, so only the most recent win may count.
	var engine: MatchEngine = _started(SEED)
	var outcomes: Array[int] = [0, 1, TIE]
	var events: Array[MatchEvent] = _play_rounds(engine, outcomes)
	var started: MatchEvent = _last(events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(_payload_int(started, "round")).is_equal(4)
	assert_int(_payload_int(started, "first_seat")).is_equal(0)
	assert_bool(_payload_bool(started, "first_by_coin")).is_false()
	assert_int(_state_int(engine, "round")).is_equal(4)
	assert_int(_state_int(engine, "turn")).is_equal(1)
	assert_int(_state_int(engine, "last_round_winner")).is_equal(1)
	assert_int(engine.awaited_seat()).is_equal(0)


func test_two_ties_after_a_win_keep_the_winner_second() -> void:
	var engine: MatchEngine = _started(SEED)
	var outcomes: Array[int] = [1, 0, TIE, TIE]
	var events: Array[MatchEvent] = _play_rounds(engine, outcomes)
	var started: MatchEvent = _last(events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(_payload_int(started, "round")).is_equal(5)
	assert_int(_payload_int(started, "first_seat")).is_equal(1)
	assert_int(engine.awaited_seat()).is_equal(1)


func test_coin_flip_only_until_the_first_won_round() -> void:
	# Rounds: tie, tie, seat 1 wins, tie, then round 5 starts. The engine stream draws
	# seat 0's shuffle, seat 1's shuffle and a coin at rounds 1-3, and no coin at 4 and 5.
	var outcomes: Array[int] = [TIE, TIE, 1, TIE]
	var coin_rounds: int = 3
	var seeds: Array[int] = [1, 2, 77, 9007199254740993]
	for match_seed: int in seeds:
		var rng: MatchRng = MatchRng.new(match_seed)
		var coins: Array[int] = []
		var deck0: Array[int] = []
		var deck1: Array[int] = []
		for round_number: int in range(1, outcomes.size() + 2):
			deck0 = _ids(0)
			deck1 = _ids(1)
			rng.shuffle_in_place(deck0)
			rng.shuffle_in_place(deck1)
			if round_number <= coin_rounds:
				coins.append(rng.coin_flip())
		var engine: MatchEngine = MatchEngine.create(match_seed, _db())
		var events: Array[MatchEvent] = _match_events(engine, outcomes)
		var starts: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.ROUND_STARTED)
		assert_int(starts.size()).is_equal(outcomes.size() + 1)
		for i: int in range(starts.size()):
			assert_int(_payload_int(starts[i], "round")).is_equal(i + 1)
			var by_coin: bool = _payload_bool(starts[i], "first_by_coin")
			if i < coin_rounds:
				assert_bool(by_coin).is_true()
				assert_int(_payload_int(starts[i], "first_seat")).is_equal(coins[i])
			else:
				assert_bool(by_coin).is_false()
				assert_int(_payload_int(starts[i], "first_seat")).is_equal(0)
		# The stream and round 5's hands match the manual replay exactly.
		assert_int(_state_int(engine, "rng_state")).is_equal(rng.state)
		var top: int = MatchRules.OPENING_HAND + 1
		assert_array(_hand(engine, 0)).is_equal(_typed(deck0.slice(0, top)))
		assert_array(_hand(engine, 1)).is_equal(_typed(deck1.slice(0, top)))


func test_turns_never_touch_the_engine_stream() -> void:
	var engine: MatchEngine = _started(SEED)
	var at_start: int = _state_int(engine, "rng_state")
	for _step: int in range(2 * MatchRules.TURNS - 1):
		_pass(engine)
		assert_int(_state_int(engine, "rng_state")).is_equal(at_start)


# --- R20: four wins ---------------------------------------------------------------------


func test_four_straight_wins_end_the_match() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [0, 0, 0, 0]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_WINS, _typed([4, 0]), 4)
	# The last round ends, then the match ends; no fifth round starts.
	var kinds: Array[int] = _kinds(events)
	assert_int(kinds[kinds.size() - 2]).is_equal(MatchEvent.Kind.ROUND_ENDED)
	assert_int(_of_kind(events, MatchEvent.Kind.ROUND_STARTED).size()).is_equal(4)
	var ended: MatchEvent = _last(events, MatchEvent.Kind.ROUND_ENDED)
	assert_int(_payload_int(ended, "round")).is_equal(4)
	assert_array(_payload_ints(ended, "wins")).is_equal(_typed([4, 0]))
	_assert_all_rejected_as_over(engine)


func test_four_wins_after_ties_end_the_match_early() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [1, TIE, 1, 0, 1, 1]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 1, MatchEngine.REASON_WINS, _typed([1, 4]), 6)


func test_fourth_win_in_round_7_is_reason_wins() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [0, 0, 0, 1, 1, 1, 0]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_WINS, _typed([4, 3]), 7)


# --- R21: after round 7 -----------------------------------------------------------------


func test_more_wins_after_round_7_take_the_match() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [0, TIE, TIE, 1, 0, TIE, TIE]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_ROUNDS, _typed([2, 1]), 7)
	assert_int(_of_kind(events, MatchEvent.Kind.ROUND_STARTED).size()).is_equal(7)
	assert_bool(_state_bool(engine, "sudden_death")).is_false()
	_assert_all_rejected_as_over(engine)


func test_single_win_in_round_7_takes_the_match() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [TIE, TIE, TIE, TIE, TIE, TIE, 1]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 1, MatchEngine.REASON_ROUNDS, _typed([0, 1]), 7)


# --- R21, R22: sudden death -------------------------------------------------------------


func test_three_all_after_round_7_goes_to_sudden_death() -> void:
	# Spec scenario: wins 3-3 after round 7; round 8 is sudden death and its first won
	# round ends the match with reason sudden_death (here, seat 0's fourth win).
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [0, 1, 0, 1, 0, 1, TIE]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	assert_bool(engine.is_over()).is_false()
	assert_array(_of_kind(events, MatchEvent.Kind.MATCH_ENDED)).is_empty()
	var round_7: MatchEvent = _last(events, MatchEvent.Kind.ROUND_ENDED)
	assert_int(_payload_int(round_7, "round")).is_equal(7)
	assert_array(_payload_ints(round_7, "wins")).is_equal(_typed([3, 3]))
	var started: MatchEvent = _last(events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(_payload_int(started, "round")).is_equal(8)
	assert_bool(_payload_bool(started, "sudden_death")).is_true()
	# Seat 1 won round 6 most recently, so it commits second (C9, sudden death included).
	assert_int(_payload_int(started, "first_seat")).is_equal(0)
	assert_bool(_payload_bool(started, "first_by_coin")).is_false()
	assert_int(_state_int(engine, "round")).is_equal(8)
	assert_bool(_state_bool(engine, "sudden_death")).is_true()
	var more: Array[MatchEvent] = _play_round(engine, 0)
	events.append_array(more)
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_SUDDEN_DEATH, _typed([4, 3]), 8)
	assert_array(_of_kind(more, MatchEvent.Kind.ROUND_STARTED)).is_empty()
	_assert_all_rejected_as_over(engine)


func test_tied_sudden_death_starts_another() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [0, 1, 0, 1, 0, 1, TIE, TIE]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	assert_bool(engine.is_over()).is_false()
	var started: MatchEvent = _last(events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(_payload_int(started, "round")).is_equal(9)
	assert_bool(_payload_bool(started, "sudden_death")).is_true()
	# The tied round 8 is looked past: seat 1 still won most recently.
	assert_int(_payload_int(started, "first_seat")).is_equal(0)
	assert_bool(_payload_bool(started, "first_by_coin")).is_false()
	var more: Array[MatchEvent] = _play_round(engine, 1)
	events.append_array(more)
	_assert_match_ended(engine, events, 1, MatchEngine.REASON_SUDDEN_DEATH, _typed([3, 4]), 9)


func test_sudden_death_after_no_wins_flips_coins_until_a_win() -> void:
	# Seven tied rounds: 0-0, so sudden death. No round has been won, so each sudden-death
	# round still flips the coin (C9) until round 9 is won.
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [TIE, TIE, TIE, TIE, TIE, TIE, TIE, TIE, 1]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 1, MatchEngine.REASON_SUDDEN_DEATH, _typed([0, 1]), 9)
	var starts: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(starts.size()).is_equal(9)
	for i: int in range(starts.size()):
		var round_number: int = i + 1
		assert_int(_payload_int(starts[i], "round")).is_equal(round_number)
		var sudden: bool = _payload_bool(starts[i], "sudden_death")
		var by_coin: bool = _payload_bool(starts[i], "first_by_coin")
		assert_bool(by_coin).is_true()
		if round_number > MatchRules.ROUNDS:
			assert_bool(sudden).is_true()
		else:
			assert_bool(sudden).is_false()
	# Nine rounds, each with a coin: the stream matches a manual replay.
	var rng: MatchRng = MatchRng.new(SEED)
	for _round: int in range(9):
		var deck0: Array[int] = _ids(0)
		var deck1: Array[int] = _ids(1)
		rng.shuffle_in_place(deck0)
		rng.shuffle_in_place(deck1)
		rng.coin_flip()
	assert_int(_state_int(engine, "rng_state")).is_equal(rng.state)


# --- R23: concede -----------------------------------------------------------------------


func test_concede_by_the_waiting_seat_ends_the_match() -> void:
	# Spec scenario: round 2, after the first commit, the seat not awaited concedes.
	var engine: MatchEngine = _started(SEED)
	_play_round(engine, 0)
	var waiting: int = engine.awaited_seat()
	_pass(engine)
	assert_int(engine.awaited_seat()).is_equal(1 - waiting)
	var count: int = engine.accepted_action_count()
	var result: ApplyResult = engine.apply(EngineAction.concede(waiting))
	assert_bool(result.ok).is_true()
	assert_int(result.error).is_equal(EngineError.Code.NONE)
	var expected: Array[int] = [MatchEvent.Kind.CONCEDED, MatchEvent.Kind.MATCH_ENDED]
	assert_array(_kinds(result.events)).is_equal(expected)
	var conceded: MatchEvent = result.events[0]
	assert_int(_payload_int(conceded, "seat")).is_equal(waiting)
	assert_int(conceded.owner_seat).is_equal(MatchEvent.PUBLIC)
	# The concede is accepted and recorded; round 2 was not finished, so 1 round played.
	assert_int(engine.accepted_action_count()).is_equal(count + 1)
	var actions: Array[EngineAction] = engine.accepted_actions()
	assert_int(actions[actions.size() - 1].kind).is_equal(EngineAction.Kind.CONCEDE)
	assert_int(actions[actions.size() - 1].seat).is_equal(waiting)
	_assert_match_ended(
		engine, result.events, 1 - waiting, MatchEngine.REASON_CONCEDE, _typed([1, 0]), 1
	)
	_assert_all_rejected_as_over(engine)


func test_concede_by_the_awaited_seat_ends_the_match() -> void:
	for seat_offset: int in range(2):
		var engine: MatchEngine = _started(SEED)
		var seat: int = (engine.awaited_seat() + seat_offset) % 2
		var result: ApplyResult = engine.apply(EngineAction.concede(seat))
		assert_bool(result.ok).is_true()
		_assert_match_ended(
			engine, result.events, 1 - seat, MatchEngine.REASON_CONCEDE, _typed([0, 0]), 0
		)
		_assert_all_rejected_as_over(engine)


func test_concede_in_sudden_death() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [0, 1, 0, 1, 0, 1, TIE]
	_match_events(engine, outcomes)
	var result: ApplyResult = engine.apply(EngineAction.concede(1))
	assert_bool(result.ok).is_true()
	_assert_match_ended(engine, result.events, 0, MatchEngine.REASON_CONCEDE, _typed([3, 3]), 7)


# --- R25: match-end payload -------------------------------------------------------------


func test_rounds_played_counts_round_ends() -> void:
	var cases: Array[Array] = [
		[0, 0, 0, 0],
		[0, TIE, TIE, 1, 0, TIE, TIE],
		[0, 1, 0, 1, 0, 1, TIE, TIE, 0],
	]
	for outcomes_raw: Array in cases:
		var engine: MatchEngine = MatchEngine.create(SEED, _db())
		var events: Array[MatchEvent] = _match_events(engine, _typed(outcomes_raw))
		assert_bool(engine.is_over()).is_true()
		var ended: MatchEvent = _last(events, MatchEvent.Kind.MATCH_ENDED)
		var round_ends: int = _of_kind(events, MatchEvent.Kind.ROUND_ENDED).size()
		assert_int(round_ends).is_equal(outcomes_raw.size())
		assert_int(_payload_int(ended, "rounds_played")).is_equal(round_ends)
