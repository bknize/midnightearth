# gdlint: disable=max-public-methods
class_name TestEffects
extends GdUnitTestSuite
## EffectResolver and the walk's trigger hooks (DC-05 T04; R13, R15, R18-R27, plan P6-P8,
## P11, P14): one case per verb with its event list, the bonus-0 mark (spent on the next
## reveal, no stacking), the random destroy (fizzle on an empty row, the engine stream, the
## preview's rule, hidden information), flat-up after every score, the energy carry (only
## while the card is on the row at turn end), the free first card (lost when unused),
## on-opponent-reveal (an in-memory card: no deck card uses it), and the round boundary.
## The four prompt verbs (DC-05 T05) are in test_choices.gd. Since DC-06 the destroy marks
## its card in place; the destroyed card's own rules (its flip, the live-only pick, the
## carry and the turn-end clear) are in test_destroyed.gd.
##
## Walk cases build MatchStates directly. Engine cases play seed 1 and plant the effect
## card they need into a hand (_plant): a fixture shortcut, since which turn a given card
## reaches a hand depends on the shuffle. Instance id = seat * DECK_SIZE + index.

const SEED: int = 1
## Seeds tried for the destroy's pick; two of them must pick different cards.
const PICK_SEEDS: int = 20
const MAX_STEPS: int = 100

# Definition indices in the default card list (test_fixture_cards_are_the_plan_table).
const C01_DRAW: int = 0
const C02: int = 1
const C03: int = 2
const C04: int = 3
const C05_CARRY: int = 4
const C06_FLAT_UP: int = 5
const C07: int = 6
const C08: int = 7
const C09_DRAW_DISCARD: int = 8
const C10_FREE_FIRST: int = 9
const C11: int = 10
const C12_SWAP: int = 11
const C13: int = 12
const C15_BONUS_ZERO: int = 14
const C17_RETURN: int = 16
const C19_DESTROY: int = 18

const PUBLIC: int = MatchEvent.PUBLIC
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.EFFECT_FIRED
const FIZZLED: int = MatchEvent.Kind.EFFECT_FIZZLED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const BURNED: int = MatchEvent.Kind.CARD_BURNED
const STATS: int = MatchEvent.Kind.STATS_CHANGED
const DESTROYED: int = MatchEvent.Kind.CARD_DESTROYED
const ZERO_SET: int = MatchEvent.Kind.BONUS_ZERO_SET
const CARRIED: int = MatchEvent.Kind.ENERGY_CARRIED
const FREE_SET: int = MatchEvent.Kind.FREE_FIRST_SET

var _cached_db: CardDb = null
var _cached_watcher_db: CardDb = null
var _cached_swap_watcher_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


## The default card list with c02 given an on-opponent-reveal "draw 1" (in-memory JSON;
## C13: the framework supports the trigger, no deck card uses it).
func _watcher_db() -> CardDb:
	if _cached_watcher_db != null:
		return _cached_watcher_db
	var text: String = FileAccess.get_file_as_string(CardDb.DEFAULT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	var entry: Dictionary = entries[C02]
	entry["effect"] = {
		"trigger": "on_opponent_reveal",
		"verb": "draw",
		"amount": 1,
		"text": "When your opponent reveals a card, draw a card.",
	}
	_cached_watcher_db = CardDb.from_json(JSON.stringify(root))
	return _cached_watcher_db


## The default card list with two watchers (in-memory JSON, as _watcher_db): c02 swaps
## places on an opponent's reveal (a prompt over its own row) and c03 draws 1. For the
## watcher snapshot (DC-05 T13): a swap by one watcher reorders the row the others sit on.
func _swap_watcher_db() -> CardDb:
	if _cached_swap_watcher_db != null:
		return _cached_swap_watcher_db
	var text: String = FileAccess.get_file_as_string(CardDb.DEFAULT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	var swapper: Dictionary = entries[C02]
	swapper["effect"] = {
		"trigger": "on_opponent_reveal",
		"verb": "swap_places",
		"amount": 0,
		"text": "When your opponent reveals a card, swap places with a card on your board.",
	}
	var drawer: Dictionary = entries[C03]
	drawer["effect"] = {
		"trigger": "on_opponent_reveal",
		"verb": "draw",
		"amount": 1,
		"text": "When your opponent reveals a card, draw a card.",
	}
	_cached_swap_watcher_db = CardDb.from_json(JSON.stringify(root))
	return _cached_swap_watcher_db


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


## Runs one live walk on `state` from begin() to its end, recording the events.
func _walk(state: MatchState, cards: CardDb, rng: MatchRng, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		var paused: bool = ScoreWalk.step(state, cards, rng, recorder.record, null)
		assert_bool(paused).is_false()
		guard += 1


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


func _payload_ints(event: MatchEvent, key: String) -> Array[int]:
	var raw: Array = event.payload[key]
	return _typed(raw)


func _payload_flags(event: MatchEvent, key: String) -> Array[bool]:
	var raw: Array = event.payload[key]
	var out: Array[bool] = []
	out.assign(raw)
	return out


## The `card` of every event of `kind`, in order.
func _cards_of(events: Array[MatchEvent], kind: int) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, kind):
		out.append(_payload_int(event, "card"))
	return out


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


func _fired(seat: int, card: int, verb: String, trigger: String) -> Dictionary:
	return {"seat": seat, "card": card, "verb": verb, "trigger": trigger}


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = MatchEngine.create(match_seed, _db())
	engine.start()
	return engine


func _pass(engine: MatchEngine) -> ApplyResult:
	return engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))


