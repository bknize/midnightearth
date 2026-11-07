class_name TestStatuses
extends GdUnitTestSuite
## Statuses and exit marks (cycle 9 plan P8, P9; spec R32 to R41; DC-13 T04). Muted stops
## triggers and keeps the Score; Squelched stops the Score and the Ongoing and keeps the
## triggers; both halves are Silenced, and ending one leaves the other; On squelch wakes
## only for a lone Squelch (read from Statuses.Applied.wakes_squelch, which the T05 queue
## will consume); cessations (turn, permanent, board scope); protections (Ward over a seat,
## Bastion's Ongoing); exit marks with replacement and the exit pass in Q3 order. Built on
## StubAbilities' shipped-card deck; "fires" is read as the card's TRIGGER_FIRED (DC-13 T06:
## Scout's draw is live); a card that does not fire makes no trigger event at all.

const SEED: int = 1
## Seat 1's copy of a seat-0 instance id.
const OTHER: int = MatchRules.DECK_SIZE

var _cached: MatchCards = null


func _defs() -> MatchCards:
	if _cached == null:
		_cached = StubAbilities.defs()
	return _cached


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## `first` then `second`, as one typed list.
func _joined(first: Array[int], second: Array[int]) -> Array[int]:
	var out: Array[int] = []
	out.append_array(first)
	out.append_array(second)
	return out


func _words(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


## Runs a whole Walk on `state`, recording into `rec`.
func _walk(state: MatchState, rec: StubAbilities.Recorder) -> void:
	ScoreWalk.begin(state)
	var paused: bool = ScoreWalk.run(state, _defs(), MatchRng.new(SEED), rec.record)
	assert_bool(paused).is_false()


func _payload_str(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


# --- R33: the two halves --------------------------------------------------------------


func test_the_stub_pool_builds() -> void:
	var defs: MatchCards = _defs()
	assert_bool(defs.is_valid()).override_failure_message(defs.build_error()).is_true()
	assert_str(defs.def_of(StubAbilities.SCOUT).name).is_equal("Scout")
	assert_str(defs.def_of(StubAbilities.BRACE + OTHER).name).is_equal("Brace")


## An unmuted Scout fires its On reveal (DC-13 T06: TRIGGER_FIRED) and Scores; a Muted
## Scout fires nothing and still Scores.
func test_muted_fires_nothing_and_scores() -> void:
	var plain: MatchState = StubAbilities.table(_typed([StubAbilities.SCOUT]), false)
	var seen: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(plain, seen)
	assert_int(seen.cards_of(MatchEvent.Kind.TRIGGER_FIRED).count(StubAbilities.SCOUT)).is_equal(1)
	var state: MatchState = StubAbilities.table(_typed([StubAbilities.SCOUT]), false)
	var muted: Statuses.Applied = StubAbilities.stub_mute(
		state, _defs(), StubAbilities.SCOUT, Callable()
	)
	assert_bool(muted.ok()).is_true()
	assert_bool(Statuses.fires(state, StubAbilities.SCOUT)).is_false()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, rec)
	assert_array(rec.of_kind(MatchEvent.Kind.TRIGGER_FIZZLED)).is_empty()
	assert_array(rec.of_kind(MatchEvent.Kind.TRIGGER_FIRED)).is_empty()
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_SCORED)).contains_exactly(
		[StubAbilities.SCOUT]
	)
	assert_int(state.scores[0]).is_equal(2)


