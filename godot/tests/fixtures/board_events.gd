class_name BoardEvents
extends RefCounted
## Hand-built MatchEvents for the board suites, made by the NAME of their MatchEvent.Kind
## (the plan's v7 event table, cycle 9), so a suite reads the same before and after the engine
## carries the v7 kinds. A name the enum lacks fails the test that asks for it.


## The event `kind_name` with `payload`, public unless `owner` names a seat.
static func make(
	kind_name: String, payload: Dictionary, owner: int = MatchEvent.PUBLIC
) -> MatchEvent:
	var kind: int = MatchEvent.Kind[kind_name]
	return MatchEvent.new(kind, payload, owner)


## The steps of `events` for `viewer` at `speed`.
static func steps(
	events: Array[MatchEvent], speed: float = 1.0, viewer: int = 0
) -> Array[BoardStep]:
	return BoardSteps.from_events(events, speed, viewer)


## The one step of a single event.
static func one(event: MatchEvent, speed: float = 1.0, viewer: int = 0) -> BoardStep:
	var events: Array[MatchEvent] = [event]
	var made: Array[BoardStep] = steps(events, speed, viewer)
	if made.size() != 1:
		push_error("BoardEvents.one: %d steps" % made.size())
		return BoardStep.new()
	return made[0]
