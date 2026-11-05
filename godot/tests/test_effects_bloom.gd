# gdlint: disable=max-public-methods
class_name TestEffectsBloom
extends GdUnitTestSuite
## The Bloom grow verbs and the uses countdown (cycle 8 DC-09 T02; R6, R12-R14, R20, plan
## P4, P7, P8): BloomEffects through EffectResolver, the memory they write and the
## STATS_CHANGED they emit (public on a revealed row card, private to the holder on a hand
## card), the two prompt verbs' eligibility, EFFECT_FIRED `uses_left` and EFFECT_FIZZLED
## `reason`, growth kept through a round start, a redraw and a recovery by the other seat,
## and a preview that equals live play with memory.
##
## The Bloom deck is built in memory from the plan's table (BloomFixture) until T04 ships it,
## on both seats: instance id = seat * DECK_SIZE + the B* index. Walk cases build
## MatchStates directly; the engine cases set a row by hand (_play) and pass.

const SEED: int = 1
const MAX_STEPS: int = 100
const MAX_PASSES: int = 60

const B01_SEED: int = BloomFixture.B01_SEED
const B02_SPROUT: int = BloomFixture.B02_SPROUT
const B03_ACORN: int = BloomFixture.B03_ACORN
const B04_MOSS: int = BloomFixture.B04_MOSS
const B05_SAPLING: int = BloomFixture.B05_SAPLING
const B06_TILLER: int = BloomFixture.B06_TILLER
const B08_RAIN: int = BloomFixture.B08_RAIN
const B09_VINE: int = BloomFixture.B09_VINE
const B11_ORCHARD: int = BloomFixture.B11_ORCHARD
const B12_GROVE: int = BloomFixture.B12_GROVE
const B13_ELDER: int = BloomFixture.B13_ELDER
const B15_OAK: int = BloomFixture.B15_OAK
const B17_REDWOOD: int = BloomFixture.B17_REDWOOD
const B18_BLOOM: int = BloomFixture.B18_BLOOM
const B20_WORLD_TREE: int = BloomFixture.B20_WORLD_TREE

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
const TURN_ENDED: int = MatchEvent.Kind.TURN_ENDED
const OWN_HAND: int = Choice.Zone.OWN_HAND
const OWN_BOARD: int = Choice.Zone.OWN_BOARD

var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = BloomFixture.defs()
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


func _cost(card: int) -> int:
	return _defs().def_of(card).cost


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


