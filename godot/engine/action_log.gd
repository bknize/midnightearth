class_name ActionLog
extends RefCounted
## The replayable action log (R31-R34, C3; DC-07 R7): a header with the log format, the
## rules version, the match seed and both seats' deck ids, then every accepted action in
## order. Nothing derived.
##
## JSON form (DC-07 plan, action log format 3, P2):
## {"format": 3, "rules": 4, "seed": "9007199254740993", "decks": ["ruin", "drift"],
##  "actions": [{"k": "commit", "s": 0, "c": [3, 7], "p": [0, 1]},
##              {"k": "choose", "s": 0, "z": 1, "i": 2},
##              {"k": "choose_set", "s": 1, "z": 1, "i": [0, 2]}, {"k": "concede", "s": 1}]}
## A set choice (DC-07 P7) is logged with its indices as given, so replay applies the same
## set and draws the same random destroys from the stream.
##
## `decks` holds the resolved ids (a seeded pick already applied, MatchEngine.deck_ids()),
## so replay() rebuilds the same decks without drawing a pairing. A header without `decks`
## (every format-2 log) still parses, with empty `deck_ids`, and replay() fails it with
## FORMAT_MISMATCH, as it fails any other format; a log naming only another rules version
## fails with RULES_MISMATCH (R40). A `decks` value that is not two strings is malformed.
##
## Every logged commit carries explicit slots (`p`): the engine resolves the empty,
## append-at-the-end default before it records the action. A format-1 log (commits
## without `p`) still parses, and replay() fails it with FORMAT_MISMATCH.
##
## The seed is a decimal string because JSON numbers lose precision above 2^53. Parsing
## accepts JSON numbers as int or as whole floats and casts them back to int. Malformed
## input gives null from from_json(); a version mismatch parses but fails replay().
## Nothing here prints, asserts or pushes an error.

const KEY_FORMAT: String = "format"
const KEY_RULES: String = "rules"
const KEY_SEED: String = "seed"
const KEY_DECKS: String = "decks"
const KEY_ACTIONS: String = "actions"
const INT64_MAX_DIGITS: String = "9223372036854775807"
const INT64_MIN_TEXT: String = "-9223372036854775808"
const INT64_MIN: int = -9223372036854775807 - 1
## Larger whole floats cannot be told apart from their neighbours, so they are rejected.
## The bound lives in EngineAction, which checks the action entries against it.
const MAX_SAFE_FLOAT: float = EngineAction.MAX_SAFE_FLOAT
const CHAR_ZERO: int = 48
const CHAR_NINE: int = 57
const CHAR_MINUS: int = 45

var format_version: int = MatchRules.LOG_FORMAT
var rules_version: int = MatchRules.RULES_VERSION
var match_seed: int = 0
## Seat 0's and seat 1's deck ids; empty when the header had none (a format mismatch).
var deck_ids: Array[String] = []
## The accepted actions, in order.
var actions: Array[EngineAction] = []


## A log at the current versions holding the deck ids and copies of `p_actions`.
static func create(
	p_match_seed: int, p_deck_ids: Array[String], p_actions: Array[EngineAction]
) -> ActionLog:
	var out_log: ActionLog = ActionLog.new()
	out_log.match_seed = p_match_seed
	out_log.deck_ids.assign(p_deck_ids)
	for action: EngineAction in p_actions:
		if action == null:
			out_log.actions.append(null)
		else:
			out_log.actions.append(action.copy())
	return out_log


func to_json() -> String:
	var entries: Array = []
	for action: EngineAction in actions:
		if action == null:
			entries.append(null)
		else:
			entries.append(action.to_dict())
	var data: Dictionary = {
		KEY_FORMAT: format_version,
		KEY_RULES: rules_version,
		KEY_SEED: str(match_seed),
	}
	# A log parsed from a header without decks writes none back, so it round-trips.
	if not deck_ids.is_empty():
		data[KEY_DECKS] = _plain_strings(deck_ids)
	data[KEY_ACTIONS] = entries
	return JSON.stringify(data, "", false)


