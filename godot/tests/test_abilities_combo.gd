# gdlint: disable=max-public-methods
class_name TestAbilitiesCombo
extends GdUnitTestSuite
## The Combo card abilities (DC-14 T12; canon [[rules/cards-v2]] section 2.2, its Flags and
## section 5; [[rules/resolution]] Q1 to Q10 and scenarios 4 and 5): one case per card text
## and one per Flags note. Each case puts the shipped card's definition on a stub deck
## instance (StubAbilities.replace_def); seat 1's instances add DECK_SIZE.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const GUARD: int = 80
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const PROMPTED: int = MatchEvent.Kind.PROMPT_OPENED
const CREATED: int = MatchEvent.Kind.CARD_CREATED
const DISCARDED: int = MatchEvent.Kind.CARD_DISCARDED
const MARKED: int = MatchEvent.Kind.EXIT_MARKED

var _cached_db: CardDb = null
## A sink for the TurnFlow calls whose events a case does not read (TurnFlow calls its
## sink without checking it).
var _spare: StubAbilities.Recorder = StubAbilities.recorder()

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## Stub-deck definitions, the queue stubs `verbs` installed when given.
func _cards(verbs: StubAbilities.StubVerbs = null) -> MatchCards:
	var cards: MatchCards = StubAbilities.defs()
	if verbs != null:
		cards.set_verb_handler(verbs)
	return cards


## Gives `instances` the shipped card `id`.
func _put(cards: MatchCards, instances: Array[int], id: String) -> void:
	var def: CardDef = _db().card_by_id(id)
	assert_object(def).is_not_null()
	assert_bool(StubAbilities.give(cards, instances, def)).is_true()


## A whole Walk on `state` that never pauses.
func _walk(state: MatchState, cards: MatchCards, rec: StubAbilities.Recorder) -> void:
	ScoreWalk.begin(state)
	var rng: MatchRng = MatchRng.new(SEED)
	var guard: int = 0
	while state.walk.active and guard < GUARD:
		assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_false()
		guard += 1


## Finishes a Walk paused in a D7 that has just been answered (TriggerQueue.answer false).
func _finish_walk(
	state: MatchState, cards: MatchCards, rng: MatchRng, rec: StubAbilities.Recorder
) -> void:
	assert_bool(ScoreWalk.resume_pulse(state, cards, rng, rec.record)).is_false()
	assert_bool(ScoreWalk.run(state, cards, rng, rec.record)).is_false()


func _int_of(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _str_of(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


func _power(state: MatchState, cards: MatchCards, card: int) -> int:
	return Scoring.stats(card, state, cards).power


# --- Wick -----------------------------------------------------------------------------


## Wick's On score draws a card, then it gets Power -1 (a Board change); at Power 1 it keeps
## no exit mark.
func test_wick_draws_then_gets_power_minus_one() -> void:
	var cards: MatchCards = _cards()
	var wick: int = 0
	_put(cards, _typed([wick]), "cb01")
	var state: MatchState = StubAbilities.table(_typed([wick]), true)
	state.seats[0].deck.assign(_typed([8, 9]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].hand).is_equal(_typed([8]))
	assert_int(_int_of(rec.of_kind(SCORED)[0], "power")).is_equal(2)
	assert_int(_power(state, cards, wick)).is_equal(1)
	assert_str(Statuses.exit_mark_of(state, wick)).is_empty()


## Wick Flags (LOOP across Turns): at Power 0 it gets Fleeting; at turn end it goes to its
## Owner's hand, its Board changes end, and it can be played again for Cost 1.
func test_wick_at_power_zero_returns_to_hand_for_cost_one() -> void:
	var cards: MatchCards = _cards()
	var wick: int = 0
	_put(cards, _typed([wick]), "cb01")
	var state: MatchState = StubAbilities.table(_typed([wick]), true)
	state.seats[0].deck.assign(_typed([8, 9]))
	state.walk.scores_twice = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].hand).is_equal(_typed([8, 9]))
	assert_int(_power(state, cards, wick)).is_equal(0)
	assert_str(Statuses.exit_mark_of(state, wick)).is_equal(Statuses.FLEETING)
	var ended: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.end_turn(state, cards, MatchRng.new(SEED), ended.record)).is_false()
	assert_array(state.seats[0].board).is_empty()
	assert_array(state.seats[0].hand).is_equal(_typed([8, 9, wick]))
	assert_object(state.card_state(wick)).is_null()
	assert_int(_power(state, cards, wick)).is_equal(2)
	assert_int(Scoring.effective_cost(wick, state, cards)).is_equal(1)