## A Squelched Scout reveals and fires its On reveal but does not Score, and its Ongoing
## abilities are not read.
func test_squelched_scores_nothing_and_fires() -> void:
	var state: MatchState = StubAbilities.table(_typed([StubAbilities.SCOUT]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(
		StubAbilities.stub_squelch(state, _defs(), StubAbilities.SCOUT, rec.record).ok()
	).is_true()
	assert_bool(Statuses.fires(state, StubAbilities.SCOUT)).is_true()
	assert_bool(Scoring.reads_ongoing(state, StubAbilities.SCOUT)).is_false()
	_walk(state, rec)
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_REVEALED)).contains_exactly(
		[StubAbilities.SCOUT]
	)
	assert_int(rec.cards_of(MatchEvent.Kind.TRIGGER_FIRED).count(StubAbilities.SCOUT)).is_equal(1)
	assert_array(rec.of_kind(MatchEvent.Kind.CARD_SCORED)).is_empty()
	assert_int(state.scores[0]).is_equal(0)


## Muted, then Squelched: Silenced (no trigger, no Score); the view lists "Silenced" alone.
func test_muted_then_squelched_is_silenced_and_the_view_lists_silenced() -> void:
	var card: int = StubAbilities.MOTE
	var state: MatchState = StubAbilities.table(_typed([StubAbilities.SCOUT, card]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	StubAbilities.stub_mute(state, _defs(), card, rec.record)
	StubAbilities.stub_squelch(state, _defs(), card, rec.record)
	assert_bool(Statuses.has(state, card, Statuses.SILENCED)).is_true()
	var view: SeatView = SeatView.build(state, 0, -1, _defs())
	var entry: Dictionary = view.own_row[1]
	var shown: Array = entry["statuses"]
	assert_array(_words(shown)).contains_exactly(["Silenced"])
	var scout_entry: Dictionary = view.own_row[0]
	var scout_shown: Array = scout_entry["statuses"]
	assert_array(scout_shown).is_empty()
	# The opponent sees the badge on a face-up card.
	var other: SeatView = SeatView.build(state, 1, -1, _defs())
	var their: Dictionary = other.opponent_row[1]
	var their_shown: Array = their["statuses"]
	assert_array(_words(their_shown)).contains_exactly(["Silenced"])
	var landed: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.STATUS_SET)
	assert_int(landed.size()).is_equal(2)
	assert_str(_payload_str(landed[0], "status")).is_equal(Statuses.MUTED)
	assert_str(_payload_str(landed[1], "status")).is_equal(Statuses.SQUELCHED)
	assert_str(_payload_str(landed[1], "cessation")).is_equal(Statuses.CEASE_TURN)
	assert_str(_payload_str(landed[1], "cause")).is_equal(StubAbilities.VERB_SQUELCH)


## A Silenced card neither fires nor Scores in the Walk.
func test_a_silenced_card_neither_fires_nor_scores() -> void:
	var state: MatchState = StubAbilities.table(_typed([StubAbilities.SCOUT]), false)
	StubAbilities.stub_silence(state, _defs(), StubAbilities.SCOUT, Callable())
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, rec)
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_REVEALED)).contains_exactly(
		[StubAbilities.SCOUT]
	)
	assert_array(rec.of_kind(MatchEvent.Kind.TRIGGER_FIZZLED)).is_empty()
	assert_array(rec.of_kind(MatchEvent.Kind.CARD_SCORED)).is_empty()
	var revealed: MatchEvent = rec.of_kind(MatchEvent.Kind.CARD_REVEALED)[0]
	var words: Array = revealed.payload["statuses"]
	assert_array(_words(words)).contains_exactly(["Silenced"])


# --- R34: splitting, and On squelch ---------------------------------------------------


