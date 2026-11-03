# gdlint: disable=max-public-methods
class_name TestTurn
extends GdUnitTestSuite
## MatchEngine core flow: R3-R5 (entry point, run to the next decision, two action
## kinds), R9 (instance ids), R11-R17 (round start, draw and burn, energy, two-step
## commit, reveal interleave, scoring, turn order for turns 2-7), R26-R27 (every error
## code leaves the state and the accepted actions unchanged; the engine never prints).
##
## Mid-match states come from scripted actions on known seeds, never from private fields.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
const ENGINE_DIR: String = "res://engine"
const FORBIDDEN_CALLS: Array[String] = [
	"print(",
	"printerr(",
	"prints(",
	"printt(",
	"print_rich(",
	"print_verbose(",
	"push_error(",
	"push_warning(",
	"assert(",
]

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


func _deck(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "deck", seat)


func _board(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "board", seat)


func _burned(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "burned", seat)


func _pending(engine: MatchEngine) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state["pending"]
	return _typed(raw)


func _scores(engine: MatchEngine) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state["scores"]
	return _typed(raw)


func _state_int(engine: MatchEngine, key: String) -> int:
	var state: Dictionary = engine.full_state()
	var value: int = state[key]
	return value


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _payload_ints(event: MatchEvent, key: String) -> Array[int]:
	var raw: Array = event.payload[key]
	return _typed(raw)


func _pass(engine: MatchEngine) -> ApplyResult:
	var none: Array[int] = []
	return engine.apply(EngineAction.commit(engine.awaited_seat(), none))


## Both seats pass until the given turn of round 1 is awaiting its first commit.
func _pass_until_turn(engine: MatchEngine, turn: int) -> void:
	while engine.energy() < turn:
		if not _pass(engine).ok:
			return


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