func _pass_until_turn(engine: MatchEngine, turn: int) -> void:
	while engine.energy() < turn:
		if not _pass(engine).ok:
			return


func _commit(engine: MatchEngine, seat: int, cards: Array[int]) -> ApplyResult:
	return engine.apply(EngineAction.commit(seat, cards))


## Moves `card` (one of `seat`'s instances) into `seat`'s hand from its deck or burn pile;
## when the hand is at the cap, its first card goes to the deck's end to make room.
func _plant(engine: MatchEngine, seat: int, card: int) -> void:
	var piles: MatchState.SeatPiles = engine._state.seats[seat]
	if piles.hand.has(card):
		return
	piles.deck.erase(card)
	piles.burned.erase(card)
	if piles.hand.size() >= MatchRules.HAND_CAP:
		var spare: int = piles.hand[0]
		piles.hand.remove_at(0)
		piles.deck.append(spare)
	piles.hand.append(card)


func _energy_ints(engine: MatchEngine, key: String) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var energy: Dictionary = state["energy"]
	var raw: Array = energy[key]
	return _typed(raw)


func _energy_flags(engine: MatchEngine, key: String) -> Array[bool]:
	var state: Dictionary = engine.full_state()
	var energy: Dictionary = state["energy"]
	var raw: Array = energy[key]
	var out: Array[bool] = []
	out.assign(raw)
	return out


func _bonus_zero_pending(engine: MatchEngine) -> Array[bool]:
	var state: Dictionary = engine.full_state()
	var raw: Array = state["bonus_zero_pending"]
	var out: Array[bool] = []
	out.assign(raw)
	return out


func _pair(seat: int, mine: int, theirs: int) -> Array[int]:
	var out: Array[int] = [theirs, theirs]
	out[seat] = mine
	return out


# --- Fixture --------------------------------------------------------------------------


func test_fixture_cards_are_the_plan_table() -> void:
	var expected: Dictionary = {
		C01_DRAW: "draw",
		C05_CARRY: "carry_energy",
		C06_FLAT_UP: "flat_up",
		C09_DRAW_DISCARD: "draw_then_discard",
		C10_FREE_FIRST: "free_first_next_turn",
		C12_SWAP: "swap_places",
		C15_BONUS_ZERO: "opponent_next_no_bonus",
		C17_RETURN: "return_at_turn_end",
		C19_DESTROY: "destroy_random_opponent",
	}
	for index: int in expected:
		var verb: String = expected[index]
		var effect: CardEffect = _db().card_at(index).effect
		assert_object(effect).is_not_null()
		assert_str(CardEffect.verb_name(effect.verb)).is_equal(verb)
	# c13 is vanilla since its switch retired (DC-07 T01, C20).
	for index: int in [C02, C03, C04, C07, C08, C11, C13]:
		assert_object(_db().card_at(index).effect).is_null()
	assert_bool(_watcher_db().is_valid()).is_true()
	var watcher: CardEffect = _watcher_db().card_at(C02).effect
	assert_int(watcher.trigger).is_equal(CardEffect.Trigger.ON_OPPONENT_REVEAL)
	assert_int(watcher.verb).is_equal(CardEffect.Verb.DRAW)


# --- DRAW (R20, R25) ------------------------------------------------------------------


func test_draw_draws_for_the_owner_with_a_private_event() -> void:
	var card: int = _id(0, C01_DRAW)
	var state: MatchState = _state(_typed([card]), _none(), 0)
	var top: int = _id(0, C02)
	var next: int = _id(0, C03)
	state.seats[0].deck.assign([top, next])
	var recorder: Recorder = Recorder.new()
	_walk(state, _db(), null, recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, DRAWN, SCORED]))
	_assert_event(events[1], FIRED, _fired(0, card, "draw", "on_reveal"), PUBLIC)
	_assert_event(events[2], DRAWN, {"seat": 0, "card": top}, 0)
	assert_array(state.seats[0].hand).is_equal(_typed([top]))
	assert_array(state.seats[0].deck).is_equal(_typed([next]))
	# The other seat sees the draw without the card (the turn-start draw's privacy).
	var redacted: MatchEvent = events[2].redacted_for(1)
	assert_int(_payload_int(redacted, "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_int(_payload_int(redacted, "seat")).is_equal(0)


func test_draw_at_the_hand_cap_burns() -> void:
	var card: int = _id(0, C01_DRAW)
	var state: MatchState = _state(_typed([card]), _none(), 0)
	var held: Array[int] = []
	for index: int in range(10, 10 + MatchRules.HAND_CAP):
		held.append(_id(0, index))
	state.seats[0].hand.assign(held)
	var top: int = _id(0, C02)
	state.seats[0].deck.assign([top])
	var recorder: Recorder = Recorder.new()
	_walk(state, _db(), null, recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, BURNED, SCORED]))
	_assert_event(events[2], BURNED, {"seat": 0, "card": top}, 0)
	assert_array(state.seats[0].hand).is_equal(held)
	assert_array(state.seats[0].burned).is_equal(_typed([top]))
	assert_array(state.seats[0].deck).is_empty()


