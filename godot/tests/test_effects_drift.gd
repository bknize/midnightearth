# gdlint: disable=max-public-methods
class_name TestEffectsDrift
extends GdUnitTestSuite
## The Drift verbs (DC-07 T07; R26, R28, R29, R33, R34, plan P5, P11, P12, C11): the moves
## through one row rewrite (CARD_MOVED per card whose slot changed, then ON_MOVED once per
## moved revealed live card) under the DC-06 slot cursor, the copy, the positional ×-parts
## of Lodestone and Herald in ScoreWalk.effective(), and Eddy's +2 until the walk ends.
##
## The Drift deck is built in memory from the plan's table (FixtureDecks.drift_defs(), Drift
## on both seats); instance id = seat * DECK_SIZE + the D* index. States are built directly.

const SEED: int = 1
const MAX_STEPS: int = 100

const D01_GUST: int = FixtureDecks.D01_GUST
const D02_SPRITE: int = FixtureDecks.D02_SPRITE
const D03_SCOUT: int = FixtureDecks.D03_SCOUT
const D04_PEBBLE: int = FixtureDecks.D04_PEBBLE
const D05_EDDY: int = FixtureDecks.D05_EDDY
const D07_MIRROR: int = FixtureDecks.D07_MIRROR
const D08_TIDE: int = FixtureDecks.D08_TIDE
const D09_SHEPHERD: int = FixtureDecks.D09_SHEPHERD
const D10_LODESTONE: int = FixtureDecks.D10_LODESTONE
const D12_HERALD: int = FixtureDecks.D12_HERALD
const D13_HOOK: int = FixtureDecks.D13_HOOK
const D14_KEEL: int = FixtureDecks.D14_KEEL
const D15_UNDERTOW: int = FixtureDecks.D15_UNDERTOW
const D17_TEMPEST: int = FixtureDecks.D17_TEMPEST
const D18_VANE: int = FixtureDecks.D18_VANE
const D19_MAELSTROM: int = FixtureDecks.D19_MAELSTROM

const PUBLIC: int = MatchEvent.PUBLIC
const HIDDEN: int = MatchEvent.HIDDEN_CARD
const OPPONENT_BOARD: int = Choice.Zone.OPPONENT_BOARD
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const MOVED: int = MatchEvent.Kind.CARD_MOVED
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.EFFECT_FIRED
const STATS: int = MatchEvent.Kind.STATS_CHANGED

var _cached_drift: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _drift() -> MatchCards:
	if _cached_drift == null:
		_cached_drift = FixtureDecks.drift_defs()
	return _cached_drift


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


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


## Runs one live walk on `state` over the Drift definitions, from begin() to its end; it
## must not pause.
func _walk(state: MatchState, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		var paused: bool = ScoreWalk.step(
			state, _drift(), MatchRng.new(SEED), recorder.record, null
		)
		assert_bool(paused).is_false()
		guard += 1


## Fires `card`'s effect for `seat` as a live walk would, with no stream.
func _fire(state: MatchState, seat: int, card: int) -> Array[MatchEvent]:
	return EffectResolver.apply(state, _drift(), null, null, seat, card).events


## The prompt `verb` of `source` (seat 0) would open over OPPONENT_BOARD with `options`.
func _prompt(source: int, verb: int, options: Array[int]) -> Dictionary:
	return {
		EffectResolver.KEY_SEAT: 0,
		EffectResolver.KEY_CARD: source,
		EffectResolver.KEY_VERB: verb,
		Choice.KEY_ZONE: OPPONENT_BOARD,
		Choice.KEY_OPTIONS: MatchState.plain(options),
		Choice.KEY_MULTI: false,
	}


func _options(state: MatchState, verb: int, source: int) -> Array[int]:
	var found: Dictionary = Choice.eligible(state, 0, verb, source)
	var zone: int = found[Choice.KEY_ZONE]
	assert_int(zone).is_equal(OPPONENT_BOARD)
	return Choice.options_of(found)


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


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _cards_of(events: Array[MatchEvent], kind: int) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, kind):
		out.append(_payload_int(event, "card"))
	return out


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