func _event_dicts(events: Array[MatchEvent]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: MatchEvent in events:
		out.append(event.to_dict())
	return out


## The first legal set of exactly `size` cards, or an empty list when none exists.
func _find_set(hand: Array[int], energy: int, size: int) -> Array[int]:
	for s: Array in LegalPlays.enumerate(hand, energy, _db()):
		if s.size() == size:
			return _typed(s)
	var none: Array[int] = []
	return none


func _power(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).power


func _ids(seat: int) -> Array[int]:
	var out: Array[int] = []
	for index: int in range(MatchRules.DECK_SIZE):
		out.append(seat * MatchRules.DECK_SIZE + index)
	return out


## Applies an illegal action and checks nothing changed (R26).
func _assert_rejected(engine: MatchEngine, action: EngineAction, code: int) -> void:
	var before: Dictionary = engine.full_state()
	var count: int = engine.accepted_action_count()
	var awaited: int = engine.awaited_seat()
	var result: ApplyResult = engine.apply(action)
	assert_bool(result.ok).is_false()
	assert_int(result.error).is_equal(code)
	assert_array(result.events).is_empty()
	assert_dict(engine.full_state()).is_equal(before)
	assert_int(engine.accepted_action_count()).is_equal(count)
	assert_int(engine.awaited_seat()).is_equal(awaited)


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


# --- R3, R5: entry point and action kinds ---------------------------------------------


func test_start_and_apply_return_apply_results() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	assert_int(started.error).is_equal(EngineError.Code.NONE)
	assert_array(started.events).is_not_empty()
	var applied: ApplyResult = _pass(engine)
	assert_bool(applied.ok).is_true()
	assert_int(applied.error).is_equal(EngineError.Code.NONE)
	assert_int(engine.accepted_action_count()).is_equal(1)
	assert_int(_state_int(engine, "actions_applied")).is_equal(1)


func test_exactly_two_action_kinds() -> void:
	assert_int(EngineAction.Kind.size()).is_equal(2)
	var cards: Array[int] = [3, 7]
	var commit: EngineAction = EngineAction.commit(0, cards)
	assert_int(commit.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(commit.seat).is_equal(0)
	assert_array(commit.cards).is_equal(cards)
	var concede: EngineAction = EngineAction.concede(1)
	assert_int(concede.kind).is_equal(EngineAction.Kind.CONCEDE)
	assert_int(concede.seat).is_equal(1)
	assert_array(concede.cards).is_empty()


func test_commit_copies_its_card_list() -> void:
	var cards: Array[int] = [3, 7]
	var commit: EngineAction = EngineAction.commit(0, cards)
	cards.append(9)
	assert_array(commit.cards).is_equal(_typed([3, 7]))


func test_action_dict_round_trip() -> void:
	var cards: Array[int] = [7, 3]
	var commit: EngineAction = EngineAction.commit(1, cards)
	var expected_commit: Dictionary = {"k": "commit", "s": 1, "c": [7, 3]}
	assert_dict(commit.to_dict()).is_equal(expected_commit)
	var back: EngineAction = EngineAction.from_dict(commit.to_dict())
	assert_object(back).is_not_null()
	assert_int(back.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(back.seat).is_equal(1)
	assert_array(back.cards).is_equal(cards)
	var concede: EngineAction = EngineAction.concede(0)
	var expected_concede: Dictionary = {"k": "concede", "s": 0}
	assert_dict(concede.to_dict()).is_equal(expected_concede)
	var conceded: EngineAction = EngineAction.from_dict(concede.to_dict())
	assert_int(conceded.kind).is_equal(EngineAction.Kind.CONCEDE)
	assert_int(conceded.seat).is_equal(0)


func test_action_from_json_style_floats() -> void:
	var parsed: EngineAction = EngineAction.from_dict({"k": "commit", "s": 1.0, "c": [3.0, 27.0]})
	assert_object(parsed).is_not_null()
	assert_int(parsed.seat).is_equal(1)
	assert_array(parsed.cards).is_equal(_typed([3, 27]))


func test_malformed_action_dicts_give_null() -> void:
	var bad: Array[Dictionary] = [
		{},
		{"k": "commit", "s": 0},
		{"k": "pass", "s": 0, "c": []},
		{"k": 1, "s": 0, "c": []},
		{"k": "commit", "s": 2, "c": []},
		{"k": "commit", "s": -1, "c": []},
		{"k": "commit", "s": 0.5, "c": []},
		{"k": "commit", "s": "0", "c": []},
		{"k": "commit", "s": 0, "c": "3"},
		{"k": "commit", "s": 0, "c": [1.5]},
		{"k": "commit", "s": 0, "c": ["3"]},
		{"k": "concede", "s": 0, "c": []},
		{"s": 0, "c": []},
	]
	for d: Dictionary in bad:
		assert_object(EngineAction.from_dict(d)).is_null()


# --- R1, R9, R11: round start ---------------------------------------------------------


func test_round_one_start_deals_three_draws_one() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	var result: ApplyResult = engine.start()
	var expected: Array[int] = [MatchEvent.Kind.ROUND_STARTED]
	for _i: int in range(2 * MatchRules.OPENING_HAND):
		expected.append(MatchEvent.Kind.CARD_DEALT)
	expected.append(MatchEvent.Kind.TURN_STARTED)
	expected.append(MatchEvent.Kind.CARD_DRAWN)
	expected.append(MatchEvent.Kind.CARD_DRAWN)
	assert_array(_kinds(result.events)).is_equal(expected)
	for seat: int in range(2):
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.OPENING_HAND + 1)
		assert_int(_deck(engine, seat).size()).is_equal(
			MatchRules.DECK_SIZE - MatchRules.OPENING_HAND - 1
		)
		assert_array(_board(engine, seat)).is_empty()
		assert_array(_burned(engine, seat)).is_empty()
	assert_int(_state_int(engine, "round")).is_equal(1)
	assert_int(_state_int(engine, "turn")).is_equal(1)
	assert_int(engine.energy()).is_equal(1)
	var round_started: MatchEvent = result.events[0]
	assert_int(_payload_int(round_started, "round")).is_equal(1)
	var by_coin: bool = round_started.payload["first_by_coin"]
	var sudden: bool = round_started.payload["sudden_death"]
	assert_bool(by_coin).is_true()
	assert_bool(sudden).is_false()
	assert_int(engine.awaited_seat()).is_equal(_payload_int(round_started, "first_seat"))


func test_deal_events_are_private_to_their_seat() -> void:
	var result: ApplyResult = MatchEngine.create(SEED, _db()).start()
	var dealt: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.CARD_DEALT)
	for i: int in range(dealt.size()):
		var seat: int = 0 if i < MatchRules.OPENING_HAND else 1
		assert_int(dealt[i].owner_seat).is_equal(seat)
		assert_int(_payload_int(dealt[i], "seat")).is_equal(seat)
	for drawn: MatchEvent in _of_kind(result.events, MatchEvent.Kind.CARD_DRAWN):
		assert_int(drawn.owner_seat).is_equal(_payload_int(drawn, "seat"))


func test_round_start_consumes_stream_seat0_seat1_then_coin() -> void:
	# The replay contract: shuffle seat 0, shuffle seat 1, then the coin flip (round 1).
	var seeds: Array[int] = [1, 2, 77, 9007199254740993]
	for match_seed: int in seeds:
		var rng: MatchRng = MatchRng.new(match_seed)
		var deck0: Array[int] = _ids(0)
		var deck1: Array[int] = _ids(1)
		rng.shuffle_in_place(deck0)
		rng.shuffle_in_place(deck1)
		var coin: int = rng.coin_flip()
		var engine: MatchEngine = _started(match_seed)
		var top: int = MatchRules.OPENING_HAND + 1
		assert_array(_hand(engine, 0)).is_equal(_typed(deck0.slice(0, top)))
		assert_array(_deck(engine, 0)).is_equal(_typed(deck0.slice(top)))
		assert_array(_hand(engine, 1)).is_equal(_typed(deck1.slice(0, top)))
		assert_array(_deck(engine, 1)).is_equal(_typed(deck1.slice(top)))
		assert_int(engine.awaited_seat()).is_equal(coin)
		assert_int(_state_int(engine, "rng_state")).is_equal(rng.state)


func test_instance_ids_unique_across_seats() -> void:
	var engine: MatchEngine = _started(SEED)
	for seat: int in range(2):
		var all: Array[int] = _typed(_hand(engine, seat) + _deck(engine, seat))
		all.sort()
		assert_array(all).is_equal(_ids(seat))


func test_next_round_reshuffles_and_clears_boards() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, MatchRules.TURNS)
	# Put a card on each board on turn 7 so the clear is observable.
	var first: int = engine.awaited_seat()
	engine.apply(EngineAction.commit(first, _find_set(_hand(engine, first), 7, 1)))
	var second: int = engine.awaited_seat()
	var result: ApplyResult = engine.apply(
		EngineAction.commit(second, _find_set(_hand(engine, second), 7, 1))
	)
	assert_bool(result.ok).is_true()
	var started: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(started.size()).is_equal(1)
	assert_int(_payload_int(started[0], "round")).is_equal(2)
	assert_int(_state_int(engine, "round")).is_equal(2)
	assert_int(_state_int(engine, "turn")).is_equal(1)
	assert_array(_pending(engine)).is_empty()
	for seat: int in range(2):
		assert_array(_board(engine, seat)).is_empty()
		assert_array(_burned(engine, seat)).is_empty()
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.OPENING_HAND + 1)
		var all: Array[int] = _typed(_hand(engine, seat) + _deck(engine, seat))
		all.sort()
		assert_array(all).is_equal(_ids(seat))
	var scores: Array[int] = _scores(engine)
	assert_array(scores).is_equal(_typed([0, 0]))


