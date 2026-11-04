class_name TestEffectsRuin
extends GdUnitTestSuite
## The Ruin verbs (DC-07 T05; R22-R25, R27, R35, plan P7, P12): sacrifice_destroy's
## multi-select prompt over the owner's other live cards, the chosen cards destroyed and as
## many random live opponent cards from the engine stream, fewer when fewer are live, the
## previews of a set (MatchEngine.preview_set) and the decline of a nested one
## (PreviewPolicy), and replay of a log holding a set.
##
## No shipped card sacrifices yet, so the fixture's c02 (cost 1, flat 2) is given an
## on-reveal sacrifice_destroy in memory (FixtureDecks.sacrifice_cards). Tables are set by
## hand on a started fixture match (FixtureDecks.play_table), except for the replay case,
## which reaches the prompt through commits alone. Instance id = seat * DECK_SIZE + index.
## The destroys are T05's provisional mark in place; T06 moves them to the P9 pipeline.

const SEED: int = 1
const SEARCH_SEEDS: int = 200
const MAX_PASSES: int = 60

# Definition indices in the fixture card list (all effect-free but c02).
const C02_SACRIFICE: int = FixtureDecks.C02_SACRIFICE
const C03: int = 2
const C04: int = 3
const C07: int = 6
const C08: int = 7

const PUBLIC: int = MatchEvent.PUBLIC
const OWN_BOARD: int = Choice.Zone.OWN_BOARD
const REQUESTED: int = MatchEvent.Kind.CHOICE_REQUESTED
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const DESTROYED: int = MatchEvent.Kind.CARD_DESTROYED
const TURN_ENDED: int = MatchEvent.Kind.TURN_ENDED

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.sacrifice_cards()
	return _cached_db


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


func _engine(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	assert_bool(engine.start().ok).is_true()
	return engine


## A started seed-1 match paused on seat 0's sacrifice prompt: seat 0's row `own` (c02,
## the source, last) and seat 1's row `theirs`, every card revealed by the walk first.
func _table(own: Array[int], theirs: Array[int]) -> MatchEngine:
	var engine: MatchEngine = _engine(SEED)
	assert_bool(FixtureDecks.play_table(engine, own, theirs)).is_true()
	assert_bool(engine.open_prompt().is_empty()).is_false()
	return engine


func _pass(engine: MatchEngine) -> ApplyResult:
	return engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))


func _pass_to_turn(engine: MatchEngine, turn: int) -> void:
	var guard: int = 0
	while engine.energy() < turn and guard < MAX_PASSES:
		assert_bool(_pass(engine).ok).is_true()
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


## The `card` of every event of `kind`, in order.
func _cards_of(events: Array[MatchEvent], kind: int) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, kind):
		out.append(_payload_int(event, "card"))
	return out


func _sorted(values: Array[int]) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	out.sort()
	return out


## The engine stream as it stands in `engine`'s full state (its next draws).
func _stream(engine: MatchEngine) -> MatchRng:
	var full: Dictionary = engine.full_state()
	var state: int = full["rng_state"]
	var rng: MatchRng = MatchRng.new(0)
	rng.state = state
	return rng


## The scores of the first TURN_ENDED in `events`, or [] when there is none.
func _turn_scores(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, TURN_ENDED):
		var scores: Array = event.payload["scores"]
		out.assign(scores)
		return out
	return out


# --- The prompt (R22, R25, P7, P12) -----------------------------------------------------


## P12: the options are every other live card of the owner's row, face up or down; the
## prompt, its event and the prompted seat's view all say `multi`, and the view of the other
## seat only that a prompt is open.
func test_the_prompt_offers_every_other_live_own_card() -> void:
	var source: int = _id(0, C02_SACRIFICE)
	var wreck: int = _id(0, C07)
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].board.assign([_id(0, C04), wreck, _id(0, C08), source])
	state.seats[0].revealed[_id(0, C04)] = true
	state.card_state_for(wreck).destroyed = true
	var found: Dictionary = Choice.eligible(state, 0, CardEffect.Verb.SACRIFICE_DESTROY, source)
	var zone: int = found[Choice.KEY_ZONE]
	assert_int(zone).is_equal(OWN_BOARD)
	assert_array(Choice.options_of(found)).is_equal(_typed([0, 2]))
	assert_bool(Choice.is_multi(CardEffect.Verb.SACRIFICE_DESTROY)).is_true()
	assert_bool(Choice.is_multi(CardEffect.Verb.SWAP_PLACES)).is_false()
	var engine: MatchEngine = _table(_typed([_id(0, C04), _id(0, C08), source]), _none())
	var prompt: Dictionary = engine.open_prompt()
	var multi: bool = prompt[Choice.KEY_MULTI]
	assert_bool(multi).is_true()
	assert_array(Choice.options_of(prompt)).is_equal(_typed([0, 1]))
	assert_int(engine.awaited_seat()).is_equal(0)
	var own_view: Dictionary = engine.view_for(0).prompt
	var view_multi: bool = own_view[Choice.KEY_MULTI]
	assert_bool(view_multi).is_true()
	assert_dict(engine.view_for(1).prompt).is_equal({"open": true, "seat": 0})


