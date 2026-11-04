class_name MatchRules
extends RefCounted
## Fixed MVP match rules (C10): constants only, no config object.

const ROUNDS: int = 7
const TURNS: int = 7
const WINS_TO_TAKE: int = 4
const OPENING_HAND: int = 3
const HAND_CAP: int = 7
const DECK_SIZE: int = 20
## 4 and 3 since DC-07 T02: decks per seat, `decks` in the log header (R7, P2).
const RULES_VERSION: int = 4
const LOG_FORMAT: int = 3
## ×1.00 in hundredths: the running mult's start and the neutral ×-part (DC-07 P4).
const MULT_ONE: int = 100
## The legal ×-bonuses, in hundredths (×1.25, ×1.5, ×2; C6, plan P1).
const TIMES_VALUES: Array[int] = [125, 150, 200]
## The legal +bonuses, in whole units (+1, +2; C6, plan P1).
const PLUS_VALUES: Array[int] = [1, 2]
## A card's flat lies within 0..cost + MAX_FLAT_OVER_COST (R3, C13).
const MAX_FLAT_OVER_COST: int = 4
## The burst card destroys itself and a random enemy card at this effective flat (P10).
const BURST_FLAT: int = 5
## The derive_seed tag of the seeded deck pairing ("dk"; plan P2).
const DECK_TAG: int = 0x646B
