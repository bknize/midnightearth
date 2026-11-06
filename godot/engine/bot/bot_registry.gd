class_name BotRegistry
extends RefCounted
## Every bot by name (cycle 7 R1; cycle 9 R70, R73, P16): the board, the smoke, the sweep
## and the harness build their bots here, so one name picks one policy everywhere. The
## engine ships one bot, `random`.
##
## make() returns null on a name it does not know. It never prints; the launcher reports
## the error.

## Separates bot seeds from any other derivation of the match seed ("bot" in ASCII). Its
## value is unchanged since cycle 7, so seed_for() is too (R5).
const SEED_TAG: int = 0x626F74
## Every name the registry knows (R70); make() builds every one of them.
const NAMES: Array[String] = ["random"]


## The bot `name` seeded `bot_seed` over `cards`; null for an unknown name.
static func make(name: String, bot_seed: int, cards: MatchCards) -> BotPlayer:
	if name == "random":
		return RandomBot.new(bot_seed, cards)
	return null


## The bot a seat gets when no name is given (R73): the random bot.
static func default_name() -> String:
	return "random"


## The seed a caller should give the bot playing `seat` in a match seeded `match_seed`.
static func seed_for(match_seed: int, seat: int) -> int:
	var parts: Array[int] = [SEED_TAG, seat]
	return MatchRng.derive_seed(match_seed, parts)