## R22: CHOICE_REQUESTED of a set is public and carries `multi` true.
func test_the_request_is_public_and_multi() -> void:
	var engine: MatchEngine = _engine(SEED)
	var source: int = _id(0, C02_SACRIFICE)
	var own: Array[int] = [_id(0, C04), source]
	var state: MatchState = engine._state
	for card: int in own:
		state.seats[0].deck.erase(card)
		state.seats[0].hand.erase(card)
	state.seats[0].board.assign(own)
	var first: ApplyResult = _pass(engine)
	var second: ApplyResult = _pass(engine)
	assert_bool(first.ok and second.ok).is_true()
	var requested: Array[MatchEvent] = _of_kind(second.events, REQUESTED)
	assert_int(requested.size()).is_equal(1)
	assert_int(requested[0].owner_seat).is_equal(PUBLIC)
	var multi: bool = requested[0].payload["multi"]
	assert_bool(multi).is_true()
	var verb: String = requested[0].payload["verb"]
	assert_str(verb).is_equal("sacrifice_destroy")
	assert_array(requested[0].payload["options"]).is_equal([0])


# --- The set (R24, R27, R35) ------------------------------------------------------------


## R27, R35: choosing 2 of 4 destroys those two (in row order) and then two random live
## opponent cards, drawn from the engine stream at the answer; CHOICE_MADE carries the set
## as given and index -1. The destroyed cards reach their piles at turn end.
func test_choosing_two_of_four_destroys_them_and_two_random_opponent_cards() -> void:
	var source: int = _id(0, C02_SACRIFICE)
	var own: Array[int] = [_id(0, C03), _id(0, C04), _id(0, C07), _id(0, C08), source]
	var theirs: Array[int] = [_id(1, C03), _id(1, C04), _id(1, C08)]
	var engine: MatchEngine = _table(own, theirs)
	assert_array(Choice.options_of(engine.open_prompt())).is_equal(_typed([0, 1, 2, 3]))
	var rng: MatchRng = _stream(engine)
	var live: Array[int] = []
	live.assign(theirs)
	var victims: Array[int] = []
	for _pick: int in range(2):
		var victim: int = live[rng.pick_index(live.size())]
		victims.append(victim)
		live.erase(victim)
	var result: ApplyResult = engine.apply(EngineAction.choose_set(0, OWN_BOARD, _typed([2, 0])))
	assert_bool(result.ok).is_true()
	var made: Array[MatchEvent] = _of_kind(result.events, MADE)
	assert_int(made.size()).is_equal(1)
	assert_array(made[0].payload["indices"]).is_equal([2, 0])
	assert_int(_payload_int(made[0], "index")).is_equal(-1)
	assert_int(made[0].owner_seat).is_equal(PUBLIC)
	var expected: Array[int] = [own[0], own[2], victims[0], victims[1]]
	assert_array(_cards_of(result.events, DESTROYED)).is_equal(expected)
	var seats: Array[int] = []
	for event: MatchEvent in _of_kind(result.events, DESTROYED):
		seats.append(_payload_int(event, "seat"))
		assert_int(event.owner_seat).is_equal(PUBLIC)
	assert_array(seats).is_equal(_typed([0, 0, 1, 1]))
	# Turn end piled them; the unchosen and the third opponent card stayed on the rows.
	var state: MatchState = engine._state
	assert_array(state.seats[0].destroyed).is_equal(_typed([own[0], own[2]]))
	assert_array(_sorted(state.seats[1].destroyed)).is_equal(_sorted(victims))
	assert_array(state.seats[0].board).is_equal(_typed([own[1], own[3], source]))
	assert_array(state.seats[1].board).is_equal(live)


## R27: with one live opponent card (the other already destroyed), a set of two destroys
## both own cards and that one card only.
func test_one_live_opponent_card_is_the_only_one_destroyed() -> void:
	var engine: MatchEngine = _engine(SEED)
	var wreck: int = _id(1, C08)
	var target: int = _id(1, C04)
	engine._state.card_state_for(wreck).destroyed = true
	var source: int = _id(0, C02_SACRIFICE)
	var own: Array[int] = [_id(0, C04), _id(0, C08), source]
	assert_bool(FixtureDecks.play_table(engine, own, _typed([wreck, target]))).is_true()
	var result: ApplyResult = engine.apply(EngineAction.choose_set(0, OWN_BOARD, _typed([0, 1])))
	assert_bool(result.ok).is_true()
	var expected: Array[int] = [own[0], own[1], target]
	assert_array(_cards_of(result.events, DESTROYED)).is_equal(expected)
	assert_array(_sorted(engine._state.seats[1].destroyed)).is_equal(
		_sorted(_typed([wreck, target]))
	)


