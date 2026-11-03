class_name SeatView
extends RefCounted
## One seat's redacted view of a match (R28, R29, C4), built by MatchEngine.view_for().
##
## Holds the seat's own hand and own face-down commit, both boards' revealed cards, the
## opponent's hand and face-down commit counts, both deck counts, both board scores, both
## round-win counts, the round, the turn, the energy, the phase and the awaited seat.
##
## Never holds the match seed, the stream state, any deck order, or the id of any card in
## the opponent's hand, deck, face-down commit or burn pile. Seat-indexed pairs
## (deck_counts, scores, wins) are indexed by seat number, like MatchState.
##
## Every array is a copy: mutating a view never touches the engine's state.

var seat: int = 0
var opponent: int = 1
## This seat's hand, in hand order.
var own_hand: Array[int] = []
## This seat's face-down commit while the opponent is awaited; empty otherwise.
var own_pending: Array[int] = []
## Revealed cards, in reveal order.
var own_board: Array[int] = []
var opponent_board: Array[int] = []
var opponent_hand_count: int = 0
## Size of the opponent's face-down commit while this seat is awaited second; else 0.
var opponent_pending_count: int = 0
var deck_counts: Array[int] = [0, 0]
var scores: Array[int] = [0, 0]
var wins: Array[int] = [0, 0]
## Counts past MatchRules.ROUNDS in sudden death.
var round_number: int = 0
var turn: int = 0
var energy: int = 0
## A MatchState.Phase.
var phase: int = MatchState.Phase.NOT_STARTED
## The seat whose commit is awaited; -1 before the start and once the match is over.
var awaited_seat: int = -1
## This turn's first committer, as announced by ROUND_STARTED and TURN_STARTED.
var first_seat: int = 0
var sudden_death: bool = false


## The view of `state` for `p_seat` (0 or 1). `p_awaited` and `p_energy` come from the
## engine, which owns those derivations.
static func build(state: MatchState, p_seat: int, p_awaited: int, p_energy: int) -> SeatView:
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
	for index: int in range(2):
		var piles: MatchState.SeatPiles = state.seats[index]
		view.deck_counts[index] = piles.deck.size()
		view.scores[index] = state.scores[index]
		view.wins[index] = state.wins[index]
	view.round_number = state.round_number
	view.turn = state.turn
	view.energy = p_energy
	view.phase = state.phase
	view.awaited_seat = p_awaited
	view.first_seat = state.first_seat
	view.sudden_death = state.sudden_death
	return view


func is_awaited() -> bool:
	return awaited_seat == seat


## The revealed board of either seat, as a copy.
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
		"deck_counts": MatchState.plain(deck_counts),
		"scores": MatchState.plain(scores),
		"wins": MatchState.plain(wins),
		"round": round_number,
		"turn": turn,
		"energy": energy,
		"phase": phase,
		"awaited_seat": awaited_seat,
		"first_seat": first_seat,
		"sudden_death": sudden_death,
	}
