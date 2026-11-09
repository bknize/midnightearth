# gdlint: disable=max-public-methods,max-file-lines
class_name TestEngine
extends GdUnitTestSuite
## MatchEngine core flow under rules 7 (cycle 9 plan P14; DC-13 T03, was test_turn.gd):
## the entry point and running to the next decision, instance ids, Match start (Decks
## shuffled once, four cards dealt once), the draws, the Budget (Turn + grants, nothing
## carries, R6, R7) and the Cost with Memory reductions (R8, R9), the two-step Commit with
## its discard-down, the tied Turn and the turn order, every error code leaving the state
## and the accepted actions unchanged, and the engine never printing. The action shapes are
## in test_engine_action.gd, the Walk in test_score_walk.gd, the Turn's own rules in
## test_turn_flow.gd. DC-05: positional commits, the second committer sees the first's
## slots, both commits merge into their rows. DC-07: a deck per seat and MATCH_STARTED;
## every match here plays the fixture deck (40 plain bodies) on both seats.
##
## Mid-match states come from scripted actions on known seeds. A pass usually leaves five
## cards against a Hand size of four, so _pass() answers the discard-down it opens with the
## first card (FixtureDecks.discard_answer). The Energy and Memory cases write a grant, the
## free first card or a cost change directly, as no T03 card does.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
const ENGINE_DIR: String = "res://engine"
const BOT_SCRIPT: String = "res://engine/bot/random_bot.gd"
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
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## The fixture-vs-fixture definitions over _db() (DC-07 T02), for the MatchCards APIs.
func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	engine.start()
	return engine


func _seat_list(engine: MatchEngine, key: String, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var per_seat: Array = state[key]
	var raw: Array = per_seat[seat]
	return Typed.ints(raw)


func _hand(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "hand", seat)


func _deck(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "deck", seat)


func _board(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "board", seat)


func _pile(engine: MatchEngine, seat: int) -> Array[int]:
	return _seat_list(engine, "pile", seat)


func _pending(engine: MatchEngine) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state["pending"]
	return Typed.ints(raw)


func _pending_slots(engine: MatchEngine) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state["pending_slots"]
	return Typed.ints(raw)


func _energy_list(engine: MatchEngine, key: String) -> Array:
	var state: Dictionary = engine.full_state()
	var energy: Dictionary = state["energy"]
	var raw: Array = energy[key]
	return raw


func _scores(engine: MatchEngine) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state["scores"]
	return Typed.ints(raw)


func _state_int(engine: MatchEngine, key: String) -> int:
	var state: Dictionary = engine.full_state()
	var value: int = state[key]
	return value


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _payload_ints(event: MatchEvent, key: String) -> Array[int]:
	var raw: Array = event.payload[key]
	return Typed.ints(raw)


## The awaited seat passes; when that opens its discard-down, the first `exact` hand cards
## answer it. One result with both actions' events (a failure as soon as one is rejected).
func _pass(engine: MatchEngine) -> ApplyResult:
	var none: Array[int] = []
	var passed: ApplyResult = engine.apply(EngineAction.commit(engine.awaited_seat(), none))
	return _then_discard(engine, passed)


## `result`, followed by the answer to a discard-down it left open, as one result.
func _then_discard(engine: MatchEngine, result: ApplyResult) -> ApplyResult:
	var answer: EngineAction = FixtureDecks.discard_answer(engine)
	if not result.ok or answer == null:
		return result
	var answered: ApplyResult = engine.apply(answer)
	if not answered.ok:
		return answered
	var events: Array[MatchEvent] = []
	events.append_array(result.events)
	events.append_array(answered.events)
	return ApplyResult.success(events)


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


## The first legal set of exactly `size` cards, or an empty list when none exists. The
## fixture's cards are plain bodies (DC-13 T02), so no set opens a prompt.
func _find_set(hand: Array[int], energy: int, size: int) -> Array[int]:
	for s: Array in LegalPlays.enumerate(hand, energy, _defs()):
		if s.size() == size:
			return Typed.ints(s)
	var none: Array[int] = []
	return none


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
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	assert_int(started.error).is_equal(EngineError.Code.NONE)
	assert_array(started.events).is_not_empty()
	var none: Array[int] = []
	var applied: ApplyResult = engine.apply(EngineAction.commit(engine.awaited_seat(), none))
	assert_bool(applied.ok).is_true()
	assert_int(applied.error).is_equal(EngineError.Code.NONE)
	assert_int(engine.accepted_action_count()).is_equal(1)
	assert_int(_state_int(engine, "actions_applied")).is_equal(1)


# --- R10: Match start -----------------------------------------------------------------


## Match start (R10): MATCH_STARTED, four cards dealt to each seat once, Round 1 (public
## {round, sudden_death}), Turn 1 (its first committer the coin's) and one draw per seat.
func test_match_start_deals_four_then_round_one_draws_one() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	var result: ApplyResult = engine.start()
	var expected: Array[int] = [MatchEvent.Kind.MATCH_STARTED]
	for _i: int in range(2 * MatchRules.OPENING_HAND):
		expected.append(MatchEvent.Kind.CARD_DEALT)
	expected.append(MatchEvent.Kind.ROUND_STARTED)
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
		assert_array(_pile(engine, seat)).is_empty()
	assert_int(_state_int(engine, "round")).is_equal(1)
	assert_int(_state_int(engine, "turn")).is_equal(1)
	assert_int(engine.energy()).is_equal(1)
	var round_started: MatchEvent = _of_kind(result.events, MatchEvent.Kind.ROUND_STARTED)[0]
	assert_dict(round_started.payload).is_equal({"round": 1, "sudden_death": false})
	var turn_started: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)[0]
	assert_int(engine.awaited_seat()).is_equal(_payload_int(turn_started, "first_seat"))
	var keys: Array = turn_started.payload.keys()
	keys.sort()
	# `free_first` per seat since rules 9 (cycle 14 R16).
	assert_array(keys).is_equal(["budgets", "first_seat", "free_first", "round", "turn"])