# --- Previews (P7, P13, R35) -------------------------------------------------------------


## preview_set() mirrors preview_choice(): [] for a bad set, another seat or a single
## answer; a pair for a valid set, the empty one included, with no change to the state or
## the stream; the empty set's preview equals the live turn's scores.
func test_preview_set_scores_a_set_without_touching_the_match() -> void:
	var source: int = _id(0, C02_SACRIFICE)
	var own: Array[int] = [_id(0, C04), _id(0, C08), source]
	var engine: MatchEngine = _table(own, _typed([_id(1, C04), _id(1, C08)]))
	var before: Dictionary = engine.full_state()
	assert_array(engine.preview_set(0, _typed([0, 0]))).is_empty()
	assert_array(engine.preview_set(0, _typed([2]))).is_empty()
	assert_array(engine.preview_set(1, _none())).is_empty()
	assert_array(engine.preview_choice(0, 0)).is_empty()
	assert_int(engine.preview_set(0, _typed([0, 1])).size()).is_equal(2)
	var declined: Array[int] = engine.preview_set(0, _none())
	assert_int(declined.size()).is_equal(2)
	assert_dict(engine.full_state()).is_equal(before)
	var result: ApplyResult = engine.apply(EngineAction.choose_set(0, OWN_BOARD, _none()))
	assert_bool(result.ok).is_true()
	assert_array(_turn_scores(result.events)).is_equal(declined)


## PreviewPolicy declines a multi-select met inside a preview's walk: the walk never pauses
## and nothing is destroyed.
func test_a_preview_walk_declines_a_nested_multi_select() -> void:
	var other: int = _id(0, C04)
	var source: int = _id(0, C02_SACRIFICE)
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].board.assign([other, source])
	state.seats[1].board.assign([_id(1, C04)])
	ScoreWalk.begin(state)
	var policy: PreviewPolicy = PreviewPolicy.new()
	assert_bool(ScoreWalk.run(state, _defs(), null, Callable(), policy)).is_false()
	assert_dict(state.prompt).is_empty()
	assert_bool(state.is_destroyed(other)).is_false()
	assert_bool(state.is_destroyed(_id(1, C04))).is_false()
	assert_array(policy.set_for(_typed([0, 1]))).is_empty()


# --- Replay (R24, P7) -------------------------------------------------------------------


## A fixture match whose turn 2 has seat 0 commit an effect-free cost-1 card then c02, and
## seat 1 its c03 and c04 in hand: c02's prompt opens through commits alone. Null when no
## seed in range deals seat 0 both by turn 2.
func _logged_prompt() -> MatchEngine:
	var source: int = _id(0, C02_SACRIFICE)
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _engine(match_seed)
		_pass_to_turn(engine, 2)
		var hand: Array[int] = []
		hand.assign(engine._state.seats[0].hand)
		var fodder: int = _id(0, C04)
		if not hand.has(fodder):
			fodder = _id(0, C03)
		if not (hand.has(source) and hand.has(fodder)):
			continue
		var theirs: Array[int] = []
		for index: int in [C03, C04]:
			if engine._state.seats[1].hand.has(_id(1, index)):
				theirs.append(_id(1, index))
		for _step: int in range(2):
			var seat: int = engine.awaited_seat()
			var cards: Array[int] = []
			if seat == 0:
				cards.assign([fodder, source])
			else:
				cards.assign(theirs)
			if not engine.apply(EngineAction.commit(seat, cards)).ok:
				break
		if not engine.open_prompt().is_empty():
			return engine
	return null


## R24, P7: the log holds the set as {"k":"choose_set",...} and a fresh engine replaying it
## reaches an equal state, the stream's random destroys included.
func test_the_log_replays_the_set() -> void:
	var engine: MatchEngine = _logged_prompt()
	assert_object(engine).override_failure_message("no seed deals c02 by turn 2").is_not_null()
	if engine == null:
		return
	assert_bool(Choice.is_multi_prompt(engine.open_prompt())).is_true()
	assert_bool(engine.apply(EngineAction.choose_set(0, OWN_BOARD, _typed([0]))).ok).is_true()
	assert_bool(_pass(engine).ok).is_true()
	var text: String = engine.action_log().to_json()
	var entry: String = '{"k":"choose_set","s":0,"z":%d,"i":[0]}' % OWN_BOARD
	assert_bool(text.contains(entry)).override_failure_message(text).is_true()
	var parsed: ActionLog = ActionLog.from_json(text)
	assert_object(parsed).is_not_null()
	if parsed == null:
		return
	var replayed: ReplayResult = parsed.replay(_db(), FixtureDecks.decks())
	assert_bool(replayed.ok).is_true()
	if not replayed.ok:
		return
	assert_dict(replayed.engine.full_state()).is_equal(engine.full_state())
	assert_str(replayed.engine.action_log().to_json()).is_equal(text)