func _moved(seat: int, card: int, from_slot: int, to_slot: int) -> Dictionary:
	return {"seat": seat, "card": card, "from_slot": from_slot, "to_slot": to_slot}


func _fired(seat: int, card: int, verb: String, trigger: String) -> Dictionary:
	# Cycle 8 P7: every EFFECT_FIRED carries `uses_left`, -1 for an unlimited effect.
	return {"seat": seat, "card": card, "verb": verb, "trigger": trigger, "uses_left": -1}


func _stats(seat: int, card: int, stats: Array, cause: String) -> Dictionary:
	return {
		"seat": seat,
		"card": card,
		"flat": stats[0],
		"times": stats[1],
		"plus": stats[2],
		# Cycle 8 P4: every STATS_CHANGED carries the effective cost and `permanent`.
		"cost": _drift().def_of(card).cost,
		"permanent": false,
		"cause": cause,
	}


func _eff(card: int, state: MatchState) -> Dictionary:
	return ScoreWalk.effective(card, state, _drift()).to_dict()


func _flat_times_plus(flat: int, times: int, plus: int) -> Dictionary:
	return {"flat": flat, "times": times, "plus": plus}


## The number of ON_MOVED firings in `events`.
func _on_moved_firings(events: Array[MatchEvent]) -> int:
	var count: int = 0
	for event: MatchEvent in _of_kind(events, FIRED):
		var trigger: String = event.payload["trigger"]
		if trigger == "on_moved":
			count += 1
	return count


# --- The reverse under the cursor (R29, DC-06 R5-R8) --------------------------------------


## The spec's scenario: seat 1 (first) has [A, B, C] and has scored A and B (cursor 2) when
## seat 0's Tempest flips. The row becomes [C, B, A]: C on slot 0 and B on slot 1 are behind
## the cursor and do not score again (C stays face down, R8), A on slot 2 scores again when
## reached. C's move is private to seat 1; A's is public.
func test_reverse_with_cursor_two_skips_c_and_b_and_scores_a_again() -> void:
	var a: int = _id(1, D01_GUST)
	var b: int = _id(1, D04_PEBBLE)
	var c: int = _id(1, D14_KEEL)
	var tempest: int = _id(0, D17_TEMPEST)
	var gust: int = _id(0, D01_GUST)
	var state: MatchState = _rows(_typed([gust, tempest]), _typed([a, b, c]), 1)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [
		REVEALED,
		SCORED,
		REVEALED,
		SCORED,
		REVEALED,
		SCORED,
		REVEALED,
		FIRED,
		MOVED,
		MOVED,
		SCORED,
		SCORED
	]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[7], FIRED, _fired(0, tempest, "reverse_opponent_row", "on_reveal"), PUBLIC)
	_assert_event(events[8], MOVED, _moved(1, c, 2, 0), 1)
	_assert_event(events[9], MOVED, _moved(1, a, 0, 2), PUBLIC)
	assert_array(state.seats[1].board).is_equal(_typed([c, b, a]))
	# Seat 1 scored A, B, then A again on slot 2; C never.
	var seat_1: Array[int] = []
	for event: MatchEvent in _of_kind(events, SCORED):
		if _payload_int(event, "seat") == 1:
			seat_1.append(_payload_int(event, "card"))
	assert_array(seat_1).is_equal(_typed([a, b, a]))
	var last: MatchEvent = events[11]
	assert_int(_payload_int(last, "slot")).is_equal(2)
	var again: bool = last.payload["again"]
	assert_bool(again).is_true()
	assert_bool(state.seats[1].is_revealed(c)).is_false()
	assert_int(state.scores[1]).is_equal(7)
	# Seat 0 sees which slots moved, never C's id.
	assert_int(_payload_int(events[8].redacted_for(0), "card")).is_equal(HIDDEN)
	assert_int(_payload_int(events[8].redacted_for(1), "card")).is_equal(c)
	var view: SeatView = _view(state, 0)
	assert_array(view.opponent_board).is_equal(_typed([HIDDEN, b, a]))


