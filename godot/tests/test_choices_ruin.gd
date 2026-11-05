class_name TestChoicesRuin
extends GdUnitTestSuite
## The Ruin prompt verbs' targets (DC-07 T06; plan P12, R27): discard_own over the owner's
## hand, destroy_own_then_draw and destroy_own_then_flat_up over the owner's live row cards
## with the source excluded and destroyed cards never offered; zero eligible fizzles, one is
## chosen at once, two or more open a single-target prompt that answer() resolves; and
## destroy_leftmost_own (no prompt) skipping the source and destroyed cards. Kept apart from
## test_choices.gd, which is at the file-length cap.
##
## States are built directly on the Ruin deck in memory (FixtureDecks.ruin_defs(), Ruin on
## both seats). Instance id = seat * DECK_SIZE + index.

const SEED: int = 1
const MAX_STEPS: int = 100

const R01_SCRAP: int = FixtureDecks.R01_SCRAP
const R02_TINDER: int = FixtureDecks.R02_TINDER
const R03_EMBER: int = FixtureDecks.R03_EMBER
const R04_SHARD: int = FixtureDecks.R04_SHARD
const R05_TALLOW: int = FixtureDecks.R05_TALLOW
const R09_WICK: int = FixtureDecks.R09_WICK
const R10_BUTCHER: int = FixtureDecks.R10_BUTCHER
const R14_GLUTTON: int = FixtureDecks.R14_GLUTTON
const R15_WRECK: int = FixtureDecks.R15_WRECK

const PUBLIC: int = MatchEvent.PUBLIC
const OWN_HAND: int = Choice.Zone.OWN_HAND
const OWN_BOARD: int = Choice.Zone.OWN_BOARD
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.EFFECT_FIRED
const FIZZLED: int = MatchEvent.Kind.EFFECT_FIZZLED
const REQUESTED: int = MatchEvent.Kind.CHOICE_REQUESTED
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const DESTROYED: int = MatchEvent.Kind.CARD_DESTROYED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const DISCARDED: int = MatchEvent.Kind.CARD_DISCARDED

var _cached_ruin: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _ruin() -> MatchCards:
	if _cached_ruin == null:
		_cached_ruin = FixtureDecks.ruin_defs()
	return _cached_ruin


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


## A state with these rows (seat 0, seat 1), nothing revealed, seat 0 committing first.
func _rows(row_0: Array[int], row_1: Array[int]) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = 0
	state.seats[0].board.assign(row_0)
	state.seats[1].board.assign(row_1)
	return state


func _reveal(state: MatchState, seat: int, cards: Array[int]) -> void:
	for card: int in cards:
		state.seats[seat].revealed[card] = true


## Steps a live walk until it ends or pauses on a prompt; true when it paused.
func _run(state: MatchState, recorder: Recorder) -> bool:
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		if ScoreWalk.step(state, _ruin(), MatchRng.new(SEED), recorder.record, null):
			return true
		guard += 1
	return false


