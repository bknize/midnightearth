class_name TestCrewEffects
extends GdUnitTestSuite
## The Crew triggers and the eight Crew abilities (DC-11 T10; cycle 8 R45-R51, plan P13,
## P14): the trigger queue drains only once the causing effect has resolved (R46), each
## Crew of the plan's table, a Crew with no eligible target, and replay of a match paused
## on a Crew prompt with its queue (and of a decline on one).
##
## Most cases build a match over the DC-05 fixture pool (or the fixture pool plus the Ruin
## table) with two in-memory decks "a" (seat 0) and "b" (seat 1) holding the same cards and
## the Crew each case needs, from the shipped Crew pool with its Crew firing
## (FixtureDecks.live_crew()). Tables are set by hand (_table), as test_effects_ruin.gd does.
## Instance id = seat * 20 + the card's index in the deck list. The replay case plays the
## shipped Ruin deck on both seats from commits alone, so its log replays.

const SEED: int = 1
const REPLAY_SEEDS: int = 12
const MAX_ACTIONS: int = 120
const MAX_STEPS: int = 200

# Fixture cards (index = instance index on seat 0), all vanilla.
const C02: int = 1  # flat 2
const C03: int = 2  # flat 1, ×1.25
const C04: int = 3  # flat 3
const C07: int = 6  # flat 2, ×1.25
const C08: int = 7  # flat 4
# Ruin cards (FixtureDecks.ruin_card_ids order).
const R01_SCRAP: int = FixtureDecks.R01_SCRAP  # flat 2
const R02_TINDER: int = FixtureDecks.R02_TINDER
const R04_SHARD: int = FixtureDecks.R04_SHARD
const R09_WICK: int = FixtureDecks.R09_WICK
const R16_IMMOLATOR: int = FixtureDecks.R16_IMMOLATOR
const R18_REAPER: int = FixtureDecks.R18_REAPER

const PUBLIC: int = MatchEvent.PUBLIC
const OWN_HAND: int = Choice.Zone.OWN_HAND
const OWN_BOARD: int = Choice.Zone.OWN_BOARD
const CREW_FIRED: int = MatchEvent.Kind.CREW_FIRED
const REQUESTED: int = MatchEvent.Kind.CHOICE_REQUESTED
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const DECLINED: int = MatchEvent.Kind.CHOICE_DECLINED
const DESTROYED: int = MatchEvent.Kind.CARD_DESTROYED
const CLEARED: int = MatchEvent.Kind.DESTROYED_CLEARED
const UNREVEALED: int = MatchEvent.Kind.CARD_UNREVEALED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const BURNED: int = MatchEvent.Kind.CARD_BURNED
const DISCARDED: int = MatchEvent.Kind.CARD_DISCARDED
const STATS: int = MatchEvent.Kind.STATS_CHANGED
const MOVED: int = MatchEvent.Kind.CARD_MOVED
const TURN_ENDED: int = MatchEvent.Kind.TURN_ENDED
const ROUND_ENDED: int = MatchEvent.Kind.ROUND_ENDED

# --- Helpers --------------------------------------------------------------------------


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


## The fixture card ids c01..c20, in order.
func _fixture_ids() -> Array:
	var out: Array = []
	for index: int in range(MatchRules.DECK_SIZE):
		out.append("c%02d" % (index + 1))
	return out


func _deck(deck_id: String, card_ids: Array, crew: Array) -> Dictionary:
	return {"id": deck_id, "name": deck_id, "theme": "", "cards": card_ids, "crew": crew}


## A match on `match_seed` over `pool`: seat 0 plays deck "a" (`card_ids`, Crew `crew_a`),
## seat 1 deck "b" (the same cards, Crew `crew_b`), the Crew firing; started.
func _engine(pool: CardDb, card_ids: Array, crew_a: Array, crew_b: Array) -> MatchEngine:
	var root: Dictionary = {
		"version": DeckList.FORMAT_VERSION,
		"decks": [_deck("a", card_ids, crew_a), _deck("b", card_ids, crew_b)],
	}
	var decks: DeckList = DeckList.from_json(JSON.stringify(root))
	var ids: Array[String] = ["a", "b"]
	var engine: MatchEngine = MatchEngine.create(SEED, pool, decks, ids, FixtureDecks.live_crew())
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).override_failure_message("start failed").is_true()
	return engine


func _fixture_engine(crew_a: Array, crew_b: Array) -> MatchEngine:
	return _engine(FixtureDecks.cards(), _fixture_ids(), crew_a, crew_b)


func _ruin_engine(crew_a: Array, crew_b: Array) -> MatchEngine:
	return _engine(FixtureDecks.ruin_cards(), FixtureDecks.ruin_card_ids(), crew_a, crew_b)


## Sets both rows of `engine` by hand (`own` seat 0's, `theirs` seat 1's; instance ids, face
## down), taking each card out of its seat's deck, hand and burn pile, then both seats
## pass. The second pass's result: the walk to its end or to its first prompt.
func _table(engine: MatchEngine, own: Array[int], theirs: Array[int]) -> ApplyResult:
	for seat: int in range(MatchEngine.SEATS):
		var row: Array[int] = own if seat == 0 else theirs
		var piles: MatchState.SeatPiles = engine._state.seats[seat]
		for card: int in row:
			piles.deck.erase(card)
			piles.hand.erase(card)
			piles.burned.erase(card)
		piles.board.assign(row)
		piles.revealed.clear()
	var first: ApplyResult = engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))
	assert_bool(first.ok).override_failure_message("first pass rejected").is_true()
	return engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))