# --- Shift (P11) ------------------------------------------------------------------------


## Undertow on slot 2 of [Gust, Pebble, Undertow, Tide]: the other cards rotate left by one
## over the slots Undertow does not hold, so the row is [Pebble, Tide, Undertow, Gust];
## Undertow keeps its slot and gets no CARD_MOVED; face-down Pebble's move is private.
func test_shift_keeps_the_source_slot_and_wraps_the_leftmost() -> void:
	var gust: int = _id(0, D01_GUST)
	var pebble: int = _id(0, D04_PEBBLE)
	var undertow: int = _id(0, D15_UNDERTOW)
	var tide: int = _id(0, D08_TIDE)
	var state: MatchState = _rows(_typed([gust, pebble, undertow, tide]), _typed([]), 0)
	_reveal(state, 0, _typed([gust, undertow, tide]))
	var events: Array[MatchEvent] = _fire(state, 0, undertow)
	assert_array(_kinds(events)).is_equal(_typed([FIRED, MOVED, MOVED, MOVED]))
	_assert_event(events[1], MOVED, _moved(0, pebble, 1, 0), 0)
	_assert_event(events[2], MOVED, _moved(0, tide, 3, 1), PUBLIC)
	_assert_event(events[3], MOVED, _moved(0, gust, 0, 3), PUBLIC)
	assert_array(state.seats[0].board).is_equal(_typed([pebble, tide, undertow, gust]))
	# Alone, or with one other card, nothing moves.
	var alone: MatchState = _rows(_typed([gust, undertow]), _typed([]), 0)
	assert_array(_kinds(_fire(alone, 0, undertow))).is_equal(_typed([FIRED]))
	assert_array(alone.seats[0].board).is_equal(_typed([gust, undertow]))


# --- Hook and Maelstrom (P12) -------------------------------------------------------------


## Hook offers every opponent position but slot 0, face down included; choosing face-down
## Pebble on slot 1 puts it on slot 0 by position. CHOICE_MADE and its CARD_MOVED are
## private to seat 1, so seat 0's copies and view never name it, and it stays face down.
func test_hook_moves_a_face_down_card_by_position() -> void:
	var hook: int = _id(0, D13_HOOK)
	var gust: int = _id(1, D01_GUST)
	var pebble: int = _id(1, D04_PEBBLE)
	var tide: int = _id(1, D08_TIDE)
	var state: MatchState = _rows(_typed([hook]), _typed([gust, pebble, tide]), 0)
	_reveal(state, 0, _typed([hook]))
	_reveal(state, 1, _typed([gust, tide]))
	var options: Array[int] = _options(state, CardEffect.Verb.MOVE_OPPONENT_LEFT, hook)
	assert_array(options).is_equal(_typed([1, 2]))
	var prompt: Dictionary = _prompt(hook, CardEffect.Verb.MOVE_OPPONENT_LEFT, options)
	var events: Array[MatchEvent] = EffectResolver.apply_choice(state, _drift(), prompt, 1, false)
	assert_array(_kinds(events)).is_equal(_typed([MADE, MOVED, MOVED]))
	var made: Dictionary = {
		"seat": 0,
		"card": hook,
		"zone": "opponent_board",
		"index": 1,
		"target": pebble,
		"auto": false,
	}
	_assert_event(events[0], MADE, made, 1)
	_assert_event(events[1], MOVED, _moved(1, pebble, 1, 0), 1)
	_assert_event(events[2], MOVED, _moved(1, gust, 0, 1), PUBLIC)
	assert_array(state.seats[1].board).is_equal(_typed([pebble, gust, tide]))
	assert_bool(state.seats[1].is_revealed(pebble)).is_false()
	# Seat 0 learns the slots, not the card.
	assert_int(_payload_int(events[0].redacted_for(0), "target")).is_equal(HIDDEN)
	assert_int(_payload_int(events[1].redacted_for(0), "card")).is_equal(HIDDEN)
	var view: SeatView = _view(state, 0)
	assert_array(view.opponent_board).is_equal(_typed([HIDDEN, gust, tide]))