## Ending the Mute of a Silenced card leaves it Squelched; the turn's end of a turn Mute
## leaves a longer Squelch in place, so the card fires again (spec scenario).
func test_ending_the_mute_leaves_squelched() -> void:
	var card: int = StubAbilities.SCOUT
	var state: MatchState = StubAbilities.table(_typed([card]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	StubAbilities.stub_silence(state, _defs(), card, rec.record)
	assert_bool(Statuses.end(state, card, Statuses.MUTED, "test", rec.record)).is_true()
	assert_bool(Statuses.has(state, card, Statuses.SILENCED)).is_false()
	assert_bool(Statuses.has(state, card, Statuses.SQUELCHED)).is_true()
	assert_array(Statuses.badges(state, _defs(), card)).contains_exactly(["Squelched"])
	var ended: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.STATUS_ENDED)
	assert_int(ended.size()).is_equal(1)
	assert_str(_payload_str(ended[0], "status")).is_equal(Statuses.MUTED)
	# A turn Mute and a permanent Squelch: turn end leaves the Squelch, triggers fire again.
	var other: int = StubAbilities.MOTE
	StubAbilities.put_row(state, 0, _typed([card, other]), true)
	StubAbilities.stub_mute(state, _defs(), other, Callable())
	var forever: Dictionary = Statuses.cessation(Statuses.CEASE_PERMANENT)
	StubAbilities.stub_squelch(state, _defs(), other, Callable(), forever)
	assert_bool(Statuses.has(state, other, Statuses.SILENCED)).is_true()
	Statuses.on_turn_end(state, Callable())
	assert_bool(Statuses.has(state, other, Statuses.MUTED)).is_false()
	assert_bool(Statuses.has(state, other, Statuses.SQUELCHED)).is_true()
	assert_bool(Statuses.fires(state, other)).is_true()


## On squelch: a lone Squelch on a clear card wakes it; a Squelch on a Muted card (Silence)
## does not, nor does a direct Silence, nor a second Squelch on a Squelched card.
func test_on_squelch_wakes_only_for_a_lone_squelch() -> void:
	var lone: int = StubAbilities.SCAPEGOAT
	var muted: int = StubAbilities.SCAPEGOAT + 1
	var direct: int = StubAbilities.SCAPEGOAT + 2
	var state: MatchState = StubAbilities.table(_typed([lone, muted, direct]), true)
	var first: Statuses.Applied = StubAbilities.stub_squelch(state, _defs(), lone, Callable())
	assert_bool(first.wakes_squelch).is_true()
	var again: Statuses.Applied = StubAbilities.stub_squelch(state, _defs(), lone, Callable())
	assert_bool(again.ok()).is_true()
	assert_bool(again.wakes_squelch).is_false()
	StubAbilities.stub_mute(state, _defs(), muted, Callable())
	var silenced: Statuses.Applied = StubAbilities.stub_squelch(state, _defs(), muted, Callable())
	assert_bool(silenced.ok()).is_true()
	assert_bool(silenced.wakes_squelch).is_false()
	var both: Statuses.Applied = StubAbilities.stub_silence(state, _defs(), direct, Callable())
	assert_array(both.landed).contains_exactly([Statuses.MUTED, Statuses.SQUELCHED])
	assert_bool(both.wakes_squelch).is_false()


# --- R35, R36: cessations and scope ---------------------------------------------------


## A permanent Squelch is Memory: it survives the Pile, a shuffle back and a redraw, and the
## card still does not Score when it is revealed again; a turn Squelch leaves with the row.
func test_a_permanent_squelch_survives_the_pile_and_a_redraw() -> void:
	var card: int = StubAbilities.PEBBLE
	var brief: int = StubAbilities.MOTE
	var state: MatchState = StubAbilities.table(_typed([card, brief]), true)
	var forever: Dictionary = Statuses.cessation(Statuses.CEASE_PERMANENT)
	StubAbilities.stub_squelch(state, _defs(), card, Callable(), forever)
	StubAbilities.stub_squelch(state, _defs(), brief, Callable())
	var defs: MatchCards = _defs()
	var moves: StubAbilities.Recorder = StubAbilities.recorder()
	for gone: int in [card, brief]:
		assert_bool(Statuses.take_from_row(state, 0, gone, moves.record)).is_true()
		TurnFlow.to_pile(state, defs, moves.record, gone, TurnFlow.FROM_ROW, TurnFlow.REASON_DISCARD)
	assert_array(state.seats[0].pile).contains_exactly([card, brief])
	assert_bool(Statuses.has(state, card, Statuses.SQUELCHED)).is_true()
	assert_bool(Statuses.has(state, brief, Statuses.SQUELCHED)).is_false()
	# Back into the Deck and drawn.
	state.seats[0].pile.clear()
	state.seats[0].deck.assign(_typed([card, brief]))
	assert_bool(TurnFlow.draw(state, defs, MatchRng.new(SEED), moves.record, 0)).is_false()
	assert_array(state.seats[0].hand).contains_exactly([card])
	assert_bool(Statuses.has(state, card, Statuses.SQUELCHED)).is_true()
	# Played again and revealed by the Walk: it does not Score.
	state.seats[0].hand.clear()
	StubAbilities.put_row(state, 0, _typed([card]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, rec)
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_REVEALED)).contains_exactly([card])
	assert_array(rec.of_kind(MatchEvent.Kind.CARD_SCORED)).is_empty()


