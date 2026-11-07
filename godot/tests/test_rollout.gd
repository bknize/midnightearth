class_name TestRollout
extends GdUnitTestSuite
## The rollout entry (cycle 11 T04; spec R16 to R24, plan P5 to P8, P10): the hidden sets
## per Owner on a hand-built state (a face-down Fade card, a looked-at card, `deck_top`, a
## created Dross in the other hand), the determinized copy keeping the seat's view and
## moving each card's records as the class comment says, the real match untouched by 16
## play-outs, same seeds same values, the value formula, `capped` and `rejected`, the
## candidate sampler, and the seed-1 pin. The seed-1 position is seat 1's first Round 3
## commit of seed 1 (its seeded pairing) under two `random` bots; play-outs there are capped
## short where the full length is not the point, to keep the gdUnit budget.

const T: int = MatchRules.DECK_SIZE
const DROSS: int = MatchCards.CREATED_BASE
const FADED: int = T + 30
const LOOKED: int = T + 31
const SHOWN: int = T + 32
const OWN_DOWN: int = 12
const POLICY: String = "random"
const POSITION_SEED: int = 1
const POSITION_SEAT: int = 1
const POSITION_ROUND: int = 3
const PREFIX_CAP: int = 600
const LABEL_SEED: int = 11
const SHORT_CAP: int = 300
## The value and action count of the one play-out of test_seed_1_pin, pinned at DC-16;
## re-pin from the failure message after a rules or data change.
const PIN_VALUE: int = -1030  # Pinned DC-16 (seed 1, seat 1, first Round 3 commit, random)
const PIN_ACTIONS: int = 115  # Pinned DC-16

var _cached_defs: MatchCards = null
var _cached_position: MatchEngine = null

# --- Fixtures -------------------------------------------------------------------------


## Greed against Greed, shipped pool (ids 0..39 seat 0's deck, 40..79 seat 1's).
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


## A hand-built state at seat 0's commit: seat 0 holds 0..2 with 20..22 in its Deck and 12
## face down on its row; seat 1 holds T+1, T+2 and a created Dross (owner 1), T+20 and T+21
## in its Deck, and on its row FADED face down with a Fade mark, LOOKED face down but looked
## at by seat 0 and SHOWN revealed. T+1 has Memory.
func _state() -> MatchState:
	var state: MatchState = MatchState.new(5)
	state.deck_ids.assign(["greed", "greed"])
	state.round_number = 2
	state.turn = 3
	state.first_seat = 0
	state.phase = MatchState.Phase.AWAIT_FIRST
	state.seats[0].hand.assign(_typed([0, 1, 2]))
	state.seats[0].deck.assign(_typed([20, 21, 22]))
	state.seats[0].board.assign(_typed([OWN_DOWN]))
	state.seats[0].pile.assign(_typed([4]))
	state.seats[0].looked[LOOKED] = true
	state.seats[1].hand.assign(_typed([T + 1, T + 2, DROSS]))
	state.seats[1].deck.assign(_typed([T + 20, T + 21]))
	state.seats[1].board.assign(_typed([FADED, LOOKED, SHOWN]))
	state.seats[1].revealed[SHOWN] = true
	state.seats[1].pile.assign(_typed([T + 4]))
	state.card_state_for(FADED).exit_mark = Statuses.FADE
	state.memory_for(T + 1).power = 2
	state.created[DROSS] = {"def": "dross", "owner": 1}
	state.next_created_id = DROSS + 1
	return state


## An engine around a copy of `state` on Greed against Greed with the Dross recorded.
func _engine_on(state: MatchState) -> MatchEngine:
	var cards: MatchCards = _defs().copy()
	cards.record_created(DROSS, cards.pool_def("dross"), 1)
	return MatchEngine.from_state(state.duplicate(), cards, 0)


