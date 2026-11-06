# gdlint: disable=max-public-methods, max-file-lines
class_name TestChoices
extends GdUnitTestSuite
## Prompts and choices (DC-05 T05; R20, R24-R26, R28-R34, R39, plan P3, P9, P10): Choice's
## zones and eligibility, the paths for 0, 1 and 2 or more eligible targets, each prompt
## verb's result (draw then discard, swap, return; the switch retired at DC-07 T01), a
## return to a full hand burning, a swap never pulsing a card twice, a paused walk resuming
## in the same pulse, the engine's AWAIT_CHOICE phase, every choice error code leaving the
## state and the log unchanged, a concede while prompted, the bot's interim answer, and
## replay of a log with a choice.
##
## Walk cases build MatchStates directly. Engine cases are scripted on searched seeds (no
## private fields): the first committer plays its c09 on turn 3 and the other passes,
## which always opens a discard prompt over a 7-card hand. Instance id = seat * 20 + index.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
const MAX_STEPS: int = 100
const MAX_ACTIONS: int = 2000
## Every fixture verb that prompts (the switch retired at DC-07 T01).
const PROMPT_VERBS: Array[int] = [
	CardEffect.Verb.DRAW_THEN_DISCARD,
	CardEffect.Verb.SWAP_PLACES,
	CardEffect.Verb.RETURN_AT_TURN_END,
]

# Definition indices in the default card list.
const C04: int = 3
const C06_FLAT_UP: int = 5
const C07: int = 6
const C08: int = 7
const C09_DRAW_DISCARD: int = 8
const C11: int = 10
const C12_SWAP: int = 11
const C13: int = 12
const C17_RETURN: int = 16

const PUBLIC: int = MatchEvent.PUBLIC
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.EFFECT_FIRED
const FIZZLED: int = MatchEvent.Kind.EFFECT_FIZZLED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const BURNED: int = MatchEvent.Kind.CARD_BURNED
const STATS: int = MatchEvent.Kind.STATS_CHANGED
const REQUESTED: int = MatchEvent.Kind.CHOICE_REQUESTED
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const MOVED: int = MatchEvent.Kind.CARD_MOVED
const RETURNED: int = MatchEvent.Kind.CARD_RETURNED
const DISCARDED: int = MatchEvent.Kind.CARD_DISCARDED

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## The fixture-vs-fixture definitions over _db() (DC-07 T02), for the MatchCards APIs:
## ScoreWalk, EffectResolver and RandomBot.
func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


## A state with these rows (seat 0, seat 1), nothing revealed, `first` committing first.
func _state(row_0: Array[int], row_1: Array[int], first: int) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = first
	state.seats[0].board.assign(row_0)
	state.seats[1].board.assign(row_1)
	return state


func _reveal(state: MatchState, seat: int, cards: Array[int]) -> void:
	for card: int in cards:
		state.seats[seat].revealed[card] = true


## Steps a live walk until it ends or pauses on a prompt; true when it paused.
func _run(state: MatchState, recorder: Recorder) -> bool:
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		if ScoreWalk.step(state, _defs(), MatchRng.new(SEED), recorder.record):
			return true
		guard += 1
	return false


## begin() then _run(); the walk must not pause.
func _walk(state: MatchState, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_false()


## Answers the open prompt with `index`, recording its events, then runs the walk on.
func _answer(state: MatchState, index: int, recorder: Recorder) -> bool:
	recorder.events.append_array(EffectResolver.answer(state, _defs(), index))
	return _run(state, recorder)


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


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


## The `card` of every event of `kind`, in order.
func _cards_of(events: Array[MatchEvent], kind: int) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, kind):
		out.append(_payload_int(event, "card"))
	return out


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


func _made(seat: int, card: int, zone: String, index: int, target: int, auto: bool) -> Dictionary:
	return {
		"seat": seat, "card": card, "zone": zone, "index": index, "target": target, "auto": auto
	}


func _text(index: int) -> String:
	return _db().card_at(index).effect.text


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	engine.start()
	return engine


func _hand(engine: MatchEngine, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var hands: Array = state["hand"]
	var raw: Array = hands[seat]
	return _typed(raw)


func _board(engine: MatchEngine, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var boards: Array = state["board"]
	var raw: Array = boards[seat]
	return _typed(raw)


func _phase(engine: MatchEngine) -> int:
	var state: Dictionary = engine.full_state()
	var phase: int = state["phase"]
	return phase


func _pass(engine: MatchEngine) -> ApplyResult:
	return engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))


func _pass_until_turn(engine: MatchEngine, turn: int) -> void:
	while engine.energy() < turn:
		if not _pass(engine).ok:
			return


## A started engine paused on c09's discard prompt (see the suite comment); null when no
## seed in the search range deals the first committer its c09 by turn 3.
func _discard_prompt_engine() -> MatchEngine:
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _started(match_seed)
		_pass_until_turn(engine, 3)
		var first: int = engine.awaited_seat()
		var c09: int = _id(first, C09_DRAW_DISCARD)
		if not _hand(engine, first).has(c09):
			continue
		if not engine.apply(EngineAction.commit(first, _typed([c09]))).ok:
			continue
		if not _pass(engine).ok:
			continue
		if not engine.open_prompt().is_empty():
			return engine
	return null


