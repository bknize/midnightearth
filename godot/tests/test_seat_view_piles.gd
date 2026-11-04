class_name TestSeatViewPiles
extends GdUnitTestSuite
## Hidden information of the destroyed piles (DC-07 T04; R18, R19, plan P6, the event
## table's CARD_RECOVERED): a seat's view lists its own pile by id and the opponent's by id
## only where the identity is public (the card left its row revealed), else HIDDEN_CARD, in
## pile order; CARD_RECOVERED and its CHOICE_MADE hide a face-down-destroyed card from the
## seat that did not recover it, and show a known one to both. test_seat_view.gd is past
## the file-length limit, so these cases live here; its scripted leak scan covers the new
## view fields too.
##
## States are built directly. Instance id = seat * DECK_SIZE + index into the fixture list.

const SEED: int = 1
const C03: int = 2
const C04: int = 3
const C08: int = 7
const C11: int = 10
const HIDDEN: int = MatchEvent.HIDDEN_CARD
const PUBLIC: int = MatchEvent.PUBLIC
const BOTH_DESTROYED: int = Choice.Zone.BOTH_DESTROYED

var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(FixtureDecks.cards())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


func _view(state: MatchState, seat: int) -> SeatView:
	var budgets: Array[int] = [1, 1]
	return SeatView.build(state, seat, -1, budgets, _defs())


func _pile(state: MatchState, seat: int, card: int, known: bool) -> void:
	state.seats[seat].destroyed.append(card)
	if known:
		state.seats[seat].destroyed_known[card] = true


## A recover prompt for `seat` over the current piles (the prompt EffectResolver opens).
func _prompt(state: MatchState, seat: int) -> Dictionary:
	var options: Array[int] = []
	for index: int in range(Choice.zone_cards(state, seat, BOTH_DESTROYED).size()):
		options.append(index)
	return {
		EffectResolver.KEY_SEAT: seat,
		EffectResolver.KEY_CARD: _id(seat, C11),
		EffectResolver.KEY_VERB: CardEffect.Verb.RECOVER_DESTROYED,
		Choice.KEY_ZONE: BOTH_DESTROYED,
		Choice.KEY_OPTIONS: MatchState.plain(options),
	}


func _of_kind(events: Array[MatchEvent], kind: int) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in events:
		if event.kind == kind:
			out.append(event)
	return out


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


## Every int at any depth of `value`.
func _all_ints(value: Variant, out: Array[int]) -> void:
	if value is Dictionary:
		var d: Dictionary = value
		for k: Variant in d.keys():
			_all_ints(d[k], out)
	elif value is Array:
		var items: Array = value
		for item: Variant in items:
			_all_ints(item, out)
	elif value is int:
		var number: int = value
		out.append(number)


# --- The views (R18, P6) --------------------------------------------------------------


## R18: the opponent's face-down-destroyed entry is HIDDEN_CARD and its known entry is its
## id, in pile order; the owner sees both ids. The hidden id appears nowhere in the other
## seat's view.
func test_the_opponents_unrevealed_destroyed_entry_is_hidden_and_a_known_one_is_public() -> void:
	var state: MatchState = MatchState.new(SEED)
	var known: int = _id(1, C04)
	var hidden: int = _id(1, C08)
	var own: int = _id(0, C03)
	_pile(state, 1, known, true)
	_pile(state, 1, hidden, false)
	_pile(state, 0, own, false)
	var theirs: SeatView = _view(state, 0)
	assert_array(theirs.opponent_destroyed).is_equal(_typed([known, HIDDEN]))
	assert_array(theirs.own_destroyed).is_equal(_typed([own]))
	var ints: Array[int] = []
	_all_ints(theirs.to_dict(), ints)
	assert_bool(ints.has(hidden)).is_false()
	var owner: SeatView = _view(state, 1)
	assert_array(owner.own_destroyed).is_equal(_typed([known, hidden]))
	assert_array(owner.opponent_destroyed).is_equal(_typed([HIDDEN]))
	var owner_dict: Dictionary = owner.to_dict()
	assert_array(owner_dict["own_destroyed"]).is_equal([known, hidden])
	assert_array(owner_dict["opponent_destroyed"]).is_equal([HIDDEN])


## R16, R18 through the turn-end clear: a revealed destroyed card is known in the pile, a
## face-down one is not, whatever the slot order.
func test_the_turn_end_clear_decides_what_the_pile_shows() -> void:
	var shown: int = _id(1, C04)
	var face_down: int = _id(1, C08)
	var state: MatchState = MatchState.new(SEED)
	state.seats[1].board.assign(_typed([face_down, shown]))
	state.seats[1].revealed[shown] = true
	state.card_state_for(shown).destroyed = true
	state.card_state_for(face_down).destroyed = true
	var cleared: Array[MatchEvent] = EffectResolver.clear_destroyed(state)
	assert_int(cleared.size()).is_equal(2)
	assert_int(cleared[0].owner_seat).is_equal(1)
	assert_int(cleared[1].owner_seat).is_equal(PUBLIC)
	assert_array(_view(state, 0).opponent_destroyed).is_equal(_typed([HIDDEN, shown]))
	assert_array(_view(state, 1).own_destroyed).is_equal(_typed([face_down, shown]))