## Runs one live walk on `state` from begin() to its end (no prompt), recording the events.
func _walk(state: MatchState, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		var paused: bool = ScoreWalk.step(state, _defs(), null, recorder.record, null)
		assert_bool(paused).is_false()
		guard += 1


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


## A growth's STATS_CHANGED payload: `stats` is [flat, times, plus] after the growth.
func _grown(seat: int, card: int, stats: Array[int]) -> Dictionary:
	return {
		"seat": seat,
		"card": card,
		"flat": stats[0],
		"times": stats[1],
		"plus": stats[2],
		"cost": _cost(card),
		"permanent": true,
		"cause": BloomEffects.CAUSE_GROW,
	}


func _engine() -> MatchEngine:
	var engine: MatchEngine = BloomFixture.engine(SEED)
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


## Puts `card` into `seat`'s hand of `state`, out of its deck, hand and burn pile first.
func _to_hand(state: MatchState, seat: int, card: int) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.deck.erase(card)
	piles.hand.erase(card)
	piles.burned.erase(card)
	piles.hand.append(card)


## The own_hand_row entry of `view` for `card`, or {} when its hand does not hold it.
func _hand_entry(view: SeatView, card: int) -> Dictionary:
	for entry: Dictionary in view.own_hand_row:
		var held: int = entry["card"]
		if held == card:
			return entry
	return {}


# --- The fixture ----------------------------------------------------------------------


func test_the_bloom_fixture_loads_with_oaks_single_use() -> void:
	assert_bool(_defs().is_valid()).is_true()
	var oak: CardDef = _defs().def_of(_id(0, B15_OAK))
	assert_str(oak.name).is_equal("Oak")
	assert_int(oak.effect.uses).is_equal(1)
	assert_int(_defs().def_of(_id(1, B05_SAPLING)).effect.uses).is_equal(0)


# --- grow_self_*: on score (R12) ------------------------------------------------------


## Sapling (flat 1, no bonus) scores thrice: it scores at ×1.00, ×1.25, ×1.50 and grows to
## ×1.25, ×1.50, ×1.75 after each score; the walk's mult follows (Moss after it scores at
## Sapling's mult). Each growth is one public STATS_CHANGED, permanent, cause grow.
func test_sapling_scores_thrice_and_grows_125_150_175() -> void:
	var sapling: int = _id(0, B05_SAPLING)
	var moss: int = _id(0, B04_MOSS)
	var state: MatchState = _state(_typed([sapling, moss]), _none())
	var grown: Array[int] = [125, 150, 175]
	var moss_added: Array[int] = [3, 3, 4]
	for walk: int in range(3):
		var recorder: Recorder = Recorder.new()
		_walk(state, recorder)
		var events: Array[MatchEvent] = recorder.events
		var expected: Array[int] = [SCORED, FIRED, STATS, SCORED]
		if walk == 0:
			expected = _typed([REVEALED, SCORED, FIRED, STATS, REVEALED, SCORED])
		assert_array(_kinds(events)).is_equal(expected)
		var scored: Array[MatchEvent] = _of_kind(events, SCORED)
		var shown: int = MatchRules.MULT_ONE if walk == 0 else grown[walk - 1]
		assert_int(_payload_int(scored[0], "times")).is_equal(shown)
		assert_int(_payload_int(scored[0], "mult")).is_equal(shown)
		assert_int(_payload_int(scored[1], "mult")).is_equal(shown)
		assert_int(_payload_int(scored[1], "added")).is_equal(moss_added[walk])
		var fired: MatchEvent = _of_kind(events, FIRED)[0]
		_assert_event(fired, FIRED, _fired(0, sapling, "grow_self_times", "on_score", -1), PUBLIC)
		var stats: MatchEvent = _of_kind(events, STATS)[0]
		_assert_event(stats, STATS, _grown(0, sapling, _typed([1, grown[walk], 0])), PUBLIC)
		assert_int(state.memory_of(sapling).times).is_equal(grown[walk] - MatchRules.MULT_ONE)
	assert_int(ScoreWalk.effective(sapling, state, _defs()).times).is_equal(175)
	assert_bool(ScoreWalk.is_grown(sapling, state)).is_true()
	# Moss never grew: no memory entry.
	assert_object(state.memory_of(moss)).is_null()


## Grove grows its +-part by 1 per score.
func test_grove_grows_its_plus_part_per_score() -> void:
	var grove: int = _id(0, B12_GROVE)
	var state: MatchState = _state(_typed([grove]), _none())
	for walk: int in range(2):
		var recorder: Recorder = Recorder.new()
		_walk(state, recorder)
		var stats: MatchEvent = _of_kind(recorder.events, STATS)[0]
		_assert_event(stats, STATS, _grown(0, grove, _typed([3, 100, walk + 1])), PUBLIC)
	assert_int(state.memory_of(grove).plus).is_equal(2)
	# The second walk scored with +1: mult 100 + 100, 3 × 2.00 = 6.
	assert_array(state.scores).is_equal(_typed([6, 0]))


# --- Seed: kept through a round start and a redraw (R2, R14) --------------------------


## Seed's flat grows by 1 each time it scores; at round start the memory stays, a redraw
## shows it on the hand face (grown mark) and the card scores with it when played again.
func test_seeds_flat_grows_per_score_and_survives_round_start_and_a_redraw() -> void:
	var engine: MatchEngine = _engine()
	var state: MatchState = engine._state
	var seed_card: int = _id(0, B01_SEED)
	var first: Array[MatchEvent] = _play(engine, _typed([seed_card]))
	assert_int(_payload_int(_of_kind(first, SCORED)[0], "flat")).is_equal(1)
	assert_int(state.memory_of(seed_card).flat).is_equal(1)
	assert_bool(_pass(engine).ok).is_true()
	var second: ApplyResult = _pass(engine)
	assert_bool(second.ok).is_true()
	assert_int(_payload_int(_of_kind(second.events, SCORED)[0], "flat")).is_equal(2)
	assert_int(state.memory_of(seed_card).flat).is_equal(2)
	# One growth per walk: seven in round 1.
	_pass_to_round(engine, 2)
	assert_int(state.memory_of(seed_card).flat).is_equal(MatchRules.TURNS)
	var printed: int = _defs().def_of(seed_card).flat
	var grown_flat: int = printed + MatchRules.TURNS
	assert_int(ScoreWalk.effective(seed_card, state, _defs()).flat).is_equal(grown_flat)
	# The redraw: back on top of its deck, then drawn; the hand face shows the growth.
	var piles: MatchState.SeatPiles = state.seats[0]
	piles.hand.erase(seed_card)
	piles.deck.erase(seed_card)
	piles.deck.insert(0, seed_card)
	var drawn: MatchEvent = EffectResolver.draw_card(state, 0)
	assert_int(drawn.kind).is_equal(DRAWN)
	var entry: Dictionary = _hand_entry(engine.view_for(0), seed_card)
	assert_int(entry["flat"]).is_equal(grown_flat)
	assert_bool(entry["grown"]).is_true()
	assert_int(entry["cost"]).is_equal(_cost(seed_card))
	# Played again: it scores with its growth, then grows once more.
	var again: Array[MatchEvent] = _play(engine, _typed([seed_card]))
	var scored: MatchEvent = _of_kind(again, SCORED)[0]
	assert_int(_payload_int(scored, "flat")).is_equal(grown_flat)
	assert_int(_payload_int(scored, "added")).is_equal(grown_flat)
	assert_int(state.memory_of(seed_card).flat).is_equal(MatchRules.TURNS + 1)


# --- Oak: once per match (R6, P7) -----------------------------------------------------


## Oak fires once (×+0.5, `uses_left` 0), then each firing is EFFECT_FIZZLED reason spent
## and nothing else.
func test_oak_fires_once_then_fizzles_spent() -> void:
	var oak: int = _id(0, B15_OAK)
	var state: MatchState = _state(_typed([oak]), _none())
	_reveal(state, 0, _typed([oak]))
	assert_int(ScoreWalk.uses_left(oak, state, _defs())).is_equal(1)
	var first: EffectResolver.Outcome = EffectResolver.apply(state, _defs(), null, null, 0, oak)
	assert_array(_kinds(first.events)).is_equal(_typed([FIRED, STATS]))
	var fired: Dictionary = _fired(0, oak, "grow_self_times_once", "on_score", 0)
	_assert_event(first.events[0], FIRED, fired, PUBLIC)
	_assert_event(first.events[1], STATS, _grown(0, oak, _typed([4, 150, 0])), PUBLIC)
	assert_int(state.memory_of(oak).uses_left).is_equal(0)
	assert_int(ScoreWalk.uses_left(oak, state, _defs())).is_equal(0)
	var second: EffectResolver.Outcome = EffectResolver.apply(state, _defs(), null, null, 0, oak)
	assert_array(_kinds(second.events)).is_equal(_typed([FIZZLED]))
	var spent: Dictionary = _fizzled(0, oak, "grow_self_times_once", EffectResolver.REASON_SPENT)
	_assert_event(second.events[0], FIZZLED, spent, PUBLIC)
	assert_int(state.memory_of(oak).times).is_equal(50)
	assert_int(state.memory_of(oak).uses_left).is_equal(0)


## In play: Oak's one use goes on its first score, `uses_left` 0 stays through round start,
## and played again next round it scores with its ×1.50 and fizzles spent.
func test_oaks_spent_use_persists_across_rounds() -> void:
	var engine: MatchEngine = _engine()
	var state: MatchState = engine._state
	var oak: int = _id(0, B15_OAK)
	var first: Array[MatchEvent] = _play(engine, _typed([oak]))
	var fired: Array[MatchEvent] = _of_kind(first, FIRED)
	assert_int(fired.size()).is_equal(1)
	assert_int(_payload_int(fired[0], "uses_left")).is_equal(0)
	_pass_to_round(engine, 2)
	assert_int(state.memory_of(oak).uses_left).is_equal(0)
	assert_int(state.memory_of(oak).times).is_equal(50)
	var again: Array[MatchEvent] = _play(engine, _typed([oak]))
	assert_int(_of_kind(again, FIRED).size()).is_equal(0)
	var fizzled: Array[MatchEvent] = _of_kind(again, FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	var reason: String = fizzled[0].payload["reason"]
	assert_str(reason).is_equal(EffectResolver.REASON_SPENT)
	assert_int(_payload_int(_of_kind(again, SCORED)[0], "times")).is_equal(150)
	assert_int(state.memory_of(oak).times).is_equal(50)
	# Public wherever the card is: the opponent's row entry shows the spent count.
	var seen: Dictionary = engine.view_for(1).opponent_row[0]
	assert_int(seen["uses_left"]).is_equal(0)


## An unlimited effect makes no memory entry when it fires (take_use).
func test_an_unlimited_effect_writes_no_uses() -> void:
	var state: MatchState = MatchState.new(SEED)
	var sapling: int = _id(0, B05_SAPLING)
	var effect: CardEffect = _defs().def_of(sapling).effect
	assert_int(EffectResolver.take_use(state, sapling, effect)).is_equal(-1)
	assert_bool(state.memory.is_empty()).is_true()


# --- Rain and Redwood: the whole hand (R13) -------------------------------------------


## Rain grows every hand card by +1 flat: one STATS_CHANGED per card, private to the holder
## (the other seat's copy hides the card), the memory written, the walk untouched.
func test_rain_grows_every_hand_card_privately() -> void:
	var rain: int = _id(0, B08_RAIN)
	var hand: Array[int] = [
		_id(0, B02_SPROUT), _id(0, B04_MOSS), _id(0, B13_ELDER), _id(0, B15_OAK)
	]
	var state: MatchState = _state(_typed([rain]), _none())
	state.seats[0].hand.assign(hand)
	_reveal(state, 0, _typed([rain]))
	var walk_before: Dictionary = state.walk.to_dict()
	var outcome: EffectResolver.Outcome = EffectResolver.apply(state, _defs(), null, null, 0, rain)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, STATS, STATS, STATS, STATS]))
	for index: int in range(hand.size()):
		var card: int = hand[index]
		var event: MatchEvent = outcome.events[index + 1]
		var shown: ScoreWalk.Effective = ScoreWalk.effective(card, state, _defs())
		var stats: Array[int] = [shown.flat, shown.times, shown.plus]
		_assert_event(event, STATS, _grown(0, card, stats), 0)
		assert_int(shown.flat).is_equal(_defs().def_of(card).flat + 1)
		assert_int(state.memory_of(card).flat).is_equal(1)
		assert_int(_payload_int(event.redacted_for(1), "card")).is_equal(HIDDEN)
		assert_int(_payload_int(event.redacted_for(0), "card")).is_equal(card)
		assert_int(_payload_int(event.redacted_for(1), "seat")).is_equal(0)
	assert_dict(state.walk.to_dict()).is_equal(walk_before)
	# The hand faces show it at once (R13): the own view's hand entries are grown.
	var view: SeatView = SeatView.build(state, 0, -1, _typed([1, 1]), _defs())
	for card: int in hand:
		var entry: Dictionary = _hand_entry(view, card)
		assert_bool(entry["grown"]).is_true()
	# The other seat's view holds no entry for those cards.
	assert_array(SeatView.build(state, 1, -1, _typed([1, 1]), _defs()).own_hand_row).is_empty()


