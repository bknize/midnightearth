# gdlint: disable=max-public-methods
class_name TestEffectsRuin
extends GdUnitTestSuite
## The Ruin verbs (DC-07 T05, T06; R22-R27, R30-R32, R35, plan P7-P10, P12): sacrifice_destroy's
## multi-select prompt over the owner's other live cards, the chosen cards destroyed and as
## many random live opponent cards from the engine stream, fewer when fewer are live, the
## previews of a set (MatchEngine.preview_set) and the decline of a nested one
## (PreviewPolicy), and replay of a log holding a set.
##
## No shipped card sacrifices yet, so the fixture's c02 (cost 1, flat 2) is given an
## on-reveal sacrifice_destroy in memory (FixtureDecks.sacrifice_cards). Tables are set by
## hand on a started fixture match (FixtureDecks.play_table), except for the replay case,
## which reaches the prompt through commits alone. Instance id = seat * DECK_SIZE + index.
## Every destroy goes through EffectResolver.destroy() (P9, T06).
##
## T06's cases (the second half) run on the Ruin deck built in memory from the plan's table
## (FixtureDecks.ruin_defs(), Ruin on both seats) and build MatchStates directly: the
## un-reveal of Phoenix (in a sacrifice, face down, ahead of and behind the cursor), Fuse's
## burst (opponent scores and a copy-like stat change), Ember's discard, Tallow's leftmost
## destroy, Glutton's flat gain, Butcher's draw and Rat's draw on each opponent reveal.

const SEED: int = 1
const SEARCH_SEEDS: int = 200
const MAX_PASSES: int = 60

# Definition indices in the fixture card list (all effect-free but c02).
const C02_SACRIFICE: int = FixtureDecks.C02_SACRIFICE
const C03: int = 2
const C04: int = 3
const C07: int = 6
const C08: int = 7

# Ruin deck indices (= instance index within a seat).
const R01_SCRAP: int = FixtureDecks.R01_SCRAP
const R02_TINDER: int = FixtureDecks.R02_TINDER
const R03_EMBER: int = FixtureDecks.R03_EMBER
const R04_SHARD: int = FixtureDecks.R04_SHARD
const R05_TALLOW: int = FixtureDecks.R05_TALLOW
const R06_FUSE: int = FixtureDecks.R06_FUSE
const R07_RAT: int = FixtureDecks.R07_RAT
const R09_WICK: int = FixtureDecks.R09_WICK
const R10_BUTCHER: int = FixtureDecks.R10_BUTCHER
const R12_PYRE: int = FixtureDecks.R12_PYRE
const R13_PHOENIX: int = FixtureDecks.R13_PHOENIX
const R14_GLUTTON: int = FixtureDecks.R14_GLUTTON
const R15_WRECK: int = FixtureDecks.R15_WRECK
const R16_IMMOLATOR: int = FixtureDecks.R16_IMMOLATOR
const R18_REAPER: int = FixtureDecks.R18_REAPER
## Seeds tried for the burst's random destroy; two must pick different cards.
const PICK_SEEDS: int = 20
const MAX_STEPS: int = 100

const PUBLIC: int = MatchEvent.PUBLIC
const HIDDEN: int = MatchEvent.HIDDEN_CARD
const OWN_BOARD: int = Choice.Zone.OWN_BOARD
const REQUESTED: int = MatchEvent.Kind.CHOICE_REQUESTED
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const DESTROYED: int = MatchEvent.Kind.CARD_DESTROYED
const TURN_ENDED: int = MatchEvent.Kind.TURN_ENDED
const UNREVEALED: int = MatchEvent.Kind.CARD_UNREVEALED
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.EFFECT_FIRED
const FIZZLED: int = MatchEvent.Kind.EFFECT_FIZZLED
const STATS: int = MatchEvent.Kind.STATS_CHANGED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const BURNED: int = MatchEvent.Kind.CARD_BURNED
const DISCARDED: int = MatchEvent.Kind.CARD_DISCARDED

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null
var _cached_ruin: MatchCards = null

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


# --- T06 helpers (the Ruin deck in memory) ---------------------------------------------


func _ruin() -> MatchCards:
	if _cached_ruin == null:
		_cached_ruin = FixtureDecks.ruin_defs()
	return _cached_ruin


