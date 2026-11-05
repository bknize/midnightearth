class_name BotPlayer
extends RefCounted
## The base of every bot (cycle 7 R1, R2, plan P1): a pure decision function over one
## seat's redacted SeatView, its own seed, its parameters and the engine's pure previews.
##
## A bot holds no generator between calls. Every draw comes from a fresh generator seeded
## from the bot's seed and the decision (decision_rng), so the same seed, view and
## parameters (on an engine in the state the view was built from) always give the same
## action. A bot reads nothing beyond its own SeatView, asks the engine only for previews
## of its own seat's hypothetical actions, and never writes output, halts or reports
## errors itself.
##
## Subclasses override choose() and bot_name(). The registry (BotRegistry.make) builds
## them by name and sets `level` and `weights`.

## Full strength: the level at which a bot adds no push to its values (R13).
const FULL_LEVEL: int = 20

## 0..20, FULL_LEVEL = full strength. Only bots built on the evaluator read it (R13).
var level: int = FULL_LEVEL
## The bot's parameters (plan P7); the built-in defaults for its name unless the registry
## sets others.
var weights: BotWeights = null

var _bot_seed: int = 0
var _cards: MatchCards = null


## `cards` supplies card stats and costs: the MatchCards of the match the bot plays in
## (MatchEngine.match_cards(), DC-07 P3), so a card is read through its origin's deck.
##
## Null, or a MatchCards whose build failed (is_valid() false), is kept, not reported:
## every card then has cost -1, the only legal set is the empty one, and a bot built on it
## passes every turn. The bot does not signal this itself, since engine code never reports
## errors out of band (R27). It cannot happen through the engine: the engine never builds a
## bot, and a match cannot start without valid cards and decks (CARD_DATA_INVALID,
## DECK_UNKNOWN), so callers that pass the match's own MatchCards always give the bot
## valid data.
func _init(bot_seed: int, cards: MatchCards) -> void:
	_bot_seed = bot_seed
	_cards = cards if cards != null else MatchCards.new()
	weights = BotWeights.defaults(bot_name())


## The action for `view.seat`. `engine` is the match the view was built from, used only
## for previews of `view.seat`. The base bot has no policy and returns null; every
## subclass overrides this and returns an action the engine accepts (R3).
func choose(_view: SeatView, _engine: MatchEngine) -> EngineAction:
	return null


## The bot's registry name (BotRegistry.NAMES); "" for the base.
func bot_name() -> String:
	return ""


## A fresh generator for one decision: seeded MatchRng.derive_seed(bot_seed, [round, turn,
## tag] + extra), from the view's round and turn. `tag` separates the kinds of draw a bot
## makes in one turn (a commit, a prompt answer, a level push); `extra` adds what else
## tells two decisions of the same kind apart (a prompt's source card).
func decision_rng(view: SeatView, tag: int, extra: Array[int] = []) -> MatchRng:
	var parts: Array[int] = [view.round_number, view.turn, tag]
	parts.append_array(extra)
	return MatchRng.new(MatchRng.derive_seed(_bot_seed, parts))
