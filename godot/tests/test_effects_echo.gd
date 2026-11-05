# gdlint: disable=max-public-methods
class_name TestEffectsEcho
extends GdUnitTestSuite
## The Echo verbs and the on-ally-reveal trigger (cycle 8 DC-09 T03; R15-R20, plan P5, P6,
## P8): EchoEffects through EffectResolver, the turn-end returns and flips, the cost
## reductions and their STATS_CHANGED (public on a revealed row card, private to its seat on
## a face-down one), Messenger's single use, the ALLY_WATCHERS stage of ScoreWalk.Pulse with
## its pause and resume, and the stage skipped when no definition has the trigger.
##
## The Echo deck is built in memory from the plan's table (EchoFixture) until T04 ships it,
## on both seats: instance id = seat * DECK_SIZE + the E* index. Walk cases build
## MatchStates directly; the engine cases set a row by hand (_play) and pass.

const SEED: int = 1
const MAX_STEPS: int = 100
const MAX_PASSES: int = 60

const E01_WHISPER: int = EchoFixture.E01_WHISPER
const E02_SPARK: int = EchoFixture.E02_SPARK
const E03_FLICKER: int = EchoFixture.E03_FLICKER
const E04_GLINT: int = EchoFixture.E04_GLINT
const E05_ECHO: int = EchoFixture.E05_ECHO
const E06_REFRAIN: int = EchoFixture.E06_REFRAIN
const E08_MESSENGER: int = EchoFixture.E08_MESSENGER
const E09_TINKER: int = EchoFixture.E09_TINKER
const E10_RECALL: int = EchoFixture.E10_RECALL
const E11_CHIME: int = EchoFixture.E11_CHIME
const E12_BANISH: int = EchoFixture.E12_BANISH
const E14_MIRAGE: int = EchoFixture.E14_MIRAGE
const E15_RELAY: int = EchoFixture.E15_RELAY
const E16_SIGNAL: int = EchoFixture.E16_SIGNAL
const E17_REVERB: int = EchoFixture.E17_REVERB
const E19_ENCORE: int = EchoFixture.E19_ENCORE

const PUBLIC: int = MatchEvent.PUBLIC
const HIDDEN: int = MatchEvent.HIDDEN_CARD
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.EFFECT_FIRED
const FIZZLED: int = MatchEvent.Kind.EFFECT_FIZZLED
const STATS: int = MatchEvent.Kind.STATS_CHANGED
const REQUESTED: int = MatchEvent.Kind.CHOICE_REQUESTED
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const BURNED: int = MatchEvent.Kind.CARD_BURNED
const RETURNED: int = MatchEvent.Kind.CARD_RETURNED
const UNREVEALED: int = MatchEvent.Kind.CARD_UNREVEALED
const CLEARED: int = MatchEvent.Kind.DESTROYED_CLEARED
const TURN_ENDED: int = MatchEvent.Kind.TURN_ENDED
const OWN_BOARD: int = Choice.Zone.OWN_BOARD
const OPPONENT_BOARD: int = Choice.Zone.OPPONENT_BOARD

var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = EchoFixture.defs()
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


## A state with these rows (seat 0, seat 1), nothing revealed, seat 0 committing first.
func _state(row_0: Array[int], row_1: Array[int]) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = 0
	state.seats[0].board.assign(row_0)
	state.seats[1].board.assign(row_1)
	return state


func _reveal(state: MatchState, seat: int, cards: Array[int]) -> void:
	for card: int in cards:
		state.seats[seat].revealed[card] = true


## Runs one live walk on `state` with `defs` from begin() to its end (no prompt), recording
## the events.
func _walk(state: MatchState, recorder: Recorder, defs: MatchCards = null) -> void:
	var used: MatchCards = defs if defs != null else _defs()
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		var paused: bool = ScoreWalk.step(state, used, null, recorder.record, null)
		assert_bool(paused).is_false()
		guard += 1


## Steps the walk of `state` until it pauses (true) or ends (false).
func _step_until_pause(state: MatchState, defs: MatchCards, recorder: Recorder) -> bool:
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		if ScoreWalk.step(state, defs, null, recorder.record, null):
			return true
		guard += 1
	return false


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


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


func _fired(seat: int, card: int, verb: String, trigger: String, uses_left: int) -> Dictionary:
	return {"seat": seat, "card": card, "verb": verb, "trigger": trigger, "uses_left": uses_left}


func _fizzled(seat: int, card: int, verb: String, reason: String) -> Dictionary:
	return {"seat": seat, "card": card, "verb": verb, "reason": reason}


## A STATS_CHANGED payload: `stats` is [flat, times, plus, cost] after the change.
func _changed(
	seat: int, card: int, stats: Array[int], permanent: bool, cause: String
) -> Dictionary:
	return {
		"seat": seat,
		"card": card,
		"flat": stats[0],
		"times": stats[1],
		"plus": stats[2],
		"cost": stats[3],
		"permanent": permanent,
		"cause": cause,
	}