## A turn Anchor ends at turn end (TurnFlow.end_turn's step 14), with STATUS_ENDED.
func test_a_turn_anchor_ends_at_turn_end() -> void:
	var card: int = StubAbilities.MOTE
	var state: MatchState = StubAbilities.table(_typed([card]), true)
	var turn: Dictionary = Statuses.cessation(Statuses.CEASE_TURN)
	var anchored: Statuses.Applied = Statuses.apply(
		state, _defs(), card, Statuses.ANCHORED, turn, "test", Callable()
	)
	assert_bool(anchored.ok()).is_true()
	assert_bool(Statuses.is_anchored(state, _defs(), card)).is_true()
	assert_array(Statuses.badges(state, _defs(), card)).contains_exactly(["Anchored"])
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.end_turn(state, _defs(), MatchRng.new(SEED), rec.record)).is_false()
	assert_bool(Statuses.is_anchored(state, _defs(), card)).is_false()
	var ended: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.STATUS_ENDED)
	assert_int(ended.size()).is_equal(1)
	assert_str(_payload_str(ended[0], "status")).is_equal(Statuses.ANCHORED)
	assert_str(_payload_str(ended[0], "cause")).is_equal(Statuses.CAUSE_TURN_END)
	# STATUS_ENDED comes before TURN_ENDED.
	var last: MatchEvent = rec.events[rec.events.size() - 1]
	assert_int(last.kind).is_equal(MatchEvent.Kind.TURN_ENDED)


## Fade at the exit pass Un-reveals the card: its board-scoped Mute ends (STATUS_ENDED,
## cause unreveal), a permanent Anchor stays.
func test_a_board_scoped_status_ends_on_fade() -> void:
	var card: int = StubAbilities.MOTE
	var state: MatchState = StubAbilities.table(_typed([card]), true)
	var long_mute: Dictionary = Statuses.cessation(
		Statuses.CEASE_CONDITION, Statuses.CONDITION_SOURCE_ON_ROW, StubAbilities.PEBBLE
	)
	StubAbilities.stub_mute(state, _defs(), card, Callable(), long_mute)
	var forever: Dictionary = Statuses.cessation(Statuses.CEASE_PERMANENT)
	Statuses.apply(state, _defs(), card, Statuses.ANCHORED, forever, "test", Callable())
	assert_bool(StubAbilities.stub_fade(state, _defs(), card, Callable())).is_true()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_array(Statuses.exit_pass(state, _defs(), rec.record)).is_empty()
	assert_bool(state.seats[0].is_revealed(card)).is_false()
	assert_bool(Statuses.has(state, card, Statuses.MUTED)).is_false()
	assert_bool(Statuses.has(state, card, Statuses.ANCHORED)).is_true()
	var ended: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.STATUS_ENDED)
	assert_int(ended.size()).is_equal(1)
	assert_str(_payload_str(ended[0], "status")).is_equal(Statuses.MUTED)
	assert_str(_payload_str(ended[0], "cause")).is_equal(Statuses.CAUSE_UNREVEAL)