func test_deal_events_are_private_to_their_seat() -> void:
	var result: ApplyResult = FixtureDecks.engine(SEED, _db()).start()
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
		assert_array(_hand(engine, 0)).is_equal(Typed.ints(deck0.slice(0, top)))
		assert_array(_deck(engine, 0)).is_equal(Typed.ints(deck0.slice(top)))
		assert_array(_hand(engine, 1)).is_equal(Typed.ints(deck1.slice(0, top)))
		assert_array(_deck(engine, 1)).is_equal(Typed.ints(deck1.slice(top)))
		assert_int(engine.awaited_seat()).is_equal(coin)
		assert_int(_state_int(engine, "rng_state")).is_equal(rng.state)


func test_instance_ids_unique_across_seats() -> void:
	var engine: MatchEngine = _started(SEED)
	for seat: int in range(2):
		var all: Array[int] = Typed.ints(_hand(engine, seat) + _deck(engine, seat))
		all.sort()
		assert_array(all).is_equal(_ids(seat))


## Rules 7 (R10, R17, R2): the next Round deals nothing and refills no Deck; the rows went
## to the Piles. Passing turns 1-6 discards one card a turn (five held against four); on
## Turn 7 each seat commits one card, which the Round end Discards. Round 2's Turn 1 then
## draws one: hands of five, Decks of 40 - 4 - 8, Piles of seven, every id still the seat's.
func test_next_round_keeps_hands_decks_and_piles() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, MatchRules.TURNS)
	var first: int = engine.awaited_seat()
	var played: Array[int] = []
	var a: Array[int] = _find_set(_hand(engine, first), MatchRules.TURNS, 1)
	played.append_array(a)
	assert_bool(engine.apply(EngineAction.commit(first, a)).ok).is_true()
	var second: int = engine.awaited_seat()
	var b: Array[int] = _find_set(_hand(engine, second), MatchRules.TURNS, 1)
	played.append_array(b)
	var result: ApplyResult = engine.apply(EngineAction.commit(second, b))
	assert_bool(result.ok).is_true()
	assert_array(_of_kind(result.events, MatchEvent.Kind.CARD_DEALT)).is_empty()
	var started: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(started.size()).is_equal(1)
	assert_int(_payload_int(started[0], "round")).is_equal(2)
	assert_int(_state_int(engine, "round")).is_equal(2)
	assert_int(_state_int(engine, "turn")).is_equal(1)
	assert_array(_pending(engine)).is_empty()
	for seat: int in range(2):
		assert_array(_board(engine, seat)).is_empty()
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.HAND_SIZE + 1)
		assert_int(_deck(engine, seat).size()).is_equal(
			MatchRules.DECK_SIZE - MatchRules.OPENING_HAND - MatchRules.TURNS - 1
		)
		var pile: Array[int] = _pile(engine, seat)
		assert_int(pile.size()).is_equal(MatchRules.TURNS)
		var all: Array[int] = Typed.ints(_hand(engine, seat) + _deck(engine, seat) + pile)
		all.sort()
		assert_array(all).is_equal(_ids(seat))
	for card: int in played:
		assert_bool(_pile(engine, card / MatchRules.DECK_SIZE).has(card)).is_true()
	var scores: Array[int] = _scores(engine)
	assert_array(scores).is_equal(Typed.ints([0, 0]))