# --- FREE_FIRST_NEXT_TURN (R20, P7) ---------------------------------------------------


func test_free_first_sets_the_owners_flag() -> void:
	var card: int = _id(1, C10_FREE_FIRST)
	var state: MatchState = _state(_none(), _typed([card]), 1)
	var recorder: Recorder = Recorder.new()
	_walk(state, _db(), null, recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, FREE_SET, SCORED]))
	_assert_event(events[1], FIRED, _fired(1, card, "free_first_next_turn", "on_reveal"), PUBLIC)
	_assert_event(events[2], FREE_SET, {"seat": 1}, PUBLIC)
	var flags: Array[bool] = [false, true]
	assert_array(state.energy.free_first).is_equal(flags)


## Turn 3: the awaited seat plays the free-card card and the other passes. Returns the
## second commit's result; the seat is awaited first on turn 4.
func _play_free_card(engine: MatchEngine) -> ApplyResult:
	_pass_until_turn(engine, 3)
	var seat: int = engine.awaited_seat()
	var free_card: int = _id(seat, C10_FREE_FIRST)
	_plant(engine, seat, free_card)
	assert_bool(_commit(engine, seat, _typed([free_card])).ok).is_true()
	return _pass(engine)


func test_the_free_first_card_applies_to_the_next_turn() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 3)
	var seat: int = engine.awaited_seat()
	var result: ApplyResult = _play_free_card(engine)
	assert_bool(result.ok).is_true()
	var set_events: Array[MatchEvent] = _of_kind(result.events, FREE_SET)
	assert_int(set_events.size()).is_equal(1)
	assert_int(_payload_int(set_events[0], "seat")).is_equal(seat)
	var started: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)[0]
	var flags: Array[bool] = [false, false]
	flags[seat] = true
	assert_array(_payload_flags(started, "free_first")).is_equal(flags)
	# Turn 4: the seat won turn 3, so it commits first; a cost-7 card leftmost costs 0.
	assert_int(engine.awaited_seat()).is_equal(seat)
	var dear: int = _id(seat, C19_DESTROY)
	_plant(engine, seat, dear)
	assert_int(engine.budget_for(seat)).is_equal(4)
	assert_bool(_commit(engine, seat, _typed([dear])).ok).is_true()
	assert_array(_energy_ints(engine, "spent")).is_equal(_pair(seat, 0, 0))
	assert_array(_energy_flags(engine, "free_first")).is_equal([false, false])


func test_an_unused_free_first_card_is_lost() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 3)
	var seat: int = engine.awaited_seat()
	assert_bool(_play_free_card(engine).ok).is_true()
	var flags: Array[bool] = [false, false]
	flags[seat] = true
	assert_array(_energy_flags(engine, "free_first")).is_equal(flags)
	# Turn 4: the seat passes; its free card is consumed unused (P7).
	assert_int(engine.awaited_seat()).is_equal(seat)
	assert_bool(_pass(engine).ok).is_true()
	assert_array(_energy_flags(engine, "free_first")).is_equal([false, false])
	var result: ApplyResult = _pass(engine)
	var started: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)[0]
	assert_int(_payload_int(started, "turn")).is_equal(5)
	assert_array(_payload_flags(started, "free_first")).is_equal([false, false])
	# Turn 5: the same cost-7 card is now over the budget of 5.
	assert_int(engine.awaited_seat()).is_equal(seat)
	var dear: int = _id(seat, C19_DESTROY)
	_plant(engine, seat, dear)
	var before: Dictionary = engine.full_state()
	var refused: ApplyResult = _commit(engine, seat, _typed([dear]))
	assert_bool(refused.ok).is_false()
	assert_int(refused.error).is_equal(EngineError.Code.OVER_BUDGET)
	assert_dict(engine.full_state()).is_equal(before)


# --- OPPONENT_NEXT_NO_BONUS (R20, R22) ------------------------------------------------