## In a walk the private events reach the sink with their owner; Redwood grows by 2.
func test_redwood_grows_the_hand_by_two_in_a_walk() -> void:
	var redwood: int = _id(0, B17_REDWOOD)
	var sprout: int = _id(0, B02_SPROUT)
	var state: MatchState = _state(_typed([redwood]), _none())
	state.seats[0].hand.assign(_typed([sprout]))
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_array(_kinds(recorder.events)).is_equal(_typed([REVEALED, FIRED, STATS, SCORED]))
	_assert_event(recorder.events[2], STATS, _grown(0, sprout, _typed([4, 100, 0])), 0)
	assert_int(state.memory_of(sprout).flat).is_equal(2)


## An empty hand: Rain fizzles (no_target) and still scores.
func test_rain_with_an_empty_hand_fizzles() -> void:
	var rain: int = _id(0, B08_RAIN)
	var state: MatchState = _state(_typed([rain]), _none())
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	assert_array(_kinds(recorder.events)).is_equal(_typed([REVEALED, FIRED, FIZZLED, SCORED]))
	var fizzled: Dictionary = _fizzled(0, rain, "grow_hand_flat", EffectResolver.REASON_NO_TARGET)
	_assert_event(recorder.events[2], FIZZLED, fizzled, PUBLIC)