# --- R4: run to the next decision point -----------------------------------------------


func test_first_commit_stops_at_second_committer() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	var result: ApplyResult = _pass(engine)
	var expected: Array[int] = [MatchEvent.Kind.COMMITTED]
	assert_array(_kinds(result.events)).is_equal(expected)
	assert_int(engine.awaited_seat()).is_equal(1 - first)


func test_second_commit_runs_into_the_next_turn() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass(engine)
	var result: ApplyResult = _pass(engine)
	var expected: Array[int] = [
		MatchEvent.Kind.COMMITTED,
		MatchEvent.Kind.TURN_ENDED,
		MatchEvent.Kind.TURN_STARTED,
		MatchEvent.Kind.CARD_DRAWN,
		MatchEvent.Kind.CARD_DRAWN,
	]
	assert_array(_kinds(result.events)).is_equal(expected)
	assert_int(engine.energy()).is_equal(2)
	assert_int(engine.awaited_seat()).is_not_equal(-1)


# --- R12: draw and burn ---------------------------------------------------------------


func test_turn_start_draws_one_per_seat() -> void:
	var engine: MatchEngine = _started(SEED)
	var deck0: Array[int] = _deck(engine, 0)
	var deck1: Array[int] = _deck(engine, 1)
	_pass(engine)
	var result: ApplyResult = _pass(engine)
	var drawn: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.CARD_DRAWN)
	assert_int(drawn.size()).is_equal(2)
	assert_int(_payload_int(drawn[0], "seat")).is_equal(0)
	assert_int(_payload_int(drawn[0], "card")).is_equal(deck0[0])
	assert_int(_payload_int(drawn[1], "seat")).is_equal(1)
	assert_int(_payload_int(drawn[1], "card")).is_equal(deck1[0])
	for seat: int in range(2):
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.OPENING_HAND + 2)