## Seed 1 under its seeded pairing, played by two `random` bots to seat 1's first commit
## of Round 3 (no prompt open). Built once; tests only read it.
func _position() -> MatchEngine:
	if _cached_position != null:
		return _cached_position
	var engine: MatchEngine = MatchEngine.create(
		POSITION_SEED,
		CardDb.load_default(),
		DeckList.load_default(),
		_typed_strings(["", ""]),
		CrewPool.load_default()
	)
	assert_bool(engine.start().ok).is_true()
	var bots: Array[BotPlayer] = []
	for seat: int in range(MatchEngine.SEATS):
		var bot_seed: int = BotRegistry.seed_for(POSITION_SEED, seat)
		bots.append(BotRegistry.make(POLICY, bot_seed, engine.match_cards()))
	var actions: int = 0
	while not engine.is_over() and actions < PREFIX_CAP:
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		var at_commit: bool = engine.open_prompt().is_empty()
		if seat == POSITION_SEAT and at_commit and view.round_number == POSITION_ROUND:
			_cached_position = engine
			return engine
		assert_bool(engine.apply(bots[seat].choose(view, engine)).ok).is_true()
		actions += 1
	fail("seed 1 never reached seat 1's Round 3 commit")
	return engine


func _typed_strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


## The commit seat 1's own `random` bot would play at the position.
func _candidate(engine: MatchEngine) -> EngineAction:
	var bot_seed: int = BotRegistry.seed_for(POSITION_SEED, POSITION_SEAT)
	var bot: BotPlayer = BotRegistry.make(POLICY, bot_seed, engine.match_cards())
	return bot.choose(engine.view_for(POSITION_SEAT), engine)


## A Pass (an empty commit) for `seat`: always legal at its commit.
func _pass(seat: int) -> EngineAction:
	var none: Array[int] = []
	return EngineAction.commit(seat, none)


func _det_seed(candidate: int, det: int) -> int:
	var parts: Array[int] = [candidate, det]
	return MatchRng.derive_seed(LABEL_SEED, parts)


func _ints(values: Variant) -> Array[int]:
	var listed: Array = values
	var out: Array[int] = []
	out.assign(listed)
	return out


## The list `key` of seat `seat` in a full state.
func _zone(full: Dictionary, key: String, seat: int) -> Array[int]:
	var per_seat: Array = full[key]
	return _ints(per_seat[seat])


# --- Hidden sets ----------------------------------------------------------------------


func test_hidden_sets_from_seat_0_skip_the_looked_and_revealed_cards() -> void:
	var engine: MatchEngine = _engine_on(_state())
	var sets: Array[Array] = Rollout.hidden_sets(engine, 0)
	assert_array(sets[0]).is_equal(_typed([20, 21, 22]))
	# The other hand (the Dross too), the face-down Fade card and the other Deck; not
	# LOOKED (looked at) nor SHOWN (revealed).
	assert_array(sets[1]).is_equal(_typed([T + 1, T + 2, T + 20, T + 21, FADED, DROSS]))


func test_hidden_sets_from_seat_1_hold_the_other_hand_row_and_deck() -> void:
	var engine: MatchEngine = _engine_on(_state())
	var sets: Array[Array] = Rollout.hidden_sets(engine, 1)
	# Seat 0's hand, its face-down 12 (seat 1 has not looked) and its Deck.
	assert_array(sets[0]).is_equal(_typed([0, 1, 2, OWN_DOWN, 20, 21, 22]))
	assert_array(sets[1]).is_equal(_typed([T + 20, T + 21]))


func test_hidden_sets_leave_out_the_deck_top_of_an_open_delve() -> void:
	var state: MatchState = _state()
	state.phase = MatchState.Phase.AWAIT_CHOICE
	state.prompt = {
		"seat": 0,
		"card": -1,
		"crew": "",
		"verb": "delve",
		"zone": "own_deck_top",
		"options": [0, 1],
		"multi": false,
		"exact": -1,
		"min": 1,
		"optional": false,
		"resume": Choice.RESUME_TURN_START,
		"step": "D1",
	}
	var engine: MatchEngine = _engine_on(state)
	assert_array(engine.view_for(0).deck_top).is_equal(_typed([20, 21]))
	assert_array(Rollout.hidden_sets(engine, 0)[0]).is_equal(_typed([22]))


func test_hidden_sets_include_the_other_seats_face_down_commit() -> void:
	var state: MatchState = _state()
	state.first_seat = 1
	state.phase = MatchState.Phase.AWAIT_SECOND
	state.seats[1].hand.assign(_typed([T + 1]))
	state.pending.assign(_typed([T + 2]))
	state.pending_slots.assign(_typed([3]))
	var engine: MatchEngine = _engine_on(state)
	assert_int(engine.awaited_seat()).is_equal(0)
	assert_array(Rollout.hidden_sets(engine, 0)[1]).contains([T + 2])
	assert_array(Rollout.hidden_sets(engine, 1)[1]).not_contains([T + 2])


