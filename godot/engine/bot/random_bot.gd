class_name RandomBot
extends BotPlayer
## The random bot (cycle 7 R20, C11): a reference floor that chooses uniformly, with its
## per-decision seed, among the legal candidate commits and among a prompt's options.
##
## Commits: one pick_index over GreedyBot.candidates_for(view) (every legal set of the
## view's hand and budget, its ordered variants and both row ends, each a commit the engine
## accepts), drawn from decision_rng(view, COMMIT_TAG). Prompts: a single-target prompt
## picks one of its options by pick_index; a multi-select prompt keeps each option on a
## coin flip, so each of its 2^n subsets (the empty decline among them) is equally likely;
## both draw from decision_rng(view, PROMPT_TAG, [the prompt's source card]).
##
## R2: the bot reads only its own SeatView and its seed; it never asks the engine anything,
## not even for a hypothetical score. R3: every commit is one of the enumerated legal candidates and
## every answer uses only the prompt's offered options, so the engine accepts it.

## Separates the commit draw ("rnd" in ASCII).
const COMMIT_TAG: int = 0x726E64
## Separates a prompt answer's draw from the commit's ("rna").
const PROMPT_TAG: int = 0x726E61


func _init(bot_seed: int, cards: MatchCards) -> void:
	super(bot_seed, cards)


## The registry name (BotRegistry.NAMES).
func bot_name() -> String:
	return "random"


## The action for `view.seat`: a uniform answer while a prompt is open for that seat,
## otherwise a uniform legal commit. `_engine` is not read.
func choose(view: SeatView, _engine: MatchEngine) -> EngineAction:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	if open and asked == view.seat:
		return _answer(view)
	var listed: Array[EngineAction] = GreedyBot.candidates_for(view, _cards)
	if listed.is_empty():
		var none: Array[int] = []
		return EngineAction.commit(view.seat, none, none)
	var rng: MatchRng = decision_rng(view, COMMIT_TAG)
	return listed[rng.pick_index(listed.size())]


## A uniform answer to the prompt open for `view.seat`: a uniform subset of a multi-select
## prompt's options (ascending position), else one uniform option (-1 with none offered).
func _answer(view: SeatView) -> EngineAction:
	var zone: int = view.prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
	var options: Array[int] = Choice.options_of(view.prompt)
	var source: int = view.prompt.get("card", -1)
	var extra: Array[int] = [source]
	var rng: MatchRng = decision_rng(view, PROMPT_TAG, extra)
	if Choice.is_multi_prompt(view.prompt):
		var kept: Array[int] = []
		for option: int in options:
			if rng.coin_flip() == 1:
				kept.append(option)
		kept.sort()
		return EngineAction.choose_set(view.seat, zone, kept)
	if options.is_empty():
		return EngineAction.choose(view.seat, zone, -1)
	return EngineAction.choose(view.seat, zone, options[rng.pick_index(options.size())])
