# gdlint: disable=max-public-methods
class_name TestTurn
extends GdUnitTestSuite
## MatchEngine core flow: R3-R4 (entry point, run to the next decision), R9 (instance
## ids), R11-R17 (round start, draw and burn, energy, two-step commit, the tied turn, turn
## order for turns 2-7), R26-R27 (every error code leaves the state and the accepted
## actions unchanged; the engine never prints). The action shapes (R5) are in
## test_engine_action.gd; the walk's reveals and scores (DC-05 R11-R17, which replace
## cycle 1's reveal interleave and summed flat) are in test_score_walk.gd. DC-05: R5-R8
## (positional commits, the second committer sees
## the first's slots, both commits merge into their rows at resolution), R9-R10 (per-seat
## budget, free first card), a choice with no prompt, the empty-slots default.
##
## Mid-match states come from scripted actions on known seeds, never from private fields,
## except the energy cases: nothing sets carry or free_first before DC-05 T04, so those
## two tests write them directly.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
const ENGINE_DIR: String = "res://engine"
const BOT_SCRIPT: String = "res://engine/bot/greedy_bot.gd"
const FORBIDDEN_CALLS: Array[String] = [
	"print(",
	"printerr(",
	"prints(",
	"printt(",
	"print_rich(",
	"print_verbose(",
	"printraw(",
	"print_debug(",
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


func _pending_slots(engine: MatchEngine) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state["pending_slots"]
	return _typed(raw)


func _energy_list(engine: MatchEngine, key: String) -> Array:
	var state: Dictionary = engine.full_state()
	var energy: Dictionary = state["energy"]
	var raw: Array = energy[key]
	return raw


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


## The first legal set of exactly `size` cards, or an empty list when none exists. Sets
## with no prompt-verb card come first (DC-05 T05): a prompt would pause the walk these
## flow tests expect to finish; when every set holds one, the first such set is used.
func _find_set(hand: Array[int], energy: int, size: int) -> Array[int]:
	var fallback: Array[int] = []
	for s: Array in LegalPlays.enumerate(hand, energy, _db()):
		if s.size() != size:
			continue
		var cards: Array[int] = _typed(s)
		if not _has_prompt_card(cards):
			return cards
		if fallback.is_empty():
			fallback = cards
	return fallback


## Whether any of `cards` carries an effect that may open a prompt.
func _has_prompt_card(cards: Array[int]) -> bool:
	for card: int in cards:
		var effect: CardEffect = _db().card_at(card % MatchRules.DECK_SIZE).effect
		if effect != null and Choice.needs_choice(effect.verb):
			return true
	return false


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


# --- R3: entry point -------------------------------------------------------------------


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
	# Both rows are empty: the walk starts (R11) and ends at once, with no pulse.
	var expected: Array[int] = [
		MatchEvent.Kind.COMMITTED,
		MatchEvent.Kind.WALK_STARTED,
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
	# No slots given on an empty row: the compatibility default resolves to slot 0.
	assert_array(_payload_ints(committed, "slots")).is_equal(_typed([0]))
	assert_array(_pending_slots(engine)).is_equal(_typed([0]))


# --- R16: scoring (the walk and its reveals: test_score_walk.gd) ----------------


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
	var concede_with_slots: EngineAction = EngineAction.concede(seat)
	concede_with_slots.slots.append(0)
	_assert_rejected(engine, concede_with_slots, EngineError.Code.MALFORMED)
	var choose_with_cards: EngineAction = EngineAction.choose(seat, 0, 0)
	choose_with_cards.cards.append(_hand(engine, seat)[0])
	_assert_rejected(engine, choose_with_cards, EngineError.Code.MALFORMED)
	_assert_rejected(engine, EngineAction.choose(2, 0, 0), EngineError.Code.MALFORMED)


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
	# R27 by inspection: no engine script calls a print, assert or push function. The
	# scan recurses, so subdirectories such as engine/bot/ are covered too.
	var scripts: Array[String] = _engine_scripts(ENGINE_DIR)
	for path: String in scripts:
		var text: String = FileAccess.get_file_as_string(path)
		assert_str(text).override_failure_message(path).is_not_empty()
		for token: String in FORBIDDEN_CALLS:
			if text.contains(token):
				fail("%s contains %s" % [path, token])
	assert_int(scripts.size()).is_greater_equal(5)
	# A scan that stops at the top level would miss the bot.
	assert_array(scripts).contains([BOT_SCRIPT])


## Every .gd path under `dir`, subdirectories included, in a stable order.
func _engine_scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.ends_with(".gd"):
			out.append(dir.path_join(file_name))
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_engine_scripts(dir.path_join(sub)))
	return out


# --- DC-05 R5-R8: positional commits and merged rows ---------------------------------


## The awaited seat commits the first legal set of `size` cards with no slots (append);
## false when it has none or the engine rejects it.
func _commit_size(engine: MatchEngine, size: int) -> bool:
	var seat: int = engine.awaited_seat()
	var cards: Array[int] = _find_set(_hand(engine, seat), engine.energy(), size)
	if cards.size() != size:
		return false
	return engine.apply(EngineAction.commit(seat, cards)).ok


## A started engine at round 1 turn 6, awaiting its first commit, with two cards on each
## row (both seats played two on turn 5), whose first committer can play two cards and
## second committer one; null when no seed in the search range allows it.
func _interleave_engine() -> MatchEngine:
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _started(match_seed)
		_pass_until_turn(engine, 5)
		if not (_commit_size(engine, 2) and _commit_size(engine, 2)):
			continue
		if engine.energy() != 6:
			continue
		var first: int = engine.awaited_seat()
		var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), 2)
		var b: Array[int] = _find_set(_hand(engine, 1 - first), engine.energy(), 1)
		if a.size() == 2 and b.size() == 1:
			return engine
	return null