## A condition status ends when its source leaves its row.
func test_a_condition_status_ends_when_its_source_leaves() -> void:
	var card: int = StubAbilities.MOTE
	var source: int = StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(_typed([card, source]), true)
	var held: Dictionary = Statuses.cessation(
		Statuses.CEASE_CONDITION, Statuses.CONDITION_SOURCE_ON_ROW, source
	)
	StubAbilities.stub_squelch(state, _defs(), card, Callable(), held)
	Statuses.on_turn_end(state, Callable())
	assert_bool(Statuses.has(state, card, Statuses.SQUELCHED)).is_true()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(Statuses.take_from_row(state, 0, source, rec.record)).is_true()
	assert_bool(Statuses.has(state, card, Statuses.SQUELCHED)).is_false()
	assert_int(rec.of_kind(MatchEvent.Kind.STATUS_ENDED).size()).is_equal(1)


# --- R37: protections -----------------------------------------------------------------


## Ward over seat 0: a Mute on its card is blocked, a Silence lands Squelched only (and so
## wakes On squelch); a Mute already in place stays; seat 1's cards are not covered; the
## protection ends at turn end.
func test_ward_blocks_a_mute_and_turns_a_silence_into_a_squelch() -> void:
	var early: int = StubAbilities.MOTE
	var target: int = StubAbilities.MOTE + 1
	var silenced: int = StubAbilities.MOTE + 2
	var theirs: int = StubAbilities.MOTE + OTHER
	var state: MatchState = StubAbilities.table(_typed([early, target, silenced]), true)
	StubAbilities.put_row(state, 1, _typed([theirs]), true)
	StubAbilities.stub_mute(state, _defs(), early, Callable())
	Statuses.protect_seat(state, 0, Statuses.MUTED, Statuses.cessation(Statuses.CEASE_TURN))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var blocked: Statuses.Applied = StubAbilities.stub_mute(state, _defs(), target, rec.record)
	assert_bool(blocked.ok()).is_false()
	assert_array(blocked.blocked).contains_exactly([Statuses.MUTED])
	assert_bool(Statuses.has(state, target, Statuses.MUTED)).is_false()
	assert_array(rec.of_kind(MatchEvent.Kind.STATUS_SET)).is_empty()
	var halved: Statuses.Applied = StubAbilities.stub_silence(state, _defs(), silenced, rec.record)
	assert_array(halved.landed).contains_exactly([Statuses.SQUELCHED])
	assert_array(halved.blocked).contains_exactly([Statuses.MUTED])
	assert_bool(halved.wakes_squelch).is_true()
	assert_bool(Statuses.has(state, silenced, Statuses.SILENCED)).is_false()
	assert_bool(Statuses.has(state, silenced, Statuses.SQUELCHED)).is_true()
	assert_bool(Statuses.has(state, early, Statuses.MUTED)).is_true()
	assert_bool(StubAbilities.stub_mute(state, _defs(), theirs, Callable()).ok()).is_true()
	Statuses.on_turn_end(state, Callable())
	assert_bool(state.seat_protections[0].is_empty()).is_true()
	assert_bool(StubAbilities.stub_mute(state, _defs(), target, Callable()).ok()).is_true()


