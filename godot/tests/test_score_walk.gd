class_name TestScoreWalk
extends GdUnitTestSuite
## ScoreWalk under rules 7 (cycle 9 plan P7; spec R25 to R29; DC-13 T03): each Scoring card
## adds its Power to its Controller's walking total, then the total is multiplied by its
## Bonus value (Scoring); CARD_SCORED carries {power, bonus_value, total} in ten-thousandths;
## the Walk ends with each Score its total rounded once and WALK_ENDED {totals, scores}. The
## slot cursor alternates the rows from the first committer's, and every ability fires on
## its moment (on_reveal at a reveal, on_score after a score; DC-13 T06's verbs). States
## are built directly on the shipped Greed deck:
## instance 4 * k .. 4 * k + 3 are the four copies of gr0(k+1), seat 1 adds DECK_SIZE.

const SEED: int = 1
const EMBER: int = 0
const PIP: int = 4
const FLARE: int = 8
const SKIM: int = 12
const CINDER: int = 16
const COURIER: int = 20
const BANNER: int = 24
const GILT: int = 32

var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


## Greed on both seats over the shipped data.
func _defs() -> MatchCards:
	if _cached_defs == null:
		var ids: Array[String] = ["greed", "greed"]
		_cached_defs = MatchCards.build(
			CardDb.load_default(), DeckList.load_default(), ids, CrewPool.load_default()
		)
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## A state with these rows (seat 0, seat 1), nothing revealed, `first` committing first.
func _state(row_0: Array[int], row_1: Array[int], first: int) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = first
	state.seats[0].board.assign(row_0)
	state.seats[1].board.assign(row_1)
	return state