# --- R4: run to the next decision point -----------------------------------------------


## A first Pass on five cards opens that seat's discard-down (R13); its answer hands the
## Turn to the second committer.
func test_first_commit_stops_at_its_discard_down_then_the_second_committer() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	var none: Array[int] = []
	var result: ApplyResult = engine.apply(EngineAction.commit(first, none))
	var expected: Array[int] = [MatchEvent.Kind.COMMITTED, MatchEvent.Kind.PROMPT_OPENED]
	assert_array(_kinds(result.events)).is_equal(expected)
	assert_int(engine.awaited_seat()).is_equal(first)
	var answered: ApplyResult = engine.apply(FixtureDecks.discard_answer(engine))
	expected = [MatchEvent.Kind.CHOICE_MADE, MatchEvent.Kind.CARD_DISCARDED]
	assert_array(_kinds(answered.events)).is_equal(expected)
	assert_int(engine.awaited_seat()).is_equal(1 - first)


func test_second_commit_runs_into_the_next_turn() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass(engine)
	var result: ApplyResult = _pass(engine)
	# Both rows are empty: after the second seat's discard-down the Walk starts and ends at
	# once, with no pulse, and the next Turn draws.
	var expected: Array[int] = [
		MatchEvent.Kind.COMMITTED,
		MatchEvent.Kind.PROMPT_OPENED,
		MatchEvent.Kind.CHOICE_MADE,
		MatchEvent.Kind.CARD_DISCARDED,
		MatchEvent.Kind.WALK_STARTED,
		MatchEvent.Kind.WALK_ENDED,
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
	# The first seat draws first (R4).
	var first: int = _state_int(engine, "first_seat")
	var decks: Array = [deck0, deck1]
	for at: int in range(2):
		var seat: int = first if at == 0 else 1 - first
		var deck: Array[int] = decks[seat]
		assert_int(_payload_int(drawn[at], "seat")).is_equal(seat)
		assert_int(_payload_int(drawn[at], "card")).is_equal(deck[0])
	for seat: int in range(2):
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.HAND_SIZE + 1)


## Rules 7: there is no hand cap and no burn. Passing every turn, each hand holds its Hand
## size plus the Turn's draw, the discard-down sending one card a Turn to the Pile.
func test_passing_discards_down_and_never_burns() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, MatchRules.TURNS)
	for seat: int in range(2):
		assert_int(_hand(engine, seat).size()).is_equal(MatchRules.HAND_SIZE + 1)
		assert_int(_pile(engine, seat).size()).is_equal(MatchRules.TURNS - 1)
		assert_int(_deck(engine, seat).size()).is_equal(
			MatchRules.DECK_SIZE - MatchRules.OPENING_HAND - MatchRules.TURNS
		)
	assert_bool(MatchEvent.Kind.keys().has("CARD_BURNED")).is_false()


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
		# Passing never banks Energy: the next Turn's Budget is just its number, plus the
		# fixture's Engineer from Turn 3 (DC-13 T07).
		var engineer: int = 1 if turn + 1 >= 3 else 0
		var budgets: Array[int] = [turn + 1 + engineer, turn + 1 + engineer]
		assert_array(_payload_ints(started[0], "budgets")).is_equal(budgets)


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
	assert_array(_payload_ints(committed, "slots")).is_equal(Typed.ints([0]))
	assert_array(_pending_slots(engine)).is_equal(Typed.ints([0]))


# --- R16: scoring (the walk and its reveals: test_score_walk.gd) ----------------


func test_tied_turn_has_no_winner() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass(engine)
	var result: ApplyResult = _pass(engine)
	var ended: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_ENDED)[0]
	assert_int(_payload_int(ended, "winner")).is_equal(-1)
	assert_array(_payload_ints(ended, "scores")).is_equal(Typed.ints([0, 0]))
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
	# An 8-card hand holds a card of cost <= 4 (only 12 of the 40 cost more).
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
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_int(engine.awaited_seat()).is_equal(-1)
	var none: Array[int] = []
	_assert_rejected(engine, EngineAction.commit(0, none), EngineError.Code.NOT_STARTED)
	_assert_rejected(engine, EngineAction.concede(1), EngineError.Code.NOT_STARTED)