func _engine() -> MatchEngine:
	var engine: MatchEngine = EchoFixture.engine(SEED)
	assert_bool(engine.start().ok).is_true()
	return engine


func _pass(engine: MatchEngine) -> ApplyResult:
	return engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))


## Sets seat 0's row of the started `engine` to `own` by hand (face down, taken out of the
## seat's deck, hand and burn pile), then both seats pass: the walk runs. The events of both
## passes.
func _play(engine: MatchEngine, own: Array[int]) -> Array[MatchEvent]:
	var piles: MatchState.SeatPiles = engine._state.seats[0]
	for card: int in own:
		piles.deck.erase(card)
		piles.hand.erase(card)
		piles.burned.erase(card)
	piles.board.assign(own)
	var out: Array[MatchEvent] = []
	for _step: int in range(MatchEngine.SEATS):
		var result: ApplyResult = _pass(engine)
		assert_bool(result.ok).is_true()
		out.append_array(result.events)
	return out


## Passes until `engine` is in round `round_number`.
func _pass_to_round(engine: MatchEngine, round_number: int) -> void:
	var guard: int = 0
	while engine._state.round_number < round_number and guard < MAX_PASSES:
		assert_bool(_pass(engine).ok).is_true()
		guard += 1
	assert_int(engine._state.round_number).is_equal(round_number)


## A fresh StubCards over the Echo definitions (see the class).
func _stub() -> StubCards:
	var stub: StubCards = StubCards.new()
	stub.copy_from(EchoFixture.defs())
	return stub


# --- The fixture and the trigger flag -------------------------------------------------


func test_the_echo_fixture_loads_with_messengers_single_use() -> void:
	assert_bool(_defs().is_valid()).is_true()
	var messenger: CardDef = _defs().def_of(_id(0, E08_MESSENGER))
	assert_str(messenger.name).is_equal("Messenger")
	assert_int(messenger.effect.uses).is_equal(1)
	assert_bool(_defs().has_trigger(CardEffect.Trigger.ON_ALLY_REVEAL)).is_true()
	assert_bool(_defs().has_verb(CardEffect.Verb.UNREVEAL_AT_TURN_END)).is_true()
	var bloom: MatchCards = BloomFixture.defs()
	assert_bool(bloom.has_trigger(CardEffect.Trigger.ON_ALLY_REVEAL)).is_false()


# --- Flicker: returns itself at turn end (R16, R17) -----------------------------------


## Flicker marks itself; at turn end it goes to its hand public, its board changes gone and
## its memory kept.
func test_flicker_returns_at_turn_end_with_memory_kept_and_board_changes_gone() -> void:
	var flicker: int = _id(0, E03_FLICKER)
	var state: MatchState = _state(_typed([flicker]), _none())
	_reveal(state, 0, _typed([flicker]))
	state.memory_for(flicker).flat = 2
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, flicker
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED]))
	var fired: Dictionary = _fired(0, flicker, "return_self_at_turn_end", "on_reveal", -1)
	_assert_event(outcome.events[0], FIRED, fired, PUBLIC)
	assert_bool(EchoEffects.is_return_marked(state, flicker)).is_true()
	# Board changes on top: +3 flat and the no-bonus mark.
	state.card_state_for(flicker).flat_delta = 3
	state.card_state_for(flicker).no_bonus = true
	assert_int(ScoreWalk.effective(flicker, state, _defs()).flat).is_equal(6)
	var returned: Array[MatchEvent] = EffectResolver.resolve_returns(state)
	assert_int(returned.size()).is_equal(1)
	var payload: Dictionary = {"seat": 0, "card": flicker, "slot": 0}
	_assert_event(returned[0], RETURNED, payload, PUBLIC)
	assert_array(state.seats[0].hand).is_equal(_typed([flicker]))
	assert_array(state.seats[0].board).is_empty()
	assert_bool(state.seats[0].is_revealed(flicker)).is_false()
	assert_object(state.card_state(flicker)).is_null()
	assert_int(state.memory_of(flicker).flat).is_equal(2)
	var shown: ScoreWalk.Effective = ScoreWalk.effective(flicker, state, _defs())
	assert_int(shown.flat).is_equal(3)
	assert_int(shown.times).is_equal(125)


## In play: Flicker reveals, scores and goes back to the hand when the turn ends, before
## TURN_ENDED.
func test_flicker_in_play_returns_before_the_turn_ends() -> void:
	var engine: MatchEngine = _engine()
	var flicker: int = _id(0, E03_FLICKER)
	var events: Array[MatchEvent] = _play(engine, _typed([flicker]))
	var kinds: Array[int] = _kinds(events)
	assert_int(kinds.find(RETURNED)).is_greater(kinds.find(SCORED))
	assert_int(kinds.find(RETURNED)).is_less(kinds.find(TURN_ENDED))
	var piles: MatchState.SeatPiles = engine._state.seats[0]
	assert_bool(piles.hand.has(flicker)).is_true()
	assert_bool(piles.board.has(flicker)).is_false()