## Applies an illegal action and checks nothing changed: state, accepted actions, log (R31).
func _assert_rejected(engine: MatchEngine, action: EngineAction, code: int) -> void:
	var before: Dictionary = engine.full_state()
	var count: int = engine.accepted_action_count()
	var logged: String = engine.action_log().to_json()
	var result: ApplyResult = engine.apply(action)
	assert_bool(result.ok).is_false()
	assert_int(result.error).is_equal(code)
	assert_array(result.events).is_empty()
	assert_dict(engine.full_state()).is_equal(before)
	assert_int(engine.accepted_action_count()).is_equal(count)
	assert_str(engine.action_log().to_json()).is_equal(logged)


# --- Choice: zones and eligibility (R30, P10) -----------------------------------------


func test_zones_are_relative_to_the_prompted_seat() -> void:
	var own_row: Array[int] = [_id(1, C04), _id(1, C08)]
	var their_row: Array[int] = [_id(0, C07)]
	var state: MatchState = _state(their_row, own_row, 1)
	state.seats[1].hand.assign([_id(1, C11)])
	state.seats[0].hand.assign([_id(0, C11), _id(0, C04)])
	var zones: Dictionary = {
		Choice.Zone.OWN_HAND: [_id(1, C11)],
		Choice.Zone.OWN_BOARD: own_row,
		Choice.Zone.OPPONENT_HAND: [_id(0, C11), _id(0, C04)],
		Choice.Zone.OPPONENT_BOARD: their_row,
		Choice.Zone.BOTH_BOARDS: [_id(1, C04), _id(1, C08), _id(0, C07)],
	}
	for zone: int in zones:
		var expected: Array = zones[zone]
		assert_array(Choice.zone_cards(state, 1, zone)).is_equal(_typed(expected))
		for index: int in range(expected.size()):
			var card: int = expected[index]
			assert_int(Choice.resolve(state, 1, zone, index)).is_equal(card)
		assert_int(Choice.resolve(state, 1, zone, expected.size())).is_equal(-1)
		assert_int(Choice.resolve(state, 1, zone, -1)).is_equal(-1)
	# Two-board zone: own row first, then the opponent's.
	assert_int(Choice.seat_at(state, 1, Choice.Zone.BOTH_BOARDS, 1)).is_equal(1)
	assert_int(Choice.seat_at(state, 1, Choice.Zone.BOTH_BOARDS, 2)).is_equal(0)
	assert_int(Choice.seat_at(state, 1, Choice.Zone.BOTH_BOARDS, 3)).is_equal(-1)
	assert_str(Choice.zone_name(Choice.Zone.BOTH_BOARDS)).is_equal("both_boards")
	assert_str(Choice.zone_name(Choice.Zone.OWN_HAND)).is_equal("own_hand")


func test_eligibility_per_verb() -> void:
	var source: int = _id(0, C13)
	var shown: int = _id(0, C04)
	var hidden: int = _id(0, C08)
	var theirs: int = _id(1, C07)
	var state: MatchState = _state(_typed([shown, source, hidden]), _typed([theirs]), 0)
	_reveal(state, 0, _typed([shown, source]))
	_reveal(state, 1, _typed([theirs]))
	state.seats[0].hand.assign([_id(0, C11), _id(0, C12_SWAP)])
	var cases: Dictionary = {
		CardEffect.Verb.DRAW_THEN_DISCARD: [Choice.Zone.OWN_HAND, [0, 1]],
		CardEffect.Verb.SWAP_PLACES: [Choice.Zone.OWN_BOARD, [0, 2]],
		CardEffect.Verb.RETURN_AT_TURN_END: [Choice.Zone.BOTH_BOARDS, [0, 3]],
	}
	for verb: int in cases:
		var expected: Array = cases[verb]
		var found: Dictionary = Choice.eligible(state, 0, verb, source)
		var zone: int = found["zone"]
		var options: Array = found["options"]
		assert_int(zone).is_equal(expected[0])
		assert_array(options).is_equal(expected[1])
		assert_bool(Choice.needs_choice(verb)).is_true()
	var draw: Dictionary = Choice.eligible(state, 0, CardEffect.Verb.DRAW, source)
	assert_int(_dict_int(draw, "zone")).is_equal(Choice.NO_ZONE)
	assert_bool(Choice.needs_choice(CardEffect.Verb.DRAW)).is_false()


## DC-06 R16: the swap may target a destroyed card; the return may not.
## Seat 0's row: a revealed card, the source, a face-down card and a destroyed revealed
## card; seat 1's: a destroyed revealed card and a live one.
func test_destroyed_cards_are_swap_targets_only() -> void:
	var source: int = _id(0, C12_SWAP)
	var shown: int = _id(0, C04)
	var hidden: int = _id(0, C08)
	var wreck: int = _id(0, C07)
	var their_wreck: int = _id(1, C07)
	var theirs: int = _id(1, C11)
	var own_row: Array[int] = [shown, source, hidden, wreck]
	var state: MatchState = _state(own_row, _typed([their_wreck, theirs]), 0)
	_reveal(state, 0, _typed([shown, source, wreck]))
	_reveal(state, 1, _typed([their_wreck, theirs]))
	state.card_state_for(wreck).destroyed = true
	state.card_state_for(their_wreck).destroyed = true
	var cases: Dictionary = {
		CardEffect.Verb.SWAP_PLACES: [Choice.Zone.OWN_BOARD, [0, 2, 3]],
		CardEffect.Verb.RETURN_AT_TURN_END: [Choice.Zone.BOTH_BOARDS, [0, 5]],
	}
	for verb: int in cases:
		var expected: Array = cases[verb]
		var found: Dictionary = Choice.eligible(state, 0, verb, source)
		var zone: int = found["zone"]
		var options: Array = found["options"]
		var where: String = CardEffect.verb_name(verb)
		assert_int(zone).override_failure_message(where).is_equal(expected[0])
		assert_array(options).override_failure_message(where).is_equal(expected[1])


