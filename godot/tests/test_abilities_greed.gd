class_name TestAbilitiesGreed
extends GdUnitTestSuite
## The Greed card abilities (DC-13 T06; cycle 9 plan P3 verb table, P12; canon
## [[rules/cards-v2]] section 2.1): Ember's choice from the hand (Q9), Flare's own Condemn
## (Q10), Courier's and Bounty's draws for the right seat, Jackpot's Discards each waking its
## own On discard Batch (Q1). Each case puts the shipped card's definition on a stub deck
## instance (StubAbilities.replace_def); seat 1's instances add DECK_SIZE.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const GUARD: int = 60
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const DISCARDED: int = MatchEvent.Kind.CARD_DISCARDED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const PROMPTED: int = MatchEvent.Kind.PROMPT_OPENED

var _cached_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


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
	var guard: int = 0
	while state.walk.active and guard < GUARD:
		assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_false()
		guard += 1


func _int_of(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _str_of(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


# --- Ember ----------------------------------------------------------------------------


## Ember with two cards in hand prompts its Controller over them (zone own_hand, single
## choice, D7); the chosen card is Discarded to its Owner's Pile from the hand.
func test_ember_prompts_with_two_hand_cards() -> void:
	var cards: MatchCards = _cards()
	var ember: int = 0
	_put(cards, Typed.ints([ember]), "gr01")
	var state: MatchState = StubAbilities.table(Typed.ints([ember]), false)
	state.seats[0].hand.assign(Typed.ints([8, 9]))
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_int(rec.of_kind(PROMPTED).size()).is_equal(1)
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_hand")
	assert_array(Choice.options_of(state.prompt)).is_equal(Typed.ints([0, 1]))
	assert_bool(Choice.is_multi_prompt(state.prompt)).is_false()
	assert_bool(Choice.is_optional_prompt(state.prompt)).is_false()
	assert_str(Choice.step_of(state.prompt)).is_equal("D7")
	var picked: Array[int] = [1]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OWN_HAND, picked, false)
	).is_false()
	assert_array(state.seats[0].hand).is_equal(Typed.ints([8]))
	assert_array(state.seats[0].pile).is_equal(Typed.ints([9]))
	var discarded: Array[MatchEvent] = rec.of_kind(DISCARDED)
	assert_int(discarded.size()).is_equal(1)
	assert_str(_str_of(discarded[0], "from")).is_equal(TurnFlow.FROM_HAND)
	assert_str(_str_of(discarded[0], "reason")).is_equal(TurnFlow.REASON_DISCARD)
	assert_int(_int_of(discarded[0], "owner")).is_equal(0)