# --- Refrain --------------------------------------------------------------------------


## Refrain (On reveal, another card of yours) gets Power +1 per other reveal of its seat,
## until it leaves the row; not for an opposing reveal.
func test_refrain_grows_for_each_other_reveal_of_its_seat() -> void:
	var cards: MatchCards = _cards()
	var refrain: int = 4
	_put(cards, _typed([refrain]), "cb02")
	var state: MatchState = MatchState.new(SEED)
	StubAbilities.put_row(state, 0, _typed([refrain]), true)
	state.seats[0].board.append_array(_typed([0, 1]))
	StubAbilities.put_row(state, 1, _typed([OTHER]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_int(rec.cards_of(FIRED).count(refrain)).is_equal(2)
	assert_int(state.card_state(refrain).power_delta).is_equal(2)
	assert_int(_power(state, cards, refrain)).is_equal(3)
	assert_bool(Statuses.take_from_row(state, 0, refrain, Callable())).is_true()
	assert_int(_power(state, cards, refrain)).is_equal(1)


## Refrain Flags (RETRIG target): a watcher is an On reveal ability, so Encore doubles it;
## the reveal of Encore itself comes before its retrigger applies.
func test_encore_doubles_refrain() -> void:
	var cards: MatchCards = _cards()
	var refrain: int = 4
	var encore: int = 5
	_put(cards, _typed([refrain]), "cb02")
	_put(cards, _typed([encore]), "cb08")
	var state: MatchState = StubAbilities.table(_typed([refrain]), true)
	state.seats[0].board.append_array(_typed([encore, 0]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_int(rec.cards_of(FIRED).count(refrain)).is_equal(3)
	assert_int(state.card_state(refrain).power_delta).is_equal(3)


# --- Swell ----------------------------------------------------------------------------


## Swell gives another card of yours Fade: one other card is chosen at once, two prompt over
## the row's other slots, none fizzles `no_target`.
func test_swell_fades_another_card_of_yours() -> void:
	var cards: MatchCards = _cards()
	var swell: int = 4
	_put(cards, _typed([swell, swell + 1, swell + 2]), "cb03")
	var one: MatchState = StubAbilities.table(_typed([swell, 8]), false)
	_walk(one, cards, StubAbilities.recorder())
	assert_str(Statuses.exit_mark_of(one, 8)).is_equal(Statuses.FADE)
	assert_str(Statuses.exit_mark_of(one, swell)).is_empty()
	var two: MatchState = StubAbilities.table(_typed([swell + 1, 8, 9]), false)
	ScoreWalk.begin(two)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(ScoreWalk.step(two, cards, MatchRng.new(SEED), rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(two.prompt))).is_equal("own_board")
	assert_array(Choice.options_of(two.prompt)).is_equal(_typed([1, 2]))
	var alone: MatchState = StubAbilities.table(_typed([swell + 2]), false)
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(alone, cards, none)
	assert_str(_str_of(none.of_kind(FIZZLED)[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)


## Swell Flags: Fade replaces an older exit mark, so it saves a Condemned card: Flare
## Condemns itself, Swell's Fade replaces it, and at turn end Flare flips face down in place.
func test_swell_saves_a_condemned_card() -> void:
	var cards: MatchCards = _cards()
	var swell: int = 4
	var flare: int = StubAbilities.FLARE
	_put(cards, _typed([swell]), "cb03")
	var state: MatchState = StubAbilities.table(_typed([flare, swell]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	var marked: Array[MatchEvent] = rec.of_kind(MARKED)
	assert_int(marked.size()).is_equal(2)
	assert_str(_str_of(marked[1], "replaced")).is_equal(Statuses.CONDEMNED)
	assert_bool(TurnFlow.end_turn(state, cards, MatchRng.new(SEED), _spare.record)).is_false()
	assert_array(state.seats[0].board).is_equal(_typed([flare, swell]))
	assert_bool(state.seats[0].is_revealed(flare)).is_false()
	assert_array(state.seats[0].pile).is_empty()


# --- Reprieve -------------------------------------------------------------------------


## Reprieve chooses a card on either row (zone both_boards, the Controller's row first) and
## gives it Fleeting.
func test_reprieve_prompts_over_both_rows() -> void:
	var cards: MatchCards = _cards()
	var reprieve: int = 4
	_put(cards, _typed([reprieve]), "cb04")
	var state: MatchState = StubAbilities.table(_typed([reprieve, 8]), false)
	StubAbilities.put_row(state, 1, _typed([OTHER]), true)
	ScoreWalk.begin(state)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("both_boards")
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 1, 2]))
	var picked: Array[int] = [1]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.BOTH_BOARDS, picked, false)
	).is_false()
	assert_str(Statuses.exit_mark_of(state, 8)).is_equal(Statuses.FLEETING)


## Reprieve Flags: on an opposing card, it Scores this Walk for its seat and goes to its
## Owner's hand at turn end; no Controller change.
func test_reprieve_on_an_opposing_card_scores_then_returns_to_its_owner() -> void:
	var cards: MatchCards = _cards()
	var reprieve: int = 4
	_put(cards, _typed([reprieve]), "cb04")
	var state: MatchState = StubAbilities.table(_typed([reprieve]), false)
	StubAbilities.put_row(state, 1, _typed([OTHER]), false)
	ScoreWalk.begin(state)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	var picked: Array[int] = [1]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.BOTH_BOARDS, picked, false)
	).is_false()
	assert_int(state.controller_of(OTHER)).is_equal(1)
	_finish_walk(state, cards, rng, rec)
	assert_int(state.scores[1]).is_equal(2)
	assert_bool(TurnFlow.end_turn(state, cards, rng, _spare.record)).is_false()
	assert_array(state.seats[1].hand).is_equal(_typed([OTHER]))
	assert_array(state.seats[0].hand).is_empty()


# --- Scrap ----------------------------------------------------------------------------


## Scrap Discards the chosen hand card and gets Add +0.25 per point of its Cost until end of
## turn, at most +1: Cost 3 gives +0.75, Cost 7 gives +1; an empty hand fizzles.
func test_scrap_adds_a_quarter_per_point_of_cost_capped_at_one() -> void:
	var cards: MatchCards = _cards()
	var scrap: int = 4
	_put(cards, _typed([scrap, scrap + 1, scrap + 2]), "cb05")
	_put(cards, _typed([29]), "ev28")
	var state: MatchState = StubAbilities.table(_typed([scrap]), false)
	state.seats[0].hand.assign(_typed([StubAbilities.BRACE]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].pile).is_equal(_typed([StubAbilities.BRACE]))
	assert_int(Scoring.stats(scrap, state, cards).add()).is_equal(75)
	assert_int(_int_of(rec.of_kind(SCORED)[0], "bonus_value")).is_equal(17500)
	TurnFlow.end_statuses(state, Callable())
	assert_int(Scoring.stats(scrap, state, cards).add()).is_equal(0)
	var capped: MatchState = StubAbilities.table(_typed([scrap + 1]), false)
	capped.seats[0].hand.assign(_typed([29]))
	_walk(capped, cards, StubAbilities.recorder())
	assert_int(Scoring.stats(scrap + 1, capped, cards).add()).is_equal(100)
	var empty: MatchState = StubAbilities.table(_typed([scrap + 2]), false)
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(empty, cards, none)
	assert_str(_str_of(none.of_kind(FIZZLED)[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)


## Canon scenario 4 (Scrap Flags, RETRIG target; Encore Flags): Encore in slot 0 sets the
## retrigger; Scrap in slot 2 resolves, then its extra resolution comes straight after,
## before the On discard Batches, each with its own prompt and its own N (Q5, Q6, Q9); the
## granted Adds stack.
func test_scenario_4_encore_and_scrap() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var encore: int = 12
	var scrap: int = 16
	var watcher: int = OTHER
	_put(cards, _typed([encore]), "cb08")
	_put(cards, _typed([scrap]), "cb05")
	var watches: Array[CardAbility] = [
		StubAbilities.ability("on_discard", StubAbilities.VERB_RECORD, 0, "any")
	]
	var watch_def: CardDef = StubAbilities.card_def("Watcher", watches)
	assert_bool(StubAbilities.give(cards, _typed([watcher]), watch_def)).is_true()
	var state: MatchState = StubAbilities.table(_typed([encore, 0, scrap]), false)
	StubAbilities.put_row(state, 1, _typed([watcher]), true)
	var hand: Array[int] = [StubAbilities.BRACE, StubAbilities.BASTION, 1]
	state.seats[0].hand.assign(hand)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	var paused: bool = false
	var guard: int = 0
	while not paused and state.walk.active and guard < GUARD:
		paused = ScoreWalk.step(state, cards, rng, rec.record)
		guard += 1
	assert_bool(paused).is_true()
	assert_int(Choice.options_of(state.prompt).size()).is_equal(3)
	var first: Array[int] = [0]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OWN_HAND, first, false)
	).is_true()
	assert_int(Choice.options_of(state.prompt).size()).is_equal(2)
	var second: Array[int] = [0]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OWN_HAND, second, false)
	).is_false()
	_finish_walk(state, cards, rng, rec)
	assert_array(rec.cards_of(FIRED)).is_equal(_typed([encore, scrap, scrap, watcher, watcher]))
	assert_array(state.seats[0].pile).is_equal(
		_typed([StubAbilities.BRACE, StubAbilities.BASTION])
	)
	var read: Scoring.Stats = Scoring.stats(scrap, state, cards)
	assert_array(read.adds).is_equal(_typed([75, 100]))
	assert_int(read.bonus_value()).is_equal(27500)


