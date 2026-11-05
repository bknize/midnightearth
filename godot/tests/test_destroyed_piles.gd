class_name TestDestroyedPiles
extends GdUnitTestSuite
## Destroyed piles and recovery (DC-07 T04; R16-R21, plan P3, P6, P12, C12): the turn-end
## clear into the seat's destroyed pile and the round-end burn of the piles, the
## BOTH_DESTROYED zone (own pile in order, then the opponent's), the recover_destroyed verb
## (printed stats, the hand cap's burn, a card destroyed this turn not offered) and a
## recovered opponent card committing and scoring for its new controller until round start
## returns it to its origin's deck. The views and the redaction are in
## test_seat_view_piles.gd.
##
## No shipped card recovers yet, so the fixture's c02 (cost 1, flat 2, vanilla) is given an
## on-reveal recover_destroyed in memory, as test_destroyed.gd builds its watcher. Walk
## cases build MatchStates directly; engine cases play seed 1 and set rows and piles by hand
## (the fixture shortcut of test_destroyed.gd). Instance id = seat * DECK_SIZE + index.

const SEED: int = 1
const MAX_STEPS: int = 100
const MAX_PASSES: int = 60

# Definition indices in the fixture card list.
const C02_RECOVER: int = 1
const C03: int = 2
const C04: int = 3
const C08: int = 7
const C18: int = 17
const C19_DESTROY: int = 18

const PUBLIC: int = MatchEvent.PUBLIC
const BOTH_DESTROYED: int = Choice.Zone.BOTH_DESTROYED
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.EFFECT_FIRED
const REQUESTED: int = MatchEvent.Kind.CHOICE_REQUESTED
const MADE: int = MatchEvent.Kind.CHOICE_MADE
const DESTROYED: int = MatchEvent.Kind.CARD_DESTROYED
const CLEARED: int = MatchEvent.Kind.DESTROYED_CLEARED
const RECOVERED: int = MatchEvent.Kind.CARD_RECOVERED
const BURNED: int = MatchEvent.Kind.CARD_BURNED

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


## The fixture pool with c02 given an on-reveal recover_destroyed (in-memory JSON).
func _db() -> CardDb:
	if _cached_db != null:
		return _cached_db
	var text: String = FileAccess.get_file_as_string(FixtureDecks.CARDS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	var entry: Dictionary = entries[C02_RECOVER]
	entry["effect"] = {
		"trigger": "on_reveal",
		"verb": "recover_destroyed",
		"amount": 0,
		"text": "Put a card from either destroyed pile into your hand.",
	}
	_cached_db = CardDb.from_json(JSON.stringify(root))
	return _cached_db


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


## A state with these rows (seat 0, seat 1), nothing revealed, `first` committing first.
func _state(row_0: Array[int], row_1: Array[int], first: int) -> MatchState:
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = first
	state.seats[0].board.assign(row_0)
	state.seats[1].board.assign(row_1)
	return state


## Puts `card` at the end of `seat`'s destroyed pile, its identity public when `known`.
func _pile(state: MatchState, seat: int, card: int, known: bool) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.deck.erase(card)
	piles.hand.erase(card)
	piles.burned.erase(card)
	piles.destroyed.append(card)
	if known:
		piles.destroyed_known[card] = true


## Runs one live walk on `state` from begin() to its end or its first prompt; true on a
## prompt.
func _walk(state: MatchState, rng: MatchRng, recorder: Recorder) -> bool:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		if ScoreWalk.step(state, _defs(), rng, recorder.record, null):
			return true
		guard += 1
	return false


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


func _engine() -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_bool(engine.start().ok).is_true()
	return engine


func _pass(engine: MatchEngine) -> ApplyResult:
	return engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))


## Passes until the engine's turn is `turn` (or later).
func _pass_to_turn(engine: MatchEngine, turn: int) -> void:
	var guard: int = 0
	while engine.energy() < turn and guard < MAX_PASSES:
		assert_bool(_pass(engine).ok).is_true()
		guard += 1


## Sets `seat`'s row of a started engine to `row`, taking the cards out of its other piles,
## and leaves the hand two short of the cap (spare cards go to the deck's end).
func _place_row(engine: MatchEngine, seat: int, row: Array[int]) -> void:
	var piles: MatchState.SeatPiles = engine._state.seats[seat]
	for card: int in row:
		piles.deck.erase(card)
		piles.hand.erase(card)
		piles.burned.erase(card)
	while piles.hand.size() > MatchRules.HAND_CAP - 2:
		var spare: int = piles.hand[0]
		piles.hand.remove_at(0)
		piles.deck.append(spare)
	piles.board.assign(row)


