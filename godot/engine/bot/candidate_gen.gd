class_name CandidateGen
extends RefCounted
## The candidate commits of a seat and their cheap ranking (cycle 7 R6, R7, plan P4, P14).
##
## all() lists exactly the greedy bot's candidates (GreedyBot.candidates_for: every legal set
## of the hand and budget, its ordered variants, both row ends, the free-first order), each
## distinct commit once, in the greedy bot's search order. It takes a hand, a budget, a row
## size and a free-first flag rather than a SeatView, so a bot can also enumerate the
## commits of a hand it only samples (the opponent's, milestone B; P14).
##
## bound() is the exact own-row gain of the committed set alone (P4): its cards walked in
## commit order from ×1.00 with their printed stats, each card's ×-part and +-part applied
## to the mult before its flat scores, as the pulse rule does (ScoreWalk._score), and the
## added amounts summed. It needs no preview and costs a few integer operations per card.
## top() is the first k of all() by bound, highest first, ties by fewer cards, then by the
## lower first instance id, then by search order.
##
## Static and pure: no state, no generator, no output.


## Every candidate commit for `seat` holding `hand` with `budget`, a row of `row_size` cards
## and the free first card when `free_first` (see the class comment), over `cards`.
static func all(
	hand: Array[int], budget: int, row_size: int, free_first: bool, seat: int, cards: MatchCards
) -> Array[EngineAction]:
	var view: SeatView = SeatView.new()
	view.seat = seat
	view.opponent = 1 - seat
	view.own_hand.assign(hand)
	for _slot: int in range(maxi(row_size, 0)):
		view.own_board.append(-1)
	view.energy = budget
	view.free_first = free_first
	var out: Array[EngineAction] = []
	var seen: Dictionary[String, bool] = {}
	for action: EngineAction in GreedyBot.candidates_for(view, cards):
		var key: String = key_of(action)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(action)
	return out


## The own-row gain of `action`'s cards alone at ×1.00 (see the class comment); 0 for an
## empty commit. A card with no definition adds nothing and leaves the mult as it is.
static func bound(action: EngineAction, cards: MatchCards) -> int:
	if action == null or cards == null:
		return 0
	var mult: int = MatchRules.MULT_ONE
	var total: int = 0
	for card: int in action.cards:
		var def: CardDef = cards.def_of(card)
		if def == null:
			continue
		if def.bonus_kind == CardDef.BonusKind.TIMES:
			mult = ScoreWalk.times_hundredths(mult, def.bonus)
		elif def.bonus_kind == CardDef.BonusKind.PLUS:
			mult += def.bonus * MatchRules.MULT_ONE
		@warning_ignore("integer_division")
		var added: int = def.flat * mult / MatchRules.MULT_ONE
		total += added
	return total


## The first `k` candidates of all() ranked by bound() (see the class comment); all of them
## when `k` is at least their count, none when `k` < 1.
static func top(
	hand: Array[int],
	budget: int,
	row_size: int,
	free_first: bool,
	seat: int,
	cards: MatchCards,
	k: int
) -> Array[EngineAction]:
	var listed: Array[EngineAction] = all(hand, budget, row_size, free_first, seat, cards)
	return ranked(listed, cards).slice(0, maxi(k, 0))


## `listed` sorted by bound() descending, then fewer cards, then lower first instance id
## (an empty commit counts as -1), then position in `listed`. A new array.
static func ranked(listed: Array[EngineAction], cards: MatchCards) -> Array[EngineAction]:
	var keys: Array[Vector4i] = []
	for index: int in range(listed.size()):
		var action: EngineAction = listed[index]
		var first: int = action.cards[0] if not action.cards.is_empty() else -1
		keys.append(Vector4i(-bound(action, cards), action.cards.size(), first, index))
	keys.sort()
	var out: Array[EngineAction] = []
	for key: Vector4i in keys:
		out.append(listed[key.w])
	return out


## A commit's identity for deduplication: its cards and slots, in order.
static func key_of(action: EngineAction) -> String:
	return "%s|%s" % [str(action.cards), str(action.slots)]