func test_card_data_invalid_refuses_to_start() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, CardDb.from_json("{}"))
	var before: Dictionary = engine.full_state()
	var result: ApplyResult = engine.start()
	assert_bool(result.ok).is_false()
	assert_int(result.error).is_equal(EngineError.Code.CARD_DATA_INVALID)
	assert_array(result.events).is_empty()
	assert_dict(engine.full_state()).is_equal(before)
	assert_int(engine.awaited_seat()).is_equal(-1)
	_assert_rejected(engine, EngineAction.concede(0), EngineError.Code.NOT_STARTED)
	var null_db: MatchEngine = FixtureDecks.engine(SEED, null)
	assert_int(null_db.start().error).is_equal(EngineError.Code.CARD_DATA_INVALID)
	var no_list: MatchEngine = MatchEngine.create(
		SEED, _db(), null, FixtureDecks.ids(), FixtureDecks.crew()
	)
	assert_int(no_list.start().error).is_equal(EngineError.Code.CARD_DATA_INVALID)


# --- DC-07 R5, R6, P2, P14: decks per seat ----------------------------------------------


## An id the deck list does not hold, on either seat, makes start() fail with DECK_UNKNOWN
## and change nothing; so does a `deck_ids` that does not name one deck per seat.
func test_unknown_deck_id_fails_start_with_deck_unknown() -> void:
	var cases: Array[Array] = [["nope", "fixture"], ["fixture", "nope"], ["fixture"], []]
	for raw: Array in cases:
		var ids: Array[String] = []
		ids.assign(raw)
		var engine: MatchEngine = MatchEngine.create(
			SEED, _db(), FixtureDecks.decks(), ids, FixtureDecks.crew()
		)
		var before: Dictionary = engine.full_state()
		var result: ApplyResult = engine.start()
		var label: String = "ids %s" % [raw]
		assert_bool(result.ok).override_failure_message(label).is_false()
		assert_int(result.error).override_failure_message(label).is_equal(
			EngineError.Code.DECK_UNKNOWN
		)
		assert_array(result.events).is_empty()
		assert_dict(engine.full_state()).is_equal(before)
		assert_int(engine.awaited_seat()).is_equal(-1)
		_assert_rejected(engine, EngineAction.concede(0), EngineError.Code.NOT_STARTED)


## A named deck is kept; an empty id resolves to the seed's own pick (P14), and the
## resolved ids are what deck_ids(), the full state and MATCH_STARTED hold.
func test_deck_ids_resolve_and_open_the_match() -> void:
	var decks: DeckList = FixtureDecks.decks()
	var seeded: Array[String] = ["", ""]
	for match_seed: int in [1, 2, 77]:
		var engine: MatchEngine = MatchEngine.create(
			match_seed, _db(), decks, seeded, FixtureDecks.crew()
		)
		var expected: Array[String] = [
			decks.seeded_pick(match_seed, 0), decks.seeded_pick(match_seed, 1)
		]
		assert_array(engine.deck_ids()).is_equal(expected)
		var result: ApplyResult = engine.start()
		assert_bool(result.ok).is_true()
		var opened: MatchEvent = result.events[0]
		assert_int(opened.kind).is_equal(MatchEvent.Kind.MATCH_STARTED)
		assert_int(opened.owner_seat).is_equal(MatchEvent.PUBLIC)
		var shown: Array = opened.payload["decks"]
		assert_array(shown).is_equal(["fixture", "fixture"])
		var state: Dictionary = engine.full_state()
		var held: Array = state["deck_ids"]
		assert_array(held).is_equal(["fixture", "fixture"])
	var named: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_array(named.deck_ids()).is_equal(FixtureDecks.ids())
	assert_int(_of_kind(named.start().events, MatchEvent.Kind.MATCH_STARTED).size()).is_equal(1)


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


## R9: a Commit over the Budget is rejected and changes nothing. Turn 1: five cards cost at
## least 5. Turn 3: five cards cost at least 5.
func test_over_budget() -> void:
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
	var one: Array[int] = _find_set(_hand(engine, first), 4, 1)
	assert_array(one).is_not_empty()
	engine.apply(EngineAction.commit(first, one))
	var second: int = engine.awaited_seat()
	assert_int(second).is_equal(1 - first)
	var hand: Array[int] = _hand(engine, second)
	var twice: Array[int] = [hand[0], hand[0]]
	var none: Array[int] = []
	var count: int = engine.accepted_action_count()
	_assert_rejected(engine, EngineAction.commit(first, none), EngineError.Code.WRONG_SEAT)
	_assert_rejected(engine, EngineAction.commit(second, twice), EngineError.Code.DUPLICATE_CARD)
	_assert_rejected(engine, EngineAction.commit(second, hand), EngineError.Code.OVER_BUDGET)
	_assert_rejected(engine, null, EngineError.Code.MALFORMED)
	assert_int(engine.accepted_action_count()).is_equal(count)


