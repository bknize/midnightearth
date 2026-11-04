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
		var result: ApplyResult = engine.apply(bots[awaited].choose(engine.view_for(awaited)))
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
	assert_int(_count_kind(steps, BoardStep.Kind.REVEAL)).is_equal(
		_count_events(events, MatchEvent.Kind.CARD_REVEALED)
	)
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
		if step.kind != BoardStep.Kind.REVEAL:
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
			assert_float(step.duration).is_equal_approx(0.0, EPSILON)
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