## Runs the Walk on `state` from begin() to its end, recording the events.
func _walk(state: MatchState, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < 100:
		var paused: bool = ScoreWalk.step(state, _defs(), null, recorder.record)
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


func _payload_str(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


## `key` of every event of `kind`, in order.
func _ints_of(events: Array[MatchEvent], kind: int, key: String) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, kind):
		out.append(_payload_int(event, key))
	return out


func _power(card: int) -> int:
	return _defs().def_of(card).power


# --- The walking total ----------------------------------------------------------------


## Pip (Power 3), Skim (Power 2, ×1.25), Gilt (Power 4, ×1.5): the total reads 3, 6.25,
## 15.375 in ten-thousandths, and the Score is 15.375 rounded once, 15. CARD_SCORED carries
## each Power, Bonus value and total after.
func test_the_walking_total_adds_power_then_multiplies_by_the_bonus_value() -> void:
	var row_0: Array[int] = [PIP, SKIM, GILT]
	var row_1: Array[int] = [MatchRules.DECK_SIZE + PIP + 1]
	var state: MatchState = _state(row_0, row_1, 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var scored: int = MatchEvent.Kind.CARD_SCORED
	var own: Array[MatchEvent] = []
	for event: MatchEvent in _of_kind(recorder.events, scored):
		if _payload_int(event, "seat") == 0:
			own.append(event)
	assert_array(_ints_of(own, scored, "power")).is_equal(_typed([3, 2, 4]))
	assert_array(_ints_of(own, scored, "bonus_value")).is_equal(_typed([10000, 12500, 15000]))
	assert_array(_ints_of(own, scored, "total")).is_equal(_typed([30000, 62500, 153750]))
	for event: MatchEvent in own:
		assert_int(_payload_int(event, "pass")).is_equal(1)
		assert_int(event.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_array(state.totals).is_equal(_typed([153750, 30000]))
	assert_array(state.scores).is_equal(_typed([15, 3]))
	assert_array(state.walk.scored_count).is_equal(_typed([3, 1]))


## The Walk ends with WALK_ENDED {totals, scores}, its last event; until then the Scores
## keep the previous Walk's (R77: the HUD shows them meanwhile), and begin() zeroes the
## totals.
func test_walk_ended_carries_the_totals_and_the_rounded_scores() -> void:
	var state: MatchState = _state(_typed([SKIM]), _typed([MatchRules.DECK_SIZE + GILT]), 1)
	state.scores.assign([7, 9])
	state.totals.assign([70000, 90000])
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_array(state.totals).is_equal(_typed([0, 0]))
	assert_array(state.scores).is_equal(_typed([7, 9]))
	assert_bool(ScoreWalk.step(state, _defs(), null, recorder.record)).is_false()
	assert_array(state.scores).is_equal(_typed([7, 9]))
	while state.walk.active:
		assert_bool(ScoreWalk.step(state, _defs(), null, recorder.record)).is_false()
	var last: MatchEvent = recorder.events[recorder.events.size() - 1]
	assert_int(last.kind).is_equal(MatchEvent.Kind.WALK_ENDED)
	# Skim: 2 x 1.25 = 2.5, rounded up to 3; Gilt: 4 x 1.5 = 6.
	var totals: Array = last.payload["totals"]
	var scores: Array = last.payload["scores"]
	assert_array(_typed(totals)).is_equal(_typed([25000, 60000]))
	assert_array(_typed(scores)).is_equal(_typed([3, 6]))
	assert_array(state.scores).is_equal(_typed([3, 6]))


## A reveal is public with the card's Power, Mult and Add (hundredths) and its statuses
## (none before DC-13 T04).
func test_a_reveal_carries_power_mult_add_and_statuses() -> void:
	var state: MatchState = _state(_typed([SKIM]), _typed([]), 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var revealed: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_REVEALED)
	assert_int(revealed.size()).is_equal(1)
	var payload: Dictionary = revealed[0].payload
	assert_dict(payload).is_equal(
		{"seat": 0, "card": SKIM, "slot": 0, "power": 2, "mult": 125, "add": 0, "statuses": []}
	)
	assert_bool(state.seats[0].is_revealed(SKIM)).is_true()


## Memory and Board changes reach the Score (R30): Pip with Memory Power +2 and a Board
## change of +1 adds 6; Skim whose Mult grew +0.25 for the match multiplies by 1.5; a
## granted Add of +0.5 joins before the Mults (C20).
func test_memory_and_board_changes_reach_the_score() -> void:
	var state: MatchState = _state(_typed([PIP, SKIM]), _typed([]), 0)
	state.memory_for(PIP).power = 2
	state.card_state_for(PIP).power_delta = 1
	state.memory_for(SKIM).mult_add_steps = 25
	state.memory_for(SKIM).mult_cap = 200
	state.card_state_for(SKIM).grant(CardState.KIND_ADD, 50, "turn")
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var scored: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED)
	assert_int(_payload_int(scored[0], "power")).is_equal(6)
	assert_int(_payload_int(scored[0], "total")).is_equal(60000)
	# (1 + 0.5) x 1.5 = 2.25; (6 + 2) x 2.25 = 18.
	assert_int(_payload_int(scored[1], "bonus_value")).is_equal(22500)
	assert_int(_payload_int(scored[1], "total")).is_equal(180000)
	assert_int(state.scores[0]).is_equal(18)


## A negative Power subtracts before the multiply, so a Score may be negative (R27).
func test_a_negative_total_gives_a_negative_score() -> void:
	var state: MatchState = _state(_typed([PIP, SKIM]), _typed([]), 0)
	state.card_state_for(PIP).power_delta = -6
	state.card_state_for(SKIM).power_delta = -4
	_walk(state, Recorder.new())
	# Pip -3 -> -3; Skim -2 -> (-3 - 2) x 1.25 = -6.25 -> -6 (half up).
	assert_int(state.totals[0]).is_equal(-62500)
	assert_int(state.scores[0]).is_equal(-6)


## The cursor alternates the rows from the first committer's, then finishes the longer row:
## three against one, seat 1 first, pulses x, a, b, c.
func test_the_cursor_alternates_then_finishes_the_longer_row() -> void:
	var row_0: Array[int] = [PIP, PIP + 1, PIP + 2]
	var other: int = MatchRules.DECK_SIZE + PIP
	var row_1: Array[int] = [other]
	var state: MatchState = _state(row_0, row_1, 1)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var expected: Array[int] = [other, PIP, PIP + 1, PIP + 2]
	var scored: int = MatchEvent.Kind.CARD_SCORED
	var revealed: int = MatchEvent.Kind.CARD_REVEALED
	assert_array(_ints_of(recorder.events, scored, "card")).is_equal(expected)
	assert_array(_ints_of(recorder.events, revealed, "card")).is_equal(expected)


## A face-up card on the row Scores again in a later Walk with no second reveal.
func test_a_revealed_card_scores_again_without_a_reveal() -> void:
	var state: MatchState = _state(_typed([PIP]), _typed([]), 0)
	_walk(state, Recorder.new())
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_array(_of_kind(recorder.events, MatchEvent.Kind.CARD_REVEALED)).is_empty()
	assert_int(_of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED).size()).is_equal(1)
	assert_int(state.scores[0]).is_equal(3)


func test_an_empty_walk_ends_on_its_first_step() -> void:
	var state: MatchState = _state(_typed([]), _typed([]), 0)
	ScoreWalk.begin(state)
	var recorder: Recorder = Recorder.new()
	assert_bool(ScoreWalk.step(state, _defs(), null, recorder.record)).is_false()
	assert_bool(state.walk.active).is_false()
	assert_int(recorder.events.size()).is_equal(1)
	assert_int(recorder.events[0].kind).is_equal(MatchEvent.Kind.WALK_ENDED)
	assert_array(state.scores).is_equal(_typed([0, 0]))


# --- The stub abilities ---------------------------------------------------------------


## Ember's On reveal Discards the one hand card right after its reveal, before its Score;
## Courier's On score draws after its Score; Flare's On reveal Condemns it and it still
## Scores (DC-13 T06). Each fires once, publicly, in that order.
func test_each_ability_fires_on_its_moment() -> void:
	var row_0: Array[int] = [EMBER, COURIER, FLARE]
	var state: MatchState = _state(row_0, _typed([]), 0)
	state.seats[0].hand.assign(_typed([PIP]))
	state.seats[0].deck.assign(_typed([PIP + 2]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var fired: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.TRIGGER_FIRED)
	assert_int(fired.size()).is_equal(3)
	var expected: Array[Array] = [[EMBER, "discard_own"], [COURIER, "draw"], [FLARE, "condemn_self"]]
	for at: int in range(fired.size()):
		var event: MatchEvent = fired[at]
		var row: Array = expected[at]
		var card: int = row[0]
		var verb: String = row[1]
		assert_int(event.owner_seat).is_equal(MatchEvent.PUBLIC)
		assert_int(_payload_int(event, "card")).is_equal(card)
		assert_int(_payload_int(event, "seat")).is_equal(0)
		assert_str(_payload_str(event, "verb")).is_equal(verb)
	assert_array(_of_kind(recorder.events, MatchEvent.Kind.TRIGGER_FIZZLED)).is_empty()
	# Ember's fires between its reveal and its Score, Courier's after its Score.
	var kinds: Array[int] = []
	for event: MatchEvent in recorder.events:
		if event.kind in [
			MatchEvent.Kind.CARD_REVEALED, MatchEvent.Kind.CARD_SCORED, MatchEvent.Kind.TRIGGER_FIRED
		]:
			kinds.append(event.kind)
	var reveal: int = MatchEvent.Kind.CARD_REVEALED
	var score: int = MatchEvent.Kind.CARD_SCORED
	var fire: int = MatchEvent.Kind.TRIGGER_FIRED
	var order: Array[int] = [reveal, fire, score, reveal, score, fire, reveal, fire, score]
	assert_array(kinds).is_equal(order)
	assert_array(state.seats[0].hand).is_equal(_typed([PIP + 2]))
	assert_array(state.seats[0].deck).is_empty()
	assert_array(state.seats[0].pile).is_equal(_typed([PIP]))
	assert_str(Statuses.exit_mark_of(state, FLARE)).is_equal(Statuses.CONDEMNED)
	assert_int(state.scores[0]).is_equal(_power(EMBER) + _power(COURIER) + _power(FLARE))


## An Ongoing ability (Banner) and a plain body fire nothing on either moment; Banner's
## Ongoing gives the plain Pip Power +4 when it Scores (DC-13 T06).
func test_ongoing_and_plain_cards_fire_nothing() -> void:
	var state: MatchState = _state(_typed([BANNER, PIP]), _typed([]), 0)
	for moment: String in ["on_reveal", "on_score"]:
		assert_array(Abilities.fire(state, _defs(), null, 0, BANNER, moment)).is_empty()
		assert_array(Abilities.fire(state, _defs(), null, 0, PIP, moment)).is_empty()
	assert_int(Abilities.on_moment(BANNER, _defs(), "ongoing").size()).is_equal(1)
	assert_array(Abilities.on_moment(-1, _defs(), "ongoing")).is_empty()
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_array(_of_kind(recorder.events, MatchEvent.Kind.TRIGGER_FIZZLED)).is_empty()
	assert_int(state.scores[0]).is_equal(_power(BANNER) + _power(PIP) + 4)


## A Walk with no sink emits nothing and reaches the same totals and Scores.
func test_a_walk_without_a_sink_gives_the_same_scores() -> void:
	var row_0: Array[int] = [EMBER, CINDER, SKIM]
	var row_1: Array[int] = [MatchRules.DECK_SIZE + GILT]
	var live: MatchState = _state(row_0, row_1, 0)
	_walk(live, Recorder.new())
	var silent: MatchState = _state(row_0, row_1, 0)
	assert_bool(ScoreWalk.run(silent, _defs(), null, Callable())).is_false()
	ScoreWalk.begin(silent)
	assert_bool(ScoreWalk.run(silent, _defs(), null, Callable())).is_false()
	assert_array(silent.totals).is_equal(live.totals)
	assert_array(silent.scores).is_equal(live.scores)


## Records what a Walk sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	## The Walk sends ability events with their owner, its own without.
	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