func test_merged_rows_for_interleaved_first_and_second_commits() -> void:
	var engine: MatchEngine = _interleave_engine()
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var first: int = engine.awaited_seat()
	var second: int = 1 - first
	var old_first: Array[int] = _board(engine, first)
	var old_second: Array[int] = _board(engine, second)
	assert_int(old_first.size()).is_equal(2)
	assert_int(old_second.size()).is_equal(2)
	var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), 2)
	var b: Array[int] = _find_set(_hand(engine, second), engine.energy(), 1)
	# First committer: new cards at both ends of a 4-card row. Second: between its two.
	var a_slots: Array[int] = [0, 3]
	var b_slots: Array[int] = [1]
	var held: ApplyResult = engine.apply(EngineAction.commit(first, a, a_slots))
	assert_bool(held.ok).is_true()
	# Nothing is placed until the second commit (R8); the slots are held with the cards.
	assert_array(_board(engine, first)).is_equal(old_first)
	assert_array(_pending(engine)).is_equal(a)
	assert_array(_pending_slots(engine)).is_equal(a_slots)
	assert_array(_payload_ints(held.events[0], "slots")).is_equal(a_slots)
	# The second committer sees the slots but not the cards (R7).
	var waiting: SeatView = engine.view_for(second)
	assert_int(waiting.opponent_pending_count).is_equal(2)
	assert_array(waiting.opponent_pending_slots).is_equal(a_slots)
	assert_array(engine.view_for(first).opponent_pending_slots).is_empty()
	var redacted: MatchEvent = held.events[0].redacted_for(second)
	assert_array(_payload_ints(redacted, "slots")).is_equal(a_slots)
	assert_array(_payload_ints(redacted, "cards")).is_equal(
		_typed([MatchEvent.HIDDEN_CARD, MatchEvent.HIDDEN_CARD])
	)
	var result: ApplyResult = engine.apply(EngineAction.commit(second, b, b_slots))
	assert_bool(result.ok).is_true()
	var first_row: Array[int] = [a[0], old_first[0], old_first[1], a[1]]
	var second_row: Array[int] = [old_second[0], b[0], old_second[1]]
	assert_array(_board(engine, first)).is_equal(first_row)
	assert_array(_board(engine, second)).is_equal(second_row)
	assert_array(_pending(engine)).is_empty()
	assert_array(_pending_slots(engine)).is_empty()
	# Reveals keep the alternation, each carrying its final slot.
	var reveals: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.CARD_REVEALED)
	var expected_cards: Array[int] = [a[0], b[0], a[1]]
	var expected_slots: Array[int] = [0, 1, 3]
	assert_int(reveals.size()).is_equal(3)
	for i: int in range(reveals.size()):
		assert_int(_payload_int(reveals[i], "card")).is_equal(expected_cards[i])
		assert_int(_payload_int(reveals[i], "slot")).is_equal(expected_slots[i])
	# Both rows are revealed in full; the log holds the slots as given.
	var state: Dictionary = engine.full_state()
	var revealed: Array = state["revealed"]
	var first_revealed: Array = revealed[first]
	var first_sorted: Array[int] = _typed(first_row)
	first_sorted.sort()
	assert_array(_typed(first_revealed)).is_equal(first_sorted)
	var actions: Array[EngineAction] = engine.accepted_actions()
	assert_array(actions[actions.size() - 2].slots).is_equal(a_slots)
	assert_array(actions[actions.size() - 1].slots).is_equal(b_slots)


func test_empty_slots_resolve_to_the_right_end_and_are_logged() -> void:
	var engine: MatchEngine = _interleave_engine()
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var first: int = engine.awaited_seat()
	var old_first: Array[int] = _board(engine, first)
	var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), 2)
	var result: ApplyResult = engine.apply(EngineAction.commit(first, a))
	assert_bool(result.ok).is_true()
	var appended: Array[int] = [2, 3]
	assert_array(_pending_slots(engine)).is_equal(appended)
	assert_array(_payload_ints(result.events[0], "slots")).is_equal(appended)
	var actions: Array[EngineAction] = engine.accepted_actions()
	assert_array(actions[actions.size() - 1].slots).is_equal(appended)
	var entry: Dictionary = engine.action_log().actions[actions.size() - 1].to_dict()
	var logged: Array = entry["p"]
	assert_array(_typed(logged)).is_equal(appended)
	_pass(engine)
	assert_array(_board(engine, first)).is_equal(_typed(old_first + a))


