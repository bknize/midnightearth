class_name TestDrossExpiry
extends GdUnitTestSuite
## Dross expiry through the running engine (rules 9, cycle 14 R10, R11, C13; T08 N5), where
## test_turn_flow.gd drives TurnFlow directly: a Round end whose D12 drain pauses on a prompt
## expires its Dross only when the answer has finished the drain, and the sudden-death
## stalemate reads the seats after expiry. Each case starts a stubs match, rearranges the
## table for the last Turn of a Round, and plays that Turn by passing. Fixture cards only.

const SEED: int = 1
const EXPIRED: int = MatchEvent.Kind.DROSS_EXPIRED
const ROUND_ENDED: int = MatchEvent.Kind.ROUND_ENDED
const ROUND_STARTED: int = MatchEvent.Kind.ROUND_STARTED
const MATCH_ENDED: int = MatchEvent.Kind.MATCH_ENDED
const CHOICE_MADE: int = MatchEvent.Kind.CHOICE_MADE

# --- Helpers --------------------------------------------------------------------------


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _started() -> MatchEngine:
	var engine: MatchEngine = StubAbilities.engine(SEED)
	assert_bool(engine.start().ok).is_true()
	return engine


## A Dross definition of lifetime `match`, never removed.
func _keeper() -> CardDef:
	var keeper: CardDef = CardDef.new("keeper", "Keeper", "evergreen", 1, 2)
	keeper.dross = true
	keeper.lifetime = CardDef.LIFETIME_MATCH
	return keeper


## Both seats pass the Turn `engine` awaits. Returns the events of both Commits, copied.
func _pass_turn(engine: MatchEngine) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	var none: Array[int] = []
	for _commit: int in range(MatchEngine.SEATS):
		var result: ApplyResult = engine.apply(EngineAction.commit(engine.awaited_seat(), none))
		assert_bool(result.ok).is_true()
		out.append_array(result.events)
	return out