# --- Vine: one hand card by prompt (R20, P8) ------------------------------------------


## Vine opens a prompt over every hand position; the answer grows the chosen card's ×-part,
## the choice and the growth both private to the holder.
func test_vine_prompts_over_the_hand() -> void:
	var vine: int = _id(0, B09_VINE)
	var moss: int = _id(0, B04_MOSS)
	var acorn: int = _id(0, B03_ACORN)
	var state: MatchState = _state(_typed([vine]), _none())
	state.seats[0].hand.assign(_typed([moss, acorn]))
	_reveal(state, 0, _typed([vine]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(state, _defs(), null, null, 0, vine)
	assert_bool(outcome.needs_prompt()).is_true()
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, REQUESTED]))
	var zone: int = outcome.prompt[Choice.KEY_ZONE]
	assert_int(zone).is_equal(OWN_HAND)
	assert_array(Choice.options_of(outcome.prompt)).is_equal(_typed([0, 1]))
	var requested: Dictionary = outcome.events[1].payload
	assert_str(requested["zone"]).is_equal("own_hand")
	assert_bool(requested["multi"]).is_false()
	state.prompt = outcome.prompt
	var view: SeatView = SeatView.build(state, 0, 0, _typed([1, 1]), _defs())
	var view_zone: int = view.prompt["zone"]
	assert_int(view_zone).is_equal(OWN_HAND)
	var answered: Array[MatchEvent] = EffectResolver.answer(state, _defs(), 1)
	assert_array(_kinds(answered)).is_equal(_typed([MADE, STATS]))
	assert_int(answered[0].owner_seat).is_equal(0)
	assert_int(_payload_int(answered[0], "target")).is_equal(acorn)
	assert_int(_payload_int(answered[0].redacted_for(1), "target")).is_equal(HIDDEN)
	# Acorn's printed ×1.25 grows to ×1.50.
	_assert_event(answered[1], STATS, _grown(0, acorn, _typed([1, 150, 0])), 0)
	assert_int(state.memory_of(acorn).times).is_equal(25)
	assert_object(state.memory_of(moss)).is_null()
	assert_dict(state.prompt).is_empty()