## begin() then _run(); the walk must not pause.
func _walk(state: MatchState, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_false()


func _kinds(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		out.append(event.kind)
	return out


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


func _options(state: MatchState, seat: int, verb: int, source: int) -> Array[int]:
	return Choice.options_of(Choice.eligible(state, seat, verb, source))


func _zone(state: MatchState, seat: int, verb: int, source: int) -> int:
	var found: Dictionary = Choice.eligible(state, seat, verb, source)
	var zone: int = found[Choice.KEY_ZONE]
	return zone


# --- Eligibility (P12) ------------------------------------------------------------------


## The three Ruin prompt verbs need a choice, take one target (not a set), and choose from
## the owner's hand (discard) or row (the two destroys).
func test_the_ruin_prompt_verbs_and_their_zones() -> void:
	var hand_verbs: Array[int] = [CardEffect.Verb.DISCARD_OWN]
	var row_verbs: Array[int] = [
		CardEffect.Verb.DESTROY_OWN_THEN_DRAW, CardEffect.Verb.DESTROY_OWN_THEN_FLAT_UP
	]
	var every: Array[int] = []
	every.append_array(hand_verbs)
	every.append_array(row_verbs)
	for verb: int in every:
		assert_bool(Choice.needs_choice(verb)).is_true()
		assert_bool(Choice.is_multi(verb)).is_false()
	for verb: int in hand_verbs:
		assert_int(Choice.zone_for(verb)).is_equal(OWN_HAND)
	for verb: int in row_verbs:
		assert_int(Choice.zone_for(verb)).is_equal(OWN_BOARD)
	# No prompt for the leftmost destroy, the burst or the un-reveal marker.
	for verb: int in [
		CardEffect.Verb.DESTROY_LEFTMOST_OWN,
		CardEffect.Verb.BURST,
		CardEffect.Verb.UNREVEAL_INSTEAD
	]:
		assert_bool(Choice.needs_choice(verb)).is_false()


## P12: the two destroys offer every live card of the owner's row but the source, face up
## or down; a destroyed card is never offered. The discard offers every hand position.
func test_sources_are_excluded_and_destroyed_cards_are_not_offered() -> void:
	var scrap: int = _id(0, R01_SCRAP)
	var wreck: int = _id(0, R15_WRECK)
	var source: int = _id(0, R10_BUTCHER)
	var wick: int = _id(0, R09_WICK)
	var state: MatchState = _rows(_typed([scrap, wreck, source, wick]), _none())
	_reveal(state, 0, _typed([scrap, wreck, source]))
	state.card_state_for(wreck).destroyed = true
	for verb: int in [
		CardEffect.Verb.DESTROY_OWN_THEN_DRAW, CardEffect.Verb.DESTROY_OWN_THEN_FLAT_UP
	]:
		assert_int(_zone(state, 0, verb, source)).is_equal(OWN_BOARD)
		assert_array(_options(state, 0, verb, source)).is_equal(_typed([0, 3]))
	state.seats[0].hand.assign([_id(0, R02_TINDER), _id(0, R04_SHARD), _id(0, R03_EMBER)])
	var ember: int = _id(0, R03_EMBER)
	assert_int(_zone(state, 0, CardEffect.Verb.DISCARD_OWN, ember)).is_equal(OWN_HAND)
	var all: Array[int] = [0, 1, 2]
	assert_array(_options(state, 0, CardEffect.Verb.DISCARD_OWN, ember)).is_equal(all)


# --- 0, 1, 2+ eligible ------------------------------------------------------------------


## Zero eligible fizzles: Butcher whose only other card is destroyed, and Glutton alone.
func test_no_eligible_target_fizzles() -> void:
	var wreck: int = _id(0, R15_WRECK)
	var butcher: int = _id(0, R10_BUTCHER)
	var state: MatchState = _rows(_typed([wreck, butcher]), _none())
	_reveal(state, 0, _typed([wreck]))
	state.card_state_for(wreck).destroyed = true
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var events: Array[MatchEvent] = recorder.events
	assert_array(_kinds(events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))
	var fizzled: Dictionary = {
		"seat": 0,
		"card": butcher,
		"verb": "destroy_own_then_draw",
		"reason": "no_target",
	}
	_assert_event(events[2], FIZZLED, fizzled, PUBLIC)
	var glutton: int = _id(0, R14_GLUTTON)
	var lone: MatchState = _rows(_typed([glutton]), _none())
	var again: Recorder = Recorder.new()
	_walk(lone, again)
	assert_array(_kinds(again.events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))


## One eligible is chosen at once: Butcher's only other live card is face down, so the
## choice and the destroy are private to seat 0.
func test_one_eligible_target_is_chosen_automatically() -> void:
	var scrap: int = _id(0, R01_SCRAP)
	var butcher: int = _id(0, R10_BUTCHER)
	var state: MatchState = _rows(_typed([butcher, scrap]), _none())
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var events: Array[MatchEvent] = recorder.events
	# Butcher's deck is empty, so the draws draw nothing; the face-down Scrap is destroyed
	# before the cursor reaches it and only flips there.
	var expected: Array[int] = [REVEALED, FIRED, MADE, DESTROYED, SCORED, REVEALED]
	assert_array(_kinds(events)).is_equal(expected)
	var made: Dictionary = {
		"seat": 0, "card": butcher, "zone": "own_board", "index": 1, "target": scrap, "auto": true
	}
	_assert_event(events[2], MADE, made, 0)
	_assert_event(events[3], DESTROYED, {"seat": 0, "card": scrap, "slot": 1}, 0)
	var flagged: bool = events[5].payload["destroyed"]
	assert_bool(flagged).is_true()


## Two eligible open a single-target prompt (multi false); answer() destroys the chosen
## card, Butcher draws 2, and the walk resumes with Butcher's score.
func test_two_eligible_targets_prompt_and_the_answer_destroys_then_draws() -> void:
	var scrap: int = _id(0, R01_SCRAP)
	var wick: int = _id(0, R09_WICK)
	var butcher: int = _id(0, R10_BUTCHER)
	var first: int = _id(0, R02_TINDER)
	var second: int = _id(0, R04_SHARD)
	var state: MatchState = _rows(_typed([scrap, wick, butcher]), _none())
	_reveal(state, 0, _typed([scrap, wick]))
	state.seats[0].deck.assign([first, second])
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_true()
	assert_array(_kinds(recorder.events)).is_equal(
		_typed([SCORED, SCORED, REVEALED, FIRED, REQUESTED])
	)
	var multi: bool = recorder.events[4].payload["multi"]
	assert_bool(multi).is_false()
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 1]))
	assert_bool(Choice.is_multi_prompt(state.prompt)).is_false()
	var answered: Array[MatchEvent] = EffectResolver.answer(state, _ruin(), 1)
	assert_array(_kinds(answered)).is_equal(_typed([MADE, DESTROYED, DRAWN, DRAWN]))
	_assert_event(answered[1], DESTROYED, {"seat": 0, "card": wick, "slot": 1}, PUBLIC)
	var rest: Recorder = Recorder.new()
	assert_bool(_run(state, rest)).is_false()
	assert_array(_kinds(rest.events)).is_equal(_typed([SCORED]))
	assert_array(state.seats[0].hand).is_equal(_typed([first, second]))
	assert_bool(state.is_destroyed(wick)).is_true()
	assert_bool(state.is_destroyed(scrap)).is_false()


