class_name TestScoreWalkMult
extends GdUnitTestSuite
## The hundredths mult (DC-07 T03; spec R10-R14, plan P4, P5): the running mult is an
## integer in hundredths from 100, a ×-part multiplies it rounded to the nearest hundredth,
## a +-part adds whole units, each card adds floor(flat × mult); the no-bonus mark clears
## both parts; `temp_plus` lasts until the walk ends; a preview walk equals the live one.
##
## The pool is the DC-05 fixture with three bonuses edited so both kinds appear: c02 (flat 2)
## +1, c08 (flat 4) ×1.25, c14 (flat 6) +2. Every card named here is effect-free. Instance
## ids are seat * DECK_SIZE + index.

const SEED: int = 1
const MAX_ACTIONS: int = 2000
# Definition indices (= seat-0 instance ids).
const C02_PLUS_1: int = 1
const C03_TIMES_125: int = 2
const C04: int = 3
const C07_TIMES_125: int = 6
const C08_TIMES_125: int = 7
const C13: int = 12
const C14_PLUS_2: int = 13
const C20_TIMES_150: int = 19
## The edited bonuses, by card id.
const EDITS: Dictionary = {"c02": {"plus": 1}, "c08": {"x": 125}, "c14": {"plus": 2}}
const SCORED_KEYS: Array[String] = [
	"seat", "card", "slot", "flat", "times", "plus", "mult", "added", "score", "again"
]

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


## The fixture pool with EDITS applied (the current pool format, 4 since DC-09 T01).
func _db() -> CardDb:
	if _cached_db == null:
		var entries: Array = []
		for def: CardDef in FixtureDecks.cards().cards():
			var entry: Dictionary = def.to_dict()
			if EDITS.has(def.id):
				entry["bonus"] = EDITS[def.id]
			entries.append(entry)
		var root: Dictionary = {"version": CardDb.FORMAT_VERSION, "cards": entries}
		_cached_db = CardDb.from_json(JSON.stringify(root))
	return _cached_db


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## A state with these rows (seat 0, seat 1), nothing revealed, seat 0 committing first.
func _state(row_0: Array[int], row_1: Array[int]) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].board.assign(row_0)
	state.seats[1].board.assign(row_1)
	return state


## Runs the walk on `state` from begin() to its end, live, recording the events.
func _walk(state: MatchState, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < 100:
		var paused: bool = ScoreWalk.step(state, _defs(), null, recorder.record, null)
		assert_bool(paused).is_false()
		guard += 1


## Runs the walk on `state` from begin() to its end as a preview (no sink, no stream).
func _preview(state: MatchState) -> void:
	ScoreWalk.begin(state)
	var paused: bool = ScoreWalk.run(state, _defs(), null, Callable(), PreviewPolicy.new())
	assert_bool(paused).is_false()


func _of_kind(events: Array[MatchEvent], kind: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == kind:
			out.append(event)
	return out


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _eff(card: int, state: MatchState) -> Dictionary:
	return ScoreWalk.effective(card, state, _defs()).to_dict()


func _stats(flat: int, times: int, plus: int) -> Dictionary:
	return {"flat": flat, "times": times, "plus": plus}


## Asserts each CARD_SCORED against [card, flat, times, plus, mult, added, score].
func _assert_scored(events: Array[MatchEvent], expected: Array[Array]) -> void:
	var scored: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CARD_SCORED)
	assert_int(scored.size()).is_equal(expected.size())
	var keys: Array[String] = ["card", "flat", "times", "plus", "mult", "added", "score"]
	for i: int in range(mini(scored.size(), expected.size())):
		var want: Array[int] = _typed(expected[i])
		for k: int in range(keys.size()):
			var where: String = "scored %d %s" % [i, keys[k]]
			var got: int = _payload_int(scored[i], keys[k])
			assert_int(got).override_failure_message(where).is_equal(want[k])


# --- The pool -------------------------------------------------------------------------


func test_the_edited_pool_loads_with_both_bonus_kinds() -> void:
	assert_bool(_db().is_valid()).override_failure_message(_db().load_error()).is_true()
	var none: Array[int] = []
	var state: MatchState = _state(none, none)
	assert_dict(_eff(C02_PLUS_1, state)).is_equal(_stats(2, 100, 1))
	assert_dict(_eff(C08_TIMES_125, state)).is_equal(_stats(4, 125, 0))
	assert_dict(_eff(C14_PLUS_2, state)).is_equal(_stats(6, 100, 2))
	assert_dict(_eff(C20_TIMES_150, state)).is_equal(_stats(7, 150, 0))
	assert_dict(_eff(C04, state)).is_equal(_stats(3, 100, 0))


# --- R10-R12, P4: the pulse math ------------------------------------------------------


## Spec scenario: [flat 4 ×1.25, flat 2 +1, flat 3] walks from ×1.00: the mult goes ×1.25 →
## ×2.25 → ×2.25 and the score 5 → 9 → 15 (floor 5, 4.5, 6.75).
func test_the_spec_row_scores_5_9_15_with_mults_125_225_225() -> void:
	var none: Array[int] = []
	var state: MatchState = _state(_typed([C08_TIMES_125, C02_PLUS_1, C04]), none)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var expected: Array[Array] = [
		[C08_TIMES_125, 4, 125, 0, 125, 5, 5],
		[C02_PLUS_1, 2, 100, 1, 225, 4, 9],
		[C04, 3, 100, 0, 225, 6, 15],
	]
	_assert_scored(recorder.events, expected)
	assert_array(state.scores).is_equal(_typed([15, 0]))
	assert_array(state.walk.mult).is_equal(_typed([225, 100]))
	# The payload is exactly the P4 set: no DC-05 `bonus` key.
	for event: MatchEvent in _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED):
		var keys: Array[String] = []
		for key: Variant in event.payload.keys():
			var key_name: String = key
			keys.append(key_name)
		keys.sort()
		var want: Array[String] = []
		want.assign(SCORED_KEYS)
		want.sort()
		assert_array(keys).is_equal(want)