## A state with these rows (seat 0, seat 1), nothing revealed, `first` committing first.
func _rows(row_0: Array[int], row_1: Array[int], first: int) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = first
	state.seats[0].board.assign(row_0)
	state.seats[1].board.assign(row_1)
	return state


func _reveal(state: MatchState, seat: int, cards: Array[int]) -> void:
	for card: int in cards:
		state.seats[seat].revealed[card] = true


## Runs one live walk on `state` over the Ruin definitions, from begin() to its end, with
## `rng` as the engine stream, recording its events; it must not pause.
func _walk(state: MatchState, rng: MatchRng, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		var paused: bool = ScoreWalk.step(state, _ruin(), rng, recorder.record, null)
		assert_bool(paused).is_false()
		guard += 1


func _kinds(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		out.append(event.kind)
	return out


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


func _fired(seat: int, card: int, verb: String, trigger: String) -> Dictionary:
	return {"seat": seat, "card": card, "verb": verb, "trigger": trigger}


func _stats(seat: int, card: int, flat: int, times: int, cause: String) -> Dictionary:
	return {"seat": seat, "card": card, "flat": flat, "times": times, "plus": 0, "cause": cause}


func _made(seat: int, card: int, zone: String, target: int, auto: bool) -> Dictionary:
	return {"seat": seat, "card": card, "zone": zone, "index": 0, "target": target, "auto": auto}


func _entry_int(entry: Dictionary, key: String) -> int:
	var value: int = entry[key]
	return value


func _entry_flag(entry: Dictionary, key: String) -> bool:
	var value: bool = entry[key]
	return value


## Immolator's multi-select prompt on seat 0's row, as the walk would open it.
func _sacrifice_prompt(source: int, options: Array) -> Dictionary:
	return {
		EffectResolver.KEY_SEAT: 0,
		EffectResolver.KEY_CARD: source,
		EffectResolver.KEY_VERB: CardEffect.Verb.SACRIFICE_DESTROY,
		Choice.KEY_ZONE: OWN_BOARD,
		Choice.KEY_OPTIONS: options,
		Choice.KEY_MULTI: true,
	}


## The first `count` random destroys the stream of `match_seed` makes over `row` (all
## live), each over the cards not yet picked (EffectResolver.random_live).
func _picks(match_seed: int, row: Array[int], count: int) -> Array[int]:
	var rng: MatchRng = MatchRng.new(match_seed)
	var live: Array[int] = []
	live.assign(row)
	var out: Array[int] = []
	for _pick: int in range(count):
		if live.is_empty():
			break
		var victim: int = live[rng.pick_index(live.size())]
		out.append(victim)
		live.erase(victim)
	return out


## Seat `seat`'s view of `state` over the Ruin definitions.
func _view(state: MatchState, seat: int) -> SeatView:
	var budgets: Array[int] = [1, 1]
	return SeatView.build(state, seat, 0, budgets, _ruin())


# --- Phoenix: the un-reveal (P9, R30-R32, C9, C18) ----------------------------------------


## Phoenix chosen with Scrap for Immolator's sacrifice flips face down in its slot with
## printed stats (its +2 flat and no-bonus mark gone), live; Scrap, which carries nothing,
## is destroyed (C18); the opponent still loses two (R32); the other seat's view hides
## Phoenix again under the face-down rules.
func test_phoenix_chosen_for_a_sacrifice_unreveals_and_still_counts() -> void:
	var phoenix: int = _id(0, R13_PHOENIX)
	var scrap: int = _id(0, R01_SCRAP)
	var source: int = _id(0, R16_IMMOLATOR)
	var own: Array[int] = [phoenix, scrap, source]
	var theirs: Array[int] = [_id(1, R01_SCRAP), _id(1, R09_WICK), _id(1, R12_PYRE)]
	var state: MatchState = _rows(own, theirs, 0)
	_reveal(state, 0, own)
	var held: CardState = state.card_state_for(phoenix)
	held.flat_delta = 2
	held.no_bonus = true
	var victims: Array[int] = _picks(SEED, theirs, 2)
	var prompt: Dictionary = _sacrifice_prompt(source, [0, 1])
	var events: Array[MatchEvent] = EffectResolver.apply_set(
		state, _ruin(), MatchRng.new(SEED), null, prompt, _typed([0, 1])
	)
	var expected: Array[int] = [MADE, STATS, UNREVEALED, DESTROYED, DESTROYED, DESTROYED]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[1], STATS, _stats(0, phoenix, 3, 125, "unreveal"), PUBLIC)
	_assert_event(events[2], UNREVEALED, {"seat": 0, "card": phoenix, "slot": 0}, PUBLIC)
	_assert_event(events[3], DESTROYED, {"seat": 0, "card": scrap, "slot": 1}, PUBLIC)
	assert_array(_cards_of(events, DESTROYED)).is_equal(_typed([scrap, victims[0], victims[1]]))
	# In its slot, face down, live, with printed stats and no marks.
	assert_array(state.seats[0].board).is_equal(own)
	assert_bool(state.seats[0].is_revealed(phoenix)).is_false()
	assert_bool(state.is_destroyed(phoenix)).is_false()
	assert_object(state.card_state(phoenix)).is_null()
	var stats: Dictionary = ScoreWalk.effective(phoenix, state, _ruin()).to_dict()
	assert_dict(stats).is_equal({"flat": 3, "times": 125, "plus": 0})
	assert_bool(state.is_destroyed(scrap)).is_true()
	for victim: int in victims:
		assert_bool(state.is_destroyed(victim)).is_true()
	# Face down again: the other seat sees a hidden card in that slot.
	var view: SeatView = _view(state, 1)
	assert_int(view.opponent_board[0]).is_equal(HIDDEN)
	var entry: Dictionary = view.opponent_row[0]
	assert_int(_entry_int(entry, "card")).is_equal(HIDDEN)
	assert_int(_entry_int(entry, "flat")).is_equal(0)
	assert_bool(_entry_flag(entry, "revealed")).is_false()
	assert_bool(_entry_flag(entry, "destroyed")).is_false()


## The un-reveal protects a revealed Phoenix only: face down, it is destroyed as any card
## (CARD_DESTROYED, private to its seat), and it still counts for the sacrifice.
func test_a_face_down_phoenix_is_destroyed_normally() -> void:
	var phoenix: int = _id(0, R13_PHOENIX)
	var source: int = _id(0, R16_IMMOLATOR)
	var target: int = _id(1, R01_SCRAP)
	var state: MatchState = _rows(_typed([phoenix, source]), _typed([target]), 0)
	_reveal(state, 0, _typed([source]))
	var events: Array[MatchEvent] = EffectResolver.apply_set(
		state, _ruin(), MatchRng.new(SEED), null, _sacrifice_prompt(source, [0]), _typed([0])
	)
	assert_array(_kinds(events)).is_equal(_typed([MADE, DESTROYED, DESTROYED]))
	_assert_event(events[1], DESTROYED, {"seat": 0, "card": phoenix, "slot": 0}, 0)
	assert_bool(state.is_destroyed(phoenix)).is_true()
	assert_bool(state.seats[0].is_revealed(phoenix)).is_false()
	assert_bool(state.is_destroyed(target)).is_true()


## R30, DC-06 R5, C24: Reaper (seat 1, first) un-reveals seat 0's Phoenix before the cursor
## reaches it; when it does, Phoenix reveals in full again: CARD_REVEALED, the no-bonus
## spend, the opponent's watchers (Rat draws), then its score at printed flat.
func test_phoenix_unrevealed_ahead_of_the_cursor_reveals_in_full_when_reached() -> void:
	var phoenix: int = _id(0, R13_PHOENIX)
	var reaper: int = _id(1, R18_REAPER)
	var rat: int = _id(1, R07_RAT)
	var drawn: int = _id(1, R01_SCRAP)
	var state: MatchState = _rows(_typed([phoenix]), _typed([reaper, rat]), 1)
	_reveal(state, 0, _typed([phoenix]))
	_reveal(state, 1, _typed([rat]))
	state.card_state_for(phoenix).flat_delta = 2
	state.bonus_zero_pending[0] = true
	state.seats[1].deck.assign([drawn])
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [
		REVEALED, FIRED, STATS, UNREVEALED, SCORED, REVEALED, STATS, FIRED, DRAWN, SCORED, SCORED
	]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(
		events[1], FIRED, _fired(1, reaper, "destroy_random_opponent", "on_reveal"), PUBLIC
	)
	_assert_event(events[2], STATS, _stats(0, phoenix, 3, 125, "unreveal"), PUBLIC)
	_assert_event(events[3], UNREVEALED, {"seat": 0, "card": phoenix, "slot": 0}, PUBLIC)
	assert_int(_payload_int(events[4], "card")).is_equal(reaper)
	# The cursor reaches slot 0 of seat 0: a full reveal of the face-down Phoenix.
	assert_int(_payload_int(events[5], "card")).is_equal(phoenix)
	var flagged: bool = events[5].payload["destroyed"]
	assert_bool(flagged).is_false()
	_assert_event(events[6], STATS, _stats(0, phoenix, 3, 100, "bonus_zero"), PUBLIC)
	_assert_event(events[7], FIRED, _fired(1, rat, "draw", "on_opponent_reveal"), PUBLIC)
	_assert_event(events[8], DRAWN, {"seat": 1, "card": drawn}, 1)
	assert_int(_payload_int(events[9], "card")).is_equal(phoenix)
	assert_int(_payload_int(events[9], "flat")).is_equal(3)
	assert_int(_payload_int(events[10], "card")).is_equal(rat)
	assert_bool(state.seats[0].is_revealed(phoenix)).is_true()
	assert_bool(state.is_destroyed(phoenix)).is_false()
	assert_array(state.seats[1].hand).is_equal(_typed([drawn]))


## R30, DC-06 R8: Phoenix scores at slot 0, then Reaper (seat 1, second) un-reveals it
## behind the cursor; it stays face down for the rest of the walk and reveals in full when
## the next walk reaches it.
func test_phoenix_unrevealed_behind_the_cursor_stays_down_until_the_next_walk() -> void:
	var phoenix: int = _id(0, R13_PHOENIX)
	var reaper: int = _id(1, R18_REAPER)
	var state: MatchState = _rows(_typed([phoenix]), _typed([reaper]), 0)
	_reveal(state, 0, _typed([phoenix]))
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	# No STATS_CHANGED: Phoenix had no modifiers, so its shown stats did not change.
	assert_array(_kinds(events)).is_equal(_typed([SCORED, REVEALED, FIRED, UNREVEALED, SCORED]))
	assert_int(_payload_int(events[0], "card")).is_equal(phoenix)
	_assert_event(events[3], UNREVEALED, {"seat": 0, "card": phoenix, "slot": 0}, PUBLIC)
	assert_bool(state.seats[0].is_revealed(phoenix)).is_false()
	assert_bool(state.is_destroyed(phoenix)).is_false()
	assert_int(_entry_int(_view(state, 1).opponent_row[0], "card")).is_equal(HIDDEN)
	# The next walk reveals it in full and scores it; Reaper, already face up, only scores.
	var next: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), next)
	assert_array(_kinds(next.events)).is_equal(_typed([REVEALED, SCORED, SCORED]))
	assert_array(_cards_of(next.events, SCORED)).is_equal(_typed([phoenix, reaper]))
	var flagged: bool = next.events[0].payload["destroyed"]
	assert_bool(flagged).is_false()
	assert_bool(state.seats[0].is_revealed(phoenix)).is_true()