## Maelstrom offers every opponent position but the rightmost (a one-card row: none, so it
## fizzles); choosing slot 1 of three swaps it with slot 2, the chosen card's CARD_MOVED
## first.
func test_maelstrom_excludes_the_rightmost() -> void:
	var maelstrom: int = _id(0, D19_MAELSTROM)
	var gust: int = _id(1, D01_GUST)
	var pebble: int = _id(1, D04_PEBBLE)
	var tide: int = _id(1, D08_TIDE)
	var state: MatchState = _rows(_typed([maelstrom]), _typed([gust, pebble, tide]), 0)
	_reveal(state, 0, _typed([maelstrom]))
	_reveal(state, 1, _typed([gust, pebble, tide]))
	var options: Array[int] = _options(state, CardEffect.Verb.SWAP_OPPONENT_RIGHT, maelstrom)
	assert_array(options).is_equal(_typed([0, 1]))
	var prompt: Dictionary = _prompt(maelstrom, CardEffect.Verb.SWAP_OPPONENT_RIGHT, options)
	var events: Array[MatchEvent] = EffectResolver.apply_choice(state, _drift(), prompt, 1, false)
	assert_array(_kinds(events)).is_equal(_typed([MADE, MOVED, MOVED]))
	_assert_event(events[1], MOVED, _moved(1, pebble, 1, 2), PUBLIC)
	_assert_event(events[2], MOVED, _moved(1, tide, 2, 1), PUBLIC)
	assert_array(state.seats[1].board).is_equal(_typed([gust, tide, pebble]))
	var lone: MatchState = _rows(_typed([maelstrom]), _typed([gust]), 0)
	var found: Dictionary = Choice.eligible(lone, 0, CardEffect.Verb.SWAP_OPPONENT_RIGHT, maelstrom)
	assert_array(Choice.options_of(found)).is_empty()
	var fizzled: Array[MatchEvent] = _fire(lone, 0, maelstrom)
	assert_array(_kinds(fizzled)).is_equal(_typed([FIRED, MatchEvent.Kind.EFFECT_FIZZLED]))


# --- Mirror (R34, P5) ---------------------------------------------------------------------


## Mirror offers the opponent's revealed live cards only. Copying Tide (flat 3 + 2, ×1.25,
## and ×1.25 more from the revealed Lodestone beside it: ×1.56) stores flat 5 and ×1.56 as
## Mirror's base (STATS_CHANGED, cause copy); later changes to Tide do not follow.
func test_mirror_copies_effective_stats_and_does_not_follow_later_changes() -> void:
	var mirror: int = _id(0, D07_MIRROR)
	var lodestone: int = _id(1, D10_LODESTONE)
	var tide: int = _id(1, D08_TIDE)
	var pebble: int = _id(1, D04_PEBBLE)
	var keel: int = _id(1, D14_KEEL)
	var theirs: Array[int] = [lodestone, tide, pebble, keel]
	var state: MatchState = _rows(_typed([mirror]), theirs, 0)
	_reveal(state, 0, _typed([mirror]))
	_reveal(state, 1, _typed([lodestone, tide, keel]))
	state.card_state_for(keel).destroyed = true
	state.card_state_for(tide).flat_delta = 2
	var options: Array[int] = _options(state, CardEffect.Verb.COPY_STATS, mirror)
	assert_array(options).is_equal(_typed([0, 1]))
	assert_dict(_eff(tide, state)).is_equal(_flat_times_plus(5, 156, 0))
	var prompt: Dictionary = _prompt(mirror, CardEffect.Verb.COPY_STATS, options)
	var events: Array[MatchEvent] = EffectResolver.apply_choice(state, _drift(), prompt, 1, false)
	assert_array(_kinds(events)).is_equal(_typed([MADE, STATS]))
	_assert_event(events[1], STATS, _stats(0, mirror, [5, 156, 0], "copy"), PUBLIC)
	var held: CardState = state.card_state(mirror)
	assert_bool(held.has_base).is_true()
	assert_int(held.base_flat).is_equal(5)
	assert_int(held.base_times).is_equal(156)
	assert_int(held.base_plus).is_equal(0)
	assert_dict(_eff(mirror, state)).is_equal(_flat_times_plus(5, 156, 0))
	# Tide changes; Mirror keeps what it copied.
	state.card_state_for(tide).flat_delta = 10
	state.card_state_for(lodestone).destroyed = true
	assert_dict(_eff(tide, state)).is_equal(_flat_times_plus(13, 125, 0))
	assert_dict(_eff(mirror, state)).is_equal(_flat_times_plus(5, 156, 0))