## Two hand cards open the discard prompt over the hand; the answer discards the chosen one
## (private) and Ember scores.
func test_a_discard_prompt_over_two_hand_cards() -> void:
	var ember: int = _id(0, R03_EMBER)
	var keep: int = _id(0, R01_SCRAP)
	var drop: int = _id(0, R09_WICK)
	var state: MatchState = _rows(_typed([ember]), _none())
	state.seats[0].hand.assign([keep, drop])
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	assert_bool(_run(state, recorder)).is_true()
	assert_array(_kinds(recorder.events)).is_equal(_typed([REVEALED, FIRED, REQUESTED]))
	var zone: int = state.prompt[Choice.KEY_ZONE]
	assert_int(zone).is_equal(OWN_HAND)
	var answered: Array[MatchEvent] = EffectResolver.answer(state, _ruin(), 1)
	assert_array(_kinds(answered)).is_equal(_typed([MADE, DISCARDED]))
	assert_int(answered[0].owner_seat).is_equal(0)
	_assert_event(answered[1], DISCARDED, {"seat": 0, "card": drop}, 0)
	var rest: Recorder = Recorder.new()
	assert_bool(_run(state, rest)).is_false()
	assert_array(_kinds(rest.events)).is_equal(_typed([SCORED]))
	assert_array(state.seats[0].hand).is_equal(_typed([keep]))
	assert_array(state.seats[0].burned).is_equal(_typed([drop]))


# --- destroy_leftmost_own: no prompt, same exclusions ------------------------------------


## Tallow on slot 0 is the leftmost card but the source: it destroys the next live one, the
## face-down Scrap (private to seat 0).
func test_tallow_skips_itself_on_the_leftmost_slot() -> void:
	var tallow: int = _id(0, R05_TALLOW)
	var scrap: int = _id(0, R01_SCRAP)
	var state: MatchState = _rows(_typed([tallow, scrap]), _none())
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [REVEALED, FIRED, DESTROYED, SCORED, REVEALED]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(events[2], DESTROYED, {"seat": 0, "card": scrap, "slot": 1}, 0)
	assert_bool(state.is_destroyed(tallow)).is_false()


class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
