class_name MatchRng
extends RefCounted
## The engine's only random stream (R1, R2, C3). Wraps one explicitly seeded
## RandomNumberGenerator; nothing here reads the global generator.

# splitmix64 constants as signed 64-bit ints (0x9E3779B97F4A7C15,
# 0xBF58476D1CE4E5B9, 0x94D049BB133111EB).
const _GOLDEN_GAMMA: int = -7046029254386353131
const _MIX_MUL_1: int = -4658895280553007687
const _MIX_MUL_2: int = -7723592293110705685

## Generator state; equal states produce equal future sequences.
var state: int:
	get:
		return _rng.state
	set(value):
		_rng.state = value

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(match_seed: int) -> void:
	_rng.seed = match_seed


## Fisher-Yates shuffle in place, drawing each swap index with randi_range.
func shuffle_in_place(values: Array[int]) -> void:
	var i: int = values.size() - 1
	while i > 0:
		var j: int = _rng.randi_range(0, i)
		var held: int = values[i]
		values[i] = values[j]
		values[j] = held
		i -= 1


## A fair coin: returns 0 or 1.
func coin_flip() -> int:
	return _rng.randi_range(0, 1)


## A uniform index in [0, count - 1]; returns 0 when count < 1.
func pick_index(count: int) -> int:
	if count < 1:
		return 0
	return _rng.randi_range(0, count - 1)


## Pure seed mixing: splitmix64 over the seed, then over each part in order.
static func derive_seed(base_seed: int, parts: Array[int]) -> int:
	var h: int = _splitmix64(base_seed)
	for part: int in parts:
		h = _splitmix64(h ^ part)
	return h


## One splitmix64 step on a wrapping signed 64-bit int.
static func _splitmix64(x: int) -> int:
	var z: int = x + _GOLDEN_GAMMA
	z = (z ^ _shr(z, 30)) * _MIX_MUL_1
	z = (z ^ _shr(z, 27)) * _MIX_MUL_2
	return z ^ _shr(z, 31)


## Logical right shift: `>>` is arithmetic on negative ints, so mask the high bits.
static func _shr(x: int, bits: int) -> int:
	return (x >> bits) & ((1 << (64 - bits)) - 1)
