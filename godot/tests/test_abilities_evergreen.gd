class_name TestAbilitiesEvergreen
extends FullMatchHarness
## The evergreen card abilities (DC-13 T06; cycle 9 plan P3 verb table, P12; canon
## [[rules/cards-v2]] section 2.7): each case puts the shipped card's definition on a stub
## deck instance (StubAbilities, MatchCards.replace_def) and drives it through the trigger
## queue or a Walk; stub statuses and shifts stand in for the effects no milestone A card
## makes. The last case plays random bots over the look-at and choice cards with the
## harness's leak scan at every step. Seat 1's instances add MatchRules.DECK_SIZE.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const GUARD: int = 60
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const LOOKED: int = MatchEvent.Kind.CARD_LOOKED
const STATS: int = MatchEvent.Kind.STATS_CHANGED
## The shipped ids the leak-scan match puts on each seat's stub-deck cards (four copies
## each, from the stub card's first instance).
const SCAN_CARDS: Dictionary[int, String] = {
	StubAbilities.MOTE: "ev07",  # Lookout
	StubAbilities.WISP: "ev06",  # Delve
	StubAbilities.PEBBLE: "ev10",  # Mirror
	StubAbilities.SCAPEGOAT: "gr01",  # Ember
	StubAbilities.BRACE: "ev16",  # Loom
	StubAbilities.BASTION: "gr07",  # Banner
}
const SCAN_SEEDS: Array[int] = [1, 2]

# --- Helpers --------------------------------------------------------------------------


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


## Wakes `moment` for `subjects` and drains it at `step`; true when it paused.
func _fire(
	state: MatchState,
	cards: MatchCards,
	moment: String,
	subjects: Array[int],
	rec: StubAbilities.Recorder,
	step: String = "D2"
) -> bool:
	TriggerQueue.wake(state, cards, moment, subjects)
	return TriggerQueue.drain(state, cards, MatchRng.new(SEED), rec.record, step)


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


## `key` of every event of `kind` that `rec` holds, in order.
func _ints(rec: StubAbilities.Recorder, kind: int, key: String) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in rec.of_kind(kind):
		out.append(_int_of(event, key))
	return out


func _power(state: MatchState, cards: MatchCards, card: int) -> int:
	return Scoring.stats(card, state, cards).power


## A stub card on `card` whose one ability records `moment` (StubVerbs.VERB_RECORD).
func _recorder_card(cards: MatchCards, card: int, moment: String, watch: String = "self") -> void:
	var abilities: Array[CardAbility] = [
		StubAbilities.ability(moment, StubAbilities.VERB_RECORD, 0, watch)
	]
	var def: CardDef = StubAbilities.card_def("Watcher", abilities, 1)
	assert_bool(StubAbilities.give(cards, _typed([card]), def)).is_true()


# --- Tuft, Scout, Delve, Lookout --------------------------------------------------------


