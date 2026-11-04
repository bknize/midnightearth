class_name TestBoardSteps
extends GdUnitTestSuite
## BoardSteps (R31-R38): seat-0 events become animation steps. The events come from a real
## seed-1 bot-vs-bot match, played as main.gd plays its smoke run, collecting
## result.events_for(0) after start() and after every accepted action.

const SEED: int = 1
const MAX_ACTIONS: int = 2000
const EPSILON: float = 0.0001

var _cached_events: Array[MatchEvent] = []

# --- Helpers --------------------------------------------------------------------------


## Seat 0's redacted events for the whole of seed 1, in the order the engine emitted them.
func _match_events() -> Array[MatchEvent]:
	if not _cached_events.is_empty():
		return _cached_events
	var cards: CardDb = CardDb.load_default()
	var engine: MatchEngine = MatchEngine.create(SEED, cards)
	var collected: Array[MatchEvent] = []
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	collected.append_array(started.events_for(0))
	var bots: Array[GreedyBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(GreedyBot.new(GreedyBot.seed_for(SEED, seat), cards))
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
	assert_bool(engine.is_over()).is_true()
	_cached_events = collected
	return _cached_events


func _steps(speed: float) -> Array[BoardStep]:
	return BoardSteps.from_events(_match_events(), speed)


func _count_kind(steps: Array[BoardStep], kind: int) -> int:
	var total: int = 0
	for step: BoardStep in steps:
		if step.kind == kind:
			total += 1
	return total


## PULSE steps that flip their card (first reveals).
func _count_flips(steps: Array[BoardStep]) -> int:
	var total: int = 0
	for step: BoardStep in steps:
		if step.kind == BoardStep.Kind.PULSE and not step.revealed:
			total += 1
	return total


func _count_events(events: Array[MatchEvent], kind: int) -> int:
	var total: int = 0
	for event: MatchEvent in events:
		if event.kind == kind:
			total += 1
	return total


func _event(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> MatchEvent:
	return MatchEvent.new(kind, payload, owner)


# --- Order ----------------------------------------------------------------------------


func test_step_order_follows_event_order() -> void:
	var events: Array[MatchEvent] = _match_events()
	var positions: Dictionary = {}
	for i: int in range(events.size()):
		positions[events[i].get_instance_id()] = i
	var steps: Array[BoardStep] = _steps(1.0)
	assert_bool(steps.is_empty()).is_false()
	var last: int = -1
	for step: BoardStep in steps:
		assert_object(step.source).is_not_null()
		var at: int = positions.get(step.source.get_instance_id(), -2)
		assert_int(at).is_greater_equal(0)
		assert_int(at).is_greater_equal(last)
		last = at
	# The first beat is a deal: round 1 has no clear. Every event but CONCEDED has a step.
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.DEAL)
	assert_int(steps[steps.size() - 1].kind).is_equal(BoardStep.Kind.MATCH_END)
	assert_int(_count_kind(steps, BoardStep.Kind.TURN_START)).is_equal(
		_count_events(events, MatchEvent.Kind.TURN_STARTED)
	)
	assert_int(_count_flips(steps)).is_equal(_count_events(events, MatchEvent.Kind.CARD_REVEALED))
	assert_int(_count_kind(steps, BoardStep.Kind.ROUND_END)).is_equal(
		_count_events(events, MatchEvent.Kind.ROUND_ENDED)
	)


func test_the_opponent_hand_is_hidden_in_deal_steps() -> void:
	var own_seen: int = 0
	var hidden_seen: int = 0
	for step: BoardStep in _steps(1.0):
		if step.kind != BoardStep.Kind.DEAL and step.kind != BoardStep.Kind.DRAW:
			continue
		if step.seat == 0:
			own_seen += 1
			assert_int(step.card).is_greater_equal(0)
			assert_int(step.def_index).is_equal(step.card % MatchRules.DECK_SIZE)
		else:
			hidden_seen += 1
			assert_int(step.card).is_equal(-1)
			assert_int(step.def_index).is_equal(-1)
	assert_int(own_seen).is_greater(0)
	assert_int(hidden_seen).is_greater(0)


# --- Reveals and scores ---------------------------------------------------------------


func test_reveal_steps_carry_engine_order_and_flat() -> void:
	var cards: CardDb = CardDb.load_default()
	var reveals: int = 0
	var next_order: int = 0
	for step: BoardStep in _steps(1.0):
		if step.kind == BoardStep.Kind.TURN_START:
			next_order = 0
		if step.kind != BoardStep.Kind.PULSE or step.revealed:
			continue
		reveals += 1
		var payload: Dictionary = step.source.payload
		var order: int = payload["order"]
		var flat: int = payload["flat"]
		assert_int(step.order).is_equal(order)
		assert_int(step.order).is_equal(next_order)
		assert_int(step.flat).is_equal(flat)
		assert_int(step.card).is_greater_equal(0)
		assert_int(step.def_index).is_equal(step.card % MatchRules.DECK_SIZE)
		var def: CardDef = cards.card_at(step.def_index)
		assert_object(def).is_not_null()
		assert_int(def.flat).is_equal(step.flat)
		next_order += 1
	assert_int(reveals).is_greater(0)


## Since DC-05 T03 a turn's scores are its walk's totals: each seat's last CARD_SCORED
## score after the turn's WALK_STARTED (0 for a seat with no card), and every TURN_END step
## carries them.
func test_turn_end_scores_are_the_walk_totals() -> void:
	var walk_totals: Array[int] = [0, 0]
	var turn_ends: int = 0
	for event: MatchEvent in _match_events():
		if event.kind == MatchEvent.Kind.WALK_STARTED:
			walk_totals = [0, 0]
		elif event.kind == MatchEvent.Kind.CARD_SCORED:
			var seat: int = event.payload["seat"]
			var score: int = event.payload["score"]
			walk_totals[seat] = score
		elif event.kind == MatchEvent.Kind.TURN_ENDED:
			turn_ends += 1
			var raw: Array = event.payload["scores"]
			var ended: Array[int] = []
			ended.assign(raw)
			assert_array(ended).is_equal(walk_totals)
	assert_int(turn_ends).is_greater(0)
	var steps_seen: int = 0
	for step: BoardStep in _steps(1.0):
		if step.kind != BoardStep.Kind.TURN_END:
			continue
		steps_seen += 1
		var source_scores: Array = step.source.payload["scores"]
		assert_int(step.scores.size()).is_equal(2)
		for seat: int in range(2):
			var expected: int = source_scores[seat]
			assert_int(step.scores[seat]).is_equal(expected)
	assert_int(steps_seen).is_equal(turn_ends)


# --- Burns ----------------------------------------------------------------------------


func test_burn_steps_go_entry_to_exit() -> void:
	# Seed 1 may never burn, so the synthetic events always run; a real burn is checked too.
	var own: MatchEvent = _event(MatchEvent.Kind.CARD_BURNED, {"seat": 0, "card": 5}, 0)
	var theirs: MatchEvent = _event(MatchEvent.Kind.CARD_BURNED, {"seat": 1, "card": 25}, 1)
	var events: Array[MatchEvent] = [own.redacted_for(0), theirs.redacted_for(0)]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0)
	assert_int(steps.size()).is_equal(2)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.BURN)
	assert_int(steps[0].seat).is_equal(0)
	assert_int(steps[0].card).is_equal(5)
	assert_int(steps[0].def_index).is_equal(5)
	assert_float(steps[0].duration).is_equal_approx(0.45, EPSILON)
	assert_int(steps[1].kind).is_equal(BoardStep.Kind.BURN)
	assert_int(steps[1].seat).is_equal(1)
	assert_int(steps[1].card).is_equal(-1)
	assert_int(steps[1].def_index).is_equal(-1)
	for step: BoardStep in _steps(1.0):
		if step.kind == BoardStep.Kind.BURN:
			assert_float(step.duration).is_equal_approx(0.45, EPSILON)
			assert_float(step.delay).is_equal_approx(0.0, EPSILON)