## The copy takes the whole current bonus (R34, C22): Vane (+1) beside a revealed Lodestone
## shows ×1.25 and +1, and Mirror stores both. Later changes do not follow: with the
## Lodestone destroyed, Vane is back to ×1.00 and Mirror keeps ×1.25 and +1. Mirror's own
## modifiers still apply on top of the copied base (P5).
func test_mirror_copying_a_plus_card_beside_lodestone_copies_both_parts() -> void:
	var mirror: int = _id(0, D07_MIRROR)
	var lodestone: int = _id(1, D10_LODESTONE)
	var vane: int = _id(1, D18_VANE)
	var state: MatchState = _rows(_typed([mirror]), _typed([lodestone, vane]), 0)
	_reveal(state, 0, _typed([mirror]))
	_reveal(state, 1, _typed([lodestone, vane]))
	assert_dict(_eff(vane, state)).is_equal(_flat_times_plus(3, 125, 1))
	var prompt: Dictionary = _prompt(mirror, CardEffect.Verb.COPY_STATS, _typed([0, 1]))
	var events: Array[MatchEvent] = EffectResolver.apply_choice(state, _drift(), prompt, 1, false)
	assert_array(_kinds(events)).is_equal(_typed([MADE, STATS]))
	_assert_event(events[1], STATS, _stats(0, mirror, [3, 125, 1], "copy"), PUBLIC)
	var held: CardState = state.card_state(mirror)
	assert_int(held.base_times).is_equal(125)
	assert_int(held.base_plus).is_equal(1)
	assert_dict(_eff(mirror, state)).is_equal(_flat_times_plus(3, 125, 1))
	# The full state carries both parts.
	var all_states: Dictionary = state.to_dict()["card_states"]
	var plain: Dictionary = all_states[mirror]
	var plain_times: int = plain["base_times"]
	var plain_plus: int = plain["base_plus"]
	assert_int(plain_times).is_equal(125)
	assert_int(plain_plus).is_equal(1)
	# The Lodestone goes: Vane loses its ×-part, Mirror does not.
	state.card_state_for(lodestone).destroyed = true
	assert_dict(_eff(vane, state)).is_equal(_flat_times_plus(3, 100, 1))
	assert_dict(_eff(mirror, state)).is_equal(_flat_times_plus(3, 125, 1))
	# Mirror's own modifiers on top: +1 flat, +2 until the walk ends, then no bonus.
	held.flat_delta = 1
	held.temp_plus = 2
	assert_dict(_eff(mirror, state)).is_equal(_flat_times_plus(4, 125, 3))
	held.no_bonus = true
	assert_dict(_eff(mirror, state)).is_equal(_flat_times_plus(4, 100, 0))