# --- Fuse: the burst (P10, R26, R27, R35, C10) ----------------------------------------------


## Seat 0's Fuse (flat 1) gains +1 after each of seat 1's scores (not after its own seat's
## Scrap), and on the fourth, at flat 5, destroys itself and then one random live card of
## seat 1's row, the stream's first draw over its five cards. Nothing fires it after.
func test_fuse_gains_one_per_opponent_score_and_bursts_at_five() -> void:
	var fuse: int = _id(0, R06_FUSE)
	var own_scrap: int = _id(0, R01_SCRAP)
	var theirs: Array[int] = [
		_id(1, R01_SCRAP), _id(1, R02_TINDER), _id(1, R04_SHARD), _id(1, R09_WICK), _id(1, R12_PYRE)
	]
	var picks: Dictionary = {}
	for match_seed: int in range(1, PICK_SEEDS + 1):
		var state: MatchState = _rows(_typed([fuse, own_scrap]), theirs, 0)
		_reveal(state, 0, _typed([fuse, own_scrap]))
		var recorder: Recorder = Recorder.new()
		_walk(state, MatchRng.new(match_seed), recorder)
		var events: Array[MatchEvent] = recorder.events
		var victim: int = _picks(match_seed, theirs, 1)[0]
		picks[victim] = true
		var fired: Array[MatchEvent] = _of_kind(events, FIRED)
		assert_int(fired.size()).is_equal(4)
		for event: MatchEvent in fired:
			assert_dict(event.payload).is_equal(_fired(0, fuse, "burst", "on_opponent_score"))
		var flats: Array[int] = []
		for event: MatchEvent in _of_kind(events, STATS):
			var cause: String = event.payload["cause"]
			assert_str(cause).is_equal("opponent_score")
			assert_int(_payload_int(event, "card")).is_equal(fuse)
			flats.append(_payload_int(event, "flat"))
		assert_array(flats).is_equal(_typed([2, 3, 4, 5]))
		assert_array(_cards_of(events, DESTROYED)).is_equal(_typed([fuse, victim]))
		assert_int(_of_kind(events, DESTROYED)[0].owner_seat).is_equal(PUBLIC)
		assert_bool(state.is_destroyed(fuse)).is_true()
		assert_bool(state.is_destroyed(victim)).is_true()
		# Each +1 follows a seat-1 score: the event before every firing is that score.
		for at: int in range(1, events.size()):
			if events[at].kind != FIRED:
				continue
			assert_int(events[at - 1].kind).is_equal(SCORED)
			assert_int(_payload_int(events[at - 1], "seat")).is_equal(1)
	assert_int(picks.size()).is_greater(1)