## One card in hand: Vine auto-chooses it (CHOICE_MADE auto), no prompt.
func test_vine_auto_chooses_the_only_hand_card() -> void:
	var vine: int = _id(0, B09_VINE)
	var moss: int = _id(0, B04_MOSS)
	var state: MatchState = _state(_typed([vine]), _none())
	state.seats[0].hand.assign(_typed([moss]))
	_reveal(state, 0, _typed([vine]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(state, _defs(), null, null, 0, vine)
	assert_bool(outcome.needs_prompt()).is_false()
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, MADE, STATS]))
	var auto: bool = outcome.events[1].payload["auto"]
	assert_bool(auto).is_true()
	_assert_event(outcome.events[2], STATS, _grown(0, moss, _typed([3, 125, 0])), 0)
	assert_int(state.memory_of(moss).times).is_equal(25)


# --- Tiller: another card of yours by prompt (R20, P8) --------------------------------


## grow_other_flat chooses from the own row: live cards but the source, face up or down; a
## destroyed card is never offered. A face-down target's growth is private to its seat.
func test_tiller_offers_live_own_cards_but_itself() -> void:
	var tiller: int = _id(0, B06_TILLER)
	var sprout: int = _id(0, B02_SPROUT)
	var moss: int = _id(0, B04_MOSS)
	var acorn: int = _id(0, B03_ACORN)
	var state: MatchState = _state(_typed([sprout, tiller, moss, acorn]), _none())
	_reveal(state, 0, _typed([sprout, tiller]))
	state.card_state_for(moss).destroyed = true
	var verb: int = CardEffect.Verb.GROW_OTHER_FLAT
	assert_bool(Choice.needs_choice(verb)).is_true()
	assert_bool(Choice.is_multi(verb)).is_false()
	assert_int(Choice.zone_for(verb)).is_equal(OWN_BOARD)
	assert_int(Choice.zone_for(CardEffect.Verb.GROW_HAND_ONE_TIMES)).is_equal(OWN_HAND)
	assert_bool(Choice.needs_choice(CardEffect.Verb.GROW_HAND_ONE_TIMES)).is_true()
	assert_bool(Choice.needs_choice(CardEffect.Verb.GROW_ROW_FLAT)).is_false()
	var found: Dictionary = Choice.eligible(state, 0, verb, tiller)
	assert_array(Choice.options_of(found)).is_equal(_typed([0, 3]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, tiller
	)
	assert_bool(outcome.needs_prompt()).is_true()
	state.prompt = outcome.prompt
	# The face-down Acorn: private to seat 0.
	var answered: Array[MatchEvent] = EffectResolver.answer(state, _defs(), 3)
	assert_array(_kinds(answered)).is_equal(_typed([MADE, STATS]))
	_assert_event(answered[1], STATS, _grown(0, acorn, _typed([2, 125, 0])), 0)
	# Then the revealed Sprout alone is left (Acorn destroyed): auto-chosen, public.
	state.card_state_for(acorn).destroyed = true
	var again: EffectResolver.Outcome = EffectResolver.apply(state, _defs(), null, null, 0, tiller)
	assert_array(_kinds(again.events)).is_equal(_typed([FIRED, MADE, STATS]))
	_assert_event(again.events[2], STATS, _grown(0, sprout, _typed([3, 100, 0])), PUBLIC)


## Alone on the row, Tiller fizzles.
func test_tiller_alone_fizzles() -> void:
	var tiller: int = _id(0, B06_TILLER)
	var state: MatchState = _state(_typed([tiller]), _none())
	_reveal(state, 0, _typed([tiller]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, tiller
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, FIZZLED]))
	var reason: String = outcome.events[1].payload["reason"]
	assert_str(reason).is_equal(EffectResolver.REASON_NO_TARGET)


