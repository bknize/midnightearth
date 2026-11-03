class_name MatchState
extends RefCounted
## All mutable match state (plan, data model). MatchEngine is the only writer; readers
## (SeatView in T06, replay in T07) use the fields or to_dict(), the full-state read (R30).
##
## Derived, not stored: energy (= turn) and the awaited seat (from phase and first_seat).
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
## The first committer's face-down cards, in commit order.
var pending: Array[int] = []
## Board scores (sum of power on each side) and round wins.
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
func to_dict() -> Dictionary:
	var decks: Array = []
	var hands: Array = []
	var boards: Array = []
	var burns: Array = []
	for piles: SeatPiles in seats:
		decks.append(plain(piles.deck))
		hands.append(plain(piles.hand))
		boards.append(plain(piles.board))
		burns.append(plain(piles.burned))
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
		"burned": burns,
		"pending": plain(pending),
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


## One seat's card piles, as ordered instance ids. `board` is in reveal order.
class SeatPiles:
	extends RefCounted

	var deck: Array[int] = []
	var hand: Array[int] = []
	var board: Array[int] = []
	var burned: Array[int] = []