func test_bonus_zero_is_spent_on_the_opponents_next_reveal() -> void:
	var source: int = _id(0, C15_BONUS_ZERO)
	var hit: int = _id(1, C03)
	var spared: int = _id(1, C07)
	var state: MatchState = _state(_typed([source]), _typed([hit, spared]), 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, _db(), null, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [
		REVEALED, FIRED, ZERO_SET, SCORED, REVEALED, STATS, SCORED, REVEALED, SCORED
	]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(
		events[1], FIRED, _fired(0, source, "opponent_next_no_bonus", "on_reveal"), PUBLIC
	)
	_assert_event(events[2], ZERO_SET, {"seat": 1}, PUBLIC)
	_assert_event(
		events[5],
		STATS,
		{"seat": 1, "card": hit, "flat": 1, "bonus": 0, "cause": "bonus_zero"},
		PUBLIC
	)
	# Applied before the card scores: c03 (1, 1) scores 1 x 1; c07 (2, 1) keeps its bonus.
	assert_int(_payload_int(events[6], "bonus")).is_equal(0)
	assert_int(_payload_int(events[6], "added")).is_equal(1)
	assert_int(_payload_int(events[8], "bonus")).is_equal(1)
	assert_int(_payload_int(events[8], "added")).is_equal(4)
	assert_array(state.scores).is_equal(_typed([5, 5]))
	assert_array(state.bonus_zero_pending).is_equal([false, false])
	assert_bool(state.card_state(hit).bonus_zero).is_true()
	assert_object(state.card_state(spared)).is_null()
	assert_vector(ScoreWalk.effective(hit, state, _db())).is_equal(Vector2i(1, 0))


func test_bonus_zero_does_not_stack() -> void:
	var source: int = _id(0, C15_BONUS_ZERO)
	var first: int = _id(1, C03)
	var second: int = _id(1, C07)
	var state: MatchState = _state(_typed([source]), _typed([first, second]), 0)
	_reveal(state, 0, _typed([source]))
	for _set: int in range(2):
		var outcome: EffectResolver.Outcome = EffectResolver.apply(
			state, _db(), null, null, 0, source
		)
		assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, ZERO_SET]))
		assert_bool(outcome.needs_prompt()).is_false()
	assert_array(state.bonus_zero_pending).is_equal([false, true])
	var recorder: Recorder = Recorder.new()
	_walk(state, _db(), null, recorder)
	# One mark, one card: only the first reveal loses its bonus.
	var changed: Array[MatchEvent] = _of_kind(recorder.events, STATS)
	assert_int(changed.size()).is_equal(1)
	assert_int(_payload_int(changed[0], "card")).is_equal(first)
	assert_object(state.card_state(second)).is_null()
	assert_array(state.bonus_zero_pending).is_equal([false, false])
	assert_int(state.scores[1]).is_equal(1 + 2 * 2)


func test_bonus_zero_waits_for_a_later_walk_and_ignores_the_setter_seat() -> void:
	var source: int = _id(0, C15_BONUS_ZERO)
	var own_new: int = _id(0, C04)
	var old: int = _id(1, C07)
	var state: MatchState = _state(_typed([source, own_new]), _typed([old]), 0)
	_reveal(state, 0, _typed([source]))
	_reveal(state, 1, _typed([old]))
	EffectResolver.apply(state, _db(), null, null, 0, source)
	assert_array(state.bonus_zero_pending).is_equal([false, true])
	# This walk reveals only the setter's own card: the mark waits.
	var recorder: Recorder = Recorder.new()
	_walk(state, _db(), null, recorder)
	assert_array(_of_kind(recorder.events, STATS)).is_empty()
	assert_array(state.bonus_zero_pending).is_equal([false, true])
	assert_object(state.card_state(old)).is_null()
	# A later walk: the opponent's next new card takes it.
	var late: int = _id(1, C03)
	state.seats[1].board.append(late)
	var later: Recorder = Recorder.new()
	_walk(state, _db(), null, later)
	var changed: Array[MatchEvent] = _of_kind(later.events, STATS)
	assert_int(changed.size()).is_equal(1)
	assert_int(_payload_int(changed[0], "card")).is_equal(late)
	assert_array(state.bonus_zero_pending).is_equal([false, false])


# --- DESTROY_RANDOM_OPPONENT (R20, R23, R26, R27) -------------------------------------


func test_destroy_fizzles_on_an_empty_row_without_touching_the_stream() -> void:
	var card: int = _id(0, C19_DESTROY)
	var state: MatchState = _state(_typed([card]), _none(), 0)
	var rng: MatchRng = MatchRng.new(SEED)
	var stream: int = rng.state
	var recorder: Recorder = Recorder.new()
	_walk(state, _db(), rng, recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))
	_assert_event(events[1], FIRED, _fired(0, card, "destroy_random_opponent", "on_reveal"), PUBLIC)
	_assert_event(
		events[2], FIZZLED, {"seat": 0, "card": card, "verb": "destroy_random_opponent"}, PUBLIC
	)
	assert_int(rng.state).is_equal(stream)


## Seat 0's destroy card against four face-down seat-1 cards, walked with `match_seed`'s
## stream.
func _destroy_case(match_seed: int, recorder: Recorder) -> MatchState:
	var source: int = _id(0, C19_DESTROY)
	var row: Array[int] = [_id(1, C02), _id(1, C03), _id(1, C04), _id(1, C07)]
	var state: MatchState = _state(_typed([source]), row, 0)
	_walk(state, _db(), MatchRng.new(match_seed), recorder)
	return state


