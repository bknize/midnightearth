class_name TestDestroyed
extends GdUnitTestSuite
## Destroyed as a card state (DC-06 T02; R12-R19, plan P4-P6): a destroyed card's flip
## (a CARD_REVEALED with `destroyed` and nothing after it: no effect, no watcher, no bonus-0
## spend, no score), the random destroy picking among live cards only and fizzling on a row
## of destroyed cards without touching the stream, a destroyed carry card carrying nothing,
## the turn end (returns, then the destroyed cards to the burn pile, then energy), and the
## hidden information of a destroyed face-down card in its events and the views (R20, R21).
## The in-place mark itself and the clear of a revealed card are in test_effects.gd.
##
## Walk cases build MatchStates directly; the turn-end case plays seed 1 to turn 4 and sets
## the rows by hand (a fixture shortcut, as test_effects.gd's _plant). Instance id = seat *
## DECK_SIZE + index.

const SEED: int = 1
## Seeds tried for the destroy's pick.
const PICK_SEEDS: int = 20
const MAX_STEPS: int = 100

# Definition indices in the default card list (test_effects.gd checks the table).
const C01_DRAW: int = 0
const C02: int = 1
const C03: int = 2
const C04: int = 3
const C05_CARRY: int = 4
const C07: int = 6
const C11: int = 10
const C19_DESTROY: int = 18

const PUBLIC: int = MatchEvent.PUBLIC
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.EFFECT_FIRED
const FIZZLED: int = MatchEvent.Kind.EFFECT_FIZZLED
const DRAWN: int = MatchEvent.Kind.CARD_DRAWN
const STATS: int = MatchEvent.Kind.STATS_CHANGED
const DESTROYED: int = MatchEvent.Kind.CARD_DESTROYED
const CLEARED: int = MatchEvent.Kind.DESTROYED_CLEARED
const RETURNED: int = MatchEvent.Kind.CARD_RETURNED
const CARRIED: int = MatchEvent.Kind.ENERGY_CARRIED
const TURN_ENDED: int = MatchEvent.Kind.TURN_ENDED

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null
var _cached_watcher_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## The fixture-vs-fixture definitions over _db() (DC-07 T02), for ScoreWalk,
## EffectResolver and SeatView.
func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


