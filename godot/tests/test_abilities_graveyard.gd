# gdlint: disable=max-public-methods
class_name TestAbilitiesGraveyard
extends GdUnitTestSuite
## The Graveyard card abilities (DC-14 T13; cycle 9 plan P3, P12; canon [[rules/cards-v2]]
## section 2.4, AbilitiesGraveyardControl): one case per card text and per Flags note.
## Fuse grows on opposing Scores and Condemns two at Power 5; Tithe turns the exit pass's
## Condemned cards into next-Turn Energy, at most three, none on Turn 7 or for a hand
## Discard; Reliquary grows ×1.2 once per Turn from hand Discards to ×2; Boneyard counts both
## Piles by four; Wraith, read once, turns its row's Condemned into Fade even when itself
## Condemned (a Fleeting card, Veil's outcome, is left alone); Glutton Condemns another card
## and gains its Power; Revive places a Pile card ahead of the cursor (reached this Walk,
## CARD_PLACED) and chains; Exhume always prompts, one pick at a time, and may stop; Immolator
## Condemns as many random opposing cards as it chose; Reset refills both Decks before it
## reaches its own Pile. Each case puts the shipped card's definition on a stub deck
## instance (StubAbilities, MatchCards.replace_def); seat 1's instances add DECK_SIZE.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const GUARD: int = 60
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const PROMPTED: int = MatchEvent.Kind.PROMPT_OPENED
const MOVED: int = MatchEvent.Kind.CARD_MOVED
const PLACED: int = MatchEvent.Kind.CARD_PLACED
const GRANTED: int = MatchEvent.Kind.ENERGY_GRANTED
const RESOLVED: int = MatchEvent.Kind.EXIT_RESOLVED
const SHUFFLED: int = MatchEvent.Kind.PILE_SHUFFLED_IN

var _cached_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _words(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


func _cards() -> MatchCards:
	return StubAbilities.defs()


## Gives `instances` the shipped card `id`.
func _put(cards: MatchCards, instances: Array[int], id: String) -> void:
	var def: CardDef = _db().card_by_id(id)
	assert_object(def).is_not_null()
	assert_bool(StubAbilities.give(cards, instances, def)).is_true()


## A whole Walk on `state` that never pauses.
func _walk(state: MatchState, cards: MatchCards, rec: StubAbilities.Recorder) -> void:
	ScoreWalk.begin(state)
	_walk_on(state, cards, rec)


## The rest of a Walk already begun, never pausing.
func _walk_on(state: MatchState, cards: MatchCards, rec: StubAbilities.Recorder) -> void:
	var guard: int = 0
	while state.walk.active and guard < GUARD:
		assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_false()
		guard += 1


## Answers the open prompt with `indices` of `zone` and finishes the Walk (the pulse's score
## stage after a D7 prompt, then the rest).
func _answer_and_finish(
	state: MatchState,
	cards: MatchCards,
	rec: StubAbilities.Recorder,
	zone: int,
	indices: Array[int]
) -> void:
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, indices, false)).is_false()
	assert_bool(ScoreWalk.resume_pulse(state, cards, rng, rec.record)).is_false()
	_walk_on(state, cards, rec)


## Moves `card` from `seat`'s hand to its Pile and drains its On discard at `step`.
func _discard(
	state: MatchState, cards: MatchCards, rec: StubAbilities.Recorder, card: int, step: String
) -> void:
	state.seats[0].hand.erase(card)
	state.seats[0].pile.append(card)
	var discarded: Array[int] = [card]
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.on_discard(state, cards, rng, rec.record, discarded, step, 0)).is_false()