func test_hand_at_cap_burns_the_draw() -> void:
	# Passing every turn: 4 cards on turn 1, then 5, 6, 7; turn 5's draw is burned.
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 4)
	for seat: int in range(2):
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.HAND_CAP)
	var hands_before: Array[Array] = [_hand(engine, 0), _hand(engine, 1)]
	var decks_before: Array[Array] = [_deck(engine, 0), _deck(engine, 1)]
	_pass(engine)
	var result: ApplyResult = _pass(engine)
	assert_int(engine.energy()).is_equal(5)
	assert_array(_of_kind(result.events, MatchEvent.Kind.CARD_DRAWN)).is_empty()
	var burned: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.CARD_BURNED)
	assert_int(burned.size()).is_equal(2)
	for seat: int in range(2):
		var burn: MatchEvent = burned[seat]
		assert_int(_payload_int(burn, "seat")).is_equal(seat)
		assert_int(burn.owner_seat).is_equal(seat)
		var top: Array[int] = _typed(decks_before[seat])
		assert_int(_payload_int(burn, "card")).is_equal(top[0])
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.HAND_CAP)
		assert_array(_hand(engine, seat)).is_equal(_typed(hands_before[seat]))
		assert_array(_burned(engine, seat)).is_equal(_typed([top[0]]))
	# Still at the cap a turn later: a second burn each.
	_pass_until_turn(engine, 6)
	for seat: int in range(2):
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.HAND_CAP)
		assert_int(_burned(engine, seat).size()).is_equal(2)


# --- R13: energy ----------------------------------------------------------------------


func test_energy_equals_turn_and_unspent_energy_is_lost() -> void:
	var engine: MatchEngine = _started(SEED)
	for turn: int in range(1, MatchRules.TURNS):
		assert_int(engine.energy()).is_equal(turn)
		_pass(engine)
		var result: ApplyResult = _pass(engine)
		var started: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)
		assert_int(started.size()).is_equal(1)
		assert_int(_payload_int(started[0], "turn")).is_equal(turn + 1)
		# Passing never banks energy: the next turn's energy is just its number.
		assert_int(_payload_int(started[0], "energy")).is_equal(turn + 1)


# --- R14: the first commit is held face down ------------------------------------------


func test_first_commit_is_face_down_and_awaits_second() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 4)
	var first: int = engine.awaited_seat()
	var hand: Array[int] = _hand(engine, first)
	var cards: Array[int] = _find_set(hand, engine.energy(), 1)
	assert_array(cards).is_not_empty()
	var result: ApplyResult = engine.apply(EngineAction.commit(first, cards))
	assert_bool(result.ok).is_true()
	assert_int(engine.awaited_seat()).is_equal(1 - first)
	assert_array(_pending(engine)).is_equal(cards)
	assert_array(_board(engine, first)).is_empty()
	assert_bool(_hand(engine, first).has(cards[0])).is_false()
	assert_array(_of_kind(result.events, MatchEvent.Kind.CARD_REVEALED)).is_empty()
	var committed: MatchEvent = result.events[0]
	assert_int(committed.kind).is_equal(MatchEvent.Kind.COMMITTED)
	assert_int(committed.owner_seat).is_equal(first)
	assert_int(_payload_int(committed, "seat")).is_equal(first)
	assert_int(_payload_int(committed, "count")).is_equal(1)
	assert_array(_payload_ints(committed, "cards")).is_equal(cards)


