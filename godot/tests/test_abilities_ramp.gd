class_name TestAbilitiesRamp
extends GdUnitTestSuite
## The Ramp card abilities (DC-13 T06; cycle 9 plan P3 verb table, P7 growth with caps;
## canon [[rules/cards-v2]] section 2.6): Memory that follows a card through the Pile and a
## Deck (Whisper, Rain), Mult growth to its cap (Sapling, Graft), Energy this Turn (Dynamo),
## Cost reductions with floor 0 (Tinker, Layaway) and the Turn-7 Cost (Colossus), the Pass
## check (Idler) and the free first card (Lantern). Each case puts the shipped card's
## definition on a stub deck instance (StubAbilities.replace_def); seat 1's
## instances add DECK_SIZE.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const GUARD: int = 60
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const STATS: int = MatchEvent.Kind.STATS_CHANGED

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


## Stub-deck definitions with the stub Crew (Tallyman, Void, Engineer): none of them acts on
## a reveal, a Score or a Commit, so the cases count the card abilities alone (Ramp's
## Navigator and Captain grow Scoring cards since DC-13 T07). Budgets are compared as
## deltas, so Engineer's +1 from Turn 3 cancels out.
func _cards() -> MatchCards:
	return StubAbilities.defs()


## Gives `instances` the shipped card `id`.
func _put(cards: MatchCards, instances: Array[int], id: String) -> void:
	var def: CardDef = _db().card_by_id(id)
	assert_object(def).is_not_null()
	assert_bool(StubAbilities.give(cards, instances, def)).is_true()


## Wakes `moment` for `subjects` (a seat event of `seat` when empty) and drains it at
## `step`; true when it paused.
func _fire(
	state: MatchState,
	cards: MatchCards,
	moment: String,
	subjects: Array[int],
	rec: StubAbilities.Recorder,
	step: String = "D2",
	seat: int = -1
) -> bool:
	TriggerQueue.wake(state, cards, moment, subjects, seat)
	return TriggerQueue.drain(state, cards, MatchRng.new(SEED), rec.record, step, seat)


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


func _cost(state: MatchState, cards: MatchCards, card: int) -> int:
	return Scoring.effective_cost(card, state, cards)


# --- Whisper, Sapling, Rain -----------------------------------------------------------


