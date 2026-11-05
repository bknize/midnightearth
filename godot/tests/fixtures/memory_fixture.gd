class_name MemoryFixture
extends RefCounted
## Reads a CardMemory back from its plain form (CardMemory.to_dict()), for tests only. Moved
## out of engine/card_memory.gd at the DC-09 T06 review: the engine never reads a memory
## back (replay rebuilds it from the action log, and there is no MatchState.from_dict), so
## the reader is a test helper, not engine code.


## The memory to_dict() wrote; a missing or non-integer key keeps its default.
static func from_dict(d: Dictionary) -> CardMemory:
	var out: CardMemory = CardMemory.new()
	out.flat = _int_or(d, "flat", out.flat)
	out.times = _int_or(d, "times", out.times)
	out.plus = _int_or(d, "plus", out.plus)
	out.cost = _int_or(d, "cost", out.cost)
	out.uses_left = _int_or(d, "uses_left", out.uses_left)
	return out


## `d[key]` as an int (a whole float included, as JSON gives it), else `fallback`.
static func _int_or(d: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = d.get(key)
	if value is int:
		var whole: int = value
		return whole
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number):
			return int(number)
	return fallback