## Parses the JSON form; null when the text is not JSON, a header key is missing or
## mistyped, the seed is not the exact decimal form of a 64-bit int, `decks` is present but
## not two strings, or any action entry is malformed (EngineAction.from_dict). Version
## values and a missing `decks` are not checked here: replay() reports a mismatch.
static func from_json(text: String) -> ActionLog:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	var root: Variant = json.data
	if not root is Dictionary:
		return null
	var d: Dictionary = root
	for key: String in [KEY_FORMAT, KEY_RULES, KEY_SEED, KEY_ACTIONS]:
		if not d.has(key):
			return null
	var format_raw: Variant = d[KEY_FORMAT]
	var rules_raw: Variant = d[KEY_RULES]
	if not (_is_whole_number(format_raw) and _is_whole_number(rules_raw)):
		return null
	var seed_raw: Variant = d[KEY_SEED]
	if not seed_raw is String:
		return null
	var seed_text: String = seed_raw
	if not _is_int64_text(seed_text):
		return null
	var actions_raw: Variant = d[KEY_ACTIONS]
	if not actions_raw is Array:
		return null
	var entries: Array = actions_raw
	var out_log: ActionLog = ActionLog.new()
	out_log.format_version = _as_int(format_raw)
	out_log.rules_version = _as_int(rules_raw)
	out_log.match_seed = _parse_int64(seed_text)
	if d.has(KEY_DECKS):
		var parsed_decks: Array[String] = _parse_decks(d[KEY_DECKS])
		if parsed_decks.is_empty():
			return null
		out_log.deck_ids = parsed_decks
	for entry: Variant in entries:
		if not entry is Dictionary:
			return null
		var entry_dict: Dictionary = entry
		var action: EngineAction = EngineAction.from_dict(entry_dict)
		if action == null:
			return null
		out_log.actions.append(action)
	return out_log


## Replays the log from a fresh match (R33, R34; DC-07 R7): checks both versions and that
## the header names both decks, creates the engine from the seed, the pool `cards`, the
## list `decks` and the logged deck ids, starts it and applies every action in order.
## Stops at the first rejected action. Never runs the bot.
func replay(cards: CardDb, decks: DeckList) -> ReplayResult:
	if format_version != MatchRules.LOG_FORMAT or deck_ids.size() != MatchEngine.SEATS:
		return ReplayResult.failed(
			ReplayResult.Reason.FORMAT_MISMATCH, null, -1, EngineError.Code.MALFORMED
		)
	if rules_version != MatchRules.RULES_VERSION:
		return ReplayResult.failed(
			ReplayResult.Reason.RULES_MISMATCH, null, -1, EngineError.Code.MALFORMED
		)
	var engine: MatchEngine = MatchEngine.create(match_seed, cards, decks, deck_ids)
	var started: ApplyResult = engine.start()
	if not started.ok:
		return ReplayResult.failed(ReplayResult.Reason.START_FAILED, engine, -1, started.error)
	for index: int in range(actions.size()):
		var result: ApplyResult = engine.apply(actions[index])
		if not result.ok:
			return ReplayResult.failed(
				ReplayResult.Reason.ACTION_REJECTED, engine, index, result.error
			)
	return ReplayResult.succeeded(engine)


## Two deck ids from a header's `decks` value, or an empty list when it is not an array
## of exactly two strings.
static func _parse_decks(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if not value is Array:
		return out
	var raw: Array = value
	if raw.size() != MatchEngine.SEATS:
		return out
	for entry: Variant in raw:
		if not entry is String:
			out.clear()
			return out
		var deck_id: String = entry
		out.append(deck_id)
	return out


## An untyped copy of the deck ids, for to_json().
static func _plain_strings(values: Array[String]) -> Array:
	var out: Array = []
	out.assign(values)
	return out


## True when `text` is exactly str(n) for some 64-bit int n: an optional minus, then
## digits with no leading zero (except "0" itself), within the int64 range. Checked
## before String.to_int(), which reports an error on overflow.
static func _is_int64_text(text: String) -> bool:
	if text == INT64_MIN_TEXT:
		return true
	var digits: String = text
	if text.length() > 0 and text.unicode_at(0) == CHAR_MINUS:
		digits = text.substr(1)
	if digits.is_empty() or digits.length() > INT64_MAX_DIGITS.length():
		return false
	for i: int in range(digits.length()):
		var code: int = digits.unicode_at(i)
		if code < CHAR_ZERO or code > CHAR_NINE:
			return false
	if digits.length() == INT64_MAX_DIGITS.length() and digits > INT64_MAX_DIGITS:
		return false
	return str(_parse_int64(text)) == text


## Only for text already accepted by _is_int64_text (or that check's own last step).
static func _parse_int64(text: String) -> int:
	if text == INT64_MIN_TEXT:
		return INT64_MIN
	return text.to_int()


## Converts a value already checked by _is_whole_number to int without an unsafe call.
static func _as_int(value: Variant) -> int:
	if value is int:
		var whole: int = value
		return whole
	var number: float = value
	return int(number)


static func _is_whole_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var f: float = value
		return is_finite(f) and f == floorf(f) and absf(f) <= MAX_SAFE_FLOAT
	return false