## P10: the burst check runs after any stat change of a revealed burst card, not only the
## opponent-score +1. T07's copy is simulated by setting Fuse's flat delta and calling the
## check: below 5 nothing happens and the stream is untouched; at 5 it destroys itself and
## a random live opponent card; with no live opponent card, only itself (no draw); face
## down, nothing.
func test_a_stat_change_to_five_bursts_fuse_too() -> void:
	var fuse: int = _id(0, R06_FUSE)
	var theirs: Array[int] = [_id(1, R01_SCRAP), _id(1, R09_WICK)]
	var state: MatchState = _rows(_typed([fuse]), theirs, 0)
	_reveal(state, 0, _typed([fuse]))
	_reveal(state, 1, theirs)
	var rng: MatchRng = MatchRng.new(SEED)
	var stream: int = rng.state
	state.card_state_for(fuse).flat_delta = 3
	var below: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(RuinEffects.check_burst(state, _ruin(), rng, null, fuse, below)).is_false()
	assert_array(below.events).is_empty()
	assert_int(rng.state).is_equal(stream)
	state.card_state_for(fuse).flat_delta = 4
	var copied: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(RuinEffects.check_burst(state, _ruin(), rng, null, fuse, copied)).is_true()
	var victim: int = _picks(SEED, theirs, 1)[0]
	assert_array(_cards_of(copied.events, DESTROYED)).is_equal(_typed([fuse, victim]))
	assert_bool(state.is_destroyed(fuse)).is_true()
	assert_bool(state.is_destroyed(victim)).is_true()
	# No live opponent card: only itself, and nothing drawn from the stream.
	var alone: MatchState = _rows(_typed([fuse]), _typed([_id(1, R01_SCRAP)]), 0)
	_reveal(alone, 0, _typed([fuse]))
	alone.card_state_for(fuse).flat_delta = 4
	alone.card_state_for(_id(1, R01_SCRAP)).destroyed = true
	var lone_rng: MatchRng = MatchRng.new(SEED)
	var lone_stream: int = lone_rng.state
	var lone: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(RuinEffects.check_burst(alone, _ruin(), lone_rng, null, fuse, lone)).is_true()
	assert_array(_cards_of(lone.events, DESTROYED)).is_equal(_typed([fuse]))
	assert_int(lone_rng.state).is_equal(lone_stream)
	# Face down at 5: not a revealed burst card, so nothing.
	var hidden: MatchState = _rows(_typed([fuse]), theirs, 0)
	hidden.card_state_for(fuse).flat_delta = 4
	var down: EffectResolver.Outcome = EffectResolver.Outcome.new()
	assert_bool(RuinEffects.check_burst(hidden, _ruin(), rng, null, fuse, down)).is_false()
	assert_bool(hidden.is_destroyed(fuse)).is_false()