## ×1.25 twice is 1.5625, kept as 156 (rounded to the nearest hundredth), not 157.
func test_times_125_twice_gives_156() -> void:
	var none: Array[int] = []
	var state: MatchState = _state(_typed([C03_TIMES_125, C07_TIMES_125]), none)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	# c03 flat 1: 1 × 1.25 = 1; c07 flat 2: 2 × 1.56 = 3.12, so 3.
	var expected: Array[Array] = [
		[C03_TIMES_125, 1, 125, 0, 125, 1, 1],
		[C07_TIMES_125, 2, 125, 0, 156, 3, 4],
	]
	_assert_scored(recorder.events, expected)
	assert_array(state.walk.mult).is_equal(_typed([156, 100]))
	assert_int(ScoreWalk.times_hundredths(125, 125)).is_equal(156)
	# Halves round up: 1.5 × 1.25 = 1.875 → 188; ×1.00 changes nothing.
	assert_int(ScoreWalk.times_hundredths(150, 125)).is_equal(188)
	assert_int(ScoreWalk.times_hundredths(156, 125)).is_equal(195)
	assert_int(ScoreWalk.times_hundredths(100, 150)).is_equal(150)
	assert_int(ScoreWalk.times_hundredths(225, 100)).is_equal(225)


## A +bonus after a ×-bonus adds whole units to the multiplied mult, and a ×-bonus after a
## +bonus multiplies the sum (R11's order: ×, then +, then the flat).
func test_times_then_plus_and_plus_then_times() -> void:
	var none: Array[int] = []
	var state: MatchState = _state(_typed([C14_PLUS_2, C20_TIMES_150]), none)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	# c14 flat 6 +2: mult 300, 6 × 3 = 18; c20 flat 7 ×1.5: mult 450, 7 × 4.5 = 31.5 → 31.
	var expected: Array[Array] = [
		[C14_PLUS_2, 6, 100, 2, 300, 18, 18],
		[C20_TIMES_150, 7, 150, 0, 450, 31, 49],
	]
	_assert_scored(recorder.events, expected)


# --- R14: the no-bonus mark -----------------------------------------------------------


## The mark spent on a reveal gives that card ×1.00 and +0, whatever its printed bonus and
## its `temp_plus`; STATS_CHANGED carries {flat, times, plus}.
func test_a_no_bonus_mark_zeroes_both_parts() -> void:
	var none: Array[int] = []
	var state: MatchState = _state(_typed([C08_TIMES_125, C02_PLUS_1]), none)
	state.card_state_for(C08_TIMES_125).temp_plus = 2
	assert_dict(_eff(C08_TIMES_125, state)).is_equal(_stats(4, 125, 2))
	state.bonus_zero_pending[0] = true
	var spent: Array[MatchEvent] = EffectResolver.spend_bonus_zero(state, _defs(), 0, C08_TIMES_125)
	assert_int(spent.size()).is_equal(1)
	var changed: Dictionary = {
		"seat": 0,
		"card": C08_TIMES_125,
		"flat": 4,
		"times": 100,
		"plus": 0,
		"cause": EffectResolver.CAUSE_BONUS_ZERO,
	}
	assert_int(spent[0].kind).is_equal(MatchEvent.Kind.STATS_CHANGED)
	assert_dict(spent[0].payload).is_equal(changed)
	assert_bool(state.card_state(C08_TIMES_125).no_bonus).is_true()
	assert_dict(_eff(C08_TIMES_125, state)).is_equal(_stats(4, 100, 0))
	# A +bonus card loses its +-part the same way.
	state.card_state_for(C02_PLUS_1).no_bonus = true
	assert_dict(_eff(C02_PLUS_1, state)).is_equal(_stats(2, 100, 0))


