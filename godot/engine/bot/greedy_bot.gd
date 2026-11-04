class_name GreedyBot
extends RefCounted
## The greedy bot (R35-R38, C8; Phase 3 R7): a pure decision function over one seat's
## redacted SeatView plus its own seed.
##
## choose() lists the legal sets for the view's hand and energy (LegalPlays.enumerate,
## ascending bitmask order), keeps those with the highest total flat (the empty set when
## nothing fits), picks one uniformly with a fresh generator seeded
## MatchRng.derive_seed(bot_seed, [round, turn]), and commits its cards in descending
## flat, then ascending instance id. The opponent's face-down count is ignored.
##
## The bot holds no generator between calls, so the same seed and view always give the
## same action (R37). It never sees the match's own random stream or hidden state; the
## caller asks it only for the awaited seat, and the engine then accepts the commit (R38).
## It never writes output, halts or reports errors itself.

## Separates bot seeds from any other derivation of the match seed ("bot" in ASCII).
const SEED_TAG: int = 0x626F74

var _bot_seed: int = 0
var _cards: CardDb = null


## `cards` supplies card flats and costs; null loads CardDb.load_default(). The plan's
## signature is `_init(bot_seed)`, so the card database is an optional extra.
##
## A card database that failed to load (CardDb.is_valid() false) is kept, not reported:
## every card then has cost -1 and flat 0, the only legal set is the empty one, and
## choose() always commits nothing, so a bot built on it passes every turn. The bot
## does not signal this itself, since engine code never reports errors out of band
## (R27). It cannot happen through the engine: the engine never builds a bot, and a
## match cannot start without a valid card database (CARD_DATA_INVALID), so callers
## that pass the database they started the match with always give the bot valid data.
## Callers relying on the default load should check CardDb.load_default().is_valid().
func _init(bot_seed: int, cards: CardDb = null) -> void:
	_bot_seed = bot_seed
	if cards == null:
		_cards = CardDb.load_default()
	else:
		_cards = cards


## The seed a caller should give the bot playing `seat` in a match seeded `match_seed`.
static func seed_for(match_seed: int, seat: int) -> int:
	var parts: Array[int] = [SEED_TAG, seat]
	return MatchRng.derive_seed(match_seed, parts)


## A commit for `view.seat`: a highest-flat legal set, tie broken by the seeded pick.
func choose(view: SeatView) -> EngineAction:
	var best: Array[Array] = best_sets(view)
	var picked: Array[int] = []
	if not best.is_empty():
		var parts: Array[int] = [view.round_number, view.turn]
		var rng: MatchRng = MatchRng.new(MatchRng.derive_seed(_bot_seed, parts))
		var chosen: Array = best[rng.pick_index(best.size())]
		picked.assign(chosen)
	picked.sort_custom(_plays_before)
	return EngineAction.commit(view.seat, picked)


## Every legal set for the view with the highest total flat, in LegalPlays.enumerate
## order. Each set keeps the hand's order. Holds just the empty set when nothing fits.
func best_sets(view: SeatView) -> Array[Array]:
	var best: Array[Array] = []
	var best_flat: int = -1
	for candidate: Array in LegalPlays.enumerate(view.own_hand, view.energy, _cards):
		var cards: Array[int] = []
		cards.assign(candidate)
		var flat: int = total_flat(cards)
		if flat > best_flat:
			best_flat = flat
			best.clear()
			best.append(cards)
		elif flat == best_flat:
			best.append(cards)
	return best


## The summed flat of a card list; a card with no definition counts 0. Bonus and effects
## are ignored until the preview-driven bot (DC-05 T06).
func total_flat(card_ids: Array[int]) -> int:
	var total: int = 0
	for instance_id: int in card_ids:
		total += flat_of(instance_id)
	return total


## The flat of one card instance (instance id % DECK_SIZE is its definition), or 0.
func flat_of(instance_id: int) -> int:
	if instance_id < 0:
		return 0
	var def: CardDef = _cards.card_at(instance_id % MatchRules.DECK_SIZE)
	if def == null:
		return 0
	return def.flat


## Commit order: higher flat first, then lower instance id.
func _plays_before(a: int, b: int) -> bool:
	var flat_a: int = flat_of(a)
	var flat_b: int = flat_of(b)
	if flat_a != flat_b:
		return flat_a > flat_b
	return a < b