# --- Twin -----------------------------------------------------------------------------


## Twin creates a copy of itself in its Controller's hand: the first created id, its
## definition and Owner recorded once (def_of, origin_of; not in MatchState), CARD_CREATED
## public; the copy has base values and no Memory.
func test_twin_creates_a_copy_in_hand() -> void:
	var cards: MatchCards = _cards()
	var twin: int = 4
	_put(cards, _typed([twin]), "cb06")
	var state: MatchState = StubAbilities.table(_typed([twin]), false)
	state.memory_for(twin).power = 2
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	var copy: int = MatchCards.CREATED_BASE
	assert_array(state.seats[0].hand).is_equal(_typed([copy]))
	assert_int(state.next_created_id).is_equal(copy + 1)
	assert_str(cards.def_of(copy).id).is_equal("cb06")
	assert_int(cards.origin_of(copy)).is_equal(0)
	assert_object(state.memory_of(copy)).is_null()
	assert_int(_power(state, cards, copy)).is_equal(1)
	var created: Array[MatchEvent] = rec.of_kind(CREATED)
	assert_int(created.size()).is_equal(1)
	assert_int(created[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_dict(created[0].payload).is_equal(
		{"seat": 0, "card": copy, "def": "cb06", "owner": 0, "to": "hand", "slot": -1}
	)
	# One record of created cards, MatchCards (DC-20 T03, NSC-179): none in MatchState.
	assert_bool(state.to_dict().has("created")).is_false()


## Twin Flags (LOOP across Turns, CREATE): the copy plays like any card; its own reveal makes
## one more copy with a new id. Rules 9 (cycle 14 R10, C9): a copy is a created card of the
## default lifetime, so a Discarded copy expires (CARD_EXPIRED) and enters no Pile.
func test_a_twin_copy_reveals_and_makes_another() -> void:
	var cards: MatchCards = _cards()
	var twin: int = 4
	_put(cards, _typed([twin]), "cb06")
	var state: MatchState = StubAbilities.table(_typed([twin]), false)
	_walk(state, cards, StubAbilities.recorder())
	var copy: int = MatchCards.CREATED_BASE
	state.seats[0].hand.clear()
	state.seats[0].board.append(copy)
	_walk(state, cards, StubAbilities.recorder())
	assert_array(state.seats[0].hand).is_equal(_typed([copy + 1]))
	assert_str(cards.def_of(copy + 1).id).is_equal("cb06")
	state.seats[0].hand.clear()
	var reason: String = TurnFlow.REASON_DISCARD
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	TurnFlow.to_pile(state, cards, rec.record, copy + 1, TurnFlow.FROM_HAND, reason)
	assert_array(state.seats[0].pile).is_empty()
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_EXPIRED)).is_equal(_typed([copy + 1]))
	assert_object(cards.def_of(copy + 1)).is_null()
	# The Deck's own Twin is not a created card: it is filed in its Owner's Pile as always.
	assert_bool(state.seats[0].board.has(twin)).is_true()
	state.seats[0].board.erase(twin)
	TurnFlow.to_pile(state, cards, rec.record, twin, TurnFlow.FROM_ROW, reason)
	assert_array(state.seats[0].pile).is_equal(_typed([twin]))