# --- R15, R16: reveal interleave and scoring ------------------------------------------


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
	# Commit out of hand order: the reveal follows the order given (R5).
	a.reverse()
	engine.apply(EngineAction.commit(first, a))
	var result: ApplyResult = engine.apply(EngineAction.commit(second, b))
	assert_bool(result.ok).is_true()
	var reveals: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.CARD_REVEALED)
	var expected_cards: Array[int] = [a[0], b[0], a[1], a[2]]
	var expected_seats: Array[int] = [first, second, first, first]
	assert_int(reveals.size()).is_equal(4)
	for i: int in range(reveals.size()):
		assert_int(_payload_int(reveals[i], "card")).is_equal(expected_cards[i])
		assert_int(_payload_int(reveals[i], "seat")).is_equal(expected_seats[i])
		assert_int(_payload_int(reveals[i], "order")).is_equal(i)
		assert_int(_payload_int(reveals[i], "power")).is_equal(_power(expected_cards[i]))
		assert_int(reveals[i].owner_seat).is_equal(MatchEvent.PUBLIC)
	# Scoring: each side's board power; the higher board wins the turn.
	var expected_scores: Array[int] = [0, 0]
	for card: int in a:
		expected_scores[first] += _power(card)
	expected_scores[second] += _power(b[0])
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
	assert_int(scores[first]).is_equal(_power(a[0]))
	assert_int(scores[second]).is_equal(_power(b[0]))


func test_tied_turn_has_no_winner() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass(engine)
	var result: ApplyResult = _pass(engine)
	var ended: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_ENDED)[0]
	assert_int(_payload_int(ended, "winner")).is_equal(-1)
	assert_array(_payload_ints(ended, "scores")).is_equal(_typed([0, 0]))
	assert_int(_state_int(engine, "last_turn_winner")).is_equal(-1)


# --- R17: turn order for turns 2-7 ----------------------------------------------------


func test_tied_turn_keeps_the_first_committer() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	for turn: int in range(2, MatchRules.TURNS + 1):
		_pass(engine)
		var result: ApplyResult = _pass(engine)
		var started: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)[0]
		assert_int(_payload_int(started, "turn")).is_equal(turn)
		assert_int(_payload_int(started, "first_seat")).is_equal(first)
		assert_int(engine.awaited_seat()).is_equal(first)


func test_turn_winner_commits_first_next_turn() -> void:
	# Turn 4: the first committer passes, the second plays a card and wins the turn.
	# A 7-card hand always holds a card of cost <= 4 (only 6 of 20 cost more).
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 4)
	var first: int = engine.awaited_seat()
	var second: int = 1 - first
	_pass(engine)
	var b: Array[int] = _find_set(_hand(engine, second), engine.energy(), 1)
	assert_array(b).is_not_empty()
	var result: ApplyResult = engine.apply(EngineAction.commit(second, b))
	var ended: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_ENDED)[0]
	assert_int(_payload_int(ended, "winner")).is_equal(second)
	var started: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)[0]
	assert_int(_payload_int(started, "turn")).is_equal(5)
	assert_int(_payload_int(started, "first_seat")).is_equal(second)
	assert_int(engine.awaited_seat()).is_equal(second)
	# Turn 5: both pass; the boards still favour `second`, so it stays first on turn 6.
	_pass(engine)
	result = _pass(engine)
	started = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)[0]
	assert_int(_payload_int(started, "first_seat")).is_equal(second)
	assert_int(_state_int(engine, "last_turn_winner")).is_equal(second)


# --- R26, R27: illegal actions ----------------------------------------------------------


func test_not_started() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	assert_int(engine.awaited_seat()).is_equal(-1)
	var none: Array[int] = []
	_assert_rejected(engine, EngineAction.commit(0, none), EngineError.Code.NOT_STARTED)
	_assert_rejected(engine, EngineAction.concede(1), EngineError.Code.NOT_STARTED)