func _dict_int(d: Dictionary, key: String) -> int:
	var value: int = d[key]
	return value


# --- 0, 1, 2+ eligible (R26, R28, R29), with SWAP_PLACES ------------------------------


func test_no_eligible_target_fizzles() -> void:
	var card: int = _id(0, C12_SWAP)
	var state: MatchState = _state(_typed([card]), _none(), 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))
	var fizzled: Dictionary = {"seat": 0, "card": card, "verb": "swap_places"}
	_assert_event(events[2], FIZZLED, fizzled.merged({"reason": "no_target"}), PUBLIC)
	assert_dict(state.prompt).is_empty()
	assert_array(state.seats[0].board).is_equal(_typed([card]))


func test_one_eligible_target_is_chosen_automatically() -> void:
	var other: int = _id(0, C04)
	var card: int = _id(0, C12_SWAP)
	var state: MatchState = _state(_typed([other, card]), _none(), 0)
	_reveal(state, 0, _typed([other]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [SCORED, REVEALED, FIRED, MADE, MOVED, MOVED, SCORED]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[3], MADE, _made(0, card, "own_board", 0, other, true), PUBLIC)
	_assert_event(events[4], MOVED, {"seat": 0, "card": card, "from_slot": 1, "to_slot": 0}, PUBLIC)
	_assert_event(
		events[5], MOVED, {"seat": 0, "card": other, "from_slot": 0, "to_slot": 1}, PUBLIC
	)
	# C23, C25: the score stage belongs to slot 1, so c04 (already scored on slot 0) scores
	# again there; c12, moved onto the passed slot 0, does not score this walk.
	assert_int(_payload_int(events[6], "card")).is_equal(other)
	assert_int(_payload_int(events[6], "slot")).is_equal(1)
	assert_bool(events[6].payload.get("again", false)).is_true()
	assert_array(state.seats[0].board).is_equal(_typed([card, other]))
	assert_dict(state.prompt).is_empty()
	assert_array(state.scores).is_equal(_typed([6, 0]))


## Rows: seat 0 [a (revealed), c12, b (face down)], seat 0 first. The walk pulses a, then
## reveals c12, whose swap has two targets (a at 0, b at 2): it pauses.
func _swap_state() -> MatchState:
	var a: int = _id(0, C04)
	var b: int = _id(0, C08)
	var state: MatchState = _state(_typed([a, _id(0, C12_SWAP), b]), _none(), 0)
	_reveal(state, 0, _typed([a]))
	return state


func test_two_or_more_targets_pause_the_walk_on_a_prompt() -> void:
	var card: int = _id(0, C12_SWAP)
	var state: MatchState = _swap_state()
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_true()
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([SCORED, REVEALED, FIRED, REQUESTED]))
	var requested: Dictionary = {
		"seat": 0,
		"card": card,
		"verb": "swap_places",
		"text": _text(C12_SWAP),
		"zone": "own_board",
		"options": [0, 2],
		"multi": false,
		# DC-11 T09 (cycle 8 P9): a card prompt is never optional and resumes the walk.
		"optional": false,
		"resume": "walk",
		"crew": "",
	}
	_assert_event(events[3], REQUESTED, requested, PUBLIC)
	var prompt: Dictionary = {
		"seat": 0,
		"card": card,
		"verb": CardEffect.Verb.SWAP_PLACES,
		"zone": Choice.Zone.OWN_BOARD,
		"options": [0, 2],
		"multi": false,
		"optional": false,
		"resume": "walk",
		"crew": "",
	}
	assert_dict(state.prompt).is_equal(prompt)
	assert_dict(state.to_dict()["prompt"]).is_equal(prompt)
	# Paused in c12's pulse: its slot passed but the card not scored, and nothing moves
	# until the answer (DC-06 R2).
	assert_array(state.walk.cursor).is_equal(_typed([2, 0]))
	assert_bool(state.walk.scored.has(card)).is_false()
	assert_int(state.walk.paused_card).is_equal(card)
	assert_int(state.walk.paused_slot).is_equal(1)
	assert_array(state.scores).is_equal(_typed([3, 0]))
	assert_bool(state.walk.active).is_true()
	var still: Dictionary = state.to_dict()
	assert_bool(ScoreWalk.step(state, _defs(), null, recorder.record)).is_true()
	assert_dict(state.to_dict()).is_equal(still)
	assert_int(recorder.events.size()).is_equal(4)


