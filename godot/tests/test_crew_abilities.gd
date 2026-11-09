# gdlint: disable=max-public-methods
class_name TestCrewAbilities
extends GdUnitTestSuite
## The six milestone A Crew (DC-13 T07; cycle 9 plan P4, P13; spec R18, R62; canon
## [[rules/crew-v2]], [[rules/resolution]] Q8, Q11, C29): Tallyman's Mult ×2 on the seat's
## 5th, 10th ... Score of a Walk, Void's stacking grant on the next Scoring card, Engineer's
## Budget from Turn 3, Navigator's second scorer and Captain's leftmost card growing as
## Memory after the Score, and Dredger's Pile shuffle (engine stream) with the resumed draw,
## alone and with Void in either Crew slot order. Milestone B (DC-14 T14): Shade's prompt
## after the exit pass over up to three random revealed cards (and its skip with none),
## Veil's Fleeting in the same pass and over Wraith, Quartermaster's Hand size 7 (9 with
## Pantry), and Salvager's prompt once per own Commit, its decline, and its Discard waking
## On discard before the discard-down. Every match plays the fixture deck
## `stubs` (StubAbilities) with the Crew named per test; the cards a test scores are made
## plain bodies of Power 1 (StubAbilities.replace_def), so each total is easy to read.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const EMPTY: int = MatchEvent.Kind.DRAW_EMPTY
const SHUFFLED: int = MatchEvent.Kind.PILE_SHUFFLED_IN
const STATS: int = MatchEvent.Kind.STATS_CHANGED
const CREW: int = MatchEvent.Kind.CREW_FIRED
## CREW_FIRED's payload keys, in order (rules 9, cycle 14 R13, plan P7).
const CREW_FIRED_KEYS: Array[String] = ["seat", "slot", "crew", "moment", "verb", "uses_left"]
const ONE: int = MatchRules.SCALE
const GUARD: int = 100
## Void and Dredger in either Crew slot order (C29).
const VOID_FIRST: Array[String] = ["void", "dredger", "engineer"]
const DREDGER_FIRST: Array[String] = ["dredger", "void", "engineer"]
const VERB_DRAW: String = "test_draw"
const OPENED: int = MatchEvent.Kind.PROMPT_OPENED
const DECLINED: int = MatchEvent.Kind.CHOICE_DECLINED
const DISCARDED: int = MatchEvent.Kind.CARD_DISCARDED
const MARKED: int = MatchEvent.Kind.EXIT_MARKED
const EXIT_RESOLVED: int = MatchEvent.Kind.EXIT_RESOLVED
const UNREVEALED: int = MatchEvent.Kind.CARD_UNREVEALED
## Milestone B's decks' Crew (DC-14 T14): Combo's (Shade at D11, Quartermaster) and
## Graveyard's (Veil at D9, Salvager On commit).
const COMBO_CREW: Array[String] = ["shade", "quartermaster", "engineer"]
const GRAVEYARD_CREW: Array[String] = ["veil", "salvager", "dredger"]

# --- Helpers --------------------------------------------------------------------------


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
	var row: Array[int] = Typed.ints(range(10))
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
	assert_array(_ints(scored, "total").slice(3, 6)).is_equal(Typed.ints([40000, 100000, 110000]))
	assert_int(state.totals[0]).is_equal(300000)
	assert_int(state.scores[0]).is_equal(30)
	assert_array(rec.of_kind(FIRED)).is_empty()