## Every card id of `seat`'s deck and hand, ascending.
func _deck_and_hand(state: MatchState, seat: int) -> Array[int]:
	var out: Array[int] = []
	out.append_array(state.seats[seat].deck)
	out.append_array(state.seats[seat].hand)
	out.sort()
	return out


## The origin ids of `seat`'s deck, ascending.
func _origin_ids(seat: int) -> Array[int]:
	var out: Array[int] = []
	for index: int in range(MatchRules.DECK_SIZE):
		out.append(_id(seat, index))
	return out


# --- The piles (R16, R17, P6) ---------------------------------------------------------


## R16, R17: a card destroyed face up is in its seat's destroyed pile after turn end, known,
## and not burned; one destroyed face down in the round's last turn joins the pile at that
## turn's end; at round end both piles empty into the burn piles, in pile order. Seat 0 is
## one round from the match (wins 3), so the round end ends it and the table stays.
func test_a_destroyed_card_is_piled_at_turn_end_and_burned_at_round_end() -> void:
	var engine: MatchEngine = _engine()
	_pass_to_turn(engine, 6)
	var state: MatchState = engine._state
	var scorer: int = _id(0, C18)
	var first: int = _id(1, C04)
	_place_row(engine, 0, _typed([scorer]))
	_place_row(engine, 1, _typed([first]))
	state.seats[0].revealed[scorer] = true
	state.seats[1].revealed[first] = true
	state.card_state_for(first).destroyed = true
	assert_bool(_pass(engine).ok).is_true()
	var turn_six: ApplyResult = _pass(engine)
	assert_bool(turn_six.ok).is_true()
	var cleared: Array[MatchEvent] = _of_kind(turn_six.events, CLEARED)
	assert_int(cleared.size()).is_equal(1)
	var payload: Dictionary = {
		"seat": 1, "card": first, "slot": 0, "pile": true, "salvaged": false
	}
	_assert_event(cleared[0], CLEARED, payload, PUBLIC)
	var other: MatchState.SeatPiles = state.seats[1]
	assert_int(engine.energy()).is_equal(7)
	assert_array(other.destroyed).is_equal(_typed([first]))
	assert_bool(other.is_destroyed_known(first)).is_true()
	assert_bool(other.burned.has(first)).is_false()
	assert_array(other.board).is_empty()
	assert_int(state.controller_of(first)).is_equal(1)
	# The last turn: a face-down card destroyed on seat 1's row, and seat 0 one win away.
	var second: int = _id(1, C08)
	other.deck.erase(second)
	other.hand.erase(second)
	other.burned.erase(second)
	other.board.append(second)
	state.card_state_for(second).destroyed = true
	state.wins[0] = MatchRules.WINS_TO_TAKE - 1
	assert_bool(_pass(engine).ok).is_true()
	var last: ApplyResult = _pass(engine)
	assert_bool(last.ok).is_true()
	assert_bool(engine.is_over()).is_true()
	var last_cleared: Array[MatchEvent] = _of_kind(last.events, CLEARED)
	assert_int(last_cleared.size()).is_equal(1)
	assert_int(_payload_int(last_cleared[0], "card")).is_equal(second)
	# Round end: the piles are burned, the first card before the second.
	for piles: MatchState.SeatPiles in state.seats:
		assert_array(piles.destroyed).is_empty()
		assert_array(piles.destroyed_known_ids()).is_empty()
	assert_bool(other.burned.has(first)).is_true()
	assert_bool(other.burned.has(second)).is_true()
	assert_int(other.burned.find(first)).is_less(other.burned.find(second))
	var full: Dictionary = engine.full_state()
	var piles_dict: Array = full["destroyed"]
	assert_array(piles_dict).is_equal([[], []])


## Round start empties the piles too (a match that goes on), and the full state carries the
## piles and their public ids, deep-copied by duplicate().
func test_piles_are_in_the_full_state_and_copied() -> void:
	var state: MatchState = _state(_none(), _none(), 0)
	_pile(state, 0, _id(0, C04), true)
	_pile(state, 1, _id(1, C03), false)
	_pile(state, 1, _id(1, C04), true)
	var full: Dictionary = state.to_dict()
	assert_array(full["destroyed"]).is_equal([[_id(0, C04)], [_id(1, C03), _id(1, C04)]])
	assert_array(full["destroyed_known"]).is_equal([[_id(0, C04)], [_id(1, C04)]])
	var copy: MatchState = state.duplicate()
	assert_dict(copy.to_dict()).is_equal(full)
	copy.seats[1].destroyed.clear()
	copy.seats[1].destroyed_known.clear()
	assert_dict(state.to_dict()).is_equal(full)


