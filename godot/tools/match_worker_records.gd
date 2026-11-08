class_name MatchWorkerRecords
extends RefCounted
## The record shapes the headless match worker writes (cycle 7 R24-R26, cycle 11 R7-R8,
## plan P2), as pure builders so a suite can check them without playing a match. Each returns
## a Dictionary the worker writes as one JSON line; `t` is the record kind. Field names are
## the ones scripts/bot/records.py reads.

const KIND_DECISION: String = "d"
const KIND_GAME: String = "g"
const KIND_PAIR: String = "p"
const KIND_END: String = "end"
## Written for a decision field the bot does not expose (no bot API was added for it).
const UNKNOWN: int = -1
## The fields of a decision record, in the plan's order.
const DECISION_FIELDS: Array[String] = [
	"t",
	"seed",
	"game",
	"round",
	"turn",
	"seat",
	"bot",
	"level",
	"legal",
	"previewed",
	"action",
	"best",
	"second",
	"chosen",
	"push",
	"us",
]
const GAME_FIELDS: Array[String] = [
	"t",
	"seed",
	"game",
	"a_seat",
	"decks",
	"winner",
	"rounds",
	"margins",
	"first_seat",
	"first_won",
	"actions",
	"replay_ok",
]
const PAIR_FIELDS: Array[String] = ["t", "seed", "decks", "points_a"]
const END_FIELDS: Array[String] = [
	"t",
	"games",
	"rejected",
	"overruns",
	"overruns_a",
	"overruns_b",
	"replay_mismatches",
	"p95_us",
	"slowest_us",
	"stamp",
	"weights_stamp",
]
## The end record's `weights_stamp` values (cycle 13 R15, plan P6): every weights file used
## carries the current stamp, one does not, or no side has a weights file.
const WEIGHTS_MATCH: String = "match"
const WEIGHTS_MISMATCH: String = "MISMATCH"
const WEIGHTS_NONE: String = "none"


## One `choose` call. `action` is EngineAction.to_dict(); `legal` is the candidate count or
## UNKNOWN (also when the worker runs without --legal, NSC-212); level, previewed, best,
## second, chosen and push are always UNKNOWN (the random bot exposes none).
static func decision(
	match_seed: int,
	game_index: int,
	round_number: int,
	turn: int,
	seat: int,
	bot: String,
	legal: int,
	action: Dictionary,
	us: int
) -> Dictionary:
	return {
		"t": KIND_DECISION,
		"seed": match_seed,
		"game": game_index,
		"round": round_number,
		"turn": turn,
		"seat": seat,
		"bot": bot,
		"level": UNKNOWN,
		"legal": legal,
		"previewed": UNKNOWN,
		"action": action,
		"best": UNKNOWN,
		"second": UNKNOWN,
		"chosen": UNKNOWN,
		"push": UNKNOWN,
		"us": us,
	}


## One finished game. `margins` are the per-round score differences from `a`'s side;
## `first_seat` is the seat that committed first in round 1.
static func game(
	match_seed: int,
	game_index: int,
	a_seat: int,
	deck_ids: Array[String],
	winner: int,
	rounds: int,
	margins: Array[int],
	first_seat: int,
	actions: int,
	replay_ok: bool
) -> Dictionary:
	return {
		"t": KIND_GAME,
		"seed": match_seed,
		"game": game_index,
		"a_seat": a_seat,
		"decks": deck_ids,
		"winner": winner,
		"rounds": rounds,
		"margins": margins,
		"first_seat": first_seat,
		"first_won": winner == first_seat,
		"actions": actions,
		"replay_ok": replay_ok,
	}


## One pentanomial pair record: `points_a` is 0, 0.5, 1, 1.5 or 2.
static func pair(match_seed: int, deck_ids: Array[String], points_a: float) -> Dictionary:
	return {"t": KIND_PAIR, "seed": match_seed, "decks": deck_ids, "points_a": points_a}


## The final record of a worker's file.
static func end(
	games: int,
	rejected: int,
	overruns_a: int,
	overruns_b: int,
	replay_mismatches: int,
	p95_us: int,
	slowest_us: int,
	stamp: String,
	weights_stamp: String
) -> Dictionary:
	return {
		"t": KIND_END,
		"games": games,
		"rejected": rejected,
		"overruns": overruns_a + overruns_b,
		"overruns_a": overruns_a,
		"overruns_b": overruns_b,
		"replay_mismatches": replay_mismatches,
		"p95_us": p95_us,
		"slowest_us": slowest_us,
		"stamp": stamp,
		"weights_stamp": weights_stamp,
	}


## What `a` scored in one game: 1.0 for a win, 0.5 for a draw (winner -1), 0.0 for a loss.
static func game_points(winner: int, a_seat: int) -> float:
	if winner < 0:
		return 0.5
	return 1.0 if winner == a_seat else 0.0


## `a`'s points over the two seat games of one deck pairing: 0, 0.5, 1, 1.5 or 2.
static func pair_points(a_points_seat0_game: float, a_points_seat1_game: float) -> float:
	return a_points_seat0_game + a_points_seat1_game


## The nearest-rank percentile (the ceil(q * n)-th smallest), 0 for no values; the same
## rule as records.py percentile().
static func percentile(values: PackedInt64Array, q: float) -> int:
	if values.is_empty():
		return 0
	var sorted: PackedInt64Array = values.duplicate()
	sorted.sort()
	var rank: int = maxi(0, ceili(q * sorted.size()) - 1)
	return sorted[rank]