## Accepted actions are recorded in order, the discard-down answers among them; a rejected
## one is not.
func test_accepted_actions_are_recorded_in_order() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	_pass(engine)
	# Rejected (the first committer again), so it is not recorded.
	var rejected: ApplyResult = engine.apply(EngineAction.commit(first, _hand(engine, first)))
	assert_bool(rejected.ok).is_false()
	_pass(engine)
	var actions: Array[EngineAction] = engine.accepted_actions()
	assert_int(actions.size()).is_equal(4)
	var kinds: Array[int] = [
		EngineAction.Kind.COMMIT,
		EngineAction.Kind.CHOOSE_SET,
		EngineAction.Kind.COMMIT,
		EngineAction.Kind.CHOOSE_SET,
	]
	var seats: Array[int] = [first, first, 1 - first, 1 - first]
	for at: int in range(actions.size()):
		assert_int(actions[at].kind).is_equal(kinds[at])
		assert_int(actions[at].seat).is_equal(seats[at])
	assert_int(_state_int(engine, "actions_applied")).is_equal(4)


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


## Opens a prompt by hand on the started `engine` for `seat`, carrying `resume` and `step`,
## and declines it through apply(). Returns the kinds of the events that sent out.
func _resume_kinds(engine: MatchEngine, resume: String, step: String, seat: int) -> Array[int]:
	engine._state.prompt = {
		Abilities.KEY_SEAT: seat,
		Abilities.KEY_CARD: -1,
		Abilities.KEY_VERB: "test",
		Choice.KEY_ZONE: Choice.zone_name(Choice.Zone.OWN_HAND),
		Choice.KEY_OPTIONS: [],
		Choice.KEY_MULTI: false,
		Choice.KEY_OPTIONAL: true,
		Choice.KEY_RESUME: resume,
		Choice.KEY_STEP: step,
		Choice.KEY_CREW: "",
	}
	engine._state.phase = MatchState.Phase.AWAIT_CHOICE
	var result: ApplyResult = engine.apply(EngineAction.decline(seat))
	assert_bool(result.ok).is_true()
	var kinds: Array[int] = []
	for event: MatchEvent in result.events:
		kinds.append(event.kind)
	return kinds


## NSC-177, T08 N4: every resume a prompt can carry takes the match on from the right step, so
## an answered prompt never leaves it awaiting nobody (no engine error path, R27). Read from
## what each one does: a branch missing from MatchEngine._resume_after sends none of these
## events and, after _answer, leaves the phase AWAIT_SECOND.
func test_every_resume_has_a_branch_in_the_engine() -> void:
	assert_int(Choice.RESUMES.size()).is_equal(5)
	var ended: int = MatchEvent.Kind.TURN_ENDED
	var walk_ended: int = MatchEvent.Kind.WALK_ENDED
	var round_ended: int = MatchEvent.Kind.ROUND_ENDED

	var start: MatchEngine = _started(SEED)
	var seat: int = start._state.first_seat
	var kinds: Array[int] = _resume_kinds(
		start, Choice.RESUME_TURN_START, TurnFlow.STEP_ON_START, seat
	)
	assert_bool(kinds.has(ended)).is_false()
	assert_int(start._state.phase).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_int(start.awaited_seat()).is_equal(seat)

	# The second seat's Commit is done (a discard drain, so no discard-down): the Walk starts.
	var commit: MatchEngine = _started(SEED)
	seat = 1 - commit._state.first_seat
	kinds = _resume_kinds(commit, Choice.RESUME_COMMIT, TurnFlow.STEP_SECOND_DISCARD, seat)
	assert_bool(kinds.has(MatchEvent.Kind.WALK_STARTED)).is_true()
	assert_int(commit.awaited_seat()).is_greater_equal(0)

	var walk: MatchEngine = _started(SEED)
	ScoreWalk.begin(walk._state)
	seat = walk._state.first_seat
	kinds = _resume_kinds(walk, Choice.RESUME_WALK, ScoreWalk.STEP_SCORE, seat)
	assert_bool(kinds.has(walk_ended)).is_true()
	assert_bool(kinds.has(ended)).is_true()
	assert_bool(kinds.has(MatchEvent.Kind.WALK_STARTED)).is_false()
	assert_int(walk.awaited_seat()).is_greater_equal(0)

	var turn_end: MatchEngine = _started(SEED)
	seat = turn_end._state.first_seat
	kinds = _resume_kinds(turn_end, Choice.RESUME_TURN_END, TurnFlow.STEP_TURN_END_AFTER, seat)
	assert_bool(kinds.has(ended)).is_true()
	assert_bool(kinds.has(walk_ended)).is_false()
	assert_bool(kinds.has(round_ended)).is_false()
	assert_int(turn_end.awaited_seat()).is_greater_equal(0)

	var round_end: MatchEngine = _started(SEED)
	seat = round_end._state.first_seat
	kinds = _resume_kinds(round_end, Choice.RESUME_ROUND_END, TurnFlow.STEP_ROUND_END, seat)
	assert_bool(kinds.has(round_ended)).is_true()
	assert_bool(kinds.has(ended)).is_false()
	assert_bool(kinds.has(MatchEvent.Kind.ROUND_STARTED)).is_true()
	assert_int(round_end.awaited_seat()).is_greater_equal(0)


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
		Typed.ints([MatchEvent.HIDDEN_CARD, MatchEvent.HIDDEN_CARD])
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
	var first_sorted: Array[int] = Typed.ints(first_row)
	first_sorted.sort()
	assert_array(Typed.ints(first_revealed)).is_equal(first_sorted)
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
	assert_array(Typed.ints(logged)).is_equal(appended)
	_pass(engine)
	assert_array(_board(engine, first)).is_equal(Typed.ints(old_first + a))