func _int_of(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _str_of(event: MatchEvent, key: String) -> String:
	var value: String = event.payload.get(key, "")
	return value


## The reasons of `rec`'s TRIGGER_FIZZLED events of `verb`, in order.
func _fizzles(rec: StubAbilities.Recorder, verb: String) -> Array[String]:
	var out: Array[String] = []
	for event: MatchEvent in rec.of_kind(FIZZLED):
		if _str_of(event, "verb") == verb:
			out.append(_str_of(event, "reason"))
	return out


## The cards of `row` holding the exit mark Condemned.
func _condemned(state: MatchState, row: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for card: int in row:
		if Statuses.exit_mark_of(state, card) == Statuses.CONDEMNED:
			out.append(card)
	return out


func _power(state: MatchState, cards: MatchCards, card: int) -> int:
	return Scoring.stats(card, state, cards).power


# --- Fuse -----------------------------------------------------------------------------


## Fuse (On score of an opposing card): Power +1 each time until it leaves the row, never
## for its own seat's Scores; at Power 5 it Condemns itself and exactly one random opposing
## card (marks only: every slot stays).
func test_fuse_grows_on_opposing_scores_then_condemns_itself_and_one_opposing() -> void:
	var cards: MatchCards = _cards()
	var fuse: int = 0
	_put(cards, _typed([fuse]), "gy01")
	var state: MatchState = StubAbilities.table(_typed([fuse, StubAbilities.MOTE + 1]), true)
	var enemy: Array[int] = [OTHER, OTHER + 1, OTHER + 2, OTHER + 3]
	StubAbilities.put_row(state, 1, enemy, true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_int(rec.cards_of(FIRED).count(fuse)).is_equal(4)
	assert_int(state.card_state(fuse).power_delta).is_equal(4)
	assert_int(_power(state, cards, fuse)).is_equal(5)
	assert_str(Statuses.exit_mark_of(state, fuse)).is_equal(Statuses.CONDEMNED)
	assert_int(_condemned(state, enemy).size()).is_equal(1)
	assert_array(state.seats[1].board).is_equal(enemy)
	assert_bool(Statuses.take_from_row(state, 0, fuse, rec.record)).is_true()
	assert_int(_power(state, cards, fuse)).is_equal(1)


## Three opposing Scores leave Fuse at Power 4: nothing is Condemned.
func test_fuse_below_five_condemns_nothing() -> void:
	var cards: MatchCards = _cards()
	var fuse: int = 0
	_put(cards, _typed([fuse]), "gy01")
	var state: MatchState = StubAbilities.table(_typed([fuse]), true)
	var enemy: Array[int] = [OTHER, OTHER + 1, OTHER + 2]
	StubAbilities.put_row(state, 1, enemy, true)
	_walk(state, cards, StubAbilities.recorder())
	assert_int(_power(state, cards, fuse)).is_equal(4)
	assert_str(Statuses.exit_mark_of(state, fuse)).is_empty()
	assert_array(_condemned(state, enemy)).is_empty()


# --- Tithe ----------------------------------------------------------------------------


## Tithe on Turn 3: four of its seat's cards Condemned reach the Pile in the exit pass (D10);
## the first three each give +1 Energy next Turn and the fourth fizzles `spent` (at most +3
## per turn end); an opposing Condemned card gives nothing. Turn end moves it into `grants`.
func test_tithe_grants_next_turn_energy_capped_at_three() -> void:
	var cards: MatchCards = _cards()
	var tithe: int = 0
	_put(cards, _typed([tithe]), "gy02")
	var own: Array[int] = [1, 2, 3, StubAbilities.PEBBLE]
	var row: Array[int] = [tithe]
	row.append_array(own)
	var state: MatchState = StubAbilities.table(row, true)
	StubAbilities.put_row(state, 1, _typed([OTHER]), true)
	state.turn = 3
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	for card: int in own + _typed([OTHER]):
		assert_bool(StubAbilities.stub_condemn(state, cards, card, rec.record)).is_true()
	assert_bool(TurnFlow.end_turn(state, cards, MatchRng.new(SEED), rec.record)).is_false()
	assert_array(state.seats[0].pile).is_equal(own)
	assert_array(state.energy.grants).is_equal(_typed([3, 0]))
	assert_array(state.energy.next_turn_grants).is_equal(_typed([0, 0]))
	var granted: Array[MatchEvent] = rec.of_kind(GRANTED)
	assert_int(granted.size()).is_equal(3)
	for event: MatchEvent in granted:
		assert_int(_int_of(event, "seat")).is_equal(0)
		assert_bool(event.payload.get("next_turn", false)).is_true()
	assert_array(_fizzles(rec, "tithe_energy")).is_equal(_words(["spent"]))


## On Turn 7 there is no next Turn in the Round: Tithe fizzles and the Energy is lost.
func test_tithe_on_turn_seven_grants_nothing() -> void:
	var cards: MatchCards = _cards()
	var tithe: int = 0
	_put(cards, _typed([tithe]), "gy02")
	var state: MatchState = StubAbilities.table(_typed([tithe, 1]), true)
	state.turn = MatchRules.TURNS
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(StubAbilities.stub_condemn(state, cards, 1, rec.record)).is_true()
	assert_bool(TurnFlow.end_turn(state, cards, MatchRng.new(SEED), rec.record)).is_false()
	assert_array(state.energy.grants).is_equal(_typed([0, 0]))
	assert_array(_fizzles(rec, "tithe_energy")).is_equal(_words(["no_target"]))


## A Discard from the hand (the discard-down, D4) is not a Condemned card Discarded at turn
## end: Tithe fizzles `no_target`.
func test_tithe_ignores_a_hand_discard() -> void:
	var cards: MatchCards = _cards()
	var tithe: int = 0
	_put(cards, _typed([tithe]), "gy02")
	var state: MatchState = StubAbilities.table(_typed([tithe]), true)
	state.turn = 2
	state.seats[0].hand.assign(_typed([1]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_discard(state, cards, rec, 1, TurnFlow.STEP_FIRST_DISCARD)
	assert_array(state.energy.next_turn_grants).is_equal(_typed([0, 0]))
	assert_array(_fizzles(rec, "tithe_energy")).is_equal(_words(["no_target"]))


# --- Reliquary ------------------------------------------------------------------------


## Reliquary ×1.25: a hand Discard multiplies its Mult by ×1.2 for the match (×1.5), a second
## the same Turn fizzles `spent`; the next Turns give ×1.8, then ×2 (capped from ×2.16), then
## nothing at the cap; a card leaving a row (the exit pass's context) never counts.
func test_reliquary_grows_once_per_turn_from_hand_discards_to_two() -> void:
	var cards: MatchCards = _cards()
	var relic: int = 0
	_put(cards, _typed([relic]), "gy03")
	var state: MatchState = StubAbilities.table(_typed([relic]), true)
	state.seats[0].hand.assign(_typed([1, 2, 3, 8, 9, 10]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_int(Scoring.stats(relic, state, cards).mult()).is_equal(125)
	_discard(state, cards, rec, 1, TurnFlow.STEP_FIRST_DISCARD)
	assert_int(Scoring.stats(relic, state, cards).mult()).is_equal(150)
	_discard(state, cards, rec, 2, TurnFlow.STEP_FIRST_DISCARD)
	assert_int(Scoring.stats(relic, state, cards).mult()).is_equal(150)
	assert_array(_fizzles(rec, "reliquary_mult")).is_equal(_words(["spent"]))
	Abilities.end_turn_changes(state)
	_discard(state, cards, rec, 3, TurnFlow.STEP_FIRST_DISCARD)
	assert_int(Scoring.stats(relic, state, cards).mult()).is_equal(180)
	Abilities.end_turn_changes(state)
	_discard(state, cards, rec, 8, TurnFlow.STEP_EXIT_PASS)
	assert_int(Scoring.stats(relic, state, cards).mult()).is_equal(180)
	_discard(state, cards, rec, 9, TurnFlow.STEP_SECOND_DISCARD)
	assert_int(Scoring.stats(relic, state, cards).mult()).is_equal(200)
	assert_bool(state.memory_of(relic) != null).is_true()
	Abilities.end_turn_changes(state)
	_discard(state, cards, rec, 10, TurnFlow.STEP_FIRST_DISCARD)
	assert_int(Scoring.stats(relic, state, cards).mult()).is_equal(200)
	var reasons: Array[String] = ["spent", "no_target", "no_target"]
	assert_array(_fizzles(rec, "reliquary_mult")).is_equal(reasons)


# --- Boneyard -------------------------------------------------------------------------


## Boneyard reads both Piles at the moment (Q5): Power 2 plus one per four cards, rounded
## down; not while Squelched (its Ongoing is not read).
func test_boneyard_counts_both_piles_by_four() -> void:
	var cards: MatchCards = _cards()
	var bone: int = 0
	_put(cards, _typed([bone]), "gy04")
	var state: MatchState = StubAbilities.table(_typed([bone]), true)
	assert_int(_power(state, cards, bone)).is_equal(2)
	state.seats[0].pile.assign(_typed([1, 2, 3]))
	state.seats[1].pile.assign(_typed([OTHER, OTHER + 1, OTHER + 2, OTHER + 3]))
	assert_int(_power(state, cards, bone)).is_equal(3)
	state.seats[0].pile.append(8)
	assert_int(_power(state, cards, bone)).is_equal(4)
	assert_bool(StubAbilities.stub_squelch(state, cards, bone, Callable()).ok()).is_true()
	assert_int(_power(state, cards, bone)).is_equal(2)


# --- Wraith ---------------------------------------------------------------------------


## Wraith, Condemned itself, is read once at the start of the pass: it and its row's other
## Condemned card resolve as Fade (face down in place, EXIT_RESOLVED `instead_of`
## condemned, no Discard), an unmarked card is untouched, and the opposing Condemned card
## still goes to its Pile.
func test_wraith_condemned_still_turns_its_rows_condemned_into_fade() -> void:
	var cards: MatchCards = _cards()
	var wraith: int = 0
	_put(cards, _typed([wraith]), "gy05")
	var state: MatchState = StubAbilities.table(_typed([wraith, 1, 2]), true)
	StubAbilities.put_row(state, 1, _typed([OTHER]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	for card: int in [wraith, 1, OTHER]:
		assert_bool(StubAbilities.stub_condemn(state, cards, card, rec.record)).is_true()
	var discarded: Array[int] = TurnFlow.exit_pass(state, cards, rec.record)
	assert_array(discarded).is_equal(_typed([OTHER]))
	assert_array(state.seats[0].board).is_equal(_typed([wraith, 1, 2]))
	assert_bool(state.seats[0].is_revealed(wraith)).is_false()
	assert_bool(state.seats[0].is_revealed(1)).is_false()
	assert_bool(state.seats[0].is_revealed(2)).is_true()
	assert_array(state.seats[0].pile).is_empty()
	assert_array(state.seats[1].pile).is_equal(_typed([OTHER]))
	var faded: int = 0
	for event: MatchEvent in rec.of_kind(RESOLVED):
		if _str_of(event, "to") == Statuses.TO_FACE_DOWN:
			assert_str(_str_of(event, "instead_of")).is_equal(Statuses.CONDEMNED)
			faded += 1
	assert_int(faded).is_equal(2)


## A Squelched Wraith is not read: its row's Condemned card goes to the Pile.
func test_squelched_wraith_changes_nothing() -> void:
	var cards: MatchCards = _cards()
	var wraith: int = 0
	_put(cards, _typed([wraith]), "gy05")
	var state: MatchState = StubAbilities.table(_typed([wraith, 1]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var sink: Callable = rec.record
	assert_bool(StubAbilities.stub_squelch(state, cards, wraith, sink).ok()).is_true()
	assert_bool(StubAbilities.stub_condemn(state, cards, 1, sink)).is_true()
	assert_array(TurnFlow.exit_pass(state, cards, sink)).is_equal(_typed([1]))
	assert_array(state.seats[0].pile).is_equal(_typed([1]))


## Wraith changes Condemned only: a card made Fleeting after its Condemn (what Veil does at
## At turn end before the pass, DC-14 T14) returns to its Owner's hand, so Veil beats Wraith
## (cards-v2 section 4). PENDING T14: repeat this with the real Veil Crew once it lands.
func test_wraith_leaves_a_fleeting_card_alone() -> void:
	var cards: MatchCards = _cards()
	var wraith: int = 0
	_put(cards, _typed([wraith]), "gy05")
	var state: MatchState = StubAbilities.table(_typed([wraith, 1]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var sink: Callable = rec.record
	assert_bool(StubAbilities.stub_condemn(state, cards, 1, sink)).is_true()
	assert_bool(StubAbilities.stub_fleeting(state, cards, 1, sink)).is_true()
	assert_array(TurnFlow.exit_pass(state, cards, sink)).is_empty()
	assert_array(state.seats[0].board).is_equal(_typed([wraith]))
	assert_array(state.seats[0].hand).is_equal(_typed([1]))


# --- Glutton --------------------------------------------------------------------------


## Glutton with two other cards prompts its Controller over them (own_board, single); the
## chosen Pebble is Condemned, Glutton gains its Power 3 until it leaves the row, and the
## Condemned Pebble still Scores this Walk (Q10).
func test_glutton_prompts_condemns_and_gains_the_power() -> void:
	var cards: MatchCards = _cards()
	var glutton: int = 0
	var pebble: int = StubAbilities.PEBBLE
	_put(cards, _typed([glutton]), "gy06")
	var state: MatchState = StubAbilities.table(_typed([glutton, pebble, 1]), false)
	state.seats[0].revealed[pebble] = true
	state.seats[0].revealed[1] = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_board")
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([1, 2]))
	_answer_and_finish(state, cards, rec, Choice.Zone.OWN_BOARD, _typed([1]))
	assert_str(Statuses.exit_mark_of(state, pebble)).is_equal(Statuses.CONDEMNED)
	assert_str(Statuses.exit_mark_of(state, 1)).is_empty()
	assert_int(_power(state, cards, glutton)).is_equal(5)
	assert_array(rec.cards_of(SCORED)).is_equal(_typed([glutton, pebble, 1]))


## One eligible card is chosen with no prompt; a card that cannot be Condemned (Bastion) is
## not eligible, so Glutton alone with it fizzles `no_target` and gains nothing.
func test_glutton_auto_chooses_one_and_skips_bastion() -> void:
	var cards: MatchCards = _cards()
	var glutton: int = 0
	_put(cards, _typed([glutton, glutton + 1]), "gy06")
	var state: MatchState = StubAbilities.table(_typed([glutton, StubAbilities.PEBBLE]), false)
	state.seats[0].revealed[StubAbilities.PEBBLE] = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(rec.of_kind(PROMPTED)).is_empty()
	assert_int(_power(state, cards, glutton)).is_equal(5)
	var bastion: int = StubAbilities.BASTION
	var guarded: MatchState = StubAbilities.table(_typed([glutton + 1, bastion]), false)
	guarded.seats[0].revealed[bastion] = true
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(guarded, cards, none)
	assert_array(_fizzles(none, "condemn_other_gain")).is_equal(_words(["no_target"]))
	assert_int(_power(guarded, cards, glutton + 1)).is_equal(2)
	assert_str(Statuses.exit_mark_of(guarded, bastion)).is_empty()


# --- Revive ---------------------------------------------------------------------------


## Revive with one Pile card: it is placed face down right of Revive (Placement: no
## CARD_MOVED), CARD_PLACED {seat, card, from: pile, slot} is public, Revive is Condemned,
## and the placed card is ahead of the cursor, so it is revealed and Scores this Walk.
func test_revive_places_a_pile_card_that_is_reached_this_walk() -> void:
	var cards: MatchCards = _cards()
	var revive: int = 0
	var pebble: int = StubAbilities.PEBBLE
	_put(cards, _typed([revive]), "gy07")
	var state: MatchState = StubAbilities.table(_typed([revive, 1]), false)
	state.seats[0].pile.assign(_typed([pebble]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].board).is_equal(_typed([revive, pebble, 1]))
	assert_array(state.seats[0].pile).is_empty()
	assert_array(rec.of_kind(MOVED)).is_empty()
	var placed: Array[MatchEvent] = rec.of_kind(PLACED)
	assert_int(placed.size()).is_equal(1)
	assert_bool(placed[0].is_private()).is_false()
	assert_int(_int_of(placed[0], "seat")).is_equal(0)
	assert_int(_int_of(placed[0], "card")).is_equal(pebble)
	assert_str(_str_of(placed[0], "from")).is_equal("pile")
	assert_int(_int_of(placed[0], "slot")).is_equal(1)
	assert_str(Statuses.exit_mark_of(state, revive)).is_equal(Statuses.CONDEMNED)
	assert_array(rec.cards_of(SCORED)).is_equal(_typed([revive, pebble, 1]))


## LOOP: a Revive revived by Revive chains one card per resolution. Two Pile cards prompt
## (own_pile); choosing the second Revive places it, it is reached, reveals and places the
## last Pile card on its own right; both Revives are Condemned. An empty Pile fizzles.
func test_revive_chains_through_a_revived_revive() -> void:
	var cards: MatchCards = _cards()
	var revive: int = 0
	var again: int = 3
	var pebble: int = StubAbilities.PEBBLE
	_put(cards, _typed([revive, again, 2]), "gy07")
	var state: MatchState = StubAbilities.table(_typed([revive, 1]), false)
	state.seats[0].pile.assign(_typed([again, pebble]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_pile")
	_answer_and_finish(state, cards, rec, Choice.Zone.OWN_PILE, _typed([0]))
	assert_array(state.seats[0].board).is_equal(_typed([revive, again, pebble, 1]))
	assert_array(state.seats[0].pile).is_empty()
	assert_array(_condemned(state, state.seats[0].board)).is_equal(_typed([revive, again]))
	var empty: MatchState = StubAbilities.table(_typed([2]), false)
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(empty, cards, none)
	assert_array(_fizzles(none, "revive")).is_equal(_words(["no_target"]))
	assert_str(Statuses.exit_mark_of(empty, 2)).is_empty()


# --- Exhume ---------------------------------------------------------------------------


## Exhume always prompts (an optional count, Q9): over both Piles (both_piles, optional);
## the opposing Pile's card is shuffled into its Owner's Deck at once (PILE_SHUFFLED_IN seat
## 1, count 1); the second pick prompts though one card is left, and its decline keeps the
## first pick and leaves the own Pile as it was.
func test_exhume_prompts_each_pick_and_may_stop() -> void:
	var cards: MatchCards = _cards()
	var exhume: int = 0
	_put(cards, _typed([exhume]), "gy08")
	var state: MatchState = StubAbilities.table(_typed([exhume]), false)
	state.seats[0].pile.assign(_typed([8]))
	state.seats[1].pile.assign(_typed([OTHER + 8]))
	state.seats[1].deck.assign(_typed([OTHER + 9]))
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("both_piles")
	assert_bool(Choice.is_optional_prompt(state.prompt)).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 1]))
	var zone: int = Choice.Zone.BOTH_PILES
	var none: Array[int] = []
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, _typed([1]), false)).is_true()
	assert_array(state.seats[1].pile).is_empty()
	assert_int(state.seats[1].deck.size()).is_equal(2)
	assert_bool(state.seats[1].deck.has(OTHER + 8)).is_true()
	assert_bool(Choice.is_optional_prompt(state.prompt)).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0]))
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, none, true)).is_false()
	assert_array(state.seats[0].pile).is_equal(_typed([8]))
	var shuffled: Array[MatchEvent] = rec.of_kind(SHUFFLED)
	assert_int(shuffled.size()).is_equal(1)
	assert_int(_int_of(shuffled[0], "seat")).is_equal(1)
	assert_int(_int_of(shuffled[0], "count")).is_equal(1)


## Exhume may choose none: declining the first pick changes no Pile or Deck.
func test_exhume_declined_changes_nothing() -> void:
	var cards: MatchCards = _cards()
	var exhume: int = 0
	_put(cards, _typed([exhume]), "gy08")
	var state: MatchState = StubAbilities.table(_typed([exhume]), false)
	state.seats[0].pile.assign(_typed([8]))
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	var none: Array[int] = []
	var zone: int = Choice.Zone.BOTH_PILES
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, none, true)).is_false()
	assert_array(state.seats[0].pile).is_equal(_typed([8]))
	assert_array(state.seats[0].deck).is_empty()


# --- Immolator ------------------------------------------------------------------------


## Immolator opens an optional-count multi-select over its other cards (min 0, any size);
## choosing one Condemns it and exactly one random opposing card; marks only, so no slot
## changes.
func test_immolator_condemns_its_choice_and_as_many_opposing() -> void:
	var cards: MatchCards = _cards()
	var imm: int = 0
	_put(cards, _typed([imm]), "gy09")
	var state: MatchState = StubAbilities.table(_typed([imm, 1, 2]), false)
	state.seats[0].revealed[1] = true
	state.seats[0].revealed[2] = true
	var enemy: Array[int] = [OTHER, OTHER + 1, OTHER + 2]
	StubAbilities.put_row(state, 1, enemy, true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_true()
	assert_bool(Choice.is_multi_prompt(state.prompt)).is_true()
	assert_int(Choice.min_of(state.prompt)).is_equal(0)
	assert_int(Choice.exact_of(state.prompt)).is_equal(Choice.ANY_SIZE)
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([1, 2]))
	_answer_and_finish(state, cards, rec, Choice.Zone.OWN_BOARD, _typed([1]))
	assert_array(_condemned(state, state.seats[0].board)).is_equal(_typed([1]))
	assert_int(_condemned(state, enemy).size()).is_equal(1)
	assert_array(state.seats[0].board).is_equal(_typed([imm, 1, 2]))
	assert_array(state.seats[1].board).is_equal(enemy)


## With one eligible card Immolator still prompts (Q9), and an empty answer Condemns nothing.
func test_immolator_prompts_with_one_and_may_choose_none() -> void:
	var cards: MatchCards = _cards()
	var imm: int = 0
	_put(cards, _typed([imm]), "gy09")
	var state: MatchState = StubAbilities.table(_typed([imm, 1]), false)
	state.seats[0].revealed[1] = true
	var enemy: Array[int] = [OTHER]
	StubAbilities.put_row(state, 1, enemy, true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([1]))
	var none: Array[int] = []
	_answer_and_finish(state, cards, rec, Choice.Zone.OWN_BOARD, none)
	assert_array(_condemned(state, state.seats[0].board)).is_empty()
	assert_array(_condemned(state, enemy)).is_empty()


# --- Reset ----------------------------------------------------------------------------


## Reset shuffles both Piles into their Decks (one public PILE_SHUFFLED_IN each), then is
## Condemned; at turn end it reaches its Pile after the shuffle, so it is not shuffled in.
func test_reset_refills_both_decks_then_reaches_its_pile() -> void:
	var cards: MatchCards = _cards()
	var reset: int = 0
	_put(cards, _typed([reset]), "gy10")
	var state: MatchState = StubAbilities.table(_typed([reset]), false)
	state.seats[0].pile.assign(_typed([8, 9]))
	state.seats[0].deck.assign(_typed([10]))
	state.seats[1].pile.assign(_typed([OTHER + 8]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].pile).is_empty()
	assert_array(state.seats[1].pile).is_empty()
	var deck: Array[int] = []
	deck.assign(state.seats[0].deck)
	deck.sort()
	assert_array(deck).is_equal(_typed([8, 9, 10]))
	assert_array(state.seats[1].deck).is_equal(_typed([OTHER + 8]))
	var shuffled: Array[MatchEvent] = rec.of_kind(SHUFFLED)
	assert_int(shuffled.size()).is_equal(2)
	for event: MatchEvent in shuffled:
		assert_bool(event.is_private()).is_false()
	assert_str(Statuses.exit_mark_of(state, reset)).is_equal(Statuses.CONDEMNED)
	assert_bool(TurnFlow.end_turn(state, cards, MatchRng.new(SEED), rec.record)).is_false()
	assert_array(state.seats[0].pile).is_equal(_typed([reset]))
	assert_bool(state.seats[0].deck.has(reset)).is_false()