## R32, DC-06 R5, R11, C23-C25: whichever card c12 swaps with, the walk resumes in the same
## pulse and scores the card now on c12's slot 1. Swapped behind (with a, index 0), a
## scores again there and c12, on the passed slot 0, does not score; b scores at slot 2.
## Swapped ahead (with b, index 2), b reveals on slot 1 and scores there, and c12 scores
## once at slot 2.
func test_after_a_swap_the_walk_resumes_in_the_same_pulse() -> void:
	var card: int = _id(0, C12_SWAP)
	var a: int = _id(0, C04)
	var b: int = _id(0, C08)
	var rows: Dictionary = {0: [card, a, b], 2: [a, b, card]}
	var scored_cards: Dictionary = {0: [a, a, b], 2: [a, b, card]}
	var after_moves: Dictionary = {0: [SCORED], 2: [REVEALED, SCORED]}
	var occupants: Dictionary = {0: a, 2: b}
	# c04 3 twice + c08 4, or c04 3 + c08 4 + c12 4.
	var totals: Dictionary = {0: 10, 2: 11}
	for index: int in rows:
		var state: MatchState = _swap_state()
		var recorder: Recorder = Recorder.new()
		ScoreWalk.begin(state)
		assert_bool(_run(state, recorder)).is_true()
		assert_bool(_answer(state, index, recorder)).is_false()
		var events: Array[MatchEvent] = recorder.events
		var expected: Array[int] = [MADE, MOVED, MOVED]
		var tail: Array = after_moves[index]
		expected.append_array(_typed(tail))
		var after_prompt: Array[int] = _kinds(events).slice(4, 4 + expected.size())
		assert_array(after_prompt).is_equal(expected)
		var occupant: int = occupants[index]
		var first_score: MatchEvent = events[3 + expected.size()]
		assert_int(_payload_int(first_score, "card")).is_equal(occupant)
		assert_int(_payload_int(first_score, "slot")).is_equal(1)
		var row: Array = rows[index]
		assert_array(state.seats[0].board).is_equal(_typed(row))
		var want_scored: Array = scored_cards[index]
		assert_array(_cards_of(events, SCORED)).is_equal(_typed(want_scored))
		assert_array(_cards_of(events, REVEALED)).is_equal(_typed([card, b]))
		assert_bool(state.seats[0].is_revealed(b)).is_true()
		var total: int = totals[index]
		assert_array(state.scores).is_equal(_typed([total, 0]))
		assert_array(state.walk.cursor).is_equal(_typed([3, 0]))
		assert_bool(state.walk.active).is_false()
		assert_int(state.walk.paused_card).is_equal(-1)
		assert_dict(state.prompt).is_empty()


## A face-down target is chosen by position (R30): the choice and its move are private
## to the row's seat, and the other seat's copies hide the card.
func test_a_face_down_swap_target_stays_hidden() -> void:
	var card: int = _id(0, C12_SWAP)
	var b: int = _id(0, C08)
	var state: MatchState = _swap_state()
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	_run(state, recorder)
	var answered: Array[MatchEvent] = EffectResolver.answer(state, _defs(), 2)
	assert_array(_kinds(answered)).is_equal(_typed([MADE, MOVED, MOVED]))
	_assert_event(answered[0], MADE, _made(0, card, "own_board", 2, b, false), 0)
	_assert_event(
		answered[1], MOVED, {"seat": 0, "card": card, "from_slot": 1, "to_slot": 2}, PUBLIC
	)
	_assert_event(answered[2], MOVED, {"seat": 0, "card": b, "from_slot": 2, "to_slot": 1}, 0)
	var made: MatchEvent = answered[0].redacted_for(1)
	assert_int(_payload_int(made, "target")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_int(_payload_int(made, "card")).is_equal(card)
	assert_int(_payload_int(answered[2].redacted_for(1), "card")).is_equal(MatchEvent.HIDDEN_CARD)


# --- DRAW_THEN_DISCARD (R20, R25) -----------------------------------------------------


func test_draw_then_discard_draws_two_then_discards_the_chosen_hand_card() -> void:
	var card: int = _id(0, C09_DRAW_DISCARD)
	var state: MatchState = _state(_typed([card]), _none(), 0)
	var held: Array[int] = [_id(0, C04), _id(0, C07)]
	var deck: Array[int] = [_id(0, C08), _id(0, C11), _id(0, C13)]
	state.seats[0].hand.assign(held)
	state.seats[0].deck.assign(deck)
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_true()
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, DRAWN, DRAWN, REQUESTED]))
	var options: Array = events[4].payload["options"]
	assert_array(options).is_equal([0, 1, 2, 3])
	var zone_name: String = events[4].payload["zone"]
	assert_str(zone_name).is_equal("own_hand")
	assert_bool(_answer(state, 1, recorder)).is_false()
	events = recorder.events
	assert_array(_kinds(events).slice(5)).is_equal(_typed([MADE, DISCARDED, SCORED]))
	_assert_event(events[5], MADE, _made(0, card, "own_hand", 1, held[1], false), 0)
	_assert_event(events[6], DISCARDED, {"seat": 0, "card": held[1]}, 0)
	assert_array(state.seats[0].hand).is_equal(_typed([held[0], deck[0], deck[1]]))
	assert_array(state.seats[0].burned).is_equal(_typed([held[1]]))
	assert_array(state.seats[0].deck).is_equal(_typed([deck[2]]))
	# The other seat sees a discard and a choice, never the card (R34).
	assert_int(_payload_int(events[6].redacted_for(1), "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_int(_payload_int(events[5].redacted_for(1), "target")).is_equal(MatchEvent.HIDDEN_CARD)


func test_draw_then_discard_with_one_card_discards_it_and_with_none_fizzles() -> void:
	var card: int = _id(0, C09_DRAW_DISCARD)
	var drawn: int = _id(0, C08)
	var one: MatchState = _state(_typed([card]), _none(), 0)
	one.seats[0].deck.assign([drawn])
	var recorder: Recorder = Recorder.new()
	_walk(one, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [REVEALED, FIRED, DRAWN, MADE, DISCARDED, SCORED]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[3], MADE, _made(0, card, "own_hand", 0, drawn, true), 0)
	assert_array(one.seats[0].hand).is_empty()
	assert_array(one.seats[0].burned).is_equal(_typed([drawn]))
	var empty: MatchState = _state(_typed([card]), _none(), 0)
	var quiet: Recorder = Recorder.new()
	_walk(empty, quiet)
	assert_array(_kinds(quiet.events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))


func test_draw_then_discard_at_the_cap_burns_the_overflow_then_prompts() -> void:
	var card: int = _id(0, C09_DRAW_DISCARD)
	var state: MatchState = _state(_typed([card]), _none(), 0)
	var held: Array[int] = []
	for index: int in range(MatchRules.HAND_CAP - 1):
		held.append(_id(0, index))
	state.seats[0].hand.assign(held)
	state.seats[0].deck.assign([_id(0, 17), _id(0, 18)])
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_true()
	assert_array(_kinds(recorder.events)).is_equal(
		_typed([REVEALED, FIRED, DRAWN, BURNED, REQUESTED])
	)
	assert_int(state.seats[0].hand.size()).is_equal(MatchRules.HAND_CAP)
	assert_int(Choice.options_of(state.prompt).size()).is_equal(MatchRules.HAND_CAP)


# --- RETURN_AT_TURN_END (R20, R24, R25) -----------------------------------------------


func test_return_marks_the_card_and_turn_end_returns_it_to_its_owner() -> void:
	var card: int = _id(0, C17_RETURN)
	var theirs: int = _id(1, C04)
	var state: MatchState = _state(_typed([card]), _typed([theirs]), 0)
	_reveal(state, 1, _typed([theirs]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, MADE, SCORED, SCORED]))
	_assert_event(events[2], MADE, _made(0, card, "both_boards", 1, theirs, true), PUBLIC)
	assert_bool(state.card_state(theirs).return_marked).is_true()
	# Still on the row (and scored) until the turn ends.
	assert_array(state.seats[1].board).is_equal(_typed([theirs]))
	var returned: Array[MatchEvent] = EffectResolver.resolve_returns(state)
	assert_int(returned.size()).is_equal(1)
	_assert_event(returned[0], RETURNED, {"seat": 1, "card": theirs, "slot": 0}, PUBLIC)
	assert_array(state.seats[1].board).is_empty()
	assert_array(state.seats[1].hand).is_equal(_typed([theirs]))
	assert_bool(state.seats[1].is_revealed(theirs)).is_false()
	assert_object(state.card_state(theirs)).is_null()


func test_a_return_to_a_full_hand_burns_the_card() -> void:
	var card: int = _id(0, C17_RETURN)
	var theirs: int = _id(1, C04)
	var state: MatchState = _state(_typed([card]), _typed([theirs]), 0)
	_reveal(state, 1, _typed([theirs]))
	var full: Array[int] = []
	for index: int in range(10, 10 + MatchRules.HAND_CAP):
		full.append(_id(1, index))
	state.seats[1].hand.assign(full)
	_walk(state, Recorder.new())
	var returned: Array[MatchEvent] = EffectResolver.resolve_returns(state)
	assert_int(returned.size()).is_equal(1)
	var burned: Dictionary = {"seat": 1, "card": theirs, "slot": 0, "row_seat": 1}  # Public.
	_assert_event(returned[0], BURNED, burned, PUBLIC)
	assert_array(state.seats[1].hand).is_equal(full)
	assert_array(state.seats[1].burned).is_equal(_typed([theirs]))
	assert_array(state.seats[1].board).is_empty()


func test_return_prompts_over_both_boards_and_never_offers_its_own_card() -> void:
	var own: int = _id(0, C04)
	var card: int = _id(0, C17_RETURN)
	var theirs: int = _id(1, C07)
	var state: MatchState = _state(_typed([own, card]), _typed([theirs]), 0)
	_reveal(state, 0, _typed([own]))
	_reveal(state, 1, _typed([theirs]))
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 2]))
	_assert_rejected_index(state, 1)
	assert_bool(_answer(state, 0, recorder)).is_false()
	assert_bool(state.card_state(own).return_marked).is_true()
	var returned: Array[MatchEvent] = EffectResolver.resolve_returns(state)
	_assert_event(returned[0], RETURNED, {"seat": 0, "card": own, "slot": 0}, PUBLIC)
	assert_array(state.seats[0].board).is_equal(_typed([card]))
	# Alone on the boards, the return has no target.
	var alone: MatchState = _state(_typed([card]), _none(), 0)
	var quiet: Recorder = Recorder.new()
	_walk(alone, quiet)
	assert_array(_kinds(quiet.events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))


