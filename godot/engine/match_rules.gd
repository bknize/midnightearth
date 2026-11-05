class_name MatchRules
extends RefCounted
## Fixed MVP match rules (C10): constants only, no config object.

const ROUNDS: int = 7
const TURNS: int = 7
const WINS_TO_TAKE: int = 4
const OPENING_HAND: int = 3
const HAND_CAP: int = 7
const DECK_SIZE: int = 20
## 4 and 3 since DC-07 T02: decks per seat, `decks` in the log header (R7, P2). Rules 5
## since DC-09 T01: card memory and effective costs (cycle 8 R29); the log format is unchanged.
const RULES_VERSION: int = 5
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
## The fixed growth steps a memory-writing verb may name, by CardMemory stat (cycle 8 R5,
## R11, plan P1): flat +1 or +2, the ×-part +0.25 or +0.5 (hundredths), the +-part +1, the
## cost -1 or -2. The loader rejects any other amount on those verbs (CardEffect.GROW_STAT).
const GROW_STEPS: Dictionary[String, Array] = {
	"flat": [1, 2],
	"times": [25, 50],
	"plus": [1],
	"cost": [1, 2],
}
## The floor of an effective cost (cycle 8 R4, plan P3): a reduction never takes it lower.
## Printed costs keep CardDb.MIN_COST (1).
const MIN_COST: int = 0