## A Squelched card does not Score, so it does not count: with the third of six Squelched,
## the 5th Scoring card is the sixth on the row.
func test_a_squelched_card_does_not_count_for_tallyman() -> void:
	var row: Array[int] = Typed.ints(range(6))
	var cards: MatchCards = _cards(StubAbilities.CREW, row)
	var state: MatchState = StubAbilities.table(row, true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(StubAbilities.stub_squelch(state, cards, 2, rec.record).landed.is_empty()).is_false()
	_walk(state, cards, rec)
	var scored: Array[MatchEvent] = rec.of_kind(SCORED)
	assert_array(rec.cards_of(SCORED)).is_equal(Typed.ints([0, 1, 3, 4, 5]))
	assert_array(_ints(scored, "bonus_value")).is_equal(Typed.ints([ONE, ONE, ONE, ONE, 2 * ONE]))
	assert_int(state.walk.scored_count[0]).is_equal(5)


## A card that Scores twice counts twice (Q7): after a stub sets Scores twice on the first
## pulse, the next two cards Score twice each, and the second's second Score is the 5th.
func test_a_card_scoring_twice_counts_twice_for_tallyman() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(StubAbilities.CREW, Typed.ints([1, 2]))
	cards.set_verb_handler(verbs)
	var twice: Array[CardAbility] = [
		StubAbilities.ability("on_reveal", StubAbilities.VERB_SCORES_TWICE)
	]
	var reprise: CardDef = StubAbilities.card_def("Reprise", twice, 1)
	assert_bool(StubAbilities.give(cards, Typed.ints([0]), reprise)).is_true()
	var state: MatchState = StubAbilities.table(Typed.ints([0, 1, 2]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	var scored: Array[MatchEvent] = rec.of_kind(SCORED)
	assert_array(rec.cards_of(SCORED)).is_equal(Typed.ints([0, 1, 1, 2, 2]))
	assert_array(_ints(scored, "pass")).is_equal(Typed.ints([1, 1, 2, 1, 2]))
	assert_array(_ints(scored, "bonus_value")).is_equal(Typed.ints([ONE, ONE, ONE, ONE, 2 * ONE]))
	assert_int(state.walk.scored_count[0]).is_equal(5)


# --- Void -----------------------------------------------------------------------------


## Void alone on an empty Deck: nothing is drawn (the Pile stays put), Void fires and holds
## one grant. The seat's next Scoring card gets Power +10, Add +0.5 and Mult ×1.25 (Bonus
## value 18750) for its Score, the other seat's card before it gets nothing, and the grant
## ends once it has Scored: the card after it is plain again.
func test_void_grants_the_next_scoring_card_once_and_alone_draws_nothing() -> void:
	var cards: MatchCards = _cards(StubAbilities.CREW, Typed.ints([0, 1, OTHER]))
	var state: MatchState = _dry(Typed.ints([20, 21]), Typed.ints([]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.draw(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	assert_int(rec.of_kind(EMPTY).size()).is_equal(1)
	assert_array(rec.of_kind(DRAWN)).is_empty()
	assert_array(rec.of_kind(SHUFFLED)).is_empty()
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["void"])
	assert_array(state.seats[0].hand).is_empty()
	assert_array(state.seats[0].deck).is_empty()
	assert_array(state.seats[0].pile).is_equal(Typed.ints([20, 21]))
	assert_array(state.void_grants).is_equal(Typed.ints([1, 0]))
	StubAbilities.put_row(state, 0, Typed.ints([0, 1]), true)
	StubAbilities.put_row(state, 1, Typed.ints([OTHER]), true)
	state.first_seat = 1
	var walk: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, walk)
	var scored: Array[MatchEvent] = walk.of_kind(SCORED)
	assert_array(walk.cards_of(SCORED)).is_equal(Typed.ints([OTHER, 0, 1]))
	assert_array(_ints(scored, "power")).is_equal(Typed.ints([1, 11, 1]))
	assert_array(_ints(scored, "bonus_value")).is_equal(Typed.ints([ONE, 18750, ONE]))
	assert_array(_ints(scored, "total")).is_equal(Typed.ints([ONE, 206250, 216250]))
	assert_array(state.void_grants).is_equal(Typed.ints([0, 0]))


## Two empty draws in one Turn stack: the same card gets the grant twice (Power +20, two
## Adds, two Mults: (1 + 1) × 1.25 × 1.25 = 3.125). Unused grants end at turn end.
func test_two_empty_draws_stack_and_unused_grants_end_at_turn_end() -> void:
	var cards: MatchCards = _cards(StubAbilities.CREW, Typed.ints([0]))
	var state: MatchState = _dry(Typed.ints([]), Typed.ints([]))
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	for _draw: int in range(2):
		assert_bool(TurnFlow.draw(state, cards, rng, rec.record, 0)).is_false()
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["void", "void"])
	assert_array(state.void_grants).is_equal(Typed.ints([2, 0]))
	StubAbilities.put_row(state, 0, Typed.ints([0]), true)
	var granted: Scoring.Stats = Scoring.score_stats(0, state, cards, 0, 1)
	assert_int(granted.power).is_equal(21)
	assert_int(granted.add()).is_equal(100)
	assert_int(granted.bonus_value()).is_equal(31250)
	state.void_grants[0] = 1
	assert_int(Scoring.score_stats(0, state, cards, 0, 1).bonus_value()).is_equal(18750)
	assert_bool(TurnFlow.end_turn(state, cards, rng, rec.record)).is_false()
	assert_array(state.void_grants).is_equal(Typed.ints([0, 0]))
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
	assert_array(state.void_grants).is_equal(Typed.ints([0, 2]))


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
	assert_array(_ints(rec.of_kind(SCORED), "power")).is_equal(Typed.ints([1, 1, 1]))
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["captain", "navigator"])
	var fizzled: Array[MatchEvent] = rec.of_kind(FIZZLED)
	assert_array(_crews(fizzled)).is_equal(["navigator", "captain", "navigator", "captain"])
	for event: MatchEvent in fizzled:
		var reason: String = event.payload["reason"]
		assert_str(reason).is_equal(Abilities.REASON_NO_TARGET)
	var grown: Array[MatchEvent] = rec.of_kind(STATS)
	assert_array(rec.cards_of(STATS)).is_equal(Typed.ints([0, 1]))
	assert_array(_ints(grown, "power")).is_equal(Typed.ints([2, 3]))
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
		Typed.ints([_memory_power(state, 0), _memory_power(state, 1), _memory_power(state, 2)])
	).is_equal(Typed.ints([1, 2, 0]))
	var again: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, again)
	assert_array(_ints(again.of_kind(SCORED), "power")).is_equal(Typed.ints([2, 3, 1]))
	assert_array(
		Typed.ints([_memory_power(state, 0), _memory_power(state, 1), _memory_power(state, 2)])
	).is_equal(Typed.ints([2, 4, 0]))


