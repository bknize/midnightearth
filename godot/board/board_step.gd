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
	## The walk begins: both displayed scores go to 0 and both mults to 1.
	WALK_START,
	## The cursor pulses a card; `revealed = false` means it flips face up first.
	PULSE,
	## A card's effect fires (`verb`, `trigger`).
	EFFECT,
	## A card's effect found no target.
	FIZZLE,
	## The viewer's own prompt opens. Untimed: it waits on the player (T12).
	PROMPT,
	## A choice was made (the bot's pick glows); `zone`, `index`, `target`.
	CHOICE_SHOW,
	## A card's shown flat and bonus changed.
	STATS,
	## A card is destroyed.
	DESTROY,
	## A card moves between slots (`from_slot` to `slot`).
	MOVE,
	## A card returns to its owner's hand.
	RETURN,
	## A hand card is discarded off the exit side.
	DISCARD,
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
var flat: int = 0
var bonus: int = 0
## Row index of the card (PULSE, DESTROY, RETURN, MOVE target); -1 when not named.
var slot: int = -1
var from_slot: int = -1
## PULSE: the card was already face up, so no flip. STATS and others leave it true.
var revealed: bool = true
## PULSE: the seat's multiplier, the points this pulse added and the seat's running score
## (-1 when the engine sent no CARD_SCORED for the card).
var mult: int = 1
var added: int = 0
var score: int = -1
## Cards committed (opponent and player commits).
var count: int = 0
## Row slots of the committed cards (commits).
var slots: Array[int] = []
## Engine reveal order (PULSE when the card was first revealed).
var order: int = 0
## TURN_START: the viewer's budget for the turn (turn plus carry) and whether its first
## card is free.
var budget: int = 0
var free_first: bool = false
## EFFECT, FIZZLE, PROMPT: the effect verb; EFFECT: the trigger; PROMPT: the rules text.
var verb: String = ""
var trigger: String = ""
var text: String = ""
## STATS: why the numbers changed.
var cause: String = ""
## CHOICE_SHOW, PROMPT: the zone chosen from and the pick.
var zone: String = ""
var index: int = -1
var target: int = -1
var options: Array[int] = []
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