## In a walk: the mark lands on the seat's first reveal, which then scores flat only; the
## next card's +1 still applies.
func test_the_mark_spent_in_a_walk_scores_the_flat_only() -> void:
	var none: Array[int] = []
	var state: MatchState = _state(_typed([C08_TIMES_125, C02_PLUS_1]), none)
	state.bonus_zero_pending[0] = true
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	# c08 4 × 1.00 = 4; c02 +1: mult 200, 2 × 2 = 4.
	var expected: Array[Array] = [
		[C08_TIMES_125, 4, 100, 0, 100, 4, 4],
		[C02_PLUS_1, 2, 100, 1, 200, 4, 8],
	]
	_assert_scored(recorder.events, expected)
	assert_array(state.bonus_zero_pending).is_equal([false, false])


# --- P5: temp_plus lasts until the walk ends ------------------------------------------


func test_temp_plus_is_gone_after_the_walk() -> void:
	var none: Array[int] = []
	var state: MatchState = _state(_typed([C04, C13]), none)
	state.seats[0].revealed[C04] = true
	state.card_state_for(C04).temp_plus = 2
	var before: MatchState = state.duplicate()
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	# c04 3 +2: mult 300, 9; c13 5 × 3 = 15. Total 24.
	var expected: Array[Array] = [[C04, 3, 100, 2, 300, 9, 9], [C13, 5, 100, 0, 300, 15, 24]]
	_assert_scored(recorder.events, expected)
	assert_int(state.card_state(C04).temp_plus).is_equal(0)
	assert_dict(_eff(C04, state)).is_equal(_stats(3, 100, 0))
	# The walk's last event: the cleared +-part, public.
	var last: MatchEvent = recorder.events[recorder.events.size() - 1]
	assert_int(last.kind).is_equal(MatchEvent.Kind.STATS_CHANGED)
	var cleared: Dictionary = {
		"seat": 0,
		"card": C04,
		"flat": 3,
		"times": 100,
		"plus": 0,
		"cause": EffectResolver.CAUSE_TEMP_PLUS,
	}
	assert_dict(last.payload).is_equal(cleared)
	assert_int(last.owner_seat).is_equal(MatchEvent.PUBLIC)
	# The next walk has no +2: 3 + 5.
	_walk(state, Recorder.new())
	assert_array(state.scores).is_equal(_typed([8, 0]))
	# A preview walk clears it too, with the same scores and no event.
	_preview(before)
	assert_array(before.scores).is_equal(_typed([24, 0]))
	assert_int(before.card_state(C04).temp_plus).is_equal(0)


# --- P4, P12: a preview walk equals the live walk -------------------------------------


## Both rows hold ×- and +bonuses (and a flat-up and a temp_plus): a preview walk on a copy
## ends on the live walk's scores, mults and state.
func test_preview_equals_live_on_a_row_with_both_bonus_kinds() -> void:
	var row_0: Array[int] = [C08_TIMES_125, C02_PLUS_1, C20_TIMES_150, C14_PLUS_2]
	var row_1: Array[int] = []
	for index: int in [C14_PLUS_2, C03_TIMES_125, C04]:
		row_1.append(MatchRules.DECK_SIZE + index)
	var state: MatchState = _state(row_0, row_1)
	state.card_state_for(MatchRules.DECK_SIZE + C04).flat_delta = 1
	var copy: MatchState = state.duplicate()
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	_preview(copy)
	# Seat 0: 5, 9, then ×1.5 → 338 and 7 × 3.38 = 23 (32), then +2 → 538 and
	# 6 × 5.38 = 32 (64). Seat 1: 6 +2 → 300, 18; ×1.25 → 375, 1 × 3.75 = 3 (21);
	# 4 × 3.75 = 15 (36).
	assert_array(state.scores).is_equal(_typed([64, 36]))
	assert_array(state.walk.mult).is_equal(_typed([538, 375]))
	assert_array(copy.scores).is_equal(state.scores)
	assert_array(copy.walk.mult).is_equal(state.walk.mult)
	assert_dict(copy.to_dict()).is_equal(state.to_dict())