## At the hand cap the returning card burns, in public.
func test_a_return_at_the_hand_cap_burns() -> void:
	var flicker: int = _id(0, E03_FLICKER)
	var state: MatchState = _state(_typed([flicker]), _none())
	_reveal(state, 0, _typed([flicker]))
	var full: Array[int] = []
	for index: int in range(MatchRules.HAND_CAP):
		full.append(_id(0, E11_CHIME + index))
	state.seats[0].hand.assign(full)
	EchoEffects.mark_return(state, flicker)
	var returned: Array[MatchEvent] = EffectResolver.resolve_returns(state)
	assert_int(returned.size()).is_equal(1)
	_assert_event(returned[0], BURNED, {"seat": 0, "card": flicker}, PUBLIC)
	assert_array(state.seats[0].burned).is_equal(_typed([flicker]))


## A marked card destroyed by turn end does not return: the destroyed clear takes it to its
## pile, memory kept (R17).
func test_a_destroyed_marked_card_is_cleared_instead() -> void:
	var flicker: int = _id(0, E03_FLICKER)
	var state: MatchState = _state(_typed([flicker]), _none())
	_reveal(state, 0, _typed([flicker]))
	state.memory_for(flicker).cost = 1
	EchoEffects.mark_return(state, flicker)
	state.card_state_for(flicker).destroyed = true
	assert_array(EffectResolver.resolve_returns(state)).is_empty()
	var cleared: Array[MatchEvent] = EffectResolver.clear_destroyed(state)
	assert_array(_kinds(cleared)).is_equal(_typed([CLEARED]))
	assert_array(state.seats[0].destroyed).is_equal(_typed([flicker]))
	assert_array(state.seats[0].hand).is_empty()
	assert_int(state.memory_of(flicker).cost).is_equal(1)


# --- Recall: another card of yours (R16, R20, P8) -------------------------------------


## Recall offers the own row's live cards not already marked, the source excluded, face up
## or down; the face-down choice and its return stay private to seat 0.
func test_recall_marks_another_own_card() -> void:
	var spark: int = _id(0, E02_SPARK)
	var recall: int = _id(0, E10_RECALL)
	var glint: int = _id(0, E04_GLINT)
	var whisper: int = _id(0, E01_WHISPER)
	var messenger: int = _id(0, E08_MESSENGER)
	var state: MatchState = _state(_typed([spark, recall, glint, whisper, messenger]), _none())
	_reveal(state, 0, _typed([spark, recall, whisper, messenger]))
	state.card_state_for(whisper).destroyed = true
	EchoEffects.mark_return(state, messenger)
	var verb: int = CardEffect.Verb.RETURN_OWN_AT_TURN_END
	assert_bool(Choice.needs_choice(verb)).is_true()
	assert_bool(Choice.is_multi(verb)).is_false()
	assert_int(Choice.zone_for(verb)).is_equal(OWN_BOARD)
	assert_bool(Choice.needs_choice(CardEffect.Verb.RETURN_SELF_AT_TURN_END)).is_false()
	assert_array(Choice.options_of(Choice.eligible(state, 0, verb, recall))).is_equal(
		_typed([0, 2])
	)
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, recall
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, REQUESTED]))
	var requested: Dictionary = outcome.events[1].payload
	assert_str(requested["zone"]).is_equal("own_board")
	state.prompt = outcome.prompt
	var answered: Array[MatchEvent] = EffectResolver.answer(state, _defs(), 2)
	assert_array(_kinds(answered)).is_equal(_typed([MADE]))
	assert_int(answered[0].owner_seat).is_equal(0)
	assert_int(_payload_int(answered[0].redacted_for(1), "target")).is_equal(HIDDEN)
	assert_bool(EchoEffects.is_return_marked(state, glint)).is_true()
	assert_bool(EchoEffects.is_return_marked(state, spark)).is_false()
	# Turn end: Glint (still face down here) first, private; then Messenger, public; the
	# destroyed Whisper stays for clear_destroyed().
	var returned: Array[MatchEvent] = EffectResolver.resolve_returns(state)
	assert_int(returned.size()).is_equal(2)
	_assert_event(returned[0], RETURNED, {"seat": 0, "card": glint, "slot": 2}, 0)
	assert_int(_payload_int(returned[0].redacted_for(1), "card")).is_equal(HIDDEN)
	_assert_event(returned[1], RETURNED, {"seat": 0, "card": messenger, "slot": 3}, PUBLIC)
	assert_array(state.seats[0].hand).is_equal(_typed([glint, messenger]))
	assert_array(state.seats[0].board).is_equal(_typed([spark, recall, whisper]))


## Alone on its row, Recall fizzles.
func test_recall_alone_fizzles() -> void:
	var recall: int = _id(0, E10_RECALL)
	var state: MatchState = _state(_typed([recall]), _none())
	_reveal(state, 0, _typed([recall]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, recall
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, FIZZLED]))
	var fizzled: Dictionary = _fizzled(
		0, recall, "return_own_at_turn_end", EffectResolver.REASON_NO_TARGET
	)
	_assert_event(outcome.events[1], FIZZLED, fizzled, PUBLIC)


