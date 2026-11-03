class_name ActionLog
extends RefCounted
## The replayable action log (R31-R34, C3): a header with the log format, the rules
## version and the match seed, then every accepted action in order. Nothing derived.
##
## JSON form (plan, data model):
## {"format": 1, "rules": 1, "seed": "9007199254740993",
##  "actions": [{"k": "commit", "s": 0, "c": [3, 7]}, {"k": "concede", "s": 1}]}
##
## The seed is a decimal string because JSON numbers lose precision above 2^53. Parsing
## accepts JSON numbers as int or as whole floats and casts them back to int. Malformed
## input gives null from from_json(); a version mismatch parses but fails replay().
## Nothing here prints, asserts or pushes an error.

const KEY_FORMAT: String = "format"
const KEY_RULES: String = "rules"
const KEY_SEED: String = "seed"
const KEY_ACTIONS: String = "actions"
const INT64_MAX_DIGITS: String = "9223372036854775807"
const INT64_MIN_TEXT: String = "-9223372036854775808"
const INT64_MIN: int = -9223372036854775807 - 1
## Larger whole floats cannot be told apart from their neighbours, so they are rejected.
const MAX_SAFE_FLOAT: float = 9007199254740992.0
const CHAR_ZERO: int = 48
const CHAR_NINE: int = 57
const CHAR_MINUS: int = 45

var format_version: int = MatchRules.LOG_FORMAT
var rules_version: int = MatchRules.RULES_VERSION
var match_seed: int = 0
## The accepted actions, in order.
var actions: Array[EngineAction] = []


## A log at the current versions holding copies of `p_actions`.
static func create(p_match_seed: int, p_actions: Array[EngineAction]) -> ActionLog:
	var out_log: ActionLog = ActionLog.new()
	out_log.match_seed = p_match_seed
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
		KEY_ACTIONS: entries,
	}
	return JSON.stringify(data, "", false)


## Parses the JSON form; null when the text is not JSON, a header key is missing or
## mistyped, the seed is not the exact decimal form of a 64-bit int, or any action entry
## is malformed (EngineAction.from_dict). Version values are not checked here: replay()
## reports a mismatch.
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
	for entry: Variant in entries:
		if not entry is Dictionary:
			return null
		var entry_dict: Dictionary = entry
		var action: EngineAction = EngineAction.from_dict(entry_dict)
		if action == null:
			return null
		out_log.actions.append(action)
	return out_log


## Replays the log from a fresh match (R33, R34): checks both versions, creates the
## engine from the seed, starts it and applies every action in order. Stops at the first
## rejected action. Never runs the bot.
func replay(cards: CardDb) -> ReplayResult:
	if format_version != MatchRules.LOG_FORMAT:
		return ReplayResult.failed(
			ReplayResult.Reason.FORMAT_MISMATCH, null, -1, EngineError.Code.MALFORMED
		)
	if rules_version != MatchRules.RULES_VERSION:
		return ReplayResult.failed(
			ReplayResult.Reason.RULES_MISMATCH, null, -1, EngineError.Code.MALFORMED
		)
	var engine: MatchEngine = MatchEngine.create(match_seed, cards)
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
