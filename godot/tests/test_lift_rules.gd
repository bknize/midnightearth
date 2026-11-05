# gdlint: ignore=max-public-methods
class_name TestLiftRules
extends GdUnitTestSuite
## LiftRules (R1, R2, R9, R11). Steps come from a real seed-1 bot-vs-bot match, built the
## way test_board_steps.gd builds them (the fixture deck on both seats, DC-07 T02).

const SEED: int = 1
const MAX_ACTIONS: int = 2000
const ABSENT_ID: int = -999
const ANY_SEAT: int = -2

var _cached_steps: Array[BoardStep] = []

# --- Helpers --------------------------------------------------------------------------


func _steps() -> Array[BoardStep]:
	if not _cached_steps.is_empty():
		return _cached_steps
	var cards: CardDb = FixtureDecks.cards()
	var engine: MatchEngine = FixtureDecks.engine(SEED, cards)
	var collected: Array[MatchEvent] = []
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	collected.append_array(started.events_for(0))
	var bots: Array[GreedyBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(GreedyBot.new(GreedyBot.seed_for(SEED, seat), engine.match_cards()))
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var awaited: int = engine.awaited_seat()
		var action: EngineAction = bots[awaited].choose(engine.view_for(awaited), engine)
		var result: ApplyResult = engine.apply(action)
		assert_bool(result.ok).is_true()
		if not result.ok:
			break
		collected.append_array(result.events_for(0))
		actions += 1
	_cached_steps = BoardSteps.from_events(collected, 1.0)
	return _cached_steps


## The first step of `kind` (and of `seat`, unless ANY_SEAT); null if none.
func _first(kind: int, seat: int = ANY_SEAT) -> BoardStep:
	for step: BoardStep in _steps():
		if step.kind == kind and (seat == ANY_SEAT or step.seat == seat):
			return step
	return null


func _commit_ids(step: BoardStep) -> Array[int]:
	var raw: Array = step.source.payload["cards"]
	var ids: Array[int] = []
	ids.assign(raw)
	return ids


# --- may_lift -------------------------------------------------------------------------


func test_may_lift_is_face_up_only_for_every_place() -> void:
	var places: Array[LiftRules.Place] = [
		LiftRules.Place.HAND,
		LiftRules.Place.ROW,
		LiftRules.Place.OPPONENT_ROW,
		LiftRules.Place.OPPONENT_HAND,
	]
	for place: LiftRules.Place in places:
		assert_bool(LiftRules.may_lift(place, true)).is_true()
		assert_bool(LiftRules.may_lift(place, false)).is_false()


# --- step_touches ---------------------------------------------------------------------


func test_clear_table_touches_any_held_card() -> void:
	var step: BoardStep = _first(BoardStep.Kind.CLEAR_TABLE)
	assert_object(step).is_not_null()
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.HAND, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.ROW, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.OPPONENT_ROW, false)).is_true()


func test_own_reveal_touches_only_the_held_card() -> void:
	var step: BoardStep = _first(BoardStep.Kind.PULSE, 0)
	assert_object(step).is_not_null()
	assert_bool(LiftRules.step_touches(step, step.card, LiftRules.Place.ROW, false)).is_true()
	assert_bool(LiftRules.step_touches(step, step.card + 1, LiftRules.Place.ROW, false)).is_false()


func test_opponent_reveal_never_touches() -> void:
	var step: BoardStep = _first(BoardStep.Kind.PULSE, 1)
	assert_object(step).is_not_null()
	var place: LiftRules.Place = LiftRules.Place.OPPONENT_ROW
	assert_bool(LiftRules.step_touches(step, step.card, place, false)).is_false()


func test_turn_start_touches_only_a_staged_card() -> void:
	var step: BoardStep = _first(BoardStep.Kind.TURN_START)
	assert_object(step).is_not_null()
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.ROW, true)).is_true()
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.ROW, false)).is_false()


func test_player_commit_touches_a_held_hand_card_in_the_list() -> void:
	var step: BoardStep = _first(BoardStep.Kind.PLAYER_COMMIT, 0)
	assert_object(step).is_not_null()
	var ids: Array[int] = _commit_ids(step)
	assert_array(ids).is_not_empty()
	assert_bool(LiftRules.step_touches(step, ids[0], LiftRules.Place.HAND, false)).is_true()


func test_player_commit_ignores_a_card_not_in_the_list() -> void:
	var step: BoardStep = _first(BoardStep.Kind.PLAYER_COMMIT, 0)
	assert_object(step).is_not_null()
	assert_bool(LiftRules.step_touches(step, ABSENT_ID, LiftRules.Place.HAND, false)).is_false()


func test_player_commit_touches_a_held_staged_card_on_the_row() -> void:
	# The commit now flips the staged cards face down in place (R46).
	var step: BoardStep = _first(BoardStep.Kind.PLAYER_COMMIT, 0)
	assert_object(step).is_not_null()
	var ids: Array[int] = _commit_ids(step)
	assert_array(ids).is_not_empty()
	assert_bool(LiftRules.step_touches(step, ids[0], LiftRules.Place.ROW, true)).is_true()
	assert_bool(LiftRules.step_touches(step, ABSENT_ID, LiftRules.Place.ROW, false)).is_false()


func test_match_end_never_touches() -> void:
	var step: BoardStep = _first(BoardStep.Kind.MATCH_END)
	assert_object(step).is_not_null()
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.ROW, true)).is_false()
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.HAND, true)).is_false()