## Bastion's Ongoing blocks Condemned while read (face up, not Squelched); face down or
## Squelched it does not. An effect's "cannot be Condemned" blocks it too.
func test_bastion_blocks_condemned() -> void:
	var bastion: int = StubAbilities.BASTION
	var hidden: int = StubAbilities.BASTION + 1
	var quiet: int = StubAbilities.BASTION + 2
	var guarded: int = StubAbilities.MOTE
	var state: MatchState = StubAbilities.table(_typed([bastion, hidden, quiet, guarded]), true)
	state.seats[0].revealed.erase(hidden)
	StubAbilities.stub_squelch(state, _defs(), quiet, Callable())
	Statuses.protect_card(state, guarded, Statuses.CONDEMNED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(StubAbilities.stub_condemn(state, _defs(), bastion, rec.record)).is_false()
	assert_str(Statuses.exit_mark_of(state, bastion)).is_equal("")
	assert_array(rec.of_kind(MatchEvent.Kind.EXIT_MARKED)).is_empty()
	assert_bool(StubAbilities.stub_condemn(state, _defs(), guarded, rec.record)).is_false()
	assert_bool(StubAbilities.stub_condemn(state, _defs(), hidden, rec.record)).is_true()
	assert_bool(StubAbilities.stub_condemn(state, _defs(), quiet, rec.record)).is_true()
	# Bastion is not protected from Fleeting.
	assert_bool(StubAbilities.stub_fleeting(state, _defs(), bastion, rec.record)).is_true()


# --- R38 to R41: exit marks and the exit pass -----------------------------------------


## Fleeting then Condemned: the card holds Condemned only; EXIT_MARKED names the replaced.
func test_fleeting_then_condemned_holds_condemned_only() -> void:
	var card: int = StubAbilities.MOTE
	var state: MatchState = StubAbilities.table(_typed([card]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(StubAbilities.stub_fleeting(state, _defs(), card, rec.record)).is_true()
	assert_bool(StubAbilities.stub_condemn(state, _defs(), card, rec.record)).is_true()
	assert_str(Statuses.exit_mark_of(state, card)).is_equal(Statuses.CONDEMNED)
	assert_bool(Statuses.has(state, card, Statuses.FLEETING)).is_false()
	assert_array(Statuses.badges(state, _defs(), card)).contains_exactly(["Condemned"])
	var marked: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.EXIT_MARKED)
	assert_int(marked.size()).is_equal(2)
	assert_str(_payload_str(marked[0], "replaced")).is_equal("")
	assert_str(_payload_str(marked[1], "mark")).is_equal(Statuses.CONDEMNED)
	assert_str(_payload_str(marked[1], "replaced")).is_equal(Statuses.FLEETING)
	var view: SeatView = SeatView.build(state, 0, -1, _defs())
	var entry: Dictionary = view.own_row[0]
	var mark: String = entry["exit_mark"]
	assert_str(mark).is_equal(Statuses.CONDEMNED)


## A Condemned card Scores this Walk, then at turn end goes to its Owner's Pile as a
## Discard (reason condemned), announced by EXIT_RESOLVED.
func test_a_condemned_card_scores_then_goes_to_its_owners_pile() -> void:
	var card: int = StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(_typed([card]), true)
	assert_bool(StubAbilities.stub_condemn(state, _defs(), card, Callable())).is_true()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, rec)
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_SCORED)).contains_exactly([card])
	assert_int(state.scores[0]).is_equal(3)
	var ended: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.end_turn(state, _defs(), MatchRng.new(SEED), ended.record)).is_false()
	assert_array(state.seats[0].board).is_empty()
	assert_array(state.seats[0].pile).contains_exactly([card])
	var discarded: Array[MatchEvent] = ended.of_kind(MatchEvent.Kind.CARD_DISCARDED)
	assert_int(discarded.size()).is_equal(1)
	assert_str(_payload_str(discarded[0], "reason")).is_equal(TurnFlow.REASON_CONDEMNED)
	assert_str(_payload_str(discarded[0], "from")).is_equal(TurnFlow.FROM_ROW)
	var resolved: Array[MatchEvent] = ended.of_kind(MatchEvent.Kind.EXIT_RESOLVED)
	assert_int(resolved.size()).is_equal(1)
	assert_str(_payload_str(resolved[0], "to")).is_equal(Statuses.TO_PILE)
	assert_int(_payload_int(resolved[0], "owner")).is_equal(0)


