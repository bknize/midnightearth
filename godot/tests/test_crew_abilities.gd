class_name TestCrewAbilities
extends GdUnitTestSuite
## The six milestone A Crew (DC-13 T07; cycle 9 plan P4, P13; spec R18, R62; canon
## [[rules/crew-v2]], [[rules/resolution]] Q8, Q11, C29): Tallyman's Mult ×2 on the seat's
## 5th, 10th ... Score of a Walk, Void's stacking grant on the next Scoring card, Engineer's
## Budget from Turn 3, Navigator's second scorer and Captain's leftmost card growing as
## Memory after the Score, and Dredger's Pile shuffle (engine stream) with the resumed draw,
## alone and with Void in either Crew slot order. Every match plays the fixture deck
## `stubs` (StubAbilities) with the Crew named per test; the cards a test scores are made
## plain bodies of Power 1 (MatchCards.replace_def), so each total is easy to read.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const EMPTY: int = MatchEvent.Kind.DRAW_EMPTY
const SHUFFLED: int = MatchEvent.Kind.PILE_SHUFFLED_IN
const STATS: int = MatchEvent.Kind.STATS_CHANGED
const ONE: int = MatchRules.SCALE
const GUARD: int = 100
## Void and Dredger in either Crew slot order (C29).
const VOID_FIRST: Array[String] = ["void", "dredger", "engineer"]
const DREDGER_FIRST: Array[String] = ["dredger", "void", "engineer"]
const VERB_DRAW: String = "test_draw"

# --- Helpers --------------------------------------------------------------------------


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## The stub match's definitions with the Crew `crew` on both seats, `instances` made plain
## bodies of Power 1.
func _cards(crew: Array[String], instances: Array[int]) -> MatchCards:
	var cards: MatchCards = StubAbilities.defs(crew)
	var none: Array[CardAbility] = []
	var plain: CardDef = StubAbilities.card_def("Plain", none, 1)
	assert_bool(StubAbilities.give(cards, instances, plain)).is_true()
	return cards


## Runs a whole Walk on `state` (begin() to its end), recording into `rec`.
func _walk(state: MatchState, cards: MatchCards, rec: StubAbilities.Recorder) -> void:
	var rng: MatchRng = MatchRng.new(SEED)
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < GUARD:
		guard += 1
		assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_false()


func _ints(events: Array[MatchEvent], key: String) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		var value: int = event.payload.get(key, -1)
		out.append(value)
	return out


func _crews(events: Array[MatchEvent]) -> Array[String]:
	var out: Array[String] = []
	for event: MatchEvent in events:
		var crew: String = event.payload.get("crew", "")
		out.append(crew)
	return out


func _kinds(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		out.append(event.kind)
	return out


func _memory_power(state: MatchState, card: int) -> int:
	var kept: CardMemory = state.memory_of(card)
	return kept.power if kept != null else 0


## A state whose seat 0 has an empty Deck, the Pile `pile` and the hand `hand`.
func _dry(pile: Array[int], hand: Array[int]) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].pile.assign(pile)
	state.seats[0].hand.assign(hand)
	return state


# --- Tallyman -------------------------------------------------------------------------