## Position `index` is not among the open prompt's options (the source itself here).
func _assert_rejected_index(state: MatchState, index: int) -> void:
	var zone: int = state.prompt["zone"]
	assert_bool(Choice.is_offered(state.prompt, zone, index)).is_false()
	assert_bool(Choice.is_offered(state.prompt, Choice.Zone.OWN_BOARD, 0)).is_false()


# --- The engine: AWAIT_CHOICE, choose, errors, replay (R28, R31, R32, R39) ------------


func test_the_engine_awaits_the_prompted_seat() -> void:
	var engine: MatchEngine = _discard_prompt_engine()
	assert_object(engine).override_failure_message("no seed gives c09 by turn 3").is_not_null()
	if engine == null:
		return
	var prompt: Dictionary = engine.open_prompt()
	var asked: int = prompt["seat"]
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_CHOICE)
	assert_int(engine.awaited_seat()).is_equal(asked)
	assert_int(engine.energy()).is_equal(3)
	var c09: int = _id(asked, C09_DRAW_DISCARD)
	assert_int(_dict_int(prompt, "card")).is_equal(c09)
	assert_int(_dict_int(prompt, "zone")).is_equal(Choice.Zone.OWN_HAND)
	var hand: Array[int] = _hand(engine, asked)
	assert_int(hand.size()).is_equal(MatchRules.HAND_CAP)
	var view: SeatView = engine.view_for(asked)
	assert_bool(view.is_awaited()).is_true()
	assert_array(Choice.options_of(view.prompt)).is_equal(Choice.options_of(prompt))
	var text: String = view.prompt["text"]
	assert_str(text).is_equal(_text(C09_DRAW_DISCARD))
	# The answer resumes c09's pulse: it scores, the turn ends and turn 4 begins.
	var result: ApplyResult = engine.apply(EngineAction.choose(asked, Choice.Zone.OWN_HAND, 6))
	assert_bool(result.ok).is_true()
	var kinds: Array[int] = _kinds(result.events)
	assert_int(kinds[0]).is_equal(MADE)
	assert_int(kinds[1]).is_equal(DISCARDED)
	assert_int(kinds.find(SCORED)).is_greater(1)
	assert_int(kinds.find(MatchEvent.Kind.TURN_ENDED)).is_greater(kinds.find(SCORED))
	assert_bool(_hand(engine, asked).has(hand[6])).is_false()
	assert_dict(engine.open_prompt()).is_empty()
	assert_int(engine.energy()).is_equal(4)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_FIRST)