func _of_kind(events: Array[MatchEvent], wanted: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == wanted:
			out.append(event)
	return out


func _first_at(events: Array[MatchEvent], wanted: int) -> int:
	for at: int in range(events.size()):
		if events[at].kind == wanted:
			return at
	return -1


func _expired_cards(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, EXPIRED):
		var card: int = event.payload["card"]
		out.append(card)
	return out


func _expired_from(events: Array[MatchEvent]) -> Array[String]:
	var out: Array[String] = []
	for event: MatchEvent in _of_kind(events, EXPIRED):
		var from: String = event.payload["from"]
		out.append(from)
	return out


## A started match set at the last Turn of a sudden-death Round in which a card was committed
## (so the no-commit stalemate, C9, is out of the way), wins 3-3, rows, hands, Decks and Piles
## empty, seat 1 ahead on the Match total.
func _sudden_death_last_turn() -> MatchEngine:
	var engine: MatchEngine = _started()
	var state: MatchState = engine._state
	state.round_number = MatchRules.ROUNDS + 1
	state.sudden_death = true
	state.turn = MatchRules.TURNS
	state.round_committed = 1
	state.wins.assign([3, 3])
	state.match_scores.assign([3, 11])
	for piles: MatchState.SeatPiles in state.seats:
		piles.hand.clear()
		piles.deck.clear()
		piles.pile.clear()
	return engine


# --- A paused D12 (RESUME_ROUND_END) --------------------------------------------------


## A row card's On discard opens a prompt in the Round-end drain (D12): the Round is not
## awarded and no Dross leaves while it is open. The answer finishes the drain, then ROUND_ENDED
## comes once, then one DROSS_EXPIRED per `round` Dross in ascending id, whatever its zone (the
## row Dross was Discarded to its Owner's Pile first), then the next Round. A `match` Dross
## stays.
func test_a_paused_round_end_expires_dross_once_after_the_answer() -> void:
	var engine: MatchEngine = _started()
	var state: MatchState = engine._state
	var cards: MatchCards = engine.match_cards()
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	cards.set_verb_handler(verbs)
	var dross: CardDef = cards.pool_def("dross")
	var keeper: CardDef = _keeper()
	var in_deck: int = AbilitiesComboDisruption.create(state, cards, dross, 1)
	var in_hand: int = AbilitiesComboDisruption.create(state, cards, dross, 0)
	var kept: int = AbilitiesComboDisruption.create(state, cards, keeper, 0)
	var in_pile: int = AbilitiesComboDisruption.create(state, cards, dross, 0)
	var on_row: int = AbilitiesComboDisruption.create(state, cards, dross, 1)
	# The watcher fires from its Owner's Pile once the Round-end clear has Discarded it.
	var watcher: int = state.seats[0].deck.pop_back()
	var watching: CardAbility = StubAbilities.ability(
		CardAbility.MOMENT_DISCARD, StubAbilities.VERB_CHOOSE_HAND
	)
	var abilities: Array[CardAbility] = [watching]
	var def: CardDef = StubAbilities.card_def("Watcher", abilities)
	assert_bool(StubAbilities.give(cards, _typed([watcher]), def)).is_true()
	# Small hands: no discard-down on the passes, and two or more cards so the prompt opens.
	var first_card: int = state.seats[0].hand[0]
	state.seats[0].hand.assign(_typed([first_card, in_hand, kept]))
	state.seats[1].hand.assign(_typed([state.seats[1].hand[0]]))
	state.seats[0].pile.assign(_typed([in_pile]))
	state.seats[1].deck.push_front(in_deck)
	StubAbilities.put_row(state, 0, _typed([watcher]), true)
	StubAbilities.put_row(state, 1, _typed([on_row]), true)
	state.turn = MatchRules.TURNS
	state.turn_wins.assign([2, 0])

	var paused: Array[MatchEvent] = _pass_turn(engine)
	assert_int(engine.awaited_seat()).is_equal(0)
	var prompt: Dictionary = engine.open_prompt()
	assert_str(Choice.resume_of(prompt)).is_equal(Choice.RESUME_ROUND_END)
	assert_str(Choice.step_of(prompt)).is_equal(TurnFlow.STEP_ROUND_END)
	assert_array(_of_kind(paused, ROUND_ENDED)).is_empty()
	assert_array(_of_kind(paused, EXPIRED)).is_empty()
	assert_object(cards.def_of(in_hand)).is_not_null()

	var result: ApplyResult = engine.apply(EngineAction.choose(0, Choice.Zone.OWN_HAND, 0))
	assert_bool(result.ok).is_true()
	var events: Array[MatchEvent] = []
	events.append_array(result.events)
	assert_array(verbs.trace).is_equal(["chose %d" % first_card])
	assert_int(_of_kind(events, ROUND_ENDED).size()).is_equal(1)
	var winner: int = _of_kind(events, ROUND_ENDED)[0].payload["winner"]
	assert_int(winner).is_equal(0)
	assert_array(_expired_cards(events)).is_equal(_typed([in_deck, in_hand, in_pile, on_row]))
	assert_array(_expired_from(events)).is_equal(["deck", "hand", "pile", "pile"])
	assert_int(_first_at(events, CHOICE_MADE)).is_less(_first_at(events, ROUND_ENDED))
	assert_int(_first_at(events, ROUND_ENDED)).is_less(_first_at(events, EXPIRED))
	assert_int(_first_at(events, EXPIRED)).is_less(_first_at(events, ROUND_STARTED))
	assert_int(_of_kind(events, ROUND_STARTED).size()).is_equal(1)
	assert_int(state.round_number).is_equal(2)
	for card: int in [in_deck, in_hand, in_pile, on_row]:
		assert_object(cards.def_of(card)).is_null()
	assert_object(cards.def_of(kept)).is_same(keeper)
	assert_bool(state.seats[0].hand.has(in_hand)).is_false()
	assert_bool(state.seats[0].hand.has(kept)).is_true()
	assert_bool(state.seats[1].deck.has(in_deck)).is_false()
	assert_bool(state.seats[0].pile.has(in_pile)).is_false()
	assert_bool(state.seats[1].pile.has(on_row)).is_false()


# --- The sudden-death stalemate after expiry ------------------------------------------


## A tied sudden-death Round in which a card was committed, both seats holding only `round`
## Dross: the Dross leaves first, so both seats count as empty and the Match ends in a
## stalemate, the higher Match total winning.
func test_a_seat_holding_only_round_dross_counts_as_empty() -> void:
	var engine: MatchEngine = _sudden_death_last_turn()
	var state: MatchState = engine._state
	var cards: MatchCards = engine.match_cards()
	var dross: CardDef = cards.pool_def("dross")
	var in_hand: int = AbilitiesComboDisruption.create(state, cards, dross, 0)
	var in_deck: int = AbilitiesComboDisruption.create(state, cards, dross, 1)
	state.seats[0].hand.append(in_hand)
	state.seats[1].deck.append(in_deck)
	var events: Array[MatchEvent] = _pass_turn(engine)
	assert_array(_expired_cards(events)).is_equal(_typed([in_hand, in_deck]))
	assert_int(_first_at(events, EXPIRED)).is_less(_first_at(events, MATCH_ENDED))
	assert_bool(engine.is_over()).is_true()
	var reason: String = state.result["reason"]
	assert_str(reason).is_equal(MatchEngine.REASON_STALEMATE)
	assert_int(engine.match_winner()).is_equal(1)
	assert_array(_of_kind(events, ROUND_STARTED)).is_empty()


## The same Round with a `match` Dross in seat 0's hand: that seat is not empty, the `round`
## Dross alone leaves, and the next sudden-death Round starts.
func test_a_match_dross_keeps_a_seat_alive() -> void:
	var engine: MatchEngine = _sudden_death_last_turn()
	var state: MatchState = engine._state
	var cards: MatchCards = engine.match_cards()
	var dross: CardDef = cards.pool_def("dross")
	var kept: int = AbilitiesComboDisruption.create(state, cards, _keeper(), 0)
	var in_deck: int = AbilitiesComboDisruption.create(state, cards, dross, 1)
	state.seats[0].hand.append(kept)
	state.seats[1].deck.append(in_deck)
	var events: Array[MatchEvent] = _pass_turn(engine)
	assert_array(_expired_cards(events)).is_equal(_typed([in_deck]))
	assert_array(_of_kind(events, MATCH_ENDED)).is_empty()
	assert_bool(engine.is_over()).is_false()
	assert_int(_of_kind(events, ROUND_STARTED).size()).is_equal(1)
	assert_int(state.round_number).is_equal(MatchRules.ROUNDS + 2)
	assert_bool(state.sudden_death).is_true()
	assert_bool(state.seats[0].hand.has(kept)).is_true()