## Ten Power 1 cards: the 5th and the 10th Score with Bonus value 2 (Mult ×2) and every
## other with 1, so the ×2 is that Score's only: 1, 2, 3, 4, (5) × 2 = 10, ..., (15) × 2.
func test_tallyman_doubles_the_fifth_and_tenth_scoring_card_for_that_score_only() -> void:
	var row: Array[int] = _typed(range(10))
	var cards: MatchCards = _cards(StubAbilities.CREW, row)
	var state: MatchState = StubAbilities.table(row, true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	var scored: Array[MatchEvent] = rec.of_kind(SCORED)
	assert_array(rec.cards_of(SCORED)).is_equal(row)
	var single: Array[int] = [ONE, ONE, ONE, ONE, 2 * ONE]
	var expected: Array[int] = []
	expected.append_array(single)
	expected.append_array(single)
	assert_array(_ints(scored, "bonus_value")).is_equal(expected)
	assert_array(_ints(scored, "total").slice(3, 6)).is_equal(_typed([40000, 100000, 110000]))
	assert_int(state.totals[0]).is_equal(300000)
	assert_int(state.scores[0]).is_equal(30)
	assert_array(rec.of_kind(FIRED)).is_empty()


## A Squelched card does not Score, so it does not count: with the third of six Squelched,
## the 5th Scoring card is the sixth on the row.
func test_a_squelched_card_does_not_count_for_tallyman() -> void:
	var row: Array[int] = _typed(range(6))
	var cards: MatchCards = _cards(StubAbilities.CREW, row)
	var state: MatchState = StubAbilities.table(row, true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(StubAbilities.stub_squelch(state, cards, 2, rec.record).landed.is_empty()).is_false()
	_walk(state, cards, rec)
	var scored: Array[MatchEvent] = rec.of_kind(SCORED)
	assert_array(rec.cards_of(SCORED)).is_equal(_typed([0, 1, 3, 4, 5]))
	assert_array(_ints(scored, "bonus_value")).is_equal(_typed([ONE, ONE, ONE, ONE, 2 * ONE]))
	assert_int(state.walk.scored_count[0]).is_equal(5)


## A card that Scores twice counts twice (Q7): after a stub sets Scores twice on the first
## pulse, the next two cards Score twice each, and the second's second Score is the 5th.
func test_a_card_scoring_twice_counts_twice_for_tallyman() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(StubAbilities.CREW, _typed([1, 2]))
	cards.set_verb_handler(verbs)
	var twice: Array[CardAbility] = [
		StubAbilities.ability("on_reveal", StubAbilities.VERB_SCORES_TWICE)
	]
	var reprise: CardDef = StubAbilities.card_def("Reprise", twice, 1)
	assert_bool(StubAbilities.give(cards, _typed([0]), reprise)).is_true()
	var state: MatchState = StubAbilities.table(_typed([0, 1, 2]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	var scored: Array[MatchEvent] = rec.of_kind(SCORED)
	assert_array(rec.cards_of(SCORED)).is_equal(_typed([0, 1, 1, 2, 2]))
	assert_array(_ints(scored, "pass")).is_equal(_typed([1, 1, 2, 1, 2]))
	assert_array(_ints(scored, "bonus_value")).is_equal(_typed([ONE, ONE, ONE, ONE, 2 * ONE]))
	assert_int(state.walk.scored_count[0]).is_equal(5)


# --- Void -----------------------------------------------------------------------------


## Void alone on an empty Deck: nothing is drawn (the Pile stays put), Void fires and holds
## one grant. The seat's next Scoring card gets Power +10, Add +0.5 and Mult ×1.25 (Bonus
## value 18750) for its Score, the other seat's card before it gets nothing, and the grant
## ends once it has Scored: the card after it is plain again.
func test_void_grants_the_next_scoring_card_once_and_alone_draws_nothing() -> void:
	var cards: MatchCards = _cards(StubAbilities.CREW, _typed([0, 1, OTHER]))
	var state: MatchState = _dry(_typed([20, 21]), _typed([]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.draw(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	assert_int(rec.of_kind(EMPTY).size()).is_equal(1)
	assert_array(rec.of_kind(DRAWN)).is_empty()
	assert_array(rec.of_kind(SHUFFLED)).is_empty()
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["void"])
	assert_array(state.seats[0].hand).is_empty()
	assert_array(state.seats[0].deck).is_empty()
	assert_array(state.seats[0].pile).is_equal(_typed([20, 21]))
	assert_array(state.void_grants).is_equal(_typed([1, 0]))
	StubAbilities.put_row(state, 0, _typed([0, 1]), true)
	StubAbilities.put_row(state, 1, _typed([OTHER]), true)
	state.first_seat = 1
	var walk: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, walk)
	var scored: Array[MatchEvent] = walk.of_kind(SCORED)
	assert_array(walk.cards_of(SCORED)).is_equal(_typed([OTHER, 0, 1]))
	assert_array(_ints(scored, "power")).is_equal(_typed([1, 11, 1]))
	assert_array(_ints(scored, "bonus_value")).is_equal(_typed([ONE, 18750, ONE]))
	assert_array(_ints(scored, "total")).is_equal(_typed([ONE, 206250, 216250]))
	assert_array(state.void_grants).is_equal(_typed([0, 0]))


## Two empty draws in one Turn stack: the same card gets the grant twice (Power +20, two
## Adds, two Mults: (1 + 1) × 1.25 × 1.25 = 3.125). Unused grants end at turn end.
func test_two_empty_draws_stack_and_unused_grants_end_at_turn_end() -> void:
	var cards: MatchCards = _cards(StubAbilities.CREW, _typed([0]))
	var state: MatchState = _dry(_typed([]), _typed([]))
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	for _draw: int in range(2):
		assert_bool(TurnFlow.draw(state, cards, rng, rec.record, 0)).is_false()
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["void", "void"])
	assert_array(state.void_grants).is_equal(_typed([2, 0]))
	StubAbilities.put_row(state, 0, _typed([0]), true)
	var granted: Scoring.Stats = Scoring.score_stats(0, state, cards, 0, 1)
	assert_int(granted.power).is_equal(21)
	assert_int(granted.add()).is_equal(100)
	assert_int(granted.bonus_value()).is_equal(31250)
	state.void_grants[0] = 1
	assert_int(Scoring.score_stats(0, state, cards, 0, 1).bonus_value()).is_equal(18750)
	assert_bool(TurnFlow.end_turn(state, cards, rng, rec.record)).is_false()
	assert_array(state.void_grants).is_equal(_typed([0, 0]))
	var plain: Scoring.Stats = Scoring.score_stats(0, state, cards, 0, 1)
	assert_int(plain.power).is_equal(1)
	assert_int(plain.bonus_value()).is_equal(ONE)


## The grants are state: a copy carries them and is independent, and to_dict() lists them.
func test_void_grants_are_copied_and_serialized() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.void_grants[1] = 2
	var copy: MatchState = state.duplicate()
	assert_dict(copy.to_dict()).is_equal(state.to_dict())
	assert_array(state.to_dict()["void_grants"]).is_equal([0, 2])
	copy.void_grants[1] = 0
	assert_array(state.void_grants).is_equal(_typed([0, 2]))


# --- Engineer -------------------------------------------------------------------------


## Engineer: the Budget is the Turn on Turns 1 and 2 and the Turn + 1 from Turn 3, for both
## seats; without Engineer it is the Turn.
func test_engineer_budget_is_turn_plus_1_from_turn_3() -> void:
	var cards: MatchCards = StubAbilities.defs(StubAbilities.CREW)
	var ramp: MatchCards = StubAbilities.defs(StubAbilities.RAMP_CREW)
	var state: MatchState = MatchState.new(SEED)
	for turn: int in range(1, MatchRules.TURNS + 1):
		state.turn = turn
		var bonus: int = 1 if turn >= 3 else 0
		for seat: int in range(2):
			assert_int(TurnFlow.budget(state, cards, seat)).is_equal(turn + bonus)
			assert_int(TurnFlow.budget(state, ramp, seat)).is_equal(turn)


# --- Navigator and Captain ------------------------------------------------------------


## Ramp's Crew over a row of three Power 1 cards: the slot-0 card gets Power +1 for the
## match (Captain) and the second Scoring card Power +2 (Navigator), each after its Score,
## public STATS_CHANGED with the Crew as cause; the other wakes fizzle `no_target`. The next
## Walk Scores them at 2, 3, 1 and grows them again: Captain per Score, Navigator per Walk.
func test_navigator_grows_the_second_scorer_and_captain_the_leftmost_after_the_score() -> void:
	var row: Array[int] = [0, 1, 2]
	var cards: MatchCards = _cards(StubAbilities.RAMP_CREW, row)
	var state: MatchState = StubAbilities.table(row, true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(_ints(rec.of_kind(SCORED), "power")).is_equal(_typed([1, 1, 1]))
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["captain", "navigator"])
	var fizzled: Array[MatchEvent] = rec.of_kind(FIZZLED)
	assert_array(_crews(fizzled)).is_equal(["navigator", "captain", "navigator", "captain"])
	for event: MatchEvent in fizzled:
		var reason: String = event.payload["reason"]
		assert_str(reason).is_equal(Abilities.REASON_NO_TARGET)
	var grown: Array[MatchEvent] = rec.of_kind(STATS)
	assert_array(rec.cards_of(STATS)).is_equal(_typed([0, 1]))
	assert_array(_ints(grown, "power")).is_equal(_typed([2, 3]))
	var causes: Array[String] = []
	for event: MatchEvent in grown:
		assert_int(event.owner_seat).is_equal(MatchEvent.PUBLIC)
		var permanent: bool = event.payload["permanent"]
		assert_bool(permanent).is_true()
		var cause: String = event.payload["cause"]
		causes.append(cause)
	assert_array(causes).is_equal(["captain", "navigator"])
	# Each change comes after the Score that woke it.
	var kinds: Array[int] = _kinds(rec.events)
	assert_int(kinds.find(STATS)).is_greater(kinds.find(SCORED))
	assert_array(
		_typed([_memory_power(state, 0), _memory_power(state, 1), _memory_power(state, 2)])
	).is_equal(_typed([1, 2, 0]))
	var again: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, again)
	assert_array(_ints(again.of_kind(SCORED), "power")).is_equal(_typed([2, 3, 1]))
	assert_array(
		_typed([_memory_power(state, 0), _memory_power(state, 1), _memory_power(state, 2)])
	).is_equal(_typed([2, 4, 0]))


# --- Dredger --------------------------------------------------------------------------


## Dredger at a turn-start draw from an empty Deck: the Pile goes into the Deck shuffled by
## the engine stream (PILE_SHUFFLED_IN {seat, count}, public), then the resumed draw takes
## the new top card once (CARD_DRAWN, private); one DRAW_EMPTY, no second On empty draw.
func test_dredger_shuffles_the_pile_in_with_the_stream_and_the_draw_resumes_once() -> void:
	var cards: MatchCards = StubAbilities.defs(StubAbilities.RAMP_CREW)
	var pile: Array[int] = [20, 21, 22, 23, 24]
	var state: MatchState = _dry(pile, _typed([0]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.draw(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	var expected: Array[int] = _typed(pile)
	MatchRng.new(SEED).shuffle_in_place(expected)
	assert_array(state.seats[0].hand).is_equal(_typed([0, expected[0]]))
	assert_array(state.seats[0].deck).is_equal(expected.slice(1))
	assert_array(state.seats[0].pile).is_empty()
	assert_array(_kinds(rec.events)).is_equal(_typed([EMPTY, FIRED, SHUFFLED, DRAWN]))
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["dredger"])
	var shuffled: MatchEvent = rec.of_kind(SHUFFLED)[0]
	assert_int(shuffled.owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_dict(shuffled.payload).is_equal({"seat": 0, "count": 5})
	var drawn: MatchEvent = rec.of_kind(DRAWN)[0]
	assert_int(drawn.owner_seat).is_equal(0)


## Dredger with an empty Pile has nothing to shuffle: it fizzles `no_target` and nothing is
## drawn.
func test_dredger_with_an_empty_pile_fizzles() -> void:
	var cards: MatchCards = StubAbilities.defs(StubAbilities.RAMP_CREW)
	var state: MatchState = _dry(_typed([]), _typed([]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.draw(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	assert_array(_crews(rec.of_kind(FIZZLED))).is_equal(["dredger"])
	assert_array(rec.of_kind(SHUFFLED)).is_empty()
	assert_array(rec.of_kind(DRAWN)).is_empty()


## An effect's draw (a stub On reveal "draw a card") from an empty Deck: Dredger's Batch
## shuffles the Pile in, then the denied draw is made once right after it (Q11), with no
## second DRAW_EMPTY.
func test_dredger_resumes_an_effect_draw_once() -> void:
	var cards: MatchCards = StubAbilities.defs(StubAbilities.RAMP_CREW)
	cards.set_verb_handler(DrawVerbs.new())
	var draws: Array[CardAbility] = [StubAbilities.ability("on_reveal", VERB_DRAW)]
	var drawer: CardDef = StubAbilities.card_def("Drawer", draws, 1)
	assert_bool(StubAbilities.give(cards, _typed([0]), drawer)).is_true()
	var pile: Array[int] = [20, 21, 22]
	var state: MatchState = _dry(pile, _typed([]))
	StubAbilities.put_row(state, 0, _typed([0]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TriggerQueue.wake(state, cards, "on_reveal", _typed([0])).is_empty()).is_false()
	assert_bool(TriggerQueue.drain(state, cards, rng, rec.record, "D2")).is_false()
	var expected: Array[int] = _typed(pile)
	MatchRng.new(SEED).shuffle_in_place(expected)
	assert_array(state.seats[0].hand).is_equal(_typed([expected[0]]))
	assert_array(state.seats[0].deck).is_equal(expected.slice(1))
	assert_array(_kinds(rec.events)).is_equal(_typed([FIRED, EMPTY, FIRED, SHUFFLED, DRAWN]))
	assert_bool(state.queue.is_empty()).is_true()


# --- Void and Dredger together (C29) --------------------------------------------------


## Void and Dredger both fire on one empty draw, in Crew slot order either way, with no
## re-check of the Deck: the Pile is shuffled in, Void's grant is held and the resumed draw
## succeeds once.
func test_void_and_dredger_both_fire_in_either_slot_order_and_the_draw_succeeds() -> void:
	for crew: Array[String] in [VOID_FIRST, DREDGER_FIRST]:
		var cards: MatchCards = StubAbilities.defs(crew)
		var state: MatchState = _dry(_typed([20, 21, 22]), _typed([]))
		var rec: StubAbilities.Recorder = StubAbilities.recorder()
		assert_bool(TurnFlow.draw(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
		var expected_crew: Array[String] = crew.slice(0, 2)
		assert_array(_crews(rec.of_kind(FIRED))).is_equal(expected_crew)
		assert_array(rec.of_kind(FIZZLED)).is_empty()
		assert_int(rec.of_kind(EMPTY).size()).is_equal(1)
		assert_int(rec.of_kind(SHUFFLED).size()).is_equal(1)
		assert_int(rec.of_kind(DRAWN).size()).is_equal(1)
		assert_int(state.seats[0].hand.size()).is_equal(1)
		assert_int(state.seats[0].deck.size()).is_equal(2)
		assert_array(state.seats[0].pile).is_empty()
		assert_array(state.void_grants).is_equal(_typed([1, 0]))


## A stub verb table with one verb, `test_draw`: its card's Controller draws a card
## (TriggerContext.draw, the effect draw of Q11).
class DrawVerbs:
	extends VerbHandler

	func handles(verb: String) -> bool:
		return verb == VERB_DRAW

	func resolve(ctx: TriggerContext) -> void:
		var drawn: int = ctx.draw(ctx.seat)
		if drawn < 0:
			pass  # The Deck was empty: the On empty draw Batch is queued.
