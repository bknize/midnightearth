class_name FullMatchRun
extends RefCounted
## One match played by TestFullMatch and everything the harness saw on the way. Moved out of
## test_full_match.gd at DC-09 T04 (it was TestFullMatch.MatchRun) so the suite stays under
## gdlint's file-length limit; the fields are unchanged but for `memory_hidden_seen`.

var match_seed: int = 0
var engine: MatchEngine = null
## The match's decks as "a/b" (seat 0's, then seat 1's; DC-07 T08).
var pairing: String = ""
var start_ok: bool = false
## Accepted actions.
var actions: int = 0
## True when the harness cap stopped the match.
var capped: bool = false
var end_payload: Dictionary = {}
var max_hand: int = 0
var steps_scanned: int = 0
var face_down_seen: int = 0
var redacted_seen: int = 0
## Prompts the bots answered (DC-05 T05).
var choices: int = 0
## The bot's registry name (BotPlayer.bot_name(); cycle 7 T05).
var bot: String = ""
## The slowest bot choose() call, in microseconds (DC-05 T07), and every call's time in
## play order (cycle 7 T05, R17).
var slowest_us: int = 0
var decision_us: PackedInt32Array = PackedInt32Array()
## The longest walk of the match in pulses (DC-06 T03).
var longest_walk: int = 0
## Destroyed face-down cards the leak scan saw: redacted CARD_DESTROYED and
## DESTROYED_CLEARED events, and destroyed face-down row entries in views (DC-06 T03).
var destroyed_hidden_seen: int = 0
## Opponent destroyed-pile entries the views showed as hidden (DC-07 R18).
var pile_hidden_seen: int = 0
## CARD_RECOVERED events, and those the other seat saw redacted (DC-07 R19).
var recoveries_seen: int = 0
var hidden_recoveries_seen: int = 0
## Memory on hidden cards the other seat saw redacted (cycle 8 R8, R31): a private
## STATS_CHANGED (a growth or cost change on a hand or face-down card) or a private
## CARD_RETURNED (a face-down card returned at turn end).
var memory_hidden_seen: int = 0
## Multi-select prompts the bots answered with a set (DC-07 P13).
var set_answers: int = 0
var rejections: Array[String] = []
var hand_violations: Array[String] = []
var energy_violations: Array[String] = []
var leaks: Array[String] = []
## The leak scan's sets of this step's `before` and `after` states (NSC-97): null until
## the scan builds them; `after`'s become the next step's `before` (TestFullMatch._play).
var sets_before: StateSets = null
var sets_after: StateSets = null


## One full state's leak-scan sets, each indexed by seat: the ids hidden from the other
## seat (TestFullMatch._hidden_set) and the ids the seat holds itself (_own_set).
class StateSets:
	extends RefCounted

	var hidden: Array[Dictionary] = []
	var own: Array[Dictionary] = []
