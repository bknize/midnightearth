# gdlint: disable=max-public-methods
class_name TestRoundMatchEnd
extends GdUnitTestSuite
## MatchEngine round and match end: R18 (turn-1 order per C9, coin flip only before the
## first won round), R19 (round winner, ties award nothing), R20 (4 wins), R21 (end after
## round 7 or into sudden death), R22 (sudden-death chains), R23 (concede out of turn),
## R24 (round-end payload), R25 (match-end payload), MATCH_OVER after the end, C14
## (`rounds_played` counts completed rounds, concede included) and C15 (the final table
## stays in view_for() after MATCH_ENDED on every end path).
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
	# The next round's start clears the old table (C15 keeps it only when the match ends).
	for seat: int in range(2):
		assert_array(_board(engine, seat)).is_empty()
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.OPENING_HAND + 1)
	assert_array(_state_ints(engine, "pending")).is_empty()


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
			if not _pass(engine).ok:
				break
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


func _cost(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).cost


func _cheapest(hand: Array[int]) -> int:
	var best: int = hand[0]
	for card: int in hand:
		if _cost(card) < _cost(best):
			best = card
	return best


func _board_power(board: Array[int]) -> int:
	var total: int = 0
	for card: int in board:
		total += _power(card)
	return total


## The events from the last ROUND_STARTED on: the round in progress or the final round.
func _last_round(events: Array[MatchEvent]) -> Array[MatchEvent]:
	var kinds: Array[int] = _kinds(events)
	var at: int = kinds.rfind(MatchEvent.Kind.ROUND_STARTED)
	var out: Array[MatchEvent] = []
	if at < 0:
		fail("no ROUND_STARTED event")
		return out
	out.assign(events.slice(at))
	return out


## `seat`'s hand rebuilt from one round's full events: deals and draws in, commits out.
func _hand_from(round_events: Array[MatchEvent], seat: int) -> Array[int]:
	var hand: Array[int] = []
	for event: MatchEvent in round_events:
		if not event.payload.has("seat") or _payload_int(event, "seat") != seat:
			continue
		if event.kind == MatchEvent.Kind.CARD_DEALT or event.kind == MatchEvent.Kind.CARD_DRAWN:
			hand.append(_payload_int(event, "card"))
		elif event.kind == MatchEvent.Kind.COMMITTED:
			for card: int in _payload_ints(event, "cards"):
				hand.erase(card)
	return hand


## `seat`'s board rebuilt from one round's CARD_REVEALED events, in reveal order.
func _board_from(round_events: Array[MatchEvent], seat: int) -> Array[int]:
	var board: Array[int] = []
	for event: MatchEvent in _of_kind(round_events, MatchEvent.Kind.CARD_REVEALED):
		if _payload_int(event, "seat") == seat:
			board.append(_payload_int(event, "card"))
	return board


## C15: after MATCH_ENDED each seat's view shows the final round's table: the boards
## revealed in it, the hands left at its end and the ROUND_ENDED scores. `events` must run
## from at least the final round's ROUND_STARTED to MATCH_ENDED.
func _assert_final_table(engine: MatchEngine, events: Array[MatchEvent]) -> void:
	assert_bool(engine.is_over()).is_true()
	var round_events: Array[MatchEvent] = _last_round(events)
	var round_end: MatchEvent = _last(round_events, MatchEvent.Kind.ROUND_ENDED)
	var scores: Array[int] = _payload_ints(round_end, "scores")
	var round_winner: int = _payload_int(round_end, "winner")
	assert_int(round_winner).is_not_equal(TIE)
	assert_int(scores[round_winner]).is_greater(0)
	for seat: int in range(2):
		var opp: int = 1 - seat
		var view: SeatView = engine.view_for(seat)
		assert_int(view.phase).is_equal(MatchState.Phase.OVER)
		assert_int(view.round_number).is_equal(_payload_int(round_end, "round"))
		assert_int(view.turn).is_equal(MatchRules.TURNS)
		assert_array(view.scores).is_equal(scores)
		assert_array(view.own_board).is_equal(_board_from(round_events, seat))
		assert_array(view.opponent_board).is_equal(_board_from(round_events, opp))
		assert_int(_board_power(view.own_board)).is_equal(scores[seat])
		var hand: Array[int] = _hand_from(round_events, seat)
		assert_array(hand).is_not_empty()
		assert_array(view.own_hand).is_equal(hand)
		assert_int(view.opponent_hand_count).is_equal(_hand_from(round_events, opp).size())
		assert_array(view.own_pending).is_empty()
		assert_int(view.opponent_pending_count).is_equal(0)
		if seat == round_winner:
			assert_array(view.own_board).is_not_empty()
	assert_array(_state_ints(engine, "pending")).is_empty()


