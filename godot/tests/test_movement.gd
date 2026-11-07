class_name TestMovement
extends GdUnitTestSuite
## Movement (cycle 9 plan P10; spec R40, R42 to R44; DC-13 T04): stepwise moves on the ring,
## Anchored cards never moved (the status, or Brace's Ongoing while read), swap, reverse and
## reorder around them, Placement that is not a Move, and the cycle 5 cursor rules. "On
## moved for A and C" is read from what a move returns (the one On moved Batch the T05
## queue will wake) and from its CARD_MOVED events.

const SEED: int = 1
const A: int = StubAbilities.MOTE
const C: int = StubAbilities.PEBBLE
const D: int = StubAbilities.WISP
## Brace: "Ongoing: this card is Anchored."
const B: int = StubAbilities.BRACE

var _cached: MatchCards = null


func _defs() -> MatchCards:
	if _cached == null:
		_cached = StubAbilities.defs()
	return _cached


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _sorted(values: Array[int]) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	out.sort()
	return out


# --- R40, R42: shifts on the ring -----------------------------------------------------


## Canon scenario 8: A B C with B Anchored by Brace; "your other cards each move one slot
## left" reads C B A, and On moved wakes for A and C only.
func test_others_shift_left_past_an_anchored_card() -> void:
	var state: MatchState = StubAbilities.table(_typed([A, B, C]), true)
	assert_bool(Statuses.is_anchored(state, _defs(), B)).is_true()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var moved: Array[int] = StubAbilities.stub_shift_others_left(state, _defs(), 0, -1, rec.record)
	assert_array(state.seats[0].board).is_equal(_typed([C, B, A]))
	assert_array(moved).is_equal(_typed([C, A]))
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_MOVED)).is_equal(_typed([C, A]))
	var first: MatchEvent = rec.of_kind(MatchEvent.Kind.CARD_MOVED)[0]
	assert_dict(first.payload).is_equal(
		{"card": C, "seat": 0, "from": 2, "to": 0, "cause": StubAbilities.VERB_SHIFT_OTHERS_LEFT}
	)
	assert_int(first.owner_seat).is_equal(MatchEvent.PUBLIC)


## The same with a turn Anchored status on a plain card; a face-down Brace is not Anchored
## (its Ongoing is not read), so everything rotates.
func test_the_anchored_status_holds_and_a_face_down_brace_does_not() -> void:
	var state: MatchState = StubAbilities.table(_typed([A, D, C]), true)
	var turn: Dictionary = Statuses.cessation(Statuses.CEASE_TURN)
	Statuses.apply(state, _defs(), D, Statuses.ANCHORED, turn, "test", Callable())
	var moved: Array[int] = StubAbilities.stub_shift_others_left(state, _defs(), 0, -1, Callable())
	assert_array(state.seats[0].board).is_equal(_typed([C, D, A]))
	assert_array(_sorted(moved)).is_equal(_sorted(_typed([A, C])))
	var hidden: MatchState = StubAbilities.table(_typed([A, B, C]), false)
	var all: Array[int] = StubAbilities.stub_shift_others_left(hidden, _defs(), 0, -1, Callable())
	assert_array(hidden.seats[0].board).is_equal(_typed([B, C, A]))
	assert_int(all.size()).is_equal(3)


## Nudge's move right from the rightmost slot wraps to slot 0 (the card there takes its
## slot); from the middle it trades places with its right neighbour.
func test_nudge_from_the_rightmost_slot_wraps_to_slot_0() -> void:
	var nudge: int = StubAbilities.NUDGE
	var state: MatchState = StubAbilities.table(_typed([A, C, D, nudge]), true)
	var moved: Array[int] = Movement.shift(state, _defs(), nudge, Movement.RIGHT, "nudge", Callable())
	assert_array(state.seats[0].board).is_equal(_typed([nudge, C, D, A]))
	assert_array(moved).is_equal(_typed([nudge, A]))
	var middle: MatchState = StubAbilities.table(_typed([A, nudge, C]), true)
	Movement.shift(middle, _defs(), nudge, Movement.RIGHT, "nudge", Callable())
	assert_array(middle.seats[0].board).is_equal(_typed([A, C, nudge]))
	# An Anchored right neighbour is slid past.
	var braced: MatchState = StubAbilities.table(_typed([nudge, B, C]), true)
	Movement.shift(braced, _defs(), nudge, Movement.RIGHT, "nudge", Callable())
	assert_array(braced.seats[0].board).is_equal(_typed([C, B, nudge]))
	# An Anchored card does not move itself.
	var stuck: MatchState = StubAbilities.table(_typed([A, B]), true)
	assert_array(Movement.shift(stuck, _defs(), B, Movement.LEFT, "x", Callable())).is_empty()
	assert_array(stuck.seats[0].board).is_equal(_typed([A, B]))