func test_opponent_commit_steps_never_touch() -> void:
	var wait: BoardStep = _first(BoardStep.Kind.BOT_WAIT)
	var slide: BoardStep = _first(BoardStep.Kind.OPPONENT_COMMIT)
	assert_object(wait).is_not_null()
	assert_object(slide).is_not_null()
	assert_bool(LiftRules.step_touches(wait, 5, LiftRules.Place.HAND, false)).is_false()
	assert_bool(LiftRules.step_touches(slide, 5, LiftRules.Place.HAND, false)).is_false()


# --- step_touches: the effect steps (R54) ---------------------------------------------


func _named(kind: int, seat: int, card: int) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = kind
	step.seat = seat
	step.card = card
	return step


func test_stats_touch_only_the_held_card() -> void:
	var step: BoardStep = _named(BoardStep.Kind.STATS, 0, 5)
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.ROW, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 6, LiftRules.Place.ROW, false)).is_false()


func test_destroy_touches_only_the_held_card() -> void:
	var step: BoardStep = _named(BoardStep.Kind.DESTROY, 1, 25)
	var place: LiftRules.Place = LiftRules.Place.OPPONENT_ROW
	assert_bool(LiftRules.step_touches(step, 25, place, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 26, place, false)).is_false()


func test_hidden_destroy_never_touches_a_face_up_held_card() -> void:
	var step: BoardStep = _named(BoardStep.Kind.DESTROY, 1, -1)
	var place: LiftRules.Place = LiftRules.Place.OPPONENT_ROW
	assert_bool(LiftRules.step_touches(step, 25, place, false)).is_false()


func test_return_touches_only_the_held_card() -> void:
	var step: BoardStep = _named(BoardStep.Kind.RETURN, 0, 7)
	assert_bool(LiftRules.step_touches(step, 7, LiftRules.Place.ROW, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 8, LiftRules.Place.ROW, false)).is_false()


func test_discard_touches_only_the_held_card() -> void:
	var step: BoardStep = _named(BoardStep.Kind.DISCARD, 0, 9)
	assert_bool(LiftRules.step_touches(step, 9, LiftRules.Place.HAND, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 10, LiftRules.Place.HAND, false)).is_false()


func test_burn_touches_a_held_row_card() -> void:
	var step: BoardStep = _named(BoardStep.Kind.BURN, 0, 11)
	assert_bool(LiftRules.step_touches(step, 11, LiftRules.Place.ROW, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 12, LiftRules.Place.ROW, false)).is_false()


func test_move_touches_a_card_on_the_moved_row() -> void:
	var own: BoardStep = _named(BoardStep.Kind.MOVE, 0, 3)
	assert_bool(LiftRules.step_touches(own, 3, LiftRules.Place.ROW, false)).is_true()
	# The other half of a swap names a different card but still reorders the held one's row.
	assert_bool(LiftRules.step_touches(own, 4, LiftRules.Place.ROW, false)).is_true()
	assert_bool(LiftRules.step_touches(own, 4, LiftRules.Place.HAND, false)).is_false()
	assert_bool(LiftRules.step_touches(own, 4, LiftRules.Place.OPPONENT_ROW, false)).is_false()
	var theirs: BoardStep = _named(BoardStep.Kind.MOVE, 1, -1)
	assert_bool(LiftRules.step_touches(theirs, 4, LiftRules.Place.OPPONENT_ROW, false)).is_true()
	assert_bool(LiftRules.step_touches(theirs, 4, LiftRules.Place.ROW, false)).is_false()


func test_effect_fizzle_and_choice_show_never_touch() -> void:
	var kinds: Array[int] = [
		BoardStep.Kind.EFFECT, BoardStep.Kind.FIZZLE, BoardStep.Kind.CHOICE_SHOW
	]
	for kind: int in kinds:
		var step: BoardStep = _named(kind, 0, 5)
		assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.ROW, true)).is_false()


# --- DC-06 steps (R37) ------------------------------------------------------------------


func _card_step(kind: int, seat: int, card: int) -> BoardStep:
	var step: BoardStep = BoardStep.new()
	step.kind = kind
	step.seat = seat
	step.card = card
	return step


func test_destroy_mark_and_clear_destroyed_touch_only_the_held_card() -> void:
	for kind: int in [BoardStep.Kind.DESTROY, BoardStep.Kind.CLEAR_DESTROYED]:
		var named: BoardStep = _card_step(kind, 0, 7)
		var other: BoardStep = _card_step(kind, 0, 8)
		assert_bool(LiftRules.step_touches(named, 7, LiftRules.Place.ROW, false)).is_true()
		assert_bool(LiftRules.step_touches(other, 7, LiftRules.Place.ROW, false)).is_false()


func test_a_re_pulse_of_the_held_card_touches_it() -> void:
	var pulse: BoardStep = _card_step(BoardStep.Kind.PULSE, 0, 7)
	pulse.again = true
	assert_bool(LiftRules.step_touches(pulse, 7, LiftRules.Place.ROW, false)).is_true()
	var elsewhere: BoardStep = _card_step(BoardStep.Kind.PULSE, 0, 9)
	assert_bool(LiftRules.step_touches(elsewhere, 7, LiftRules.Place.ROW, false)).is_false()


func test_a_crew_lifts_to_read_and_a_crew_firing_sets_a_held_crew_down() -> void:
	assert_bool(LiftRules.may_lift(LiftRules.Place.CREW, true)).is_true()
	var step: BoardStep = BoardStep.new()
	step.kind = BoardStep.Kind.CREW_FIRE
	assert_bool(LiftRules.step_touches(step, -1, LiftRules.Place.CREW, false)).is_true()
	assert_bool(LiftRules.step_touches(step, 5, LiftRules.Place.HAND, false)).is_false()
