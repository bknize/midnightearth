class_name PreviewPolicy
extends RefCounted
## How a previewed walk decides what a live walk would ask for (plan P12, R35). ScoreWalk.step
## takes one: null means a live walk, which emits events and draws from the engine stream;
## a policy means a preview, which emits nothing and never touches the stream.
##
## The decisions (DC-05 T06):
## - a prompt takes its first option at once, so a preview never pauses (option_for);
## - a random pick (the destroy, P11) takes the opponent's card with the lowest effective
##   flat, the leftmost on a tie, with no draw from any stream (destroy_slot).
## EffectResolver asks the policy for both whenever one is passed. Neither rule reads a
## random stream, so a preview is a function of the state it runs on.
##
## MatchEngine.preview() and preview_choice() run their walks under one of these. The
## policy holds no state, so one instance serves every preview.


## The option a preview takes for a prompt: the first one, or -1 when there is none.
func option_for(options: Array[int]) -> int:
	if options.is_empty():
		return -1
	return options[0]


## The slot in `row` a preview's random destroy takes: the lowest effective flat
## (ScoreWalk.effective), the leftmost on a tie. 0 for an empty row (the caller fizzles an
## empty row before asking). Static, since a live walk given no stream uses the same rule
## (EffectResolver).
static func destroy_slot(state: MatchState, cards: CardDb, row: Array[int]) -> int:
	var best: int = 0
	var best_flat: int = 0
	for i: int in range(row.size()):
		var flat: int = ScoreWalk.effective(row[i], state, cards).x
		if i == 0 or flat < best_flat:
			best = i
			best_flat = flat
	return best
