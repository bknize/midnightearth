class_name TestScoreWalk
extends GdUnitTestSuite
## The DC-13 T02 interim walk (cycle 9 plan, wave 2) and the stub Abilities.fire: every card
## scores its Power with a ×1 Bonus (a printed Mult or Add is not applied until T03's
## walking total), the slot cursor alternates the rows from the first committer's, and every
## ability on the moment that fires (on_reveal at a reveal, on_score after a score) fizzles
## `no_target` and changes nothing. States are built directly on the shipped Greed deck:
## instance 4 * k .. 4 * k + 3 are the four copies of gr0(k+1), seat 1 adds DECK_SIZE.
## The v6 walk's cases (the hundredths multiplier, swaps, destroys) went with the v6 rules;
## T03 rewrites this suite for the walking total.

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


## Runs the walk on `state` from begin() to its end, recording the events.
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


## The `card` of every event of `kind`, in order.
func _cards_of(events: Array[MatchEvent], kind: int) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, kind):
		out.append(_payload_int(event, "card"))
	return out


func _power(card: int) -> int:
	return _defs().def_of(card).power


# --- The score ------------------------------------------------------------------------


## Plain bodies and Bonus cards alike add their Power: the multiplier stays ×1.00.
func test_every_card_scores_its_power_with_a_x1_bonus() -> void:
	var row_0: Array[int] = [PIP, SKIM, GILT]
	var row_1: Array[int] = [MatchRules.DECK_SIZE + PIP + 1]
	var state: MatchState = _state(row_0, row_1, 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_int(state.scores[0]).is_equal(_power(PIP) + _power(SKIM) + _power(GILT))
	assert_int(state.scores[0]).is_equal(3 + 2 + 4)
	assert_int(state.scores[1]).is_equal(3)
	assert_int(state.walk.mult[0]).is_equal(MatchRules.BONUS_ONE)
	for event: MatchEvent in _of_kind(recorder.events, MatchEvent.Kind.CARD_SCORED):
		var card: int = _payload_int(event, "card")
		assert_int(_payload_int(event, "flat")).is_equal(_power(card))
		assert_int(_payload_int(event, "times")).is_equal(MatchRules.BONUS_ONE)
		assert_int(_payload_int(event, "plus")).is_equal(0)
		assert_int(_payload_int(event, "added")).is_equal(_power(card))


func test_effective_reads_power_and_no_bonus() -> void:
	var state: MatchState = _state(_typed([]), _typed([]), 0)
	var skim: ScoreWalk.Effective = ScoreWalk.effective(SKIM, state, _defs())
	assert_dict(skim.to_dict()).is_equal({"flat": 2, "times": 100, "plus": 0})
	var unknown: ScoreWalk.Effective = ScoreWalk.effective(999, state, _defs())
	assert_dict(unknown.to_dict()).is_equal({"flat": 0, "times": 100, "plus": 0})
	assert_int(ScoreWalk.effective_cost(GILT, state, _defs())).is_equal(6)
	assert_int(ScoreWalk.uses_left(EMBER, state, _defs())).is_equal(-1)


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
	assert_array(_cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)).is_equal(expected)
	assert_array(_cards_of(recorder.events, MatchEvent.Kind.CARD_REVEALED)).is_equal(expected)


func test_an_empty_walk_ends_on_its_first_step() -> void:
	var state: MatchState = _state(_typed([]), _typed([]), 0)
	ScoreWalk.begin(state)
	var recorder: Recorder = Recorder.new()
	assert_bool(ScoreWalk.step(state, _defs(), null, recorder.record)).is_false()
	assert_bool(state.walk.active).is_false()
	assert_array(recorder.events).is_empty()


# --- The stub abilities ---------------------------------------------------------------