## DC-06 R12-R14: the destroy marks the picked card in place; the row keeps its size, the
## cursor still reaches the card's slot, and its flip is a CARD_REVEALED with `destroyed`
## true and nothing after it (no effect, no score).
func test_destroy_picks_from_the_stream_and_marks_the_card_in_place() -> void:
	var source: int = _id(0, C19_DESTROY)
	var row: Array[int] = [_id(1, C02), _id(1, C03), _id(1, C04), _id(1, C07)]
	var picks: Dictionary = {}
	for match_seed: int in range(1, PICK_SEEDS + 1):
		var recorder: Recorder = Recorder.new()
		var state: MatchState = _destroy_case(match_seed, recorder)
		var events: Array[MatchEvent] = recorder.events
		# The pick is the stream's first draw: pick_index over the live cards of the row.
		var slot: int = MatchRng.new(match_seed).pick_index(row.size())
		var target: int = row[slot]
		picks[target] = true
		var expected: Array[int] = [REVEALED, FIRED, DESTROYED, SCORED]
		for at: int in range(row.size()):
			expected.append(REVEALED)
			if at != slot:
				expected.append(SCORED)
		assert_array(_kinds(events)).is_equal(expected)
		# Face down when destroyed: private to its seat (orchestrator decision, DC-06 R20).
		_assert_event(events[2], DESTROYED, {"seat": 1, "card": target, "slot": slot}, 1)
		var seen: MatchEvent = events[2].redacted_for(0)
		assert_int(_payload_int(seen, "card")).is_equal(MatchEvent.HIDDEN_CARD)
		assert_int(_payload_int(seen, "seat")).is_equal(1)
		assert_int(_payload_int(seen, "slot")).is_equal(slot)
		# It keeps its slot, marked (R12); the row is the same size.
		assert_array(state.seats[1].board).is_equal(row)
		assert_bool(state.is_destroyed(target)).is_true()
		assert_bool(state.card_state(target).destroyed).is_true()
		assert_array(state.seats[1].burned).is_empty()
		# The cursor flips it like any card (R14) and every reveal carries the flag.
		assert_array(_cards_of(events, REVEALED)).is_equal(_typed([source] + row))
		for reveal: MatchEvent in _of_kind(events, REVEALED):
			var flagged: bool = reveal.payload["destroyed"]
			assert_bool(flagged).is_equal(_payload_int(reveal, "card") == target)
		# Nothing scores it (R13).
		var rest: Array[int] = []
		rest.assign(row)
		rest.erase(target)
		assert_array(_cards_of(events, SCORED)).is_equal(_typed([source] + rest))
		assert_array(state.walk.cursor).is_equal(_typed([1, row.size()]))
		assert_bool(state.seats[1].is_revealed(target)).is_true()
		var held: Dictionary = state.to_dict()["card_states"]
		assert_int(held.size()).is_equal(1)
	# Two seeds differ.
	assert_int(picks.size()).is_greater(1)


func test_destroy_with_one_seed_repeats() -> void:
	var first: Recorder = Recorder.new()
	var second: Recorder = Recorder.new()
	var a: MatchState = _destroy_case(7, first)
	var b: MatchState = _destroy_case(7, second)
	assert_dict(b.to_dict()).is_equal(a.to_dict())
	var a_events: Array[Dictionary] = []
	var b_events: Array[Dictionary] = []
	for event: MatchEvent in first.events:
		a_events.append(event.to_dict())
	for event: MatchEvent in second.events:
		b_events.append(event.to_dict())
	assert_array(b_events).is_equal(a_events)


## A revealed card's destroy is public; the card keeps its modifiers and its slot until the
## turn-end clear (DC-06 R12, R18, R22), which burns it with a public DESTROYED_CLEARED.
func test_destroying_a_revealed_card_is_public_and_it_clears_at_turn_end() -> void:
	var source: int = _id(0, C19_DESTROY)
	var target: int = _id(1, C04)
	var state: MatchState = _state(_typed([source]), _typed([target]), 0)
	_reveal(state, 1, _typed([target]))
	state.card_state_for(target).flat_delta = 2
	var recorder: Recorder = Recorder.new()
	_walk(state, _db(), MatchRng.new(SEED), recorder)
	var destroyed: Array[MatchEvent] = _of_kind(recorder.events, DESTROYED)
	assert_int(destroyed.size()).is_equal(1)
	_assert_event(destroyed[0], DESTROYED, {"seat": 1, "card": target, "slot": 0}, PUBLIC)
	# Face up when destroyed: its pulse makes no event at all.
	assert_array(_kinds(recorder.events)).is_equal(_typed([REVEALED, FIRED, DESTROYED, SCORED]))
	assert_int(state.card_state(target).flat_delta).is_equal(2)
	assert_bool(state.is_destroyed(target)).is_true()
	assert_array(state.seats[1].board).is_equal(_typed([target]))
	assert_int(state.scores[1]).is_equal(0)
	# Turn end: it leaves for the burn pile, the mark and the modifiers with it.
	var cleared: Array[MatchEvent] = EffectResolver.clear_destroyed(state)
	assert_int(cleared.size()).is_equal(1)
	var payload: Dictionary = {"seat": 1, "card": target, "slot": 0}
	_assert_event(cleared[0], MatchEvent.Kind.DESTROYED_CLEARED, payload, PUBLIC)
	assert_object(state.card_state(target)).is_null()
	assert_bool(state.is_destroyed(target)).is_false()
	assert_array(state.seats[1].board).is_empty()
	assert_array(state.seats[1].revealed_ids()).is_empty()
	assert_array(state.seats[1].burned).is_equal(_typed([target]))
	assert_array(EffectResolver.clear_destroyed(state)).is_empty()