## Tuft: each Score gives it Power +1 as a Board change, so it Scores 1, 2, 3 over three
## Walks; the change leaves with the row (Memory stays empty).
func test_tuft_gains_one_per_score_until_it_leaves_the_row() -> void:
	var cards: MatchCards = _cards()
	var tuft: int = 0
	_put(cards, _typed([tuft]), "ev03")
	var state: MatchState = StubAbilities.table(_typed([tuft]), false)
	var powers: Array[int] = []
	var last: StubAbilities.Recorder = null
	for _walk_number: int in range(3):
		last = StubAbilities.recorder()
		_walk(state, cards, last)
		powers.append_array(_ints(last, SCORED, "power"))
	assert_array(powers).is_equal(_typed([1, 2, 3]))
	assert_int(state.card_state(tuft).power_delta).is_equal(3)
	var changed: Array[MatchEvent] = last.of_kind(STATS)
	assert_int(changed.size()).is_equal(1)
	assert_int(_int_of(changed[0], "power")).is_equal(4)
	assert_bool(changed[0].payload["permanent"]).is_false()
	assert_int(changed[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_bool(Statuses.take_from_row(state, 0, tuft, Callable())).is_true()
	assert_int(_power(state, cards, tuft)).is_equal(1)
	assert_object(state.memory_of(tuft)).is_null()


## Scout draws the top card of its Controller's Deck (CARD_DRAWN private); from an empty
## Deck it draws nothing, DRAW_EMPTY is public and its seat's On empty draw fires.
func test_scout_draws_and_from_an_empty_deck_fires_on_empty_draw() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var scout: int = StubAbilities.SCOUT
	var state: MatchState = StubAbilities.table(_typed([scout]), false)
	state.seats[0].deck.assign(_typed([StubAbilities.PEBBLE]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].hand).is_equal(_typed([StubAbilities.PEBBLE]))
	assert_array(state.seats[0].deck).is_empty()
	var drawn: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.CARD_DRAWN)
	assert_int(drawn.size()).is_equal(1)
	assert_int(drawn[0].owner_seat).is_equal(0)
	assert_int(_int_of(drawn[0].redacted_for(1), "card")).is_equal(MatchEvent.HIDDEN_CARD)
	# An empty Deck: nothing drawn, On empty draw fires for the seat's watcher.
	var watcher: int = 0
	_recorder_card(cards, watcher, "on_empty_draw")
	var empty: MatchState = StubAbilities.table(_typed([watcher, scout + 1]), false)
	empty.seats[0].revealed[watcher] = true
	var dry: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(empty, cards, dry)
	assert_array(empty.seats[0].hand).is_empty()
	var denied: Array[MatchEvent] = dry.of_kind(MatchEvent.Kind.DRAW_EMPTY)
	assert_int(denied.size()).is_equal(1)
	assert_int(_int_of(denied[0], "seat")).is_equal(0)
	assert_int(denied[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	var fired: Array[String] = []
	for line: String in verbs.trace:
		if line.begins_with("fire %d " % watcher):
			fired.append(line)
	assert_int(fired.size()).is_equal(1)
	assert_int(dry.cards_of(FIRED).count(watcher)).is_equal(1)


## Delve looks at the top three (one private CARD_LOOKED each), prompts over them in zone
## own_deck_top (deck_top in its own view only), draws the chosen one and shuffles the
## other two back in with the stream; the other seat sees counts only.
func test_delve_offers_three_draws_the_chosen_one_and_shuffles_the_others_in() -> void:
	var cards: MatchCards = _cards()
	var delve: int = 0
	_put(cards, _typed([delve]), "ev06")
	var state: MatchState = StubAbilities.table(_typed([delve]), false)
	var top: Array[int] = [8, 9, 10]
	state.seats[0].deck.assign(_typed([8, 9, 10, 11, 1]))
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_deck_top")
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 1, 2]))
	assert_bool(Choice.is_multi_prompt(state.prompt)).is_false()
	assert_array(rec.cards_of(LOOKED)).is_equal(top)
	for event: MatchEvent in rec.of_kind(LOOKED):
		assert_int(event.owner_seat).is_equal(0)
	var own: SeatView = SeatView.build(state, 0, 0, cards)
	assert_array(own.deck_top).is_equal(top)
	var theirs: SeatView = SeatView.build(state, 1, 0, cards)
	assert_array(theirs.deck_top).is_empty()
	assert_dict(theirs.prompt).is_equal({"open": true, "seat": 0})
	var picked: Array[int] = [1]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OWN_DECK_TOP, picked, false)
	).is_false()
	assert_array(state.seats[0].hand).is_equal(_typed([9]))
	var expected: Array[int] = [11, 1]
	var mirror: MatchRng = MatchRng.new(SEED)
	for card: int in [8, 10]:
		expected.insert(mirror.pick_index(expected.size() + 1), card)
	assert_array(state.seats[0].deck).is_equal(expected)
	assert_array(SeatView.build(state, 0, -1, cards).deck_top).is_empty()
	var after: SeatView = SeatView.build(state, 1, -1, cards)
	assert_int(after.deck_counts[0]).is_equal(4)
	assert_int(after.opponent_hand_count).is_equal(1)
	# No event the other seat receives names one of the looked-at cards.
	var looked_at: Array[int] = [8, 9, 10, 11, 1]
	for event: MatchEvent in rec.events:
		for card: int in FullMatchRun.event_card_ids(event.redacted_for(1)):
			assert_bool(looked_at.has(card)).override_failure_message(
				"%s names %d" % [MatchEvent.kind_name(event.kind), card]
			).is_false()
	assert_bool(ScoreWalk.resume_pulse(state, cards, rng, rec.record)).is_false()
	assert_array(rec.cards_of(SCORED)).is_equal(_typed([delve]))