## One action for whoever is awaited: a pass, or for an open prompt the empty set (a
## multi-select), the decline (an optional prompt) or the first option.
func _step(engine: MatchEngine) -> ApplyResult:
	var prompt: Dictionary = engine.open_prompt()
	if prompt.is_empty():
		return engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))
	var seat: int = prompt["seat"]
	var zone: int = prompt["zone"]
	if Choice.is_multi_prompt(prompt):
		return engine.apply(EngineAction.choose_set(seat, zone, _none()))
	if Choice.is_optional_prompt(prompt):
		return engine.apply(EngineAction.decline(seat))
	return engine.apply(EngineAction.choose(seat, zone, Choice.options_of(prompt)[0]))


## Steps (_step) until round `at_round` turn `turn` has started; every event on the way.
func _step_to(engine: MatchEngine, at_round: int, turn: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var guard: int = 0
	var state: MatchState = engine._state
	while (
		state.round_number < at_round or (state.round_number == at_round and state.turn < turn)
	):
		var result: ApplyResult = _step(engine)
		assert_bool(result.ok).override_failure_message("step %d rejected" % guard).is_true()
		out.append_array(result.events)
		guard += 1
		if not result.ok or guard > MAX_STEPS or engine.is_over():
			break
	return out


func _kinds(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		out.append(event.kind)
	return out


func _of_kind(events: Array[MatchEvent], kind: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == kind:
			out.append(event)
	return out


func _crew_fired(seat: int, slot: int, crew: String, uses_left: int) -> Dictionary:
	var def: CrewDef = FixtureDecks.live_crew().crew_of(crew)
	return {
		"seat": seat,
		"slot": slot,
		"crew": crew,
		"verb": CrewDef.VERB_NAMES[def.verb],
		"trigger": CrewDef.TRIGGER_NAMES[def.trigger],
		"uses_left": uses_left,
	}


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


## Crew slot `slot` of `seat`'s uses left in the full state.
func _uses(engine: MatchEngine, seat: int, slot: int) -> int:
	var all_uses: Array = engine.full_state()["crew_uses"]
	var held: Array = all_uses[seat]
	var left: int = held[slot]
	return left


func _destroyed_on_row(engine: MatchEngine, seat: int) -> int:
	var piles: MatchState.SeatPiles = engine._state.seats[seat]
	var count: int = 0
	for card: int in piles.board:
		if engine._state.is_destroyed(card):
			count += 1
	return count


## Keeps `count` cards in `seat`'s hand, the rest put back under its deck.
func _trim_hand(engine: MatchEngine, seat: int, count: int) -> void:
	var piles: MatchState.SeatPiles = engine._state.seats[seat]
	while piles.hand.size() > count:
		var card: int = piles.hand[piles.hand.size() - 1]
		piles.hand.remove_at(piles.hand.size() - 1)
		piles.deck.append(card)


# --- Quartermaster ------------------------------------------------------------------------


## Quartermaster draws 2 extra for its seat on turn 1 (after the turn's draws, before any
## commit) and not on turn 2; the other seat draws as usual.
func test_quartermaster_draws_two_extra_on_turn_one_only() -> void:
	var engine: MatchEngine = MatchEngine.create(
		SEED, FixtureDecks.cards(), _decks_qm(), _ids_ab(), FixtureDecks.live_crew()
	)
	var started: ApplyResult = engine.start()
	assert_bool(started.ok).is_true()
	var fired: Array[MatchEvent] = _of_kind(started.events, CREW_FIRED)
	assert_int(fired.size()).is_equal(1)
	_assert_event(fired[0], CREW_FIRED, _crew_fired(0, 0, "quartermaster", -1), PUBLIC)
	var kinds: Array[int] = _kinds(started.events)
	var at: int = kinds.find(CREW_FIRED)
	assert_int(kinds.find(MatchEvent.Kind.TURN_STARTED)).is_less(at)
	assert_array(kinds.slice(at + 1)).is_equal(_typed([DRAWN, DRAWN]))
	for event: MatchEvent in started.events.slice(at + 1):
		assert_int(event.owner_seat).is_equal(0)
	var hand_0: int = engine._state.seats[0].hand.size()
	var hand_1: int = engine._state.seats[1].hand.size()
	assert_int(hand_0).is_equal(MatchRules.OPENING_HAND + 1 + CrewEffects.QUARTERMASTER_DRAWS)
	assert_int(hand_1).is_equal(MatchRules.OPENING_HAND + 1)
	var turn_2: Array[MatchEvent] = _step_to(engine, 1, 2)
	assert_array(_of_kind(turn_2, CREW_FIRED)).is_empty()
	assert_int(engine._state.seats[0].hand.size()).is_equal(hand_0 + 1)


## At the hand cap Quartermaster's draws burn as every draw does; off its turn it does not
## fire at all.
func test_quartermaster_burns_at_the_cap() -> void:
	var engine: MatchEngine = MatchEngine.create(
		SEED, FixtureDecks.cards(), _decks_qm(), _ids_ab(), FixtureDecks.live_crew()
	)
	assert_bool(engine.start().ok).is_true()
	var state: MatchState = engine._state
	var piles: MatchState.SeatPiles = state.seats[0]
	assert_int(piles.hand.size()).is_equal(MatchRules.HAND_CAP - 1)
	var burned: int = piles.burned.size()
	var outcome: EffectResolver.Outcome = CrewEffects.turn_start(
		state, engine.match_cards(), null, 0, 0
	)
	assert_object(outcome).is_not_null()
	if outcome == null:
		return
	assert_array(_kinds(outcome.events)).is_equal(_typed([CREW_FIRED, DRAWN, BURNED]))
	assert_int(piles.hand.size()).is_equal(MatchRules.HAND_CAP)
	assert_int(piles.burned.size()).is_equal(burned + 1)
	state.turn = 2
	assert_object(CrewEffects.turn_start(state, engine.match_cards(), null, 0, 0)).is_null()


func _decks_qm() -> DeckList:
	var root: Dictionary = {
		"version": DeckList.FORMAT_VERSION,
		"decks": [
			_deck("a", _fixture_ids(), ["quartermaster", "navigator", "gardener"]),
			_deck("b", _fixture_ids(), ["navigator", "gardener", "lookout"]),
		],
	}
	return DeckList.from_json(JSON.stringify(root))


func _ids_ab() -> Array[String]:
	var ids: Array[String] = ["a", "b"]
	return ids


# --- Tallyman -------------------------------------------------------------------------


## Tallyman: a card on its seat's row with an even effective flat (0 included) gets ×1.25,
## an odd one nothing, a card of the other seat (no Tallyman) or in a hand nothing; the
## no-bonus mark still clears it.
func test_tallyman_gives_even_flat_cards_of_its_seat_times_one_twenty_five() -> void:
	var engine: MatchEngine = _fixture_engine(
		["tallyman", "navigator", "gardener"], ["navigator", "gardener", "lookout"]
	)
	var state: MatchState = engine._state
	var cards: MatchCards = engine.match_cards()
	var other_c02: int = MatchRules.DECK_SIZE + C02
	var own: Array[int] = [C02, C04, C07, C03]
	var theirs: Array[int] = [other_c02]
	for seat: int in range(MatchEngine.SEATS):
		var piles: MatchState.SeatPiles = state.seats[seat]
		var row: Array[int] = own if seat == 0 else theirs
		for card: int in row:
			piles.deck.erase(card)
			piles.hand.erase(card)
		piles.board.assign(row)
	var hand: MatchState.SeatPiles = state.seats[0]
	hand.deck.erase(C08)
	if not hand.hand.has(C08):
		hand.hand.append(C08)
	assert_int(ScoreWalk.effective(C02, state, cards).times).is_equal(125)
	assert_int(ScoreWalk.effective(C04, state, cards).times).is_equal(100)
	assert_int(ScoreWalk.effective(C07, state, cards).times).is_equal(156)
	assert_int(ScoreWalk.effective(C03, state, cards).times).is_equal(125)
	assert_int(ScoreWalk.effective(other_c02, state, cards).times).is_equal(100)
	assert_int(ScoreWalk.effective(C08, state, cards).times).is_equal(100)
	# Flat 0 is even.
	state.card_state_for(C02).flat_delta = -2
	var zero: ScoreWalk.Effective = ScoreWalk.effective(C02, state, cards)
	assert_int(zero.flat).is_equal(0)
	assert_int(zero.times).is_equal(125)
	# An odd flat after a board change: no ×1.25.
	state.card_state_for(C02).flat_delta = -1
	assert_int(ScoreWalk.effective(C02, state, cards).times).is_equal(100)
	state.card_state_for(C07).no_bonus = true
	assert_int(ScoreWalk.effective(C07, state, cards).times).is_equal(100)


# --- Shade and Lookout ----------------------------------------------------------------


## A fixture match paused on Shade's turn-4 prompt: seat 0 (Shade, Lookout, Navigator) has
## C02 and C04 face up on its row from turn 3, seat 1 C02; seat 0's hand kept small so
## Lookout's draw is not burned.
func _shade_engine() -> MatchEngine:
	var engine: MatchEngine = _fixture_engine(
		["shade", "lookout", "navigator"], ["navigator", "gardener", "veil"]
	)
	_step_to(engine, 1, 3)
	_trim_hand(engine, 0, 2)
	var own: Array[int] = [C02, C04]
	var theirs: Array[int] = [MatchRules.DECK_SIZE + C02]
	var walked: ApplyResult = _table(engine, own, theirs)
	assert_bool(walked.ok).is_true()
	var kinds: Array[int] = _kinds(walked.events)
	assert_int(kinds.rfind(REQUESTED)).is_equal(kinds.size() - 1)
	return engine


## Shade prompts at the start of turn 4, before any commit, over its seat's revealed cards
## (optional, resuming the turn start); a choice flips that card face down and Lookout
## draws for it; then the first committer is awaited.
func test_shade_flips_a_chosen_card_and_lookout_draws() -> void:
	var engine: MatchEngine = _shade_engine()
	assert_int(engine.energy()).is_equal(4)
	assert_int(engine._state.phase).is_equal(MatchState.Phase.AWAIT_CHOICE)
	assert_int(engine.awaited_seat()).is_equal(0)
	var prompt: Dictionary = engine.open_prompt()
	assert_str(Choice.crew_of(prompt)).is_equal("shade")
	assert_bool(Choice.is_optional_prompt(prompt)).is_true()
	assert_str(Choice.resume_of(prompt)).is_equal(Choice.RESUME_TURN_START)
	var zone: int = prompt["zone"]
	assert_int(zone).is_equal(OWN_BOARD)
	assert_array(Choice.options_of(prompt)).is_equal(_typed([0, 1]))
	var piles: MatchState.SeatPiles = engine._state.seats[0]
	var hand: int = piles.hand.size()
	var chosen: ApplyResult = engine.apply(EngineAction.choose(0, OWN_BOARD, 1))
	assert_bool(chosen.ok).is_true()
	var kinds: Array[int] = []
	for kind: int in _kinds(chosen.events):
		if kind != STATS:
			kinds.append(kind)
	assert_array(kinds).is_equal(_typed([MADE, CREW_FIRED, UNREVEALED, CREW_FIRED, DRAWN]))
	var fired: Array[MatchEvent] = _of_kind(chosen.events, CREW_FIRED)
	_assert_event(fired[0], CREW_FIRED, _crew_fired(0, 0, "shade", -1), PUBLIC)
	_assert_event(fired[1], CREW_FIRED, _crew_fired(0, 1, "lookout", -1), PUBLIC)
	var flipped: Array[MatchEvent] = _of_kind(chosen.events, UNREVEALED)
	_assert_event(flipped[0], UNREVEALED, {"seat": 0, "card": C04, "slot": 1}, PUBLIC)
	assert_int(_of_kind(chosen.events, DRAWN)[0].owner_seat).is_equal(0)
	assert_bool(piles.is_revealed(C04)).is_false()
	assert_bool(piles.is_revealed(C02)).is_true()
	assert_array(piles.board).is_equal(_typed([C02, C04]))
	assert_int(piles.hand.size()).is_equal(hand + 1)
	assert_int(engine._state.phase).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_dict(engine.open_prompt()).is_empty()


## Declining Shade changes nothing: no Crew fires, no card flips, no draw.
func test_declining_shade_changes_nothing() -> void:
	var engine: MatchEngine = _shade_engine()
	var piles: MatchState.SeatPiles = engine._state.seats[0]
	var hand: Array[int] = piles.hand.duplicate()
	var revealed: Array[int] = piles.revealed_ids()
	var memory: Dictionary = engine.full_state()["memory"]
	var declined: ApplyResult = engine.apply(EngineAction.decline(0))
	assert_bool(declined.ok).is_true()
	assert_array(_kinds(declined.events)).is_equal(_typed([DECLINED]))
	_assert_event(declined.events[0], DECLINED, {"seat": 0, "card": -1, "crew": "shade"}, PUBLIC)
	assert_array(piles.hand).is_equal(hand)
	assert_array(piles.revealed_ids()).is_equal(revealed)
	assert_dict(engine.full_state()["memory"]).is_equal(memory)
	assert_int(engine._state.phase).is_equal(MatchState.Phase.AWAIT_FIRST)


# --- Salvager -------------------------------------------------------------------------


## A Ruin match paused on Immolator's sacrifice prompt: seat 0 holds Scrap and Tinder face
## up and Immolator (slot 2, revealing now); seat 1 three vanilla cards. Seat 0's Crew are
## `crew_a`; seat 1's (Navigator, Gardener, Lookout) never fire here.
func _sacrifice_engine(crew_a: Array) -> MatchEngine:
	var engine: MatchEngine = _ruin_engine(crew_a, ["navigator", "gardener", "lookout"])
	var own: Array[int] = [R01_SCRAP, R02_TINDER, R16_IMMOLATOR]
	var theirs: Array[int] = []
	for index: int in [R01_SCRAP, R04_SHARD, R09_WICK]:
		theirs.append(MatchRules.DECK_SIZE + index)
	var walked: ApplyResult = _table(engine, own, theirs)
	assert_bool(walked.ok).is_true()
	assert_bool(Choice.is_multi_prompt(engine.open_prompt())).is_true()
	return engine


## Salvager prompts once Immolator's sacrifice has resolved, the opponent having already
## lost its card; a discard sends the destroyed card to its hand at turn end with its
## memory, the destroyed pile staying empty.
func test_salvager_prompts_after_the_sacrifice_and_returns_the_card() -> void:
	var engine: MatchEngine = _sacrifice_engine(["salvager", "navigator", "gardener"])
	engine._state.memory_for(R01_SCRAP).flat = 1
	var answered: ApplyResult = engine.apply(EngineAction.choose_set(0, OWN_BOARD, _typed([0])))
	assert_bool(answered.ok).is_true()
	var kinds: Array[int] = _kinds(answered.events)
	assert_int(_of_kind(answered.events, DESTROYED).size()).is_equal(2)
	assert_int(kinds.rfind(DESTROYED)).is_less(kinds.find(REQUESTED))
	assert_int(kinds.find(REQUESTED)).is_equal(kinds.size() - 1)
	assert_int(_destroyed_on_row(engine, 1)).is_equal(1)
	var prompt: Dictionary = engine.open_prompt()
	assert_str(Choice.crew_of(prompt)).is_equal("salvager")
	assert_bool(Choice.is_optional_prompt(prompt)).is_true()
	assert_str(Choice.resume_of(prompt)).is_equal(Choice.RESUME_WALK)
	var zone: int = prompt["zone"]
	assert_int(zone).is_equal(OWN_HAND)
	var queue: Array = engine.full_state()["crew_queue"]
	assert_int(queue.size()).is_greater(0)
	var piles: MatchState.SeatPiles = engine._state.seats[0]
	var discard: int = piles.hand[0]
	var chosen: ApplyResult = engine.apply(EngineAction.choose(0, OWN_HAND, 0))
	assert_bool(chosen.ok).is_true()
	var fired: Array[MatchEvent] = _of_kind(chosen.events, CREW_FIRED)
	assert_int(fired.size()).is_equal(1)
	_assert_event(fired[0], CREW_FIRED, _crew_fired(0, 0, "salvager", 0), PUBLIC)
	var discarded: Array[MatchEvent] = _of_kind(chosen.events, DISCARDED)
	_assert_event(discarded[0], DISCARDED, {"seat": 0, "card": discard}, 0)
	var salvaged: Dictionary = {
		"seat": 0, "card": R01_SCRAP, "slot": 0, "pile": false, "salvaged": true
	}
	var cleared: Array[MatchEvent] = []
	for event: MatchEvent in _of_kind(chosen.events, CLEARED):
		var seat: int = event.payload["seat"]
		if seat == 0:
			cleared.append(event)
	assert_int(cleared.size()).is_equal(1)
	_assert_event(cleared[0], CLEARED, salvaged, PUBLIC)
	assert_bool(piles.hand.has(R01_SCRAP)).is_true()
	assert_bool(piles.burned.has(discard)).is_true()
	assert_array(piles.destroyed).is_empty()
	assert_int(engine._state.memory_of(R01_SCRAP).flat).is_equal(1)
	assert_int(_uses(engine, 0, 0)).is_equal(0)
	assert_int(engine.energy()).is_equal(2)


## Salvager fires once per round: a second destroy that round opens no prompt, fires
## nothing, and the card goes to the pile.
func test_salvager_is_silent_once_spent_this_round() -> void:
	var engine: MatchEngine = _sacrifice_engine(["salvager", "navigator", "gardener"])
	assert_bool(engine.apply(EngineAction.choose_set(0, OWN_BOARD, _typed([0]))).ok).is_true()
	assert_bool(engine.apply(EngineAction.choose(0, OWN_HAND, 0)).ok).is_true()
	assert_int(engine.energy()).is_equal(2)
	var own: Array[int] = [R09_WICK]
	var theirs: Array[int] = [MatchRules.DECK_SIZE + R18_REAPER]
	var walked: ApplyResult = _table(engine, own, theirs)
	assert_bool(walked.ok).is_true()
	assert_array(_of_kind(walked.events, REQUESTED)).is_empty()
	assert_array(_of_kind(walked.events, CREW_FIRED)).is_empty()
	assert_int(_uses(engine, 0, 0)).is_equal(0)
	var piles: MatchState.SeatPiles = engine._state.seats[0]
	assert_array(piles.destroyed).is_equal(_typed([R09_WICK]))
	assert_int(engine.energy()).is_equal(3)


## The queued cards of `state`'s Crew queue, head first.
func _queued_cards(state: MatchState) -> Array[int]:
	var out: Array[int] = []
	for entry: Dictionary in state.crew_queue:
		var card: int = entry[CrewEffects.KEY_CARD]
		out.append(card)
	return out


## Puts `row` (instance ids, all face up) on `seat`'s row, out of its deck and hand.
func _face_up_row(state: MatchState, seat: int, row: Array[int]) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	for card: int in row:
		piles.deck.erase(card)
		piles.hand.erase(card)
		piles.revealed[card] = true
	piles.board.assign(row)


## One effect destroying the opponent's slot 2 and then slot 0 (a random multi-destroy's
## order) queues them in that order, but the queue fires in row order (R45; DC-11 T13
## review, C13): the once-per-round Salvager is offered slot 0's card, and accepting
## salvages that card, not slot 2's.
func test_a_multi_destroy_fires_its_crew_in_row_order() -> void:
	var engine: MatchEngine = _fixture_engine(
		["navigator", "gardener", "lookout"], ["salvager", "navigator", "gardener"]
	)
	var state: MatchState = engine._state
	var cards: MatchCards = engine.match_cards()
	var theirs: Array[int] = []
	for index: int in [C02, C04, C08]:
		theirs.append(MatchRules.DECK_SIZE + index)
	_face_up_row(state, 1, theirs)
	var piles: MatchState.SeatPiles = state.seats[1]
	assert_bool(piles.hand.is_empty()).is_false()
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(EffectResolver.destroy(state, cards, theirs[2], outcome)).is_true()
	assert_bool(EffectResolver.destroy(state, cards, theirs[0], outcome)).is_true()
	assert_array(_queued_cards(state)).is_equal(_typed([theirs[2], theirs[0]]))
	var drained: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(CrewEffects.drain(state, cards, null, true, drained)).is_true()
	assert_array(_queued_cards(state)).is_equal(_typed([theirs[0], theirs[2]]))
	assert_str(Choice.crew_of(state.prompt)).is_equal("salvager")
	var discard: int = piles.hand[0]
	var chosen: Array[MatchEvent] = CrewEffects.apply_choice(
		state, cards, state.prompt, discard, null
	)
	assert_array(_kinds(chosen)).is_equal(_typed([CREW_FIRED, DISCARDED]))
	assert_bool(state.card_state_for(theirs[0]).salvaged).is_true()
	assert_bool(state.card_state_for(theirs[2]).salvaged).is_false()
	# The rest of the batch: Salvager is spent, so slot 2's card is offered nothing.
	state.prompt = {}
	var rest: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(CrewEffects.drain(state, cards, null, true, rest)).is_false()
	assert_array(rest.events).is_empty()
	assert_array(state.crew_queue).is_empty()


## The same out-of-order destroys, replayed on a copy of the state, drain in the same order
## (the sort reads only the state).
func test_the_row_order_is_the_same_on_a_copy() -> void:
	var engine: MatchEngine = _fixture_engine(
		["navigator", "gardener", "lookout"], ["salvager", "navigator", "gardener"]
	)
	var state: MatchState = engine._state
	var cards: MatchCards = engine.match_cards()
	var theirs: Array[int] = []
	for index: int in [C02, C04, C08]:
		theirs.append(MatchRules.DECK_SIZE + index)
	_face_up_row(state, 1, theirs)
	var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(EffectResolver.destroy(state, cards, theirs[1], outcome)).is_true()
	assert_bool(EffectResolver.destroy(state, cards, theirs[0], outcome)).is_true()
	var copy: MatchState = state.duplicate()
	for held: MatchState in [state, copy]:
		var drained: EffectResolver.Outcome = EffectResolver.Outcome.new()
		assert_bool(CrewEffects.drain(held, cards, null, true, drained)).is_true()
		assert_array(_queued_cards(held)).is_equal(_typed([theirs[0], theirs[1]]))
	assert_dict(copy.to_dict()).is_equal(state.to_dict())


## Salvager at the hand cap (R51, R65; DC-11 T13 review, C13): the salvaged card burns from
## its row as a return at the cap does, CARD_BURNED {seat, card, slot, row_seat} alone with
## no DESTROYED_CLEARED before it; public for a revealed card, private to its seat (its id
## hidden from the other seat, its slot kept) for a face-down one.
func test_a_salvaged_card_at_the_hand_cap_burns_from_its_row() -> void:
	var engine: MatchEngine = _fixture_engine(
		["salvager", "navigator", "gardener"], ["navigator", "gardener", "lookout"]
	)
	var state: MatchState = engine._state
	var cards: MatchCards = engine.match_cards()
	var row: Array[int] = [C02, C04, C08]
	_face_up_row(state, 0, row)
	var piles: MatchState.SeatPiles = state.seats[0]
	assert_bool(piles.revealed.erase(C02)).is_true()  # C02 face down.
	while piles.hand.size() < MatchRules.HAND_CAP and not piles.deck.is_empty():
		piles.hand.append(piles.deck.pop_back())
	assert_int(piles.hand.size()).is_equal(MatchRules.HAND_CAP)
	for card: int in [C02, C08]:
		state.card_state_for(card).destroyed = true
		state.card_state_for(card).salvaged = true
	var events: Array[MatchEvent] = EffectResolver.clear_destroyed(state, cards)
	assert_array(_kinds(events)).is_equal(_typed([BURNED, BURNED]))
	var hidden: Dictionary = {"seat": 0, "card": C02, "slot": 0, "row_seat": 0}
	_assert_event(events[0], BURNED, hidden, 0)
	var shown: Dictionary = {"seat": 0, "card": C08, "slot": 1, "row_seat": 0}
	_assert_event(events[1], BURNED, shown, PUBLIC)
	var redacted: Dictionary = events[0].redacted_for(1).payload
	var masked: Dictionary = {"seat": 0, "card": MatchEvent.HIDDEN_CARD, "slot": 0, "row_seat": 0}
	assert_dict(redacted).is_equal(masked)
	assert_dict(events[1].redacted_for(1).payload).is_equal(shown)
	assert_array(piles.board).is_equal(_typed([C04]))
	assert_bool(piles.burned.has(C02)).is_true()
	assert_bool(piles.burned.has(C08)).is_true()
	assert_array(piles.destroyed).is_empty()
	assert_int(piles.hand.size()).is_equal(MatchRules.HAND_CAP)
	assert_array(state.crew_queue).is_empty()


## With an empty hand Salvager has no target: it does not fire or count, and the walk goes
## on to the turn end.
func test_salvager_does_not_fire_with_an_empty_hand() -> void:
	var engine: MatchEngine = _sacrifice_engine(["salvager", "navigator", "gardener"])
	engine._state.seats[0].hand.clear()
	var answered: ApplyResult = engine.apply(EngineAction.choose_set(0, OWN_BOARD, _typed([0])))
	assert_bool(answered.ok).is_true()
	assert_array(_of_kind(answered.events, REQUESTED)).is_empty()
	assert_array(_of_kind(answered.events, CREW_FIRED)).is_empty()
	assert_int(_uses(engine, 0, 0)).is_equal(1)
	assert_int(engine._state.phase).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_array(engine._state.seats[0].destroyed).is_equal(_typed([R01_SCRAP]))


# --- Veil -----------------------------------------------------------------------------


## Veil prompts over the destroyed card alone; accepting un-destroys it and flips every
## revealed card of the row face down, in slot order, and spends its use for the match.
func test_veil_un_destroys_and_flips_the_row_face_down() -> void:
	var engine: MatchEngine = _sacrifice_engine(["veil", "navigator", "gardener"])
	var answered: ApplyResult = engine.apply(EngineAction.choose_set(0, OWN_BOARD, _typed([0])))
	assert_bool(answered.ok).is_true()
	var prompt: Dictionary = engine.open_prompt()
	assert_str(Choice.crew_of(prompt)).is_equal("veil")
	assert_bool(Choice.is_optional_prompt(prompt)).is_true()
	var zone: int = prompt["zone"]
	assert_int(zone).is_equal(OWN_BOARD)
	assert_array(Choice.options_of(prompt)).is_equal(_typed([0]))
	var chosen: ApplyResult = engine.apply(EngineAction.choose(0, OWN_BOARD, 0))
	assert_bool(chosen.ok).is_true()
	var fired: Array[MatchEvent] = _of_kind(chosen.events, CREW_FIRED)
	_assert_event(fired[0], CREW_FIRED, _crew_fired(0, 0, "veil", 0), PUBLIC)
	var flips: Array[MatchEvent] = []
	for event: MatchEvent in _of_kind(chosen.events, UNREVEALED):
		var seat: int = event.payload["seat"]
		if seat == 0:
			flips.append(event)
	assert_int(flips.size()).is_equal(3)
	var expected: Array = [R01_SCRAP, R02_TINDER, R16_IMMOLATOR]
	for slot: int in range(flips.size()):
		var payload: Dictionary = {"seat": 0, "card": expected[slot], "slot": slot}
		_assert_event(flips[slot], UNREVEALED, payload, PUBLIC)
	var piles: MatchState.SeatPiles = engine._state.seats[0]
	assert_array(piles.board).is_equal(_typed(expected))
	assert_array(piles.revealed_ids()).is_empty()
	assert_bool(engine._state.is_destroyed(R01_SCRAP)).is_false()
	assert_array(piles.destroyed).is_empty()
	# The opponent's card the sacrifice destroyed still went: the effect counted it.
	assert_int(engine._state.seats[1].destroyed.size()).is_equal(1)
	assert_int(_uses(engine, 0, 0)).is_equal(0)
	# Spent for the match: still spent in round 2.
	_step_to(engine, 2, 1)
	assert_int(engine._state.round_number).is_equal(2)
	assert_int(_uses(engine, 0, 0)).is_equal(0)


## Declining Veil keeps its use: the card stays destroyed and goes to the pile.
func test_declining_veil_keeps_its_use() -> void:
	var engine: MatchEngine = _sacrifice_engine(["veil", "navigator", "gardener"])
	assert_bool(engine.apply(EngineAction.choose_set(0, OWN_BOARD, _typed([0]))).ok).is_true()
	var declined: ApplyResult = engine.apply(EngineAction.decline(0))
	assert_bool(declined.ok).is_true()
	assert_int(declined.events[0].kind).is_equal(DECLINED)
	assert_array(_of_kind(declined.events, CREW_FIRED)).is_empty()
	assert_int(_uses(engine, 0, 0)).is_equal(1)
	assert_array(engine._state.seats[0].destroyed).is_equal(_typed([R01_SCRAP]))


# --- Navigator ------------------------------------------------------------------------


## Navigator: each card of its seat moved by an effect gets +1 flat for the round, once the
## move has resolved (the queue holds it until then), each move again; a face-down card's
## change is private; a move of the other seat's cards (no Navigator) fires nothing.
func test_navigator_gives_plus_one_flat_on_each_own_move() -> void:
	var engine: MatchEngine = _fixture_engine(
		["navigator", "gardener", "lookout"], ["gardener", "lookout", "veil"]
	)
	var state: MatchState = engine._state
	var cards: MatchCards = engine.match_cards()
	var own: Array[int] = [C02, C03, C04, C08]
	var theirs: Array[int] = [MatchRules.DECK_SIZE + C02, MatchRules.DECK_SIZE + C04]
	for seat: int in range(MatchEngine.SEATS):
		var piles: MatchState.SeatPiles = state.seats[seat]
		var row: Array[int] = own if seat == 0 else theirs
		for card: int in row:
			piles.deck.erase(card)
			piles.hand.erase(card)
			if card != C08:
				piles.revealed[card] = true
		piles.board.assign(row)
	var moved: EffectResolver.Outcome = EffectResolver.Outcome.new()
	DriftEffects.place(state, cards, null, null, 0, C08, 0, moved)
	assert_array(state.seats[0].board).is_equal(_typed([C08, C02, C03, C04]))
	assert_int(_of_kind(moved.events, MOVED).size()).is_equal(4)
	# Not inside the move: queued, nothing fired yet.
	assert_array(_of_kind(moved.events, CREW_FIRED)).is_empty()
	assert_int(state.crew_queue.size()).is_equal(4)
	assert_object(state.card_state(C02)).is_null()
	var drained: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(CrewEffects.drain(state, cards, null, true, drained)).is_false()
	assert_array(state.crew_queue).is_empty()
	var expected: Array[int] = []
	for _card: int in own:
		expected.append_array([CREW_FIRED, STATS])
	assert_array(_kinds(drained.events)).is_equal(expected)
	var stats: Array[MatchEvent] = _of_kind(drained.events, STATS)
	assert_int(stats[0].owner_seat).is_equal(0)  # C08 is face down.
	for index: int in range(1, stats.size()):
		assert_int(stats[index].owner_seat).is_equal(PUBLIC)
	var cause: String = stats[1].payload["cause"]
	assert_str(cause).is_equal(CrewEffects.CAUSE_CREW)
	for card: int in own:
		assert_int(state.card_state(card).flat_delta).is_equal(1)
	assert_int(ScoreWalk.effective(C04, state, cards).flat).is_equal(4)
	# Each move again: C04 to the far left moves all four once more.
	var again: EffectResolver.Outcome = EffectResolver.Outcome.new()
	DriftEffects.place(state, cards, null, null, 0, C04, 0, again)
	assert_bool(CrewEffects.drain(state, cards, null, true, again)).is_false()
	for card: int in own:
		assert_int(state.card_state(card).flat_delta).is_equal(2)
	# The other seat's row reversed: its seat holds no Navigator, so nothing is queued.
	var reversed: Array[int] = [theirs[1], theirs[0]]
	var other: EffectResolver.Outcome = EffectResolver.Outcome.new()
	DriftEffects.rewrite_row(state, cards, null, null, 1, reversed, other)
	assert_array(state.crew_queue).is_empty()
	assert_object(state.card_state(theirs[0])).is_null()


# --- Gardener -------------------------------------------------------------------------


## Gardener: when the round ends (after the last turn's end, before the round's winner)
## each card on its seat's row grows +1 flat for the match; next round that card shows the
## growth in the hand.
func test_gardener_grows_the_row_at_round_end_into_the_next_hand() -> void:
	var engine: MatchEngine = _fixture_engine(
		["gardener", "navigator", "lookout"], ["navigator", "veil", "lookout"]
	)
	_step_to(engine, 1, MatchRules.TURNS)
	var own: Array[int] = [C02, C04]
	var walked: ApplyResult = _table(engine, own, _none())
	assert_bool(walked.ok).is_true()
	var kinds: Array[int] = _kinds(walked.events)
	var at: int = kinds.find(CREW_FIRED)
	assert_int(at).is_greater(kinds.find(TURN_ENDED))
	assert_int(at).is_less(kinds.find(ROUND_ENDED))
	assert_int(_of_kind(walked.events, CREW_FIRED).size()).is_equal(1)
	var fired: MatchEvent = walked.events[at]
	_assert_event(fired, CREW_FIRED, _crew_fired(0, 0, "gardener", -1), PUBLIC)
	var grown: Array[MatchEvent] = walked.events.slice(at + 1, at + 3)
	for index: int in range(grown.size()):
		assert_int(grown[index].kind).is_equal(STATS)
		var card: int = grown[index].payload["card"]
		var permanent: bool = grown[index].payload["permanent"]
		assert_int(card).is_equal(own[index])
		assert_bool(permanent).is_true()
	assert_int(engine._state.round_number).is_equal(2)
	var state: MatchState = engine._state
	assert_int(state.memory_of(C02).flat).is_equal(1)
	assert_int(state.memory_of(C04).flat).is_equal(1)
	var piles: MatchState.SeatPiles = state.seats[0]
	if not piles.hand.has(C02):
		piles.deck.erase(C02)
		piles.hand.append(C02)
	var entry: Dictionary = {}
	for shown: Dictionary in engine.view_for(0).own_hand_row:
		var card: int = shown["card"]
		if card == C02:
			entry = shown
	var flat: int = entry.get("flat", -1)
	var marked: bool = entry.get("grown", false)
	assert_int(flat).is_equal(3)
	assert_bool(marked).is_true()


# --- No target ------------------------------------------------------------------------


## A Crew with no eligible target does not fire or count: Shade on turn 4 with no card up,
## Gardener over an empty row, and Salvager and Veil with nothing destroyed, through a
## whole round of passes.
func test_a_crew_with_no_target_does_not_fire_or_count() -> void:
	var engine: MatchEngine = _fixture_engine(
		["shade", "gardener", "salvager"], ["veil", "lookout", "navigator"]
	)
	var events: Array[MatchEvent] = _step_to(engine, 1, 4)
	assert_int(engine._state.phase).is_equal(MatchState.Phase.AWAIT_FIRST)
	assert_dict(engine.open_prompt()).is_empty()
	events.append_array(_step_to(engine, 2, 1))
	assert_int(engine._state.round_number).is_equal(2)
	assert_array(_of_kind(events, CREW_FIRED)).is_empty()
	assert_array(_of_kind(events, REQUESTED)).is_empty()
	var none: int = CrewDef.UNLIMITED
	var uses: Array = engine.full_state()["crew_uses"]
	assert_array(uses).is_equal([[none, none, 1], [1, none, none]])


# --- Replay ---------------------------------------------------------------------------


## The shipped Ruin deck on both seats from `match_seed`, played by a fixed script (the
## first affordable hand card, the first option, a sacrifice of the first option) until a
## Crew prompt opens in a walk; null when none opens within MAX_ACTIONS.
func _crew_prompt_match(match_seed: int) -> MatchEngine:
	var ids: Array[String] = ["ruin", "ruin"]
	var engine: MatchEngine = MatchEngine.create(
		match_seed, CardDb.load_default(), DeckList.load_default(), ids, CrewPool.load_default()
	)
	if not engine.start().ok:
		return null
	for _action: int in range(MAX_ACTIONS):
		var prompt: Dictionary = engine.open_prompt()
		if Choice.crew_of(prompt) != "" and Choice.resume_of(prompt) == Choice.RESUME_WALK:
			return engine
		if engine.is_over() or not engine.apply(_scripted(engine)).ok:
			return null
	return null


## The script of _crew_prompt_match() for whoever is awaited.
func _scripted(engine: MatchEngine) -> EngineAction:
	var prompt: Dictionary = engine.open_prompt()
	if not prompt.is_empty():
		var asked: int = prompt["seat"]
		var zone: int = prompt["zone"]
		var first: int = Choice.options_of(prompt)[0]
		if Choice.is_multi_prompt(prompt):
			return EngineAction.choose_set(asked, zone, _typed([first]))
		return EngineAction.choose(asked, zone, first)
	var seat: int = engine.awaited_seat()
	var view: SeatView = engine.view_for(seat)
	for index: int in range(view.own_hand.size()):
		if view.own_hand_costs[index] <= engine.budget_for(seat):
			return EngineAction.commit(seat, _typed([view.own_hand[index]]))
	return EngineAction.commit(seat, _none())


func _replayed(text: String) -> ReplayResult:
	var parsed: ActionLog = ActionLog.from_json(text)
	assert_object(parsed).is_not_null()
	return parsed.replay(CardDb.load_default(), DeckList.load_default(), CrewPool.load_default())


## A match paused on a Crew prompt in a walk holds its queue in the full state (and in a
## copy), and its log replays to an equal state through ActionLog.replay, the shipped Crew
## firing; the greedy bot answers that prompt with a plain choice the engine accepts; and a
## log holding a decline of a real Crew prompt replays too.
func test_a_queued_crew_and_a_declined_crew_prompt_replay() -> void:
	var engine: MatchEngine = null
	for match_seed: int in range(1, REPLAY_SEEDS + 1):
		engine = _crew_prompt_match(match_seed)
		if engine != null:
			break
	assert_object(engine).override_failure_message("no Crew prompt in a walk").is_not_null()
	if engine == null:
		return
	var paused: Dictionary = engine.full_state()
	var queue: Array = paused["crew_queue"]
	assert_int(queue.size()).is_greater(0)
	assert_dict(engine._state.duplicate().to_dict()).is_equal(paused)
	var text: String = engine.action_log().to_json()
	var at_prompt: ReplayResult = _replayed(text)
	assert_bool(at_prompt.ok).is_true()
	if not at_prompt.ok:
		return
	assert_dict(at_prompt.engine.full_state()).is_equal(paused)
	# A bot answers the Crew prompt with a plain choice (bots do not decline yet).
	var seat: int = engine.open_prompt()["seat"]
	var replica: MatchEngine = at_prompt.engine
	var bot: GreedyBot = GreedyBot.new(GreedyBot.seed_for(SEED, seat), replica.match_cards())
	var answer: EngineAction = bot.choose(replica.view_for(seat), replica)
	assert_int(answer.kind).is_equal(EngineAction.Kind.CHOOSE)
	assert_bool(replica.apply(answer).ok).is_true()
	# The decline, then a few more actions; the whole log replays.
	assert_bool(engine.apply(EngineAction.decline(seat)).ok).is_true()
	for _action: int in range(6):
		if engine.is_over():
			break
		assert_bool(engine.apply(_scripted(engine)).ok).is_true()
	var logged: String = engine.action_log().to_json()
	assert_bool(logged.contains('{"k":"decline","s":%d}' % seat)).is_true()
	var replayed: ReplayResult = _replayed(logged)
	assert_bool(replayed.ok).is_true()
	if not replayed.ok:
		return
	assert_dict(replayed.engine.full_state()).is_equal(engine.full_state())
	assert_str(replayed.engine.action_log().to_json()).is_equal(logged)
