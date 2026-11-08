class_name TestTurnFlow
extends GdUnitTestSuite
## TurnFlow (cycle 9 plan P14; spec R1 to R21; DC-13 T03): Match start deals four cards once
## from Decks shuffled once; each Turn both seats draw, the first seat first; an empty Deck
## draws nothing and says so (DRAW_EMPTY, no burn exists); the Hand size (base four, plus a
## read Pantry); a Commit records `committed_count` (0 for a Pass) and opens the
## discard-down for a hand over its Hand size, a multi-select of exactly the excess that
## rejects any other size and every Commit while open, its Discards going to the Owner's
## Pile with reason discard_down; Round end sends both rows to their Owners' Piles with
## reason round_end, hands and Decks untouched. Engine matches play the fixture deck (40
## plain bodies) on both seats; the Pantry case builds a small pool from the shipped cards.

const SEED: int = 1
## The fixture's first card, Cost 1 (FixtureDecks.TABLE).
const CHEAP_INDEX: int = 0
## Pantry (ev14): "Ongoing: your Hand size is +2."
const PANTRY_ID: String = "ev14"

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	engine.start()
	return engine


func _seat_list(engine: MatchEngine, key: String, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var per_seat: Array = state[key]
	var raw: Array = per_seat[seat]
	return _typed(raw)


func _of_kind(events: Array[MatchEvent], kind: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == kind:
			out.append(event)
	return out


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _payload_str(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


## The awaited seat passes, answering the discard-down it opens (FixtureDecks).
func _pass(engine: MatchEngine) -> Array[MatchEvent]:
	var seen: Array[MatchEvent] = []
	var none: Array[int] = []
	var result: ApplyResult = engine.apply(EngineAction.commit(engine.awaited_seat(), none))
	seen.append_array(result.events)
	var answer: EngineAction = FixtureDecks.discard_answer(engine)
	if answer != null:
		seen.append_array(engine.apply(answer).events)
	return seen


## Moves `card` into `seat`'s hand from its Deck or Pile (a test-only edit).
func _into_hand(engine: MatchEngine, seat: int, card: int) -> void:
	var piles: MatchState.SeatPiles = engine._state.seats[seat]
	piles.deck.erase(card)
	piles.pile.erase(card)
	if not piles.hand.has(card):
		piles.hand.append(card)


## Records what TurnFlow sends to its sink.
func _recorder() -> Recorder:
	return Recorder.new()


# --- R10, R17: Match start deals once -------------------------------------------------


## Match start: both Decks shuffled once from their 40 ids, four cards dealt to each seat
## (seat 0's first, each private to its seat), 36 left in each Deck.
func test_match_start_deals_four_cards_and_leaves_36() -> void:
	var state: MatchState = MatchState.new(SEED)
	var recorder: Recorder = _recorder()
	TurnFlow.start_match(state, _defs(), MatchRng.new(SEED), recorder.record)
	var dealt: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_DEALT)
	assert_int(dealt.size()).is_equal(2 * MatchRules.OPENING_HAND)
	for at: int in range(dealt.size()):
		var seat: int = 0 if at < MatchRules.OPENING_HAND else 1
		assert_int(dealt[at].owner_seat).is_equal(seat)
		assert_int(_payload_int(dealt[at], "seat")).is_equal(seat)
	for seat: int in range(2):
		var piles: MatchState.SeatPiles = state.seats[seat]
		assert_int(piles.hand.size()).is_equal(MatchRules.OPENING_HAND)
		assert_int(piles.deck.size()).is_equal(36)
		var all: Array[int] = _typed(piles.hand + piles.deck)
		all.sort()
		for index: int in range(MatchRules.DECK_SIZE):
			assert_int(all[index]).is_equal(seat * MatchRules.DECK_SIZE + index)


## Round 2 starts with no deal: the only CARD_DEALT events of a match are Match start's.
func test_no_card_is_dealt_at_round_2() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	var events: Array[MatchEvent] = engine.start().events
	assert_int(_of_kind(events, MatchEvent.Kind.CARD_DEALT).size()).is_equal(8)
	var guard: int = 0
	while engine.full_state()["round"] == 1 and guard < 60:
		events.append_array(_pass(engine))
		guard += 1
	assert_int(engine.full_state()["round"]).is_equal(2)
	assert_int(_of_kind(events, MatchEvent.Kind.CARD_DEALT).size()).is_equal(8)
	assert_int(_of_kind(events, MatchEvent.Kind.ROUND_STARTED).size()).is_equal(2)


# --- R4, R12, R18: draws ----------------------------------------------------------------


## Each Turn both seats draw one card, the first seat first (resolution step 2).
func test_both_seats_draw_first_seat_first() -> void:
	var engine: MatchEngine = _started(SEED)
	for _turn: int in range(3):
		var events: Array[MatchEvent] = _pass(engine)
		events.append_array(_pass(engine))
		var started: MatchEvent = _of_kind(events, MatchEvent.Kind.TURN_STARTED)[0]
		var first: int = _payload_int(started, "first_seat")
		var drawn: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CARD_DRAWN)
		assert_int(drawn.size()).is_equal(2)
		assert_int(_payload_int(drawn[0], "seat")).is_equal(first)
		assert_int(_payload_int(drawn[1], "seat")).is_equal(1 - first)
		assert_int(drawn[0].owner_seat).is_equal(first)


## An empty Deck draws nothing and emits DRAW_EMPTY {seat}, public; no card is burned (no
## such event kind exists) and the hand is unchanged.
func test_an_empty_deck_draws_nothing_and_emits_draw_empty() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.seats[1].hand.assign(_typed([40, 41]))
	var recorder: Recorder = _recorder()
	assert_bool(TurnFlow.draw(state, _defs(), MatchRng.new(SEED), recorder.record, 1)).is_false()
	# DRAW_EMPTY, then the On empty draw drain (D1): the fixture's Void fires (DC-13 T07).
	assert_int(recorder.events[0].kind).is_equal(MatchEvent.Kind.DRAW_EMPTY)
	assert_int(recorder.events[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_dict(recorder.events[0].payload).is_equal({"seat": 1})
	var seen: int = recorder.events.size()
	var crew_kinds: Array[int] = [MatchEvent.Kind.TRIGGER_FIRED, MatchEvent.Kind.CREW_FIRED]
	for event: MatchEvent in recorder.events.slice(1):
		assert_bool(crew_kinds.has(event.kind)).is_true()
	assert_array(state.seats[1].hand).is_equal(_typed([40, 41]))
	assert_bool(MatchEvent.Kind.keys().has("CARD_BURNED")).is_false()
	# The resumed draw (Q11) finds the Deck still empty: nothing, and no second DRAW_EMPTY.
	assert_bool(TurnFlow.resumed_draw(state, recorder.record, 1)).is_false()
	assert_int(recorder.events.size()).is_equal(seen)
	# Once the Deck holds a card, the resumed draw takes it.
	state.seats[1].deck.assign(_typed([42]))
	assert_bool(TurnFlow.resumed_draw(state, recorder.record, 1)).is_true()
	assert_int(recorder.events[seen].kind).is_equal(MatchEvent.Kind.CARD_DRAWN)
	assert_array(state.seats[1].hand).is_equal(_typed([40, 41, 42]))


## Rules 9 (cycle 14 R16, NSC-186): TURN_STARTED says which seat starts its Turn with a
## free first card (Lantern), `free_first` per seat from the state's Energy, so a viewer
## learns it without the SeatView. An event change only: nothing else moves.
func test_turn_started_carries_free_first_per_seat() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].deck.assign(_typed([0, 1]))
	state.seats[1].deck.assign(_typed([40, 41]))
	state.energy.free_first[1] = true
	var recorder: Recorder = _recorder()
	assert_bool(TurnFlow.begin_turn(state, _defs(), MatchRng.new(SEED), recorder.record)).is_false()
	var started: MatchEvent = recorder.events[0]
	assert_int(started.kind).is_equal(MatchEvent.Kind.TURN_STARTED)
	assert_int(started.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_array(started.payload["free_first"]).is_equal([false, true])
	assert_bool(state.energy.free_first[1]).is_true()
	var engine: MatchEngine = _started(SEED)
	var events: Array[MatchEvent] = _pass(engine)
	events.append_array(_pass(engine))
	var next: MatchEvent = _of_kind(events, MatchEvent.Kind.TURN_STARTED)[0]
	assert_array(next.payload["free_first"]).is_equal([false, false])


## In a match, a seat whose Deck ran out draws nothing at the next turn start, in public,
## while the other seat still draws.
func test_an_empty_deck_at_turn_start_emits_draw_empty_in_the_match() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	var piles: MatchState.SeatPiles = engine._state.seats[first]
	piles.pile.append_array(piles.deck)
	piles.deck.clear()
	var events: Array[MatchEvent] = _pass(engine)
	events.append_array(_pass(engine))
	var empty: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.DRAW_EMPTY)
	assert_int(empty.size()).is_equal(1)
	assert_int(_payload_int(empty[0], "seat")).is_equal(first)
	var drawn: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CARD_DRAWN)
	assert_int(drawn.size()).is_equal(1)
	assert_int(_payload_int(drawn[0], "seat")).is_equal(1 - first)
	assert_int(_seat_list(engine, "hand", first).size()).is_equal(MatchRules.HAND_SIZE)


# --- R11: Hand size --------------------------------------------------------------------


## A pool of the shipped cards whose deck holds four Pantries (instances 0..3 of each seat).
func _pantry_defs() -> MatchCards:
	var listed: Array = []
	for _copy: int in range(4):
		listed.append(PANTRY_ID)
	for number: int in range(1, 10):
		for _copy: int in range(4):
			listed.append("ev%02d" % number)
	var deck: Dictionary = {
		"id": "pantry",
		"name": "Pantry",
		"tag": "evergreen",
		"theme": "Hand size.",
		"cards": listed,
		"crew": ["tallyman", "void", "engineer"],
	}
	var decks: DeckList = DeckList.from_json(
		JSON.stringify({"version": DeckList.FORMAT_VERSION, "decks": [deck]})
	)
	var ids: Array[String] = ["pantry", "pantry"]
	return MatchCards.build(CardDb.load_default(), decks, ids, CrewPool.load_default())


## The base Hand size is four; a revealed Pantry on the seat's row (an Ongoing read) makes
## it six, two make it eight; a face-down Pantry or the other seat's is not read.
func test_pantry_read_on_the_row_makes_hand_size_6() -> void:
	var defs: MatchCards = _pantry_defs()
	assert_bool(defs.is_valid()).override_failure_message(defs.build_error()).is_true()
	var state: MatchState = MatchState.new(SEED)
	assert_int(TurnFlow.hand_size(state, defs, 0)).is_equal(MatchRules.HAND_SIZE)
	state.seats[0].board.assign(_typed([0]))
	assert_int(TurnFlow.hand_size(state, defs, 0)).is_equal(MatchRules.HAND_SIZE)
	state.seats[0].revealed[0] = true
	assert_int(TurnFlow.hand_size(state, defs, 0)).is_equal(6)
	assert_int(TurnFlow.hand_size(state, defs, 1)).is_equal(MatchRules.HAND_SIZE)
	state.seats[0].board.append(1)
	state.seats[0].revealed[1] = true
	assert_int(TurnFlow.hand_size(state, defs, 0)).is_equal(8)
	var view: SeatView = SeatView.build(state, 1, -1, defs)
	assert_array(view.hand_sizes).is_equal(_typed([8, MatchRules.HAND_SIZE]))


## With six cards in hand and Pantry read, a Pass opens no discard-down.
func test_no_discard_down_within_the_hand_size() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign(_typed([4, 5, 6, 7]))
	var recorder: Recorder = _recorder()
	assert_bool(TurnFlow.open_discard_down(state, _defs(), recorder.record, 0)).is_false()
	assert_dict(state.prompt).is_empty()
	assert_array(recorder.events).is_empty()


# --- R13, R14: the discard-down ---------------------------------------------------------


## A hand of six (Hand size 4) after a one-card Commit holds five: the discard-down opens
## for that seat, a multi-select over its hand of exactly 1, not optional, resuming the
## Commit at D4; a two-card set and an empty set are rejected (BAD_SET), and so is the
## other seat's Commit (WRONG_SEAT), each changing nothing; the one-card answer sends that
## card to its Owner's Pile, public, reason discard_down, and only then is the other seat
## awaited.
func test_a_hand_of_six_after_a_one_card_commit_discards_exactly_one() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	var cheap: int = first * MatchRules.DECK_SIZE + CHEAP_INDEX
	_into_hand(engine, first, cheap)
	var piles: MatchState.SeatPiles = engine._state.seats[first]
	while piles.hand.size() < 6:
		piles.hand.append(piles.deck.pop_back())
	assert_int(piles.hand.size()).is_equal(6)
	var cards: Array[int] = [cheap]
	var committed: ApplyResult = engine.apply(EngineAction.commit(first, cards))
	assert_bool(committed.ok).is_true()
	var opened: Array[MatchEvent] = _of_kind(committed.events, MatchEvent.Kind.PROMPT_OPENED)
	assert_int(opened.size()).is_equal(1)
	assert_int(opened[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	var prompt: Dictionary = engine.open_prompt()
	assert_int(engine.awaited_seat()).is_equal(first)
	assert_int(prompt.get("seat", -1)).is_equal(first)
	assert_str(prompt.get("verb", "")).is_equal(TurnFlow.VERB_DISCARD_DOWN)
	assert_str(prompt.get("zone", "")).is_equal("own_hand")
	assert_int(Choice.exact_of(prompt)).is_equal(1)
	assert_bool(Choice.is_multi_prompt(prompt)).is_true()
	assert_bool(Choice.is_optional_prompt(prompt)).is_false()
	assert_str(Choice.resume_of(prompt)).is_equal(Choice.RESUME_COMMIT)
	assert_str(Choice.step_of(prompt)).is_equal(TurnFlow.STEP_FIRST_DISCARD)
	assert_array(Choice.options_of(prompt)).is_equal(_typed([0, 1, 2, 3, 4]))
	assert_str(_payload_str(opened[0], "text")).is_equal("Discard 1")
	var view: SeatView = engine.view_for(first)
	assert_int(view.prompt.get("exact", -1)).is_equal(1)
	assert_dict(engine.view_for(1 - first).prompt).is_equal({"open": true, "seat": first})
	var zone: int = Choice.Zone.OWN_HAND
	var none: Array[int] = []
	var bad_set: int = EngineError.Code.BAD_SET
	_assert_rejected(engine, EngineAction.choose_set(first, zone, _typed([0, 1])), bad_set)
	_assert_rejected(engine, EngineAction.choose_set(first, zone, none), bad_set)
	_assert_rejected(engine, EngineAction.choose_set(first, zone, _typed([5])), bad_set)
	var wrong: int = EngineError.Code.WRONG_SEAT
	_assert_rejected(engine, EngineAction.commit(1 - first, none), wrong)
	_assert_rejected(engine, EngineAction.commit(first, none), wrong)
	var single: int = EngineError.Code.NOT_ELIGIBLE
	_assert_rejected(engine, EngineAction.choose(first, zone, 0), single)
	var target: int = piles.hand[2]
	var answered: ApplyResult = engine.apply(EngineAction.choose_set(first, zone, _typed([2])))
	assert_bool(answered.ok).is_true()
	var discarded: Array[MatchEvent] = _of_kind(answered.events, MatchEvent.Kind.CARD_DISCARDED)
	assert_int(discarded.size()).is_equal(1)
	assert_int(discarded[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_dict(discarded[0].payload).is_equal(
		{
			"owner": first,
			"card": target,
			"from": "hand",
			"reason": "discard_down",
			"pile_index": 0,
		}
	)
	assert_array(_seat_list(engine, "pile", first)).is_equal(_typed([target]))
	assert_int(_seat_list(engine, "hand", first).size()).is_equal(MatchRules.HAND_SIZE)
	assert_bool(_seat_list(engine, "hand", first).has(target)).is_false()
	assert_dict(engine.open_prompt()).is_empty()
	assert_int(engine.awaited_seat()).is_equal(1 - first)
	# Both seats see the Discard in the Pile.
	for seat: int in range(2):
		assert_array(engine.view_for(seat).pile_of(first)).is_equal(_typed([target]))


## An illegal action changes nothing (EngineError code `code`).
func _assert_rejected(engine: MatchEngine, action: EngineAction, code: int) -> void:
	var before: Dictionary = engine.full_state()
	var count: int = engine.accepted_action_count()
	var result: ApplyResult = engine.apply(action)
	assert_bool(result.ok).is_false()
	assert_int(result.error).is_equal(code)
	assert_dict(engine.full_state()).is_equal(before)
	assert_int(engine.accepted_action_count()).is_equal(count)


## The second seat's discard-down resumes its Commit at D6, then the Walk runs.
func test_the_second_seats_discard_down_comes_before_the_walk() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass(engine)
	var none: Array[int] = []
	var second: int = engine.awaited_seat()
	var committed: ApplyResult = engine.apply(EngineAction.commit(second, none))
	assert_array(_of_kind(committed.events, MatchEvent.Kind.WALK_STARTED)).is_empty()
	assert_str(Choice.step_of(engine.open_prompt())).is_equal(TurnFlow.STEP_SECOND_DISCARD)
	var answered: ApplyResult = engine.apply(FixtureDecks.discard_answer(engine))
	assert_int(_of_kind(answered.events, MatchEvent.Kind.WALK_STARTED).size()).is_equal(1)


# --- P14: Commits -----------------------------------------------------------------------


## A Pass is an accepted Commit of zero cards: COMMITTED `pass` true, cost 0, and
## `committed_count` 0; a one-card Commit records 1.
func test_a_pass_is_accepted_and_committed_count_is_0() -> void:
	var engine: MatchEngine = _started(SEED)
	var first: int = engine.awaited_seat()
	var none: Array[int] = []
	var passed: ApplyResult = engine.apply(EngineAction.commit(first, none))
	assert_bool(passed.ok).is_true()
	var committed: MatchEvent = _of_kind(passed.events, MatchEvent.Kind.COMMITTED)[0]
	var is_pass: bool = committed.payload["pass"]
	assert_bool(is_pass).is_true()
	assert_int(_payload_int(committed, "cost")).is_equal(0)
	var raw_counts: Array = engine.full_state()["committed_count"]
	var counts: Array[int] = _typed(raw_counts)
	assert_int(counts[first]).is_equal(0)
	engine.apply(FixtureDecks.discard_answer(engine))
	var second: int = 1 - first
	var cheap: int = second * MatchRules.DECK_SIZE + CHEAP_INDEX
	_into_hand(engine, second, cheap)
	var cards: Array[int] = [cheap]
	var played: ApplyResult = engine.apply(EngineAction.commit(second, cards))
	assert_bool(played.ok).is_true()
	committed = _of_kind(played.events, MatchEvent.Kind.COMMITTED)[0]
	var not_pass: bool = committed.payload["pass"]
	assert_bool(not_pass).is_false()
	assert_int(_payload_int(committed, "cost")).is_equal(1)


## `committed_count` is the Turn's: a one-card Commit records 1 until the next turn start.
func test_committed_count_records_the_commit_until_the_next_turn() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.turn = 1
	state.first_seat = 0
	state.seats[0].hand.assign(_typed([0, 4]))
	var recorder: Recorder = _recorder()
	TurnFlow.accept_commit(state, _defs(), recorder.record, 0, _typed([0]), _typed([0]))
	assert_array(state.committed_count).is_equal(_typed([1, 0]))
	assert_array(state.pending).is_equal(_typed([0]))
	assert_array(state.seats[0].hand).is_equal(_typed([4]))
	var committed: MatchEvent = recorder.events[0]
	assert_int(committed.owner_seat).is_equal(0)
	var keys: Array = committed.payload.keys()
	keys.sort()
	assert_array(keys).is_equal(["cards", "cost", "count", "pass", "seat", "slots"])


## Placement (R43): committed cards take their slots and the row's cards keep their order.
func test_merge_row_places_cards_at_their_slots() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].board.assign(_typed([10, 11]))
	TurnFlow.merge_row(state, 0, _typed([20, 21]), _typed([0, 3]))
	assert_array(state.seats[0].board).is_equal(_typed([20, 10, 11, 21]))
	TurnFlow.merge_row(state, 0, _typed([22]), _typed([2]))
	assert_array(state.seats[0].board).is_equal(_typed([20, 10, 22, 11, 21]))


# --- R2, R20, R31: Round end ------------------------------------------------------------


## Round end sends every row card to its Owner's Pile as a public Discard, reason
## round_end, from row, the first seat's row first, each in slot order; a card on the row
## of the seat that does not Own it goes to its Owner's Pile. Hands and Decks stay.
func test_round_end_sends_both_rows_to_their_owners_piles() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = 1
	state.seats[0].board.assign(_typed([3, 45]))
	state.seats[1].board.assign(_typed([41, 42]))
	state.seats[0].revealed[3] = true
	state.seats[1].revealed[41] = true
	state.seats[0].hand.assign(_typed([5, 6]))
	state.seats[1].hand.assign(_typed([47]))
	state.seats[0].deck.assign(_typed([7]))
	state.seats[1].pile.assign(_typed([49]))
	state.card_state_for(41).power_delta = 2
	state.scores.assign([4, 9])
	state.turn_wins.assign([2, 3])  # C13: more Turn wins take the Round.
	var recorder: Recorder = _recorder()
	var winner: int = TurnFlow.end_round(state, _defs(), MatchRng.new(SEED), recorder.record)
	assert_int(winner).is_equal(1)
	var discarded: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_DISCARDED)
	var order: Array[int] = []
	for event: MatchEvent in discarded:
		order.append(_payload_int(event, "card"))
		assert_int(event.owner_seat).is_equal(MatchEvent.PUBLIC)
		assert_str(_payload_str(event, "reason")).is_equal(TurnFlow.REASON_ROUND_END)
		assert_str(_payload_str(event, "from")).is_equal(TurnFlow.FROM_ROW)
	# Seat 1 committed first: its row (41, 42), then seat 0's (3, 45).
	assert_array(order).is_equal(_typed([41, 42, 3, 45]))
	assert_int(_payload_int(discarded[3], "owner")).is_equal(1)
	assert_array(state.seats[1].pile).is_equal(_typed([49, 41, 42, 45]))
	assert_array(state.seats[0].pile).is_equal(_typed([3]))
	for seat: int in range(2):
		assert_array(state.seats[seat].board).is_empty()
		assert_bool(state.seats[seat].revealed.is_empty()).is_true()
	assert_bool(state.card_states.is_empty()).is_true()
	assert_array(state.seats[0].hand).is_equal(_typed([5, 6]))
	assert_array(state.seats[1].hand).is_equal(_typed([47]))
	assert_array(state.seats[0].deck).is_equal(_typed([7]))
	var ended: MatchEvent = recorder.events[recorder.events.size() - 1]
	assert_int(ended.kind).is_equal(MatchEvent.Kind.ROUND_ENDED)
	assert_int(_payload_int(ended, "winner")).is_equal(1)
	assert_array(state.wins).is_equal(_typed([0, 1]))


## Rules 9 (cycle 14 R10, R11, C13): at Round end, after ROUND_ENDED, every Dross card of
## lifetime `round` leaves the Match from wherever it is (hand, Pile, Deck, and a row card
## by way of its Round-end Discard), one public DROSS_EXPIRED {owner, card, from, reason}
## each in ascending id whatever the zone order, its record forgotten; a `match` Dross card
## stays; the other cards keep their order (the Deck is not reshuffled) and no random draw
## is made.
func test_round_end_removes_every_round_dross_card() -> void:
	var cards: MatchCards = StubAbilities.defs()
	var dross: CardDef = cards.pool_def("dross")
	var keeper: CardDef = CardDef.new("keeper", "Keeper", "evergreen", 1, 2)
	keeper.dross = true
	keeper.lifetime = CardDef.LIFETIME_MATCH
	var state: MatchState = MatchState.new(SEED)
	var in_deck: int = AbilitiesComboDisruption.create(state, cards, dross, 1)
	var in_hand: int = AbilitiesComboDisruption.create(state, cards, dross, 0)
	var kept: int = AbilitiesComboDisruption.create(state, cards, keeper, 0)
	var in_pile: int = AbilitiesComboDisruption.create(state, cards, dross, 0)
	var on_row: int = AbilitiesComboDisruption.create(state, cards, dross, 1)
	assert_int(in_deck).is_equal(MatchCards.DROSS_BASE)
	assert_int(on_row).is_equal(MatchCards.DROSS_BASE + 4)
	var other: int = MatchRules.DECK_SIZE
	state.first_seat = 0
	state.seats[0].hand.assign(_typed([3, kept, in_hand]))
	state.seats[0].pile.assign(_typed([in_pile, 4]))
	state.seats[0].deck.assign(_typed([5, 6]))
	state.seats[1].board.assign(_typed([on_row]))
	state.seats[1].deck.assign(_typed([other + 1, in_deck, other + 2, other + 3]))
	state.turn_wins.assign([1, 0])
	var rng: MatchRng = MatchRng.new(SEED)
	var stream_before: int = rng.state
	var recorder: Recorder = _recorder()
	assert_int(TurnFlow.end_round(state, cards, rng, recorder.record)).is_equal(0)
	assert_int(rng.state).is_equal(stream_before)
	var expired: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.DROSS_EXPIRED)
	var order: Array[int] = []
	for event: MatchEvent in expired:
		order.append(_payload_int(event, "card"))
		assert_int(event.owner_seat).is_equal(MatchEvent.PUBLIC)
		assert_str(_payload_str(event, "reason")).is_equal(TurnFlow.REASON_ROUND_END)
	assert_array(order).is_equal(_typed([in_deck, in_hand, in_pile, on_row]))
	assert_dict(expired[0].payload).is_equal(
		{"owner": 1, "card": in_deck, "from": "deck", "reason": "round_end"}
	)
	assert_str(_payload_str(expired[1], "from")).is_equal(TurnFlow.FROM_HAND)
	assert_int(_payload_int(expired[1], "owner")).is_equal(0)
	assert_str(_payload_str(expired[2], "from")).is_equal(TurnFlow.FROM_PILE)
	# The row Dross was Discarded to its Owner's Pile first, then left it.
	assert_str(_payload_str(expired[3], "from")).is_equal(TurnFlow.FROM_PILE)
	# Every DROSS_EXPIRED comes after ROUND_ENDED, and they are the last events.
	var ended_at: int = -1
	for at: int in range(recorder.events.size()):
		if recorder.events[at].kind == MatchEvent.Kind.ROUND_ENDED:
			ended_at = at
	assert_int(ended_at).is_equal(recorder.events.size() - 1 - expired.size())
	assert_array(state.seats[0].hand).is_equal(_typed([3, kept]))
	assert_array(state.seats[0].pile).is_equal(_typed([4]))
	assert_array(state.seats[0].deck).is_equal(_typed([5, 6]))
	assert_array(state.seats[1].board).is_empty()
	assert_array(state.seats[1].pile).is_empty()
	assert_array(state.seats[1].deck).is_equal(_typed([other + 1, other + 2, other + 3]))
	for card: int in [in_deck, in_hand, in_pile, on_row]:
		assert_object(cards.def_of(card)).is_null()
		assert_int(cards.origin_of(card)).is_equal(-1)
	assert_object(cards.def_of(kept)).is_same(keeper)
	assert_int(state.next_dross_id).is_equal(MatchCards.DROSS_BASE + 5)


## A Round with no Dross card ends exactly as before: no DROSS_EXPIRED, ROUND_ENDED last.
func test_round_end_without_dross_emits_no_expiry() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign(_typed([5]))
	var recorder: Recorder = _recorder()
	TurnFlow.end_round(state, _defs(), MatchRng.new(SEED), recorder.record)
	assert_array(_of_kind(recorder.events, MatchEvent.Kind.DROSS_EXPIRED)).is_empty()
	var last: MatchEvent = recorder.events[recorder.events.size() - 1]
	assert_int(last.kind).is_equal(MatchEvent.Kind.ROUND_ENDED)


# --- R6: Budget -------------------------------------------------------------------------


## The Budget is the Turn plus this Turn's grants (TurnFlow.budget); turn end moves the
## next Turn's grants in and clears the spend. The fixture's Engineer adds 1 from Turn 3
## (DC-13 T07).
func test_budget_is_the_turn_plus_grants_and_turn_end_settles_them() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.turn = 3
	state.energy.grants.assign([1, 0])
	state.energy.next_turn_grants.assign([0, 2])
	state.energy.spent.assign([3, 1])
	assert_int(TurnFlow.budget(state, _defs(), 0)).is_equal(5)
	assert_int(TurnFlow.budget(state, _defs(), 1)).is_equal(4)
	assert_int(TurnFlow.budget(state, _defs(), 2)).is_equal(0)
	var recorder: Recorder = _recorder()
	assert_bool(TurnFlow.end_turn(state, _defs(), MatchRng.new(SEED), recorder.record)).is_false()
	assert_array(state.energy.grants).is_equal(_typed([0, 2]))
	assert_array(state.energy.next_turn_grants).is_equal(_typed([0, 0]))
	assert_array(state.energy.spent).is_equal(_typed([0, 0]))
	var ended: MatchEvent = recorder.events[recorder.events.size() - 1]
	assert_int(ended.kind).is_equal(MatchEvent.Kind.TURN_ENDED)
	assert_int(_payload_int(ended, "winner")).is_equal(-1)


## Records what TurnFlow sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
