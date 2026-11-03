class_name ReplayResult
extends RefCounted
## What ActionLog.replay() returns (R33, R34): ok, the replayed engine, the index of the
## first bad action and its error code. `reason` says which check failed.
##
## - ok: every action was accepted; `engine` holds the replayed match.
## - FORMAT_MISMATCH / RULES_MISMATCH: the log names another version; nothing was
##   replayed, `engine` is null, `failed_index` is -1 and `error` is MALFORMED.
## - START_FAILED: start() failed (e.g. CARD_DATA_INVALID); `failed_index` is -1 and
##   `engine` is the unstarted engine.
## - ACTION_REJECTED: the action at `failed_index` was rejected with `error`; `engine`
##   holds the match after the accepted actions before it.

enum Reason { NONE, FORMAT_MISMATCH, RULES_MISMATCH, START_FAILED, ACTION_REJECTED }

var ok: bool = false
var engine: MatchEngine = null
## Index into the log's actions of the first rejected action; -1 when none was rejected.
var failed_index: int = -1
## An EngineError.Code; NONE when ok.
var error: int = EngineError.Code.NONE
var reason: int = Reason.NONE


static func succeeded(p_engine: MatchEngine) -> ReplayResult:
	var result: ReplayResult = ReplayResult.new()
	result.ok = true
	result.engine = p_engine
	return result


static func failed(
	p_reason: int, p_engine: MatchEngine, p_failed_index: int, p_error: int
) -> ReplayResult:
	var result: ReplayResult = ReplayResult.new()
	result.ok = false
	result.reason = p_reason
	result.engine = p_engine
	result.failed_index = p_failed_index
	result.error = p_error
	return result