func test_a_preview_destroys_the_lowest_flat_card_without_the_stream() -> void:
	var source: int = _id(0, C19_DESTROY)
	# Flats 3, 2, 4: the c02 in the middle is the lowest.
	var row: Array[int] = [_id(1, C04), _id(1, C02), _id(1, C08)]
	var state: MatchState = _state(_typed([source]), row, 0)
	var rng: MatchRng = MatchRng.new(SEED)
	var stream: int = rng.state
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	var paused: bool = ScoreWalk.run(state, _db(), rng, recorder.record, PreviewPolicy.new())
	assert_bool(paused).is_false()
	assert_array(recorder.events).is_empty()
	assert_int(rng.state).is_equal(stream)
	# Marked in place (DC-06 R12, R23): the row keeps its three slots.
	assert_array(state.seats[1].board).is_equal(row)
	assert_bool(state.is_destroyed(_id(1, C02))).is_true()
	assert_array(state.seats[1].burned).is_empty()
	assert_array(state.scores).is_equal(_typed([7, 3 + 4]))


# --- FLAT_UP_ON_SCORE (R15, R20, R21) -------------------------------------------------


func test_flat_up_applies_after_each_scoring() -> void:
	var card: int = _id(0, C06_FLAT_UP)
	var state: MatchState = _state(_typed([card]), _none(), 0)
	for walk: int in range(3):
		var recorder: Recorder = Recorder.new()
		_walk(state, _db(), null, recorder)
		var events: Array[MatchEvent] = recorder.events
		var expected: Array[int] = [SCORED, FIRED, STATS]
		if walk == 0:
			expected.push_front(REVEALED)
		assert_array(_kinds(events)).is_equal(expected)
		var at: int = expected.size() - 3
		# The pulse scores the flat as it stood, then the flat rises by 1 (c06: flat 1).
		assert_int(_payload_int(events[at], "flat")).is_equal(1 + walk)
		assert_int(_payload_int(events[at], "added")).is_equal(1 + walk)
		_assert_event(events[at + 1], FIRED, _fired(0, card, "flat_up", "on_score"), PUBLIC)
		_assert_event(
			events[at + 2],
			STATS,
			{"seat": 0, "card": card, "flat": 2 + walk, "bonus": 0, "cause": "flat_up"},
			PUBLIC
		)
	# Pulsed three times: shown flat is base + 3.
	assert_int(state.card_state(card).flat_delta).is_equal(3)
	assert_vector(ScoreWalk.effective(card, state, _db())).is_equal(Vector2i(4, 0))


# --- CARRY_ENERGY (R9, R20, P7, P14) --------------------------------------------------


func test_energy_carries_only_while_the_card_is_on_the_row_at_turn_end() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, 4)
	var seat: int = engine.awaited_seat()
	var carrier: int = _id(seat, C05_CARRY)
	_plant(engine, seat, carrier)
	assert_bool(_commit(engine, seat, _typed([carrier])).ok).is_true()
	var result: ApplyResult = _pass(engine)
	assert_bool(result.ok).is_true()
	# Spec scenario: 2 of 4 spent, so turn 5's budget reads 5 + 2.
	var kinds: Array[int] = _kinds(result.events)
	var at: int = kinds.find(CARRIED)
	assert_int(at).is_greater(0)
	_assert_event(
		result.events[at - 1], FIRED, _fired(seat, carrier, "carry_energy", "ongoing"), PUBLIC
	)
	_assert_event(result.events[at], CARRIED, {"seat": seat, "amount": 2}, PUBLIC)
	assert_int(kinds[at + 1]).is_equal(MatchEvent.Kind.TURN_ENDED)
	# Ongoing: nothing fired at its reveal, only at turn end.
	assert_int(_of_kind(result.events, FIRED).size()).is_equal(1)
	var started: MatchEvent = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)[0]
	assert_array(_payload_ints(started, "budgets")).is_equal(_pair(seat, 7, 5))
	assert_int(engine.budget_for(seat)).is_equal(7)
	# Turn 5, still on the row, nothing spent: budget - spent = 7 carries (P7).
	assert_int(engine.awaited_seat()).is_equal(seat)
	_pass(engine)
	result = _pass(engine)
	var carried: Array[MatchEvent] = _of_kind(result.events, CARRIED)
	assert_int(carried.size()).is_equal(1)
	assert_int(_payload_int(carried[0], "amount")).is_equal(7)
	assert_int(engine.budget_for(seat)).is_equal(6 + 7)
	assert_int(engine.budget_for(1 - seat)).is_equal(6)
	# Turn 6 passes; turn 7: the opponent's destroy takes the card, the only one on the row.
	_pass(engine)
	_pass(engine)
	assert_int(engine.energy()).is_equal(7)
	assert_int(engine.awaited_seat()).is_equal(seat)
	assert_bool(_pass(engine).ok).is_true()
	var other: int = 1 - seat
	var destroyer: int = _id(other, C19_DESTROY)
	_plant(engine, other, destroyer)
	result = _commit(engine, other, _typed([destroyer]))
	assert_bool(result.ok).is_true()
	var destroyed: Array[MatchEvent] = _of_kind(result.events, DESTROYED)
	assert_int(destroyed.size()).is_equal(1)
	_assert_event(destroyed[0], DESTROYED, {"seat": seat, "card": carrier, "slot": 0}, PUBLIC)
	# Not on the row at turn end: nothing carries.
	assert_array(_of_kind(result.events, CARRIED)).is_empty()