## C12, P3: the controller is the seat whose piles hold the card, the face-down commit
## being the first committer's; -1 when no pile does.
func test_controller_of_follows_the_piles_not_the_origin() -> void:
	var state: MatchState = _state(_typed([_id(1, C03)]), _none(), 1)
	state.seats[0].hand.append(_id(1, C04))
	state.seats[1].deck.append(_id(0, C04))
	state.seats[0].burned.append(_id(1, C08))
	_pile(state, 1, _id(0, C08), false)
	state.pending.append(_id(0, C18))
	assert_int(state.controller_of(_id(1, C03))).is_equal(0)
	assert_int(state.controller_of(_id(1, C04))).is_equal(0)
	assert_int(state.controller_of(_id(0, C04))).is_equal(1)
	assert_int(state.controller_of(_id(1, C08))).is_equal(0)
	assert_int(state.controller_of(_id(0, C08))).is_equal(1)
	assert_int(state.controller_of(_id(0, C18))).is_equal(1)
	assert_int(state.controller_of(_id(0, C19_DESTROY))).is_equal(-1)


# --- The prompt (R19, R21, P12) -------------------------------------------------------


## R19, P12: the prompt lists the chooser's own pile in pile order, then the opponent's;
## every position is offered, and each maps back to its pile and position.
func test_the_prompt_offers_own_then_opponent_positions() -> void:
	var source: int = _id(0, C02_RECOVER)
	var state: MatchState = _state(_typed([source]), _none(), 0)
	var own_known: int = _id(0, C04)
	var own_hidden: int = _id(0, C08)
	var their_hidden: int = _id(1, C03)
	var their_known: int = _id(1, C04)
	_pile(state, 0, own_known, true)
	_pile(state, 0, own_hidden, false)
	_pile(state, 1, their_hidden, false)
	_pile(state, 1, their_known, true)
	var recorder: Recorder = Recorder.new()
	assert_bool(_walk(state, MatchRng.new(SEED), recorder)).is_true()
	assert_array(_kinds(recorder.events)).is_equal(_typed([REVEALED, FIRED, REQUESTED]))
	var requested: Dictionary = recorder.events[2].payload
	var zone_name: String = requested["zone"]
	assert_str(zone_name).is_equal("both_destroyed")
	assert_array(requested["options"]).is_equal([0, 1, 2, 3])
	assert_int(recorder.events[2].owner_seat).is_equal(PUBLIC)
	var zone: int = state.prompt[Choice.KEY_ZONE]
	assert_int(zone).is_equal(BOTH_DESTROYED)
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 1, 2, 3]))
	var listed: Array[int] = [own_known, own_hidden, their_hidden, their_known]
	assert_array(Choice.zone_cards(state, 0, BOTH_DESTROYED)).is_equal(listed)
	var seats: Array[int] = []
	var positions: Array[int] = []
	for index: int in range(4):
		seats.append(Choice.seat_at(state, 0, BOTH_DESTROYED, index))
		positions.append(Choice.local_index(state, 0, BOTH_DESTROYED, index))
	assert_array(seats).is_equal(_typed([0, 0, 1, 1]))
	assert_array(positions).is_equal(_typed([0, 1, 0, 1]))
	assert_int(Choice.seat_at(state, 0, BOTH_DESTROYED, 4)).is_equal(-1)
	assert_int(Choice.resolve(state, 0, BOTH_DESTROYED, 4)).is_equal(-1)
	# Relative to the other seat, its own pile comes first.
	var mirrored: Array[int] = [their_hidden, their_known, own_known, own_hidden]
	assert_array(Choice.zone_cards(state, 1, BOTH_DESTROYED)).is_equal(mirrored)
	# Answering with the opponent's second position takes that card from that pile.
	var made: Array[MatchEvent] = EffectResolver.answer(state, _defs(), 3)
	assert_array(_kinds(made)).is_equal(_typed([MADE, RECOVERED]))
	var recovered: Dictionary = {"seat": 0, "card": their_known, "from_seat": 1, "position": 1}
	_assert_event(made[1], RECOVERED, recovered, PUBLIC)
	assert_array(state.seats[1].destroyed).is_equal(_typed([their_hidden]))
	assert_array(state.seats[0].hand).is_equal(_typed([their_known]))