## DC-07 T07: a Drift row with a neighbour (Lodestone), an edge (Herald on slot 0) and moves
## (Courier to the far right, Tempest reversing the other row, Eddy's +2 when moved): a
## preview walk on a copy ends on the live walk's scores, mults, rows and state.
func test_preview_equals_live_on_a_row_with_a_neighbour_and_an_edge() -> void:
	var drift: MatchCards = FixtureDecks.drift_defs()
	var herald: int = FixtureDecks.D12_HERALD
	var lodestone: int = FixtureDecks.D10_LODESTONE
	var sprite: int = FixtureDecks.D02_SPRITE
	var tempest: int = FixtureDecks.D17_TEMPEST
	var eddy: int = MatchRules.DECK_SIZE + FixtureDecks.D05_EDDY
	var courier: int = MatchRules.DECK_SIZE + FixtureDecks.D06_COURIER
	var tide: int = MatchRules.DECK_SIZE + FixtureDecks.D08_TIDE
	var pebble: int = MatchRules.DECK_SIZE + FixtureDecks.D04_PEBBLE
	var state: MatchState = _state(
		_typed([herald, lodestone, sprite, tempest]), _typed([eddy, courier, tide, pebble])
	)
	state.seats[1].revealed[eddy] = true
	var copy: MatchState = state.duplicate()
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < 100:
		var paused: bool = ScoreWalk.step(state, drift, null, recorder.record, null)
		assert_bool(paused).is_false()
		guard += 1
	ScoreWalk.begin(copy)
	var preview_paused: bool = ScoreWalk.run(copy, drift, null, Callable(), PreviewPolicy.new())
	assert_bool(preview_paused).is_false()
	# The moves happened: Courier went right, then Tempest reversed seat 1's row.
	assert_array(state.seats[1].board).is_equal(_typed([courier, pebble, tide, eddy]))
	assert_int(_of_kind(recorder.events, MatchEvent.Kind.CARD_MOVED).size()).is_greater(0)
	# Herald scored at ×1.5 on slot 0 and Sprite with Lodestone's ×1.25.
	var times: Dictionary = {}
	for event: MatchEvent in _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED):
		times[_payload_int(event, "card")] = _payload_int(event, "times")
	assert_int(_dict_int(times, herald)).is_equal(150)
	assert_int(_dict_int(times, sprite)).is_equal(156)
	assert_int(state.scores[0]).is_greater(0)
	assert_array(copy.scores).is_equal(state.scores)
	assert_array(copy.walk.mult).is_equal(state.walk.mult)
	assert_array(copy.seats[1].board).is_equal(state.seats[1].board)
	assert_dict(copy.to_dict()).is_equal(state.to_dict())


func _dict_int(values: Dictionary, key: int) -> int:
	var value: int = values.get(key, -1)
	return value


## A bot match over the edited pool: after each turn that neither ends a round nor changed
## a card mid-walk (a destroy, a choice, a stat change), a preview walk on a copy of the
## engine's state gives the live TURN_ENDED scores.
func test_a_preview_on_the_live_state_gives_the_live_scores() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_bool(engine.start().ok).is_true()
	var bots: Array[GreedyBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(GreedyBot.new(GreedyBot.seed_for(SEED, seat), _defs()))
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
		var events: Array[MatchEvent] = []
		events.assign(turn_events)
		turn_events.clear()
		if not _of_kind(result.events, MatchEvent.Kind.ROUND_STARTED).is_empty():
			continue
		if engine.is_over() or _changed_the_walk(events):
			continue
		var copy: MatchState = engine._state.duplicate()
		_preview(copy)
		var raw: Array = ended[0].payload["scores"]
		assert_array(copy.scores).is_equal(_typed(raw))
		compared += 1
	assert_bool(engine.is_over()).is_true()
	assert_int(compared).is_greater(0)


func _changed_the_walk(events: Array[MatchEvent]) -> bool:
	for kind: int in [
		MatchEvent.Kind.CARD_DESTROYED,
		MatchEvent.Kind.CHOICE_MADE,
		MatchEvent.Kind.STATS_CHANGED,
	]:
		if not _of_kind(events, kind).is_empty():
			return true
	return false


## Records what a walk sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	## The walk sends effect events with their owner, its own without.
	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
