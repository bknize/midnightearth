class_name TestCrewFlow
extends GdUnitTestSuite
## The turn-start pause and the decline in a running match (DC-11 T09; cycle 8 R52-R54,
## plan P9-P11): a Crew prompt opened at turn start leaves phase AWAIT_CHOICE with the walk
## inactive, after the turn's draws and before any commit; commits are rejected meanwhile;
## a choice or a decline resumes the turn start (the remaining Crew, first-committer order)
## and the first committer is awaited as usual. preview_decline() changes nothing and
## returns two scores.
##
## The Crew abilities are T10's, so the prompts come from StubCrew (tests/fixtures), set as
## the engine's TurnStart.fire over the shipped Echo deck on both seats: Shade (slot 0,
## optional) and Quartermaster (slot 2, not optional) are its turn-start Crew.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
## Fixture definition index of c09 (draw 2, then discard 1: a hand prompt on a full hand).
const C09_DRAW_DISCARD: int = 8
const HAND: int = Choice.Zone.OWN_HAND
const REQUESTED: int = MatchEvent.Kind.CHOICE_REQUESTED
const DECLINED: int = MatchEvent.Kind.CHOICE_DECLINED
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const PUBLIC: int = MatchEvent.PUBLIC

# --- Helpers --------------------------------------------------------------------------


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## StubCrew.calls' form: [seat, slot] pairs.
func _calls(values: Array) -> Array[Array]:
	var out: Array[Array] = []
	out.assign(values)
	return out


func _kinds(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		out.append(event.kind)
	return out


func _state_int(engine: MatchEngine, key: String) -> int:
	var value: int = engine.full_state()[key]
	return value


func _phase(engine: MatchEngine) -> int:
	return _state_int(engine, "phase")


func _walk_active(engine: MatchEngine) -> bool:
	var walk: Dictionary = engine.full_state()["walk"]
	var active: bool = walk["active"]
	return active


func _hand(engine: MatchEngine, seat: int) -> Array[int]:
	var hands: Array = engine.full_state()["hand"]
	var raw: Array = hands[seat]
	return _typed(raw)


func _shade_text() -> String:
	return CrewPool.load_default().crew_of("shade").text


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


## Applies an illegal action and checks nothing changed: state, accepted actions, log.
func _assert_rejected(engine: MatchEngine, action: EngineAction, code: int) -> void:
	var before: Dictionary = engine.full_state()
	var count: int = engine.accepted_action_count()
	var logged: String = engine.action_log().to_json()
	var result: ApplyResult = engine.apply(action)
	assert_bool(result.ok).is_false()
	assert_int(result.error).is_equal(code)
	assert_array(result.events).is_empty()
	assert_dict(engine.full_state()).is_equal(before)
	assert_int(engine.accepted_action_count()).is_equal(count)
	assert_str(engine.action_log().to_json()).is_equal(logged)


## `stub`'s engine on `match_seed`, started; the start must succeed.
func _started(stub: StubCrew, match_seed: int) -> MatchEngine:
	var engine: MatchEngine = stub.engine(match_seed)
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	return engine


## The CHOICE_REQUESTED payload of a turn-start Crew prompt over `seat`'s hand of `size`.
func _crew_request(seat: int, crew: CrewDef, size: int, optional: bool) -> Dictionary:
	var options: Array = []
	for index: int in range(size):
		options.append(index)
	return {
		"seat": seat,
		"card": -1,
		"verb": CrewDef.VERB_NAMES[crew.verb],
		"text": crew.text,
		"zone": "own_hand",
		"options": options,
		"multi": false,
		"optional": optional,
		"resume": "turn_start",
		"crew": crew.id,
	}


## The TURN_STARTED event's `first_seat` among `events`, or -1.
func _turn_first_seat(events: Array[MatchEvent]) -> int:
	for event: MatchEvent in events:
		if event.kind == MatchEvent.Kind.TURN_STARTED:
			var first: int = event.payload["first_seat"]
			return first
	return -1


# --- The pause -------------------------------------------------------------------------


## R54, P11: Shade's stub prompt opens after turn 1's draws for the first committer; the
## turn waits in AWAIT_CHOICE with the walk inactive, the prompted seat awaited, the
## prompt optional and resuming the turn start, its card -1 and its Crew named.
func test_a_turn_start_prompt_pauses_the_turn_in_await_choice() -> void:
	var stub: StubCrew = StubCrew.new(1, _typed([StubCrew.SHADE_SLOT]))
	var engine: MatchEngine = stub.engine(SEED)
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	var first: int = _state_int(engine, "first_seat")
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_CHOICE)
	assert_bool(_walk_active(engine)).is_false()
	assert_int(engine.awaited_seat()).is_equal(first)
	assert_int(engine.energy()).is_equal(1)
	# After the turn's draws, before anything else: the request is the last event.
	var kinds: Array[int] = _kinds(started.events)
	var at: int = kinds.find(REQUESTED)
	assert_int(at).is_equal(kinds.size() - 1)
	assert_int(kinds.find(MatchEvent.Kind.TURN_STARTED)).is_less(at)
	assert_int(kinds.rfind(MatchEvent.Kind.CARD_DRAWN)).is_less(at)
	var shade: CrewDef = CrewPool.load_default().crew_of("shade")
	var size: int = _hand(engine, first).size()
	assert_int(size).is_equal(MatchRules.OPENING_HAND + 1)
	_assert_event(started.events[at], REQUESTED, _crew_request(first, shade, size, true), PUBLIC)
	var prompt: Dictionary = engine.open_prompt()
	assert_bool(Choice.is_optional_prompt(prompt)).is_true()
	assert_str(Choice.resume_of(prompt)).is_equal(Choice.RESUME_TURN_START)
	assert_str(Choice.crew_of(prompt)).is_equal("shade")
	var card: int = prompt["card"]
	assert_int(card).is_equal(-1)
	# The cursor stands past the first seat's slot 0; both are in the full state.
	assert_int(_state_int(engine, "turn_start_at")).is_equal(1)
	assert_array(stub.calls).is_equal(_calls([[first, 0]]))
	# The prompted seat's view shows the Crew prompt; the other seat only that one is open.
	var view: SeatView = engine.view_for(first)
	assert_int(view.phase).is_equal(MatchState.Phase.AWAIT_CHOICE)
	assert_bool(view.is_awaited()).is_true()
	var text: String = view.prompt["text"]
	var crew: String = view.prompt["crew"]
	var resume: String = view.prompt["resume"]
	var optional: bool = view.prompt["optional"]
	assert_str(text).is_equal(_shade_text())
	assert_str(crew).is_equal("shade")
	assert_str(resume).is_equal("turn_start")
	assert_bool(optional).is_true()
	assert_dict(engine.view_for(1 - first).prompt).is_equal({"open": true, "seat": first})
	# The pause survives a copy of the state (replay and previews read it).
	var copied: MatchState = engine._state.duplicate()
	assert_dict(copied.to_dict()).is_equal(engine.full_state())