# --- Ember, Tallow, Glutton, Butcher, Rat (P8, P12, R27, C17) ----------------------------


## C17: Ember's discard with an empty hand fizzles, and Ember still scores.
func test_a_discard_with_an_empty_hand_fizzles_and_the_card_scores() -> void:
	var ember: int = _id(0, R03_EMBER)
	var state: MatchState = _rows(_typed([ember]), _none(), 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))
	_assert_event(events[2], FIZZLED, {"seat": 0, "card": ember, "verb": "discard_own"}, PUBLIC)
	assert_int(_payload_int(events[3], "card")).is_equal(ember)
	assert_int(_payload_int(events[3], "added")).is_equal(4)


## P12: one card in hand is chosen at once (CHOICE_MADE auto, private) and discarded to the
## burn pile (CARD_DISCARDED, private); Ember scores.
func test_a_discard_with_one_card_in_hand_takes_it() -> void:
	var ember: int = _id(0, R03_EMBER)
	var spare: int = _id(0, R01_SCRAP)
	var state: MatchState = _rows(_typed([ember]), _none(), 0)
	state.seats[0].hand.assign([spare])
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, MADE, DISCARDED, SCORED]))
	_assert_event(events[2], MADE, _made(0, ember, "own_hand", spare, true), 0)
	_assert_event(events[3], DISCARDED, {"seat": 0, "card": spare}, 0)
	assert_array(state.seats[0].hand).is_empty()
	assert_array(state.seats[0].burned).is_equal(_typed([spare]))