## R21: a card destroyed in this walk is still on its row, not in a pile, so the recovery
## does not offer it: here the only pile card is the one option and is chosen at once.
func test_a_card_destroyed_this_turn_is_not_offered() -> void:
	var destroyer: int = _id(0, C19_DESTROY)
	var source: int = _id(0, C02_RECOVER)
	var victim: int = _id(1, C04)
	var piled: int = _id(1, C08)
	var state: MatchState = _state(_typed([destroyer, source]), _typed([victim]), 0)
	_pile(state, 1, piled, true)
	var recorder: Recorder = Recorder.new()
	assert_bool(_walk(state, MatchRng.new(SEED), recorder)).is_false()
	var destroyed: Array[MatchEvent] = _of_kind(recorder.events, DESTROYED)
	assert_int(destroyed.size()).is_equal(1)
	assert_int(_payload_int(destroyed[0], "card")).is_equal(victim)
	assert_array(_of_kind(recorder.events, REQUESTED)).is_empty()
	var made: Array[MatchEvent] = _of_kind(recorder.events, MADE)
	assert_int(made.size()).is_equal(1)
	var auto: bool = made[0].payload["auto"]
	assert_bool(auto).is_true()
	assert_int(_payload_int(made[0], "target")).is_equal(piled)
	assert_array(state.seats[0].hand).is_equal(_typed([piled]))
	# The victim stays on its row, marked, until turn end piles it.
	assert_array(state.seats[1].board).is_equal(_typed([victim]))
	assert_bool(state.is_destroyed(victim)).is_true()
	assert_array(state.seats[1].destroyed).is_empty()
	var found: Dictionary = Choice.eligible(state, 0, CardEffect.Verb.RECOVER_DESTROYED, source)
	assert_array(Choice.options_of(found)).is_empty()
	var cleared: Array[MatchEvent] = EffectResolver.clear_destroyed(state)
	assert_int(cleared.size()).is_equal(1)
	assert_array(Choice.zone_cards(state, 0, BOTH_DESTROYED)).is_equal(_typed([victim]))