## R54: while the turn start is paused every commit is rejected (WRONG_SEAT), from either
## seat, and nothing changes; previews of a commit give nothing either.
func test_commits_are_rejected_while_the_turn_start_is_paused() -> void:
	var stub: StubCrew = StubCrew.new(1, _typed([StubCrew.SHADE_SLOT]))
	var engine: MatchEngine = _started(stub, SEED)
	var first: int = engine.awaited_seat()
	var wrong: int = EngineError.Code.WRONG_SEAT
	_assert_rejected(engine, EngineAction.commit(first, _typed([])), wrong)
	_assert_rejected(engine, EngineAction.commit(1 - first, _typed([])), wrong)
	var card: int = _hand(engine, first)[0]
	_assert_rejected(engine, EngineAction.commit(first, _typed([card])), wrong)
	assert_array(engine.preview(first, EngineAction.commit(first, _typed([])))).is_empty()
	# The other seat cannot answer or decline the prompt either.
	_assert_rejected(engine, EngineAction.decline(1 - first), wrong)
	_assert_rejected(engine, EngineAction.choose(1 - first, HAND, 0), wrong)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_CHOICE)


## R54, P11: a choice closes the first seat's Crew prompt (CHOICE_MADE, private to it: a
## hand card), the turn start goes on (its Quartermaster, then the other seat's Shade,
## which prompts in turn); that seat's decline closes it (CHOICE_DECLINED, public) and,
## the last Crew fired, the first committer is awaited in AWAIT_FIRST, and may commit.
func test_after_a_choice_and_a_decline_the_first_committer_is_awaited() -> void:
	var stub: StubCrew = StubCrew.new(1, _typed([StubCrew.SHADE_SLOT]))
	var engine: MatchEngine = stub.engine(SEED)
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	var first: int = engine.awaited_seat()
	assert_int(_turn_first_seat(started.events)).is_equal(first)
	var other: int = 1 - first
	var target: int = _hand(engine, first)[1]
	var chosen: ApplyResult = engine.apply(EngineAction.choose(first, HAND, 1))
	assert_bool(chosen.ok).is_true()
	assert_array(_kinds(chosen.events)).is_equal(_typed([MADE, REQUESTED]))
	var made: Dictionary = {
		"seat": first,
		"card": -1,
		"zone": "own_hand",
		"index": 1,
		"target": target,
		"auto": false,
	}
	_assert_event(chosen.events[0], MADE, made, first)
	var shade: CrewDef = CrewPool.load_default().crew_of("shade")
	var size: int = _hand(engine, other).size()
	_assert_event(chosen.events[1], REQUESTED, _crew_request(other, shade, size, true), PUBLIC)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_CHOICE)
	assert_int(engine.awaited_seat()).is_equal(other)
	assert_bool(_walk_active(engine)).is_false()
	assert_array(stub.calls).is_equal(_calls([[first, 0], [first, 2], [other, 0]]))
	var declined: ApplyResult = engine.apply(EngineAction.decline(other))
	assert_bool(declined.ok).is_true()
	var payload: Dictionary = {"seat": other, "card": -1, "crew": "shade"}
	assert_int(declined.events.size()).is_equal(1)
	_assert_event(declined.events[0], DECLINED, payload, PUBLIC)
	var all_calls: Array[Array] = _calls([[first, 0], [first, 2], [other, 0], [other, 2]])
	assert_array(stub.calls).is_equal(all_calls)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_int(engine.awaited_seat()).is_equal(first)
	assert_int(_state_int(engine, "turn_start_at")).is_equal(TurnStart.DONE)
	assert_dict(engine.open_prompt()).is_empty()
	assert_int(engine.accepted_action_count()).is_equal(2)
	assert_bool(engine.apply(EngineAction.commit(first, _typed([]))).ok).is_true()
	assert_int(engine.awaited_seat()).is_equal(other)