## Tallow alone on its row has no other card to destroy: it fizzles and scores.
func test_tallow_with_no_other_card_fizzles() -> void:
	var tallow: int = _id(0, R05_TALLOW)
	var state: MatchState = _rows(_typed([tallow]), _none(), 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))
	var fizzled: Dictionary = {"seat": 0, "card": tallow, "verb": "destroy_leftmost_own"}
	_assert_event(events[2], FIZZLED, fizzled, PUBLIC)
	# Only destroyed cards beside it: fizzles too (P12).
	var wreck: int = _id(0, R15_WRECK)
	var wrecked: MatchState = _rows(_typed([wreck, tallow]), _none(), 0)
	_reveal(wrecked, 0, _typed([wreck]))
	wrecked.card_state_for(wreck).destroyed = true
	var again: Recorder = Recorder.new()
	_walk(wrecked, MatchRng.new(SEED), again)
	assert_array(_kinds(again.events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))


## Tallow destroys the leftmost live other card: a destroyed Wreck on slot 0 is skipped,
## the revealed Scrap on slot 1 is destroyed (public).
func test_tallow_destroys_the_leftmost_live_other_card() -> void:
	var wreck: int = _id(0, R15_WRECK)
	var scrap: int = _id(0, R01_SCRAP)
	var tallow: int = _id(0, R05_TALLOW)
	var state: MatchState = _rows(_typed([wreck, scrap, tallow]), _none(), 0)
	_reveal(state, 0, _typed([wreck, scrap]))
	state.card_state_for(wreck).destroyed = true
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([SCORED, REVEALED, FIRED, DESTROYED, SCORED]))
	_assert_event(events[3], DESTROYED, {"seat": 0, "card": scrap, "slot": 1}, PUBLIC)
	assert_bool(state.is_destroyed(scrap)).is_true()


## Glutton (flat 2) destroys the only other live card, Scrap at effective flat 3 (2 + 1),
## and gains 3: STATS_CHANGED (flat_up) at flat 5, and it scores 5.
func test_glutton_gains_the_targets_effective_flat() -> void:
	var scrap: int = _id(0, R01_SCRAP)
	var glutton: int = _id(0, R14_GLUTTON)
	var state: MatchState = _rows(_typed([scrap, glutton]), _none(), 0)
	_reveal(state, 0, _typed([scrap]))
	state.card_state_for(scrap).flat_delta = 1
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [SCORED, REVEALED, FIRED, MADE, DESTROYED, STATS, SCORED]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[3], MADE, _made(0, glutton, "own_board", scrap, true), PUBLIC)
	_assert_event(events[4], DESTROYED, {"seat": 0, "card": scrap, "slot": 0}, PUBLIC)
	_assert_event(events[5], STATS, _stats(0, glutton, 5, 100, "flat_up"), PUBLIC)
	assert_int(_payload_int(events[6], "card")).is_equal(glutton)
	assert_int(_payload_int(events[6], "flat")).is_equal(5)
	assert_int(ScoreWalk.effective(glutton, state, _ruin()).flat).is_equal(5)