func test_bad_slots_are_rejected_and_change_nothing() -> void:
	var engine: MatchEngine = _interleave_engine()
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var first: int = engine.awaited_seat()
	var a: Array[int] = _find_set(_hand(engine, first), engine.energy(), 2)
	var cases: Array[Array] = [[0, 4], [-1, 0], [2, 2], [3, 1], [0], [0, 1, 2]]
	for slots: Array in cases:
		var action: EngineAction = EngineAction.commit(first, a, Typed.ints(slots))
		_assert_rejected(engine, action, EngineError.Code.BAD_SLOTS)
	# Also while the second committer is awaited.
	assert_bool(engine.apply(EngineAction.commit(first, a, Typed.ints([0, 3]))).ok).is_true()
	var second: int = engine.awaited_seat()
	var b: Array[int] = _find_set(_hand(engine, second), engine.energy(), 1)
	_assert_rejected(
		engine, EngineAction.commit(second, b, Typed.ints([3])), EngineError.Code.BAD_SLOTS
	)
	var none: Array[int] = []
	_assert_rejected(
		engine, EngineAction.commit(second, none, Typed.ints([0])), EngineError.Code.BAD_SLOTS
	)


# --- DC-05 R31: a choice with no prompt open (the rest in test_choices.gd) -------------


func test_choose_without_a_prompt_is_rejected() -> void:
	var engine: MatchEngine = _started(SEED)
	var seat: int = engine.awaited_seat()
	_assert_rejected(engine, EngineAction.choose(seat, 0, 0), EngineError.Code.NO_PROMPT)
	_assert_rejected(engine, EngineAction.choose(1 - seat, 1, 2), EngineError.Code.NO_PROMPT)


# --- DC-05 R9, R10: per-seat budget ---------------------------------------------------


## R6, R7 (cycle 9 plan P14): the Budget on Turn N is N plus the Energy granted for that
## Turn, and nothing carries; the fixture's Engineer adds 1 from Turn 3 (DC-13 T07). Turn
## 5's Budget is 5 + 1 for both seats (TURN_STARTED, views); a grant of 1 to one seat makes
## its Budget 7 and lets it commit a card costing 7; the grant is gone at turn end and
## unspent Energy is lost, so Turn 6's Budget is 6 + 1 for both.
func test_budget_on_turn_5_is_5_with_a_grant_6_and_nothing_carries() -> void:
	var engine: MatchEngine = _started(SEED)
	assert_int(engine.budget_for(2)).is_equal(0)
	_pass_until_turn(engine, 5)
	for seat: int in range(2):
		assert_int(engine.budget_for(seat)).is_equal(6)
		assert_int(engine.view_for(seat).budgets[seat]).is_equal(6)
		assert_int(engine.view_for(seat).budgets[1 - seat]).is_equal(6)
		assert_int(engine.view_for(seat).energy).is_equal(6)
	var energy_state: Dictionary = engine.full_state()["energy"]
	assert_bool(energy_state.has("carry")).is_false()
	var first: int = engine.awaited_seat()
	engine._state.energy.grants[first] = 1
	assert_int(engine.budget_for(first)).is_equal(7)
	assert_int(engine.budget_for(1 - first)).is_equal(6)
	assert_int(engine.view_for(first).energy).is_equal(7)
	# A cost-7 card enters the first seat's hand (fixture f19 of its own deck).
	var dear: int = first * MatchRules.DECK_SIZE + 18
	assert_int(LegalPlays.cost_of(dear, _defs())).is_equal(7)
	var piles: MatchState.SeatPiles = engine._state.seats[first]
	piles.deck.erase(dear)
	piles.pile.erase(dear)
	if not piles.hand.has(dear):
		piles.hand.append(dear)
	var cards: Array[int] = [dear]
	var result: ApplyResult = _then_discard(engine, engine.apply(EngineAction.commit(first, cards)))
	assert_bool(result.ok).is_true()
	var committed: MatchEvent = _of_kind(result.events, MatchEvent.Kind.COMMITTED)[0]
	assert_int(_payload_int(committed, "cost")).is_equal(7)
	var spent: Array = _energy_list(engine, "spent")
	var first_spent: int = spent[first]
	assert_int(first_spent).is_equal(7)
	var ended: ApplyResult = _pass(engine)
	var started: MatchEvent = _of_kind(ended.events, MatchEvent.Kind.TURN_STARTED)[0]
	assert_int(_payload_int(started, "turn")).is_equal(6)
	assert_array(_payload_ints(started, "budgets")).is_equal(Typed.ints([7, 7]))
	var grants: Array = _energy_list(engine, "grants")
	assert_array(grants).is_equal([0, 0])