func test_choice_errors_leave_the_state_and_the_log_unchanged() -> void:
	# NO_PROMPT before any prompt opens.
	var fresh: MatchEngine = _started(SEED)
	var awaited: int = fresh.awaited_seat()
	_assert_rejected(fresh, EngineAction.choose(awaited, 0, 0), EngineError.Code.NO_PROMPT)
	var engine: MatchEngine = _discard_prompt_engine()
	assert_object(engine).override_failure_message("no seed gives c09 by turn 3").is_not_null()
	if engine == null:
		return
	var asked: int = engine.awaited_seat()
	var other: int = 1 - asked
	var hand_zone: int = Choice.Zone.OWN_HAND
	# WRONG_SEAT: the other seat's choice, and any commit while the prompt is open.
	_assert_rejected(engine, EngineAction.choose(other, hand_zone, 0), EngineError.Code.WRONG_SEAT)
	_assert_rejected(engine, EngineAction.commit(asked, _none()), EngineError.Code.WRONG_SEAT)
	_assert_rejected(engine, EngineAction.commit(other, _none()), EngineError.Code.WRONG_SEAT)
	# NOT_ELIGIBLE: a position outside the options, or another zone.
	var not_eligible: int = EngineError.Code.NOT_ELIGIBLE
	_assert_rejected(
		engine, EngineAction.choose(asked, hand_zone, MatchRules.HAND_CAP), not_eligible
	)
	_assert_rejected(engine, EngineAction.choose(asked, hand_zone, -1), not_eligible)
	var board_zone: int = Choice.Zone.OWN_BOARD
	_assert_rejected(engine, EngineAction.choose(asked, board_zone, 0), not_eligible)
	_assert_rejected(engine, EngineAction.choose(asked, 99, 0), not_eligible)
	# Accepted, then NO_PROMPT again.
	var count: int = engine.accepted_action_count()
	assert_bool(engine.apply(EngineAction.choose(asked, hand_zone, 0)).ok).is_true()
	assert_int(engine.accepted_action_count()).is_equal(count + 1)
	var next: int = engine.awaited_seat()
	_assert_rejected(engine, EngineAction.choose(next, hand_zone, 0), EngineError.Code.NO_PROMPT)


func test_a_concede_while_prompted_ends_the_match_and_closes_the_prompt() -> void:
	var engine: MatchEngine = _discard_prompt_engine()
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var asked: int = engine.awaited_seat()
	assert_bool(engine.apply(EngineAction.concede(1 - asked)).ok).is_true()
	assert_bool(engine.is_over()).is_true()
	assert_dict(engine.open_prompt()).is_empty()
	assert_dict(engine.view_for(asked).prompt).is_empty()


## The random bot answers its prompt with an offered option of the prompt's zone, which the
## engine accepts (cycle 9 R70).
func test_the_bot_answers_its_prompt_with_an_offered_option() -> void:
	var engine: MatchEngine = _discard_prompt_engine()
	assert_object(engine).is_not_null()
	if engine == null:
		return
	var asked: int = engine.awaited_seat()
	var bot: RandomBot = RandomBot.new(BotRegistry.seed_for(SEED, asked), _defs())
	var action: EngineAction = bot.choose(engine.view_for(asked), engine)
	assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE)
	assert_int(action.seat).is_equal(asked)
	assert_int(action.zone).is_equal(Choice.Zone.OWN_HAND)
	var options: Array[int] = Choice.options_of(engine.open_prompt())
	assert_bool(options.has(action.index)).is_true()
	assert_bool(engine.apply(action).ok).is_true()


func _seat_list(state: Dictionary, key: String, seat: int) -> Array[int]:
	var per_seat: Array = state[key]
	var raw: Array = per_seat[seat]
	return _typed(raw)


func test_a_log_with_a_choice_replays_to_an_equal_state() -> void:
	var engine: MatchEngine = _discard_prompt_engine()
	assert_object(engine).is_not_null()
	if engine == null:
		return
	# Replay of the paused match reaches the same open prompt.
	var paused: ReplayResult = ActionLog.from_json(engine.action_log().to_json()).replay(
		_db(), FixtureDecks.decks(), FixtureDecks.crew()
	)
	assert_bool(paused.ok).is_true()
	assert_dict(paused.engine.full_state()).is_equal(engine.full_state())
	var asked: int = engine.awaited_seat()
	assert_bool(engine.apply(EngineAction.choose(asked, Choice.Zone.OWN_HAND, 3)).ok).is_true()
	_pass(engine)
	var text: String = engine.action_log().to_json()
	var entry: String = '{"k":"choose","s":%d,"z":%d,"i":3}' % [asked, Choice.Zone.OWN_HAND]
	assert_bool(text.contains(entry)).override_failure_message(text).is_true()
	var replayed: ReplayResult = ActionLog.from_json(text).replay(
		_db(), FixtureDecks.decks(), FixtureDecks.crew()
	)
	assert_bool(replayed.ok).is_true()
	assert_dict(replayed.engine.full_state()).is_equal(engine.full_state())
	assert_str(replayed.engine.action_log().to_json()).is_equal(text)