# --- Limited uses and CREW_FIRED (rules 9, cycle 14 R6, R7, R13) ----------------------


## A fixture Crew pool built from the shipped one in memory (its file is never edited):
## `crew_id` gets `uses` and `scope`.
func _limited_pool(crew_id: String, uses: int, scope: String) -> CrewPool:
	var listed: Array = []
	for def: CrewDef in CrewPool.load_default().all():
		var entry: Dictionary = def.to_dict()
		if def.id == crew_id:
			entry["uses"] = uses
			entry["scope"] = scope
		listed.append(entry)
	var text: String = JSON.stringify({"version": CrewPool.FORMAT_VERSION, "crew": listed})
	var pool: CrewPool = CrewPool.from_json(text)
	assert_bool(pool.is_valid()).override_failure_message(pool.load_error()).is_true()
	return pool


## The stub match's definitions over `pool` with the Crew `crew` on both seats, `instances`
## made plain bodies of Power 1; the Crew uses filled as at Match start.
func _limited_cards(crew: Array[String], pool: CrewPool, instances: Array[int]) -> MatchCards:
	var ids: Array[String] = [StubAbilities.DECK_ID, StubAbilities.DECK_ID]
	var decks: DeckList = StubAbilities.deck_list(crew)
	var cards: MatchCards = MatchCards.build(CardDb.load_default(), decks, ids, pool)
	var none: Array[CardAbility] = []
	var plain: CardDef = StubAbilities.card_def("Plain", none, 1)
	assert_bool(StubAbilities.give(cards, instances, plain)).is_true()
	return cards


## The `reason` of every TRIGGER_FIZZLED of the Crew `crew_id` in `events`.
func _crew_reasons(events: Array[MatchEvent], crew_id: String) -> Array[String]:
	var out: Array[String] = []
	for event: MatchEvent in events:
		var crew: String = event.payload.get("crew", "")
		if event.kind == FIZZLED and crew == crew_id:
			var reason: String = event.payload["reason"]
			out.append(reason)
	return out