## The flat is read before the destroy: Glutton eating a revealed Phoenix at flat 5 (3 + 2)
## gains 5, though the un-reveal resets Phoenix to its printed 3 (P9).
func test_glutton_eating_phoenix_gains_its_flat_before_the_unreveal() -> void:
	var phoenix: int = _id(0, R13_PHOENIX)
	var glutton: int = _id(0, R14_GLUTTON)
	var state: MatchState = _rows(_typed([phoenix, glutton]), _none(), 0)
	_reveal(state, 0, _typed([phoenix, glutton]))
	state.card_state_for(phoenix).flat_delta = 2
	var prompt: Dictionary = {
		EffectResolver.KEY_SEAT: 0,
		EffectResolver.KEY_CARD: glutton,
		EffectResolver.KEY_VERB: CardEffect.Verb.DESTROY_OWN_THEN_FLAT_UP,
		Choice.KEY_ZONE: OWN_BOARD,
		Choice.KEY_OPTIONS: [0],
		Choice.KEY_MULTI: false,
	}
	var events: Array[MatchEvent] = EffectResolver.apply_choice(state, _ruin(), prompt, 0, true)
	assert_array(_kinds(events)).is_equal(_typed([MADE, STATS, UNREVEALED, STATS]))
	_assert_event(events[3], STATS, _stats(0, glutton, 7, 100, "flat_up"), PUBLIC)
	assert_bool(state.is_destroyed(phoenix)).is_false()
	assert_int(ScoreWalk.effective(phoenix, state, _ruin()).flat).is_equal(3)


## Butcher destroys the only other live card and draws 2 (private draws).
func test_butcher_destroys_then_draws_two() -> void:
	var scrap: int = _id(0, R01_SCRAP)
	var butcher: int = _id(0, R10_BUTCHER)
	var first: int = _id(0, R02_TINDER)
	var second: int = _id(0, R04_SHARD)
	var state: MatchState = _rows(_typed([scrap, butcher]), _none(), 0)
	_reveal(state, 0, _typed([scrap]))
	state.seats[0].deck.assign([first, second])
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [SCORED, REVEALED, FIRED, MADE, DESTROYED, DRAWN, DRAWN, SCORED]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[5], DRAWN, {"seat": 0, "card": first}, 0)
	_assert_event(events[6], DRAWN, {"seat": 0, "card": second}, 0)
	assert_array(state.seats[0].hand).is_equal(_typed([first, second]))
	assert_bool(state.is_destroyed(scrap)).is_true()


## Rat (revealed, seat 0) draws on each of seat 1's reveals; the second draw meets a full
## hand (HAND_CAP) and burns (R25).
func test_rat_draws_on_each_opponent_reveal_and_burns_at_the_cap() -> void:
	var rat: int = _id(0, R07_RAT)
	var theirs: Array[int] = [_id(1, R01_SCRAP), _id(1, R02_TINDER)]
	var state: MatchState = _rows(_typed([rat]), theirs, 0)
	_reveal(state, 0, _typed([rat]))
	var hand: Array[int] = []
	for index: int in range(MatchRules.HAND_CAP - 1):
		hand.append(_id(0, index))
	state.seats[0].hand.assign(hand)
	var first: int = _id(0, R09_WICK)
	var second: int = _id(0, R12_PYRE)
	state.seats[0].deck.assign([first, second])
	var recorder: Recorder = Recorder.new()
	_walk(state, MatchRng.new(SEED), recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [
		SCORED, REVEALED, FIRED, DRAWN, SCORED, REVEALED, FIRED, BURNED, SCORED
	]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[2], FIRED, _fired(0, rat, "draw", "on_opponent_reveal"), PUBLIC)
	_assert_event(events[3], DRAWN, {"seat": 0, "card": first}, 0)
	_assert_event(events[7], BURNED, {"seat": 0, "card": second}, 0)
	assert_int(state.seats[0].hand.size()).is_equal(MatchRules.HAND_CAP)
	assert_array(state.seats[0].burned).is_equal(_typed([second]))


class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