func test_card_data_invalid_refuses_to_start() -> void:
	var engine: MatchEngine = MatchEngine.create(SEED, CardDb.from_json("{}"))
	var before: Dictionary = engine.full_state()
	var result: ApplyResult = engine.start()
	assert_bool(result.ok).is_false()
	assert_int(result.error).is_equal(EngineError.Code.CARD_DATA_INVALID)
	assert_array(result.events).is_empty()
	assert_dict(engine.full_state()).is_equal(before)
	assert_int(engine.awaited_seat()).is_equal(-1)
	_assert_rejected(engine, EngineAction.concede(0), EngineError.Code.NOT_STARTED)
	var null_db: MatchEngine = MatchEngine.create(SEED, null)
	assert_int(null_db.start().error).is_equal(EngineError.Code.CARD_DATA_INVALID)


func test_second_start_is_rejected() -> void:
	var engine: MatchEngine = _started(SEED)
	var before: Dictionary = engine.full_state()
	var result: ApplyResult = engine.start()
	assert_bool(result.ok).is_false()
	assert_int(result.error).is_equal(EngineError.Code.MALFORMED)
	assert_dict(engine.full_state()).is_equal(before)


func test_wrong_seat() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	var none: Array[int] = []
	_assert_rejected(engine, EngineAction.commit(1 - first, none), EngineError.Code.WRONG_SEAT)
	_pass(engine)
	# The first committer may not commit twice.
	_assert_rejected(engine, EngineAction.commit(first, none), EngineError.Code.WRONG_SEAT)


func test_card_not_in_hand() -> void:
	var engine: MatchEngine = _started(SEED)
	var seat: int = engine.awaited_seat()
	var theirs: Array[int] = [_hand(engine, 1 - seat)[0]]
	_assert_rejected(engine, EngineAction.commit(seat, theirs), EngineError.Code.CARD_NOT_IN_HAND)
	var from_deck: Array[int] = [_deck(engine, seat)[0]]
	_assert_rejected(
		engine, EngineAction.commit(seat, from_deck), EngineError.Code.CARD_NOT_IN_HAND
	)
	var unknown: Array[int] = [99]
	_assert_rejected(engine, EngineAction.commit(seat, unknown), EngineError.Code.CARD_NOT_IN_HAND)


func test_duplicate_card() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, MatchRules.TURNS)
	var seat: int = engine.awaited_seat()
	var card: int = _hand(engine, seat)[0]
	var twice: Array[int] = [card, card]
	_assert_rejected(engine, EngineAction.commit(seat, twice), EngineError.Code.DUPLICATE_CARD)


func test_over_budget() -> void:
	# Turn 1: four cards cost at least 4. Turn 3: six cards cost at least 8.
	var engine: MatchEngine = _started(SEED)
	var seat: int = engine.awaited_seat()
	_assert_rejected(
		engine, EngineAction.commit(seat, _hand(engine, seat)), EngineError.Code.OVER_BUDGET
	)
	_pass_until_turn(engine, 3)
	seat = engine.awaited_seat()
	_assert_rejected(
		engine, EngineAction.commit(seat, _hand(engine, seat)), EngineError.Code.OVER_BUDGET
	)


func test_malformed() -> void:
	var engine: MatchEngine = _started(SEED)
	var seat: int = engine.awaited_seat()
	var none: Array[int] = []
	_assert_rejected(engine, null, EngineError.Code.MALFORMED)
	_assert_rejected(engine, EngineAction.commit(2, none), EngineError.Code.MALFORMED)
	_assert_rejected(engine, EngineAction.commit(-1, none), EngineError.Code.MALFORMED)
	var unknown_kind: EngineAction = EngineAction.commit(seat, none)
	unknown_kind.kind = 99
	_assert_rejected(engine, unknown_kind, EngineError.Code.MALFORMED)
	var concede_with_cards: EngineAction = EngineAction.concede(seat)
	concede_with_cards.cards.append(_hand(engine, seat)[0])
	_assert_rejected(engine, concede_with_cards, EngineError.Code.MALFORMED)


