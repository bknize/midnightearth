class_name BoardSeeds
extends RefCounted
## Match seeds for the launch path: the `--seed=N` flag, the clock seed and the rematch bump.
## The clock is read here and nowhere else, and only to make a seed.

const SEED_ARG: String = "--seed="
const SEED_MASK: int = 0x7FFFFFFF


## The N of the first `--seed=N` in `args`, or 0 when absent or not a whole number.
static func from_args(args: PackedStringArray) -> int:
	for arg: String in args:
		if arg.begins_with(SEED_ARG):
			var text: String = arg.substr(SEED_ARG.length())
			if text.is_valid_int():
				return text.to_int()
	return 0


## A fresh seed from the clock; never 0.
static func clock_seed() -> int:
	var ticks: int = Time.get_ticks_usec()
	var unix_usec: int = int(Time.get_unix_time_from_system() * 1000000.0)
	var mixed: int = (ticks ^ (unix_usec << 7) ^ (unix_usec >> 11)) & SEED_MASK
	return mixed if mixed != 0 else 1


## The rematch seed (R43): `previous` + 1 when the first seed was fixed, else a fresh clock seed.
static func rematch(was_fixed: bool, previous: int) -> int:
	return bumped(previous) if was_fixed else clock_seed()


## The seed after `previous`, masked; never 0.
static func bumped(previous: int) -> int:
	var next_seed: int = (previous + 1) & SEED_MASK
	return next_seed if next_seed != 0 else 1
