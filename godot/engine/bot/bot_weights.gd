class_name BotWeights
extends RefCounted
## A bot's parameters (cycle 7 plan P7): the search caps, the level's push unit and the
## evaluator's feature weights, all whole numbers so every bot stays integer arithmetic and
## deterministic across machines (R18). Feature weights are in hundredths: a weight of 100
## counts a feature once.
##
## Minimal for now (T01): the fields and the built-in defaults. T03 adds load(), to_json(),
## validation and the stamp check.

## The bot these weights are for (the registry name), "" when unnamed.
var bot: String = ""
## The tuned bot's preview cap: how many candidates of the bound ranking are previewed (R7).
var k: int = 48
## The matrix bot's cap on opponent candidates (milestone B).
var k_opp: int = 12
## How many opponent hands the matrix bot samples (milestone B).
var samples: int = 4
## Regret-matching iterations of the matrix bot (milestone B).
var rm_iterations: int = 200
## The level push's spread cap (P6), about one mid card's score at ×1.00.
var push_unit: int = 10
## Feature name -> weight in hundredths (P5).
var weights: Dictionary = {}
## The rules-and-data stamp the weights were trained under (P8); "" for the defaults.
var stamp: String = ""
## Why loading failed ("" when it did not); the defaults are then in force (R11).
var load_error: String = ""


## The built-in weights for `bot_name`: every cap at its default and the plain
## own-minus-opponent score (`score_diff` at 100 hundredths), so a bot on the defaults
## values a candidate exactly as the greedy bot does (R11, R12).
static func defaults(bot_name: String) -> BotWeights:
	var out: BotWeights = BotWeights.new()
	out.bot = bot_name
	out.weights = {"score_diff": 100}
	return out