func test_match_over() -> void:
	var engine: MatchEngine = _started(SEED)
	var waiting: int = 1 - engine.awaited_seat()
	# A concede is accepted from the seat that is not awaited.
	var result: ApplyResult = engine.apply(EngineAction.concede(waiting))
	assert_bool(result.ok).is_true()
	assert_bool(engine.is_over()).is_true()
	assert_int(engine.awaited_seat()).is_equal(-1)
	var none: Array[int] = []
	_assert_rejected(engine, EngineAction.commit(0, none), EngineError.Code.MATCH_OVER)
	_assert_rejected(engine, EngineAction.commit(1, none), EngineError.Code.MATCH_OVER)
	_assert_rejected(engine, EngineAction.concede(1 - waiting), EngineError.Code.MATCH_OVER)
	_assert_rejected(engine, null, EngineError.Code.MATCH_OVER)


func test_rejections_while_awaiting_second_change_nothing() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 4)
	var first: int = engine.awaited_seat()
	engine.apply(EngineAction.commit(first, _find_set(_hand(engine, first), 4, 1)))
	var second: int = engine.awaited_seat()
	var hand: Array[int] = _hand(engine, second)
	var twice: Array[int] = [hand[0], hand[0]]
	var none: Array[int] = []
	_assert_rejected(engine, EngineAction.commit(first, none), EngineError.Code.WRONG_SEAT)
	_assert_rejected(engine, EngineAction.commit(second, twice), EngineError.Code.DUPLICATE_CARD)
	_assert_rejected(engine, EngineAction.commit(second, hand), EngineError.Code.OVER_BUDGET)
	_assert_rejected(engine, null, EngineError.Code.MALFORMED)
	assert_int(engine.accepted_action_count()).is_equal(7)


func test_accepted_actions_are_recorded_in_order() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	_pass(engine)
	# Rejected (the first committer again), so it is not recorded.
	var rejected: ApplyResult = engine.apply(EngineAction.commit(first, _hand(engine, first)))
	assert_bool(rejected.ok).is_false()
	_pass(engine)
	var actions: Array[EngineAction] = engine.accepted_actions()
	assert_int(actions.size()).is_equal(2)
	assert_int(actions[0].seat).is_equal(first)
	assert_int(actions[1].seat).is_equal(1 - first)
	assert_int(_state_int(engine, "actions_applied")).is_equal(2)


func test_engine_source_never_prints_asserts_or_pushes_errors() -> void:
	# R27 by inspection: no engine script calls a print, assert or push function.
	var checked: int = 0
	for file_name: String in DirAccess.get_files_at(ENGINE_DIR):
		if not file_name.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string(ENGINE_DIR.path_join(file_name))
		assert_str(text).is_not_empty()
		for token: String in FORBIDDEN_CALLS:
			if text.contains(token):
				fail("%s contains %s" % [file_name, token])
		checked += 1
	assert_int(checked).is_greater_equal(5)


# --- Determinism ------------------------------------------------------------------------


## The awaited seat plays the highest-mask legal set: deterministic and card-heavy.
func _scripted_action(engine: MatchEngine) -> EngineAction:
	var seat: int = engine.awaited_seat()
	var sets: Array[Array] = LegalPlays.enumerate(_hand(engine, seat), engine.energy(), _db())
	return EngineAction.commit(seat, _typed(sets[sets.size() - 1]))


func test_same_seed_and_actions_give_equal_states_and_events() -> void:
	var a: MatchEngine = MatchEngine.create(SEED, _db())
	var b: MatchEngine = MatchEngine.create(SEED, _db())
	assert_array(_event_dicts(a.start().events)).is_equal(_event_dicts(b.start().events))
	assert_dict(a.full_state()).is_equal(b.full_state())
	# 20 actions span round 1 and the start of round 2.
	for _step: int in range(20):
		var action: EngineAction = _scripted_action(a)
		var ra: ApplyResult = a.apply(action)
		var rb: ApplyResult = b.apply(action)
		assert_bool(ra.ok).is_true()
		assert_bool(rb.ok).is_true()
		assert_array(_event_dicts(ra.events)).is_equal(_event_dicts(rb.events))
		assert_dict(a.full_state()).is_equal(b.full_state())
	assert_int(_state_int(a, "round")).is_equal(2)


func test_different_seeds_give_different_states() -> void:
	assert_dict(_started(1).full_state()).is_not_equal(_started(2).full_state())