# --- Orchard and World Tree: the rest of the row (R12, R13) ---------------------------


## Orchard alone on its row: EFFECT_FIZZLED reason no_target, nothing grows.
func test_orchard_alone_on_the_row_fizzles() -> void:
	var orchard: int = _id(0, B11_ORCHARD)
	var state: MatchState = _state(_typed([orchard]), _typed([_id(1, B04_MOSS)]))
	_reveal(state, 0, _typed([orchard]))
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, orchard
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, FIZZLED]))
	var fired: Dictionary = _fired(0, orchard, "grow_row_flat", "on_reveal", -1)
	_assert_event(outcome.events[0], FIRED, fired, PUBLIC)
	var fizzled: Dictionary = _fizzled(
		0, orchard, "grow_row_flat", EffectResolver.REASON_NO_TARGET
	)
	_assert_event(outcome.events[1], FIZZLED, fizzled, PUBLIC)
	assert_bool(state.memory.is_empty()).is_true()


## Orchard grows each other live card of its own row (face up or down), never a destroyed
## one or the other seat's; World Tree does the same to the ×-part.
func test_orchard_and_world_tree_grow_the_rest_of_the_row() -> void:
	var orchard: int = _id(0, B11_ORCHARD)
	var tree: int = _id(0, B20_WORLD_TREE)
	var moss: int = _id(0, B04_MOSS)
	var bloom: int = _id(0, B18_BLOOM)
	var wreck: int = _id(0, B02_SPROUT)
	var theirs: int = _id(1, B04_MOSS)
	var state: MatchState = _state(_typed([moss, orchard, wreck, bloom, tree]), _typed([theirs]))
	_reveal(state, 0, _typed([moss, orchard, tree]))
	_reveal(state, 1, _typed([theirs]))
	state.card_state_for(wreck).destroyed = true
	var outcome: EffectResolver.Outcome = EffectResolver.apply(
		state, _defs(), null, null, 0, orchard
	)
	assert_array(_kinds(outcome.events)).is_equal(_typed([FIRED, STATS, STATS, STATS]))
	_assert_event(outcome.events[1], STATS, _grown(0, moss, _typed([4, 100, 0])), PUBLIC)
	# Bloom is face down: its growth is private to seat 0.
	_assert_event(outcome.events[2], STATS, _grown(0, bloom, _typed([5, 100, 1])), 0)
	_assert_event(outcome.events[3], STATS, _grown(0, tree, _typed([6, 100, 0])), PUBLIC)
	assert_object(state.memory_of(wreck)).is_null()
	assert_object(state.memory_of(theirs)).is_null()
	var times: EffectResolver.Outcome = EffectResolver.apply(state, _defs(), null, null, 0, tree)
	assert_array(_kinds(times.events)).is_equal(_typed([FIRED, STATS, STATS, STATS]))
	assert_int(state.memory_of(moss).times).is_equal(25)
	assert_int(state.memory_of(orchard).times).is_equal(25)
	assert_int(state.memory_of(bloom).times).is_equal(25)
	assert_int(state.memory_of(tree).times).is_equal(0)


