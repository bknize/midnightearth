class_name PairPreview
extends RefCounted
## The opponent's side of the joint preview (cycle 7 R47-R49, plan P10), for
## MatchEngine.preview_pair(): whether a hypothetical opponent commit is acceptable, and
## the staging that puts it on a preview's clone in place of the real face-down commit.
##
## A hypothesis card is a card of the opponent's deck (its origin, MatchCards.origin_of) that
## the previewing seat cannot locate: in the opponent's hand, deck or burn pile, in its
## face-down commit, face down on its row, or in its destroyed pile with its identity hidden
## (unseen). A card the seat's view shows (a revealed row card, a known destroyed-pile card)
## or one the seat holds itself is not. Every unseen card is accepted the same way and
## staged to the same place, so neither the answer nor the scores depend on where it
## really is (R49).
##
## A hypothesis card is staged as the printed card: its memory is dropped on the clone, since
## no view shows the memory of a card it cannot locate (cycle 8 R8). So its cost in the
## budget check is the printed one (LegalPlays.def_costs), as on the clone.
##
## Static and pure: accepts() only reads; place() writes the clone it is given.


## Whether `opp` is a hypothesis the joint preview takes for `opponent` on `state` (R48):
## a commit by `opponent` whose cards are unseen (is_unseen) and legal for its public
## `budget` (MatchEngine.budget_for: the turn plus its carry) at the resolved slots
## (slots_of) on its row, priced at printed costs with its free-first grant as `state` holds
## it now. When `opponent` committed first (its face-down commit is pending), the hypothesis
## must also have the public count and the public slots of that commit. Its grant is then
## already consumed, so the check prices the hypothesis without it.
static func accepts(
	state: MatchState, opponent: int, opp: EngineAction, budget: int, cards: MatchCards
) -> bool:
	if opp == null or opp.kind != EngineAction.Kind.COMMIT or opp.seat != opponent:
		return false
	if not opp.indices.is_empty():
		return false
	for card: int in opp.cards:
		if not is_unseen(state, opponent, card, cards):
			return false
	var slots: Array[int] = slots_of(state, opp)
	if state.phase == MatchState.Phase.AWAIT_SECOND and state.first_seat == opponent:
		if opp.cards.size() != state.pending.size() or slots != state.pending_slots:
			return false
	return _legal(state, opponent, opp.cards, slots, budget, cards)


## Whether `card` is a card of `opponent`'s deck whose place the other seat cannot see on
## `state` (see the class comment).
static func is_unseen(state: MatchState, opponent: int, card: int, cards: MatchCards) -> bool:
	if cards == null or cards.origin_of(card) != opponent:
		return false
	var piles: MatchState.SeatPiles = state.seats[opponent]
	if piles.board.has(card):
		return not piles.is_revealed(card)
	if piles.destroyed.has(card):
		return not piles.is_destroyed_known(card)
	if state.pending.has(card):
		return state.first_seat == opponent
	return piles.hand.has(card) or piles.deck.has(card) or piles.burned.has(card)


## `opp`'s slots: its own, or for the compatibility default (cards with no slots) the right
## end of its seat's row on `state`, as MatchEngine resolves a commit.
static func slots_of(state: MatchState, opp: EngineAction) -> Array[int]:
	var out: Array[int] = []
	if not opp.slots.is_empty() or opp.cards.is_empty():
		out.assign(opp.slots)
		return out
	var piles: MatchState.SeatPiles = state.seats[opp.seat]
	return LegalPlays.append_slots(piles.board.size(), opp.cards.size())


## Stages the accepted hypothesis `hypothesis` of `opponent` on `clone` (a preview's copy,
## never the live state): the real face-down commit is dropped, and each hypothesis card
## leaves whichever hidden place holds it. Out of the hand, deck or burn pile it is simply
## taken; a card face down on the row or hidden in the destroyed pile leaves a placeholder
## in its place (an id past the match's instances, so it has no definition), which keeps
## the row and the pile their public sizes, and the caller's _hide_opponent then marks the
## row placeholder inert like any other face-down card. That is the "synthesised into the
## hand" of plan P10: the card is then in no pile, ready for the caller to commit. Each
## hypothesis card loses its memory and any row modifiers, so it commits as the printed card.
static func place(
	clone: MatchState, opponent: int, hypothesis: Array[int], cards: MatchCards
) -> void:
	clone.pending.clear()
	clone.pending_slots.clear()
	var piles: MatchState.SeatPiles = clone.seats[opponent]
	var placeholder: int = cards.size()
	for card: int in hypothesis:
		var slot: int = piles.board.find(card)
		if slot >= 0:
			piles.board[slot] = placeholder
			placeholder += 1
		var at: int = piles.destroyed.find(card)
		if at >= 0:
			piles.destroyed[at] = placeholder
			placeholder += 1
		piles.hand.erase(card)
		piles.deck.erase(card)
		piles.burned.erase(card)
		if piles.revealed.erase(card):
			pass  # A face-down card may still carry a false entry; it leaves the row.
		if clone.clear_card_state(card):
			pass  # Its row modifiers stay behind with its slot.
		if clone.memory.erase(card):
			pass  # No view shows it: the hypothesis is the printed card (cycle 8 R8).


## Whether `hand` committed at `slots` is legal for `opponent` on `state`: LegalPlays over
## the hypothesis's printed costs, with the row size, `budget` and the grant `state` holds.
static func _legal(
	state: MatchState,
	opponent: int,
	hand: Array[int],
	slots: Array[int],
	budget: int,
	cards: MatchCards
) -> bool:
	var piles: MatchState.SeatPiles = state.seats[opponent]
	var code: int = LegalPlays.validate_with(
		hand,
		slots,
		hand,
		LegalPlays.def_costs(hand, cards),
		piles.board.size(),
		budget,
		state.energy.free_first[opponent]
	)
	return code == EngineError.Code.NONE
