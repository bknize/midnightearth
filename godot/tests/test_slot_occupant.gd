class_name TestSlotOccupant
extends GdUnitTestSuite
## DC-06 T01 rework (R4, R5, R11, R13, R14; C23-C25, plan P2): the score stage of a pulse
## belongs to the slot. After c12's swap, the card on the pulsed slot is scored: a destroyed
## one only flips, a face-down one first reveals in full (and may prompt on its own), and a
## resume after a prompt scores the slot's occupant, read from `walk.paused_slot`.
##
## States are built directly. Seat 0's row is [a (revealed c04), c12, x] against seat 1's
## two face-down vanilla cards, seat 0 first: the walk pulses a, seat 1's slot 0, then
## reveals c12, whose swap prompts over a (position 0) and x (position 2). Card instance ids
## are seat * DECK_SIZE + index.

const SEED: int = 1
const MAX_STEPS: int = 100
# Definition indices (= seat-0 instance ids) in the default card list.
const C04: int = 3
const C08: int = 7
const C12_SWAP: int = 11
const C17_RETURN: int = 16

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


## Seat 1's two face-down vanilla cards (the first two effect-free definitions).
func _theirs() -> Array[int]:
	var out: Array[int] = []
	for index: int in range(_db().size()):
		if _db().card_at(index).effect == null:
			out.append(MatchRules.DECK_SIZE + index)
		if out.size() == 2:
			break
	return out


## Seat 0 [a (revealed c04), c12, `third` (face down)] against _theirs(), seat 0 first.
func _swap_state(third: int) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = 0
	state.seats[0].board.assign([C04, C12_SWAP, third])
	state.seats[1].board.assign(_theirs())
	state.seats[0].revealed[C04] = true
	return state


## Steps the live walk until it ends or pauses on a prompt; true when it paused.
func _run(state: MatchState, recorder: Recorder) -> bool:
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		if ScoreWalk.step(state, _db(), null, recorder.record, null):
			return true
		guard += 1
	return false


## Answers the open prompt with position `index`, recording the choice's events.
func _answer(state: MatchState, index: int, recorder: Recorder) -> void:
	recorder.events.append_array(EffectResolver.answer(state, _db(), index))


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


## The events of `kind` naming `card`, in order.
func _for_card(events: Array[MatchEvent], kind: int, card: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in _of_kind(events, kind):
		if _payload_int(event, "card") == card:
			out.append(event)
	return out


## The `again` flags of `events`' CARD_SCORED, in order.
func _again_flags(events: Array[MatchEvent]) -> Array[bool]:
	var out: Array[bool] = []
	for event: MatchEvent in _of_kind(events, MatchEvent.Kind.CARD_SCORED):
		var flag: bool = event.payload["again"]
		out.append(flag)
	return out


# --- C25, R13, R14: a destroyed card swapped onto the pulsed slot ---------------------


## c12 swaps with x, a destroyed c08, face down or face up. x, now on slot 1, flips if face
## down (CARD_REVEALED with `destroyed`, slot 1) and scores nothing: no CARD_SCORED, no
## bonus-0 spend (the mark set while the prompt waits is still pending). c12 scores once at
## slot 2, and the walk still makes n + m = 5 pulses (R4).
func test_a_destroyed_card_swapped_onto_the_slot_flips_and_scores_nothing() -> void:
	var theirs: Array[int] = _theirs()
	for face_down: bool in [true, false]:
		var where: String = "face down %s" % face_down
		var state: MatchState = _swap_state(C08)
		state.card_state_for(C08).destroyed = true
		if not face_down:
			state.seats[0].revealed[C08] = true
		var recorder: Recorder = Recorder.new()
		ScoreWalk.begin(state)
		var pulses: int = 0
		var guard: int = 0
		while state.walk.active and guard < MAX_STEPS:
			guard += 1
			if state.walk.paused_card < 0 and ScoreWalk.next_slot(state).x >= 0:
				pulses += 1
			if ScoreWalk.step(state, _db(), null, recorder.record, null):
				state.bonus_zero_pending[0] = true
				_answer(state, 2, recorder)
		assert_int(pulses).override_failure_message(where).is_equal(5)
		assert_array(state.seats[0].board).is_equal(_typed([C04, C08, C12_SWAP]))
		var scored: Array[int] = _cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)
		var expected: Array[int] = [C04, theirs[0], theirs[1], C12_SWAP]
		assert_array(scored).override_failure_message(where).is_equal(expected)
		var flips: Array[MatchEvent] = _for_card(
			recorder.events, MatchEvent.Kind.CARD_REVEALED, C08
		)
		assert_int(flips.size()).override_failure_message(where).is_equal(1 if face_down else 0)
		if face_down:
			var destroyed: bool = flips[0].payload["destroyed"]
			assert_bool(destroyed).is_true()
			assert_int(_payload_int(flips[0], "slot")).is_equal(1)
		assert_bool(state.seats[0].is_revealed(C08)).is_true()
		var c12_score: MatchEvent = _for_card(
			recorder.events, MatchEvent.Kind.CARD_SCORED, C12_SWAP
		)[0]
		assert_int(_payload_int(c12_score, "slot")).is_equal(2)
		var again: bool = c12_score.payload["again"]
		assert_bool(again).is_false()
		# R14: the flip spends no bonus-0 mark and the card gains none.
		assert_bool(state.bonus_zero_pending[0]).override_failure_message(where).is_true()
		assert_bool(state.card_state(C08).bonus_zero).is_false()
		assert_bool(state.walk.scored.has(C08)).is_false()
		# c04 3 + c12 4.
		assert_int(state.scores[0]).override_failure_message(where).is_equal(7)