# --- Reprise --------------------------------------------------------------------------


## Reprise (On commit) makes every card on both rows Score twice this Turn: the opponent's
## row is doubled too (C30).
func test_reprise_makes_both_rows_score_twice() -> void:
	var cards: MatchCards = _cards()
	var reprise: int = 4
	_put(cards, _typed([reprise]), "cb07")
	var state: MatchState = StubAbilities.table(_typed([reprise]), true)
	var none: Array[int] = []
	TurnFlow.accept_commit(state, cards, _spare.record, 0, none, none)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_commit(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	assert_bool(state.walk.scores_twice).is_true()
	state.seats[0].board.append(0)
	StubAbilities.put_row(state, 1, _typed([OTHER]), false)
	var walked: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, walked)
	var passes: Array = []
	for event: MatchEvent in walked.of_kind(SCORED):
		passes.append([_int_of(event, "card"), _int_of(event, "pass")])
	assert_array(passes).is_equal(
		[[reprise, 1], [reprise, 2], [OTHER, 1], [OTHER, 2], [0, 1], [0, 2]]
	)
	assert_int(state.scores[1]).is_equal(4)
	assert_int(state.scores[0]).is_equal(10)
	TurnFlow.settle_turn(state, _spare.record)
	assert_bool(state.walk.scores_twice).is_false()


