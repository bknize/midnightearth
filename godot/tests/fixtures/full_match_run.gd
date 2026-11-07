class_name FullMatchRun
extends RefCounted
## One match played by TestFullMatch (and the sweep) and everything the harness saw on the
## way. Rules 7 (DC-13 T03): the destroyed-pile and recovery counters went with the v6
## piles; the discard-downs, empty draws, Pile entries and looked-at cards the scan met are
## counted instead (the sweep's coverage counters are reset for them at DC-13 T08).

var match_seed: int = 0
var engine: MatchEngine = null
## The match's decks as "a/b" (seat 0's, then seat 1's).
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
## Prompts the bots answered.
var choices: int = 0
## The bot's registry name (BotPlayer.bot_name()).
var bot: String = ""
## The slowest bot choose() call, in microseconds, and every call's time in play order.
var slowest_us: int = 0
var decision_us: PackedInt32Array = PackedInt32Array()
## The longest Walk of the match in pulses.
var longest_walk: int = 0
## Discard-downs the bots answered (rules 7, R13).
var discard_downs: int = 0
## DRAW_EMPTY events the scan saw (R18).
var empty_draws: int = 0
## Opponent Pile entries the views showed (public, R19).
var pile_seen: int = 0
## Looked-at opposing cards the views showed their own seat (R59).
var looked_seen: int = 0
## Memory on hidden cards the other seat saw redacted: a private STATS_CHANGED or
## CARD_RETURNED.
var memory_hidden_seen: int = 0
## Multi-select prompts the bots answered with a set.
var set_answers: int = 0
## Crew prompts the bots answered, optional prompts they declined, and Crew prompts the
## leak scan saw from the asked seat.
var crew_prompts: int = 0
var declines: int = 0
var crew_prompts_scanned: int = 0
var rejections: Array[String] = []
var hand_violations: Array[String] = []
var energy_violations: Array[String] = []
var leaks: Array[String] = []
## The leak scan's sets of this step's `before` and `after` states: null until the scan
## builds them; `after`'s become the next step's `before`.
var sets_before: StateSets = null
var sets_after: StateSets = null


## Every int under an event payload's `card`, `target` (CHOICE_MADE) or `cards` key.
static func event_card_ids(event: MatchEvent) -> Array[int]:
	var out: Array[int] = []
	for key: String in [MatchEvent.KEY_CARD, MatchEvent.KEY_TARGET]:
		var single: Variant = event.payload.get(key)
		if single is int:
			var card: int = single
			if card >= 0:
				out.append(card)
	var many: Variant = event.payload.get(MatchEvent.KEY_CARDS)
	if many is Array:
		var items: Array = many
		for item: Variant in items:
			if item is int:
				var listed: int = item
				if listed >= 0:
					out.append(listed)
	return out


## The kinds that carry Memory on a hidden card when private: a growth or cost change
## (STATS_CHANGED) and a face-down card's return (CARD_RETURNED).
static func is_memory_kind(kind: int) -> bool:
	return kind == MatchEvent.Kind.STATS_CHANGED or kind == MatchEvent.Kind.CARD_RETURNED


## A redacted private STATS_CHANGED the other seat received must show MatchEvent.STATS_HIDDEN's
## neutral values, since a hidden card's effective Power, Bonus and Cost would name it
## through the public deck list; any other value is a leak, recorded on `leaks` at `where`.
func check_neutral_stats(event: MatchEvent, where: String) -> void:
	if event.kind != MatchEvent.Kind.STATS_CHANGED:
		return
	for key: Variant in MatchEvent.STATS_HIDDEN:
		if event.payload.get(key) != MatchEvent.STATS_HIDDEN[key]:
			leaks.append(where + ": redacted STATS_CHANGED shows its %s" % key)


## One full state's leak-scan sets, each indexed by seat: the ids hidden from the other
## seat and the ids the seat knows itself.
class StateSets:
	extends RefCounted

	var hidden: Array[Dictionary] = []
	var own: Array[Dictionary] = []