## A fixture Captain with `uses` 1 for the match (Ramp's Crew, Captain in slot 1): it fires
## once, on the slot-0 card's Score, and CREW_FIRED {seat, slot, crew, moment, verb,
## uses_left} (exactly those keys, public) shows `uses_left` 0; the unlimited Navigator's
## shows -1. Every later wake of Captain, that Walk and the next, fizzles `spent`: no
## TRIGGER_FIRED, no CREW_FIRED and no growth.
func test_a_crew_with_one_use_fires_once_and_crew_fired_shows_the_uses_left() -> void:
	var row: Array[int] = [0, 1, 2]
	var pool: CrewPool = _limited_pool("captain", 1, "")
	var cards: MatchCards = _limited_cards(StubAbilities.RAMP_CREW, pool, row)
	var state: MatchState = StubAbilities.table(row, true)
	state.reset_crew_uses(cards)
	assert_array(state.crew_uses[0]).is_equal([CrewDef.UNLIMITED, 1, CrewDef.UNLIMITED])
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["captain", "navigator"])
	var crew_fired: Array[MatchEvent] = rec.of_kind(CREW)
	assert_array(_crews(crew_fired)).is_equal(["captain", "navigator"])
	var captain: MatchEvent = crew_fired[0]
	assert_int(captain.owner_seat).is_equal(MatchEvent.PUBLIC)
	var keys: Array[String] = []
	keys.assign(captain.payload.keys())
	assert_array(keys).is_equal(CREW_FIRED_KEYS)
	var expected: Dictionary = {
		"seat": 0,
		"slot": 1,
		"crew": "captain",
		"moment": "on_score",
		"verb": CrewAbilities.VERB_CAPTAIN,
		"uses_left": 0,
	}
	assert_dict(captain.payload).is_equal(expected)
	var navigator: int = crew_fired[1].payload["uses_left"]
	assert_int(navigator).is_equal(CrewDef.UNLIMITED)
	assert_array(_crew_reasons(rec.events, "captain")).is_equal(
		[Abilities.REASON_SPENT, Abilities.REASON_SPENT]
	)
	assert_array(state.crew_uses[0]).is_equal([CrewDef.UNLIMITED, 0, CrewDef.UNLIMITED])
	assert_int(_memory_power(state, 0)).is_equal(1)
	var again: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, again)
	assert_array(_crews(again.of_kind(FIRED))).is_equal(["navigator"])
	assert_array(_crews(again.of_kind(CREW))).is_equal(["navigator"])
	var spent: Array[String] = [
		Abilities.REASON_SPENT, Abilities.REASON_SPENT, Abilities.REASON_SPENT
	]
	assert_array(_crew_reasons(again.events, "captain")).is_equal(spent)
	assert_int(_memory_power(state, 0)).is_equal(1)


## A fixture Void with `uses` 1 per Turn: the first empty draw fires it (CREW_FIRED
## `uses_left` 0), the second that Turn wakes no firing (`spent`, one grant held); after
## turn end its use is back and the next empty draw fires it again.
func test_a_once_per_turn_crew_fires_again_after_turn_end() -> void:
	var pool: CrewPool = _limited_pool("void", 1, Abilities.SCOPE_TURN)
	var cards: MatchCards = _limited_cards(StubAbilities.CREW, pool, Typed.ints([]))
	var state: MatchState = _dry(Typed.ints([]), Typed.ints([]))
	state.reset_crew_uses(cards)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	for _draw: int in range(2):
		assert_bool(TurnFlow.draw(state, cards, rng, rec.record, 0)).is_false()
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["void"])
	assert_array(_ints(rec.of_kind(CREW), "uses_left")).is_equal(Typed.ints([0]))
	assert_array(_crew_reasons(rec.events, "void")).is_equal([Abilities.REASON_SPENT])
	assert_array(state.void_grants).is_equal(Typed.ints([1, 0]))
	assert_bool(TurnFlow.end_turn(state, cards, rng, rec.record)).is_false()
	assert_array(state.crew_uses[0]).is_equal([CrewDef.UNLIMITED, 1, CrewDef.UNLIMITED])
	var next: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.draw(state, cards, rng, next.record, 0)).is_false()
	assert_array(_crews(next.of_kind(FIRED))).is_equal(["void"])
	assert_array(_ints(next.of_kind(CREW), "uses_left")).is_equal(Typed.ints([0]))


## R7: every shipped Crew has `uses` 0 (unlimited, CrewDef.UNLIMITED at Match start), so
## enforcing uses changes no shipped Crew.
func test_no_shipped_crew_has_limited_uses() -> void:
	for def: CrewDef in CrewPool.load_default().all():
		assert_int(def.uses).override_failure_message(def.id).is_equal(0)
		assert_int(def.initial_uses()).is_equal(CrewDef.UNLIMITED)