# --- Rounds ---------------------------------------------------------------------------


func test_the_round_sweep_precedes_the_deal_of_rounds_after_the_first() -> void:
	var events: Array[MatchEvent] = _match_events()
	var steps: Array[BoardStep] = _steps(1.0)
	var rounds: int = _count_events(events, MatchEvent.Kind.ROUND_STARTED)
	assert_int(rounds).is_greater(1)
	assert_int(_count_kind(steps, BoardStep.Kind.CLEAR_TABLE)).is_equal(rounds - 1)
	for i: int in range(steps.size()):
		var step: BoardStep = steps[i]
		if step.kind != BoardStep.Kind.CLEAR_TABLE:
			continue
		assert_int(i).is_greater(0)
		assert_int(steps[i - 1].kind).is_equal(BoardStep.Kind.ROUND_END)
		assert_int(steps[i + 1].kind).is_equal(BoardStep.Kind.DEAL)
		assert_float(step.duration).is_equal_approx(0.40, EPSILON)
		assert_float(step.delay).is_equal_approx(0.0, EPSILON)
		# Deals of the new round: the first has no stagger, the rest wait 0.12 s.
		assert_float(steps[i + 1].delay).is_equal_approx(0.0, EPSILON)
		assert_float(steps[i + 2].delay).is_equal_approx(0.12, EPSILON)