## Whisper's On reveal gives it Power +1 for the match (Memory): it Scores 2, keeps it in
## the Pile, through a Pile shuffled into the Deck (as Dredger does) and a redraw, and a
## second reveal grows it again.
func test_whisper_power_for_the_match_survives_the_pile_and_a_shuffle() -> void:
	var cards: MatchCards = _cards()
	var whisper: int = 0
	_put(cards, _typed([whisper]), "ra01")
	var state: MatchState = StubAbilities.table(_typed([whisper]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(_ints(rec, SCORED, "power")).is_equal(_typed([2]))
	var changed: Array[MatchEvent] = rec.of_kind(STATS)
	assert_int(changed.size()).is_equal(1)
	assert_bool(changed[0].payload["permanent"]).is_true()
	assert_bool(Statuses.take_from_row(state, 0, whisper, Callable())).is_true()
	TurnFlow.to_pile(state, cards, rec.record, whisper, TurnFlow.FROM_ROW, TurnFlow.REASON_DISCARD)
	assert_int(Scoring.stats(whisper, state, cards).power).is_equal(2)
	# The Pile shuffled into the Deck (Dredger), then drawn.
	var piles: MatchState.SeatPiles = state.seats[0]
	piles.deck.append_array(piles.pile)
	piles.pile.clear()
	MatchRng.new(SEED).shuffle_in_place(piles.deck)
	assert_bool(TurnFlow.draw(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	assert_array(piles.hand).is_equal(_typed([whisper]))
	var view: SeatView = SeatView.build(state, 0, -1, cards)
	var entry: Dictionary = view.own_hand_row[0]
	assert_int(entry["power"]).is_equal(2)
	assert_bool(entry["grown"]).is_true()
	piles.hand.clear()
	StubAbilities.put_row(state, 0, _typed([whisper]), false)
	var again: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, again)
	assert_array(_ints(again, SCORED, "power")).is_equal(_typed([3]))


## Sapling's On score adds +0.25 to its Mult for the match: it Scores at ×1.25, ×1.50,
## ×1.75, then ×2.00 and stays there (the cap, P7), its Memory growing no further.
func test_sapling_grows_to_the_cap_of_two() -> void:
	var cards: MatchCards = _cards()
	var sapling: int = 0
	_put(cards, _typed([sapling]), "ra02")
	var state: MatchState = StubAbilities.table(_typed([sapling]), true)
	var values: Array[int] = []
	for _walk_number: int in range(6):
		var rec: StubAbilities.Recorder = StubAbilities.recorder()
		_walk(state, cards, rec)
		values.append_array(_ints(rec, SCORED, "bonus_value"))
	assert_array(values).is_equal(_typed([12500, 15000, 17500, 20000, 20000, 20000]))
	var kept: CardMemory = state.memory_of(sapling)
	assert_int(kept.mult_add_steps).is_equal(75)
	assert_int(kept.mult_cap).is_equal(200)
	assert_int(Scoring.stats(sapling, state, cards).mult()).is_equal(200)


## Rain gives every card in its Controller's hand Power +1 for the match, each with a
## STATS_CHANGED private to that seat (neutral stats for the other).
func test_rain_grows_every_hand_card_privately() -> void:
	var cards: MatchCards = _cards()
	var rain: int = 0
	_put(cards, _typed([rain]), "ra03")
	var state: MatchState = StubAbilities.table(_typed([rain]), false)
	var hand: Array[int] = [1, 8]
	state.seats[0].hand.assign(hand)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_int(Scoring.stats(1, state, cards).power).is_equal(3)
	assert_int(Scoring.stats(8, state, cards).power).is_equal(4)
	assert_int(Scoring.stats(rain, state, cards).power).is_equal(1)
	var changed: Array[MatchEvent] = rec.of_kind(STATS)
	assert_array(rec.cards_of(STATS)).is_equal(hand)
	for event: MatchEvent in changed:
		assert_int(event.owner_seat).is_equal(0)
		assert_bool(event.payload["permanent"]).is_true()
		var other: MatchEvent = event.redacted_for(1)
		assert_int(_int_of(other, "card")).is_equal(MatchEvent.HIDDEN_CARD)
		assert_int(_int_of(other, "power")).is_equal(0)


# --- Dynamo, Tinker, Layaway, Colossus ------------------------------------------------


## Dynamo's On start (revealed) adds +1 to its seat's Budget this Turn (ENERGY_GRANTED);
## the Turn's end takes it away; face down it does not fire.
func test_dynamo_adds_one_energy_on_the_turn_it_fires_only() -> void:
	var cards: MatchCards = _cards()
	var dynamo: int = 0
	_put(cards, _typed([dynamo, dynamo + 1]), "ra04")
	var state: MatchState = StubAbilities.table(_typed([dynamo, dynamo + 1]), true)
	assert_bool(state.seats[0].revealed.erase(dynamo + 1)).is_true()
	state.turn = 3
	var before: int = TurnFlow.budget(state, cards, 0)
	var other: int = TurnFlow.budget(state, cards, 1)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(state, cards, MatchRng.new(SEED), rec.record)).is_false()
	assert_int(TurnFlow.budget(state, cards, 0)).is_equal(before + 1)
	assert_int(TurnFlow.budget(state, cards, 1)).is_equal(other)
	var granted: Array[MatchEvent] = rec.of_kind(MatchEvent.Kind.ENERGY_GRANTED)
	assert_int(granted.size()).is_equal(1)
	assert_dict(granted[0].payload).is_equal({"seat": 0, "amount": 1, "source": dynamo})
	assert_int(granted[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	TurnFlow.settle_turn(state, rec.record)
	assert_int(TurnFlow.budget(state, cards, 0)).is_equal(before)


## Tinker's On reveal makes the card to its right cost 1 less for the match (Memory), to a
## floor of 0; the reduction stays with the card off the row.
func test_tinker_reduces_the_right_card_for_the_match_with_floor_0() -> void:
	var cards: MatchCards = _cards()
	var tinker: int = 0
	var pebble: int = StubAbilities.PEBBLE
	_put(cards, _typed([tinker]), "ra05")
	var state: MatchState = StubAbilities.table(_typed([tinker, pebble]), true)
	var costs: Array[int] = []
	for _reveal: int in range(3):
		var rec: StubAbilities.Recorder = StubAbilities.recorder()
		assert_bool(_fire(state, cards, "on_reveal", _typed([tinker]), rec, "D7")).is_false()
		costs.append(_cost(state, cards, pebble))
	assert_array(costs).is_equal(_typed([1, 0, 0]))
	assert_int(state.memory_of(pebble).cost_delta).is_equal(-3)
	assert_bool(Statuses.take_from_row(state, 0, pebble, Callable())).is_true()
	assert_int(_cost(state, cards, pebble)).is_equal(0)
	assert_int(_cost(state, cards, tinker)).is_equal(3)


## Layaway's On commit fires from its Controller's hand (publicly, C14; its Cost change stays
## private) at each of that seat's Commits: Cost 5, 4, ... to 0 and no lower.
func test_layaway_reduces_itself_from_the_hand_with_floor_0() -> void:
	var cards: MatchCards = _cards()
	var layaway: int = 0
	_put(cards, _typed([layaway]), "ra09")
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign(_typed([layaway]))
	var costs: Array[int] = []
	var rec: StubAbilities.Recorder = null
	for _commit: int in range(6):
		rec = StubAbilities.recorder()
		var none: Array[int] = []
		TurnFlow.accept_commit(state, cards, rec.record, 0, none, none)
		assert_bool(TurnFlow.on_commit(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
		costs.append(_cost(state, cards, layaway))
	assert_array(costs).is_equal(_typed([4, 3, 2, 1, 0, 0]))
	var fired: Array[MatchEvent] = rec.of_kind(FIRED)
	assert_int(fired.size()).is_equal(1)
	assert_int(fired[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	var changed: Array[MatchEvent] = rec.of_kind(STATS)
	assert_int(changed[0].owner_seat).is_equal(0)
	assert_int(_int_of(changed[0], "cost")).is_equal(0)
	# The other seat's Commit does not wake it.
	var other: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_commit(state, cards, MatchRng.new(SEED), other.record, 1)).is_false()
	assert_int(other.cards_of(FIRED).count(layaway)).is_equal(0)


## C14: a hand trigger is public. Seat 0 commits with a Layaway in hand: its TRIGGER_FIRED
## is public and says `from_hand`, and seat 1's copy names the card, its verb and moment.
func test_a_layaway_firing_from_the_hand_is_public_to_both_seats() -> void:
	var cards: MatchCards = _cards()
	var layaway: int = 0
	_put(cards, _typed([layaway]), "ra09")
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign(_typed([layaway]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var none: Array[int] = []
	TurnFlow.accept_commit(state, cards, rec.record, 0, none, none)
	assert_bool(TurnFlow.on_commit(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	var fired: Array[MatchEvent] = rec.of_kind(FIRED)
	assert_int(fired.size()).is_equal(1)
	assert_bool(fired[0].is_private()).is_false()
	var seen: MatchEvent = fired[0].redacted_for(1)
	assert_int(_int_of(seen, "card")).is_equal(layaway)
	assert_str(_str_of(seen, "verb")).is_equal("cost_down_self")
	assert_str(_str_of(seen, "moment")).is_equal("on_commit")
	var from_hand: bool = seen.payload.get(MatchEvent.KEY_FROM_HAND, false)
	assert_bool(from_hand).is_true()


## A trigger whose card is in its Deck when it comes up stays private (none in milestone A:
## a queued Layaway is put into the Deck before the drain): seat 1's copy hides the card and
## carries no `from_hand`.
func test_a_trigger_of_a_deck_card_stays_private() -> void:
	var cards: MatchCards = _cards()
	var layaway: int = 0
	_put(cards, _typed([layaway]), "ra09")
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign(_typed([layaway]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var none: Array[int] = []
	TriggerQueue.wake(state, cards, "on_commit", none, 0)
	state.seats[0].hand.clear()
	state.seats[0].deck.append(layaway)
	assert_bool(TriggerQueue.drain(state, cards, MatchRng.new(SEED), rec.record, "D3", 0)).is_false()
	var events: Array[MatchEvent] = rec.of_kind(FIRED)
	events.append_array(rec.of_kind(FIZZLED))
	assert_int(events.size()).is_equal(1)
	assert_int(events[0].owner_seat).is_equal(0)
	assert_int(_int_of(events[0], "card")).is_equal(layaway)
	var seen: MatchEvent = events[0].redacted_for(1)
	assert_int(_int_of(seen, "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_bool(seen.payload.has(MatchEvent.KEY_FROM_HAND)).is_false()


## Colossus costs 12, and 7 on Turn 7; a Cost change applies after (Tinker's -1: 6).
func test_colossus_costs_7_on_turn_7_and_12_on_turn_6() -> void:
	var cards: MatchCards = _cards()
	var colossus: int = 0
	_put(cards, _typed([colossus]), "ra10")
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign(_typed([colossus]))
	state.turn = 6
	assert_int(_cost(state, cards, colossus)).is_equal(12)
	state.turn = 7
	assert_int(_cost(state, cards, colossus)).is_equal(7)
	state.memory_for(colossus).cost_delta = -1
	assert_int(_cost(state, cards, colossus)).is_equal(6)
	state.turn = 6
	assert_int(_cost(state, cards, colossus)).is_equal(11)


# --- Idler and Lantern ----------------------------------------------------------------


## Idler fires on its seat's Pass (Power +2 and Add +0.5 until end of turn) and fizzles
## `no_target` on a one-card Commit.
func test_idler_fires_on_a_pass_and_not_on_a_one_card_commit() -> void:
	var cards: MatchCards = _cards()
	var idler: int = 0
	_put(cards, _typed([idler]), "ra06")
	var state: MatchState = StubAbilities.table(_typed([idler]), true)
	state.seats[0].hand.assign(_typed([1]))
	var none: Array[int] = []
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	TurnFlow.accept_commit(state, cards, rec.record, 0, none, none)
	assert_bool(TurnFlow.on_commit(state, cards, MatchRng.new(SEED), rec.record, 0)).is_false()
	assert_array(rec.cards_of(FIRED)).is_equal(_typed([idler]))
	var grown: Scoring.Stats = Scoring.stats(idler, state, cards)
	assert_int(grown.power).is_equal(4)
	assert_int(grown.add()).is_equal(50)
	assert_int(grown.bonus_value()).is_equal(15000)
	TurnFlow.end_statuses(state, Callable())
	var settled: Scoring.Stats = Scoring.stats(idler, state, cards)
	assert_int(settled.power).is_equal(2)
	assert_int(settled.add()).is_equal(0)
	# A one-card Commit: the trigger fizzles and nothing changes.
	var one: StubAbilities.Recorder = StubAbilities.recorder()
	TurnFlow.accept_commit(state, cards, one.record, 0, _typed([1]), _typed([1]))
	assert_int(state.committed_count[0]).is_equal(1)
	assert_bool(TurnFlow.on_commit(state, cards, MatchRng.new(SEED), one.record, 0)).is_false()
	assert_array(one.cards_of(FIRED)).is_empty()
	var fizzled: Array[MatchEvent] = one.of_kind(FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	assert_str(_str_of(fizzled[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)
	assert_int(Scoring.stats(idler, state, cards).power).is_equal(2)


## Lantern's On reveal makes its seat's first card next Turn free: not this Turn, then the
## next Turn's first Commit of a card uses it (Cost 0); a second Lantern's free card unused
## through a Pass ends at that Turn's end.
func test_lantern_free_first_ends_after_one_commit_or_at_the_next_turn_end() -> void:
	var cards: MatchCards = _cards()
	var lantern: int = 0
	var pebble: int = StubAbilities.PEBBLE
	_put(cards, _typed([lantern]), "ra07")
	var state: MatchState = StubAbilities.table(_typed([lantern]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_reveal", _typed([lantern]), rec, "D7")).is_false()
	assert_bool(state.energy.free_first[0]).is_false()
	assert_bool(state.energy.free_first_next[0]).is_true()
	TurnFlow.end_statuses(state, Callable())
	assert_bool(state.energy.free_first[0]).is_true()
	assert_bool(SeatView.build(state, 0, -1, cards).free_first).is_true()
	state.seats[0].hand.assign(_typed([pebble, pebble + 1]))
	TurnFlow.accept_commit(state, cards, rec.record, 0, _typed([pebble]), _typed([1]))
	assert_int(state.energy.spent[0]).is_equal(0)
	assert_bool(state.energy.free_first[0]).is_false()
	# A second Lantern; next Turn a Pass keeps the free card, and that Turn's end ends it.
	assert_bool(_fire(state, cards, "on_reveal", _typed([lantern]), rec, "D7")).is_false()
	TurnFlow.end_statuses(state, Callable())
	assert_bool(state.energy.free_first[0]).is_true()
	var none: Array[int] = []
	TurnFlow.accept_commit(state, cards, rec.record, 0, none, none)
	assert_bool(state.energy.free_first[0]).is_true()
	TurnFlow.end_statuses(state, Callable())
	assert_bool(state.energy.free_first[0]).is_false()
	TurnFlow.accept_commit(state, cards, rec.record, 0, _typed([pebble + 1]), _typed([2]))
	assert_int(state.energy.spent[0]).is_equal(_cost(state, cards, pebble + 1))


# --- Graft ----------------------------------------------------------------------------


## Graft's On score multiplies the Mult of the card to its right by ×1.2 for the match:
## Wisp ×1.25 reads 1.50, 1.80, 2.16, then 2.50 (the cap) and stays; the card on its left
## is untouched.
func test_graft_multiplies_the_right_cards_mult_to_the_cap() -> void:
	var cards: MatchCards = _cards()
	var graft: int = 0
	var left: int = StubAbilities.WISP + 1
	var wisp: int = StubAbilities.WISP
	_put(cards, _typed([graft]), "ra08")
	var state: MatchState = StubAbilities.table(_typed([left, graft, wisp]), true)
	var mults: Array[int] = []
	for _score: int in range(5):
		var rec: StubAbilities.Recorder = StubAbilities.recorder()
		assert_bool(_fire(state, cards, "on_score", _typed([graft]), rec, "D8")).is_false()
		mults.append(Scoring.stats(wisp, state, cards).mult())
	assert_array(mults).is_equal(_typed([150, 180, 216, 250, 250]))
	assert_int(state.memory_of(wisp).mult_times_steps.size()).is_equal(4)
	assert_object(state.memory_of(left)).is_null()


## Graft fizzles `no_target` when the card to its right has no Mult, or when there is none.
func test_graft_fizzles_on_a_card_with_no_mult() -> void:
	var cards: MatchCards = _cards()
	var graft: int = 0
	var mote: int = 1
	_put(cards, _typed([graft]), "ra08")
	var state: MatchState = StubAbilities.table(_typed([graft, mote]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(state, cards, "on_score", _typed([graft]), rec, "D8")).is_false()
	var fizzled: Array[MatchEvent] = rec.of_kind(FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	assert_str(_str_of(fizzled[0], "verb")).is_equal("grow_right_mult_times")
	assert_str(_str_of(fizzled[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)
	assert_object(state.memory_of(mote)).is_null()
	var last: MatchState = StubAbilities.table(_typed([mote, graft]), true)
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(_fire(last, cards, "on_score", _typed([graft]), none, "D8")).is_false()
	assert_int(none.of_kind(FIZZLED).size()).is_equal(1)
