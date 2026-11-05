class_name TestPreviewPair
extends GdUnitTestSuite
## The joint preview (cycle 7 DC-10 T12; R47-R49, plan P10): MatchEngine.preview_pair()
## scores one own commit against one hypothetical opponent commit. With an empty hypothesis
## it equals preview(); when the opponent committed first, a hypothesis must have the public
## count and slots; an unseen card scores the same wherever it really sits (hand, deck,
## burn, face down on the row, hidden in the destroyed pile) and as the printed card; the
## real face-down commit never scores; and nothing the engine holds changes.
##
## Positions are set by hand on the DC-05 fixture (as test_greedy_bot.gd does), every card
## used here vanilla. Instance id = seat * DECK_SIZE + index.

const SEED: int = 1
const TURN: int = 6
# Definition indices in the fixture card list.
const C02: int = 1  # cost 1, flat 2
const C03: int = 2  # cost 1, flat 1, ×1.25
const C04: int = 3  # cost 1, flat 3
const C08: int = 7  # cost 2, flat 4
const C13: int = 12  # cost 4, flat 5
const C14: int = 13  # cost 4, flat 6
const C18: int = 17  # cost 6, flat 8

var _cached_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


## A started engine on round 1, turn TURN (each budget TURN), `first` awaited first, with
## these hands and rows (every row card revealed), each deck holding the seat's other cards.
func _position(
	first: int, hand_0: Array[int], hand_1: Array[int], row_0: Array[int], row_1: Array[int]
) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	engine.start()
	var state: MatchState = engine._state
	state.round_number = 1
	state.turn = TURN
	state.first_seat = first
	state.phase = MatchState.Phase.AWAIT_FIRST
	state.pending.clear()
	state.pending_slots.clear()
	state.scores.assign([0, 0])
	state.card_states.clear()
	state.walk = MatchState.WalkState.new()
	state.prompt = {}
	state.energy = MatchState.EnergyState.new()
	state.bonus_zero_pending.assign([false, false])
	_set_seat(state, 0, hand_0, row_0)
	_set_seat(state, 1, hand_1, row_1)
	return engine


func _set_seat(state: MatchState, seat: int, hand: Array[int], row: Array[int]) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.hand.assign(hand)
	piles.board.assign(row)
	piles.burned.clear()
	piles.destroyed.clear()
	piles.destroyed_known.clear()
	piles.revealed.clear()
	for card: int in row:
		piles.revealed[card] = true
	piles.deck.clear()
	for index: int in range(MatchRules.DECK_SIZE):
		var card: int = _id(seat, index)
		if not hand.has(card) and not row.has(card):
			piles.deck.append(card)


## Turns `card` face down on seat 1's row (as an Echo flip or a swap behind the cursor
## leaves it).
func _face_down(engine: MatchEngine, card: int) -> void:
	var piles: MatchState.SeatPiles = engine._state.seats[1]
	piles.revealed.erase(card)


## Moves `card` from seat 1's deck to `pile` ("burned", or "destroyed" with its identity
## hidden).
func _bury(engine: MatchEngine, card: int, pile: String) -> void:
	var piles: MatchState.SeatPiles = engine._state.seats[1]
	piles.deck.erase(card)
	if pile == "burned":
		piles.burned.append(card)
	else:
		piles.destroyed.append(card)


## Everything a preview must leave alone: the full state, the live stream, the accepted
## actions, the log, the last call's events and both views.
func _snapshot(engine: MatchEngine) -> Dictionary:
	return {
		"state": engine.full_state(),
		"stream": engine._rng.state,
		"count": engine.accepted_action_count(),
		"log": engine.action_log().to_json(),
		"events": engine._events.size(),
		"view_0": engine.view_for(0).to_dict(),
		"view_1": engine.view_for(1).to_dict(),
	}


## Seat 0's own commit used throughout: c03 then c08 on an empty row, scoring
## 1 + floor(4 × 1.25) = 6.
func _own() -> EngineAction:
	return EngineAction.commit(0, _typed([_id(0, C03), _id(0, C08)]), _typed([0, 1]))


func _own_hand() -> Array[int]:
	return _typed([_id(0, C03), _id(0, C08)])