## R8, R9: a Commit's Cost reads Memory. A cost-3 card is over a Budget of 2; with Memory
## -1 it commits on that Budget, paying 2.
func test_a_cost_3_card_with_memory_minus_1_commits_on_budget_2() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 2)
	var first: int = engine.awaited_seat()
	assert_int(engine.budget_for(first)).is_equal(2)
	var card: int = first * MatchRules.DECK_SIZE + 8
	assert_int(LegalPlays.cost_of(card, _defs())).is_equal(3)
	var piles: MatchState.SeatPiles = engine._state.seats[first]
	piles.deck.erase(card)
	piles.pile.erase(card)
	if not piles.hand.has(card):
		piles.hand.append(card)
	var cards: Array[int] = [card]
	_assert_rejected(engine, EngineAction.commit(first, cards), EngineError.Code.OVER_BUDGET)
	engine._state.memory_for(card).cost_delta = -1
	assert_int(engine.view_for(first).own_hand_costs[piles.hand.find(card)]).is_equal(2)
	var result: ApplyResult = engine.apply(EngineAction.commit(first, cards))
	assert_bool(result.ok).is_true()
	var committed: MatchEvent = _of_kind(result.events, MatchEvent.Kind.COMMITTED)[0]
	assert_int(_payload_int(committed, "cost")).is_equal(2)
	var spent: Array = _energy_list(engine, "spent")
	var first_spent: int = spent[first]
	assert_int(first_spent).is_equal(2)


func test_spent_is_recorded_and_the_free_first_card_is_consumed() -> void:
	# Turn 1 (budget 1): find a seed whose first committer holds a card costing 2 or more.
	var engine: MatchEngine = null
	var seat: int = -1
	var dear: int = -1
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var candidate: MatchEngine = _started(match_seed)
		var awaited: int = candidate.awaited_seat()
		for card: int in _hand(candidate, awaited):
			if LegalPlays.cost_of(card, _defs()) >= 2:
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


## The awaited seat plays the highest-mask legal set: deterministic and card-heavy. An open
## discard-down is answered with its first `exact` cards.
func _scripted_action(engine: MatchEngine) -> EngineAction:
	var answer: EngineAction = FixtureDecks.discard_answer(engine)
	if answer != null:
		return answer
	var seat: int = engine.awaited_seat()
	var sets: Array[Array] = LegalPlays.enumerate(_hand(engine, seat), engine.energy(), _defs())
	# The empty set (mask 0) is always listed.
	return EngineAction.commit(seat, Typed.ints(sets[sets.size() - 1]))


func test_same_seed_and_actions_give_equal_states_and_events() -> void:
	var a: MatchEngine = FixtureDecks.engine(SEED, _db())
	var b: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_array(_event_dicts(a.start().events)).is_equal(_event_dicts(b.start().events))
	assert_dict(a.full_state()).is_equal(b.full_state())
	# Round 1 and the start of round 2 (a Turn is two Commits and at most two discard-downs).
	for _step: int in range(40):
		if _state_int(a, "round") > 1:
			break
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


# --- DC-11 T08: Crew (cycle 8 R42, R43, plan P12, P13) ----------------------------------


