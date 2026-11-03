class_name BoardStep
extends RefCounted
## One beat of the board's animation queue (R31). BoardSteps builds these from seat-0
## events; Board plays them one at a time. Fields not named by a kind keep their defaults.

enum Kind {
	## Sweep both rows and both hands to the exit (round 2 onwards).
	CLEAR_TABLE,
	## A card sweeps from the entry into `seat`'s fan.
	DEAL,
	## A drawn card sweeps from the entry into `seat`'s fan.
	DRAW,
	## A burned card sweeps from the entry straight to the exit.
	BURN,
	## HUD round, turn and energy; staging resets.
	TURN_START,
	## The bot thinks before its commit.
	BOT_WAIT,
	## `count` face-down cards slide from the opponent's fan onto its row.
	OPPONENT_COMMIT,
	## The viewer's own commit: the cards are already on the row.
	PLAYER_COMMIT,
	## A card flips face up and its power joins `seat`'s score.
	REVEAL,
	## Both displayed scores are set from `scores`.
	TURN_END,
	## The round's winner (`seat`, -1 for a tie) lights a pip; `wins` is the tally.
	ROUND_END,
	## The match is over; `source` keeps the payload.
	MATCH_END,
}

var kind: int = Kind.CLEAR_TABLE
var seat: int = -1
## Instance id; -1 when hidden from the viewer.
var card: int = -1
## Index into the card database; -1 when unknown.
var def_index: int = -1
var power: int = 0
## Cards committed (opponent and player commits).
var count: int = 0
## Engine reveal order (REVEAL).
var order: int = 0
var scores: Array[int] = []
var wins: Array[int] = []
var round_number: int = 0
var turn: int = 0
var energy: int = 0
## Seconds the step plays for, already divided by speed.
var duration: float = 0.0
## Seconds to wait before the step starts, already divided by speed.
var delay: float = 0.0
## The event this step came from.
var source: MatchEvent = null
