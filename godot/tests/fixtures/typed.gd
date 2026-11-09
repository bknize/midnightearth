class_name Typed
extends RefCounted
## Typed-array builders for tests: GDScript will not pass a literal `[1, 2]` where an
## `Array[int]` or `Array[String]` is expected, so tests wrap the literal in one of these.


static func ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


static func strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out