## Both seats pass turns 1-6; on turn 7 the first committer plays its strongest card and
## the second its weakest. When those powers are equal it stops before turn 7's commits
## (the round would tie) and the caller tries another seed.
func _play_contested_round(engine: MatchEngine) -> Array[MatchEvent]:
	var seen: Array[MatchEvent] = []
	while engine.energy() < MatchRules.TURNS:
		var passed: ApplyResult = _pass(engine)
		if not passed.ok:
			fail("pass rejected with code %d" % passed.error)
			return seen
		seen.append_array(passed.events)
	var first: int = engine.awaited_seat()
	var second: int = 1 - first
	var strong: int = _strongest(_hand(engine, first))
	var weak: int = _weakest(_hand(engine, second))
	if _power(strong) == _power(weak):
		return seen
	var a: Array[int] = [strong]
	var b: Array[int] = [weak]
	seen.append_array(engine.apply(EngineAction.commit(first, a)).events)
	seen.append_array(engine.apply(EngineAction.commit(second, b)).events)
	return seen


# --- C15: the final table stays after MATCH_ENDED ---------------------------------------


func test_wins_end_keeps_the_final_table() -> void:
	# The fourth win's round is not cleared: seat 0's turn-7 card stays on its board.
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [0, 0, 0, 0]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_WINS, _typed([4, 0]), 4)
	_assert_final_table(engine, events)
	assert_int(_board(engine, 0).size()).is_equal(1)
	assert_array(_board(engine, 1)).is_empty()
	var round_end: MatchEvent = _last(events, MatchEvent.Kind.ROUND_ENDED)
	assert_array(_state_ints(engine, "scores")).is_equal(_payload_ints(round_end, "scores"))


func test_rounds_end_keeps_the_final_table() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [TIE, TIE, TIE, TIE, TIE, TIE, 1]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 1, MatchEngine.REASON_ROUNDS, _typed([0, 1]), 7)
	_assert_final_table(engine, events)


func test_sudden_death_end_keeps_the_final_table() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var outcomes: Array[int] = [0, 1, 0, 1, 0, 1, TIE, 0]
	var events: Array[MatchEvent] = _match_events(engine, outcomes)
	_assert_match_ended(engine, events, 0, MatchEngine.REASON_SUDDEN_DEATH, _typed([4, 3]), 8)
	_assert_final_table(engine, events)


func test_contested_final_round_keeps_both_boards_on_every_end_path() -> void:
	# The deciding round has a card on each board; whichever seat wins it ends the match.
	var cases: Array[Array] = [
		[0, 0, 0, 1, 1, 1],
		[TIE, TIE, TIE, TIE, TIE, TIE],
		[0, 1, 0, 1, 0, 1, TIE],
	]
	var reasons: Array[String] = [
		MatchEngine.REASON_WINS, MatchEngine.REASON_ROUNDS, MatchEngine.REASON_SUDDEN_DEATH
	]
	for index: int in range(cases.size()):
		var outcomes: Array[int] = _typed(cases[index])
		var checked: bool = false
		for match_seed: int in range(1, SEARCH_SEEDS + 1):
			var engine: MatchEngine = MatchEngine.create(match_seed, _db())
			var events: Array[MatchEvent] = _match_events(engine, outcomes)
			events.append_array(_play_contested_round(engine))
			if not engine.is_over():
				continue
			var ended: MatchEvent = _last(events, MatchEvent.Kind.MATCH_ENDED)
			assert_str(_payload_str(ended, "reason")).is_equal(reasons[index])
			_assert_final_table(engine, events)
			for seat: int in range(2):
				assert_int(_board(engine, seat).size()).is_equal(1)
			checked = true
			break
		assert_bool(checked).override_failure_message(reasons[index]).is_true()


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