# --- Banish: an enemy card (R16, R17, R20, P8) ----------------------------------------


## Banish offers the opponent's revealed live cards not already marked; the chosen card goes
## to its controller's hand at turn end.
func test_banish_marks_a_revealed_enemy_card_which_returns_to_its_controller() -> void:
	var banish: int = _id(0, E12_BANISH)
	var theirs: Array[int] = [
		_id(1, E02_SPARK),
		_id(1, E04_GLINT),
		_id(1, E11_CHIME),
		_id(1, E14_MIRAGE),
		_id(1, E16_SIGNAL),
	]
	var state: MatchState = _state(_typed([banish]), theirs)
	_reveal(state, 0, _typed([banish]))
	_reveal(state, 1, _typed([theirs[0], theirs[2], theirs[3], theirs[4]]))
	state.card_state_for(theirs[2]).destroyed = true
	EchoEffects.mark_return(state, theirs[3])
	var verb: int = CardEffect.Verb.RETURN_OPPONENT_AT_TURN_END
	assert_bool(Choice.needs_choice(verb)).is_true()
	assert_int(Choice.zone_for(verb)).is_equal(OPPONENT_BOARD)
	assert_array(Choice.options_of(Choice.eligible(state, 0, verb, banish))).is_equal(
		_typed([0, 4])
	)
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, banish
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, REQUESTED]))
	state.prompt = outcome.prompt
	var answered: Array[MatchEvent] = EffectResolver.answer(state, _defs(), 4)
	assert_array(_kinds(answered)).is_equal(_typed([MADE]))
	assert_int(answered[0].owner_seat).is_equal(PUBLIC)
	assert_bool(EchoEffects.is_return_marked(state, theirs[4])).is_true()
	var returned: Array[MatchEvent] = EffectResolver.resolve_returns(state)
	assert_int(returned.size()).is_equal(2)
	_assert_event(returned[0], RETURNED, {"seat": 1, "card": theirs[3], "slot": 3}, PUBLIC)
	_assert_event(returned[1], RETURNED, {"seat": 1, "card": theirs[4], "slot": 3}, PUBLIC)
	assert_array(state.seats[1].hand).is_equal(_typed([theirs[3], theirs[4]]))
	assert_array(state.seats[0].hand).is_empty()


## A card seat 1 recovered from seat 0 goes back to seat 1's hand (its controller), not to
## its origin's.
func test_banish_returns_a_recovered_card_to_the_recoverer() -> void:
	var banish: int = _id(0, E12_BANISH)
	var recovered: int = _id(0, E14_MIRAGE)
	var state: MatchState = _state(_typed([banish]), _typed([recovered]))
	_reveal(state, 0, _typed([banish]))
	_reveal(state, 1, _typed([recovered]))
	assert_int(state.controller_of(recovered)).is_equal(1)
	assert_int(_defs().origin_of(recovered)).is_equal(0)
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, banish
	)
	# One option: auto-chosen.
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, MADE]))
	var returned: Array[MatchEvent] = EffectResolver.resolve_returns(state)
	_assert_event(returned[0], RETURNED, {"seat": 1, "card": recovered, "slot": 0}, PUBLIC)
	assert_array(state.seats[1].hand).is_equal(_typed([recovered]))
	assert_array(state.seats[0].hand).is_empty()


## A face-down enemy card is never offered: Banish fizzles.
func test_banish_with_no_revealed_enemy_card_fizzles() -> void:
	var banish: int = _id(0, E12_BANISH)
	var state: MatchState = _state(_typed([banish]), _typed([_id(1, E04_GLINT)]))
	_reveal(state, 0, _typed([banish]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, banish
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, FIZZLED]))


# --- Echo: the turn-end flip (R18) ----------------------------------------------------