func test_hidden_sets_are_empty_for_a_seat_out_of_range() -> void:
	var engine: MatchEngine = _engine_on(_state())
	var none: Array[Array] = Rollout.hidden_sets(engine, 2)
	assert_int(none.size()).is_equal(2)
	assert_array(none[0]).is_empty()
	assert_array(none[1]).is_empty()
	assert_object(Rollout.determinize(engine, -1, 3)).is_null()


# --- Determinized copies --------------------------------------------------------------


func test_a_copy_keeps_the_seats_view_and_moves_records_with_their_owners() -> void:
	var engine: MatchEngine = _engine_on(_state())
	var before: Dictionary = engine.full_state()
	var view: Dictionary = engine.view_for(0).to_dict()
	var faded_moved: bool = false
	var dross_moved: bool = false
	for det_seed: int in range(1, 9):
		var copy: MatchEngine = Rollout.determinize(engine, 0, det_seed)
		assert_dict(copy.view_for(0).to_dict()).is_equal(view)
		var full: Dictionary = copy.full_state()
		# Known zones keep their cards.
		assert_array(_zone(full, "hand", 0)).is_equal(_typed([0, 1, 2]))
		assert_array(_zone(full, "board", 0)).is_equal(_typed([OWN_DOWN]))
		var row: Array[int] = _zone(full, "board", 1)
		assert_int(row[1]).is_equal(LOOKED)
		assert_int(row[2]).is_equal(SHOWN)
		# Hidden zones keep their counts and Owners' sets.
		assert_int(_zone(full, "hand", 1).size()).is_equal(3)
		assert_int(_zone(full, "deck", 1).size()).is_equal(2)
		assert_array(Rollout.hidden_sets(copy, 0)).is_equal(Rollout.hidden_sets(engine, 0))
		# The Fade mark stays on the face-down slot; Memory and the Dross stay by identity.
		var states: Dictionary = full["card_states"]
		assert_int(states.size()).is_equal(1)
		assert_bool(states.has(row[0])).is_true()
		var faded: Dictionary = states[row[0]]
		assert_str(faded["exit_mark"]).is_equal(Statuses.FADE)
		assert_dict(full["memory"]).is_equal(before["memory"])
		assert_dict(full["created"]).is_equal(before["created"])
		assert_str(copy.match_cards().def_of(DROSS).id).is_equal("dross")
		faded_moved = faded_moved or row[0] != FADED
		dross_moved = dross_moved or _zone(full, "hand", 1)[2] != DROSS
	assert_bool(faded_moved).is_true()
	assert_bool(dross_moved).is_true()
	assert_dict(engine.full_state()).is_equal(before)


func test_a_copy_at_the_seed_1_position_keeps_seat_1s_view() -> void:
	var engine: MatchEngine = _position()
	var before: Dictionary = engine.full_state()
	var copy: MatchEngine = Rollout.determinize(engine, POSITION_SEAT, 7)
	assert_dict(copy.view_for(POSITION_SEAT).to_dict()).is_equal(
		engine.view_for(POSITION_SEAT).to_dict()
	)
	var full: Dictionary = copy.full_state()
	assert_array(_zone(full, "hand", 1)).is_equal(_zone(before, "hand", 1))
	assert_array(_zone(full, "pile", 0)).is_equal(_zone(before, "pile", 0))
	assert_array(_zone(full, "pile", 1)).is_equal(_zone(before, "pile", 1))
	assert_int(_zone(full, "hand", 0).size()).is_equal(_zone(before, "hand", 0).size())
	assert_array(Rollout.hidden_sets(copy, POSITION_SEAT)).is_equal(
		Rollout.hidden_sets(engine, POSITION_SEAT)
	)
	# The copy's stream is its own (P7), not the real match's.
	var parts: Array[int] = [Rollout.ROLLOUT_TAG]
	var expected: MatchRng = MatchRng.new(MatchRng.derive_seed(7, parts))
	assert_int(full["rng_state"]).is_equal(expected.state)
	assert_dict(engine.full_state()).is_equal(before)