# --- A recovered card (R14) -----------------------------------------------------------


## A grown card of seat 0's, recovered by seat 1 from seat 0's destroyed pile, keeps its
## memory, scores with it on seat 1's row for seat 1, and grows again for seat 1.
func test_a_grown_card_recovered_by_the_other_seat_scores_with_its_growth() -> void:
	var seed_card: int = _id(0, B01_SEED)
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = 1
	state.seats[0].destroyed.assign(_typed([seed_card]))
	state.seats[0].destroyed_known[seed_card] = true
	state.memory_for(seed_card).flat = 3
	var prompt: Dictionary = {
		EffectResolver.KEY_SEAT: 1,
		EffectResolver.KEY_CARD: -1,
		EffectResolver.KEY_VERB: CardEffect.Verb.RECOVER_DESTROYED,
		Choice.KEY_ZONE: Choice.Zone.BOTH_DESTROYED,
		Choice.KEY_OPTIONS: [0],
		Choice.KEY_MULTI: false,
	}
	var recovered: Array[MatchEvent] = EffectResolver.apply_choice(
		state, _defs(), prompt, 0, true
	)
	assert_int(recovered.size()).is_greater(0)
	assert_array(state.seats[1].hand).is_equal(_typed([seed_card]))
	assert_int(state.memory_of(seed_card).flat).is_equal(3)
	# Seat 1 plays it.
	state.seats[1].hand.clear()
	state.seats[1].board.assign(_typed([seed_card]))
	assert_int(state.controller_of(seed_card)).is_equal(1)
	var recorder: Recorder = Recorder.new()
	_walk(state, recorder)
	var scored: MatchEvent = _of_kind(recorder.events, SCORED)[0]
	assert_int(_payload_int(scored, "seat")).is_equal(1)
	assert_int(_payload_int(scored, "flat")).is_equal(4)
	assert_array(state.scores).is_equal(_typed([0, 4]))
	var stats: MatchEvent = _of_kind(recorder.events, STATS)[0]
	_assert_event(stats, STATS, _grown(1, seed_card, _typed([5, 100, 0])), PUBLIC)
	assert_int(state.memory_of(seed_card).flat).is_equal(4)