## R24 in a real match: turn 5 the first committer plays an effect-free card and wins;
## turn 6 it plays c17, whose only target is that card, which returns at turn end, before
## the energy settles and the turn ends.
func test_a_marked_card_returns_to_its_owners_hand_at_turn_end() -> void:
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _started(match_seed)
		_pass_until_turn(engine, 5)
		var first: int = engine.awaited_seat()
		var plain: int = _first_vanilla(_hand(engine, first), 5)
		var c17: int = _id(first, C17_RETURN)
		if plain < 0 or not _hand(engine, first).has(c17):
			continue
		assert_bool(engine.apply(EngineAction.commit(first, _typed([plain]))).ok).is_true()
		_pass(engine)
		if engine.awaited_seat() != first or not _hand(engine, first).has(c17):
			continue
		assert_bool(engine.apply(EngineAction.commit(first, _typed([c17]))).ok).is_true()
		var result: ApplyResult = _pass(engine)
		assert_bool(result.ok).is_true()
		var kinds: Array[int] = _kinds(result.events)
		var made: MatchEvent = _of_kind(result.events, MADE)[0]
		_assert_event(made, MADE, _made(first, c17, "both_boards", 0, plain, true), PUBLIC)
		var at: int = kinds.find(RETURNED)
		assert_int(at).is_greater(kinds.find(SCORED))
		assert_int(at).is_less(kinds.find(MatchEvent.Kind.TURN_ENDED))
		var back: Dictionary = {"seat": first, "card": plain, "slot": 0}
		_assert_event(result.events[at], RETURNED, back, PUBLIC)
		assert_array(_board(engine, first)).is_equal(_typed([c17]))
		assert_bool(_hand(engine, first).has(plain)).is_true()
		return
	fail("no seed gives an effect-free card and c17 by turn 5")


## The first effect-free card of `hand` costing at most `budget`, or -1.
func _first_vanilla(hand: Array[int], budget: int) -> int:
	for card: int in hand:
		var def: CardDef = _db().card_at(card % MatchRules.DECK_SIZE)
		if def.effect == null and def.cost <= budget:
			return card
	return -1


# --- Multi-select (DC-07 T05; R22-R25, P7; c02 given sacrifice_destroy) ---------------


## R25: no eligible card fizzles; one still prompts (multi); the empty set fizzles (R24).
func test_a_multi_select_fizzles_on_none_and_prompts_on_one() -> void:
	var defs: MatchCards = FixtureDecks.defs(FixtureDecks.sacrifice_cards())
	var source: int = _id(0, FixtureDecks.C02_SACRIFICE)
	var recorder: Recorder = Recorder.new()
	var alone: MatchState = _state(_typed([source]), _none(), 0)
	ScoreWalk.begin(alone)
	assert_bool(ScoreWalk.run(alone, defs, null, recorder.record)).is_false()
	assert_array(_kinds(recorder.events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))
	var other: int = _id(0, C04)
	var state: MatchState = _state(_typed([other, source]), _none(), 0)
	_reveal(state, 0, _typed([other]))
	recorder.events.clear()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.run(state, defs, null, recorder.record)).is_true()
	assert_array(_kinds(recorder.events)).is_equal(_typed([SCORED, REVEALED, FIRED, REQUESTED]))
	var multi: bool = recorder.events[3].payload["multi"]
	assert_bool(multi and Choice.is_multi_prompt(state.prompt)).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0]))
	recorder.events.assign(EffectResolver.answer_set(state, defs, null, _none()))
	assert_bool(ScoreWalk.run(state, defs, null, recorder.record)).is_false()
	assert_array(_kinds(recorder.events)).is_equal(_typed([MADE, FIZZLED, SCORED]))
	assert_array(recorder.events[0].payload["indices"]).is_empty()
	assert_bool(state.is_destroyed(other)).is_false()


## R23, P7: bad sets and wrong kinds change nothing; then the empty set is accepted.
func test_set_choice_errors_and_the_decline() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, FixtureDecks.sacrifice_cards())
	engine.start()
	var own: Array[int] = [_id(0, C04), _id(0, C08), _id(0, FixtureDecks.C02_SACRIFICE)]
	assert_bool(FixtureDecks.play_table(engine, own, _typed([_id(1, C04)]))).is_true()
	var board: int = Choice.Zone.OWN_BOARD
	assert_array(Choice.options_of(engine.open_prompt())).is_equal(_typed([0, 1]))
	var bad: int = EngineError.Code.BAD_SET
	_assert_rejected(engine, EngineAction.choose_set(0, board, _typed([1, 1])), bad)
	_assert_rejected(engine, EngineAction.choose_set(0, board, _typed([0, 2])), bad)
	_assert_rejected(engine, EngineAction.choose_set(0, Choice.Zone.OWN_HAND, _typed([0])), bad)
	_assert_rejected(
		engine, EngineAction.choose_set(1, board, _none()), EngineError.Code.WRONG_SEAT
	)
	_assert_rejected(engine, EngineAction.choose(0, board, 0), EngineError.Code.NOT_ELIGIBLE)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_CHOICE)
	var single: MatchEngine = _discard_prompt_engine()
	if single != null:
		var hand_set: EngineAction = EngineAction.choose_set(single.awaited_seat(), 0, _typed([0]))
		_assert_rejected(single, hand_set, EngineError.Code.NOT_ELIGIBLE)
	var idle: MatchEngine = _started(SEED)
	var early: EngineAction = EngineAction.choose_set(idle.awaited_seat(), board, _none())
	_assert_rejected(idle, early, EngineError.Code.NO_PROMPT)
	var declined: ApplyResult = engine.apply(EngineAction.choose_set(0, board, _none()))
	assert_bool(declined.ok).is_true()
	var kinds: Array[int] = _kinds(declined.events)
	assert_array([kinds[0], kinds[1]]).is_equal([MADE, FIZZLED])
	assert_array(_of_kind(declined.events, MatchEvent.Kind.CARD_DESTROYED)).is_empty()