# --- Dredger --------------------------------------------------------------------------


## Dredger at a turn-start draw from an empty Deck: the Pile goes into the Deck shuffled by
## the engine stream (PILE_SHUFFLED_IN {seat, count}, public), then the resumed draw takes
## the new top card once (CARD_DRAWN, private); one DRAW_EMPTY, no second On empty draw.
func test_dredger_shuffles_the_pile_in_with_the_stream_and_the_draw_resumes_once() -> void:
	var cards: MatchCards = StubAbilities.defs(StubAbilities.RAMP_CREW)
	var pile: Array[int] = [20, 21, 22, 23, 24]
	var state: MatchState = _dry(pile, Typed.ints([0]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.draw(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	var expected: Array[int] = Typed.ints(pile)
	MatchRng.new(SEED).shuffle_in_place(expected)
	assert_array(state.seats[0].hand).is_equal(Typed.ints([0, expected[0]]))
	assert_array(state.seats[0].deck).is_equal(expected.slice(1))
	assert_array(state.seats[0].pile).is_empty()
	assert_array(_kinds(rec.events)).is_equal(Typed.ints([EMPTY, FIRED, SHUFFLED, CREW, DRAWN]))
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
	var state: MatchState = _dry(Typed.ints([]), Typed.ints([]))
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
	assert_bool(StubAbilities.give(cards, Typed.ints([0]), drawer)).is_true()
	var pile: Array[int] = [20, 21, 22]
	var state: MatchState = _dry(pile, Typed.ints([]))
	StubAbilities.put_row(state, 0, Typed.ints([0]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TriggerQueue.wake(state, cards, "on_reveal", Typed.ints([0])).is_empty()).is_false()
	assert_bool(TriggerQueue.drain(state, cards, rng, rec.record, "D2")).is_false()
	var expected: Array[int] = Typed.ints(pile)
	MatchRng.new(SEED).shuffle_in_place(expected)
	assert_array(state.seats[0].hand).is_equal(Typed.ints([expected[0]]))
	assert_array(state.seats[0].deck).is_equal(expected.slice(1))
	var expected_kinds: Array[int] = [FIRED, EMPTY, FIRED, SHUFFLED, CREW, DRAWN]
	assert_array(_kinds(rec.events)).is_equal(expected_kinds)
	assert_bool(state.queue.is_empty()).is_true()


# --- Void and Dredger together (C29) --------------------------------------------------


## Void and Dredger both fire on one empty draw, in Crew slot order either way, with no
## re-check of the Deck: the Pile is shuffled in, Void's grant is held and the resumed draw
## succeeds once.
func test_void_and_dredger_both_fire_in_either_slot_order_and_the_draw_succeeds() -> void:
	for crew: Array[String] in [VOID_FIRST, DREDGER_FIRST]:
		var cards: MatchCards = StubAbilities.defs(crew)
		var state: MatchState = _dry(Typed.ints([20, 21, 22]), Typed.ints([]))
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
		assert_array(state.void_grants).is_equal(Typed.ints([1, 0]))


# --- Milestone B: Shade (DC-14 T14) ---------------------------------------------------


## Shade prompts at D11, after the exit pass: seat 0's Condemned card has already gone to
## its Pile, and the offer is three of the five revealed cards left, the slots the engine
## stream picks (a shuffled copy of the slots, the first three kept, in slot order), optional,
## in own_board. The chosen card flips face down in its slot (CARD_UNREVEALED, public),
## keeping its Memory and losing its Board changes. Seat 1, with no revealed card, fizzles.
func test_shade_prompts_after_the_exit_pass_over_three_random_revealed_cards() -> void:
	var cards: MatchCards = StubAbilities.defs(COMBO_CREW)
	var state: MatchState = StubAbilities.table(Typed.ints(range(6)), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(StubAbilities.stub_condemn(state, cards, 5, rec.record)).is_true()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.end_turn(state, cards, rng, rec.record)).is_true()
	assert_array(state.seats[0].pile).is_equal(Typed.ints([5]))
	var kinds: Array[int] = _kinds(rec.events)
	assert_int(kinds.find(OPENED)).is_greater(kinds.find(EXIT_RESOLVED))
	var expected: Array[int] = Typed.ints(range(5))
	MatchRng.new(SEED).shuffle_in_place(expected)
	var offered: Array[int] = expected.slice(0, 3)
	offered.sort()
	assert_str(Choice.crew_of(state.prompt)).is_equal("shade")
	assert_str(Choice.step_of(state.prompt)).is_equal("D11")
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_board")
	assert_bool(Choice.is_optional_prompt(state.prompt)).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(offered)
	var slot: int = offered[0]
	var card: int = state.seats[0].board[slot]
	state.memory_for(card).power = 3
	state.card_state_for(card).power_delta = 2
	var chosen: Array[int] = [slot]
	var zone: int = Choice.Zone.OWN_BOARD
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, chosen, false)).is_false()
	assert_bool(TurnFlow.continue_end_turn(state, cards, rng, rec.record, "D11")).is_false()
	assert_bool(state.seats[0].is_revealed(card)).is_false()
	assert_int(state.seats[0].board.find(card)).is_equal(slot)
	assert_int(_memory_power(state, card)).is_equal(3)
	var held: CardState = state.card_state(card)
	assert_int(held.power_delta if held != null else 0).is_equal(0)
	assert_array(rec.cards_of(UNREVEALED)).is_equal(Typed.ints([card]))
	assert_int(rec.of_kind(UNREVEALED)[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["shade"])
	assert_array(_crews(rec.of_kind(FIZZLED))).is_equal(["shade"])


## Shade offers fewer than three when fewer are revealed (here the two face-up cards, slots
## 1 and 2), and with no revealed card it skips: TRIGGER_FIZZLED `no_target`, no prompt.
func test_shade_offers_fewer_and_skips_with_none() -> void:
	var cards: MatchCards = StubAbilities.defs(COMBO_CREW)
	var state: MatchState = StubAbilities.table(Typed.ints([0, 1, 2]), true)
	assert_bool(state.seats[0].revealed.erase(0)).is_true()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.end_turn(state, cards, rng, rec.record)).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(Typed.ints([1, 2]))
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	var bare: MatchState = StubAbilities.table(Typed.ints([0, 1]), false)
	assert_bool(TurnFlow.end_turn(bare, cards, rng, none.record)).is_false()
	assert_dict(bare.prompt).is_empty()
	assert_array(none.of_kind(OPENED)).is_empty()
	var fizzled: Array[MatchEvent] = none.of_kind(FIZZLED)
	assert_array(_crews(fizzled)).is_equal(["shade", "shade"])
	for event: MatchEvent in fizzled:
		var reason: String = event.payload["reason"]
		assert_str(reason).is_equal(Abilities.REASON_NO_TARGET)
	assert_array(bare.seats[0].board).is_equal(Typed.ints([0, 1]))


# --- Milestone B: Veil ----------------------------------------------------------------


## Veil prompts at D9, before the exit pass, over seat 0's Condemned cards (slots 1 and 2,
## optional, own_board); the chosen one's mark becomes Fleeting (EXIT_MARKED, replaced
## condemned) and the same exit pass sends it to its Owner's hand while the other goes to
## the Pile. Seat 1 has no Condemned card: its Veil fizzles.
func test_veil_turns_the_chosen_condemned_card_fleeting_in_the_same_pass() -> void:
	var cards: MatchCards = StubAbilities.defs(GRAVEYARD_CREW)
	var state: MatchState = StubAbilities.table(Typed.ints([0, 1, 2]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	for card: int in [1, 2]:
		assert_bool(StubAbilities.stub_condemn(state, cards, card, rec.record)).is_true()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.end_turn(state, cards, rng, rec.record)).is_true()
	assert_str(Choice.crew_of(state.prompt)).is_equal("veil")
	assert_str(Choice.step_of(state.prompt)).is_equal("D9")
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_board")
	assert_bool(Choice.is_optional_prompt(state.prompt)).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(Typed.ints([1, 2]))
	assert_array(rec.of_kind(EXIT_RESOLVED)).is_empty()
	var chosen: Array[int] = [2]
	var zone: int = Choice.Zone.OWN_BOARD
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, chosen, false)).is_false()
	assert_str(Statuses.exit_mark_of(state, 2)).is_equal(Statuses.FLEETING)
	var marks: Array[MatchEvent] = rec.of_kind(MARKED)
	var marked: MatchEvent = marks[marks.size() - 1]
	var replaced: String = marked.payload["replaced"]
	assert_str(replaced).is_equal(Statuses.CONDEMNED)
	assert_bool(TurnFlow.continue_end_turn(state, cards, rng, rec.record, "D9")).is_false()
	assert_array(state.seats[0].board).is_equal(Typed.ints([0]))
	assert_array(state.seats[0].pile).is_equal(Typed.ints([1]))
	assert_array(state.seats[0].hand).is_equal(Typed.ints([2]))
	assert_array(_crews(rec.of_kind(FIRED))).is_equal(["veil"])
	assert_array(_crews(rec.of_kind(FIZZLED))).is_equal(["veil"])


## Veil beats Wraith (cards-v2 section 4): with Wraith face up on the row, the Condemned card
## Veil chose returns to its Owner's hand as Fleeting, while the other Condemned card
## resolves as Fade (flips face down in place) under Wraith.
func test_veil_beats_wraith() -> void:
	var cards: MatchCards = StubAbilities.defs(GRAVEYARD_CREW)
	var wraith: CardDef = CardDb.load_default().card_by_id("gy05")
	assert_bool(StubAbilities.give(cards, Typed.ints([0]), wraith)).is_true()
	var state: MatchState = StubAbilities.table(Typed.ints([0, 1, 2]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	for card: int in [1, 2]:
		assert_bool(StubAbilities.stub_condemn(state, cards, card, rec.record)).is_true()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.end_turn(state, cards, rng, rec.record)).is_true()
	var chosen: Array[int] = [1]
	var zone: int = Choice.Zone.OWN_BOARD
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, chosen, false)).is_false()
	assert_bool(TurnFlow.continue_end_turn(state, cards, rng, rec.record, "D9")).is_false()
	assert_array(state.seats[0].hand).is_equal(Typed.ints([1]))
	assert_array(state.seats[0].board).is_equal(Typed.ints([0, 2]))
	assert_bool(state.seats[0].is_revealed(2)).is_false()
	assert_array(state.seats[0].pile).is_empty()
	var marks: Array[String] = []
	for event: MatchEvent in rec.of_kind(EXIT_RESOLVED):
		var mark: String = event.payload["mark"]
		marks.append(mark)
	assert_array(marks).is_equal([Statuses.FLEETING, Statuses.FADE])


