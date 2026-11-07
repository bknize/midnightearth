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
	## A card's shown flat, ×-part or +-part changed.
	STATS,
	## One or more cards move between slots in one re-layout: `cards`, `from_slots`, `slots_to`
	## (`card`, `from_slot` and `slot` name the first).
	MOVE,
	## A card returns to its owner's hand.
	RETURN,
	## A hand card is discarded off the exit side.
	DISCARD,
	## WALK_ENDED: the tallies hold `totals` and fly into the HUD scores, which count to
	## `scores` (R77).
	WALK_END,
	## TURN_ENDED: the Scores are final (`scores`, `wins`); no motion.
	TURN_END,
	## The round's winner (`seat`, -1 for a tie) lights a pip; `wins` is the tally.
	ROUND_END,
	## The match is over; `source` keeps the payload.
	MATCH_END,
	## A revealed card flips face down in its slot (CARD_UNREVEALED).
	UNREVEAL,
	## EXIT_RESOLVED (R81): the exit pass resolves a card. `exit_to` is "pile" (it flies to its
	## Owner's Pile), "hand" (to the Owner's fan) or "face_down" (it flips in its slot).
	EXIT,
	## STATUS_SET / STATUS_ENDED: a card gains or loses a badge `word`; `status_on` tells which.
	STATUS,
	## DRAW_EMPTY: a note on `seat`'s deck (R82).
	EMPTY_DRAW,
	## PILE_SHUFFLED_IN: `seat`'s Pile (`count` cards) empties into its Deck (R82).
	SHUFFLE_IN,
	## ENERGY_GRANTED: `seat`'s Budget rises by `amount` (R82).
	ENERGY_GRANT,
	## CARD_LOOKED: the viewer looked at an opposing face-down card (`slot`, `from_seat`).
	LOOK,
	## A Pile strip slides in (the board makes it; no event maps to it).
	PILE_SHOW,
	## The Pile strip slides away.
	PILE_HIDE,
	## A Crew's ability fires (CREW_FIRED): `seat`, `slot`, `crew`, `verb`, `trigger`,
	## `uses_left`. The Crew lifts and settles.
	CREW_FIRE,
	## An optional prompt was declined (CHOICE_DECLINED): the prompt clears.
	DECLINE,
	## The opponent's hand card fires or fizzles (C14, public): its face (`card`) rises above
	## the opponent's hand, holds and goes back; the fan does not change. `verb`, `trigger`,
	## `reason` (a fizzle's, "" when it fired).
	TELEGRAPH,
	## CARD_CREATED onto a row (Twin's copy): a new face-up card appears at `slot` of `seat`'s
	## row. A created card going to a hand is a DRAW with `created` set.
	CREATE,
	## CARD_PLACED (Revive): a Pile card lands face down at `slot` of `seat`'s row.
	PLACE,
	## CONTROL_CHANGED (Saboteur): `card` moves from `from_seat`'s row to `seat`'s (the new
	## Controller) at `slot`. The Owner is kept (`owner`).
	CONTROL,
}

var kind: int = Kind.CLEAR_TABLE
var seat: int = -1
## Instance id; -1 when hidden from the viewer.
var card: int = -1
## The card's shown Power and printed or granted Bonus (STATS, PULSE reveal): `mult` as a
## hundredths multiplier (0 or 100 = none), `add` in hundredths (0 = none).
var power: int = 0
var mult: int = 0
var add: int = 0
## Row index of the card (PULSE, RETURN, MOVE target, EXIT); -1 when not named.
var slot: int = -1
var from_slot: int = -1
## PULSE: the card was already face up, so no flip. STATS and others leave it true.
var revealed: bool = true
## PULSE: whether a CARD_SCORED folded in, the seat's walking total after it (ten-thousandths,
## which may be negative, so `scored` tells whether it is set) and the Bonus value it applied
## (ten-thousandths; SCALE = none).
var scored: bool = false
var total: int = 0
var bonus_value: int = ScoreChips.SCALE
## PULSE: the card already scored this walk (CARD_SCORED `pass` 2), so this is a short pulse.
var again: bool = false
## PULSE (reveal) and CARD_REVEALED: the badge words the card holds.
var statuses: Array[String] = []
## PULSE: seconds after the step starts before its chips show: the flip time on a first
## reveal, so "×M" and "+N" rise once the card is face up; 0 for a revealed card (R31).
var chip_delay: float = 0.0
## MOVE: every moved card (instance id, -1 when hidden) with its row index before and after.
## SHUFFLE_IN: the Pile cards that went into the Deck (Exhume's `pile_cards`; none for a Reset).
var cards: Array[int] = []
var from_slots: Array[int] = []
var slots_to: Array[int] = []
## EXIT: "pile", "hand" or "face_down". DISCARD: whether the card left a row (`from_row`),
## its Pile index and the reason (discard, discard_down, condemned, round_end).
var exit_to: String = ""
var from_row: bool = false
var pile_index: int = -1
## STATUS: the badge word and whether it was set (true) or ended (false).
var word: String = ""
var status_on: bool = true
## STATUS (EXIT_MARKED): the mark the new one replaced ("" when none).
var old_word: String = ""
## ENERGY_GRANT: the Budget added, and whether it lands next Turn (Tithe), so this Turn's
## Energy stays as it is.
var amount: int = 0
var next_turn: bool = false
## DRAW, CREATE (CARD_CREATED): the definition id and the Owner of a created card. CONTROL: the
## Owner, which a change of Controller keeps.
var created: bool = false
var def_id: String = ""
var owner: int = -1
## LOOK, CONTROL: the seat whose row was looked at, or the card left.
var from_seat: int = -1
## WALK_END: both seats' walking totals (ten-thousandths) and the Dross each seat held in hand
## (the engine's own count: a seat with none shows no multiply).
var totals: Array[int] = []
var dross: Array[int] = []
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
## STATS: the card's effective cost after the change (-1 when the event carried none), whether
## the change is kept as card memory, and whether the card is in the viewer's hand (cycle 8
## P16: EffectPlayer.restat_hand).
var cost: int = -1
var permanent: bool = false
var in_hand: bool = false
## PULSE (first reveal): the card carries a grown bonus (public).
var grown: bool = false
## CREW_FIRE: the Crew's id and the uses it has left (-1 unlimited).
var crew: String = ""
var uses_left: int = -1
## EFFECT, FIZZLE: the card fired from the viewer's own hand (C14), so it pulses in the fan.
var from_hand: bool = false
## FIZZLE: "no_target", "exhausted" or "spent".
var reason: String = ""
## CHOICE_SHOW, PROMPT: the zone chosen from and the pick.
var zone: String = ""
## PROMPT: the multi-select's required set size (-1 for any size up to the options), whether
## it is a multi-select or optional, and the drain point it opened at (P12 `step`, D1..D12).
var exact: int = -1
var multi: bool = false
var optional: bool = false
var step: Variant = ""
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