## An Eddy that has moved (+2 until the walk ends) beside a revealed Lodestone (×1.25) shows
## both parts, and Mirror copies both as its base (R34, C22). The walk's end clears Eddy's
## +2 and a destroy takes the Lodestone's ×1.25 from Eddy; Mirror keeps what it copied.
func test_mirror_copying_a_moved_eddy_beside_lodestone_copies_both_parts() -> void:
	var mirror: int = _id(0, D07_MIRROR)
	var lodestone: int = _id(1, D10_LODESTONE)
	var eddy: int = _id(1, D05_EDDY)
	var state: MatchState = _rows(_typed([mirror]), _typed([lodestone, eddy]), 0)
	_reveal(state, 0, _typed([mirror]))
	_reveal(state, 1, _typed([lodestone, eddy]))
	state.card_state_for(eddy).temp_plus = 2
	assert_dict(_eff(eddy, state)).is_equal(_flat_times_plus(1, 125, 2))
	var prompt: Dictionary = _prompt(mirror, CardEffect.Verb.COPY_STATS, _typed([0, 1]))
	var events: Array[MatchEvent] = EffectResolver.apply_choice(state, _drift(), prompt, 1, false)
	assert_array(_kinds(events)).is_equal(_typed([MADE, STATS]))
	_assert_event(events[1], STATS, _stats(0, mirror, [1, 125, 2], "copy"), PUBLIC)
	assert_dict(_eff(mirror, state)).is_equal(_flat_times_plus(1, 125, 2))
	state.card_state_for(eddy).temp_plus = 0
	state.card_state_for(lodestone).destroyed = true
	assert_dict(_eff(eddy, state)).is_equal(_flat_times_plus(1, 100, 0))
	assert_dict(_eff(mirror, state)).is_equal(_flat_times_plus(1, 125, 2))


## A preview of Mirror's copy scores as the live engine then does (R34 with DC-05 R35): seat
## 0's [Gust, Pebble, Mirror] against seat 1's [Lodestone, Vane], all face down, both pass.
## Whichever seat commits first, Lodestone and Vane are revealed before Mirror, so its
## prompt offers both; copying Vane (×1.25 and +1) previews to the scores the live answer
## ends the walk on, and the copy stays on Mirror after the turn.
func test_mirror_copy_preview_equals_live() -> void:
	var mirror: int = _id(0, D07_MIRROR)
	var own: Array[int] = [_id(0, D01_GUST), _id(0, D04_PEBBLE), mirror]
	var theirs: Array[int] = [_id(1, D10_LODESTONE), _id(1, D18_VANE)]
	var engine: MatchEngine = FixtureDecks.drift_engine(SEED)
	assert_bool(engine.start().ok).is_true()
	assert_bool(FixtureDecks.play_table(engine, own, theirs)).is_true()
	assert_int(engine.awaited_seat()).is_equal(0)
	var prompt: Dictionary = engine.open_prompt()
	assert_array(Choice.options_of(prompt)).is_equal(_typed([0, 1]))
	var previewed: Array[int] = engine.preview_choice(0, 1)
	assert_int(previewed.size()).is_equal(2)
	assert_bool(engine.apply(EngineAction.choose(0, OPPONENT_BOARD, 1)).ok).is_true()
	var raw: Array = engine.full_state()["scores"]
	assert_array(_typed(raw)).is_equal(previewed)
	var stats: ScoreWalk.Effective = ScoreWalk.effective(
		mirror, engine._state, engine.match_cards()
	)
	assert_dict(stats.to_dict()).is_equal(_flat_times_plus(3, 125, 1))


# --- Lodestone and Herald (P5, R28) -------------------------------------------------------