# --- Milestone B: Quartermaster -------------------------------------------------------


## Quartermaster sets the Hand size to 7, and Pantry's +2 on a revealed row card adds to
## it: 9. Without Quartermaster, Pantry gives 4 + 2 = 6; Quartermaster alone gives 7.
func test_quartermaster_with_pantry_gives_9() -> void:
	var pantry: CardDef = CardDb.load_default().card_by_id("ev14")
	var with_quartermaster: MatchCards = StubAbilities.defs(COMBO_CREW)
	var without: MatchCards = StubAbilities.defs(StubAbilities.CREW)
	for cards: MatchCards in [with_quartermaster, without]:
		assert_bool(StubAbilities.give(cards, Typed.ints([0]), pantry)).is_true()
	var state: MatchState = StubAbilities.table(Typed.ints([0]), true)
	assert_int(TurnFlow.hand_size(state, with_quartermaster, 0)).is_equal(9)
	assert_int(TurnFlow.hand_size(state, with_quartermaster, 1)).is_equal(7)
	assert_int(TurnFlow.hand_size(state, without, 0)).is_equal(6)
	assert_int(TurnFlow.hand_size(state, without, 1)).is_equal(MatchRules.HAND_SIZE)


# --- Milestone B: Salvager ------------------------------------------------------------


