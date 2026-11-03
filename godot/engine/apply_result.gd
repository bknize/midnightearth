class_name ApplyResult
extends RefCounted
## What start() or apply() returns (R3, C1): success or a failure code, plus every event
## the call caused, in order. A failure carries no events. T06 adds events_for(seat).

var ok: bool = false
## An EngineError.Code; NONE when ok.
var error: int = EngineError.Code.NONE
## Full events, for tests and replay.
var events: Array[MatchEvent] = []


static func success(p_events: Array[MatchEvent]) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	result.ok = true
	result.error = EngineError.Code.NONE
	result.events.assign(p_events)
	return result


static func failure(code: int) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	result.ok = false
	result.error = code
	return result
