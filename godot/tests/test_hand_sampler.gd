class_name TestHandSampler
extends GdUnitTestSuite
## HandSampler (cycle 7 DC-10 T13; R50, plan P12): unseen() is the opponent's twenty ids
## minus every id the view shows (either row, known destroyed, recovered into the seat's
## hand, commit or pile); sample() draws hand_size() distinct unseen ids per hand, the same
## hands for the same seed. Views are built by hand (seat 0, opponent 1: ids 20..39), and
## once from a started fixture match.

## Seat 1's first instance id (ids are origin * DECK_SIZE + index).
const OPPONENT_FIRST: int = MatchRules.DECK_SIZE
const SAMPLE_SEEDS: int = 20
const HANDS: int = 4


## Seat 0's view with opponent ids shown in every place a view can show one: 20 and 22 on
## the opponent's row (one hidden slot between), 25 on seat 0's row, 27 recovered into seat
## 0's hand, 26 in seat 0's face-down commit, 28 in seat 0's destroyed pile, 29 known in the
## opponent's pile (one hidden entry). The opponent holds `hand` cards, `pending` face down.
func _view(hand: int, pending: int) -> SeatView:
	var view: SeatView = SeatView.new()
	view.seat = 0
	view.opponent = 1
	view.opponent_board.assign([20, MatchEvent.HIDDEN_CARD, 22])
	view.own_board.assign([3, 25])
	view.own_hand.assign([5, 6, 27])
	view.own_pending.assign([26])
	view.own_destroyed.assign([28, 4])
	view.opponent_destroyed.assign([29, MatchEvent.HIDDEN_CARD])
	view.pile_entries = {29: {"card": 29}, 28: {"card": 28}, 4: {"card": 4}}
	view.opponent_hand_count = hand
	view.opponent_pending_count = pending
	return view


func _shown() -> Array[int]:
	var out: Array[int] = [20, 22, 25, 26, 27, 28, 29]
	return out


func test_unseen_excludes_every_shown_id_and_keeps_the_rest() -> void:
	var unseen: Array[int] = HandSampler.unseen(_view(5, 0), null)
	var expected: Array[int] = []
	for card: int in range(OPPONENT_FIRST, OPPONENT_FIRST + MatchRules.DECK_SIZE):
		if not _shown().has(card):
			expected.append(card)
	assert_array(unseen).is_equal(expected)
	assert_int(unseen.size()).is_equal(MatchRules.DECK_SIZE - _shown().size())
	for card: int in unseen:
		assert_int(card).is_between(OPPONENT_FIRST, OPPONENT_FIRST + MatchRules.DECK_SIZE - 1)


func test_samples_have_the_hand_count_of_distinct_unseen_ids() -> void:
	var view: SeatView = _view(5, 0)
	var unseen: Array[int] = HandSampler.unseen(view, null)
	for draw_seed: int in range(1, SAMPLE_SEEDS + 1):
		var hands: Array[Array] = HandSampler.sample(view, null, MatchRng.new(draw_seed), HANDS)
		assert_int(hands.size()).is_equal(HANDS)
		for hand: Array in hands:
			assert_int(hand.size()).is_equal(view.opponent_hand_count)
			var distinct: Dictionary[int, bool] = {}
			for card: int in hand:
				assert_bool(unseen.has(card)).is_true()
				distinct[card] = true
			assert_int(distinct.size()).is_equal(hand.size())


func test_same_seed_same_samples() -> void:
	var view: SeatView = _view(6, 0)
	var differs: bool = false
	for draw_seed: int in range(1, SAMPLE_SEEDS + 1):
		var first: Array[Array] = HandSampler.sample(view, null, MatchRng.new(draw_seed), HANDS)
		var again: Array[Array] = HandSampler.sample(view, null, MatchRng.new(draw_seed), HANDS)
		assert_array(again).is_equal(first)
		var other: Array[Array] = HandSampler.sample(
			view, null, MatchRng.new(draw_seed + 1000), HANDS
		)
		if other != first:
			differs = true
	assert_bool(differs).is_true()


## While the opponent has committed first, its commit left its hand: a sample is the hand it
## committed from (hand count plus face-down count). More than the unseen ids is clamped.
func test_hand_size_counts_the_face_down_commit_and_is_clamped() -> void:
	var view: SeatView = _view(3, 2)
	assert_int(HandSampler.hand_size(view)).is_equal(5)
	for hand: Array in HandSampler.sample(view, null, MatchRng.new(7), HANDS):
		assert_int(hand.size()).is_equal(5)
	var crowded: SeatView = _view(30, 0)
	var unseen: int = HandSampler.unseen(crowded, null).size()
	for hand: Array in HandSampler.sample(crowded, null, MatchRng.new(7), 2):
		assert_int(hand.size()).is_equal(unseen)
	assert_int(HandSampler.sample(view, null, MatchRng.new(7), 0).size()).is_equal(0)


## On a started fixture match, every card the opponent really holds (hand and deck) is
## unseen to seat 0, and no id seat 0's view shows is.
func test_a_real_view_hides_the_opponent_hand_and_nothing_shown() -> void:
	var engine: MatchEngine = FixtureDecks.engine(3, FixtureDecks.cards())
	assert_bool(engine.start().ok).is_true()
	var view: SeatView = engine.view_for(0)
	var unseen: Array[int] = HandSampler.unseen(view, engine.match_cards())
	var piles: MatchState.SeatPiles = engine._state.seats[1]
	for card: int in piles.hand:
		assert_bool(unseen.has(card)).is_true()
	for card: int in piles.deck:
		assert_bool(unseen.has(card)).is_true()
	for card: int in view.own_hand:
		assert_bool(unseen.has(card)).is_false()
	for hand: Array in HandSampler.sample(view, engine.match_cards(), MatchRng.new(1), HANDS):
		assert_int(hand.size()).is_equal(view.opponent_hand_count)