# --- R5, C24: the card landing on the slot reveals in full, prompts, then scores ------


## c12 swaps with x, a face-down c17 (on-reveal return; c13's switch retired at DC-07 T01).
## x, now on slot 1, reveals in full in c12's pulse: CARD_REVEALED at slot 1, the bonus-0
## mark spent on it, its on-reveal return opening a prompt of its own (c04, c12 and seat
## 1's revealed c02). That pause records x and slot 1; the resume after the return scores x
## on slot 1 (flat 6, bonus 0), and c12 scores once at slot 2.
func test_the_card_landing_on_the_slot_reveals_in_full_before_it_scores() -> void:
	var x: int = C17_RETURN
	var state: MatchState = _swap_state(x)
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_true()
	assert_int(state.walk.paused_card).is_equal(C12_SWAP)
	assert_int(state.walk.paused_slot).is_equal(1)
	# Seat 0's next reveal will take the bonus-0 mark.
	state.bonus_zero_pending[0] = true
	_answer(state, 2, recorder)
	assert_bool(_run(state, recorder)).is_true()
	# Paused on x's own prompt, in c12's pulse, before x scores.
	var prompt_card: int = state.prompt["card"]
	var prompt_verb: int = state.prompt["verb"]
	assert_int(prompt_card).is_equal(x)
	assert_int(prompt_verb).is_equal(CardEffect.Verb.RETURN_AT_TURN_END)
	assert_int(state.walk.paused_card).is_equal(x)
	assert_int(state.walk.paused_slot).is_equal(1)
	assert_int(state.walk.paused_stage).is_equal(ScoreWalk.Stage.WATCHERS)
	var walk_dict: Dictionary = state.to_dict()["walk"]
	var stored_slot: int = walk_dict["paused_slot"]
	assert_int(stored_slot).is_equal(1)
	assert_array(state.walk.cursor).is_equal(_typed([2, 1]))
	var reveals: Array[MatchEvent] = _for_card(recorder.events, MatchEvent.Kind.CARD_REVEALED, x)
	assert_int(reveals.size()).is_equal(1)
	assert_int(_payload_int(reveals[0], "slot")).is_equal(1)
	assert_bool(state.bonus_zero_pending[0]).is_false()
	assert_bool(state.card_state(x).bonus_zero).is_true()
	assert_int(_for_card(recorder.events, MatchEvent.Kind.STATS_CHANGED, x).size()).is_equal(1)
	assert_array(_for_card(recorder.events, MatchEvent.Kind.CARD_SCORED, x)).is_empty()
	# Mark c04 (position 0 of both boards, already scored): x is scored next, on slot 1.
	_answer(state, 0, recorder)
	var before_resume: int = recorder.events.size()
	assert_bool(_run(state, recorder)).is_false()
	var resumed: Array[MatchEvent] = recorder.events.slice(before_resume)
	var first_score: MatchEvent = _of_kind(resumed, MatchEvent.Kind.CARD_SCORED)[0]
	assert_int(_payload_int(first_score, "card")).is_equal(x)
	assert_int(_payload_int(first_score, "slot")).is_equal(1)
	assert_int(_payload_int(first_score, "added")).is_equal(6)
	var theirs: Array[int] = _theirs()
	var scored: Array[int] = _cards_of(recorder.events, MatchEvent.Kind.CARD_SCORED)
	assert_array(scored).is_equal(_typed([C04, theirs[0], x, theirs[1], C12_SWAP]))
	var want_again: Array[bool] = [false, false, false, false, false]
	assert_array(_again_flags(recorder.events)).is_equal(want_again)
	# c04 3 + c17 6*1 + c12 4*1.
	assert_int(state.scores[0]).is_equal(13)
	assert_int(state.walk.paused_slot).is_equal(-1)
	assert_bool(state.walk.active).is_false()