## Lodestone gives ×1.25 to the card on each side of it while it is revealed and live: not
## face down, not destroyed, not to itself and not two slots away. In a walk the neighbours
## score with it: Gust ×1.25 (2), Lodestone ×1.00 (2), Pebble ×1.25 on ×1.25 = ×1.56 (4).
func test_lodestone_gives_125_to_both_neighbours_only_while_revealed_and_live() -> void:
	var gust: int = _id(0, D01_GUST)
	var lodestone: int = _id(0, D10_LODESTONE)
	var sprite: int = _id(0, D02_SPRITE)
	var pebble: int = _id(0, D04_PEBBLE)
	var state: MatchState = _rows(_typed([gust, lodestone, sprite, pebble]), _typed([]), 0)
	assert_dict(_eff(gust, state)).is_equal(_flat_times_plus(2, 100, 0))
	assert_dict(_eff(sprite, state)).is_equal(_flat_times_plus(1, 125, 0))
	_reveal(state, 0, _typed([lodestone]))
	assert_dict(_eff(gust, state)).is_equal(_flat_times_plus(2, 125, 0))
	assert_dict(_eff(sprite, state)).is_equal(_flat_times_plus(1, 156, 0))
	assert_dict(_eff(lodestone, state)).is_equal(_flat_times_plus(2, 100, 0))
	assert_dict(_eff(pebble, state)).is_equal(_flat_times_plus(3, 100, 0))
	state.card_state_for(lodestone).destroyed = true
	assert_dict(_eff(gust, state)).is_equal(_flat_times_plus(2, 100, 0))
	assert_dict(_eff(sprite, state)).is_equal(_flat_times_plus(1, 125, 0))
	# A walk: [Gust, Lodestone (revealed), Pebble].
	var walked: MatchState = _rows(_typed([gust, lodestone, pebble]), _typed([]), 0)
	_reveal(walked, 0, _typed([lodestone]))
	var recorder: Recorder = Recorder.new()
	_walk(walked, recorder)
	var times: Array[int] = []
	var added: Array[int] = []
	for event: MatchEvent in _of_kind(recorder.events, SCORED):
		times.append(_payload_int(event, "times"))
		added.append(_payload_int(event, "added"))
	assert_array(times).is_equal(_typed([125, 100, 125]))
	assert_array(added).is_equal(_typed([2, 2, 4]))
	assert_int(walked.scores[0]).is_equal(8)


## Herald has ×1.5 only while it holds slot 0 of its row: Scout moving itself to the far
## left pushes Herald to slot 1, and Herald loses it.
func test_herald_has_150_only_at_slot_0() -> void:
	var herald: int = _id(0, D12_HERALD)
	var gust: int = _id(0, D01_GUST)
	var scout: int = _id(0, D03_SCOUT)
	var state: MatchState = _rows(_typed([herald, gust]), _typed([]), 0)
	assert_dict(_eff(herald, state)).is_equal(_flat_times_plus(3, 150, 0))
	var second: MatchState = _rows(_typed([gust, herald]), _typed([]), 0)
	assert_dict(_eff(herald, second)).is_equal(_flat_times_plus(3, 100, 0))
	var pushed: MatchState = _rows(_typed([herald, scout]), _typed([]), 0)
	_reveal(pushed, 0, _typed([herald, scout]))
	var events: Array[MatchEvent] = _fire(pushed, 0, scout)
	assert_array(_kinds(events)).is_equal(_typed([FIRED, MOVED, MOVED]))
	_assert_event(events[1], MOVED, _moved(0, scout, 1, 0), PUBLIC)
	assert_array(pushed.seats[0].board).is_equal(_typed([scout, herald]))
	assert_dict(_eff(herald, pushed)).is_equal(_flat_times_plus(3, 100, 0))
	# On the other row's slot 0 it has it too: each row has its own far left.
	var theirs: MatchState = _rows(_typed([gust]), _typed([_id(1, D12_HERALD)]), 0)
	assert_dict(_eff(_id(1, D12_HERALD), theirs)).is_equal(_flat_times_plus(3, 150, 0))


# --- Eddy and ON_MOVED (R26, R33, C11) -----------------------------------------------------