# --- CARD_RECOVERED (R19, the event table) --------------------------------------------


## A seat recovers its own face-down-destroyed card: CHOICE_MADE and CARD_RECOVERED are
## private to it, the other seat sees the seat, pile and position but not the card, and
## its view shows only the hand count growing.
func test_card_recovered_hides_a_face_down_destroyed_card_from_the_other_seat() -> void:
	var state: MatchState = MatchState.new(SEED)
	var known: int = _id(0, C04)
	var hidden: int = _id(0, C08)
	_pile(state, 0, known, true)
	_pile(state, 0, hidden, false)
	var events: Array[MatchEvent] = EffectResolver.apply_choice(
		state, _defs(), _prompt(state, 0), 1, false
	)
	var made: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CHOICE_MADE)
	var recovered: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CARD_RECOVERED)
	assert_int(made.size()).is_equal(1)
	assert_int(recovered.size()).is_equal(1)
	assert_int(made[0].owner_seat).is_equal(0)
	assert_int(recovered[0].owner_seat).is_equal(0)
	assert_int(_payload_int(made[0].redacted_for(1), "target")).is_equal(HIDDEN)
	var seen: MatchEvent = recovered[0].redacted_for(1)
	assert_int(_payload_int(seen, "card")).is_equal(HIDDEN)
	assert_int(_payload_int(seen, "seat")).is_equal(0)
	assert_int(_payload_int(seen, "from_seat")).is_equal(0)
	assert_int(_payload_int(seen, "position")).is_equal(1)
	var own_copy: MatchEvent = recovered[0].redacted_for(0)
	assert_int(_payload_int(own_copy, "card")).is_equal(hidden)
	for event: MatchEvent in events:
		var ints: Array[int] = []
		_all_ints(event.redacted_for(1).payload, ints)
		assert_bool(ints.has(hidden)).is_false()
	var other: SeatView = _view(state, 1)
	assert_int(other.opponent_hand_count).is_equal(1)
	assert_array(other.opponent_destroyed).is_equal(_typed([known]))
	var ints_view: Array[int] = []
	_all_ints(other.to_dict(), ints_view)
	assert_bool(ints_view.has(hidden)).is_false()
	assert_array(_view(state, 0).own_hand).is_equal(_typed([hidden]))


## A known card's recovery is public: both seats see it, and the pile entry is gone.
func test_card_recovered_shows_a_known_card_to_both_seats() -> void:
	var state: MatchState = MatchState.new(SEED)
	var known: int = _id(1, C04)
	_pile(state, 0, _id(0, C03), false)
	_pile(state, 1, known, true)
	var events: Array[MatchEvent] = EffectResolver.apply_choice(
		state, _defs(), _prompt(state, 0), 1, false
	)
	var recovered: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CARD_RECOVERED)
	assert_int(recovered.size()).is_equal(1)
	assert_int(recovered[0].owner_seat).is_equal(PUBLIC)
	var payload: Dictionary = {"seat": 0, "card": known, "from_seat": 1, "position": 0}
	for seat: int in range(2):
		assert_dict(recovered[0].redacted_for(seat).payload).is_equal(payload)
	var made: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CHOICE_MADE)
	assert_int(made[0].owner_seat).is_equal(PUBLIC)
	assert_array(_view(state, 1).own_destroyed).is_empty()
	assert_bool(state.seats[1].is_destroyed_known(known)).is_false()


## Recovering the opponent's face-down-destroyed card: the chooser learns it (its own copy
## and its hand name it), and its view never named it while it was in the pile.
func test_recovering_an_opponents_hidden_card_reveals_it_only_to_the_chooser() -> void:
	var state: MatchState = MatchState.new(SEED)
	var hidden: int = _id(1, C08)
	_pile(state, 1, hidden, false)
	var before: Array[int] = []
	_all_ints(_view(state, 0).to_dict(), before)
	assert_bool(before.has(hidden)).is_false()
	var events: Array[MatchEvent] = EffectResolver.apply_choice(
		state, _defs(), _prompt(state, 0), 0, true
	)
	var recovered: Array[MatchEvent] = _of_kind(events, MatchEvent.Kind.CARD_RECOVERED)
	assert_int(recovered.size()).is_equal(1)
	assert_int(recovered[0].owner_seat).is_equal(0)
	assert_int(_payload_int(recovered[0].redacted_for(0), "card")).is_equal(hidden)
	assert_array(_view(state, 0).own_hand).is_equal(_typed([hidden]))
	assert_int(state.controller_of(hidden)).is_equal(0)
