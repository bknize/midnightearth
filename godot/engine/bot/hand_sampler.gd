class_name HandSampler
extends RefCounted
## Opponent hands consistent with one seat's view (cycle 7 R50, plan P12), for the matrix
## bot's hypotheses.
##
## unseen() is the opponent's twenty instance ids (`opponent * DECK_SIZE + i`: deck lists
## are public, MatchCards) minus every id the view shows: any card on either row with an id
## (the opponent's revealed row cards among them), the opponent's destroyed-pile cards whose
## identity is public, and every card of the opponent's deck the seat holds itself (recovered
## into its hand, its face-down commit, its row or its destroyed pile). What is left is
## exactly what the seat cannot locate: the opponent's hand, deck, burn pile, face-down
## commit, face-down row cards and hidden destroyed-pile cards, as PairPreview.is_unseen
## accepts them.
##
## sample() draws hand_size() distinct ids of unseen() without replacement, `n` times, each
## draw one rng.pick_index over the ids not yet drawn. hand_size() is the opponent's hand
## count plus its face-down commit count: while the opponent has committed first, its
## commit left its hand, and the hypotheses are commits from the hand it held then (R53).
## Before it commits the pending count is 0, so a sample is opponent_hand_count ids.
##
## Static and pure: no state, no output, every draw from the generator passed in.


## The opponent's instance ids the view does not show (see the class comment), ascending.
## `_cards` is not read: instance ids are `origin * DECK_SIZE + index` for every deck.
static func unseen(view: SeatView, _cards: MatchCards) -> Array[int]:
	var shown: Dictionary[int, bool] = {}
	for listed: Array[int] in [
		view.own_board,
		view.opponent_board,
		view.own_hand,
		view.own_pending,
		view.own_destroyed,
		view.opponent_destroyed,
	]:
		for card: int in listed:
			shown[card] = true
	for card: int in view.pile_entries:
		shown[card] = true
	var out: Array[int] = []
	var first: int = view.opponent * MatchRules.DECK_SIZE
	for card: int in range(first, first + MatchRules.DECK_SIZE):
		if not shown.has(card):
			out.append(card)
	return out


## How many cards a sampled hand holds: the opponent's hand count plus its face-down commit
## count (see the class comment).
static func hand_size(view: SeatView) -> int:
	return maxi(view.opponent_hand_count, 0) + maxi(view.opponent_pending_count, 0)


## `n` hands (none when `n` < 1), each hand_size() distinct ids of unseen() (all of them
## when fewer are unseen) drawn without replacement by `rng`, each hand sorted ascending.
## The same view and generator state give the same hands.
static func sample(view: SeatView, cards: MatchCards, rng: MatchRng, n: int) -> Array[Array]:
	var pool: Array[int] = unseen(view, cards)
	var size: int = mini(hand_size(view), pool.size())
	var out: Array[Array] = []
	for _hand: int in range(maxi(n, 0)):
		var left: Array[int] = pool.duplicate()
		var hand: Array[int] = []
		for _draw: int in range(size):
			var at: int = rng.pick_index(left.size())
			hand.append(left[at])
			left.remove_at(at)
		hand.sort()
		out.append(hand)
	return out