# --- P2: a resume scores the slot's occupant ------------------------------------------


## Paused on c12's swap prompt, answered with a (swap behind): the paused state carries
## `paused_slot` 1 through to_dict() and duplicate(), and the resumed step scores a on
## slot 1 with `again`, not c12. A resume on the copy gives the same events and state.
func test_a_resume_after_the_swap_prompt_scores_the_slots_occupant() -> void:
	var state: MatchState = _swap_state(C08)
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_true()
	_answer(state, 0, recorder)
	assert_dict(state.prompt).is_empty()
	assert_int(state.walk.paused_card).is_equal(C12_SWAP)
	assert_int(state.walk.paused_slot).is_equal(1)
	var copy: MatchState = state.duplicate()
	assert_int(copy.walk.paused_slot).is_equal(1)
	assert_dict(copy.to_dict()).is_equal(state.to_dict())
	var live: Recorder = Recorder.new()
	var copied: Recorder = Recorder.new()
	assert_bool(ScoreWalk.step(state, _db(), null, live.record, null)).is_false()
	assert_bool(ScoreWalk.step(copy, _db(), null, copied.record, null)).is_false()
	var kinds: Array[int] = []
	for event: MatchEvent in live.events:
		kinds.append(event.kind)
	assert_array(kinds).is_equal(_typed([MatchEvent.Kind.CARD_SCORED]))
	var scored: MatchEvent = live.events[0]
	assert_int(_payload_int(scored, "card")).is_equal(C04)
	assert_int(_payload_int(scored, "slot")).is_equal(1)
	var again: bool = scored.payload["again"]
	assert_bool(again).is_true()
	assert_int(copied.events.size()).is_equal(1)
	assert_dict(copied.events[0].payload).is_equal(scored.payload)
	assert_int(state.walk.paused_card).is_equal(-1)
	assert_int(state.walk.paused_slot).is_equal(-1)
	assert_dict(copy.to_dict()).is_equal(state.to_dict())
	# The cursor goes on from seat 1's slot 1; c12, on the passed slot 0, never scores.
	assert_vector(ScoreWalk.next_slot(state)).is_equal(Vector2i(1, 1))
	assert_bool(_run(state, recorder)).is_false()
	assert_bool(state.walk.scored.has(C12_SWAP)).is_false()


## Records what a walk sends to its sink.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	## The walk sends effect events with their owner (DC-05 T04), its own without.
	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