## Fleeting sends the card to its Owner's hand: Board changes gone, Memory kept.
func test_fleeting_goes_to_the_owners_hand_keeping_memory() -> void:
	var card: int = StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(_typed([card]), true)
	state.card_state_for(card).power_delta = 2
	state.memory_for(card).power = 1
	StubAbilities.stub_fleeting(state, _defs(), card, Callable())
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_array(Statuses.exit_pass(state, _defs(), rec.record)).is_empty()
	assert_array(state.seats[0].board).is_empty()
	assert_array(state.seats[0].hand).contains_exactly([card])
	assert_bool(state.seats[0].is_revealed(card)).is_false()
	assert_object(state.card_state(card)).is_null()
	assert_int(state.memory_of(card).power).is_equal(1)
	assert_int(Scoring.stats(card, state, _defs()).power).is_equal(4)
	var returned: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.CARD_RETURNED)
	assert_int(returned.size()).is_equal(1)
	assert_int(_payload_int(returned[0], "owner")).is_equal(0)
	assert_int(returned[0].owner_seat).is_equal(MatchEvent.PUBLIC)


## Fade flips the card face down in its slot: Board changes gone, Memory kept,
## CARD_UNREVEALED {seat, card, slot}.
func test_fade_flips_face_down_keeping_memory() -> void:
	var card: int = StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(_typed([StubAbilities.MOTE, card]), true)
	state.card_state_for(card).power_delta = 2
	state.memory_for(card).power = 1
	StubAbilities.stub_fade(state, _defs(), card, Callable())
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_array(Statuses.exit_pass(state, _defs(), rec.record)).is_empty()
	assert_array(state.seats[0].board).contains_exactly([StubAbilities.MOTE, card])
	assert_bool(state.seats[0].is_revealed(card)).is_false()
	assert_object(state.card_state(card)).is_null()
	assert_int(state.memory_of(card).power).is_equal(1)
	var flipped: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.CARD_UNREVEALED)
	assert_int(flipped.size()).is_equal(1)
	assert_dict(flipped[0].payload).is_equal({"seat": 0, "card": card, "slot": 1})
	var resolved: MatchEvent = rec.of_kind(MatchEvent.Kind.EXIT_RESOLVED)[0]
	assert_str(_payload_str(resolved, "to")).is_equal(Statuses.TO_FACE_DOWN)