func test_round_end_and_match_end_carry_the_tally() -> void:
	var last_wins: Array[int] = []
	var round_ends: int = 0
	var match_end: BoardStep = null
	for step: BoardStep in _steps(1.0):
		if step.kind == BoardStep.Kind.ROUND_END:
			round_ends += 1
			assert_int(step.wins.size()).is_equal(2)
			assert_float(step.duration).is_equal_approx(0.30, EPSILON)
			last_wins = step.wins
		elif step.kind == BoardStep.Kind.MATCH_END:
			match_end = step
	assert_int(round_ends).is_greater(0)
	assert_object(match_end).is_not_null()
	assert_float(match_end.duration).is_equal_approx(0.0, EPSILON)
	var payload: Dictionary = match_end.source.payload
	var winner: int = payload["winner"]
	assert_int(match_end.seat).is_equal(winner)
	assert_array(match_end.wins).is_equal(last_wins)


# --- Commits --------------------------------------------------------------------------


func test_an_opponent_commit_yields_the_bot_wait() -> void:
	var steps: Array[BoardStep] = _steps(1.0)
	var waits: int = 0
	var slides: int = 0
	var own: int = 0
	for i: int in range(steps.size()):
		var step: BoardStep = steps[i]
		if step.kind == BoardStep.Kind.BOT_WAIT:
			waits += 1
			assert_float(step.duration).is_equal_approx(0.6, EPSILON)
			assert_int(step.seat).is_equal(1)
			var slide: BoardStep = steps[i + 1]
			assert_int(slide.kind).is_equal(BoardStep.Kind.OPPONENT_COMMIT)
			var count: int = slide.source.payload["count"]
			assert_int(slide.count).is_equal(count)
			assert_float(slide.duration).is_equal_approx(0.25 * float(count), EPSILON)
		elif step.kind == BoardStep.Kind.OPPONENT_COMMIT:
			slides += 1
			assert_int(steps[i - 1].kind).is_equal(BoardStep.Kind.BOT_WAIT)
		elif step.kind == BoardStep.Kind.PLAYER_COMMIT:
			own += 1
			assert_int(step.seat).is_equal(0)
			assert_float(step.duration).is_equal_approx(0.30, EPSILON)
	assert_int(waits).is_greater(0)
	assert_int(slides).is_equal(waits)
	assert_int(own).is_greater(0)
	assert_int(waits + own).is_equal(_count_events(_match_events(), MatchEvent.Kind.COMMITTED))


func test_a_concede_has_no_step_of_its_own() -> void:
	var events: Array[MatchEvent] = [
		_event(MatchEvent.Kind.CONCEDED, {"seat": 1}),
		_event(
			MatchEvent.Kind.MATCH_ENDED,
			{"winner": 0, "reason": "concede", "wins": [0, 0], "rounds_played": 0}
		),
	]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0)
	assert_int(steps.size()).is_equal(1)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.MATCH_END)
	assert_int(steps[0].seat).is_equal(0)


# --- Speed ----------------------------------------------------------------------------


func test_every_duration_at_speed_four_is_a_quarter() -> void:
	var slow: Array[BoardStep] = _steps(1.0)
	var fast: Array[BoardStep] = _steps(4.0)
	assert_int(fast.size()).is_equal(slow.size())
	var timed: int = 0
	for i: int in range(slow.size()):
		assert_int(fast[i].kind).is_equal(slow[i].kind)
		assert_float(fast[i].duration).is_equal_approx(slow[i].duration / 4.0, EPSILON)
		assert_float(fast[i].delay).is_equal_approx(slow[i].delay / 4.0, EPSILON)
		if slow[i].duration > 0.0:
			timed += 1
	assert_int(timed).is_greater(0)


# --- Walk and effect steps (P17, P18) ---------------------------------------------------


func _reveal_event(card: int, seat: int = 0) -> MatchEvent:
	return _event(
		MatchEvent.Kind.CARD_REVEALED,
		{"seat": seat, "card": card, "def_id": "c01", "slot": 1, "flat": 2, "bonus": 1, "order": 0}
	)