## R52, P11: declining the first seat's Crew prompt with the other seat's Crew silent
## resumes the turn start to its end: AWAIT_FIRST, the first committer awaited.
func test_a_decline_resumes_the_turn_start_and_awaits_the_first_committer() -> void:
	for match_seed: int in [SEED, 2, 3]:
		var stub: StubCrew = StubCrew.new(1, _typed([StubCrew.SHADE_SLOT]))
		var engine: MatchEngine = _started(stub, match_seed)
		var first: int = engine.awaited_seat()
		assert_bool(engine.apply(EngineAction.decline(first)).ok).is_true()
		assert_bool(engine.apply(EngineAction.decline(1 - first)).ok).is_true()
		assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_FIRST)
		assert_int(engine.awaited_seat()).is_equal(first)
		assert_int(_state_int(engine, "first_seat")).is_equal(first)
		# Nothing applied: both hands are as dealt and drawn.
		assert_int(_hand(engine, first).size()).is_equal(MatchRules.OPENING_HAND + 1)
		assert_int(_hand(engine, 1 - first).size()).is_equal(MatchRules.OPENING_HAND + 1)


## R53: Quartermaster's stub prompt is not optional: a decline is NOT_OPTIONAL and changes
## nothing; a choice resumes the turn start as with an optional one.
func test_a_crew_prompt_that_is_not_optional_rejects_the_decline() -> void:
	var stub: StubCrew = StubCrew.new(1, _typed([StubCrew.QUARTERMASTER_SLOT]))
	var engine: MatchEngine = _started(stub, SEED)
	var first: int = engine.awaited_seat()
	var prompt: Dictionary = engine.open_prompt()
	assert_str(Choice.crew_of(prompt)).is_equal("quartermaster")
	assert_bool(Choice.is_optional_prompt(prompt)).is_false()
	_assert_rejected(engine, EngineAction.decline(first), EngineError.Code.NOT_OPTIONAL)
	assert_array(engine.preview_decline(first)).is_empty()
	assert_bool(engine.apply(EngineAction.choose(first, HAND, 0)).ok).is_true()
	assert_int(engine.awaited_seat()).is_equal(1 - first)
	assert_bool(engine.apply(EngineAction.choose(1 - first, HAND, 0)).ok).is_true()
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_int(engine.awaited_seat()).is_equal(first)


## P11: a Crew prompt on a later turn opens when the previous turn's walk has ended and the
## new turn has drawn; after the answers the turn's first committer (TURN_STARTED's) is
## awaited.
func test_a_turn_start_prompt_on_a_later_turn_follows_the_turn_end() -> void:
	var stub: StubCrew = StubCrew.new(2, _typed([StubCrew.SHADE_SLOT]))
	var engine: MatchEngine = _started(stub, SEED)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_bool(engine.apply(EngineAction.commit(engine.awaited_seat(), _typed([]))).ok).is_true()
	var second: ApplyResult = engine.apply(EngineAction.commit(engine.awaited_seat(), _typed([])))
	assert_bool(second.ok).is_true()
	var kinds: Array[int] = _kinds(second.events)
	assert_int(kinds.find(MatchEvent.Kind.TURN_ENDED)).is_less(kinds.find(REQUESTED))
	assert_int(kinds.find(MatchEvent.Kind.TURN_STARTED)).is_less(kinds.find(REQUESTED))
	var first: int = _turn_first_seat(second.events)
	assert_int(engine.energy()).is_equal(2)
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_CHOICE)
	assert_int(engine.awaited_seat()).is_equal(first)
	assert_bool(engine.apply(EngineAction.decline(first)).ok).is_true()
	assert_bool(engine.apply(EngineAction.choose(1 - first, HAND, 0)).ok).is_true()
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_int(engine.awaited_seat()).is_equal(first)