# --- Previews (P3, P7) ----------------------------------------------------------------


## A preview of a commit holding a grown card equals the live result: same effective cost
## (a reduced Sapling fits a budget of 1), same stats, and the preview's growth stays on its
## clone.
func test_preview_equals_live_with_memory() -> void:
	var engine: MatchEngine = _engine()
	var state: MatchState = engine._state
	var first: int = state.first_seat
	var second: int = 1 - first
	assert_bool(engine.apply(EngineAction.commit(first, _none())).ok).is_true()
	var sapling: int = _id(second, B05_SAPLING)
	_to_hand(state, second, sapling)
	var kept: CardMemory = state.memory_for(sapling)
	kept.cost = 1
	kept.flat = 3
	kept.times = 50
	var action: EngineAction = EngineAction.commit(second, _typed([sapling]))
	var before: Dictionary = engine.full_state()
	var previewed: Array[int] = engine.preview(second, action)
	assert_dict(engine.full_state()).is_equal(before)
	# Flat 1 + 3, ×1.00 + 0.50: 4 × 1.50 = 6.
	assert_int(previewed.size()).is_equal(2)
	assert_int(previewed[second]).is_equal(6)
	var result: ApplyResult = engine.apply(action)
	assert_bool(result.ok).is_true()
	var ended: MatchEvent = _of_kind(result.events, TURN_ENDED)[0]
	var live: Array = ended.payload["scores"]
	assert_array(previewed).is_equal(_typed(live))
	assert_int(state.memory_of(sapling).times).is_equal(75)


## A preview's uses countdown runs on its clone only: Oak's use is still there afterwards.
func test_preview_counts_down_uses_on_the_clone_only() -> void:
	var engine: MatchEngine = _engine()
	var state: MatchState = engine._state
	var first: int = state.first_seat
	var second: int = 1 - first
	assert_bool(engine.apply(EngineAction.commit(first, _none())).ok).is_true()
	var oak: int = _id(second, B15_OAK)
	_to_hand(state, second, oak)
	state.memory_for(oak).cost = 4
	var action: EngineAction = EngineAction.commit(second, _typed([oak]))
	var previewed: Array[int] = engine.preview(second, action)
	assert_int(state.memory_of(oak).uses_left).is_equal(-1)
	var result: ApplyResult = engine.apply(action)
	assert_bool(result.ok).is_true()
	var ended: MatchEvent = _of_kind(result.events, TURN_ENDED)[0]
	var live: Array = ended.payload["scores"]
	assert_array(previewed).is_equal(_typed(live))
	assert_int(state.memory_of(oak).uses_left).is_equal(0)


## Records a walk's events as MatchEvents (the walk's sink).
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