func _scored_event(card: int, seat: int = 0) -> MatchEvent:
	return _event(
		MatchEvent.Kind.CARD_SCORED,
		{
			"seat": seat,
			"card": card,
			"slot": 1,
			"flat": 2,
			"bonus": 1,
			"mult": 3,
			"added": 9,
			"score": 12,
		}
	)


func _one(event: MatchEvent, speed: float = 1.0, viewer: int = 0) -> BoardStep:
	var events: Array[MatchEvent] = [event]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, speed, viewer)
	assert_int(steps.size()).is_equal(1)
	return steps[0]


func test_walk_started_yields_walk_start() -> void:
	var step: BoardStep = _one(
		_event(MatchEvent.Kind.WALK_STARTED, {"round": 1, "turn": 2, "first_seat": 0})
	)
	assert_int(step.kind).is_equal(BoardStep.Kind.WALK_START)
	assert_float(step.duration).is_equal_approx(0.0, EPSILON)


func test_reveal_then_score_is_one_flip_pulse() -> void:
	var events: Array[MatchEvent] = [_reveal_event(4), _scored_event(4)]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 2.0)
	assert_int(steps.size()).is_equal(1)
	var pulse: BoardStep = steps[0]
	assert_int(pulse.kind).is_equal(BoardStep.Kind.PULSE)
	assert_bool(pulse.revealed).is_false()
	assert_float(pulse.duration).is_equal_approx(0.35 / 2.0, EPSILON)
	assert_float(pulse.delay).is_equal_approx(0.15 / 2.0, EPSILON)
	assert_int(pulse.seat).is_equal(0)
	assert_int(pulse.card).is_equal(4)
	assert_int(pulse.slot).is_equal(1)
	assert_int(pulse.flat).is_equal(2)
	assert_int(pulse.bonus).is_equal(1)
	assert_int(pulse.mult).is_equal(3)
	assert_int(pulse.added).is_equal(9)
	assert_int(pulse.score).is_equal(12)


func test_a_flip_pulse_keeps_its_place_before_effects_between_reveal_and_score() -> void:
	var fired: MatchEvent = _event(
		MatchEvent.Kind.EFFECT_FIRED, {"seat": 0, "card": 4, "verb": "draw", "trigger": "on_reveal"}
	)
	var events: Array[MatchEvent] = [_reveal_event(4), fired, _scored_event(4)]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0)
	assert_int(steps.size()).is_equal(2)
	assert_int(steps[0].kind).is_equal(BoardStep.Kind.PULSE)
	assert_int(steps[0].score).is_equal(12)
	assert_int(steps[1].kind).is_equal(BoardStep.Kind.EFFECT)


func test_a_score_with_no_reveal_is_a_revealed_pulse() -> void:
	var step: BoardStep = _one(_scored_event(4), 4.0)
	assert_int(step.kind).is_equal(BoardStep.Kind.PULSE)
	assert_bool(step.revealed).is_true()
	assert_float(step.duration).is_equal_approx(0.12 / 4.0, EPSILON)
	assert_float(step.delay).is_equal_approx(0.0, EPSILON)
	assert_int(step.added).is_equal(9)
	assert_int(step.mult).is_equal(3)


func test_effect_event_steps_and_durations() -> void:
	var cases: Array = [
		[
			MatchEvent.Kind.EFFECT_FIRED,
			{"seat": 0, "card": 3, "verb": "draw", "trigger": "on_reveal"},
			BoardStep.Kind.EFFECT,
			0.25,
		],
		[
			MatchEvent.Kind.EFFECT_FIZZLED,
			{"seat": 0, "card": 3, "verb": "destroy_random_opponent"},
			BoardStep.Kind.FIZZLE,
			0.15,
		],
		[
			MatchEvent.Kind.CHOICE_MADE,
			{"seat": 1, "card": 3, "zone": "board", "index": 0, "target": 7, "auto": false},
			BoardStep.Kind.CHOICE_SHOW,
			0.4,
		],
		[
			MatchEvent.Kind.STATS_CHANGED,
			{"seat": 0, "card": 3, "flat": 1, "bonus": 2, "cause": "switch"},
			BoardStep.Kind.STATS,
			0.2,
		],
		[
			MatchEvent.Kind.CARD_DESTROYED,
			{"seat": 1, "card": 25, "slot": 0},
			BoardStep.Kind.DESTROY,
			0.45,
		],
		[
			MatchEvent.Kind.CARD_MOVED,
			{"seat": 0, "card": 3, "from_slot": 0, "to_slot": 2},
			BoardStep.Kind.MOVE,
			0.3,
		],
		[
			MatchEvent.Kind.CARD_RETURNED,
			{"seat": 0, "card": 3, "slot": 1},
			BoardStep.Kind.RETURN,
			0.3,
		],
		[
			MatchEvent.Kind.CARD_DISCARDED,
			{"seat": 1, "card": -1},
			BoardStep.Kind.DISCARD,
			0.45,
		],
	]
	for entry: Array in cases:
		var kind: int = entry[0]
		var payload: Dictionary = entry[1]
		var want_kind: int = entry[2]
		var seconds: float = entry[3]
		var step: BoardStep = _one(_event(kind, payload), 2.0)
		assert_int(step.kind).is_equal(want_kind)
		assert_float(step.duration).is_equal_approx(seconds / 2.0, EPSILON)


