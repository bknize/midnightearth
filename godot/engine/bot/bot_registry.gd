class_name BotRegistry
extends RefCounted
## Every bot by name (cycle 7 R1, plan P2): the board, autoplay, the smoke, the sweep and the
## harness build their bots here, so one name picks one policy everywhere.
##
## make() returns null on anything it cannot build: an unknown name, a name whose class has
## not landed yet (`greedy_v1` at T02, `tuned` at T04, `matrix` in milestone B), a level
## outside 0..20, and a level below full strength for a bot without an evaluator (`greedy`,
## `greedy_v1`, `random`). It never prints; the launcher reports the error (P16).

## Separates bot seeds from any other derivation of the match seed ("bot" in ASCII). Moved
## from GreedyBot with its value, so seed_for() is unchanged (cycle 7 P1, R5).
const SEED_TAG: int = 0x626F74
## Every name the registry knows, in a fixed order (R1); make() builds those whose class
## exists.
const NAMES: Array[String] = ["greedy", "greedy_v1", "random", "tuned", "matrix"]
## The names whose bots have no evaluator and so take only the full level (P2).
const NO_LEVEL: Array[String] = ["greedy", "greedy_v1", "random"]
## Where a bot's shipped weights live: WEIGHTS_DIR + name + WEIGHTS_SUFFIX (P7).
const WEIGHTS_DIR: String = "res://engine/bot/data/"
const WEIGHTS_SUFFIX: String = "_weights.json"


## The bot `name` seeded `bot_seed` over `cards`, with `weights` (the built-in defaults for
## the name when null) and `level`; null when it cannot be built (see the class comment).
static func make(
	name: String, bot_seed: int, cards: MatchCards, weights: BotWeights, level: int
) -> BotPlayer:
	if not NAMES.has(name) or level < 0 or level > BotPlayer.FULL_LEVEL:
		return null
	if level != BotPlayer.FULL_LEVEL and NO_LEVEL.has(name):
		return null
	var bot: BotPlayer = null
	if name == "greedy":
		bot = GreedyBot.new(bot_seed, cards)
	elif name == "random":
		bot = RandomBot.new(bot_seed, cards)
	if bot == null:
		return null
	bot.level = level
	bot.weights = weights if weights != null else BotWeights.defaults(name)
	return bot


## The bot a seat gets when no name is given (R4): `greedy` until the tuned bot lands
## (cycle 7 T04 switches it to `tuned`).
static func default_name() -> String:
	return "greedy"


## The seed a caller should give the bot playing `seat` in a match seeded `match_seed`.
## Equal to what GreedyBot.seed_for returned before cycle 7, so every golden holds (R5).
static func seed_for(match_seed: int, seat: int) -> int:
	var parts: Array[int] = [SEED_TAG, seat]
	return MatchRng.derive_seed(match_seed, parts)


## The shipped weights file of bot `name`: res://engine/bot/data/<name>_weights.json.
static func default_weights_path(name: String) -> String:
	return WEIGHTS_DIR + name + WEIGHTS_SUFFIX