# --- The empty hypothesis -------------------------------------------------------------


## Seat 0 committing first: the empty hypothesis scores what preview() scores, and a real
## hypothesis adds its cards to the opponent's row.
func test_empty_hypothesis_equals_preview_when_committing_first() -> void:
	var row_1: Array[int] = [_id(1, C02)]
	var hand_1: Array[int] = [_id(1, C04), _id(1, C14)]
	var engine: MatchEngine = _position(0, _own_hand(), hand_1, _none(), row_1)
	var empty: EngineAction = EngineAction.commit(1, _none())
	var expected: Array[int] = engine.preview(0, _own())
	assert_array(expected).is_equal(_typed([6, 2]))
	assert_array(engine.preview_pair(0, _own(), empty)).is_equal(expected)
	var passing: EngineAction = EngineAction.commit(0, _none())
	assert_array(engine.preview_pair(0, passing, empty)).is_equal(engine.preview(0, passing))
	var hypothesis: EngineAction = EngineAction.commit(1, _typed([_id(1, C14)]))
	assert_array(engine.preview_pair(0, _own(), hypothesis)).is_equal(_typed([6, 8]))


## Seat 0 committing second after the opponent passed: the empty hypothesis equals preview().
func test_empty_hypothesis_equals_preview_when_committing_second() -> void:
	var row_1: Array[int] = [_id(1, C02)]
	var hand_1: Array[int] = [_id(1, C04), _id(1, C14)]
	var engine: MatchEngine = _position(1, _own_hand(), hand_1, _none(), row_1)
	assert_bool(engine.apply(EngineAction.commit(1, _none())).ok).is_true()
	var empty: EngineAction = EngineAction.commit(1, _none())
	var expected: Array[int] = engine.preview(0, _own())
	assert_int(expected.size()).is_equal(2)
	assert_array(engine.preview_pair(0, _own(), empty)).is_equal(expected)


# --- The public count and slots -------------------------------------------------------


## The opponent committed two cards first on slots 0 and 2: only a two-card hypothesis on
## slots 0 and 2, legal for its budget, is previewed.
func test_hypothesis_must_match_the_public_count_and_slots() -> void:
	var hand_1: Array[int] = [_id(1, C02), _id(1, C04), _id(1, C08)]
	var engine: MatchEngine = _position(1, _own_hand(), hand_1, _none(), _typed([_id(1, C13)]))
	var real: EngineAction = EngineAction.commit(
		1, _typed([_id(1, C02), _id(1, C04)]), _typed([0, 2])
	)
	assert_bool(engine.apply(real).ok).is_true()
	var own: EngineAction = EngineAction.commit(0, _none())
	var c08: int = _id(1, C08)
	var c14: int = _id(1, C14)
	var wrong_count: EngineAction = EngineAction.commit(1, _typed([c08]), _typed([0]))
	var wrong_slots: EngineAction = EngineAction.commit(1, _typed([c08, c14]), _typed([0, 1]))
	var appended: EngineAction = EngineAction.commit(1, _typed([c08, c14]))
	var three: EngineAction = EngineAction.commit(
		1, _typed([c08, c14, _id(1, C03)]), _typed([0, 2, 3])
	)
	var over_budget: EngineAction = EngineAction.commit(
		1, _typed([c14, _id(1, C18)]), _typed([0, 2])
	)
	assert_array(engine.preview_pair(0, own, wrong_count)).is_empty()
	assert_array(engine.preview_pair(0, own, wrong_slots)).is_empty()
	assert_array(engine.preview_pair(0, own, appended)).is_empty()
	assert_array(engine.preview_pair(0, own, three)).is_empty()
	assert_array(engine.preview_pair(0, own, EngineAction.commit(1, _none()))).is_empty()
	assert_array(engine.preview_pair(0, own, over_budget)).is_empty()
	# c08 on slot 0, c13 stays on 1, c14 on 2: 4 + 5 + 6.
	var good: EngineAction = EngineAction.commit(1, _typed([c08, c14]), _typed([0, 2]))
	assert_array(engine.preview_pair(0, own, good)).is_equal(_typed([0, 15]))
	# The real commit as a hypothesis: 2 + 5 + 3.
	assert_array(engine.preview_pair(0, own, real)).is_equal(_typed([0, 10]))