## Ember with one card in hand Discards it with no prompt; with none it fizzles
## `no_target` and still Scores.
func test_ember_auto_chooses_with_one_and_fizzles_with_none() -> void:
	var cards: MatchCards = _cards()
	var ember: int = 0
	_put(cards, Typed.ints([ember, ember + 1]), "gr01")
	var state: MatchState = StubAbilities.table(Typed.ints([ember]), false)
	state.seats[0].hand.assign(Typed.ints([8]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(rec.of_kind(PROMPTED)).is_empty()
	assert_array(state.seats[0].hand).is_empty()
	assert_array(state.seats[0].pile).is_equal(Typed.ints([8]))
	assert_array(rec.cards_of(FIRED)).is_equal(Typed.ints([ember]))
	var empty: MatchState = StubAbilities.table(Typed.ints([ember + 1]), false)
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(empty, cards, none)
	var fizzled: Array[MatchEvent] = none.of_kind(FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	assert_str(_str_of(fizzled[0], "verb")).is_equal("discard_own")
	assert_str(_str_of(fizzled[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)
	assert_array(none.cards_of(SCORED)).is_equal(Typed.ints([ember + 1]))


# --- Flare ----------------------------------------------------------------------------


## Flare's On reveal Condemns it; it still Scores this Walk, then the exit pass sends it to
## its Owner's Pile (reason condemned).
func test_flare_condemns_itself_and_still_scores() -> void:
	var cards: MatchCards = _cards()
	var flare: int = StubAbilities.FLARE
	var state: MatchState = StubAbilities.table(Typed.ints([flare]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_str(Statuses.exit_mark_of(state, flare)).is_equal(Statuses.CONDEMNED)
	assert_array(rec.cards_of(SCORED)).is_equal(Typed.ints([flare]))
	assert_int(state.scores[0]).is_equal(5)
	var ended: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.end_turn(state, cards, MatchRng.new(SEED), ended.record)).is_false()
	assert_array(state.seats[0].board).is_empty()
	assert_array(state.seats[0].pile).is_equal(Typed.ints([flare]))
	var discarded: Array[MatchEvent] = ended.of_kind(DISCARDED)
	assert_int(discarded.size()).is_equal(1)
	assert_str(_str_of(discarded[0], "reason")).is_equal(TurnFlow.REASON_CONDEMNED)


# --- Courier and Bounty ---------------------------------------------------------------


## Courier's On score draws for its Controller (seat 1 here), privately.
func test_courier_draws_for_its_own_seat() -> void:
	var cards: MatchCards = _cards()
	var courier: int = OTHER + StubAbilities.COURIER
	var state: MatchState = MatchState.new(SEED)
	StubAbilities.put_row(state, 1, Typed.ints([courier]), true)
	state.seats[0].deck.assign(Typed.ints([8]))
	state.seats[1].deck.assign(Typed.ints([OTHER + 8]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[1].hand).is_equal(Typed.ints([OTHER + 8]))
	assert_array(state.seats[0].hand).is_empty()
	var drawn: Array[MatchEvent] = rec.of_kind(DRAWN)
	assert_int(drawn.size()).is_equal(1)
	assert_int(drawn[0].owner_seat).is_equal(1)
	assert_int(_int_of(drawn[0], "seat")).is_equal(1)


## Bounty's On score makes the opponent draw: seat 0's Bounty gives seat 1 its top card,
## privately to seat 1; seat 0's hand and Deck are untouched.
func test_bounty_draws_for_the_opponent() -> void:
	var cards: MatchCards = _cards()
	var bounty: int = 0
	_put(cards, Typed.ints([bounty]), "gr08")
	var state: MatchState = StubAbilities.table(Typed.ints([bounty]), true)
	state.seats[0].deck.assign(Typed.ints([8]))
	state.seats[1].deck.assign(Typed.ints([OTHER + 8, OTHER + 9]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[1].hand).is_equal(Typed.ints([OTHER + 8]))
	assert_array(state.seats[1].deck).is_equal(Typed.ints([OTHER + 9]))
	assert_array(state.seats[0].hand).is_empty()
	assert_array(state.seats[0].deck).is_equal(Typed.ints([8]))
	var drawn: Array[MatchEvent] = rec.of_kind(DRAWN)
	assert_int(drawn.size()).is_equal(1)
	assert_int(drawn[0].owner_seat).is_equal(1)
	assert_int(_int_of(drawn[0].redacted_for(0), "card")).is_equal(MatchEvent.HIDDEN_CARD)


# --- Jackpot --------------------------------------------------------------------------


## Jackpot Discards every hand card in hand order; each Discard wakes its own On discard
## Batch (a watcher on the row fires once per card, from three different Batches).
func test_jackpot_discards_every_hand_card_each_a_batch() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var watcher: int = 0
	var jackpot: int = 1
	var abilities: Array[CardAbility] = [
		StubAbilities.ability("on_discard", StubAbilities.VERB_RECORD, 0, "any")
	]
	assert_bool(
		StubAbilities.give(cards, Typed.ints([watcher]), StubAbilities.card_def("Watcher", abilities))
	).is_true()
	_put(cards, Typed.ints([jackpot]), "gr10")
	var state: MatchState = StubAbilities.table(Typed.ints([watcher, jackpot]), false)
	state.seats[0].revealed[watcher] = true
	var hand: Array[int] = [8, 9, 2]
	state.seats[0].hand.assign(hand)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].hand).is_empty()
	assert_array(state.seats[0].pile).is_equal(hand)
	assert_array(rec.cards_of(DISCARDED)).is_equal(hand)
	var batches: Dictionary[String, bool] = {}
	for line: String in verbs.trace:
		if line.begins_with("fire %d batch " % watcher):
			batches[line] = true
	assert_int(batches.size()).is_equal(3)
	assert_int(rec.cards_of(FIRED).count(watcher)).is_equal(3)