## A concede while the turn start is paused ends the match and closes the prompt.
func test_a_concede_during_the_pause_ends_the_match() -> void:
	var stub: StubCrew = StubCrew.new(1, _typed([StubCrew.SHADE_SLOT]))
	var engine: MatchEngine = _started(stub, SEED)
	var first: int = engine.awaited_seat()
	assert_bool(engine.apply(EngineAction.concede(1 - first)).ok).is_true()
	assert_bool(engine.is_over()).is_true()
	assert_dict(engine.open_prompt()).is_empty()
	_assert_rejected(engine, EngineAction.decline(first), EngineError.Code.MATCH_OVER)


## With the shipped Crew (no stub; DC-11 T10) Echo's turn 1 fires only Quartermaster, which
## needs no choice, so the turn start does not pause.
func test_without_a_firing_the_turn_start_awaits_the_first_committer() -> void:
	var engine: MatchEngine = MatchEngine.create(
		SEED,
		CardDb.load_default(),
		DeckList.load_default(),
		StubCrew.ids(),
		CrewPool.load_default()
	)
	assert_bool(engine.start().ok).is_true()
	assert_int(_phase(engine)).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_dict(engine.open_prompt()).is_empty()
	assert_int(_state_int(engine, "turn_start_at")).is_equal(TurnStart.DONE)


# --- preview_decline (cycle 8 R56, P15) ------------------------------------------------


## A fixture match paused on c09's discard prompt (as test_choices.gd finds it), marked
## optional on the live state since no card prompt is optional before the Crew; null when
## no seed in the range deals the first committer its c09 by turn 3.
func _optional_walk_prompt_engine() -> MatchEngine:
	var db: CardDb = FixtureDecks.cards()
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = FixtureDecks.engine(match_seed, db)
		engine.start()
		while engine.energy() < 3:
			if not engine.apply(EngineAction.commit(engine.awaited_seat(), _typed([]))).ok:
				break
		var first: int = engine.awaited_seat()
		var c09: int = first * MatchRules.DECK_SIZE + C09_DRAW_DISCARD
		if engine.energy() != 3 or not _hand(engine, first).has(c09):
			continue
		if not engine.apply(EngineAction.commit(first, _typed([c09]))).ok:
			continue
		if not engine.apply(EngineAction.commit(1 - first, _typed([]))).ok:
			continue
		if engine.open_prompt().is_empty():
			continue
		engine._state.prompt[Choice.KEY_OPTIONAL] = true
		return engine
	return null


## R56, P15: preview_decline() on an optional walk prompt changes no state, accepted
## action or log and returns two scores: the scores the live decline's walk ends on (the
## opponent's row is empty, so nothing is hidden). Nothing for the other seat, and nothing
## on a turn-start prompt, where no walk is paused.
func test_preview_decline_changes_no_state_and_returns_two_scores() -> void:
	var engine: MatchEngine = _optional_walk_prompt_engine()
	assert_object(engine).override_failure_message("no seed gives c09 by turn 3").is_not_null()
	if engine == null:
		return
	var asked: int = engine.awaited_seat()
	var before: Dictionary = engine.full_state()
	var count: int = engine.accepted_action_count()
	var logged: String = engine.action_log().to_json()
	var scores: Array[int] = engine.preview_decline(asked)
	assert_int(scores.size()).is_equal(2)
	assert_array(engine.preview_decline(1 - asked)).is_empty()
	assert_dict(engine.full_state()).is_equal(before)
	assert_int(engine.accepted_action_count()).is_equal(count)
	assert_str(engine.action_log().to_json()).is_equal(logged)
	# Twice the same.
	assert_array(engine.preview_decline(asked)).is_equal(scores)
	var live: ApplyResult = engine.apply(EngineAction.decline(asked))
	assert_bool(live.ok).is_true()
	var ended: Array = []
	for event: MatchEvent in live.events:
		if event.kind == MatchEvent.Kind.TURN_ENDED:
			ended = event.payload["scores"]
	assert_array(ended).is_equal(MatchState.plain(scores))
	# A turn-start Crew prompt has no walk to preview.
	var stub: StubCrew = StubCrew.new(1, _typed([StubCrew.SHADE_SLOT]))
	var paused: MatchEngine = _started(stub, SEED)
	var first: int = paused.awaited_seat()
	assert_bool(Choice.is_optional_prompt(paused.open_prompt())).is_true()
	var still: Dictionary = paused.full_state()
	assert_array(paused.preview_decline(first)).is_empty()
	assert_dict(paused.full_state()).is_equal(still)