## Salvager prompts its own seat once per Commit of that seat (D3 for the first seat, D5 for
## the second), over its hand (own_hand, optional); the other seat's Salvager does not wake.
## A decline changes nothing: no Discard, no draw, the hand, Deck and Pile as they were, and
## CHOICE_DECLINED names the Crew.
func test_salvager_prompts_once_per_own_commit_and_a_decline_changes_nothing() -> void:
	var cards: MatchCards = StubAbilities.defs(GRAVEYARD_CREW)
	var state: MatchState = _salvage_table()
	var rng: MatchRng = MatchRng.new(SEED)
	for seat: int in range(2):
		var rec: StubAbilities.Recorder = StubAbilities.recorder()
		var before: Array = _zones(state)
		assert_bool(TurnFlow.after_commit(state, cards, rng, rec.record, seat)).is_true()
		assert_int(rec.of_kind(OPENED).size()).is_equal(1)
		assert_array(_crews(rec.of_kind(FIRED))).is_equal(["salvager"])
		var asked: int = state.prompt.get("seat", -1)
		assert_int(asked).is_equal(seat)
		assert_str(Choice.crew_of(state.prompt)).is_equal("salvager")
		assert_str(Choice.step_of(state.prompt)).is_equal("D3" if seat == 0 else "D5")
		assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_hand")
		assert_bool(Choice.is_optional_prompt(state.prompt)).is_true()
		assert_array(Choice.options_of(state.prompt)).is_equal(Typed.ints([0, 1]))
		var none: Array[int] = []
		var zone: int = Choice.Zone.OWN_HAND
		assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, none, true)).is_false()
		var declined: Array[MatchEvent] = rec.of_kind(DECLINED)
		assert_int(declined.size()).is_equal(1)
		var crew: String = declined[0].payload["crew"]
		assert_str(crew).is_equal("salvager")
		assert_array(_zones(state)).is_equal(before)
		assert_array(rec.of_kind(DRAWN)).is_empty()
		assert_array(rec.of_kind(DISCARDED)).is_empty()