## A swap naming an Anchored card fizzles: nothing moves and nothing is reported; two free
## cards trade slots and both are moved.
func test_a_swap_naming_an_anchored_card_fizzles() -> void:
	var state: MatchState = StubAbilities.table(_typed([A, B, C]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_array(StubAbilities.stub_swap(state, _defs(), A, B, rec.record)).is_empty()
	assert_array(state.seats[0].board).is_equal(_typed([A, B, C]))
	assert_array(rec.events).is_empty()
	var moved: Array[int] = StubAbilities.stub_swap(state, _defs(), A, C, rec.record)
	assert_array(state.seats[0].board).is_equal(_typed([C, B, A]))
	assert_array(moved).is_equal(_typed([C, A]))


# --- R40: reverse and reorder ---------------------------------------------------------


## Reverse keeps the Anchored slot and reverses the rest around it; reorder (the engine
## stream) keeps it too and only permutes the others, the same way for the same seed.
func test_reverse_and_reorder_keep_anchored_slots() -> void:
	var state: MatchState = StubAbilities.table(_typed([A, B, C, D]), true)
	var moved: Array[int] = StubAbilities.stub_reverse(state, _defs(), 0, Callable())
	assert_array(state.seats[0].board).is_equal(_typed([D, B, C, A]))
	assert_array(moved).is_equal(_typed([D, A]))
	var row: Array[int] = _typed([A, C, B, D, StubAbilities.MOTE + 1, StubAbilities.MOTE + 2])
	var first: MatchState = StubAbilities.table(row, true)
	var second: MatchState = StubAbilities.table(row, true)
	Movement.reorder(first, _defs(), 0, MatchRng.new(SEED), "test", Callable())
	Movement.reorder(second, _defs(), 0, MatchRng.new(SEED), "test", Callable())
	assert_int(first.seats[0].board[2]).is_equal(B)
	assert_array(_sorted(first.seats[0].board)).is_equal(_sorted(row))
	assert_array(first.seats[0].board).is_equal(second.seats[0].board)


# --- R43: Placement -------------------------------------------------------------------


## A committed card changes other cards' slot numbers without a Move: no CARD_MOVED, no On
## moved, and an Anchored card is displaced without breaking its Anchor.
func test_a_committed_card_changes_slot_numbers_without_on_moved() -> void:
	var state: MatchState = StubAbilities.table(_typed([B, C]), true)
	TurnFlow.merge_row(state, 0, _typed([A]), _typed([0]))
	assert_array(state.seats[0].board).is_equal(_typed([A, B, C]))
	assert_bool(state.seats[0].is_revealed(A)).is_false()
	assert_bool(Statuses.is_anchored(state, _defs(), B)).is_true()
	assert_int(Movement.place(state, 0, D, 1)).is_equal(1)
	assert_array(state.seats[0].board).is_equal(_typed([A, D, B, C]))
	assert_int(Movement.place(state, 0, StubAbilities.MOTE + 1, 99)).is_equal(4)


## A Placement at a passed slot during a Walk moves the cursor on, so the passed cards stay
## passed and the placed card waits.
func test_a_placement_behind_the_cursor_waits() -> void:
	var state: MatchState = StubAbilities.table(_typed([A, C]), true)
	ScoreWalk.begin(state)
	state.walk.cursor[0] = 1
	Movement.place(state, 0, D, 0)
	assert_int(state.walk.cursor[0]).is_equal(2)
	assert_int(ScoreWalk.next_card(state)).is_equal(C)


# --- R44: the cursor ------------------------------------------------------------------


## A face-down card swapped behind the cursor waits for the next Walk (no reveal, no
## Score); the card swapped ahead is reached later and Scores again.
func test_a_card_moved_behind_the_cursor_waits() -> void:
	var state: MatchState = StubAbilities.table(_typed([A, C, D]), false)
	var defs: MatchCards = _defs()
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, defs, rng, rec.record)).is_false()
	assert_bool(ScoreWalk.step(state, defs, rng, rec.record)).is_false()
	assert_int(state.walk.cursor[0]).is_equal(2)
	var moved: Array[int] = Movement.swap(state, defs, D, A, "test", rec.record)
	assert_array(moved).is_equal(_typed([D, A]))
	# D is face down: its CARD_MOVED is private to seat 0.
	var hidden_move: MatchEvent = rec.of_kind(MatchEvent.Kind.CARD_MOVED)[0]
	assert_int(hidden_move.owner_seat).is_equal(0)
	assert_bool(ScoreWalk.run(state, defs, rng, rec.record)).is_false()
	assert_bool(state.walk.active).is_false()
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_REVEALED)).is_equal(_typed([A, C]))
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_SCORED)).is_equal(_typed([A, C, A]))
	assert_bool(state.seats[0].is_revealed(D)).is_false()


## A card landing on the pulsed slot Scores now (revealing first when face down); the
## pulsed card moved ahead Scores when the cursor reaches it.
func test_a_card_landing_on_the_pulsed_slot_scores_now() -> void:
	var state: MatchState = StubAbilities.table(_typed([A, C, D]), false)
	var defs: MatchCards = _defs()
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	# The pulse on slot 0: the slot is passed, A reveals, then (as Nudge would) moves right.
	state.walk.cursor[0] = 1
	state.walk.next_seat = 1
	ScoreWalk.reveal(state, defs, rec.record, 0, A)
	var moved: Array[int] = Movement.shift(state, defs, A, Movement.RIGHT, "nudge", rec.record)
	assert_array(moved).is_equal(_typed([C, A]))
	assert_bool(ScoreWalk.score_slot(state, defs, rng, rec.record, 0, 0)).is_false()
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_SCORED)).is_equal(_typed([C]))
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_REVEALED)).is_equal(_typed([A, C]))
	assert_bool(ScoreWalk.run(state, defs, rng, rec.record)).is_false()
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_SCORED)).is_equal(_typed([C, A, D]))