## Echo flips face down at turn end after the destroyed clear and before TURN_ENDED; it
## reveals in full on the next walk, where Refrain's ally watcher fires for it again, and it
## flips again at that turn's end.
func test_echo_flips_after_the_clear_and_reveals_in_full_next_walk() -> void:
	var engine: MatchEngine = _engine()
	var state: MatchState = engine._state
	var refrain: int = _id(0, E06_REFRAIN)
	var echo: int = _id(0, E05_ECHO)
	var spark: int = _id(0, E02_SPARK)
	var first: Array[MatchEvent] = _play(engine, _typed([refrain, echo, spark]))
	var flipped: Array[MatchEvent] = _of_kind(first, UNREVEALED)
	assert_int(flipped.size()).is_equal(1)
	_assert_event(flipped[0], UNREVEALED, {"seat": 0, "card": echo, "slot": 1}, PUBLIC)
	var kinds: Array[int] = _kinds(first)
	assert_int(kinds.find(UNREVEALED)).is_less(kinds.find(TURN_ENDED))
	var piles: MatchState.SeatPiles = state.seats[0]
	assert_array(piles.board).is_equal(_typed([refrain, echo, spark]))
	assert_bool(piles.is_revealed(echo)).is_false()
	assert_bool(piles.is_revealed(refrain)).is_true()
	# Refrain gained +1 for Echo and +1 for Spark.
	assert_int(state.card_state(refrain).flat_delta).is_equal(2)
	# Turn 2: Spark is destroyed before the walk, so turn end clears it, then flips Echo.
	assert_bool(_pass(engine).ok).is_true()
	state.card_state_for(spark).destroyed = true
	var second: ApplyResult = _pass(engine)
	assert_bool(second.ok).is_true()
	var revealed: Array[MatchEvent] = _of_kind(second.events, REVEALED)
	assert_int(revealed.size()).is_equal(1)
	assert_int(_payload_int(revealed[0], "card")).is_equal(echo)
	assert_int(_payload_int(revealed[0], "slot")).is_equal(1)
	var fired: Array[MatchEvent] = _of_kind(second.events, FIRED)
	assert_int(fired.size()).is_equal(1)
	var again: Dictionary = _fired(0, refrain, "ally_reveal_flat", "on_ally_reveal", -1)
	_assert_event(fired[0], FIRED, again, PUBLIC)
	assert_int(state.card_state(refrain).flat_delta).is_equal(3)
	var next: Array[int] = _kinds(second.events)
	assert_int(next.find(CLEARED)).is_greater(-1)
	assert_int(next.find(CLEARED)).is_less(next.find(UNREVEALED))
	assert_int(next.find(UNREVEALED)).is_less(next.find(TURN_ENDED))
	assert_bool(piles.is_revealed(echo)).is_false()
	assert_array(piles.board).is_equal(_typed([refrain, echo]))


## flip_echoes turns only revealed live carriers face down: a face-down or destroyed Echo
## stays; the flip drops the board changes (STATS_CHANGED cause unreveal) and keeps memory.
func test_flip_echoes_resets_board_changes_and_keeps_memory() -> void:
	var echo: int = _id(0, E05_ECHO)
	var theirs: int = _id(1, E05_ECHO)
	var state: MatchState = _state(_typed([_id(0, E02_SPARK), echo]), _typed([theirs]))
	_reveal(state, 1, _typed([theirs]))
	state.card_state_for(theirs).destroyed = true
	# Face down: nothing to flip.
	assert_array(EffectResolver.flip_echoes(state, _defs())).is_empty()
	_reveal(state, 0, _typed([echo]))
	state.memory_for(echo).flat = 1
	state.card_state_for(echo).flat_delta = 2
	var events: Array[MatchEvent] = EffectResolver.flip_echoes(state, _defs())
	assert_array(_kinds(events)).is_equal(_typed([STATS, UNREVEALED]))
	var stats: Dictionary = _changed(
		0, echo, _typed([3, 100, 0, 2]), false, EffectResolver.CAUSE_UNREVEAL
	)
	_assert_event(events[0], STATS, stats, PUBLIC)
	_assert_event(events[1], UNREVEALED, {"seat": 0, "card": echo, "slot": 1}, PUBLIC)
	assert_bool(state.seats[0].is_revealed(echo)).is_false()
	assert_object(state.card_state(echo)).is_null()
	assert_int(state.memory_of(echo).flat).is_equal(1)
	assert_bool(state.seats[1].is_revealed(theirs)).is_true()


## A match with no Echo definition flips nothing.
func test_flip_echoes_without_the_verb_does_nothing() -> void:
	var bloom: MatchCards = BloomFixture.defs()
	var card: int = _id(0, BloomFixture.B02_SPROUT)
	var state: MatchState = _state(_typed([card]), _none())
	_reveal(state, 0, _typed([card]))
	assert_array(EffectResolver.flip_echoes(state, bloom)).is_empty()
	assert_bool(state.seats[0].is_revealed(card)).is_true()


# --- Tinker and Reverb: cost reductions (R16, P6) -------------------------------------


## Tinker reduces the card at slot + 1 by 1 for the match: private to seat 0 while that
## card is face down, public once it is revealed.
func test_tinker_reduces_the_card_to_its_right() -> void:
	var tinker: int = _id(0, E09_TINKER)
	var encore: int = _id(0, E19_ENCORE)
	var state: MatchState = _state(_typed([tinker, encore, _id(0, E04_GLINT)]), _none())
	_reveal(state, 0, _typed([tinker]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, tinker
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, STATS]))
	var cause: String = BloomEffects.CAUSE_COST
	var hidden: Dictionary = _changed(0, encore, _typed([10, 100, 0, 6]), true, cause)
	_assert_event(outcome.events[1], STATS, hidden, 0)
	assert_int(_payload_int(outcome.events[1].redacted_for(1), "card")).is_equal(HIDDEN)
	assert_int(state.memory_of(encore).cost).is_equal(1)
	assert_int(ScoreWalk.effective_cost(encore, state, _defs())).is_equal(6)
	_reveal(state, 0, _typed([encore]))
	var again: EffectResolver.Outcome = EffectResolver.apply(state, _defs(), null, null, 0, tinker)
	var shown: Dictionary = _changed(0, encore, _typed([10, 100, 0, 5]), true, cause)
	_assert_event(again.events[1], STATS, shown, PUBLIC)
	# The reduction is memory: it holds in the hand.
	assert_bool(state.take_from_row(0, encore)).is_true()
	state.seats[0].hand.append(encore)
	assert_int(ScoreWalk.effective_cost(encore, state, _defs())).is_equal(5)


