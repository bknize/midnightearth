# gdlint: disable=max-public-methods
class_name TestAbilitiesDisruption
extends GdUnitTestSuite
## The Disruption card abilities and Dross (DC-14 T12; canon [[rules/cards-v2]] sections 1,
## 2.3 and 5; [[rules/resolution]] Q2, Q9, Q10): one case per card text and one per Flags
## note. Each case puts the shipped card's definition on a stub deck instance
## (StubAbilities.replace_def); seat 1's instances add DECK_SIZE.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const GUARD: int = 80
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const PROMPTED: int = MatchEvent.Kind.PROMPT_OPENED
const CREATED: int = MatchEvent.Kind.CARD_CREATED
const CONTROL: int = MatchEvent.Kind.CONTROL_CHANGED
const WALK_ENDED: int = MatchEvent.Kind.WALK_ENDED
const DROSS: String = "dross"

var _cached_db: CardDb = null
## A sink for the TurnFlow calls whose events a case does not read (TurnFlow calls its
## sink without checking it).
var _spare: StubAbilities.Recorder = StubAbilities.recorder()

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


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
	var rng: MatchRng = MatchRng.new(SEED)
	var guard: int = 0
	while state.walk.active and guard < GUARD:
		assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_false()
		guard += 1


func _int_of(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _str_of(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


## The cards of `seat`'s row holding `status` now, in slot order.
func _with_status(state: MatchState, seat: int, status: String) -> Array[int]:
	var out: Array[int] = []
	for card: int in state.seats[seat].board:
		if Statuses.has(state, card, status):
			out.append(card)
	return out


## Creates `count` Dross Owned by `seat` straight into its hand.
func _dross_into(state: MatchState, cards: MatchCards, seat: int, count: int) -> void:
	var def: CardDef = cards.pool_def(DROSS)
	assert_object(def).is_not_null()
	for _made: int in range(count):
		var made: int = AbilitiesComboDisruption.create(state, cards, def, seat)
		state.seats[seat].hand.append(made)


# --- Hush -----------------------------------------------------------------------------


## Hush Mutes an opposing card until end of turn (by slot, face down too): the Muted Scout's
## On reveal does not fire, it still Scores, and the Mute ends at turn end; two opposing
## cards open a prompt over the opposing row.
func test_hush_mutes_an_opposing_card_until_end_of_turn() -> void:
	var cards: MatchCards = _cards()
	var hush: int = 4
	_put(cards, Typed.ints([hush, hush + 1]), "di01")
	var scout: int = OTHER + StubAbilities.SCOUT
	var state: MatchState = StubAbilities.table(Typed.ints([hush]), false)
	StubAbilities.put_row(state, 1, Typed.ints([scout]), false)
	state.seats[1].deck.assign(Typed.ints([OTHER + 8]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_bool(Statuses.has(state, scout, Statuses.MUTED)).is_true()
	assert_array(rec.cards_of(FIRED)).is_equal(Typed.ints([hush]))
	assert_array(state.seats[1].hand).is_empty()
	assert_array(rec.cards_of(SCORED)).contains([scout])
	TurnFlow.end_statuses(state, _spare.record)
	assert_bool(Statuses.has(state, scout, Statuses.MUTED)).is_false()
	var two: MatchState = StubAbilities.table(Typed.ints([hush + 1]), false)
	StubAbilities.put_row(two, 1, Typed.ints([OTHER, OTHER + 1]), false)
	ScoreWalk.begin(two)
	assert_bool(ScoreWalk.step(two, cards, MatchRng.new(SEED), _spare.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(two.prompt))).is_equal("opponent_board")
	assert_array(Choice.options_of(two.prompt)).is_equal(Typed.ints([0, 1]))


# --- Muzzle ---------------------------------------------------------------------------


## Muzzle Squelches an opposing card until end of turn: it does not Score this Walk.
func test_muzzle_squelches_an_opposing_card() -> void:
	var cards: MatchCards = _cards()
	var muzzle: int = 4
	_put(cards, Typed.ints([muzzle]), "di02")
	var pebble: int = OTHER + StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(Typed.ints([muzzle]), false)
	StubAbilities.put_row(state, 1, Typed.ints([pebble]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_bool(Statuses.has(state, pebble, Statuses.SQUELCHED)).is_true()
	assert_array(rec.cards_of(SCORED)).is_equal(Typed.ints([muzzle]))
	assert_int(state.scores[1]).is_equal(0)
	TurnFlow.end_statuses(state, _spare.record)
	assert_bool(Statuses.has(state, pebble, Statuses.SQUELCHED)).is_false()


## A Squelch that lands alone wakes On squelch (R34): Muzzle on a revealed Scapegoat makes
## it end its Squelch and Condemn itself.
func test_muzzle_wakes_on_squelch() -> void:
	var cards: MatchCards = _cards()
	var muzzle: int = 4
	_put(cards, Typed.ints([muzzle]), "di02")
	var goat: int = OTHER + StubAbilities.SCAPEGOAT
	var state: MatchState = StubAbilities.table(Typed.ints([muzzle]), false)
	StubAbilities.put_row(state, 1, Typed.ints([goat]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(rec.cards_of(FIRED)).is_equal(Typed.ints([muzzle, goat]))
	assert_bool(Statuses.has(state, goat, Statuses.SQUELCHED)).is_false()
	assert_str(Statuses.exit_mark_of(state, goat)).is_equal(Statuses.CONDEMNED)


# --- Litter and Dross -----------------------------------------------------------------


## Litter creates three Dross in the opponent's hand, each Owned by that seat, with a public
## CARD_CREATED each; the other seat's view counts them and names none.
func test_litter_creates_three_dross_in_the_opponents_hand() -> void:
	var cards: MatchCards = _cards()
	var litter: int = 4
	_put(cards, Typed.ints([litter]), "di03")
	var state: MatchState = StubAbilities.table(Typed.ints([litter]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	var base: int = MatchCards.DROSS_BASE
	assert_array(state.seats[1].hand).is_equal(Typed.ints([base, base + 1, base + 2]))
	assert_array(state.seats[0].hand).is_empty()
	var created: Array[MatchEvent] = rec.of_kind(CREATED)
	assert_int(created.size()).is_equal(3)
	for event: MatchEvent in created:
		assert_int(event.owner_seat).is_equal(MatchEvent.PUBLIC)
		assert_int(_int_of(event, "seat")).is_equal(1)
		assert_int(_int_of(event, "owner")).is_equal(1)
		assert_str(_str_of(event, "def")).is_equal(DROSS)
		assert_str(_str_of(event, "to")).is_equal("hand")
		assert_int(_int_of(event, "slot")).is_equal(-1)
	assert_str(cards.def_of(base).id).is_equal(DROSS)
	assert_int(cards.origin_of(base + 2)).is_equal(1)
	var view: SeatView = SeatView.build(state, 0, -1, cards)
	assert_int(view.opponent_hand_count).is_equal(3)
	assert_array(view.own_hand).is_empty()
	var held: SeatView = SeatView.build(state, 1, -1, cards)
	assert_array(held.own_hand).is_equal(Typed.ints([base, base + 1, base + 2]))


## Litter Flags (CREATE) under rules 9 (cycle 14 R8, R10, C13): a Dross card is Owned by the
## seat it is put in and, within the Round, moves like any card: a Discarded Dross goes to
## that seat's Pile as a public CARD_DISCARDED (no DROSS_EXPIRED), its record kept, and a
## later Dredger shuffles it back with the Pile.
func test_a_discarded_dross_is_filed_and_can_be_shuffled_back() -> void:
	var cards: MatchCards = StubAbilities.defs(StubAbilities.RAMP_CREW)
	var state: MatchState = MatchState.new(SEED)
	_dross_into(state, cards, 1, 1)
	var dross: int = MatchCards.DROSS_BASE
	assert_bool(cards.def_of(dross).expires_at_round_end()).is_true()
	state.seats[1].hand.erase(dross)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	TurnFlow.to_pile(
		state, cards, rec.record, dross, TurnFlow.FROM_HAND, TurnFlow.REASON_DISCARD_DOWN
	)
	assert_array(state.seats[1].pile).is_equal(Typed.ints([dross]))
	assert_array(state.seats[0].pile).is_empty()
	assert_array(rec.of_kind(MatchEvent.Kind.DROSS_EXPIRED)).is_empty()
	var filed: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.CARD_DISCARDED)
	assert_int(filed.size()).is_equal(1)
	assert_int(filed[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_int(_int_of(filed[0], "owner")).is_equal(1)
	assert_str(cards.def_of(dross).id).is_equal(DROSS)
	assert_int(cards.origin_of(dross)).is_equal(1)
	# Seat 1's Deck is empty: its draw wakes Dredger, which shuffles the Dross back in (R10).
	var dredge: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.draw(state, cards, MatchRng.new(SEED), dredge.record, 1)).is_false()
	assert_int(dredge.of_kind(MatchEvent.Kind.PILE_SHUFFLED_IN).size()).is_equal(1)
	assert_array(state.seats[1].pile).is_empty()
	var back: bool = state.seats[1].deck.has(dross) or state.seats[1].hand.has(dross)
	assert_bool(back).is_true()


## Dross: at Walk end, before rounding, the holder's walking total is multiplied by ×0.75
## once per Dross in its hand (Pebble's 3 becomes 2.25, then 1.6875, Score 2); the other
## seat is untouched and WALK_ENDED counts the Dross per seat.
func test_dross_multiplies_the_holders_total_at_walk_end_once_per_dross() -> void:
	var cards: MatchCards = _cards()
	var pebble: int = OTHER + StubAbilities.PEBBLE
	var one: MatchState = StubAbilities.table(Typed.ints([StubAbilities.PEBBLE]), true)
	StubAbilities.put_row(one, 1, Typed.ints([pebble]), true)
	_dross_into(one, cards, 1, 1)
	_walk(one, cards, StubAbilities.recorder())
	assert_int(one.totals[0]).is_equal(30000)
	assert_int(one.totals[1]).is_equal(22500)
	assert_int(one.scores[1]).is_equal(2)
	var two: MatchState = StubAbilities.table(Typed.ints([StubAbilities.PEBBLE]), true)
	StubAbilities.put_row(two, 1, Typed.ints([pebble]), true)
	_dross_into(two, cards, 1, 2)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(two, cards, rec)
	assert_int(two.totals[1]).is_equal(16875)
	assert_int(two.scores[1]).is_equal(2)
	assert_int(two.scores[0]).is_equal(3)
	var ended: MatchEvent = rec.of_kind(WALK_ENDED)[0]
	assert_array(ended.payload["dross"]).is_equal([0, 2])
	assert_array(ended.payload["totals"]).is_equal([30000, 16875])
	# A Dross on a row, not in a hand, multiplies nothing.
	var played: MatchState = StubAbilities.table(Typed.ints([StubAbilities.PEBBLE]), true)
	_dross_into(played, cards, 0, 1)
	var on_row: int = played.seats[0].hand.pop_back()
	played.seats[0].board.append(on_row)
	_walk(played, cards, StubAbilities.recorder())
	assert_int(played.totals[0]).is_equal(30000)


## Dross is Cost 1, Power 0, no Bonus, and can be committed like any card.
func test_dross_costs_one_and_scores_zero() -> void:
	var cards: MatchCards = _cards()
	var state: MatchState = MatchState.new(SEED)
	_dross_into(state, cards, 0, 1)
	var dross: int = MatchCards.DROSS_BASE
	assert_int(Scoring.effective_cost(dross, state, cards)).is_equal(1)
	var read: Scoring.Stats = Scoring.stats(dross, state, cards)
	assert_int(read.power).is_equal(0)
	assert_int(read.bonus_value()).is_equal(MatchRules.SCALE)


# --- Saboteur -------------------------------------------------------------------------


## Saboteur moves to the rightmost slot of the opponent's row (CONTROL_CHANGED, Owner kept),
## is reached later this Walk and Scores for the opposing seat: (2 - 3) × 0.75 = -0.75, a
## Score of -1. The card sliding into its old slot Scores in that pulse; none is skipped.
func test_saboteur_scores_for_the_opposing_seat() -> void:
	var cards: MatchCards = _cards()
	var saboteur: int = 4
	_put(cards, Typed.ints([saboteur]), "di04")
	var pebble: int = StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(Typed.ints([saboteur, pebble]), false)
	StubAbilities.put_row(state, 1, Typed.ints([OTHER]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].board).is_equal(Typed.ints([pebble]))
	assert_array(state.seats[1].board).is_equal(Typed.ints([OTHER, saboteur]))
	assert_int(cards.origin_of(saboteur)).is_equal(0)
	assert_int(state.controller_of(saboteur)).is_equal(1)
	var changed: Array[MatchEvent] = rec.of_kind(CONTROL)
	assert_int(changed.size()).is_equal(1)
	assert_dict(changed[0].payload).is_equal(
		{"card": saboteur, "owner": 0, "controller": 1, "from_seat": 0, "slot": 1}
	)
	assert_array(rec.cards_of(SCORED)).is_equal(Typed.ints([pebble, OTHER, saboteur]))
	assert_int(state.totals[1]).is_equal(-7500)
	assert_int(state.scores[1]).is_equal(-1)
	assert_int(state.scores[0]).is_equal(3)


## Saboteur Flags (CTRL): it is on the opposing row at the end of the Walk and goes to its
## Owner's Pile at Round end (D12).
func test_saboteur_goes_to_its_owners_pile_at_round_end() -> void:
	var cards: MatchCards = _cards()
	var saboteur: int = 4
	_put(cards, Typed.ints([saboteur]), "di04")
	var state: MatchState = StubAbilities.table(Typed.ints([saboteur]), false)
	StubAbilities.put_row(state, 1, Typed.ints([OTHER]), false)
	_walk(state, cards, StubAbilities.recorder())
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.end_turn(state, cards, rng, _spare.record)).is_false()
	assert_array(state.seats[1].board).is_equal(Typed.ints([OTHER, saboteur]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_int(TurnFlow.end_round(state, cards, rng, rec.record)).is_not_equal(
		TurnFlow.ROUND_PAUSED
	)
	assert_array(state.seats[0].pile).is_equal(Typed.ints([saboteur]))
	assert_array(state.seats[1].pile).is_equal(Typed.ints([OTHER]))


## An Anchored Saboteur cannot be moved: it fizzles `no_target` and Scores for its Owner.
func test_an_anchored_saboteur_stays() -> void:
	var cards: MatchCards = _cards()
	var saboteur: int = 4
	_put(cards, Typed.ints([saboteur]), "di04")
	var state: MatchState = StubAbilities.table(Typed.ints([saboteur]), false)
	var cease: Dictionary = Statuses.cessation(Statuses.CEASE_TURN)
	Statuses.apply(state, cards, saboteur, Statuses.ANCHORED, cease, "test", _spare.record)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].board).is_equal(Typed.ints([saboteur]))
	assert_str(_str_of(rec.of_kind(FIZZLED)[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)
	assert_int(state.totals[0]).is_equal(-22500)


# --- Hex ------------------------------------------------------------------------------


## Hex chooses a card on either row at its reveal (a prompt over both rows), and at each On
## start Mutes the chosen card until end of turn.
func test_hex_mutes_the_chosen_card_on_start() -> void:
	var cards: MatchCards = _cards()
	var hex: int = 4
	_put(cards, Typed.ints([hex]), "di05")
	var pebble: int = OTHER + StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(Typed.ints([hex]), false)
	StubAbilities.put_row(state, 1, Typed.ints([OTHER, pebble]), false)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("both_boards")
	assert_array(Choice.options_of(state.prompt)).is_equal(Typed.ints([0, 1, 2]))
	var picked: Array[int] = [2]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.BOTH_BOARDS, picked, false)
	).is_false()
	assert_int(state.chosen[hex]).is_equal(pebble)
	assert_bool(ScoreWalk.resume_pulse(state, cards, rng, rec.record)).is_false()
	assert_bool(ScoreWalk.run(state, cards, rng, rec.record)).is_false()
	assert_bool(Statuses.has(state, pebble, Statuses.MUTED)).is_false()
	var started: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(state, cards, rng, started.record)).is_false()
	assert_bool(Statuses.has(state, pebble, Statuses.MUTED)).is_true()
	TurnFlow.end_statuses(state, _spare.record)
	assert_bool(Statuses.has(state, pebble, Statuses.MUTED)).is_false()
	assert_bool(TurnFlow.on_start(state, cards, rng, _spare.record)).is_false()
	assert_bool(Statuses.has(state, pebble, Statuses.MUTED)).is_true()
	var listed: Dictionary = state.to_dict()["chosen"]
	assert_dict(listed).is_equal({hex: pebble})
	assert_dict(state.duplicate().to_dict()["chosen"]).is_equal({hex: pebble})


## Hex Flags: the choice is kept until Hex or the chosen card leaves its row or is
## Un-revealed (then On start fizzles `no_target`); a Muted Hex does not fire.
func test_hex_choice_ends_when_either_card_leaves_or_flips() -> void:
	var cards: MatchCards = _cards()
	var hex: int = 4
	_put(cards, Typed.ints([hex]), "di05")
	var pebble: int = OTHER + StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(Typed.ints([hex]), true)
	StubAbilities.put_row(state, 1, Typed.ints([pebble, OTHER]), true)
	var rng: MatchRng = MatchRng.new(SEED)
	state.chosen[hex] = pebble
	StubAbilities.stub_mute(state, cards, hex, _spare.record)
	var muted: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(state, cards, rng, muted.record)).is_false()
	assert_array(muted.cards_of(FIRED)).is_empty()
	TurnFlow.end_statuses(state, _spare.record)
	assert_bool(Statuses.take_from_row(state, 1, pebble, _spare.record)).is_true()
	assert_bool(state.chosen.has(hex)).is_false()
	var gone: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(state, cards, rng, gone.record)).is_false()
	assert_str(_str_of(gone.of_kind(FIZZLED)[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)
	state.chosen[hex] = OTHER
	assert_bool(Statuses.unreveal(state, 0, hex, _spare.record)).is_true()
	assert_bool(state.chosen.has(hex)).is_false()


# --- Jam ------------------------------------------------------------------------------


## Jam's On score Mutes N random opposing cards until end of turn, N its Power read now:
## three of five, all of two, and five of six after Power +2.
func test_jam_mutes_its_power_in_random_opposing_cards() -> void:
	var cards: MatchCards = _cards()
	var jam: int = 4
	_put(cards, Typed.ints([jam]), "di06")
	var five: MatchState = StubAbilities.table(Typed.ints([jam]), true)
	StubAbilities.put_row(five, 1, Typed.ints(range(OTHER, OTHER + 5)), true)
	five.first_seat = 0
	_walk(five, cards, StubAbilities.recorder())
	assert_int(_with_status(five, 1, Statuses.MUTED).size()).is_equal(3)
	var two: MatchState = StubAbilities.table(Typed.ints([jam]), true)
	StubAbilities.put_row(two, 1, Typed.ints([OTHER, OTHER + 1]), true)
	_walk(two, cards, StubAbilities.recorder())
	assert_int(_with_status(two, 1, Statuses.MUTED).size()).is_equal(2)
	var grown: MatchState = StubAbilities.table(Typed.ints([jam]), true)
	StubAbilities.put_row(grown, 1, Typed.ints(range(OTHER, OTHER + 6)), true)
	grown.card_state_for(jam).power_delta = 2
	_walk(grown, cards, StubAbilities.recorder())
	assert_int(_with_status(grown, 1, Statuses.MUTED).size()).is_equal(5)


# --- Stasis ---------------------------------------------------------------------------


## Stasis: a Squelch applied by your effects lasts until Stasis leaves your row instead of
## until end of turn; it ends with Stasis.
func test_stasis_keeps_your_squelch_until_it_leaves_the_row() -> void:
	var cards: MatchCards = _cards()
	var stasis: int = 4
	var muzzle: int = 5
	_put(cards, Typed.ints([stasis]), "di07")
	_put(cards, Typed.ints([muzzle]), "di02")
	var pebble: int = OTHER + StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(Typed.ints([stasis]), true)
	state.seats[0].board.append(muzzle)
	StubAbilities.put_row(state, 1, Typed.ints([pebble]), true)
	_walk(state, cards, StubAbilities.recorder())
	assert_bool(Statuses.has(state, pebble, Statuses.SQUELCHED)).is_true()
	TurnFlow.end_statuses(state, _spare.record)
	assert_bool(Statuses.has(state, pebble, Statuses.SQUELCHED)).is_true()
	assert_bool(Statuses.take_from_row(state, 0, stasis, _spare.record)).is_true()
	assert_bool(Statuses.has(state, pebble, Statuses.SQUELCHED)).is_false()


## Stasis Flags: it protects the Squelch half of your Silences (the Mute half still ends at
## turn end); a Squelched Stasis's Ongoing stops, so a new Squelch takes the default end.
func test_stasis_holds_a_silences_squelch_half_unless_squelched() -> void:
	var cards: MatchCards = _cards()
	var stasis: int = 4
	var eclipse: int = 5
	var muzzle: int = 6
	_put(cards, Typed.ints([stasis]), "di07")
	_put(cards, Typed.ints([eclipse]), "di10")
	_put(cards, Typed.ints([muzzle]), "di02")
	var pebble: int = OTHER + StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(Typed.ints([stasis]), true)
	state.seats[0].board.append(eclipse)
	StubAbilities.put_row(state, 1, Typed.ints([pebble]), true)
	_walk(state, cards, StubAbilities.recorder())
	assert_bool(Statuses.has(state, pebble, Statuses.SILENCED)).is_true()
	TurnFlow.end_statuses(state, _spare.record)
	assert_bool(Statuses.has(state, pebble, Statuses.MUTED)).is_false()
	assert_bool(Statuses.has(state, pebble, Statuses.SQUELCHED)).is_true()
	var off: MatchState = StubAbilities.table(Typed.ints([stasis]), true)
	off.seats[0].board.append(muzzle)
	StubAbilities.put_row(off, 1, Typed.ints([pebble]), true)
	StubAbilities.stub_squelch(off, cards, stasis, _spare.record)
	_walk(off, cards, StubAbilities.recorder())
	assert_bool(Statuses.has(off, pebble, Statuses.SQUELCHED)).is_true()
	TurnFlow.end_statuses(off, _spare.record)
	assert_bool(Statuses.has(off, pebble, Statuses.SQUELCHED)).is_false()


# --- Gag ------------------------------------------------------------------------------


## Gag (On commit, revealed on an earlier Turn): a prompt at D3 over the opposing row; the
## chosen card is Squelched permanently, then Gag is Condemned.
func test_gag_squelches_permanently_then_condemns_itself() -> void:
	var cards: MatchCards = _cards()
	var gag: int = 4
	_put(cards, Typed.ints([gag]), "di08")
	var pebble: int = OTHER + StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(Typed.ints([gag]), true)
	StubAbilities.put_row(state, 1, Typed.ints([OTHER, pebble]), true)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_commit(state, cards, rng, rec.record, 0)).is_true()
	assert_str(Choice.step_of(state.prompt)).is_equal("D3")
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("opponent_board")
	var picked: Array[int] = [1]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OPPONENT_BOARD, picked, false)
	).is_false()
	assert_bool(state.memory_of(pebble).permanent_statuses.has(Statuses.SQUELCHED)).is_true()
	assert_str(Statuses.exit_mark_of(state, gag)).is_equal(Statuses.CONDEMNED)
	assert_bool(Statuses.has(state, OTHER, Statuses.SQUELCHED)).is_false()


## Gag Flags: the Squelch is Memory and follows the card into its Pile and back to a row; a
## Gag committed face down this Turn does not fire.
func test_gags_squelch_follows_the_card_and_a_face_down_gag_waits() -> void:
	var cards: MatchCards = _cards()
	var gag: int = 4
	_put(cards, Typed.ints([gag, gag + 1]), "di08")
	var pebble: int = OTHER + StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(Typed.ints([gag]), true)
	StubAbilities.put_row(state, 1, Typed.ints([pebble]), true)
	var rng: MatchRng = MatchRng.new(SEED)
	assert_bool(TurnFlow.on_commit(state, cards, rng, _spare.record, 0)).is_false()
	assert_bool(Statuses.take_from_row(state, 1, pebble, _spare.record)).is_true()
	TurnFlow.to_pile(state, cards, _spare.record, pebble, TurnFlow.FROM_ROW, TurnFlow.REASON_ROUND_END)
	assert_bool(Statuses.has(state, pebble, Statuses.SQUELCHED)).is_true()
	var face_down: MatchState = StubAbilities.table(Typed.ints([gag + 1]), false)
	StubAbilities.put_row(face_down, 1, Typed.ints([pebble]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_commit(face_down, cards, rng, rec.record, 0)).is_false()
	assert_array(rec.of_kind(FIRED)).is_empty()
	assert_bool(Statuses.has(face_down, pebble, Statuses.SQUELCHED)).is_false()


# --- Quorum ---------------------------------------------------------------------------


## Quorum prompts both seats in commit order (the first seat, then the second), each for
## exactly two of its revealed cards; then every other revealed card on both rows, its own
## included, is Muted until end of turn. The random bot answers each prompt legally.
func test_quorum_prompts_both_seats_in_order_and_mutes_the_rest() -> void:
	var cards: MatchCards = _cards()
	var quorum: int = 4
	_put(cards, Typed.ints([quorum]), "di09")
	var state: MatchState = StubAbilities.table(Typed.ints([quorum, 0, 1]), true)
	StubAbilities.put_row(state, 1, Typed.ints([OTHER, OTHER + 1, OTHER + 2]), true)
	state.first_seat = 1
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(state, cards, rng, rec.record)).is_true()
	assert_int(_prompt_seat(state)).is_equal(1)
	_assert_bot_answers(state, cards, 1)
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_board")
	assert_int(Choice.exact_of(state.prompt)).is_equal(2)
	var first: Array[int] = [1, 2]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OWN_BOARD, first, false)
	).is_true()
	assert_int(_prompt_seat(state)).is_equal(0)
	_assert_bot_answers(state, cards, 0)
	var second: Array[int] = [1, 2]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OWN_BOARD, second, false)
	).is_false()
	assert_int(rec.of_kind(PROMPTED).size()).is_equal(2)
	assert_array(_with_status(state, 0, Statuses.MUTED)).is_equal(Typed.ints([quorum]))
	assert_array(_with_status(state, 1, Statuses.MUTED)).is_equal(Typed.ints([OTHER]))
	TurnFlow.end_statuses(state, _spare.record)
	assert_array(_with_status(state, 0, Statuses.MUTED)).is_empty()


## Quorum Flags: a seat with two or fewer revealed cards is unaffected and not asked; with
## no seat over two, it fizzles `no_target`.
func test_quorum_skips_a_seat_with_two_or_fewer_revealed() -> void:
	var cards: MatchCards = _cards()
	var quorum: int = 4
	_put(cards, Typed.ints([quorum]), "di09")
	var state: MatchState = StubAbilities.table(Typed.ints([quorum, 0, 1]), true)
	StubAbilities.put_row(state, 1, Typed.ints([OTHER, OTHER + 1]), true)
	state.seats[1].board.append(OTHER + 2)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(state, cards, rng, rec.record)).is_true()
	assert_int(_prompt_seat(state)).is_equal(0)
	var kept: Array[int] = [0, 1]
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.Zone.OWN_BOARD, kept, false)
	).is_false()
	assert_array(_with_status(state, 0, Statuses.MUTED)).is_equal(Typed.ints([1]))
	assert_array(_with_status(state, 1, Statuses.MUTED)).is_empty()
	var small: MatchState = StubAbilities.table(Typed.ints([quorum, 0]), true)
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(small, cards, rng, none.record)).is_false()
	assert_str(_str_of(none.of_kind(FIZZLED)[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)


## Gives `quorum` a fixture Quorum with `uses` in `scope`, on a table where both seats hold
## three revealed cards, so a firing opens two prompts. `quorum` is in slot 0 of seat 0.
func _limited_quorum_table(cards: MatchCards, quorum: int, uses: int, scope: String) -> MatchState:
	var limited: CardAbility = StubAbilities.ability(
		CardAbility.MOMENT_START, AbilitiesComboDisruption.VERB_QUORUM, 2
	)
	limited.uses = uses
	limited.scope = scope
	var abilities: Array[CardAbility] = [limited]
	var def: CardDef = StubAbilities.card_def("Quorum", abilities, 4, 5)
	assert_bool(StubAbilities.give(cards, Typed.ints([quorum]), def)).is_true()
	var state: MatchState = StubAbilities.table(Typed.ints([quorum, 0, 1]), true)
	StubAbilities.put_row(state, 1, Typed.ints([OTHER, OTHER + 1, OTHER + 2]), true)
	return state


## R6 (T08 S1): one firing counts one use however many prompts it opens, in every scope. With
## `uses` 2 a firing asks both seats and leaves 1, nothing counted until the first answer; the
## second firing asks both again and leaves 0; the third fizzles `spent`. Each answer keeps
## slots 0 and 1, so Quorum itself is never Muted and always comes up.
func test_one_quorum_firing_counts_one_use_over_its_two_prompts() -> void:
	for scope: String in [Abilities.SCOPE_TURN, Abilities.SCOPE_ROW, Abilities.SCOPE_MATCH]:
		var cards: MatchCards = _cards()
		var quorum: int = 4
		var state: MatchState = _limited_quorum_table(cards, quorum, 2, scope)
		var rng: MatchRng = MatchRng.new(SEED)
		var rec: StubAbilities.Recorder = StubAbilities.recorder()
		var zone: int = Choice.Zone.OWN_BOARD
		var kept: Array[int] = [0, 1]
		for left: int in [1, 0]:
			assert_bool(TurnFlow.on_start(state, cards, rng, rec.record)).is_true()
			assert_int(Scoring.uses_left(quorum, state, cards)).is_equal(left + 1)
			assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, kept, false)).is_true()
			assert_int(Scoring.uses_left(quorum, state, cards)).is_equal(left)
			assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, kept, false)).is_false()
			assert_int(Scoring.uses_left(quorum, state, cards)).is_equal(left)
		assert_int(rec.of_kind(PROMPTED).size()).is_equal(4)
		var spent: StubAbilities.Recorder = StubAbilities.recorder()
		assert_bool(TurnFlow.on_start(state, cards, rng, spent.record)).is_false()
		assert_array(spent.of_kind(FIRED)).is_empty()
		assert_str(_str_of(spent.of_kind(FIZZLED)[0], "reason")).is_equal(Abilities.REASON_SPENT)