## Delve over a Deck of one draws it with no prompt; over an empty Deck it fizzles.
func test_delve_over_one_card_draws_it_and_over_none_fizzles() -> void:
	var cards: MatchCards = _cards()
	var delve: int = 0
	_put(cards, _typed([delve, delve + 1]), "ev06")
	var state: MatchState = StubAbilities.table(_typed([delve]), true)
	state.seats[0].deck.assign(_typed([8]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_reveal", _typed([delve]), rec)).is_false()
	assert_array(state.seats[0].hand).is_equal(_typed([8]))
	assert_array(rec.of_kind(MatchEvent.Kind.PROMPT_OPENED)).is_empty()
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_reveal", _typed([delve]), none)).is_false()
	var fizzled: Array[MatchEvent] = none.of_kind(FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	assert_str(_str_of(fizzled[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)


## Lookout prompts over the face-down opposing cards; the chosen one joins its seat's
## `looked` (its view names it at its slot, the other seat's does not), CARD_LOOKED is
## private, and the card leaves `looked` when it is revealed.
func test_lookout_records_the_card_for_the_looker_only() -> void:
	var cards: MatchCards = _cards()
	var lookout: int = 0
	_put(cards, _typed([lookout]), "ev07")
	var x: int = OTHER + StubAbilities.PEBBLE
	var y: int = OTHER + StubAbilities.MOTE
	var state: MatchState = MatchState.new(SEED)
	StubAbilities.put_row(state, 0, _typed([lookout]), false)
	StubAbilities.put_row(state, 1, _typed([x, y]), false)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("opponent_board")
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 1]))
	var picked: Array[int] = [1]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OPPONENT_BOARD, picked, false)
	).is_false()
	assert_bool(state.seats[0].looked.has(y)).is_true()
	var own: SeatView = SeatView.build(state, 0, -1, cards)
	var expected: Dictionary[int, int] = {1: y}
	assert_dict(own.looked).is_equal(expected)
	var hidden: Dictionary = own.opponent_row[1]
	assert_int(hidden["card"]).is_equal(MatchEvent.HIDDEN_CARD)
	assert_dict(SeatView.build(state, 1, -1, cards).looked).is_empty()
	var looked: Array[MatchEvent] = rec.of_kind(LOOKED)
	assert_int(looked.size()).is_equal(1)
	assert_int(looked[0].owner_seat).is_equal(0)
	assert_int(_int_of(looked[0], "card")).is_equal(y)
	assert_int(_int_of(looked[0], "slot")).is_equal(1)
	assert_int(_int_of(looked[0].redacted_for(1), "card")).is_equal(MatchEvent.HIDDEN_CARD)
	var made: MatchEvent = rec.of_kind(MatchEvent.Kind.CHOICE_MADE)[0]
	assert_int(_int_of(made.redacted_for(1), "target")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_bool(ScoreWalk.resume_pulse(state, cards, rng, rec.record)).is_false()
	assert_bool(ScoreWalk.run(state, cards, rng, rec.record)).is_false()
	assert_bool(state.seats[0].looked.is_empty()).is_true()


# --- Statuses and protections ---------------------------------------------------------


## Scapegoat: a stub Squelch wakes its On squelch, which ends the Squelch and Condemns it.
func test_scapegoat_ends_its_squelch_and_condemns_itself() -> void:
	var cards: MatchCards = _cards()
	var goat: int = StubAbilities.SCAPEGOAT
	var state: MatchState = StubAbilities.table(_typed([goat]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var applied: Statuses.Applied = StubAbilities.stub_squelch(state, cards, goat, rec.record)
	assert_bool(applied.wakes_squelch).is_true()
	assert_bool(_fire(state, cards, "on_squelch", _typed([goat]), rec)).is_false()
	assert_bool(Statuses.has(state, goat, Statuses.SQUELCHED)).is_false()
	assert_str(Statuses.exit_mark_of(state, goat)).is_equal(Statuses.CONDEMNED)
	var ended: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.STATUS_ENDED)
	assert_int(ended.size()).is_equal(1)
	assert_str(_str_of(ended[0], "status")).is_equal(Statuses.SQUELCHED)
	assert_str(_str_of(ended[0], "cause")).is_equal("scapegoat")
	assert_int(rec.of_kind(MatchEvent.Kind.EXIT_MARKED).size()).is_equal(1)


## Ward's On score protects its seat's cards from Muted until end of turn: a stub Silence
## then lands Squelched only; turn end lifts the protection.
func test_ward_then_a_stub_silence_leaves_squelched() -> void:
	var cards: MatchCards = _cards()
	var ward: int = 0
	var mote: int = 1
	_put(cards, _typed([ward]), "ev09")
	var state: MatchState = StubAbilities.table(_typed([ward, mote]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_score", _typed([ward]), rec, "D8")).is_false()
	assert_bool(state.seat_protections[0].has(Statuses.MUTED)).is_true()
	var silenced: Statuses.Applied = StubAbilities.stub_silence(state, cards, mote, rec.record)
	assert_array(silenced.landed).contains_exactly([Statuses.SQUELCHED])
	assert_array(silenced.blocked).contains_exactly([Statuses.MUTED])
	assert_bool(Statuses.has(state, mote, Statuses.SQUELCHED)).is_true()
	assert_bool(Statuses.has(state, mote, Statuses.SILENCED)).is_false()
	assert_array(Statuses.badges(state, cards, mote)).contains_exactly(["Squelched"])
	TurnFlow.end_statuses(state, Callable())
	assert_dict(state.seat_protections[0]).is_empty()


## Bastion's Ongoing refuses a stub Condemn; Squelched, its Ongoing is not read and the
## Condemn lands.
func test_bastion_refuses_a_stub_condemn() -> void:
	var cards: MatchCards = _cards()
	var bastion: int = StubAbilities.BASTION
	var state: MatchState = StubAbilities.table(_typed([bastion]), true)
	assert_bool(StubAbilities.stub_condemn(state, cards, bastion, Callable())).is_false()
	assert_str(Statuses.exit_mark_of(state, bastion)).is_equal("")
	StubAbilities.stub_squelch(state, cards, bastion, Callable())
	assert_bool(StubAbilities.stub_condemn(state, cards, bastion, Callable())).is_true()
	assert_str(Statuses.exit_mark_of(state, bastion)).is_equal(Statuses.CONDEMNED)


# --- Mirror, Nudge, Brace -------------------------------------------------------------


## Mirror copies the one revealed opposing card's current Power and Bonus (with its Memory)
## until end of turn, choosing it at once since the face-down card is not offered; it
## Scores as the copy.
func test_mirror_copies_a_revealed_opposing_card_until_turn_end() -> void:
	var cards: MatchCards = _cards()
	var mirror: int = 0
	_put(cards, _typed([mirror]), "ev10")
	var wisp: int = OTHER + StubAbilities.WISP
	var down: int = OTHER + StubAbilities.PEBBLE
	var state: MatchState = MatchState.new(SEED)
	StubAbilities.put_row(state, 0, _typed([mirror]), false)
	StubAbilities.put_row(state, 1, _typed([wisp, down]), false)
	state.seats[1].revealed[wisp] = true
	state.memory_for(wisp).power = 2
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(rec.of_kind(MatchEvent.Kind.PROMPT_OPENED)).is_empty()
	var scored: Array[MatchEvent] = rec.of_kind(SCORED)
	assert_int(_int_of(scored[0], "card")).is_equal(mirror)
	assert_int(_int_of(scored[0], "power")).is_equal(3)
	assert_int(_int_of(scored[0], "bonus_value")).is_equal(12500)
	var copied: Scoring.Stats = Scoring.stats(mirror, state, cards)
	assert_int(copied.power).is_equal(3)
	assert_array(copied.mults).is_equal(_typed([125]))
	TurnFlow.end_statuses(state, Callable())
	var plain: Scoring.Stats = Scoring.stats(mirror, state, cards)
	assert_int(plain.power).is_equal(0)
	assert_array(plain.mults).is_empty()


## With two revealed opposing cards Mirror prompts over them and never offers the
## face-down one between them.
func test_mirror_does_not_offer_a_face_down_card() -> void:
	var cards: MatchCards = _cards()
	var mirror: int = 0
	_put(cards, _typed([mirror]), "ev10")
	var first: int = OTHER + StubAbilities.WISP
	var down: int = OTHER + StubAbilities.PEBBLE
	var last: int = OTHER + StubAbilities.MOTE
	var state: MatchState = MatchState.new(SEED)
	StubAbilities.put_row(state, 0, _typed([mirror]), true)
	StubAbilities.put_row(state, 1, _typed([first, down, last]), true)
	assert_bool(state.seats[1].revealed.erase(down)).is_true()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_reveal", _typed([mirror]), rec, "D7")).is_true()
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 2]))
	var picked: Array[int] = [2]
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OPPONENT_BOARD, picked, false)
	).is_false()
	assert_int(_power(state, cards, mirror)).is_equal(2)