## Not acceptable either way: a card the view shows (a revealed row card), a card of the
## previewing seat's own deck, a commit for the wrong seat, not a commit, or no hypothesis;
## and an own commit the engine would refuse.
func test_hypothesis_of_seen_cards_or_wrong_shape_is_refused() -> void:
	var row_1: Array[int] = [_id(1, C02)]
	var hand_1: Array[int] = [_id(1, C04), _id(1, C14)]
	var engine: MatchEngine = _position(0, _own_hand(), hand_1, _none(), row_1)
	var shown: EngineAction = EngineAction.commit(1, _typed([_id(1, C02)]))
	var own_deck: EngineAction = EngineAction.commit(1, _typed([_id(0, C13)]))
	var wrong_seat: EngineAction = EngineAction.commit(0, _typed([_id(1, C14)]))
	var over_budget: EngineAction = EngineAction.commit(1, _typed([_id(1, C14), _id(1, C13)]))
	assert_array(engine.preview_pair(0, _own(), shown)).is_empty()
	assert_array(engine.preview_pair(0, _own(), own_deck)).is_empty()
	assert_array(engine.preview_pair(0, _own(), wrong_seat)).is_empty()
	assert_array(engine.preview_pair(0, _own(), over_budget)).is_empty()
	assert_array(engine.preview_pair(0, _own(), EngineAction.concede(1))).is_empty()
	assert_array(engine.preview_pair(0, _own(), null)).is_empty()
	var empty: EngineAction = EngineAction.commit(1, _none())
	assert_array(engine.preview_pair(1, EngineAction.commit(1, _none()), empty)).is_empty()
	var not_held: EngineAction = EngineAction.commit(0, _typed([_id(0, C18)]))
	assert_array(engine.preview_pair(0, not_held, empty)).is_empty()


# --- Hidden information (R49) ---------------------------------------------------------


## Two engines with the same view, one holding the hypothesis card in the opponent's hand
## and the other in its deck, return equal scores; so does a third with it in the burn pile
## and a fourth with it hidden in the destroyed pile.
func test_hand_deck_or_burn_give_equal_scores() -> void:
	var x: int = _id(1, C14)
	var y: int = _id(1, C13)
	var row_1: Array[int] = [_id(1, C04)]
	var in_hand: MatchEngine = _position(0, _own_hand(), _typed([_id(1, C02), x]), _none(), row_1)
	var in_deck: MatchEngine = _position(0, _own_hand(), _typed([_id(1, C02), y]), _none(), row_1)
	assert_dict(in_deck.view_for(0).to_dict()).is_equal(in_hand.view_for(0).to_dict())
	var hypothesis: EngineAction = EngineAction.commit(1, _typed([x]))
	var expected: Array[int] = in_hand.preview_pair(0, _own(), hypothesis)
	# c04 then c14: 3 + 6.
	assert_array(expected).is_equal(_typed([6, 9]))
	assert_array(in_deck.preview_pair(0, _own(), hypothesis)).is_equal(expected)
	var other: EngineAction = EngineAction.commit(1, _typed([y]))
	assert_array(in_deck.preview_pair(0, _own(), other)).is_equal(
		in_hand.preview_pair(0, _own(), other)
	)
	var burned: MatchEngine = _position(0, _own_hand(), _typed([_id(1, C02), y]), _none(), row_1)
	_bury(burned, x, "burned")
	assert_array(burned.preview_pair(0, _own(), hypothesis)).is_equal(expected)
	var wrecked: MatchEngine = _position(0, _own_hand(), _typed([_id(1, C02), y]), _none(), row_1)
	_bury(wrecked, x, "destroyed")
	assert_array(wrecked.preview_pair(0, _own(), hypothesis)).is_equal(expected)


