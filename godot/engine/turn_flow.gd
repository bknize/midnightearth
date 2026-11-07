class_name TurnFlow
extends RefCounted
## The Turn outside the Walk, rules version 7 (cycle 9 plan P14; spec R1 to R21; resolution
## section 2): Match start, Round start, turn start, Commit acceptance, the discard-down,
## turn end and Round end. Static and pure over a MatchState: no node, no clock, every
## random draw from the engine stream passed in. MatchEngine sequences these calls; events
## go to `sink` as sink.call(kind, payload) or sink.call(kind, payload, owner).
##
## - start_match(): each Deck is built from its Owner's 40 ids and shuffled once with the
##   stream (seat 0's first), then each seat is dealt MatchRules.OPENING_HAND cards, seat 0's
##   first (R10). Nothing is dealt, refilled or reshuffled at Round start (R17).
## - begin_round(): the Round's first committer (R3: a coin flip on Round 1, else the
##   previous Round's loser, and after a tied Round the seat that did not commit first on
##   its last Turn).
## - begin_turn(): the commit order (the previous Turn's winner; a tie keeps it), TURN_STARTED
##   {round, turn, first_seat, budgets}, then each seat draws one card, first seat first
##   (draw()), then On start (hook on_start(), D2).
## - draw(): the top card of the Deck, or with an empty Deck nothing: DRAW_EMPTY {seat}, the
##   On empty draw hook (on_empty_draw(), D1, no re-check of the Deck, C29), then the resumed
##   draw of Q11 once if the Deck is no longer empty (resumed_draw()).
## - budget(): turn + the Energy granted this Turn (+ the Crew hook), nothing carried (R6).
## - hand_size(): MatchRules.HAND_SIZE plus every read "Hand size +N" (Pantry, R11).
## - accept_commit(): the cards leave the hand, the cost is spent (effective costs, the free
##   first card), `committed_count` records the Commit (0 for a Pass), COMMITTED; the first
##   Commit waits face down in `pending`, the second merges both into their rows face down.
## - after_commit(): On commit (hook on_commit(), D3/D5), then the discard-down: with more
##   cards in hand than its Hand size, a multi-select prompt for that seat over its hand
##   with `exact` the excess (R13), answered by answer_discard_down() (R14 is
##   Choice.is_valid_set), its Discards waking On discard (hook, D4/D6).
## - end_turn(): At turn end before the exit pass (hook, D9), the exit pass
##   (Statuses.exit_pass) and its On discard (D10), At turn end after (D11), turn-scoped
##   statuses end (Statuses.on_turn_end), Energy settles, the Turn's winner is recorded,
##   TURN_ENDED.
## - end_round(): every card on both rows to its Owner's Pile as a Discard, first seat's row
##   first, in slot order (R2, R20), On discard once (D12), then the Round is awarded to the
##   higher Score of its last Walk (R1, today's rule), ROUND_ENDED.
##
## Hook points (no-ops until their task fills them; each returns true when its drain paused
## on a prompt, and the task that makes one pause adds the resume): on_empty_draw() (T07
## Crew, T05 queue), on_start(), on_commit(), on_discard(), at_turn_end() (T05),
## crew_budget_bonus() (T07, Engineer). exit_pass() and end_statuses() are filled (T04).

const SEATS: int = 2
## The verb of the discard-down prompt.
const VERB_DISCARD_DOWN: String = "discard_down"
## CARD_DISCARDED `from` and `reason` (plan event table).
const FROM_HAND: String = "hand"
const FROM_ROW: String = "row"
const REASON_DISCARD: String = "discard"
const REASON_DISCARD_DOWN: String = "discard_down"
const REASON_CONDEMNED: String = "condemned"
const REASON_ROUND_END: String = "round_end"
## The drain points this module owns (resolution section 2).
const STEP_EMPTY_DRAW: String = "D1"
const STEP_ON_START: String = "D2"
const STEP_FIRST_COMMIT: String = "D3"
const STEP_FIRST_DISCARD: String = "D4"
const STEP_SECOND_COMMIT: String = "D5"
const STEP_SECOND_DISCARD: String = "D6"
const STEP_TURN_END_BEFORE: String = "D9"
const STEP_EXIT_PASS: String = "D10"
const STEP_TURN_END_AFTER: String = "D11"
const STEP_ROUND_END: String = "D12"
const MOMENT_TURN_END_BEFORE: String = "at_turn_end_before"
const MOMENT_TURN_END_AFTER: String = "at_turn_end_after"