## R6: `uses` 1 is enough for a whole firing: its second prompt still opens and its effect
## still lands, the use counted once.
func test_a_quorum_with_one_use_finishes_its_firing() -> void:
	var cards: MatchCards = _cards()
	var quorum: int = 4
	var state: MatchState = _limited_quorum_table(cards, quorum, 1, Abilities.SCOPE_MATCH)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var zone: int = Choice.Zone.OWN_BOARD
	var kept: Array[int] = [0, 1]
	assert_bool(TurnFlow.on_start(state, cards, rng, rec.record)).is_true()
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, kept, false)).is_true()
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, kept, false)).is_false()
	assert_int(Scoring.uses_left(quorum, state, cards)).is_equal(0)
	assert_array(_with_status(state, 0, Statuses.MUTED)).is_equal(Typed.ints([1]))
	assert_array(_with_status(state, 1, Statuses.MUTED)).is_equal(Typed.ints([OTHER + 2]))


## R6: a firing declined at its first prompt counts no use and has no effect. Quorum's prompts
## are not optional, so this answers the queue directly: the engine would refuse the decline.
func test_a_quorum_declined_at_its_first_prompt_counts_no_use() -> void:
	var cards: MatchCards = _cards()
	var quorum: int = 4
	var state: MatchState = _limited_quorum_table(cards, quorum, 2, Abilities.SCOPE_MATCH)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var none: Array[int] = []
	assert_bool(TurnFlow.on_start(state, cards, rng, rec.record)).is_true()
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, Choice.NO_ZONE, none, true)
	).is_false()
	assert_int(Scoring.uses_left(quorum, state, cards)).is_equal(2)
	assert_array(_with_status(state, 0, Statuses.MUTED)).is_empty()