## The spec's scenario: Eddy scores on slot 0, then Shepherd (slot 1) swaps with it, so Eddy
## moves forward onto the pulsed slot: ON_MOVED gives it +2 and it scores again there with
## it (mult 1.00 + 2 = 3.00, 3 points); Shepherd, now behind the cursor, does not score. The
## walk's end clears the +2; next turn Eddy scores with none.
func test_eddy_swapped_forward_scores_with_two_and_has_none_next_turn() -> void:
	var eddy: int = _id(0, D05_EDDY)
	var shepherd: int = _id(0, D09_SHEPHERD)
	var state: MatchState = _rows(_typed([eddy, shepherd]), _typed([]), 0)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [
		REVEALED, SCORED, REVEALED, FIRED, MADE, MOVED, MOVED, FIRED, STATS, SCORED, STATS
	]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[5], MOVED, _moved(0, shepherd, 1, 0), PUBLIC)
	_assert_event(events[6], MOVED, _moved(0, eddy, 0, 1), PUBLIC)
	_assert_event(events[7], FIRED, _fired(0, eddy, "plus_on_moved", "on_moved"), PUBLIC)
	_assert_event(events[8], STATS, _stats(0, eddy, [1, 100, 2], "temp_plus"), PUBLIC)
	var scored: MatchEvent = events[9]
	assert_int(_payload_int(scored, "card")).is_equal(eddy)
	assert_int(_payload_int(scored, "slot")).is_equal(1)
	assert_int(_payload_int(scored, "plus")).is_equal(2)
	assert_int(_payload_int(scored, "mult")).is_equal(300)
	assert_int(_payload_int(scored, "added")).is_equal(3)
	_assert_event(events[10], STATS, _stats(0, eddy, [1, 100, 0], "temp_plus"), PUBLIC)
	assert_int(state.scores[0]).is_equal(4)
	assert_dict(_eff(eddy, state)).is_equal(_flat_times_plus(1, 100, 0))
	# Next turn: no move, no +2.
	var next: Recorder = Recorder.new()
	_walk(state, next)
	assert_array(_kinds(next.events)).is_equal(_typed([SCORED, SCORED]))
	assert_array(_cards_of(next.events, SCORED)).is_equal(_typed([shepherd, eddy]))
	assert_int(_payload_int(next.events[1], "plus")).is_equal(0)


## ON_MOVED fires once per moved card that is revealed and live: Tempest reversing [Eddy,
## Gust, Pebble] moves Eddy (fires once) and face-down Pebble (no firing); an Eddy that does
## not move (the middle of three), is face down or is destroyed does not fire.
func test_on_moved_fires_once_per_moved_revealed_live_card() -> void:
	var tempest: int = _id(0, D17_TEMPEST)
	var eddy: int = _id(1, D05_EDDY)
	var gust: int = _id(1, D01_GUST)
	var pebble: int = _id(1, D04_PEBBLE)
	var state: MatchState = _rows(_typed([tempest]), _typed([eddy, gust, pebble]), 0)
	_reveal(state, 1, _typed([eddy, gust]))
	var events: Array[MatchEvent] = _fire(state, 0, tempest)
	assert_array(_kinds(events)).is_equal(_typed([FIRED, MOVED, MOVED, FIRED, STATS]))
	_assert_event(events[1], MOVED, _moved(1, pebble, 2, 0), 1)
	_assert_event(events[2], MOVED, _moved(1, eddy, 0, 2), PUBLIC)
	_assert_event(events[3], FIRED, _fired(1, eddy, "plus_on_moved", "on_moved"), PUBLIC)
	assert_int(_on_moved_firings(events)).is_equal(1)
	assert_int(state.card_state(eddy).temp_plus).is_equal(2)
	# Unmoved: Eddy in the middle of three.
	var middle: MatchState = _rows(_typed([tempest]), _typed([gust, eddy, pebble]), 0)
	_reveal(middle, 1, _typed([gust, eddy]))
	assert_int(_on_moved_firings(_fire(middle, 0, tempest))).is_equal(0)
	# Face down.
	var down: MatchState = _rows(_typed([tempest]), _typed([eddy, gust]), 0)
	assert_int(_on_moved_firings(_fire(down, 0, tempest))).is_equal(0)
	assert_object(down.card_state(eddy)).is_null()
	# Destroyed.
	var wrecked: MatchState = _rows(_typed([tempest]), _typed([eddy, gust]), 0)
	_reveal(wrecked, 1, _typed([eddy, gust]))
	wrecked.card_state_for(eddy).destroyed = true
	assert_int(_on_moved_firings(_fire(wrecked, 0, tempest))).is_equal(0)
	assert_int(wrecked.card_state(eddy).temp_plus).is_equal(0)


# --- Helpers that build views -------------------------------------------------------------


## Seat `seat`'s view of `state` over the Drift definitions.
func _view(state: MatchState, seat: int) -> SeatView:
	var budgets: Array[int] = [1, 1]
	return SeatView.build(state, seat, 0, budgets, _drift())


class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