## The fixture card list with c02 given an on-opponent-reveal "draw 1" (in-memory JSON, as
## test_effects.gd: no deck card uses the trigger).
func _watcher_db() -> CardDb:
	if _cached_watcher_db != null:
		return _cached_watcher_db
	var text: String = FileAccess.get_file_as_string(FixtureDecks.CARDS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	var entry: Dictionary = entries[C02]
	entry["effect"] = {
		"trigger": "on_opponent_reveal",
		"verb": "draw",
		"amount": 1,
		"text": "When your opponent reveals a card, draw a card.",
	}
	_cached_watcher_db = CardDb.from_json(JSON.stringify(root))
	return _cached_watcher_db


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


func _reveal(state: MatchState, seat: int, cards: Array[int]) -> void:
	for card: int in cards:
		state.seats[seat].revealed[card] = true


## Runs one live walk on `state` from begin() to its end, recording the events.
func _walk(state: MatchState, cards: MatchCards, rng: MatchRng, recorder: Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < MAX_STEPS:
		var paused: bool = ScoreWalk.step(state, cards, rng, recorder.record, null)
		assert_bool(paused).is_false()
		guard += 1


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


## The `card` of every event of `kind`, in order.
func _cards_of(events: Array[MatchEvent], kind: int) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in _of_kind(events, kind):
		out.append(_payload_int(event, "card"))
	return out


func _assert_event(event: MatchEvent, kind: int, payload: Dictionary, owner: int) -> void:
	var expected: Dictionary = {"kind": kind, "owner": owner, "payload": payload}
	assert_dict(event.to_dict()).is_equal(expected)


func _fired(seat: int, card: int, verb: String, trigger: String) -> Dictionary:
	return {"seat": seat, "card": card, "verb": verb, "trigger": trigger}


func _pass(engine: MatchEngine) -> ApplyResult:
	return engine.apply(EngineAction.commit(engine.awaited_seat(), _none()))


## Sets `seat`'s row of a started engine to `row`, taking the cards out of its deck, hand
## and burn pile, and leaves the hand two short of the cap (spare cards go to the deck's
## end) so a return and the next turn's draw both fit.
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


# --- The destroyed card's flip (R13, R14) ---------------------------------------------


## R14: a destroyed face-down card flips with CARD_REVEALED {..., destroyed: true} and
## nothing more: its own on-reveal draw does not fire, the other seat's on-opponent-reveal
## watcher does not fire, the seat's bonus-0 mark is not spent (it waits for the next live
## reveal) and nothing scores.
func test_a_destroyed_card_flips_with_no_effect_no_mark_spent_and_no_score() -> void:
	var cards: MatchCards = FixtureDecks.defs(_watcher_db())
	var wreck: int = _id(0, C01_DRAW)
	var live: int = _id(0, C03)
	var watcher: int = _id(1, C02)
	var state: MatchState = _state(_typed([wreck, live]), _typed([watcher]), 0)
	_reveal(state, 1, _typed([watcher]))
	state.card_state_for(wreck).destroyed = true
	state.bonus_zero_pending[0] = true
	var own_deck: Array[int] = [_id(0, C11)]
	state.seats[0].deck.assign(own_deck)
	state.seats[1].deck.assign([_id(1, C11)])
	var recorder: Recorder = Recorder.new()
	_walk(state, cards, null, recorder)
	var events: Array[MatchEvent] = recorder.events
	# 0-0 the wreck flips; 1-0 the watcher scores; 0-1 the live card flips, takes the mark,
	# wakes the watcher and scores.
	var expected: Array[int] = [REVEALED, SCORED, REVEALED, STATS, FIRED, DRAWN, SCORED]
	assert_array(_kinds(events)).is_equal(expected)
	var stats: Vector2i = ScoreWalk.effective(wreck, state, cards)
	var flipped: Dictionary = {
		"seat": 0,
		"card": wreck,
		"def_id": cards.def_of(wreck).id,
		"slot": 0,
		"flat": stats.x,
		"bonus": stats.y,
		"order": 0,
		"destroyed": true,
	}
	_assert_event(events[0], REVEALED, flipped, PUBLIC)
	var live_flag: bool = events[2].payload["destroyed"]
	assert_bool(live_flag).is_false()
	# The mark went to the live card, not the wreck.
	assert_int(_payload_int(events[3], "card")).is_equal(live)
	assert_bool(state.card_state(live).bonus_zero).is_true()
	assert_bool(state.card_state(wreck).bonus_zero).is_false()
	assert_array(state.bonus_zero_pending).is_equal([false, false])
	# The watcher fired once, for the live card only; the wreck's own draw never fired.
	assert_array(_cards_of(events, FIRED)).is_equal(_typed([watcher]))
	assert_array(state.seats[0].hand).is_empty()
	assert_array(state.seats[0].deck).is_equal(own_deck)
	# No score for the wreck: seat 0 scores only c03 (1, 0 after the mark).
	assert_array(_cards_of(events, SCORED)).is_equal(_typed([watcher, live]))
	assert_int(state.scores[0]).is_equal(1)
	assert_bool(state.seats[0].is_revealed(wreck)).is_true()
	# A later walk passes the face-up wreck with no event at all.
	var later: Recorder = Recorder.new()
	_walk(state, cards, null, later)
	assert_bool(_cards_of(later.events, SCORED).has(wreck)).is_false()
	assert_bool(_cards_of(later.events, REVEALED).has(wreck)).is_false()
	assert_bool(_cards_of(later.events, FIRED).has(wreck)).is_false()


# --- The random destroy's targets (R16, R17) ------------------------------------------


## R16, R17: with only destroyed cards opposite, the destroy fizzles and the stream is
## untouched; the destroyed cards still flip when the cursor reaches them.
func test_destroy_with_only_destroyed_cards_opposite_fizzles() -> void:
	var card: int = _id(0, C19_DESTROY)
	var wrecks: Array[int] = [_id(1, C03), _id(1, C04)]
	var state: MatchState = _state(_typed([card]), wrecks, 0)
	for wreck: int in wrecks:
		state.card_state_for(wreck).destroyed = true
	var rng: MatchRng = MatchRng.new(SEED)
	var stream: int = rng.state
	var recorder: Recorder = Recorder.new()
	_walk(state, _defs(), rng, recorder)
	var events: Array[MatchEvent] = recorder.events
	var expected: Array[int] = [REVEALED, FIRED, FIZZLED, SCORED, REVEALED, REVEALED]
	assert_array(_kinds(events)).is_equal(expected)
	_assert_event(
		events[2], FIZZLED, {"seat": 0, "card": card, "verb": "destroy_random_opponent"}, PUBLIC
	)
	assert_int(rng.state).is_equal(stream)
	assert_array(_of_kind(events, DESTROYED)).is_empty()
	assert_array(state.seats[1].board).is_equal(wrecks)


## R16: the destroy picks among the live cards only, so a live card beside a destroyed one
## is the one picked whatever the stream, and the event names its row slot.
func test_destroy_skips_a_card_already_destroyed() -> void:
	var source: int = _id(0, C19_DESTROY)
	var wreck: int = _id(1, C03)
	var target: int = _id(1, C04)
	for match_seed: int in range(1, PICK_SEEDS + 1):
		var state: MatchState = _state(_typed([source]), _typed([wreck, target]), 0)
		state.card_state_for(wreck).destroyed = true
		var recorder: Recorder = Recorder.new()
		_walk(state, _defs(), MatchRng.new(match_seed), recorder)
		var destroyed: Array[MatchEvent] = _of_kind(recorder.events, DESTROYED)
		assert_int(destroyed.size()).is_equal(1)
		_assert_event(destroyed[0], DESTROYED, {"seat": 1, "card": target, "slot": 1}, 1)
		assert_int(state.scores[1]).is_equal(0)


# --- The energy carry (R15) -----------------------------------------------------------


## R15: a destroyed c05 carries nothing, even while still on its row.
func test_a_destroyed_carry_card_carries_nothing() -> void:
	var carrier: int = _id(0, C05_CARRY)
	var state: MatchState = _state(_typed([carrier]), _none(), 0)
	_reveal(state, 0, _typed([carrier]))
	state.turn = 4
	state.energy.carry[0] = 3
	state.card_state_for(carrier).destroyed = true
	assert_array(EffectResolver.settle_energy(state, _defs())).is_empty()
	assert_array(state.energy.carry).is_equal(_typed([0, 0]))
	# The same card live carries: budget 4 + 0 less 0 spent.
	state.card_state_for(carrier).destroyed = false
	var events: Array[MatchEvent] = EffectResolver.settle_energy(state, _defs())
	assert_array(_kinds(events)).is_equal(_typed([FIRED, CARRIED]))
	assert_array(state.energy.carry).is_equal(_typed([4, 0]))


# --- Turn end (R18, R19, R21, P6) -----------------------------------------------------


## P6: turn end resolves the returns, then clears the destroyed cards to their burn piles
## in row order per seat, then settles energy, then TURN_ENDED. A return-marked destroyed
## card is discarded, not returned (R19), and a destroyed carry card carries nothing (R15).
func test_turn_end_clears_destroyed_cards_after_returns_and_before_energy() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_bool(engine.start().ok).is_true()
	while engine.energy() < 4:
		assert_bool(_pass(engine).ok).is_true()
	var returned: int = _id(0, C03)
	var lost: int = _id(0, C04)
	var hidden: int = _id(0, C07)
	var carrier: int = _id(0, C05_CARRY)
	var gone: int = _id(1, C05_CARRY)
	_place_row(engine, 0, _typed([returned, lost, hidden, carrier]))
	_place_row(engine, 1, _typed([gone]))
	var state: MatchState = engine._state
	_reveal(state, 0, _typed([returned, lost, carrier]))
	_reveal(state, 1, _typed([gone]))
	state.card_state_for(returned).return_marked = true
	state.card_state_for(lost).return_marked = true
	for card: int in [lost, hidden, gone]:
		state.card_state_for(card).destroyed = true
	assert_bool(_pass(engine).ok).is_true()
	var result: ApplyResult = _pass(engine)
	assert_bool(result.ok).is_true()
	var events: Array[MatchEvent] = result.events
	# The walk flips the face-down wreck (so its clear is public) and scores no wreck.
	var flips: Array[MatchEvent] = _of_kind(events, REVEALED)
	assert_int(flips.size()).is_equal(1)
	assert_int(_payload_int(flips[0], "card")).is_equal(hidden)
	var flagged: bool = flips[0].payload["destroyed"]
	assert_bool(flagged).is_true()
	assert_array(_cards_of(events, SCORED)).is_equal(_typed([returned, carrier]))
	# Returns, then the clear in row order per seat, then energy, then TURN_ENDED.
	var kinds: Array[int] = _kinds(events)
	var at: int = kinds.find(RETURNED)
	assert_int(at).is_greater(0)
	var order: Array[int] = [RETURNED, CLEARED, CLEARED, CLEARED, FIRED, CARRIED, TURN_ENDED]
	assert_array(kinds.slice(at, at + order.size())).is_equal(order)
	_assert_event(events[at], RETURNED, {"seat": 0, "card": returned, "slot": 0}, PUBLIC)
	_assert_event(events[at + 1], CLEARED, {"seat": 0, "card": lost, "slot": 0}, PUBLIC)
	_assert_event(events[at + 2], CLEARED, {"seat": 0, "card": hidden, "slot": 0}, PUBLIC)
	_assert_event(events[at + 3], CLEARED, {"seat": 1, "card": gone, "slot": 0}, PUBLIC)
	_assert_event(events[at + 4], FIRED, _fired(0, carrier, "carry_energy", "ongoing"), PUBLIC)
	assert_int(_payload_int(events[at + 5], "seat")).is_equal(0)
	assert_array(_of_kind(events, CARRIED).slice(1)).is_empty()
	# Where everything went: the return to the hand, the wrecks to the burn piles.
	var own: MatchState.SeatPiles = state.seats[0]
	var other: MatchState.SeatPiles = state.seats[1]
	assert_bool(own.hand.has(returned)).is_true()
	assert_bool(own.hand.has(lost)).is_false()
	assert_bool(own.burned.has(lost)).is_true()
	assert_bool(own.burned.has(hidden)).is_true()
	assert_bool(other.burned.has(gone)).is_true()
	assert_array(own.board).is_equal(_typed([carrier]))
	assert_array(other.board).is_empty()
	for card: int in [returned, lost, hidden, gone]:
		assert_object(state.card_state(card)).is_null()
	assert_int(state.energy.carry[1]).is_equal(0)


## R21: a destroyed card the cursor never reached leaves at turn end with an event private
## to its seat: the other seat sees the seat and the slot, not the card.
func test_clearing_a_face_down_destroyed_card_is_private() -> void:
	var shown: int = _id(1, C03)
	var hidden: int = _id(1, C04)
	var state: MatchState = _state(_none(), _typed([shown, hidden]), 0)
	_reveal(state, 1, _typed([shown]))
	state.card_state_for(shown).destroyed = true
	state.card_state_for(hidden).destroyed = true
	var cleared: Array[MatchEvent] = EffectResolver.clear_destroyed(state)
	assert_int(cleared.size()).is_equal(2)
	_assert_event(cleared[0], CLEARED, {"seat": 1, "card": shown, "slot": 0}, PUBLIC)
	_assert_event(cleared[1], CLEARED, {"seat": 1, "card": hidden, "slot": 0}, 1)
	var seen: MatchEvent = cleared[1].redacted_for(0)
	assert_int(_payload_int(seen, "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_int(_payload_int(seen, "seat")).is_equal(1)
	assert_int(_payload_int(seen, "slot")).is_equal(0)
	assert_dict(cleared[1].redacted_for(1).to_dict()).is_equal(cleared[1].to_dict())
	assert_array(state.seats[1].board).is_empty()
	assert_array(state.seats[1].burned).is_equal(_typed([shown, hidden]))


# --- Hidden information (R20, R21) ----------------------------------------------------
# (test_seat_view.gd is at the file-length limit, so its DC-06 case lives here.)


## Seat 0's c19 destroys one of seat 1's two face-down cards: the opponent (seat 0) sees
## the destroy's seat and slot but not the card, in the event, in its view's row entry
## (destroyed, still a hidden id) and in the turn-end DESTROYED_CLEARED; the owner sees it
## all.
func test_a_destroyed_face_down_card_stays_hidden_from_the_opponent() -> void:
	var source: int = _id(0, C19_DESTROY)
	var row: Array[int] = [_id(1, C03), _id(1, C04)]
	var state: MatchState = _state(_typed([source]), row, 0)
	var recorder: Recorder = Recorder.new()
	ScoreWalk.begin(state)
	# One pulse: c19 flips and destroys; seat 1's cards are still face down.
	var paused: bool = ScoreWalk.step(state, _defs(), MatchRng.new(SEED), recorder.record, null)
	assert_bool(paused).is_false()
	var slot: int = MatchRng.new(SEED).pick_index(row.size())
	var target: int = row[slot]
	var found: Array[MatchEvent] = _of_kind(recorder.events, DESTROYED)
	assert_int(found.size()).is_equal(1)
	if found.is_empty():
		return
	var destroyed: MatchEvent = found[0]
	assert_int(destroyed.owner_seat).is_equal(1)
	_assert_hidden_with_slot(destroyed.redacted_for(0), slot)
	assert_int(_payload_int(destroyed.redacted_for(1), "card")).is_equal(target)
	# The row entries: the opponent sees the slot destroyed and no id; the owner sees both.
	var budgets: Array[int] = [1, 1]
	var theirs: SeatView = SeatView.build(state, 0, -1, budgets, _defs())
	var entry: Dictionary = theirs.opponent_row[slot]
	var flag: bool = entry["destroyed"]
	var shown: int = entry["card"]
	assert_bool(flag).is_true()
	assert_int(shown).is_equal(MatchEvent.HIDDEN_CARD)
	assert_bool(theirs.opponent_board.has(target)).is_false()
	for other: Dictionary in theirs.opponent_row:
		var named: int = other["card"]
		assert_int(named).is_not_equal(target)
	var other_entry: Dictionary = theirs.opponent_row[1 - slot]
	var other_flag: bool = other_entry["destroyed"]
	assert_bool(other_flag).is_false()
	var own: SeatView = SeatView.build(state, 1, -1, budgets, _defs())
	var own_entry: Dictionary = own.own_row[slot]
	var own_flag: bool = own_entry["destroyed"]
	var own_card: int = own_entry["card"]
	assert_bool(own_flag).is_true()
	assert_int(own_card).is_equal(target)
	# Cleared before the cursor reached it: the clear stays private to its seat.
	var cleared: Array[MatchEvent] = EffectResolver.clear_destroyed(state)
	assert_int(cleared.size()).is_equal(1)
	assert_int(cleared[0].kind).is_equal(CLEARED)
	assert_int(cleared[0].owner_seat).is_equal(1)
	_assert_hidden_with_slot(cleared[0].redacted_for(0), slot)
	assert_int(_payload_int(cleared[0].redacted_for(1), "card")).is_equal(target)


## A redacted destroy or clear of seat 1's card: the seat and the slot, no card id.
func _assert_hidden_with_slot(seen: MatchEvent, slot: int) -> void:
	assert_int(_payload_int(seen, "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_int(_payload_int(seen, "seat")).is_equal(1)
	assert_int(_payload_int(seen, "slot")).is_equal(slot)


## Records what a walk sends to its sink, with each event's owner.
class Recorder:
	extends RefCounted

	var events: Array[MatchEvent] = []

	func record(kind: int, payload: Dictionary, owner: int = MatchEvent.PUBLIC) -> void:
		events.append(MatchEvent.new(kind, payload, owner))
