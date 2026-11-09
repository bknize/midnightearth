class_name MatchRules
extends RefCounted
## The match rules, version 7 (cycle 9 plan P1): constants only, no config object.
##
## Rules 7 and log format 5 since DC-13 T02 (spec R65): the v2 card anatomy, pool format 5,
## Crew v2 and deck list v3, so a format-4 log fails replay with FORMAT_MISMATCH. The
## arithmetic is integer: a printed Bonus is in hundredths (BONUS_ONE is ×1.00), the walking
## total and a Bonus value in ten-thousandths (SCALE, plan P7, spec R28).

const ROUNDS: int = 7
const TURNS: int = 7
const WINS_TO_TAKE: int = 4
## The sudden-death Rounds in a row that may tie: the last of them ends the Match in a
## stalemate, so a Match is over after Round 10 at the latest (rules 10, cycle 14 C15).
const SUDDEN_DEATH_TIES: int = 3
## The cards each seat is dealt at Match start (canon R13).
const OPENING_HAND: int = 4
## The base Hand size the discard-down keeps a hand to (canon R14; T03 enforces it).
const HAND_SIZE: int = 4
## The cards in a Deck (canon R18).
const DECK_SIZE: int = 40
## The most copies of one card id a Deck may list (canon R18).
const MAX_COPIES: int = 4
## Each deck names exactly this many different Crew (canon R58).
const CREW_SIZE: int = 3
## The resolutions one pulse or drain point may make before the rest fizzle (canon Q4).
const TRIGGER_BUDGET: int = 50
## Rules 8 since cycle 13 C9 (Ben, 2026-11-08): a tied sudden-death Round with no card
## committed ends the Match in a stalemate (MatchEngine._stalled()). Rules 9 since DC-20 T03
## (cycle 14 R12, C13): a Dross card leaves the Match at the end of the Round
## (CardDef.lifetime, TurnFlow.expire_dross), Level skips face-down cards and a random
## Condemn pick that lands on a protected or Condemned card is a visible miss, so a rules-8
## log is refused at replay. Rules 10 since DC-20 T17a (cycle 14 C15, Ben, 2026-11-09): the
## third tied sudden-death Round in a row ends the Match in a stalemate (SUDDEN_DEATH_TIES),
## so a rules-9 log is refused at replay.
const RULES_VERSION: int = 10
const LOG_FORMAT: int = 5
## Ten-thousandths: the unit of the walking total and of a Bonus value (plan P7).
const SCALE: int = 10000
## ×1.00 (or +1) in hundredths: the unit of a printed or granted Bonus (plan P7).
const BONUS_ONE: int = 100
## The legal printed Mults, in hundredths (×1.25, ×1.5, ×2; canon cards-v2 section 3).
const MULT_VALUES: Array[int] = [125, 150, 200]
## The legal printed Adds, in hundredths (+0.25, +0.5, +1).
const ADD_VALUES: Array[int] = [25, 50, 100]
## The printed Mults below ×1, in hundredths, a named exception the loader also accepts:
## Saboteur's ×0.75 (canon cards-v2 section 3, C27; DC-14 T12).
const MULT_BELOW_ONE: Array[int] = [75]
## The floor of an effective Cost (canon R12): a reduction never takes it lower.
const MIN_COST: int = 0
## The highest printed Cost; the one card above it carries the `cost_on_turn` verb (R12).
const MAX_PRINTED_COST: int = 7
## The derive_seed tag of the seeded deck pairing ("dk"; DC-07 plan P2).
const DECK_TAG: int = 0x646B