## Salvager's Discard comes first and wakes its On discard (the discarded card's own stub
## trigger fires from the Pile), then the seat draws, all inside D3; only after that drain
## does the discard-down open, over the hand as Salvager left it (six cards, Hand size 4:
## exactly 2).
func test_salvager_discard_wakes_on_discard_before_the_discard_down() -> void:
	var cards: MatchCards = StubAbilities.defs(GRAVEYARD_CREW)
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	cards.set_verb_handler(verbs)
	var watches: Array[CardAbility] = [
		StubAbilities.ability("on_discard", StubAbilities.VERB_RECORD)
	]
	var discarded: CardDef = StubAbilities.card_def("Watcher", watches, 1)
	assert_bool(StubAbilities.give(cards, Typed.ints([0]), discarded)).is_true()
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign(Typed.ints(range(6)))
	state.seats[0].deck.assign(Typed.ints([10, 11]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.after_commit(state, cards, rng, rec.record, 0)).is_true()
	var chosen: Array[int] = [0]
	var zone: int = Choice.Zone.OWN_HAND
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, chosen, false)).is_false()
	assert_array(state.seats[0].pile).is_equal(Typed.ints([0]))
	assert_array(state.seats[0].hand).is_equal(Typed.ints([1, 2, 3, 4, 5, 10]))
	assert_array(state.seats[0].deck).is_equal(Typed.ints([11]))
	assert_int(verbs.trace.size()).is_equal(1)
	assert_bool(TurnFlow.open_discard_down(state, cards, rec.record, 0)).is_true()
	assert_bool(TurnFlow.is_discard_down(state.prompt)).is_true()
	assert_int(Choice.exact_of(state.prompt)).is_equal(2)
	var kinds: Array[int] = _kinds(rec.events)
	var woke: int = -1
	for at: int in range(rec.events.size()):
		var event: MatchEvent = rec.events[at]
		var card: int = event.payload.get("card", -1)
		if event.kind == FIRED and card == 0:
			woke = at
	assert_int(kinds.find(DISCARDED)).is_less(kinds.find(DRAWN))
	assert_int(woke).is_greater(kinds.find(DISCARDED))
	assert_int(woke).is_less(kinds.rfind(OPENED))


## Both seats' hand, Deck and Pile, as plain arrays (seat 0's first).
func _zones(state: MatchState) -> Array:
	var out: Array = []
	for piles: MatchState.SeatPiles in state.seats:
		out.append([piles.hand.duplicate(), piles.deck.duplicate(), piles.pile.duplicate()])
	return out


## Both seats with two hand cards and two Deck cards, seat 0 committing first.
func _salvage_table() -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign(Typed.ints([0, 1]))
	state.seats[0].deck.assign(Typed.ints([2, 3]))
	state.seats[1].hand.assign(Typed.ints([OTHER, OTHER + 1]))
	state.seats[1].deck.assign(Typed.ints([OTHER + 2, OTHER + 3]))
	return state


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
