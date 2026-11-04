class_name SeatView
extends RefCounted
## One seat's redacted view of a match (R28, R29, C4), built by MatchEngine.view_for().
##
## Holds the seat's own hand and own face-down commit, both ordered rows, the opponent's
## hand and face-down commit counts and that commit's slots (R7), both deck counts, both
## board scores, both round-win counts, both budgets, the round, the turn, the energy,
## the phase and the awaited seat.
##
## Never holds the match seed, the stream state, any deck order, or the id of any card in
## the opponent's hand, deck, face-down commit or burn pile. Seat-indexed pairs
## (deck_counts, scores, wins, budgets) are indexed by seat number, like MatchState.
##
## Every array is a copy: mutating a view never touches the engine's state.

var seat: int = 0
var opponent: int = 1
## This seat's hand, in hand order.
var own_hand: Array[int] = []
## This seat's face-down commit while the opponent is awaited; empty otherwise.
var own_pending: Array[int] = []
## The ordered rows (R4): a card's slot is its index. Pending cards are not on a row.
var own_board: Array[int] = []
var opponent_board: Array[int] = []
var opponent_hand_count: int = 0
## Size of the opponent's face-down commit while this seat is awaited second; else 0.
var opponent_pending_count: int = 0
## The final-row slots of that face-down commit (R7, plan P2), without its card ids;
## empty unless this seat is awaited second.
var opponent_pending_slots: Array[int] = []
var deck_counts: Array[int] = [0, 0]
var scores: Array[int] = [0, 0]
var wins: Array[int] = [0, 0]
## Counts past MatchRules.ROUNDS in sudden death.
var round_number: int = 0
var turn: int = 0
## This seat's budget this turn: budgets[seat] (R9).
var energy: int = 0
## Both seats' budgets this turn, turn + carry (R9).
var budgets: Array[int] = [0, 0]
## A MatchState.Phase.
var phase: int = MatchState.Phase.NOT_STARTED
## The seat whose commit is awaited; -1 before the start and once the match is over.
var awaited_seat: int = -1
## This turn's first committer, as announced by ROUND_STARTED and TURN_STARTED.
var first_seat: int = 0
var sudden_death: bool = false


## The view of `state` for `p_seat` (0 or 1). `p_awaited` and `p_budgets` come from the
## engine, which owns those derivations.
static func build(
	state: MatchState, p_seat: int, p_awaited: int, p_budgets: Array[int]
) -> SeatView:
	var view: SeatView = SeatView.new()
	view.seat = p_seat
	view.opponent = 1 - p_seat
	var own: MatchState.SeatPiles = state.seats[view.seat]
	var other: MatchState.SeatPiles = state.seats[view.opponent]
	view.own_hand.assign(own.hand)
	view.own_board.assign(own.board)
	view.opponent_board.assign(other.board)
	view.opponent_hand_count = other.hand.size()
	# `pending` belongs to the first committer while the second is awaited.
	if state.phase == MatchState.Phase.AWAIT_SECOND:
		if state.first_seat == view.seat:
			view.own_pending.assign(state.pending)
		else:
			view.opponent_pending_count = state.pending.size()
			view.opponent_pending_slots.assign(state.pending_slots)
	for index: int in range(2):
		var piles: MatchState.SeatPiles = state.seats[index]
		view.deck_counts[index] = piles.deck.size()
		view.scores[index] = state.scores[index]
		view.wins[index] = state.wins[index]
		view.budgets[index] = p_budgets[index]
	view.round_number = state.round_number
	view.turn = state.turn
	view.energy = view.budgets[view.seat]
	view.phase = state.phase
	view.awaited_seat = p_awaited
	view.first_seat = state.first_seat
	view.sudden_death = state.sudden_death
	return view


func is_awaited() -> bool:
	return awaited_seat == seat


## The ordered row of either seat, as a copy.
func board_of(p_seat: int) -> Array[int]:
	var out: Array[int] = []
	if p_seat == seat:
		out.assign(own_board)
	elif p_seat == opponent:
		out.assign(opponent_board)
	return out


## The view as plain, deep-copied data, for tests and leak scans.
func to_dict() -> Dictionary:
	return {
		"seat": seat,
		"opponent": opponent,
		"own_hand": MatchState.plain(own_hand),
		"own_pending": MatchState.plain(own_pending),
		"own_board": MatchState.plain(own_board),
		"opponent_board": MatchState.plain(opponent_board),
		"opponent_hand_count": opponent_hand_count,
		"opponent_pending_count": opponent_pending_count,
		"opponent_pending_slots": MatchState.plain(opponent_pending_slots),
		"deck_counts": MatchState.plain(deck_counts),
		"scores": MatchState.plain(scores),
		"wins": MatchState.plain(wins),
		"round": round_number,
		"turn": turn,
		"energy": energy,
		"budgets": MatchState.plain(budgets),
		"phase": phase,
		"awaited_seat": awaited_seat,
		"first_seat": first_seat,
		"sudden_death": sudden_death,
	}