# --- Match and Round start ------------------------------------------------------------


## Match start (R10): both Decks built and shuffled once (seat 0's first), the Crew uses
## filled, then MatchRules.OPENING_HAND cards dealt to each seat, seat 0's first (CARD_DEALT,
## private).
static func start_match(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable
) -> void:
	state.reset_crew_uses(cards)
	for seat: int in range(SEATS):
		var piles: MatchState.SeatPiles = state.seats[seat]
		piles.deck.clear()
		for index: int in range(MatchRules.DECK_SIZE):
			piles.deck.append(seat * MatchRules.DECK_SIZE + index)
		rng.shuffle_in_place(piles.deck)
	for seat: int in range(SEATS):
		for _deal: int in range(MatchRules.OPENING_HAND):
			var card: int = _take_top(state, seat)
			if card >= 0:
				sink.call(MatchEvent.Kind.CARD_DEALT, {"seat": seat, "card": card}, seat)


## Round start: the Round counter, sudden death past MatchRules.ROUNDS, Turn 0, both Scores
## and walking totals 0, the first committer (R3), ROUND_STARTED {round, sudden_death}. The
## rows are empty (end_round()); hands, Decks and Piles stay as they are (R17). The coin
## flip of Round 1 is the stream's only coin.
static func begin_round(state: MatchState, rng: MatchRng, sink: Callable) -> void:
	state.round_number += 1
	state.sudden_death = state.round_number > MatchRules.ROUNDS
	state.turn = 0
	for seat: int in range(SEATS):
		state.scores[seat] = 0
		state.totals[seat] = 0
	state.last_turn_winner = -1
	state.pending.clear()
	state.pending_slots.clear()
	state.walk = MatchState.WalkState.new()
	state.prompt = {}
	if state.round_number == 1:
		state.first_seat = rng.coin_flip()
	elif state.last_round_winner >= 0:
		state.first_seat = 1 - state.last_round_winner
	else:
		# A tied Round: the alternation goes on from its last Turn (C25).
		state.first_seat = 1 - state.first_seat
	var started: Dictionary = {"round": state.round_number, "sudden_death": state.sudden_death}
	sink.call(MatchEvent.Kind.ROUND_STARTED, started)


# --- Turn start -----------------------------------------------------------------------