## At the row's end Tinker has no card to its right: it fizzles and writes no memory.
func test_tinker_at_the_rows_end_fizzles() -> void:
	var tinker: int = _id(0, E09_TINKER)
	var state: MatchState = _state(_typed([_id(0, E04_GLINT), tinker]), _none())
	_reveal(state, 0, _typed([tinker]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, tinker
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, FIZZLED]))
	var fizzled: Dictionary = _fizzled(
		0, tinker, "cost_down_right", EffectResolver.REASON_NO_TARGET
	)
	_assert_event(outcome.events[1], FIZZLED, fizzled, PUBLIC)
	assert_bool(state.memory.is_empty()).is_true()


## Reverb reduces its own cost by 2 each time it reveals, public.
func test_reverb_reduces_its_own_cost() -> void:
	var reverb: int = _id(0, E17_REVERB)
	var state: MatchState = _state(_typed([reverb]), _none())
	_reveal(state, 0, _typed([reverb]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, reverb
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, STATS]))
	var stats: Dictionary = _changed(
		0, reverb, _typed([5, 100, 0, 4]), true, BloomEffects.CAUSE_COST
	)
	_assert_event(outcome.events[1], STATS, stats, PUBLIC)
	assert_int(state.memory_of(reverb).cost).is_equal(2)


# --- Messenger: draw 2 once per match (R6, R16) ---------------------------------------


