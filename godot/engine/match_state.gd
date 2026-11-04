class_name MatchState
extends RefCounted
## All mutable match state (plan, data model). MatchEngine is the only writer; readers
## (SeatView, replay) use the fields or to_dict(), the full-state read (R30).
##
## Derived, not stored: the budget (= turn + energy.carry[seat], MatchEngine.budget_for)
## and the awaited seat (from phase and first_seat).
## Card instance ids are seat * DECK_SIZE + definition index (R9, C5).

## NOT_STARTED holds until start() succeeds; the plan's three phases follow it.
enum Phase { NOT_STARTED, AWAIT_FIRST, AWAIT_SECOND, OVER }

var match_seed: int = 0
## Mirror of the engine stream's state, refreshed by the engine after every change.
var rng_state: int = 0
## Counts past MatchRules.ROUNDS in sudden death.
var round_number: int = 0
var turn: int = 0
var sudden_death: bool = false
var phase: int = Phase.NOT_STARTED
## This turn's first committer.
var first_seat: int = 0
## Per seat, indexed by seat number.
var seats: Array[SeatPiles] = []
## The first committer's face-down cards, in commit order (= slot order).
var pending: Array[int] = []
## The final-row slot of each card in `pending` (plan P1, P2); always explicit.
var pending_slots: Array[int] = []
## Per-seat energy state (plan P7).
var energy: EnergyState = EnergyState.new()
## Board scores (the sum of flat on each side until DC-05 T03) and round wins.
var scores: Array[int] = [0, 0]
var wins: Array[int] = [0, 0]
## Winner of the last resolved turn in this round; -1 for a tie or none yet.
var last_turn_winner: int = -1
## Seat that won the most recent won round of the match; -1 until one is won (C9).
var last_round_winner: int = -1
## winner, reason, rounds_played; empty while the match is in progress.
var result: Dictionary = {}
## Accepted actions so far; equals the action log's length.
var actions_applied: int = 0


func _init(p_match_seed: int = 0) -> void:
	match_seed = p_match_seed
	for _seat: int in range(2):
		seats.append(SeatPiles.new())


## The full state as plain data, deep-copied. Two states are equal when these are equal.
## `revealed` is listed per seat as the ascending ids of its revealed cards.
func to_dict() -> Dictionary:
	var decks: Array = []
	var hands: Array = []
	var boards: Array = []
	var burns: Array = []
	var revealed: Array = []
	for piles: SeatPiles in seats:
		decks.append(plain(piles.deck))
		hands.append(plain(piles.hand))
		boards.append(plain(piles.board))
		burns.append(plain(piles.burned))
		revealed.append(plain(piles.revealed_ids()))
	return {
		"seed": match_seed,
		"rng_state": rng_state,
		"round": round_number,
		"turn": turn,
		"sudden_death": sudden_death,
		"phase": phase,
		"first_seat": first_seat,
		"deck": decks,
		"hand": hands,
		"board": boards,
		"revealed": revealed,
		"burned": burns,
		"pending": plain(pending),
		"pending_slots": plain(pending_slots),
		"energy": energy.to_dict(),
		"scores": plain(scores),
		"wins": plain(wins),
		"last_turn_winner": last_turn_winner,
		"last_round_winner": last_round_winner,
		"result": result.duplicate(true),
		"actions_applied": actions_applied,
	}


## An untyped copy, so serialized forms hold plain data only.
static func plain(values: Array[int]) -> Array:
	var out: Array = []
	out.assign(values)
	return out


## One seat's card piles, as ordered instance ids. `board` is the ordered row (R4): a
## card's slot is its index.
class SeatPiles:
	extends RefCounted

	var deck: Array[int] = []
	var hand: Array[int] = []
	var board: Array[int] = []
	var burned: Array[int] = []
	## Cards on the row that have been revealed (plan, MatchState additions).
	var revealed: Dictionary[int, bool] = {}

	## The revealed card ids, ascending.
	func revealed_ids() -> Array[int]:
		var out: Array[int] = []
		out.assign(revealed.keys())
		out.sort()
		return out


## Per-seat energy (plan P7), each pair indexed by seat. The budget is turn + carry; a
## true `free_first` makes the leftmost card of that seat's next commit cost 0 and is
## consumed by that commit; `spent` is what the seat's commit this turn cost.
class EnergyState:
	extends RefCounted

	var carry: Array[int] = [0, 0]
	var free_first: Array[bool] = [false, false]
	var spent: Array[int] = [0, 0]

	func to_dict() -> Dictionary:
		var flags: Array = []
		flags.assign(free_first)
		return {
			"carry": MatchState.plain(carry),
			"free_first": flags,
			"spent": MatchState.plain(spent),
		}