## Turn start (resolution steps 1 to 3): the commit order, each seat's spend and Commit
## count cleared, TURN_STARTED, the draws (first seat first), then On start. The phase is
## AWAIT_FIRST. True when a drain paused on a prompt (none before T05 and T07).
static func begin_turn(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> bool:
	state.turn += 1
	if state.turn > 1 and state.last_turn_winner >= 0:
		state.first_seat = state.last_turn_winner
	state.phase = MatchState.Phase.AWAIT_FIRST
	for seat: int in range(SEATS):
		state.energy.spent[seat] = 0
		state.committed_count[seat] = 0
	var started: Dictionary = {
		"round": state.round_number,
		"turn": state.turn,
		"first_seat": state.first_seat,
		"budgets": [budget(state, cards, 0), budget(state, cards, 1)],
	}
	sink.call(MatchEvent.Kind.TURN_STARTED, started)
	for seat: int in [state.first_seat, 1 - state.first_seat]:
		if draw(state, cards, rng, sink, seat):
			return true
	return on_start(state, cards, rng, sink)


## One draw for `seat` (R12, R18, Q11): the top card of its Deck to its hand (CARD_DRAWN,
## private). With an empty Deck nothing is drawn: DRAW_EMPTY {seat}, then its On empty draw
## Batch drains (on_empty_draw(), D1) with no re-check of the Deck, then the denied draw is
## made once if the Deck is no longer empty (resumed_draw()). True when the drain paused.
static func draw(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, seat: int
) -> bool:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if not piles.deck.is_empty():
		var card: int = _take_top(state, seat)
		sink.call(MatchEvent.Kind.CARD_DRAWN, {"seat": seat, "card": card}, seat)
		return false
	sink.call(MatchEvent.Kind.DRAW_EMPTY, {"seat": seat})
	if on_empty_draw(state, cards, rng, sink, seat):
		return true
	if resumed_draw(state, sink, seat):
		pass  # Q11: the Deck was refilled during the drain (Dredger, T07).
	return false


## The resumed draw of Q11, right after the On empty draw drain: the top card when the Deck
## is no longer empty, else nothing and no second DRAW_EMPTY. True when a card was drawn.
static func resumed_draw(state: MatchState, sink: Callable, seat: int) -> bool:
	var card: int = _take_top(state, seat)
	if card < 0:
		return false
	sink.call(MatchEvent.Kind.CARD_DRAWN, {"seat": seat, "card": card}, seat)
	return true


## `seat`'s Budget this Turn (R6, R7): the Turn number plus the Energy granted for this
## Turn, plus a Crew's bonus (crew_budget_bonus()). Nothing carries between Turns.
static func budget(state: MatchState, cards: MatchCards, seat: int) -> int:
	if seat < 0 or seat >= SEATS:
		return 0
	return state.turn + state.energy.grants[seat] + crew_budget_bonus(state, cards, seat)


## `seat`'s Hand size (R11): the base MatchRules.HAND_SIZE, plus the amount of every "your
## Hand size is +N" Ongoing its revealed row cards make apply (Pantry). Milestone B's
## Quartermaster adds the "is N" set, which applies first.
static func hand_size(state: MatchState, cards: MatchCards, seat: int) -> int:
	var size: int = MatchRules.HAND_SIZE
	for ability: CardAbility in Scoring.ongoing_on_row(state, cards, seat, Scoring.HAND_SIZE_ADD_VERB):
		size += ability.amount
	return size


# --- Commits --------------------------------------------------------------------------


## Accepts `seat`'s validated Commit of `picked` at `slots` (R4, R8, R9): the cards leave
## the hand, the cost (Scoring.effective_cost each, less the leftmost card's with the free
## first card, which a Commit of a card uses up) is spent, `committed_count[seat]` is the
## card count (0 for a Pass), then COMMITTED {seat, cards, slots, cost, pass, count}, its
## cards private to the seat. The first Commit waits face down in `pending`; the second
## merges both into their rows face down, first seat's first. The phase is the caller's.
static func accept_commit(
	state: MatchState,
	cards: MatchCards,
	sink: Callable,
	seat: int,
	picked: Array[int],
	slots: Array[int]
) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	for card: int in picked:
		piles.hand.erase(card)
	var costs: Array[int] = Scoring.effective_costs(picked, state, cards)
	var cost: int = maxi(LegalPlays.commit_cost_with(picked, costs, state.energy.free_first[seat]), 0)
	state.energy.spent[seat] = cost
	if not picked.is_empty():
		state.energy.free_first[seat] = false
	state.committed_count[seat] = picked.size()
	var committed: Dictionary = {
		"seat": seat,
		"cards": MatchState.plain(picked),
		"slots": MatchState.plain(slots),
		"cost": cost,
		"pass": picked.is_empty(),
		"count": picked.size(),
	}
	sink.call(MatchEvent.Kind.COMMITTED, committed, seat)
	if seat == state.first_seat:
		state.pending.assign(picked)
		state.pending_slots.assign(slots)
		return
	var first_cards: Array[int] = []
	first_cards.assign(state.pending)
	var first_slots: Array[int] = []
	first_slots.assign(state.pending_slots)
	state.pending.clear()
	state.pending_slots.clear()
	merge_row(state, state.first_seat, first_cards, first_slots)
	merge_row(state, seat, picked, slots)


## After `seat`'s accepted Commit (resolution steps 5, 6, 8, 9): On commit drains (D3 or
## D5), then the discard-down opens when the hand is over its Hand size. True when a prompt
## is open (the discard-down, or a prompt the drain paused on).
static func after_commit(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, seat: int
) -> bool:
	if on_commit(state, cards, rng, sink, seat):
		return true
	return open_discard_down(state, cards, sink, seat)


## Opens the discard-down for `seat` when its hand holds more cards than its Hand size (R13):
## a multi-select over its hand (`zone` own_hand, every position an option) accepting exactly
## the excess, not optional, resuming the Commit at D4 (first seat) or D6 (second); the
## phase is AWAIT_CHOICE and PROMPT_OPENED (the prompt plus `text`) is public. False, with
## nothing changed, when the hand is within its Hand size.
static func open_discard_down(
	state: MatchState, cards: MatchCards, sink: Callable, seat: int
) -> bool:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var excess: int = LegalPlays.excess(piles.hand.size(), hand_size(state, cards, seat))
	if excess == 0:
		return false
	var options: Array = []
	for index: int in range(piles.hand.size()):
		options.append(index)
	var first: bool = seat == state.first_seat
	state.prompt = {
		Abilities.KEY_SEAT: seat,
		Abilities.KEY_CARD: -1,
		Choice.KEY_CREW: "",
		Abilities.KEY_VERB: VERB_DISCARD_DOWN,
		Choice.KEY_ZONE: Choice.zone_name(Choice.Zone.OWN_HAND),
		Choice.KEY_OPTIONS: options,
		Choice.KEY_MULTI: true,
		Choice.KEY_EXACT: excess,
		Choice.KEY_MIN: excess,
		Choice.KEY_OPTIONAL: false,
		Choice.KEY_RESUME: Choice.RESUME_COMMIT,
		Choice.KEY_STEP: STEP_FIRST_DISCARD if first else STEP_SECOND_DISCARD,
	}
	state.phase = MatchState.Phase.AWAIT_CHOICE
	var opened: Dictionary = state.prompt.duplicate(true)
	opened["text"] = discard_text(excess)
	sink.call(MatchEvent.Kind.PROMPT_OPENED, opened)
	return true


## The discard-down's banner text: "Discard N".
static func discard_text(count: int) -> String:
	return "Discard %d" % count


## Whether `prompt` is a discard-down.
static func is_discard_down(prompt: Dictionary) -> bool:
	var verb: String = prompt.get(Abilities.KEY_VERB, "")
	return verb == VERB_DISCARD_DOWN


## Answers the open discard-down with the hand positions `indices` (already validated: R14):
## the prompt closes (CHOICE_MADE, private), each chosen card goes to its Owner's Pile as a
## Discard in hand order (CARD_DISCARDED, reason discard_down), then their On discard
## Batches drain (D4 or D6). Returns the seat that discarded; the caller resumes its Commit.
static func answer_discard_down(
	state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable, indices: Array[int]
) -> int:
	var prompt: Dictionary = state.prompt
	var seat: int = prompt.get(Abilities.KEY_SEAT, -1)
	var step: String = Choice.step_of(prompt)
	var made: MatchEvent = Abilities.choice_made(state, prompt, Choice.Zone.OWN_HAND, indices)
	sink.call(made.kind, made.payload, made.owner_seat)
	state.prompt = {}
	var piles: MatchState.SeatPiles = state.seats[seat]
	var ordered: Array[int] = []
	ordered.assign(indices)
	ordered.sort()
	var chosen: Array[int] = []
	for index: int in ordered:
		chosen.append(piles.hand[index])
	for card: int in chosen:
		piles.hand.erase(card)
		to_pile(state, cards, sink, card, FROM_HAND, REASON_DISCARD_DOWN)
	if on_discard(state, cards, rng, sink, chosen, step):
		pass  # T05 adds the resume of a D4 or D6 drain paused on a prompt.
	return seat


## Sends `card`, already taken from its hand or row, to its Owner's Pile as a Discard
## (R19, R20, R31): CARD_DISCARDED {owner, card, from, reason, pile_index}, public, since a
## Pile entry is public (R24).
static func to_pile(
	state: MatchState, cards: MatchCards, sink: Callable, card: int, from: String, reason: String
) -> void:
	var owner: int = cards.origin_of(card)
	if owner < 0:
		owner = 0
	var pile: Array[int] = state.seats[owner].pile
	pile.append(card)
	var discarded: Dictionary = {
		"owner": owner,
		"card": card,
		"from": from,
		"reason": reason,
		"pile_index": pile.size() - 1,
	}
	sink.call(MatchEvent.Kind.CARD_DISCARDED, discarded)


## Places `picked` into `seat`'s row at their final `slots` (Placement, R43): walks the
## merged row's indices 0..n-1, taking the committed card whose slot matches, else the next
## card already on the row. Committed cards keep their relative order and stay face down.
static func merge_row(state: MatchState, seat: int, picked: Array[int], slots: Array[int]) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	var old_row: Array[int] = []
	old_row.assign(piles.board)
	var merged: Array[int] = []
	var next_new: int = 0
	var next_old: int = 0
	for slot: int in range(old_row.size() + picked.size()):
		if next_new < picked.size() and slots[next_new] == slot:
			merged.append(picked[next_new])
			next_new += 1
		elif next_old < old_row.size():
			merged.append(old_row[next_old])
			next_old += 1
	piles.board.assign(merged)


# --- Turn and Round end ---------------------------------------------------------------


## Turn end (R5; resolution steps 11 to 16): At turn end before the exit pass (D9), the exit
## pass (exit_pass()) with its On discard (D10), At turn end after (D11), turn-scoped
## statuses end (end_statuses()), Energy settles (this Turn's grants go and the next Turn's
## move in, spend cleared), the Turn's winner is recorded (the higher Score; a tie keeps the
## order), TURN_ENDED {scores, winner, wins, round, turn}. True when a drain paused.
static func end_turn(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> bool:
	if at_turn_end(state, cards, rng, sink, MOMENT_TURN_END_BEFORE, STEP_TURN_END_BEFORE):
		return true
	var exited: Array[int] = exit_pass(state, cards, sink)
	if not exited.is_empty() and on_discard(state, cards, rng, sink, exited, STEP_EXIT_PASS):
		return true
	if at_turn_end(state, cards, rng, sink, MOMENT_TURN_END_AFTER, STEP_TURN_END_AFTER):
		return true
	end_statuses(state, sink)
	for seat: int in range(SEATS):
		state.energy.grants[seat] = state.energy.next_turn_grants[seat]
		state.energy.next_turn_grants[seat] = 0
		state.energy.spent[seat] = 0
	var winner: int = leader(state.scores)
	state.last_turn_winner = winner
	var ended: Dictionary = {
		"scores": MatchState.plain(state.scores),
		"winner": winner,
		"wins": MatchState.plain(state.wins),
		"round": state.round_number,
		"turn": state.turn,
	}
	sink.call(MatchEvent.Kind.TURN_ENDED, ended)
	return false


## Round end (R1, R2, R20): every card on both rows goes to its Owner's Pile as a Discard,
## the first seat's row first, each in slot order (CARD_DISCARDED, from row, reason
## round_end); hands, Decks and Piles stay; On discard drains once (D12). Then the Round is
## awarded: the higher Score of its last Walk wins it, a tie awards none;
## `last_round_winner` is that winner (-1 for a tie), ROUND_ENDED {winner, wins, round,
## scores}. Returns the winner, or -1.
static func end_round(state: MatchState, cards: MatchCards, rng: MatchRng, sink: Callable) -> int:
	var cleared: Array[int] = []
	for seat: int in [state.first_seat, 1 - state.first_seat]:
		var piles: MatchState.SeatPiles = state.seats[seat]
		var row: Array[int] = []
		row.assign(piles.board)
		for card: int in row:
			if Statuses.take_from_row(state, seat, card, sink):
				pass  # Revealed or not, a Round-end clear is a Discard (R20).
			to_pile(state, cards, sink, card, FROM_ROW, REASON_ROUND_END)
			cleared.append(card)
	if not cleared.is_empty() and on_discard(state, cards, rng, sink, cleared, STEP_ROUND_END):
		pass  # T05 adds the resume of a Round end paused on a prompt.
	var winner: int = leader(state.scores)
	if winner >= 0:
		state.wins[winner] += 1
	state.last_round_winner = winner
	var ended: Dictionary = {
		"winner": winner,
		"wins": MatchState.plain(state.wins),
		"round": state.round_number,
		"scores": MatchState.plain(state.scores),
	}
	sink.call(MatchEvent.Kind.ROUND_ENDED, ended)
	return winner


## The seat with the higher of `values`, or -1 when they are equal.
static func leader(values: Array[int]) -> int:
	if values[0] > values[1]:
		return 0
	if values[1] > values[0]:
		return 1
	return -1


# --- Hook points ----------------------------------------------------------------------


## Hook (T07 Crew, T05 queue): `seat`'s On empty draw Batch wakes and drains (D1), every
## trigger firing with no re-check of the Deck (C29). True when the drain paused; the
## resumed draw (resumed_draw()) follows it.
static func on_empty_draw(
	_state: MatchState, _cards: MatchCards, _rng: MatchRng, _sink: Callable, _seat: int
) -> bool:
	return false


## Hook (T05): the On start Batch of revealed cards and Crew wakes and drains (D2).
static func on_start(
	_state: MatchState, _cards: MatchCards, _rng: MatchRng, _sink: Callable
) -> bool:
	return false


## Hook (T05): `seat`'s On commit Batch (its revealed row cards, its hand cards with `zone:
## hand`, its Crew; never a card committed this Turn) wakes and drains (D3 or D5).
static func on_commit(
	_state: MatchState, _cards: MatchCards, _rng: MatchRng, _sink: Callable, _seat: int
) -> bool:
	return false


## Hook (T05): each card of `discarded`, in order, wakes its On discard Batch, and the queue
## drains at `step` (D4, D6, D10 or D12).
static func on_discard(
	_state: MatchState,
	_cards: MatchCards,
	_rng: MatchRng,
	_sink: Callable,
	_discarded: Array[int],
	_step: String
) -> bool:
	return false


## Hook (T05): the At turn end Batch of `moment` (MOMENT_TURN_END_BEFORE or _AFTER) wakes
## and drains at `step` (D9 or D11).
static func at_turn_end(
	_state: MatchState,
	_cards: MatchCards,
	_rng: MatchRng,
	_sink: Callable,
	_moment: String,
	_step: String
) -> bool:
	return false


## The exit pass (R41, Statuses.exit_pass) in Q3 order, the first seat's row first, each in
## slot order; returns the cards it sent to a Pile as Discards (to_pile(), reason
## condemned), in pass order, for the D10 On discard Batches.
static func exit_pass(state: MatchState, cards: MatchCards, sink: Callable) -> Array[int]:
	return Statuses.exit_pass(state, cards, sink)


## Turn-scoped statuses and met named conditions end (resolution step 14;
## Statuses.on_turn_end), the seats' turn protections with them.
static func end_statuses(state: MatchState, sink: Callable) -> void:
	Statuses.on_turn_end(state, sink)


## Hook (T07, Engineer): the Energy a seat's Crew add to its Budget this Turn; 0 until then.
static func crew_budget_bonus(_state: MatchState, _cards: MatchCards, _seat: int) -> int:
	return 0


## Takes the top card of `seat`'s Deck into its hand; -1 when the Deck is empty.
static func _take_top(state: MatchState, seat: int) -> int:
	var piles: MatchState.SeatPiles = state.seats[seat]
	if piles.deck.is_empty():
		return -1
	var card: int = piles.deck[0]
	piles.deck.remove_at(0)
	piles.hand.append(card)
	return card
