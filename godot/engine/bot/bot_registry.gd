class_name BotRegistry
extends RefCounted
## Every bot by name (cycle 7 R1; cycle 9 R70, R73, P16; cycle 13 R5, R8, R12, plan P4): the
## board, the smoke, the sweep, the workers and the harness build their bots here, so one
## name picks one policy everywhere. The engine ships `random` (the default) and `linear`
## (reached by name only).
##
## make() and make_with() return null on a name they do not know. They never print; the
## launcher reports the error, and prints weights_error() as its one `Bot weights:` line.

## Separates bot seeds from any other derivation of the match seed ("bot" in ASCII). Its
## value is unchanged since cycle 7, so seed_for() is too (R5).
const SEED_TAG: int = 0x626F74
## Every name the registry knows (R70); make() builds every one of them.
const NAMES: Array[String] = ["random", "linear"]


## The bot `name` seeded `bot_seed` over `cards`, `linear` on the committed weights file;
## null for an unknown name.
static func make(name: String, bot_seed: int, cards: MatchCards) -> BotPlayer:
	return make_with(name, bot_seed, cards, "")


## The bot `name` seeded `bot_seed` over `cards`; `linear` is built on the weights file at
## `weights_path` (BotWeights.DEFAULT_PATH when empty), read once per path
## (BotWeights.cached), its defaults when the file is broken (R9). Other bots ignore the
## path. Null for an unknown name.
static func make_with(
	name: String, bot_seed: int, cards: MatchCards, weights_path: String
) -> BotPlayer:
	if name == "random":
		return RandomBot.new(bot_seed, cards)
	if name == "linear":
		return LinearBot.new(bot_seed, cards, BotWeights.cached(weights_path))
	return null


## Why bot `name` would play its built-in default weights: the `load_error` of the file at
## `weights_path` (BotWeights.DEFAULT_PATH when empty); "" when the file is sound or the bot
## reads no weights.
static func weights_error(name: String, weights_path: String) -> String:
	if name != "linear":
		return ""
	return BotWeights.cached(weights_path).load_error


## The bot a seat gets when no name is given (R73; cycle 13 R12): the random bot.
static func default_name() -> String:
	return "random"


## The seed a caller should give the bot playing `seat` in a match seeded `match_seed`.
static func seed_for(match_seed: int, seat: int) -> int:
	var parts: Array[int] = [SEED_TAG, seat]
	return MatchRng.derive_seed(match_seed, parts)
