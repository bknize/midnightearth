class_name LinearBot
extends BotPlayer
## The `linear` bot (cycle 13 spec R5 to R7; plan P3): scores each candidate commit by the
## integer sum of its feature vector (BotFeatures.of over its own view and the candidate)
## times the weights (BotWeights, hundredths) and commits the highest-scoring one.
##
## Commits: the candidates are RandomBot.candidates_for(view, cards) when the hand is
## enumerable (LegalPlays.ENUMERATE_MAX cards or fewer); when they number more than the
## weights' `k`, `k` of them are kept, drawn uniformly (a shuffle of their indices, the first
## `k` kept in ascending order) from decision_rng(view, COMMIT_TAG), except that the pass
## always survives (B-51): it takes the last kept place when the shuffle cut it, for no
## extra draw, so the other kept candidates stay a uniform draw. A hand too large to
## enumerate is sampled as `random` samples it: `k` draws of RandomBot.large_hand_commit from
## that same generator, duplicates dropped, in draw order (R6). Every kept candidate is scored
## in 64-bit integers; the highest wins and a tie is broken by one pick_index over the tied
## candidates (in candidate order) from decision_rng(view, TIE_TAG) (R5).
##
## Prompts: answered by a RandomBot built on the same seed and cards, so the answer equals
## `random`'s for the same seed and view (R7).
##
## R2: the bot reads only its own SeatView, its seed, its weights and the cards' definitions;
## it never asks the engine anything. R3: every commit is one of RandomBot's legal candidates
## (or its large-hand draw), so the engine accepts it.

## Separates the candidate draw ("lin" in ASCII).
const COMMIT_TAG: int = 0x6C696E
## Separates the tie-break draw ("tie").
const TIE_TAG: int = 0x746965

var _weights: BotWeights = null
## The weights laid out in BotFeatures.names(cards) order.
var _vector: PackedInt64Array = PackedInt64Array()
## Answers every prompt (R7).
var _prompts: RandomBot = null


## `p_weights` null takes BotWeights.defaults().
func _init(bot_seed: int, cards: MatchCards, p_weights: BotWeights) -> void:
	super(bot_seed, cards)
	_weights = p_weights if p_weights != null else BotWeights.defaults()
	_vector = _weights.vector_for(_cards)
	_prompts = RandomBot.new(bot_seed, cards)


## The registry name (BotRegistry.NAMES).
func bot_name() -> String:
	return "linear"


## The weights the bot plays (read-only).
func weights() -> BotWeights:
	return _weights


## The action for `view.seat`: `random`'s answer while a prompt is open for that seat,
## otherwise the highest-scoring kept candidate commit. `_engine` is not read.
func choose(view: SeatView, _engine: MatchEngine) -> EngineAction:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	if open and asked == view.seat:
		return _prompts.choose(view, null)
	var kept: Array[EngineAction] = candidates(view)
	if kept.is_empty():
		var none: Array[int] = []
		return EngineAction.commit(view.seat, none, none)
	var common: PackedInt64Array = BotFeatures.base(view, _cards)
	var best: int = 0
	var tied: Array[int] = []
	for index: int in range(kept.size()):
		var value: int = score(BotFeatures.patched(common, view, kept[index], _cards), _vector)
		if tied.is_empty() or value > best:
			best = value
			tied.clear()
			tied.append(index)
		elif value == best:
			tied.append(index)
	if tied.size() == 1:
		return kept[tied[0]]
	var rng: MatchRng = decision_rng(view, TIE_TAG)
	return kept[tied[rng.pick_index(tied.size())]]


## The candidates the bot scores at `view` (see the class comment): at most `k` of them.
func candidates(view: SeatView) -> Array[EngineAction]:
	var k: int = maxi(_weights.k, 1)
	if view.own_hand.size() > LegalPlays.ENUMERATE_MAX:
		return _large_hand(view, k, decision_rng(view, COMMIT_TAG))
	var listed: Array[EngineAction] = RandomBot.candidates_for(view, _cards)
	if listed.size() <= k:
		return listed
	# Built only when drawing; decision_rng is a fresh generator from the view, so the draws
	# do not depend on when it is built.
	var rng: MatchRng = decision_rng(view, COMMIT_TAG)
	var indices: Array[int] = []
	for index: int in range(listed.size()):
		indices.append(index)
	rng.shuffle_in_place(indices)
	var picked: Array[int] = []
	picked.assign(indices.slice(0, k))
	# candidates_for lists the pass first: mask 0 is always legal.
	if not picked.has(0):
		picked[k - 1] = 0
	picked.sort()
	var out: Array[EngineAction] = []
	for index: int in picked:
		out.append(listed[index])
	return out


## The integer sum of `features` times `vector`, over the shorter of the two.
static func score(features: PackedInt64Array, vector: PackedInt64Array) -> int:
	var total: int = 0
	for index: int in range(mini(features.size(), vector.size())):
		var weight: int = vector[index]
		if weight != 0:
			total += features[index] * weight
	return total


## Up to `k` distinct commits of a hand too large to enumerate: `k` draws of
## RandomBot.large_hand_commit from `rng`, duplicates dropped, in draw order.
func _large_hand(view: SeatView, k: int, rng: MatchRng) -> Array[EngineAction]:
	var out: Array[EngineAction] = []
	var seen: Dictionary = {}
	for _draw: int in range(k):
		var action: EngineAction = RandomBot.large_hand_commit(view, _cards, rng)
		# Every draw is a commit by view.seat, so its cards and slots tell it apart.
		var key: String = "%s|%s" % [action.cards, action.slots]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(action)
	return out