func test_the_real_match_is_unchanged_by_16_play_outs() -> void:
	var engine: MatchEngine = _position()
	var before: Dictionary = engine.full_state()
	var log_before: String = engine.action_log().to_json()
	var count_before: int = engine.accepted_action_count()
	var next_created: int = before["next_created_id"]
	var candidate: EngineAction = _candidate(engine)
	for det: int in range(16):
		var det_seed: int = _det_seed(0, det)
		var copy: MatchEngine = Rollout.determinize(engine, POSITION_SEAT, det_seed)
		var played: Dictionary = Rollout.play(
			copy, POSITION_SEAT, candidate, POLICY, det_seed, SHORT_CAP
		)
		assert_bool(played["rejected"]).is_false()
	assert_dict(engine.full_state()).is_equal(before)
	assert_str(engine.action_log().to_json()).is_equal(log_before)
	assert_int(engine.accepted_action_count()).is_equal(count_before)
	# No card a copy created was recorded on the real match's definitions.
	for created: int in range(next_created, next_created + 16):
		assert_object(engine.match_cards().def_of(created)).is_null()


# --- Play-outs and labels -------------------------------------------------------------


func test_the_same_seeds_give_the_same_labels() -> void:
	var engine: MatchEngine = _position()
	var candidates: Array[EngineAction] = [_candidate(engine), _pass(POSITION_SEAT)]
	var first: Array[Dictionary] = Rollout.label(
		engine, POSITION_SEAT, candidates, 2, POLICY, LABEL_SEED
	)
	var second: Array[Dictionary] = Rollout.label(
		engine, POSITION_SEAT, candidates, 2, POLICY, LABEL_SEED
	)
	assert_array(second).is_equal(first)
	for entry: Dictionary in first:
		var n: int = entry["n"]
		var wins: int = entry["wins"]
		var draws: int = entry["draws"]
		var losses: int = entry["losses"]
		assert_int(n).is_equal(2)
		assert_int(wins + draws + losses).is_equal(n)
		assert_int(entry["rejected"]).is_equal(0)
		assert_int(entry["spread"]).is_greater_equal(0)


func test_a_play_out_value_follows_the_formula() -> void:
	var engine: MatchEngine = _position()
	var det_seed: int = _det_seed(0, 0)
	var copy: MatchEngine = Rollout.determinize(engine, POSITION_SEAT, det_seed)
	var played: Dictionary = Rollout.play(copy, POSITION_SEAT, _candidate(engine), POLICY, det_seed)
	var wins: Array[int] = _ints(played["wins"])
	var result: int = played["result"]
	var value: int = played["value"]
	assert_array([-1, 0, 1]).contains([result])
	assert_int(value).is_equal(1000 * result + 10 * (wins[1] - wins[0]))
	assert_bool(played["rejected"]).is_false()
	if not played["capped"]:
		assert_bool(copy.is_over()).is_true()
	# Each value is a win, draw or loss plus a tiebreak within ±40 (spec Scenarios).
	assert_int(absi(value - 1000 * result)).is_less_equal(40)


func test_a_concede_is_a_loss_with_the_round_wins_tiebreak() -> void:
	var engine: MatchEngine = _position()
	var wins: Array[int] = _ints(engine.full_state()["wins"])
	var copy: MatchEngine = Rollout.determinize(engine, POSITION_SEAT, 3)
	var played: Dictionary = Rollout.play(
		copy, POSITION_SEAT, EngineAction.concede(POSITION_SEAT), POLICY, 3
	)
	assert_int(played["result"]).is_equal(-1)
	assert_int(played["actions"]).is_equal(1)
	assert_bool(played["capped"]).is_false()
	assert_int(played["value"]).is_equal(-1000 + 10 * (wins[1] - wins[0]))