## Empty piles: the recovery fizzles.
func test_recovering_with_both_piles_empty_fizzles() -> void:
	var source: int = _id(0, C02_RECOVER)
	var state: MatchState = _state(_typed([source]), _none(), 0)
	var recorder: Recorder = Recorder.new()
	assert_bool(_walk(state, null, recorder)).is_false()
	var fizzled: Array[MatchEvent] = _of_kind(recorder.events, MatchEvent.Kind.EFFECT_FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	var verb: String = fizzled[0].payload["verb"]
	assert_str(verb).is_equal("recover_destroyed")
	assert_array(state.seats[0].hand).is_empty()


# --- The recovered card (R19, R20, C12) -----------------------------------------------


## R19, R20, C12: seat 0 recovers seat 1's face-down-destroyed card through a real prompt.
## It enters seat 0's hand with printed stats; seat 0 commits it, it sits on seat 0's row
## and scores there for seat 0; at round start it is back in seat 1's deck (or opening
## hand), and every deck holds its origin's 20 ids again.
func test_a_recovered_opponent_card_plays_for_its_new_controller_until_round_start() -> void:
	var engine: MatchEngine = _engine()
	_pass_to_turn(engine, 3)
	var state: MatchState = engine._state
	var source: int = _id(0, C02_RECOVER)
	var own_wreck: int = _id(0, C04)
	var target: int = _id(1, C08)
	_place_row(engine, 0, _typed([source]))
	_place_row(engine, 1, _none())
	_pile(state, 0, own_wreck, true)
	_pile(state, 1, target, false)
	assert_bool(_pass(engine).ok).is_true()
	assert_bool(_pass(engine).ok).is_true()
	var prompt: Dictionary = engine.open_prompt()
	assert_dict(prompt).is_not_empty()
	var asked: int = prompt[EffectResolver.KEY_SEAT]
	assert_int(asked).is_equal(0)
	assert_array(Choice.options_of(prompt)).is_equal(_typed([0, 1]))
	# Position 1: the opponent's pile, position 0.
	var chosen: ApplyResult = engine.apply(EngineAction.choose(0, BOTH_DESTROYED, 1))
	assert_bool(chosen.ok).is_true()
	var recovered: Array[MatchEvent] = _of_kind(chosen.events, RECOVERED)
	assert_int(recovered.size()).is_equal(1)
	var payload: Dictionary = {"seat": 0, "card": target, "from_seat": 1, "position": 0}
	_assert_event(recovered[0], RECOVERED, payload, 0)
	assert_bool(state.seats[0].hand.has(target)).is_true()
	assert_bool(state.seats[1].holds(target)).is_false()
	assert_int(state.controller_of(target)).is_equal(0)
	assert_object(state.card_state(target)).is_null()
	assert_array(state.seats[0].destroyed).is_equal(_typed([own_wreck]))
	assert_array(state.seats[1].destroyed).is_empty()
	# Next turn seat 0 commits it; it scores on seat 0's row with its printed stats.
	var zero_first: bool = engine.awaited_seat() == 0
	if not zero_first:
		assert_bool(_pass(engine).ok).is_true()
	var commit: ApplyResult = engine.apply(EngineAction.commit(0, _typed([target])))
	assert_bool(commit.ok).is_true()
	var events: Array[MatchEvent] = commit.events
	if zero_first:
		# Seat 1 commits second, which runs the walk.
		var second: ApplyResult = _pass(engine)
		assert_bool(second.ok).is_true()
		events = second.events
	var def: CardDef = _defs().def_of(target)
	var scored: Array[MatchEvent] = []
	for event: MatchEvent in _of_kind(events, SCORED):
		if _payload_int(event, "card") == target:
			scored.append(event)
	assert_int(scored.size()).is_equal(1)
	assert_int(_payload_int(scored[0], "seat")).is_equal(0)
	assert_int(_payload_int(scored[0], "flat")).is_equal(def.flat)
	assert_int(_payload_int(scored[0], "times")).is_equal(MatchRules.MULT_ONE)
	assert_int(_payload_int(scored[0], "plus")).is_equal(0)
	assert_bool(state.seats[0].board.has(target)).is_true()
	assert_int(state.controller_of(target)).is_equal(0)
	# Round start returns it to its origin.
	var guard: int = 0
	while state.round_number == 1 and guard < MAX_PASSES:
		assert_bool(_pass(engine).ok).is_true()
		guard += 1
	assert_int(state.round_number).is_equal(2)
	assert_int(state.controller_of(target)).is_equal(1)
	assert_bool(state.seats[0].holds(target)).is_false()
	for seat: int in range(2):
		assert_array(_deck_and_hand(state, seat)).is_equal(_origin_ids(seat))
		assert_array(state.seats[seat].destroyed).is_empty()


## R19 (cycle 1 R12): at the hand cap the recovered card is burned, as a draw at the cap
## is: CARD_RECOVERED (it left the pile), then CARD_BURNED, both public for a known card;
## the hand is unchanged and the card is in the chooser's burn pile.
func test_recovering_at_the_hand_cap_burns_it() -> void:
	var source: int = _id(0, C02_RECOVER)
	var state: MatchState = _state(_typed([source]), _none(), 0)
	var hand: Array[int] = []
	for index: int in range(MatchRules.HAND_CAP):
		hand.append(_id(0, 10 + index))
	state.seats[0].hand.assign(hand)
	var target: int = _id(1, C08)
	_pile(state, 1, target, true)
	var recorder: Recorder = Recorder.new()
	assert_bool(_walk(state, null, recorder)).is_false()
	var expected: Array[int] = [REVEALED, FIRED, MADE, RECOVERED, BURNED, SCORED]
	assert_array(_kinds(recorder.events)).is_equal(expected)
	var recovered: Dictionary = {"seat": 0, "card": target, "from_seat": 1, "position": 0}
	_assert_event(recorder.events[3], RECOVERED, recovered, PUBLIC)
	_assert_event(recorder.events[4], BURNED, {"seat": 0, "card": target}, PUBLIC)
	assert_array(state.seats[0].hand).is_equal(hand)
	assert_array(state.seats[0].burned).is_equal(_typed([target]))
	assert_array(state.seats[1].destroyed).is_empty()
	assert_array(state.seats[1].destroyed_known_ids()).is_empty()


## A face-down-destroyed card burned at the cap stays private to the chooser.
func test_a_hidden_card_burned_at_the_cap_stays_private() -> void:
	var source: int = _id(0, C02_RECOVER)
	var state: MatchState = _state(_typed([source]), _none(), 0)
	for index: int in range(MatchRules.HAND_CAP):
		state.seats[0].hand.append(_id(0, 10 + index))
	var target: int = _id(0, C08)
	_pile(state, 0, target, false)
	var recorder: Recorder = Recorder.new()
	assert_bool(_walk(state, null, recorder)).is_false()
	var recovered: Array[MatchEvent] = _of_kind(recorder.events, RECOVERED)
	var burned: Array[MatchEvent] = _of_kind(recorder.events, BURNED)
	assert_int(recovered.size()).is_equal(1)
	assert_int(burned.size()).is_equal(1)
	assert_int(recovered[0].owner_seat).is_equal(0)
	assert_int(burned[0].owner_seat).is_equal(0)
	assert_int(_payload_int(burned[0].redacted_for(1), "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_array(state.seats[0].burned).is_equal(_typed([target]))


## Records what a walk sends to its sink, with each event's owner.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