func test_concede_mid_round_counts_completed_rounds_and_keeps_the_table() -> void:
	# C14: a concede in round 3 reports 2 rounds played (the round number still says 3).
	# C15: the table is left exactly as it stood, a revealed card and a face-down commit
	# included; only the phase, the result and the action count change.
	var engine: MatchEngine = _started(SEED)
	var outcomes: Array[int] = [0, TIE]
	_play_rounds(engine, outcomes)
	var play_turn: int = 5
	while engine.energy() < play_turn:
		var passed: ApplyResult = _pass(engine)
		if not passed.ok:
			fail("pass rejected with code %d" % passed.error)
			return
	var player: int = engine.awaited_seat()
	var card: int = _cheapest(_hand(engine, player))
	assert_int(_cost(card)).is_less_equal(play_turn)
	var play: Array[int] = [card]
	assert_bool(engine.apply(EngineAction.commit(player, play)).ok).is_true()
	assert_bool(_pass(engine).ok).is_true()
	# Turn 6: the player won turn 5, so it commits first, face down.
	assert_int(engine.energy()).is_equal(play_turn + 1)
	assert_int(engine.awaited_seat()).is_equal(player)
	var held: Array[int] = [_cheapest(_hand(engine, player))]
	assert_bool(engine.apply(EngineAction.commit(player, held)).ok).is_true()
	assert_int(engine.awaited_seat()).is_equal(1 - player)
	var before: Dictionary = engine.full_state()
	var round_number: int = engine.view_for(0).round_number
	assert_int(round_number).is_equal(3)
	var result: ApplyResult = engine.apply(EngineAction.concede(player))
	assert_bool(result.ok).is_true()
	_assert_match_ended(
		engine, result.events, 1 - player, MatchEngine.REASON_CONCEDE, _typed([1, 0]), 2
	)
	var ended: MatchEvent = _last(result.events, MatchEvent.Kind.MATCH_ENDED)
	assert_int(_payload_int(ended, "rounds_played")).is_equal(round_number - 1)
	# The full state differs from the pre-concede one only in phase, result and count.
	var expected: Dictionary = before.duplicate(true)
	var applied: int = before["actions_applied"]
	expected["phase"] = MatchState.Phase.OVER
	expected["result"] = {
		"winner": 1 - player, "reason": MatchEngine.REASON_CONCEDE, "rounds_played": 2
	}
	expected["actions_applied"] = applied + 1
	assert_dict(engine.full_state()).is_equal(expected)
	assert_array(_state_ints(engine, "pending")).is_equal(held)
	# Each view shows the table as left: hands, the revealed card and its score.
	var power: int = _power(card)
	for seat: int in range(2):
		var view: SeatView = engine.view_for(seat)
		assert_int(view.round_number).is_equal(round_number)
		assert_int(view.turn).is_equal(play_turn + 1)
		assert_array(view.own_hand).is_equal(_hand(engine, seat))
		assert_array(view.own_hand).is_not_empty()
		assert_array(view.board_of(player)).is_equal(play)
		assert_array(view.board_of(1 - player)).is_empty()
		assert_int(view.scores[player]).is_equal(power)
		assert_int(view.scores[1 - player]).is_equal(0)


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