func test_a_capped_play_out_is_a_draw_with_the_tiebreak() -> void:
	var engine: MatchEngine = _position()
	var copy: MatchEngine = Rollout.determinize(engine, POSITION_SEAT, 4)
	var played: Dictionary = Rollout.play(copy, POSITION_SEAT, _pass(POSITION_SEAT), POLICY, 4, 1)
	var wins: Array[int] = _ints(played["wins"])
	assert_bool(copy.is_over()).is_false()
	assert_bool(played["capped"]).is_true()
	assert_int(played["actions"]).is_equal(1)
	assert_int(played["result"]).is_equal(0)
	assert_int(played["value"]).is_equal(10 * (wins[1] - wins[0]))


func test_an_illegal_candidate_is_rejected_and_not_counted() -> void:
	var engine: MatchEngine = _position()
	var copy: MatchEngine = Rollout.determinize(engine, POSITION_SEAT, 5)
	var wrong_seat: Dictionary = Rollout.play(copy, POSITION_SEAT, _pass(0), POLICY, 5)
	assert_bool(wrong_seat["rejected"]).is_true()
	assert_int(wrong_seat["value"]).is_equal(0)
	assert_int(wrong_seat["actions"]).is_equal(0)
	var unheld: Array[int] = [999]
	var bad: EngineAction = EngineAction.commit(POSITION_SEAT, unheld)
	var refused: Dictionary = Rollout.play(copy, POSITION_SEAT, bad, POLICY, 5)
	assert_bool(refused["rejected"]).is_true()
	assert_int(refused["value"]).is_equal(0)
	var candidates: Array[EngineAction] = [bad]
	var labels: Array[Dictionary] = Rollout.label(
		engine, POSITION_SEAT, candidates, 2, POLICY, LABEL_SEED
	)
	var expected: Dictionary = {
		"mean": 0,
		"spread": 0,
		"n": 0,
		"wins": 0,
		"draws": 0,
		"losses": 0,
		"capped": 0,
		"rejected": 2,
	}
	assert_dict(labels[0]).is_equal(expected)


func test_seed_1_pin() -> void:
	var engine: MatchEngine = _position()
	var det_seed: int = _det_seed(0, 0)
	var copy: MatchEngine = Rollout.determinize(engine, POSITION_SEAT, det_seed)
	var played: Dictionary = Rollout.play(copy, POSITION_SEAT, _candidate(engine), POLICY, det_seed)
	var value: int = played["value"]
	var actions: int = played["actions"]
	var seen: String = "seed-1 pin: value %d actions %d" % [value, actions]
	# The message prints the values seen, for a re-pin after a rules change.
	assert_int(value).override_failure_message(seen).is_equal(PIN_VALUE)
	assert_int(actions).override_failure_message(seen).is_equal(PIN_ACTIONS)


# --- Candidate sampling ---------------------------------------------------------------


func test_sample_indices_draws_k_distinct_ascending_indices() -> void:
	var picked: Array[int] = Rollout.sample_indices(20, 8, LABEL_SEED)
	assert_int(picked.size()).is_equal(8)
	var sorted: Array[int] = []
	sorted.assign(picked)
	sorted.sort()
	assert_array(picked).is_equal(sorted)
	var seen: Dictionary = {}
	for index: int in picked:
		assert_int(index).is_between(0, 19)
		seen[index] = true
	assert_int(seen.size()).is_equal(8)
	assert_array(Rollout.sample_indices(20, 8, LABEL_SEED)).is_equal(picked)
	assert_array(Rollout.sample_indices(5, 8, LABEL_SEED)).is_equal(_typed([0, 1, 2, 3, 4]))
	assert_array(Rollout.sample_indices(0, 8, LABEL_SEED)).is_empty()
	assert_array(Rollout.sample_indices(20, 0, LABEL_SEED)).is_empty()


# --- Reach (R24) ----------------------------------------------------------------------


func test_no_bot_board_or_main_scene_names_the_training_entries() -> void:
	var sources: Array[String] = ["res://main.gd"]
	_collect_sources("res://engine/bot", sources)
	_collect_sources("res://board", sources)
	assert_int(sources.size()).is_greater(1)
	for path: String in sources:
		var text: String = FileAccess.get_file_as_string(path)
		for name: String in ["Rollout", "from_state", "state_copy"]:
			assert_bool(text.contains(name)).override_failure_message(
				"%s names %s" % [path, name]
			).is_false()


## Every .gd file under `dir`, recursively, into `out`.
func _collect_sources(dir: String, out: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		_collect_sources(dir.path_join(sub), out)