## Nudge from the rightmost slot wraps to slot 0 (the card there takes its slot); both
## moved cards are announced.
func test_nudge_wraps_from_the_rightmost_slot() -> void:
	var cards: MatchCards = _cards()
	var nudge: int = StubAbilities.NUDGE
	var a: int = StubAbilities.MOTE
	var b: int = StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(_typed([a, b, nudge]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_reveal", _typed([nudge]), rec, "D7")).is_false()
	assert_array(state.seats[0].board).is_equal(_typed([nudge, b, a]))
	assert_array(rec.cards_of(MatchEvent.Kind.CARD_MOVED)).is_equal(_typed([nudge, a]))


## Brace is not moved by a stub shift; once Squelched its Ongoing stops and it moves.
func test_brace_holds_through_a_stub_shift_until_squelched() -> void:
	var cards: MatchCards = _cards()
	var a: int = StubAbilities.MOTE
	var brace: int = StubAbilities.BRACE
	var c: int = StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(_typed([a, brace, c]), true)
	var moved: Array[int] = StubAbilities.stub_shift_others_left(state, cards, 0, -1, Callable())
	assert_array(state.seats[0].board).is_equal(_typed([c, brace, a]))
	assert_bool(moved.has(brace)).is_false()
	StubAbilities.stub_squelch(state, cards, brace, Callable())
	var again: Array[int] = StubAbilities.stub_shift_others_left(state, cards, 0, -1, Callable())
	assert_bool(again.has(brace)).is_true()
	assert_int(state.seats[0].board.find(brace)).is_not_equal(1)


# --- Pantry, Loom, Bolster, Banner ----------------------------------------------------


## Pantry read on its row makes the Hand size 6; face down it is not read.
func test_pantry_gives_hand_size_6() -> void:
	var cards: MatchCards = _cards()
	var pantry: int = 0
	_put(cards, _typed([pantry]), "ev14")
	var state: MatchState = StubAbilities.table(_typed([pantry]), false)
	assert_int(TurnFlow.hand_size(state, cards, 0)).is_equal(MatchRules.HAND_SIZE)
	state.seats[0].revealed[pantry] = true
	assert_int(TurnFlow.hand_size(state, cards, 0)).is_equal(6)


## Loom gives the card to its right (face down here: the change is private) Power +2 until
## end of turn; at the rightmost slot it fizzles.
func test_loom_grants_the_right_card_power_until_turn_end() -> void:
	var cards: MatchCards = _cards()
	var loom: int = 0
	var right: int = 1
	_put(cards, _typed([loom]), "ev16")
	var state: MatchState = StubAbilities.table(_typed([loom, right]), false)
	state.seats[0].revealed[loom] = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_reveal", _typed([loom]), rec, "D7")).is_false()
	assert_int(_power(state, cards, right)).is_equal(4)
	var changed: Array[MatchEvent] = rec.of_kind(STATS)
	assert_int(changed.size()).is_equal(1)
	assert_int(changed[0].owner_seat).is_equal(0)
	assert_int(_int_of(changed[0].redacted_for(1), "power")).is_equal(0)
	TurnFlow.end_statuses(state, Callable())
	assert_int(_power(state, cards, right)).is_equal(2)
	assert_int(_power(state, cards, loom)).is_equal(3)
	var alone: MatchState = StubAbilities.table(_typed([right, loom]), true)
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(alone, cards, "on_reveal", _typed([loom]), none, "D7")).is_false()
	assert_int(none.of_kind(FIZZLED).size()).is_equal(1)


## Bolster gives each other revealed card of its seat Power +1 until end of turn, not a
## face-down one and not itself.
func test_bolster_grants_the_other_revealed_cards_until_turn_end() -> void:
	var cards: MatchCards = _cards()
	var bolster: int = 0
	var a: int = 1
	var down: int = 2
	var d: int = 3
	_put(cards, _typed([bolster]), "ev19")
	var state: MatchState = StubAbilities.table(_typed([a, bolster, down, d]), true)
	assert_bool(state.seats[0].revealed.erase(down)).is_true()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_reveal", _typed([bolster]), rec, "D7")).is_false()
	var powers: Array[int] = []
	for card: int in [a, bolster, down, d]:
		powers.append(_power(state, cards, card))
	assert_array(powers).is_equal(_typed([3, 4, 2, 3]))
	TurnFlow.end_statuses(state, Callable())
	powers.clear()
	for card: int in [a, bolster, down, d]:
		powers.append(_power(state, cards, card))
	assert_array(powers).is_equal(_typed([2, 4, 2, 2]))


## Banner (revealed, read) gives each of its seat's cards with no rules text Power +4:
## Mote, not Scout, not itself, not the other seat's; face down or Squelched it is not read.
func test_banner_gives_four_to_mote_and_nothing_to_scout() -> void:
	var cards: MatchCards = _cards()
	var banner: int = 0
	var mote: int = 1
	var scout: int = StubAbilities.SCOUT
	var theirs: int = OTHER + StubAbilities.MOTE
	_put(cards, _typed([banner]), "gr07")
	var state: MatchState = StubAbilities.table(_typed([banner, mote, scout]), true)
	StubAbilities.put_row(state, 1, _typed([theirs]), true)
	assert_int(_power(state, cards, mote)).is_equal(6)
	assert_int(_power(state, cards, scout)).is_equal(2)
	assert_int(_power(state, cards, banner)).is_equal(3)
	assert_int(_power(state, cards, theirs)).is_equal(2)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(_ints(rec, SCORED, "power")).contains([6])
	StubAbilities.stub_squelch(state, cards, banner, Callable())
	assert_int(_power(state, cards, mote)).is_equal(2)


# --- Random bots over the look-at and choice cards ------------------------------------


## The stub deck on both seats with Lookout, Delve, Mirror, Ember, Loom and Banner in place
## of six of its cards (SCAN_CARDS), Scout, Nudge, Flare and Courier kept.
func _new_engine(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = StubAbilities.engine(match_seed)
	var cards: MatchCards = engine.match_cards()
	for seat: int in range(MatchEngine.SEATS):
		for first: int in SCAN_CARDS:
			var instances: Array[int] = []
			for copy: int in range(MatchRules.MAX_COPIES):
				instances.append(seat * OTHER + first + copy)
			_put(cards, instances, SCAN_CARDS[first])
	return engine


## Random against random over those cards: every prompt is answered (single choices over a
## hand, an opposing row and the Deck top, the discard-down), the match ends with no
## rejected action, the leak scan at every step finds nothing, and a replay of the accepted
## actions reaches the same full state.
func test_random_bots_play_the_look_and_choice_cards_without_a_leak() -> void:
	for match_seed: int in SCAN_SEEDS:
		var run: FullMatchRun = _play(match_seed, true)
		var label: String = "seed %d: " % match_seed
		assert_bool(run.start_ok).override_failure_message(label + "start failed").is_true()
		assert_bool(run.capped).override_failure_message(label + "capped").is_false()
		_assert_none(run.rejections, label + "rejected bot action")
		_assert_none(run.leaks, label + "hidden card leaked")
		assert_bool(run.engine.is_over()).override_failure_message(label + "not over").is_true()
		assert_int(run.choices).override_failure_message(label + "no prompt").is_greater(0)
		var again: MatchEngine = _new_engine(match_seed)
		assert_bool(again.start().ok).is_true()
		for action: EngineAction in run.engine.accepted_actions():
			assert_bool(again.apply(action).ok).is_true()
		assert_dict(again.full_state()).is_equal(run.engine.full_state())