# --- The decline (DC-11 T09; cycle 8 R52, R53, P10) ------------------------------------


## R53: a decline with no prompt open (NO_PROMPT), from the seat not prompted (WRONG_SEAT)
## or on a prompt that is not optional (NOT_OPTIONAL; every card prompt) changes nothing:
## state, accepted actions and log. A decline carrying cards or a set is MALFORMED.
func test_decline_errors_leave_the_state_and_the_log_unchanged() -> void:
	var fresh: MatchEngine = _started(SEED)
	var awaited: int = fresh.awaited_seat()
	_assert_rejected(fresh, EngineAction.decline(awaited), EngineError.Code.NO_PROMPT)
	_assert_rejected(fresh, EngineAction.decline(1 - awaited), EngineError.Code.NO_PROMPT)
	var engine: MatchEngine = _discard_prompt_engine()
	assert_object(engine).override_failure_message("no seed gives c09 by turn 3").is_not_null()
	if engine == null:
		return
	var asked: int = engine.awaited_seat()
	assert_bool(Choice.is_optional_prompt(engine.open_prompt())).is_false()
	var optional: bool = engine.view_for(asked).prompt["optional"]
	assert_bool(optional).is_false()
	_assert_rejected(engine, EngineAction.decline(1 - asked), EngineError.Code.WRONG_SEAT)
	_assert_rejected(engine, EngineAction.decline(asked), EngineError.Code.NOT_OPTIONAL)
	var carded: EngineAction = EngineAction.decline(asked)
	carded.cards.append(_hand(engine, asked)[0])
	_assert_rejected(engine, carded, EngineError.Code.MALFORMED)
	var with_set: EngineAction = EngineAction.decline(asked)
	with_set.indices.append(0)
	_assert_rejected(engine, with_set, EngineError.Code.MALFORMED)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_CHOICE)
	# A concede still ends it; a decline then meets the match's end.
	assert_bool(engine.apply(EngineAction.concede(asked)).ok).is_true()
	_assert_rejected(engine, EngineAction.decline(asked), EngineError.Code.MATCH_OVER)


## R52: on an optional prompt the prompted seat's decline is accepted and logged like a
## choice: the prompt closes with CHOICE_DECLINED {seat, card, crew: ""} (public), the
## effect does not apply (no CHOICE_MADE, no discard) and the walk resumes in the same
## pulse: c09 scores, the turn ends and turn 4 begins. No card prompt is optional before
## the Crew (T10), so the test marks c09's discard prompt optional on the live state.
func test_a_decline_on_an_optional_prompt_skips_the_effect_and_the_walk_resumes() -> void:
	var engine: MatchEngine = _discard_prompt_engine()
	assert_object(engine).override_failure_message("no seed gives c09 by turn 3").is_not_null()
	if engine == null:
		return
	var asked: int = engine.awaited_seat()
	var c09: int = _id(asked, C09_DRAW_DISCARD)
	engine._state.prompt[Choice.KEY_OPTIONAL] = true
	var view: SeatView = engine.view_for(asked)
	var optional: bool = view.prompt["optional"]
	var resume: String = view.prompt["resume"]
	assert_bool(optional).is_true()
	assert_str(resume).is_equal(Choice.RESUME_WALK)
	_assert_rejected(engine, EngineAction.decline(1 - asked), EngineError.Code.WRONG_SEAT)
	var hand: Array[int] = _hand(engine, asked)
	assert_int(hand.size()).is_equal(MatchRules.HAND_CAP)
	var count: int = engine.accepted_action_count()
	var result: ApplyResult = engine.apply(EngineAction.decline(asked))
	assert_bool(result.ok).is_true()
	var declined: Dictionary = {"seat": asked, "card": c09, "crew": ""}
	_assert_event(result.events[0], MatchEvent.Kind.CHOICE_DECLINED, declined, PUBLIC)
	var kinds: Array[int] = _kinds(result.events)
	assert_bool(kinds.has(MADE)).is_false()
	assert_bool(kinds.has(DISCARDED)).is_false()
	assert_bool(_cards_of(result.events, SCORED).has(c09)).is_true()
	assert_int(kinds.find(MatchEvent.Kind.TURN_ENDED)).is_greater(kinds.find(SCORED))
	# Nothing was discarded; turn 4's draw burns at the cap.
	assert_array(_hand(engine, asked)).is_equal(hand)
	assert_dict(engine.open_prompt()).is_empty()
	assert_int(engine.energy()).is_equal(4)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_int(engine.accepted_action_count()).is_equal(count + 1)
	var entry: String = '{"k":"decline","s":%d}' % asked
	var text: String = engine.action_log().to_json()
	assert_bool(text.contains(entry)).override_failure_message(text).is_true()


## Records what a walk sends to its sink, with each event's owner.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