func _prompt_seat(state: MatchState) -> int:
	var seat: int = state.prompt.get(Abilities.KEY_SEAT, -1)
	return seat


## The random bot, seeing `seat`'s view, answers the open prompt with a legal set.
func _assert_bot_answers(state: MatchState, cards: MatchCards, seat: int) -> void:
	var bot: RandomBot = RandomBot.new(SEED, cards)
	var view: SeatView = SeatView.build(state, seat, seat, cards)
	var action: EngineAction = bot.choose(view, null)
	assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
	assert_bool(Choice.is_valid_set(state.prompt, action.zone, action.indices)).is_true()


# --- Eclipse --------------------------------------------------------------------------


## Eclipse Silences an opposing card until end of turn: no triggers, no Score; both halves
## end at turn end.
func test_eclipse_silences_an_opposing_card() -> void:
	var cards: MatchCards = _cards()
	var eclipse: int = 4
	_put(cards, Typed.ints([eclipse]), "di10")
	var scout: int = OTHER + StubAbilities.SCOUT
	var state: MatchState = StubAbilities.table(Typed.ints([eclipse]), false)
	StubAbilities.put_row(state, 1, Typed.ints([scout]), false)
	state.seats[1].deck.assign(Typed.ints([OTHER + 8]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_bool(Statuses.has(state, scout, Statuses.SILENCED)).is_true()
	assert_array(rec.cards_of(FIRED)).is_equal(Typed.ints([eclipse]))
	assert_array(rec.cards_of(SCORED)).is_equal(Typed.ints([eclipse]))
	assert_array(state.seats[1].hand).is_empty()
	assert_array(Statuses.badges(state, cards, scout)).contains(["Silenced"])
	TurnFlow.end_statuses(state, _spare.record)
	assert_bool(Statuses.has(state, scout, Statuses.MUTED)).is_false()
	assert_bool(Statuses.has(state, scout, Statuses.SQUELCHED)).is_false()


## Eclipse Flags: against a card that cannot be Muted (Ward) it Squelches only (C24), and
## that lone Squelch wakes On squelch.
func test_eclipse_against_ward_squelches_only() -> void:
	var cards: MatchCards = _cards()
	var eclipse: int = 4
	_put(cards, Typed.ints([eclipse]), "di10")
	var goat: int = OTHER + StubAbilities.SCAPEGOAT
	var state: MatchState = StubAbilities.table(Typed.ints([eclipse]), false)
	StubAbilities.put_row(state, 1, Typed.ints([goat]), true)
	var cease: Dictionary = Statuses.cessation(Statuses.CEASE_TURN)
	Statuses.protect_seat(state, 1, Statuses.MUTED, cease)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_bool(Statuses.has(state, goat, Statuses.MUTED)).is_false()
	assert_array(rec.cards_of(FIRED)).is_equal(Typed.ints([eclipse, goat]))
	assert_str(Statuses.exit_mark_of(state, goat)).is_equal(Statuses.CONDEMNED)