func test_move_and_destroy_carry_their_slots() -> void:
	var moved: BoardStep = _one(
		_event(MatchEvent.Kind.CARD_MOVED, {"seat": 0, "card": 3, "from_slot": 0, "to_slot": 2})
	)
	assert_int(moved.from_slot).is_equal(0)
	assert_int(moved.slot).is_equal(2)
	var destroyed: BoardStep = _one(
		_event(MatchEvent.Kind.CARD_DESTROYED, {"seat": 1, "card": 25, "slot": 3})
	)
	assert_int(destroyed.slot).is_equal(3)


func test_prompt_is_untimed_and_only_for_the_viewer() -> void:
	var asked: Dictionary = {
		"seat": 0,
		"card": 8,
		"verb": "switch_stats",
		"text": "Pick",
		"zone": "board",
		"options": [1, 2],
	}
	var own: BoardStep = _one(_event(MatchEvent.Kind.CHOICE_REQUESTED, asked), 4.0)
	assert_int(own.kind).is_equal(BoardStep.Kind.PROMPT)
	assert_float(own.duration).is_equal_approx(0.0, EPSILON)
	assert_array(own.options).is_equal([1, 2])
	var other: Dictionary = asked.duplicate()
	other["seat"] = 1
	var events: Array[MatchEvent] = [_event(MatchEvent.Kind.CHOICE_REQUESTED, other)]
	assert_array(BoardSteps.from_events(events, 1.0, 0)).is_empty()


func test_bookkeeping_events_have_no_step() -> void:
	var events: Array[MatchEvent] = [
		_event(MatchEvent.Kind.BONUS_ZERO_SET, {"seat": 1}),
		_event(MatchEvent.Kind.ENERGY_CARRIED, {"seat": 0, "amount": 2}),
		_event(MatchEvent.Kind.FREE_FIRST_SET, {"seat": 0}),
	]
	assert_array(BoardSteps.from_events(events, 1.0)).is_empty()


func test_commits_carry_slots_and_the_player_commit_takes_time() -> void:
	var own: BoardStep = _one(
		_event(
			MatchEvent.Kind.COMMITTED, {"seat": 0, "count": 2, "cards": [1, 2], "slots": [0, 2]}
		),
		2.0
	)
	assert_int(own.kind).is_equal(BoardStep.Kind.PLAYER_COMMIT)
	assert_array(own.slots).is_equal([0, 2])
	assert_float(own.duration).is_equal_approx(0.30 / 2.0, EPSILON)
	var events: Array[MatchEvent] = [
		_event(MatchEvent.Kind.COMMITTED, {"seat": 1, "count": 1, "cards": [-1], "slots": [1]})
	]
	var steps: Array[BoardStep] = BoardSteps.from_events(events, 1.0)
	assert_int(steps[1].kind).is_equal(BoardStep.Kind.OPPONENT_COMMIT)
	assert_array(steps[1].slots).is_equal([1])


func test_turn_start_carries_the_viewers_budget_and_free_first() -> void:
	var step: BoardStep = _one(
		_event(
			MatchEvent.Kind.TURN_STARTED,
			{
				"round": 1,
				"turn": 3,
				"energy": 3,
				"budgets": [5, 3],
				"free_first": [true, false],
				"first_seat": 0,
			}
		)
	)
	assert_int(step.energy).is_equal(3)
	assert_int(step.budget).is_equal(5)
	assert_bool(step.free_first).is_true()