## A face-down card's exit (DC-14 T17): EXIT_RESOLVED and CARD_RETURNED carry the row's
## `seat` and the card's `slot` before it left; the other seat's copy keeps both and hides
## `card`, and a hidden Fade's copy blanks `mark` and `instead_of`, so it names neither.
func test_a_hidden_exit_carries_its_slot_and_hides_its_mark() -> void:
	var faded: int = StubAbilities.PEBBLE
	var fleeting: int = StubAbilities.WISP
	var state: MatchState = StubAbilities.table(
		_typed([StubAbilities.MOTE, faded, fleeting]), false
	)
	StubAbilities.stub_fade(state, _defs(), faded, Callable())
	StubAbilities.stub_fleeting(state, _defs(), fleeting, Callable())
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_array(Statuses.exit_pass(state, _defs(), rec.record)).is_empty()
	var resolved: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.EXIT_RESOLVED)
	assert_int(resolved.size()).is_equal(2)
	var fade_event: MatchEvent = resolved[0]
	assert_int(fade_event.owner_seat).is_equal(0)
	assert_int(_payload_int(fade_event, "seat")).is_equal(0)
	assert_int(_payload_int(fade_event, "slot")).is_equal(1)
	assert_str(_payload_str(fade_event, "mark")).is_equal(Statuses.FADE)
	var seen: MatchEvent = fade_event.redacted_for(1)
	assert_int(_payload_int(seen, "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_int(_payload_int(seen, "seat")).is_equal(0)
	assert_int(_payload_int(seen, "slot")).is_equal(1)
	assert_str(_payload_str(seen, "mark")).is_empty()
	assert_str(_payload_str(seen, "instead_of")).is_empty()
	assert_str(_payload_str(seen, "to")).is_equal(Statuses.TO_FACE_DOWN)
	var own: MatchEvent = fade_event.redacted_for(0)
	assert_str(_payload_str(own, "mark")).is_equal(Statuses.FADE)
	var gone: MatchEvent = resolved[1].redacted_for(1)
	assert_int(_payload_int(gone, "slot")).is_equal(2)
	assert_str(_payload_str(gone, "mark")).is_empty()
	assert_str(_payload_str(gone, "to")).is_equal(Statuses.TO_HAND)
	var returned: MatchEvent = rec.of_kind(MatchEvent.Kind.CARD_RETURNED)[0]
	var returned_seen: MatchEvent = returned.redacted_for(1)
	assert_int(_payload_int(returned_seen, "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_int(_payload_int(returned_seen, "seat")).is_equal(0)
	assert_int(_payload_int(returned_seen, "slot")).is_equal(2)
	assert_int(_payload_int(returned_seen, "owner")).is_equal(0)
	assert_int(returned_seen.owner_seat).is_equal(0)


## A card seat 0 controls but seat 1 owns: Fleeting returns it to seat 1's hand, Condemned
## sends it to seat 1's Pile.
func test_a_card_the_other_seat_controls_returns_to_its_owner() -> void:
	var fleeting: int = StubAbilities.PEBBLE + OTHER
	var condemned: int = StubAbilities.MOTE + OTHER
	var state: MatchState = StubAbilities.table(_typed([fleeting, condemned]), true)
	StubAbilities.stub_fleeting(state, _defs(), fleeting, Callable())
	StubAbilities.stub_condemn(state, _defs(), condemned, Callable())
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var discarded: Array[int] = Statuses.exit_pass(state, _defs(), rec.record)
	assert_array(discarded).contains_exactly([condemned])
	assert_array(state.seats[0].board).is_empty()
	assert_array(state.seats[0].hand).is_empty()
	assert_array(state.seats[0].pile).is_empty()
	assert_array(state.seats[1].hand).contains_exactly([fleeting])
	assert_array(state.seats[1].pile).contains_exactly([condemned])
	var returned: MatchEvent = rec.of_kind(MatchEvent.Kind.CARD_RETURNED)[0]
	assert_int(_payload_int(returned, "owner")).is_equal(1)
	var pile_event: MatchEvent = rec.of_kind(MatchEvent.Kind.CARD_DISCARDED)[0]
	assert_int(_payload_int(pile_event, "owner")).is_equal(1)


## The pass runs the first seat's row first, each in slot order (Q3), and returns the
## Discards in that order.
func test_the_pass_runs_the_first_seats_row_first_in_slot_order() -> void:
	var own: Array[int] = _typed([StubAbilities.MOTE, StubAbilities.PEBBLE, StubAbilities.WISP])
	var theirs: Array[int] = _typed(
		[StubAbilities.MOTE + OTHER, StubAbilities.PEBBLE + OTHER, StubAbilities.WISP + OTHER]
	)
	var state: MatchState = StubAbilities.table(own, true)
	StubAbilities.put_row(state, 1, theirs, true)
	state.first_seat = 1
	var both: Array[int] = _joined(theirs, own)
	for card: int in both:
		StubAbilities.stub_condemn(state, _defs(), card, Callable())
	StubAbilities.stub_fade(state, _defs(), StubAbilities.PEBBLE, Callable())
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var discarded: Array[int] = Statuses.exit_pass(state, _defs(), rec.record)
	var expected: Array[int] = _joined(theirs, _typed([StubAbilities.MOTE, StubAbilities.WISP]))
	assert_array(discarded).is_equal(expected)
	var order: Array[int] = rec.cards_of(MatchEvent.Kind.EXIT_RESOLVED)
	assert_array(order).is_equal(both)
	assert_array(state.seats[0].board).contains_exactly([StubAbilities.PEBBLE])
	assert_array(state.seats[1].board).is_empty()
	# No mark is left behind.
	assert_str(Statuses.exit_mark_of(state, StubAbilities.PEBBLE)).is_equal("")