## Reprise Flags: it fires only for a Reprise revealed on an earlier Turn (never the Turn it
## is committed, face down) and only on its own seat's Commit.
func test_reprise_does_not_fire_face_down_or_on_the_other_commit() -> void:
	var cards: MatchCards = _cards()
	var reprise: int = 4
	_put(cards, _typed([reprise]), "cb07")
	var face_down: MatchState = StubAbilities.table(_typed([reprise]), false)
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.on_commit(face_down, cards, rng, _spare.record, 0)).is_false()
	assert_bool(face_down.walk.scores_twice).is_false()
	var other: MatchState = StubAbilities.table(_typed([reprise]), true)
	assert_bool(TurnFlow.on_commit(other, cards, rng, _spare.record, 1)).is_false()
	assert_bool(other.walk.scores_twice).is_false()


# --- Encore ---------------------------------------------------------------------------


## Encore: until end of turn each other On reveal of its seat resolves twice; never itself,
## and only for cards revealed after it (slot order); the retrigger ends at turn end.
func test_encore_doubles_later_reveals_only_until_end_of_turn() -> void:
	var cards: MatchCards = _cards()
	var encore: int = 4
	var early: int = StubAbilities.SCOUT
	var late: int = StubAbilities.SCOUT + 1
	_put(cards, _typed([encore]), "cb08")
	var state: MatchState = StubAbilities.table(_typed([early, encore, late]), false)
	state.seats[0].deck.assign(_typed([8, 9, 10, 11]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(rec.cards_of(FIRED)).is_equal(_typed([early, encore, late, late]))
	assert_array(state.seats[0].hand).is_equal(_typed([8, 9, 10]))
	assert_int(state.walk.retrigger_on_reveal[0].size()).is_equal(1)
	TurnFlow.settle_turn(state, _spare.record)
	assert_array(state.walk.retrigger_on_reveal[0]).is_empty()


# --- Reverb ---------------------------------------------------------------------------


## Reverb gets Fleeting and costs 2 less for the match (Memory): it returns to the hand at
## turn end costing 4, each replay costs 2 less, and the Cost clamps at 0.
func test_reverb_returns_cheaper_each_time_down_to_zero() -> void:
	var cards: MatchCards = _cards()
	var reverb: int = 4
	_put(cards, _typed([reverb]), "cb09")
	var state: MatchState = StubAbilities.table(_typed([reverb]), false)
	var costs: Array[int] = []
	for _replay: int in range(4):
		_walk(state, cards, StubAbilities.recorder())
		assert_str(Statuses.exit_mark_of(state, reverb)).is_equal(Statuses.FLEETING)
		assert_bool(TurnFlow.end_turn(state, cards, MatchRng.new(SEED), _spare.record)).is_false()
		assert_array(state.seats[0].hand).is_equal(_typed([reverb]))
		costs.append(Scoring.effective_cost(reverb, state, cards))
		state.seats[0].hand.clear()
		state.seats[0].board.append(reverb)
	assert_array(costs).is_equal(_typed([4, 2, 0, 0]))
	assert_int(state.memory_of(reverb).cost_delta).is_equal(-8)


# --- Finale ---------------------------------------------------------------------------


## Finale gets Power +2 until end of turn per other card of its row revealed this Turn, read
## when it resolves (Q5): a card to its left counts, one to its right does not yet, and one
## revealed on an earlier Turn does not count.
func test_finale_counts_its_seats_reveals_this_turn_so_far() -> void:
	var cards: MatchCards = _cards()
	var finale: int = 4
	_put(cards, _typed([finale]), "cb10")
	var state: MatchState = StubAbilities.table(_typed([8]), true)
	state.seats[0].board.append_array(_typed([0, finale, 1]))
	StubAbilities.put_row(state, 1, _typed([OTHER]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	var finale_score: int = -1
	for event: MatchEvent in rec.of_kind(SCORED):
		if _int_of(event, "card") == finale:
			finale_score = _int_of(event, "power")
	assert_int(finale_score).is_equal(6)
	TurnFlow.end_statuses(state, Callable())
	assert_int(_power(state, cards, finale)).is_equal(4)


# --- Scenario 5: the budget with real cards -------------------------------------------


## Canon scenario 5 with real cards (Q4; Encore and Refrain Flags): four Encores' retriggers
## make each of eleven Refrains resolve five times for one reveal; the 50th resolution is
## the last, the eleventh Refrain fizzles `exhausted` in a public event, and the Walk goes on
## to Score the revealed card.
func test_scenario_5_the_budget_with_refrains_and_encores() -> void:
	var cards: MatchCards = _cards()
	var refrains: Array[int] = _typed(range(11))
	var encores: Array[int] = _typed([11, 12, 13, 14])
	var mote: int = 20
	_put(cards, refrains, "cb02")
	_put(cards, encores, "cb08")
	_put(cards, _typed([mote]), "ev01")
	var row: Array[int] = []
	row.append_array(refrains)
	row.append_array(encores)
	var state: MatchState = StubAbilities.table(row, true)
	state.seats[0].board.append(mote)
	for encore: int in encores:
		TriggerQueue.add_retrigger(state, 0, encore)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_int(rec.of_kind(FIRED).size()).is_equal(MatchRules.TRIGGER_BUDGET)
	var fizzled: Array[MatchEvent] = rec.of_kind(FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	assert_str(_str_of(fizzled[0], "reason")).is_equal(Abilities.REASON_EXHAUSTED)
	assert_int(_int_of(fizzled[0], "card")).is_equal(refrains[10])
	assert_int(fizzled[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	var grown: int = 0
	for refrain: int in refrains:
		var held: CardState = state.card_state(refrain)
		grown += held.power_delta if held != null else 0
	assert_int(grown).is_equal(MatchRules.TRIGGER_BUDGET)
	assert_int(rec.cards_of(SCORED).back()).is_equal(mote)