## A Greed-vs-Ramp match over the shipped data (not started): seat 0 holds tallyman, void,
## engineer; seat 1 navigator, captain, dredger.
func _crew_engine() -> MatchEngine:
	var ids: Array[String] = ["greed", "ramp"]
	return MatchEngine.create(
		SEED, CardDb.load_default(), DeckList.load_default(), ids, CrewPool.load_default()
	)


func _crew_uses(engine: MatchEngine) -> Array:
	var state: Dictionary = engine.full_state()
	var raw: Array = state["crew_uses"]
	return raw


## Both seats' Crew ids of the Greed-vs-Ramp match, seat 0's first.
func _greed_ramp_crew() -> Array:
	return [["tallyman", "void", "engineer"], ["navigator", "captain", "dredger"]]


## MATCH_STARTED names both seats' Crew in slot order, seat 0's first, and is public.
func test_match_started_names_both_seats_crew() -> void:
	var engine: MatchEngine = _crew_engine()
	var result: ApplyResult = engine.start()
	assert_bool(result.ok).is_true()
	if not result.ok:
		return
	var opened: MatchEvent = result.events[0]
	assert_int(opened.kind).is_equal(MatchEvent.Kind.MATCH_STARTED)
	assert_int(opened.owner_seat).is_equal(MatchEvent.PUBLIC)
	var shown: Array = opened.payload["crew"]
	assert_array(shown).is_equal(_greed_ramp_crew())
	var fixture: ApplyResult = FixtureDecks.engine(SEED, _db()).start()
	var first: MatchEvent = fixture.events[0]
	var both: Array = first.payload["crew"]
	var fixture_crew: Array = []
	fixture_crew.assign(FixtureDecks.CREW)
	assert_array(both).is_equal([fixture_crew, fixture_crew])


## A deck list checked against a missing or failed Crew pool refuses to start (R41).
func test_no_crew_pool_refuses_to_start() -> void:
	var engine: MatchEngine = MatchEngine.create(
		SEED, _db(), FixtureDecks.decks(), FixtureDecks.ids(), null
	)
	assert_int(engine.start().error).is_equal(EngineError.Code.CARD_DATA_INVALID)
	var broken: MatchEngine = MatchEngine.create(
		SEED, _db(), FixtureDecks.decks(), FixtureDecks.ids(), CrewPool.from_json("{}")
	)
	assert_int(broken.start().error).is_equal(EngineError.Code.CARD_DATA_INVALID)


## Round start gives every Crew its uses: every v2 Crew is unlimited (-1, cycle 9 plan P4).
## A later round start keeps what each seat has left (a v2 Crew's uses are for the match).
## The counts are in the full state and survive a duplicate().
func test_crew_uses_are_filled_once_and_kept() -> void:
	var engine: MatchEngine = _crew_engine()
	assert_bool(engine.start().ok).is_true()
	var unlimited: int = CrewDef.UNLIMITED
	var all_unlimited: Array = [unlimited, unlimited, unlimited]
	assert_array(_crew_uses(engine)).is_equal([all_unlimited, all_unlimited])
	engine._state.crew_uses[0] = [0, unlimited, unlimited]
	# full_state() adds `dross` from MatchCards (NSC-179: one record); the rest is the state.
	var full: Dictionary = engine.full_state()
	assert_bool(full.has("dross")).is_true()
	full.erase("dross")
	assert_dict(engine._state.duplicate().to_dict()).is_equal(full)
	for _step: int in range(2 * MatchRules.TURNS + 2):
		if _state_int(engine, "round") > 1 or engine.is_over():
			break
		assert_bool(_pass(engine).ok).is_true()
	assert_int(_state_int(engine, "round")).is_equal(2)
	assert_array(_crew_uses(engine)).is_equal([[0, unlimited, unlimited], all_unlimited])


## Every view carries both seats' Crew and their uses, the same for either seat (public).
func test_the_view_carries_both_seats_crew() -> void:
	var engine: MatchEngine = _crew_engine()
	assert_bool(engine.start().ok).is_true()
	for seat: int in range(2):
		var view: SeatView = engine.view_for(seat)
		var crew: Array = []
		crew.append_array(view.crew)
		assert_array(crew).is_equal(_greed_ramp_crew())
		var uses: Array = []
		uses.append_array(view.crew_uses)
		assert_array(uses).is_equal(_crew_uses(engine))
		var shown: Dictionary = view.to_dict()
		var held: Array = shown["crew"]
		var shown_crew: Array = []
		shown_crew.append_array(held)
		assert_array(shown_crew).is_equal(_greed_ramp_crew())