## Ember's on-reveal Discard and Flare's on-reveal Condemn fizzle `no_target` right after
## their reveal, before their score; Courier's on-score draw fizzles after its score. Nothing
## else happens: no draw, no discard, the hands and piles unchanged.
func test_every_ability_fizzles_no_target_on_its_moment() -> void:
	var row_0: Array[int] = [EMBER, COURIER, FLARE]
	var state: MatchState = _state(row_0, _typed([]), 0)
	state.seats[0].hand.assign(_typed([PIP, PIP + 1]))
	state.seats[0].deck.assign(_typed([PIP + 2]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var fizzled: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.EFFECT_FIZZLED)
	assert_int(fizzled.size()).is_equal(3)
	var expected: Array[Array] = [
		[EMBER, "discard_own", "on_reveal"],
		[COURIER, "draw", "on_score"],
		[FLARE, "condemn_self", "on_reveal"],
	]
	for at: int in range(fizzled.size()):
		var event: MatchEvent = fizzled[at]
		var row: Array = expected[at]
		var card: int = row[0]
		var verb: String = row[1]
		var moment: String = row[2]
		assert_int(event.owner_seat).is_equal(MatchEvent.PUBLIC)
		assert_int(_payload_int(event, "card")).is_equal(card)
		assert_int(_payload_int(event, "seat")).is_equal(0)
		assert_str(_payload_str(event, "verb")).is_equal(verb)
		assert_str(_payload_str(event, "moment")).is_equal(moment)
		assert_str(_payload_str(event, "reason")).is_equal(Abilities.REASON_NO_TARGET)
	# Ember's fizzle comes between its reveal and its score; Courier's after its score.
	var kinds: Array[int] = []
	for event: MatchEvent in recorder.events:
		kinds.append(event.kind)
	var reveal: int = MatchEvent.Kind.CARD_REVEALED
	var score: int = MatchEvent.Kind.CARD_SCORED
	var fizzle: int = MatchEvent.Kind.EFFECT_FIZZLED
	var order: Array[int] = [reveal, fizzle, score, reveal, score, fizzle, reveal, fizzle, score]
	assert_array(kinds).is_equal(order)
	assert_array(state.seats[0].hand).is_equal(_typed([PIP, PIP + 1]))
	assert_array(state.seats[0].deck).is_equal(_typed([PIP + 2]))
	assert_int(state.scores[0]).is_equal(_power(EMBER) + _power(COURIER) + _power(FLARE))


## An Ongoing ability (Banner) and a plain body fire nothing on either moment.
func test_ongoing_and_plain_cards_fire_nothing() -> void:
	var state: MatchState = _state(_typed([BANNER, PIP]), _typed([]), 0)
	for moment: String in ["on_reveal", "on_score"]:
		assert_array(Abilities.fire(state, _defs(), null, 0, BANNER, moment)).is_empty()
		assert_array(Abilities.fire(state, _defs(), null, 0, PIP, moment)).is_empty()
	assert_int(Abilities.on_moment(BANNER, _defs(), "ongoing").size()).is_equal(1)
	assert_array(Abilities.on_moment(-1, _defs(), "ongoing")).is_empty()
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_array(_of_kind(recorder.events, MatchEvent.Kind.EFFECT_FIZZLED)).is_empty()
	assert_int(state.scores[0]).is_equal(_power(BANNER) + _power(PIP))


## A walk with no sink emits nothing and reaches the same scores.
func test_a_walk_without_a_sink_gives_the_same_scores() -> void:
	var row_0: Array[int] = [EMBER, CINDER, COURIER]
	var row_1: Array[int] = [MatchRules.DECK_SIZE + GILT]
	var live: MatchState = _state(row_0, row_1, 0)
	_walk(live, Recorder.new())
	var silent: MatchState = _state(row_0, row_1, 0)
	assert_bool(ScoreWalk.run(silent, _defs(), null, Callable())).is_false()
	ScoreWalk.begin(silent)
	assert_bool(ScoreWalk.run(silent, _defs(), null, Callable())).is_false()
	assert_array(silent.scores).is_equal(live.scores)


## Records what a walk sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	## The walk sends ability events with their owner, its own without.
	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