## The hypothesis card face down on the opponent's row (another card in its hand) scores as
## when it is in the hand (another card face down in that slot), and as the printed card even
## when it carries a memory the view cannot show.
func test_face_down_row_card_and_hidden_memory_give_equal_scores() -> void:
	var x: int = _id(1, C14)
	var z: int = _id(1, C18)
	var in_hand: MatchEngine = _position(
		0, _own_hand(), _typed([_id(1, C02), x]), _none(), _typed([_id(1, C04), z])
	)
	_face_down(in_hand, z)
	var on_row: MatchEngine = _position(
		0, _own_hand(), _typed([_id(1, C02), z]), _none(), _typed([_id(1, C04), x])
	)
	_face_down(on_row, x)
	on_row._state.memory_for(x).flat = 5
	assert_dict(on_row.view_for(0).to_dict()).is_equal(in_hand.view_for(0).to_dict())
	var hypothesis: EngineAction = EngineAction.commit(1, _typed([x]))
	var expected: Array[int] = in_hand.preview_pair(0, _own(), hypothesis)
	# c04, the inert face-down slot, then c14 as printed: 3 + 0 + 6.
	assert_array(expected).is_equal(_typed([6, 9]))
	assert_array(on_row.preview_pair(0, _own(), hypothesis)).is_equal(expected)
	in_hand._state.memory_for(x).flat = 5
	assert_array(in_hand.preview_pair(0, _own(), hypothesis)).is_equal(expected)


## The opponent's real face-down commit never scores: a weak hypothesis against a strong
## real commit gives the weak result, the same as on a twin where the weak card is real.
func test_real_pending_cards_never_score() -> void:
	var weak: int = _id(1, C02)
	var strong: int = _id(1, C18)
	var hand_1: Array[int] = [weak, strong]
	var row_1: Array[int] = [_id(1, C04)]
	var strong_real: MatchEngine = _position(1, _own_hand(), hand_1, _none(), row_1)
	var weak_real: MatchEngine = _position(1, _own_hand(), hand_1, _none(), row_1)
	assert_bool(strong_real.apply(EngineAction.commit(1, _typed([strong]))).ok).is_true()
	assert_bool(weak_real.apply(EngineAction.commit(1, _typed([weak]))).ok).is_true()
	assert_dict(weak_real.view_for(0).to_dict()).is_equal(strong_real.view_for(0).to_dict())
	var weak_hypothesis: EngineAction = EngineAction.commit(1, _typed([weak]), _typed([1]))
	var strong_hypothesis: EngineAction = EngineAction.commit(1, _typed([strong]), _typed([1]))
	# c04 then c02: 3 + 2; c04 then c18: 3 + 8.
	assert_array(strong_real.preview_pair(0, _own(), weak_hypothesis)).is_equal(_typed([6, 5]))
	assert_array(weak_real.preview_pair(0, _own(), weak_hypothesis)).is_equal(_typed([6, 5]))
	assert_array(strong_real.preview_pair(0, _own(), strong_hypothesis)).is_equal(_typed([6, 11]))
	assert_array(weak_real.preview_pair(0, _own(), strong_hypothesis)).is_equal(_typed([6, 11]))


# --- Purity ---------------------------------------------------------------------------


## preview_pair changes no state, stream, accepted action, log, event or view, whether it
## scores or refuses, with a real face-down commit and a face-down row card in play.
func test_preview_pair_changes_nothing() -> void:
	var x: int = _id(1, C14)
	var hand_1: Array[int] = [_id(1, C02), _id(1, C18)]
	var row_1: Array[int] = [_id(1, C04), x]
	var engine: MatchEngine = _position(1, _own_hand(), hand_1, _none(), row_1)
	_face_down(engine, x)
	engine._state.memory_for(x).flat = 5
	assert_bool(engine.apply(EngineAction.commit(1, _typed([_id(1, C18)]))).ok).is_true()
	var before: Dictionary = _snapshot(engine)
	var slot: Array[int] = [2]
	var scored: Array[int] = engine.preview_pair(
		0, _own(), EngineAction.commit(1, _typed([x]), slot)
	)
	assert_int(scored.size()).is_equal(2)
	var real: EngineAction = EngineAction.commit(1, _typed([_id(1, C18)]), slot)
	assert_int(engine.preview_pair(0, _own(), real).size()).is_equal(2)
	var refused: EngineAction = EngineAction.commit(1, _typed([x]), _typed([0]))
	assert_array(engine.preview_pair(0, _own(), refused)).is_empty()
	assert_dict(_snapshot(engine)).is_equal(before)