func test_bad_slots_are_rejected_and_change_nothing() -> void:
	var engine: MatchEngine = _interleave_engine()
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var first: int = engine.awaited_seat()
	var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), 2)
	var cases: Array[Array] = [[0, 4], [-1, 0], [2, 2], [3, 1], [0], [0, 1, 2]]
	for slots: Array in cases:
		var action: EngineAction = EngineAction.commit(first, a, _typed(slots))
		_assert_rejected(engine, action, EngineError.Code.BAD_SLOTS)
	# Also while the second committer is awaited.
	assert_bool(engine.apply(EngineAction.commit(first, a, _typed([0, 3]))).ok).is_true()
	var second: int = engine.awaited_seat()
	var b: Array[int] = _find_set(_hand(engine, second), engine.energy(), 1)
	_assert_rejected(
		engine, EngineAction.commit(second, b, _typed([3])), EngineError.Code.BAD_SLOTS
	)
	var none: Array[int] = []
	_assert_rejected(
		engine, EngineAction.commit(second, none, _typed([0])), EngineError.Code.BAD_SLOTS
	)


# --- DC-05 R31: a choice with no prompt open (the rest in test_choices.gd) -------------


func test_choose_without_a_prompt_is_rejected() -> void:
	var engine: MatchEngine = _started(SEED)
	var seat: int = engine.awaited_seat()
	_assert_rejected(engine, EngineAction.choose(seat, 0, 0), EngineError.Code.NO_PROMPT)
	_assert_rejected(engine, EngineAction.choose(1 - seat, 1, 2), EngineError.Code.NO_PROMPT)


# --- DC-05 R9, R10: per-seat budget ---------------------------------------------------


func test_budget_is_the_turn_plus_carry() -> void:
	var engine: MatchEngine = _started(SEED)
	assert_int(engine.budget_for(2)).is_equal(0)
	for turn: int in range(1, 4):
		for seat: int in range(2):
			assert_int(engine.budget_for(seat)).is_equal(turn)
			assert_int(engine.view_for(seat).budgets[seat]).is_equal(turn)
			assert_int(engine.view_for(seat).budgets[1 - seat]).is_equal(turn)
			assert_int(engine.view_for(seat).energy).is_equal(turn)
		_pass(engine)
		var result: ApplyResult = _pass(engine)
		var started: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)[0]
		assert_array(_payload_ints(started, "budgets")).is_equal(_typed([turn + 1, turn + 1]))
	# Nothing carries before T04; a carry written directly raises only that seat's budget
	# and lets it commit above the turn number.
	_pass_until_turn(engine, MatchRules.TURNS)
	var seat_first: int = engine.awaited_seat()
	var hand: Array[int] = _hand(engine, seat_first)
	var cost: int = LegalPlays.total_cost(hand, _db())
	assert_int(cost).is_greater(MatchRules.TURNS)
	_assert_rejected(engine, EngineAction.commit(seat_first, hand), EngineError.Code.OVER_BUDGET)
	engine._state.energy.carry[seat_first] = cost - MatchRules.TURNS
	assert_int(engine.budget_for(seat_first)).is_equal(cost)
	assert_int(engine.budget_for(1 - seat_first)).is_equal(MatchRules.TURNS)
	assert_int(engine.view_for(seat_first).energy).is_equal(cost)
	assert_bool(engine.apply(EngineAction.commit(seat_first, hand)).ok).is_true()
	var spent: Array = _energy_list(engine, "spent")
	var first_spent: int = spent[seat_first]
	var other_spent: int = spent[1 - seat_first]
	assert_int(first_spent).is_equal(cost)
	assert_int(other_spent).is_equal(0)


func test_spent_is_recorded_and_the_free_first_card_is_consumed() -> void:
	# Turn 1 (budget 1): find a seed whose first committer holds a card costing 2 or more.
	var engine: MatchEngine = null
	var seat: int = -1
	var dear: int = -1
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var candidate: MatchEngine = _started(match_seed)
		var awaited: int = candidate.awaited_seat()
		for card: int in _hand(candidate, awaited):
			if LegalPlays.cost_of(card, _db()) >= 2:
				engine = candidate
				seat = awaited
				dear = card
				break
		if engine != null:
			break
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var cards: Array[int] = [dear]
	_assert_rejected(engine, EngineAction.commit(seat, cards), EngineError.Code.OVER_BUDGET)
	engine._state.energy.free_first[seat] = true
	assert_bool(engine.apply(EngineAction.commit(seat, cards)).ok).is_true()
	# The free card cost nothing and is consumed by the commit (plan P7).
	var spent: Array = _energy_list(engine, "spent")
	var free_first: Array = _energy_list(engine, "free_first")
	var seat_spent: int = spent[seat]
	var seat_free: bool = free_first[seat]
	assert_int(seat_spent).is_equal(0)
	assert_bool(seat_free).is_false()


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
