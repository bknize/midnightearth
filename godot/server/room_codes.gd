class_name RoomCodes
extends RefCounted
## Room codes (cycle 12 spec R12, plan P4): four characters from the capital letters and
## digits without 0, O, 1 and I, unique among live rooms, drawn from a RandomNumberGenerator
## the caller injects (the server seeds it from the clock; a suite seeds it with a number).
## A typed code is accepted whatever its letter case (normalized()). Pure and static.

const ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const LENGTH: int = 4
## Draws fresh() makes before giving up; with at most a handful of live rooms among the
## 32^4 codes a retry is already rare.
const MAX_DRAWS: int = 64


## One code drawn from `rng`, taken or not.
static func draw(rng: RandomNumberGenerator) -> String:
	var out: String = ""
	for _i: int in range(LENGTH):
		var at: int = rng.randi_range(0, ALPHABET.length() - 1)
		out += ALPHABET[at]
	return out


## A code drawn from `rng` that `taken` (codes as keys) does not hold, retried while taken;
## "" after MAX_DRAWS taken draws.
static func fresh(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	for _i: int in range(MAX_DRAWS):
		var code: String = draw(rng)
		if not taken.has(code):
			return code
	return ""


## `typed` as the server keys it: surrounding spaces dropped, letters upper-cased.
static func normalized(typed: String) -> String:
	return typed.strip_edges().to_upper()


## True when `code` is LENGTH characters of ALPHABET (already normalized).
static func is_valid(code: String) -> bool:
	if code.length() != LENGTH:
		return false
	for at: int in range(code.length()):
		if not ALPHABET.contains(code[at]):
			return false
	return true