## Messenger draws 2 on its first reveal (uses_left 0); then it fizzles spent, also after a
## bounce and a new reveal.
func test_messenger_draws_two_once_per_match() -> void:
	var messenger: int = _id(0, E08_MESSENGER)
	var deck: Array[int] = [_id(0, E04_GLINT), _id(0, E02_SPARK), _id(0, E11_CHIME)]
	var state: MatchState = _state(_typed([messenger]), _none())
	state.seats[0].deck.assign(deck)
	_reveal(state, 0, _typed([messenger]))
	var first: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, messenger
	)
	assert_array(_kinds(first.events)).is_equal(_typed([FIRED, DRAWN, DRAWN]))
	var fired: Dictionary = _fired(0, messenger, "draw_once", "on_reveal", 0)
	_assert_event(first.events[0], FIRED, fired, PUBLIC)
	assert_int(first.events[1].owner_seat).is_equal(0)
	assert_array(state.seats[0].hand).is_equal(_typed([deck[0], deck[1]]))
	var second: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, messenger
	)
	var spent: Dictionary = _fizzled(0, messenger, "draw_once", EffectResolver.REASON_SPENT)
	assert_array(_kinds(second.events)).is_equal(_typed([FIZZLED]))
	_assert_event(second.events[0], FIZZLED, spent, PUBLIC)
	# Bounced and played again: it reveals, fizzles spent, draws nothing and scores.
	EchoEffects.mark_return(state, messenger)
	assert_int(EffectResolver.resolve_returns(state).size()).is_equal(1)
	state.seats[0].hand.erase(messenger)
	state.seats[0].board.assign(_typed([messenger]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_array(_kinds(recorder.events)).is_equal(_typed([REVEALED, FIZZLED, SCORED]))
	assert_array(state.seats[0].hand).is_equal(_typed([deck[0], deck[1]]))
	assert_int(state.memory_of(messenger).uses_left).is_equal(0)


# --- Refrain and Relay: on ally reveal (R15, R16) -------------------------------------


## Refrain gains +1 flat (a board change, cause ally_reveal) for each other card of its
## seat that reveals after it; its own reveal and the opponent's do not count.
func test_refrain_gains_one_per_other_own_reveal() -> void:
	var refrain: int = _id(0, E06_REFRAIN)
	var spark: int = _id(0, E02_SPARK)
	var glint: int = _id(0, E04_GLINT)
	var state: MatchState = _state(_typed([refrain, spark, glint]), _typed([_id(1, E04_GLINT)]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var fired: Array[MatchEvent] = _of_kind(recorder.events, FIRED)
	assert_int(fired.size()).is_equal(2)
	var stats: Array[MatchEvent] = _of_kind(recorder.events, STATS)
	assert_int(stats.size()).is_equal(2)
	var cause: String = EchoEffects.CAUSE_ALLY_REVEAL
	for index: int in range(2):
		var watched: Dictionary = _fired(0, refrain, "ally_reveal_flat", "on_ally_reveal", -1)
		_assert_event(fired[index], FIRED, watched, PUBLIC)
		var flat: int = 2 + index
		var grown: Dictionary = _changed(0, refrain, _typed([flat, 100, 0, 2]), false, cause)
		_assert_event(stats[index], STATS, grown, PUBLIC)
	assert_int(state.card_state(refrain).flat_delta).is_equal(2)
	assert_object(state.memory_of(refrain)).is_null()
	# The order: Spark's reveal, Refrain's firing, then Spark's score.
	var kinds: Array[int] = _kinds(recorder.events)
	var spark_reveal: int = -1
	for index: int in range(recorder.events.size()):
		var event: MatchEvent = recorder.events[index]
		if event.kind == REVEALED and _payload_int(event, "card") == spark:
			spark_reveal = index
	assert_int(kinds[spark_reveal + 1]).is_equal(FIRED)
	assert_int(kinds[spark_reveal + 2]).is_equal(STATS)
	assert_int(kinds[spark_reveal + 3]).is_equal(SCORED)


## Refrain's gain is for the round: gone at round start, no memory written.
func test_refrains_gain_resets_at_round_start() -> void:
	var engine: MatchEngine = _engine()
	var state: MatchState = engine._state
	var refrain: int = _id(0, E06_REFRAIN)
	var events: Array[MatchEvent] = _play(
		engine, _typed([refrain, _id(0, E02_SPARK), _id(0, E04_GLINT)])
	)
	assert_int(_of_kind(events, STATS).size()).is_equal(2)
	assert_int(state.card_state(refrain).flat_delta).is_equal(2)
	# Next turn's walk: nothing reveals, the gain holds.
	assert_bool(_pass(engine).ok).is_true()
	assert_bool(_pass(engine).ok).is_true()
	assert_int(state.card_state(refrain).flat_delta).is_equal(2)
	_pass_to_round(engine, 2)
	assert_object(state.card_state(refrain)).is_null()
	assert_object(state.memory_of(refrain)).is_null()
	assert_int(ScoreWalk.effective(refrain, state, _defs()).flat).is_equal(1)


## Relay draws a card for each other own card revealing after it, each draw private.
func test_relay_draws_per_ally_reveal() -> void:
	var relay: int = _id(0, E15_RELAY)
	var spark: int = _id(0, E02_SPARK)
	var glint: int = _id(0, E04_GLINT)
	var deck: Array[int] = [_id(0, E11_CHIME), _id(0, E14_MIRAGE), _id(0, E16_SIGNAL)]
	var state: MatchState = _state(_typed([relay, spark, glint]), _none())
	state.seats[0].deck.assign(deck)
	_reveal(state, 0, _typed([relay]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var expected: Array[int] = [
		SCORED, REVEALED, FIRED, DRAWN, SCORED, REVEALED, FIRED, DRAWN, SCORED
	]
	assert_array(_kinds(recorder.events)).is_equal(expected)
	_assert_event(recorder.events[2], FIRED, _fired(0, relay, "draw", "on_ally_reveal", -1), PUBLIC)
	_assert_event(recorder.events[3], DRAWN, {"seat": 0, "card": deck[0]}, 0)
	assert_array(state.seats[0].hand).is_equal(_typed([deck[0], deck[1]]))


# --- ALLY_WATCHERS: pause and resume (P5) ---------------------------------------------


## An ally watcher that opens a prompt pauses the walk at ALLY_WATCHERS with the snapshot
## and the next index in the walk state (so a copy of the paused state finishes alike); the
## answer resumes the stage at the next watcher, then the revealing card scores.
func test_a_prompt_opened_by_an_ally_watcher_pauses_and_resumes_in_order() -> void:
	var defs: MatchCards = EchoFixture.defs()
	var asker: int = _id(0, E02_SPARK)
	# A test-only definition the loader would refuse: a prompt verb on on_ally_reveal.
	defs.def_of(asker).effect = CardEffect.new(
		CardEffect.Trigger.ON_ALLY_REVEAL, CardEffect.Verb.GROW_OTHER_FLAT, 1, "test"
	)
	var relay: int = _id(0, E15_RELAY)
	var glint: int = _id(0, E04_GLINT)
	var chime: int = _id(0, E11_CHIME)
	var state: MatchState = _state(_typed([asker, relay, glint]), _none())
	state.seats[0].deck.assign(_typed([chime]))
	_reveal(state, 0, _typed([asker, relay]))
	ScoreWalk.begin(state)
	var recorder: Recorder = Recorder.new()
	assert_bool(_step_until_pause(state, defs, recorder)).is_true()
	var before: Array[int] = [SCORED, SCORED, REVEALED, FIRED, REQUESTED]
	assert_array(_kinds(recorder.events)).is_equal(before)
	var asked: Dictionary = _fired(0, asker, "grow_other_flat", "on_ally_reveal", -1)
	_assert_event(recorder.events[3], FIRED, asked, PUBLIC)
	var walk: Dictionary = state.walk.to_dict()
	assert_int(walk["paused_stage"]).is_equal(ScoreWalk.Stage.ALLY_WATCHERS)
	assert_int(walk["paused_card"]).is_equal(glint)
	assert_int(walk["paused_slot"]).is_equal(2)
	assert_array(walk["paused_watchers"]).is_equal([asker, relay])
	assert_int(walk["paused_watcher_at"]).is_equal(1)
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([1, 2]))
	var copy: MatchState = state.duplicate()
	assert_dict(copy.to_dict()).is_equal(state.to_dict())
	# The answer grows Glint; the walk resumes with Relay's draw, then Glint scores.
	var answered: Array[MatchEvent] = EffectResolver.answer(state, defs, 2)
	assert_array(_kinds(answered)).is_equal(_typed([MADE, STATS]))
	var resumed: Recorder = Recorder.new()
	assert_bool(_step_until_pause(state, defs, resumed)).is_false()
	assert_array(_kinds(resumed.events)).is_equal(_typed([FIRED, DRAWN, SCORED]))
	_assert_event(resumed.events[0], FIRED, _fired(0, relay, "draw", "on_ally_reveal", -1), PUBLIC)
	assert_int(_payload_int(resumed.events[2], "card")).is_equal(glint)
	assert_int(_payload_int(resumed.events[2], "flat")).is_equal(4)
	assert_array(state.seats[0].hand).is_equal(_typed([chime]))
	# The paused copy, answered alike, ends in the same state.
	assert_int(EffectResolver.answer(copy, defs, 2).size()).is_equal(2)
	assert_bool(_step_until_pause(copy, defs, Recorder.new())).is_false()
	assert_dict(copy.to_dict()).is_equal(state.to_dict())


## A prompt in the revealing card's own on-reveal stage resolves first: the ally watchers
## fire after the answer, before the score.
func test_an_on_reveal_prompt_resolves_before_the_ally_watchers() -> void:
	var refrain: int = _id(0, E06_REFRAIN)
	var spark: int = _id(0, E02_SPARK)
	var recall: int = _id(0, E10_RECALL)
	var state: MatchState = _state(_typed([refrain, spark, recall]), _none())
	_reveal(state, 0, _typed([refrain, spark]))
	ScoreWalk.begin(state)
	var recorder: Recorder = Recorder.new()
	assert_bool(_step_until_pause(state, _defs(), recorder)).is_true()
	assert_int(state.walk.paused_stage).is_equal(ScoreWalk.Stage.WATCHERS)
	assert_object(state.card_state(refrain)).is_null()
	assert_int(EffectResolver.answer(state, _defs(), 1).size()).is_equal(1)
	var resumed: Recorder = Recorder.new()
	assert_bool(_step_until_pause(state, _defs(), resumed)).is_false()
	assert_array(_kinds(resumed.events)).is_equal(_typed([FIRED, STATS, SCORED]))
	assert_int(_payload_int(resumed.events[0], "card")).is_equal(refrain)
	assert_int(_payload_int(resumed.events[2], "card")).is_equal(recall)
	assert_bool(EchoEffects.is_return_marked(state, spark)).is_true()


## With no definition carrying ON_ALLY_REVEAL (as MatchCards.has_trigger reports it) the
## stage is skipped outright: a stub that answers false keeps a revealed Refrain silent, and
## counts one question per reveal; the real definitions fire it.
func test_ally_watchers_are_skipped_when_no_definition_has_the_trigger() -> void:
	var refrain: int = _id(0, E06_REFRAIN)
	var spark: int = _id(0, E02_SPARK)
	var stub: StubCards = _stub()
	var state: MatchState = _state(_typed([refrain, spark]), _none())
	_reveal(state, 0, _typed([refrain]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder, stub)
	assert_array(_kinds(recorder.events)).is_equal(_typed([SCORED, REVEALED, SCORED]))
	assert_int(stub.ally_asked).is_equal(1)
	assert_object(state.card_state(refrain)).is_null()
	# The same walk with the real definitions: Refrain fires.
	var real: MatchState = _state(_typed([refrain, spark]), _none())
	_reveal(real, 0, _typed([refrain]))
	var heard: Recorder = Recorder.new()
	_walk(real, heard)
	assert_array(_kinds(heard.events)).is_equal(_typed([SCORED, REVEALED, FIRED, STATS, SCORED]))


## Records a walk's events as MatchEvents (the walk's sink).
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))


## MatchCards over built definitions whose has_trigger() answers false for ON_ALLY_REVEAL,
## counting those questions (the skip check of ScoreWalk.Pulse._ally_watchers).
class StubCards:
	extends MatchCards

	var ally_asked: int = 0

	func copy_from(built: MatchCards) -> void:
		_defs = built._defs
		_deck_ids = built._deck_ids
		_verbs = built._verbs
		_triggers = built._triggers

	func has_trigger(trigger: int) -> bool:
		if trigger == CardEffect.Trigger.ON_ALLY_REVEAL:
			ally_asked += 1
			return false
		return super.has_trigger(trigger)