func test_settle_energy_without_a_revealed_carry_card_zeroes_the_carry() -> void:
	var carrier: int = _id(0, C05_CARRY)
	var state: MatchState = _state(_typed([carrier]), _none(), 0)
	state.turn = 4
	state.energy.carry[0] = 3
	state.energy.carry[1] = 2
	state.energy.spent[0] = 1
	# Face down (never true at a real turn end): it does not carry.
	assert_array(EffectResolver.settle_energy(state, _db())).is_empty()
	assert_array(state.energy.carry).is_equal(_typed([0, 0]))
	# Revealed: budget 4 + 0 less 1 spent.
	_reveal(state, 0, _typed([carrier]))
	var events: Array[MatchEvent] = EffectResolver.settle_energy(state, _db())
	assert_array(_kinds(events)).is_equal(_typed([FIRED, CARRIED]))
	_assert_event(events[1], CARRIED, {"seat": 0, "amount": 3}, PUBLIC)
	assert_array(state.energy.carry).is_equal(_typed([3, 0]))


# --- ON_OPPONENT_REVEAL (R19, C13) ----------------------------------------------------


func test_on_opponent_reveal_fires_once_per_revealed_card_of_the_other_seat() -> void:
	var watcher: int = _id(0, C02)
	var theirs: Array[int] = [_id(1, C03), _id(1, C04)]
	var state: MatchState = _state(_typed([watcher]), theirs, 0)
	_reveal(state, 0, _typed([watcher]))
	var deck: Array[int] = [_id(0, C11), _id(0, C08), _id(0, C07)]
	state.seats[0].deck.assign(deck)
	var recorder: Recorder = Recorder.new()
	_walk(state, _watcher_db(), null, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [
		SCORED, REVEALED, FIRED, DRAWN, SCORED, REVEALED, FIRED, DRAWN, SCORED
	]
	assert_array(_kinds(events)).is_equal(expected)
	for at: int in [2, 6]:
		_assert_event(events[at], FIRED, _fired(0, watcher, "draw", "on_opponent_reveal"), PUBLIC)
	_assert_event(events[3], DRAWN, {"seat": 0, "card": deck[0]}, 0)
	_assert_event(events[7], DRAWN, {"seat": 0, "card": deck[1]}, 0)
	assert_array(state.seats[0].hand).is_equal(_typed([deck[0], deck[1]]))


func test_on_opponent_reveal_needs_its_card_revealed_and_ignores_its_own_seat() -> void:
	var own: int = _id(0, C04)
	var watcher: int = _id(0, C02)
	var theirs: Array[int] = [_id(1, C03), _id(1, C07), _id(1, C08)]
	# Seat 1 first: 1-0, 0-0, 1-1, 0-1 (the watcher flips), 1-2.
	var state: MatchState = _state(_typed([own, watcher]), theirs, 1)
	state.seats[0].deck.assign([_id(0, C11)])
	var recorder: Recorder = Recorder.new()
	_walk(state, _watcher_db(), null, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [
		REVEALED,
		SCORED,
		REVEALED,
		SCORED,
		REVEALED,
		SCORED,
		REVEALED,
		SCORED,
		REVEALED,
		FIRED,
		DRAWN,
		SCORED
	]
	assert_array(_kinds(events)).is_equal(expected)
	assert_int(_payload_int(events[8], "card")).is_equal(theirs[2])
	_assert_event(events[9], FIRED, _fired(0, watcher, "draw", "on_opponent_reveal"), PUBLIC)


## Seat 0's revealed `row` of watchers and a vanilla card against one face-down seat-1
## card, seat 1 first: its reveal fires seat 0's watchers. Walks live under
## _swap_watcher_db, answering the swap's prompt with `answer`; returns the events.
func _swap_watcher_walk(row: Array[int], answer: int) -> Array[MatchEvent]:
	var cards: CardDb = _swap_watcher_db()
	var state: MatchState = _state(row, _typed([_id(1, C08)]), 1)
	_reveal(state, 0, row)
	state.seats[0].deck.assign([_id(0, C11), _id(0, C07)])
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	var prompts: int = 0
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		if ScoreWalk.step(state, cards, null, recorder.record, null):
			prompts += 1
			# The snapshot and its next index wait in the walk state with the prompt.
			assert_array(state.walk.paused_watchers).is_not_empty()
			recorder.events.append_array(EffectResolver.answer(state, cards, answer))
		guard += 1
	assert_int(prompts).is_equal(1)
	assert_array(state.walk.paused_watchers).is_empty()
	return recorder.events


## The watchers among `events`' EFFECT_FIRED, in firing order.
func _fired_watchers(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, FIRED):
		var trigger: String = event.payload["trigger"]
		if trigger == "on_opponent_reveal":
			out.append(_payload_int(event, "card"))
	return out


## DC-05 T13: the swapper fires first and its swap moves the drawer to its left. With a
## resume point looked up on the reordered row the drawer would be skipped; the snapshot
## still fires it, once.
func test_a_swap_by_a_watcher_does_not_skip_a_later_watcher() -> void:
	var swapper: int = _id(0, C02)
	var drawer: int = _id(0, C03)
	var plain: int = _id(0, C04)
	for answer: int in [1, 2]:
		var events: Array[MatchEvent] = _swap_watcher_walk(_typed([swapper, drawer, plain]), answer)
		var where: String = "answer %d" % answer
		var order: Array[int] = _fired_watchers(events)
		assert_array(order).override_failure_message(where).is_equal(_typed([swapper, drawer]))
		assert_int(_of_kind(events, DRAWN).size()).override_failure_message(where).is_equal(1)


## DC-05 T13: the drawer fires first, then the swapper's swap moves the drawer to its
## right. A resume point looked up on the reordered row would fire the drawer again; the
## snapshot is done after the swapper.
func test_a_swap_by_a_watcher_does_not_fire_an_earlier_watcher_twice() -> void:
	var swapper: int = _id(0, C02)
	var drawer: int = _id(0, C03)
	var plain: int = _id(0, C04)
	var events: Array[MatchEvent] = _swap_watcher_walk(_typed([drawer, swapper, plain]), 0)
	assert_array(_fired_watchers(events)).is_equal(_typed([drawer, swapper]))
	assert_int(_of_kind(events, DRAWN).size()).is_equal(1)
	var moved: Array[int] = _cards_of(events, MatchEvent.Kind.CARD_MOVED)
	assert_array(moved).is_equal(_typed([swapper, drawer]))


# --- Round boundaries (orchestrator decision) -----------------------------------------


func test_round_start_clears_carry_free_first_and_bonus_zero() -> void:
	var engine: MatchEngine = _started(SEED)
	_pass_until_turn(engine, MatchRules.TURNS)
	var first: int = engine.awaited_seat()
	var second: int = 1 - first
	var first_cards: Array[int] = [_id(first, C10_FREE_FIRST), _id(first, C05_CARRY)]
	var second_cards: Array[int] = [_id(second, C02), _id(second, C15_BONUS_ZERO)]
	for card: int in first_cards:
		_plant(engine, first, card)
	for card: int in second_cards:
		_plant(engine, second, card)
	assert_bool(_commit(engine, first, first_cards).ok).is_true()
	var result: ApplyResult = _commit(engine, second, second_cards)
	assert_bool(result.ok).is_true()
	# All three fire in the round's last turn (the mark lands after the first seat's last
	# reveal, so it is still pending at turn end)...
	var kinds: Array[int] = _kinds(result.events)
	var round_start: int = kinds.find(MatchEvent.Kind.ROUND_STARTED)
	assert_int(round_start).is_greater(0)
	for kind: int in [FREE_SET, ZERO_SET, CARRIED]:
		var at: int = kinds.find(kind)
		assert_int(at).is_greater(0)
		assert_int(at).is_less(round_start)
	var carried: MatchEvent = _of_kind(result.events, CARRIED)[0]
	assert_int(_payload_int(carried, "seat")).is_equal(first)
	assert_int(_payload_int(carried, "amount")).is_equal(MatchRules.TURNS - 5)
	# ...and do nothing for the next round.
	var state: Dictionary = engine.full_state()
	var round_number: int = state["round"]
	assert_int(round_number).is_equal(2)
	assert_array(_energy_ints(engine, "carry")).is_equal(_typed([0, 0]))
	assert_array(_energy_flags(engine, "free_first")).is_equal([false, false])
	assert_array(_bonus_zero_pending(engine)).is_equal([false, false])
	var started: Array[MatchEvent] = _of_kind(result.events, MatchEvent.Kind.TURN_STARTED)
	var opening: MatchEvent = started[started.size() - 1]
	assert_array(_payload_ints(opening, "budgets")).is_equal(_typed([1, 1]))
	assert_array(_payload_flags(opening, "free_first")).is_equal([false, false])


## Records what a walk sends to its sink, with each event's owner.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
