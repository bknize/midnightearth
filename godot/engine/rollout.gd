class_name Rollout
extends RefCounted
## The rollout entry (cycle 11 spec R16 to R24; plan P5 to P8, P10): determinized copies of
## a running match and play-outs on them, for the play-out worker and the tests only. No
## bot, board or scene calls it (R24); nothing here is on the shipped decision path. Static
## functions only, pure over their inputs: every draw comes from a generator seeded from
## the determinization or label seed, never from the real match's stream (R18).
##
## Determinization (P6, R17). From `seat`'s view, a card is hidden when it is in the other
## seat's hand, the other seat's face-down Commit (`pending` while the other seat is the
## first committer), face down on the other seat's row and not in the view's `looked`, in
## the other seat's Deck, or in `seat`'s own Deck and not in the view's `deck_top`. The
## hidden cards are split by Owner (MatchCards.origin_of, Dross cards included: they are
## hidden like any other), and each Owner's set is permuted with one MatchRng seeded by the
## determinization seed (owner 0's set first). The copy's zone arrays are rewritten through
## that mapping, so every zone keeps its count and every slot its position, and a card
## never changes Owner. What belongs to a card moves with its identity: its Memory and a
## Dross card's definition stay keyed by its id, so they follow the card to wherever the
## permutation puts it. What belongs to a row slot stays with the slot: the Board changes
## (`card_states`) and the kept choices (`chosen`) are re-keyed through the mapping, so a
## status on a face-down slot stays on that slot whichever card now lies there. Cards a
## queued or paused trigger names (never at a commit decision, where the queue is idle)
## keep their identity, so the queue stays coherent. The seat's view of the copy equals its
## view of the original.
##
## Play-out (P5, P8, R20 to R22): the candidate is applied for `seat`, then the policy bot
## (BotRegistry, seeded MatchRng.derive_seed(det_seed, [seat])) answers every decision of
## both seats, prompts included, until the match ends or `cap` actions (the candidate
## counted) have been applied. Value: 1000 * result + 10 * (wins[seat] - wins[other]),
## result 1 for a win, 0 for a draw, -1 for a loss; a capped play-out is a draw on the
## result term. A candidate the copy refuses is `rejected` with value 0.

## The action cap of a play-out: FullMatchHarness.MAX_ACTIONS (spec Clarifications).
const DEFAULT_CAP: int = 2000
## The tag of the copy's stream seed, "rol" in ASCII (P7).
const ROLLOUT_TAG: int = 0x726F6C
## The tag of the candidate sampler's seed, "can" in ASCII (P10).
const CANDIDATE_TAG: int = 0x63616E
const RESULT_WEIGHT: int = 1000
const WINS_WEIGHT: int = 10
## The ctx.data keys of a paused drain that hold card ids (R18): Quorum's kept cards
## (AbilitiesComboDisruption.DATA_KEPT) and Cull's kept cards per seat
## (AbilitiesGraveyardControl.DATA_KEPT). Every other data key is a number that is not a
## card (Delve's `count`, Quorum's `stage`, Cull's `asked`).
const PAUSED_CARD_LISTS: Array[String] = ["kept", "kept_0", "kept_1"]
## The card list of a Batch a paused effect woke (TriggerContext.wake()).
const WOKEN_SUBJECTS: String = "subjects"


## The cards hidden from `seat` in `engine`'s match, per Owner: [owner 0's, owner 1's], each
## ascending. Exactly the sets determinize() permutes. Empty sets for a seat other than 0
## or 1.
static func hidden_sets(engine: MatchEngine, seat: int) -> Array[Array]:
	var view: SeatView = engine.view_for(seat)
	if view == null:
		var none: Array[Array] = [[], []]
		return none
	return _hidden_of(engine.state_copy(), engine.match_cards(), view)


## A determinized copy of `engine`'s match for `seat` (see the class comment), its stream
## seeded MatchRng.derive_seed(det_seed, [ROLLOUT_TAG]) (P7). `engine` is only read. Null
## for a seat other than 0 or 1.
static func determinize(engine: MatchEngine, seat: int, det_seed: int) -> MatchEngine:
	var view: SeatView = engine.view_for(seat)
	if view == null:
		return null
	var state: MatchState = engine.state_copy()
	var sets: Array[Array] = _hidden_of(state, engine.match_cards(), view)
	return _built(engine, state, _mapping_of(sets, det_seed), det_seed)


## Plays `copy` out from `candidate` for `seat` (see the class comment) and returns
## {value, result, wins: [seat 0's, seat 1's], actions, capped, rejected}. `copy` is
## changed; build a fresh one per play-out. A bot the registry cannot build, a decision no
## bot can take, or a bot action the copy refuses ends the play-out as `rejected` (no value,
## not counted in `n`): a broken rollout policy, never a draw (T06 review). Both seats' bots
## come from BotRegistry.make_with(policy, …, `weights_path`): a `linear` policy plays the
## weights file there (the committed file when empty); `random` ignores it (cycle 13 P5).
static func play(
	copy: MatchEngine,
	seat: int,
	candidate: EngineAction,
	policy: String,
	det_seed: int,
	cap: int = DEFAULT_CAP,
	weights_path: String = ""
) -> Dictionary:
	if seat < 0 or seat >= MatchEngine.SEATS or candidate == null or candidate.seat != seat:
		return _rejected(copy)
	if not copy.apply(candidate).ok:
		return _rejected(copy)
	var bots: Array[BotPlayer] = []
	for bot_seat: int in range(MatchEngine.SEATS):
		var parts: Array[int] = [bot_seat]
		var bot_seed: int = MatchRng.derive_seed(det_seed, parts)
		bots.append(BotRegistry.make_with(policy, bot_seed, copy.match_cards(), weights_path))
	var actions: int = 1
	var capped: bool = false
	while not copy.is_over():
		if actions >= cap:
			capped = true
			break
		var awaited: int = copy.awaited_seat()
		if awaited < 0 or awaited >= MatchEngine.SEATS or bots[awaited] == null:
			return _rejected(copy)
		var bot: BotPlayer = bots[awaited]
		var action: EngineAction = bot.choose(copy.view_for(awaited), copy)
		if action == null or not copy.apply(action).ok:
			return _rejected(copy)
		actions += 1
	return _outcome(copy, seat, actions, capped)


## Labels each of `candidates` for `seat` at `engine`'s decision point (P10): one play-out
## under `policy` on each of `determinizations` copies, determinization seed
## MatchRng.derive_seed(label_seed, [determinization index]): every candidate is played
## on the same deals (common random numbers, /cycle test DC-16 review F1). One
## dictionary per candidate, in order: {mean, spread, n, wins, draws, losses, capped,
## rejected}; `n` counts the play-outs that were not rejected (R22: a rejected one has no
## value and is not counted), `mean` is their mean value rounded half up and `spread` the
## floor of their population standard deviation, both 0 when `n` is 0; `wins`, `draws`
## and `losses` count their results (a capped play-out is a draw, also counted in
## `capped`); `rejected` counts the rejected play-outs. `engine` is only read (R19).
## `weights_path` goes to every play() (cycle 13 P5).
static func label(
	engine: MatchEngine,
	seat: int,
	candidates: Array[EngineAction],
	determinizations: int,
	policy: String,
	label_seed: int,
	weights_path: String = ""
) -> Array[Dictionary]:
	# The view and the hidden sets are the same for every play-out of the position, and so
	# is each determinization's relabelled state for every candidate (NSC-210, NSC-233): work
	# them out once. Each play-out still gets its own copy of that state and, through
	# from_state, its own MatchCards copy, since what a play-out changes and the cards it
	# creates must not reach the next one.
	var view: SeatView = engine.view_for(seat)
	var det_seeds: Array[int] = []
	var deals: Array[MatchState] = []
	if view != null:
		var sets: Array[Array] = _hidden_of(engine.state_copy(), engine.match_cards(), view)
		for det: int in range(determinizations):
			var parts: Array[int] = [det]
			var det_seed: int = MatchRng.derive_seed(label_seed, parts)
			det_seeds.append(det_seed)
			var deal: MatchState = engine.state_copy()
			_relabel(deal, _mapping_of(sets, det_seed))
			deals.append(deal)
	var out: Array[Dictionary] = []
	for index: int in range(candidates.size()):
		var values: Array[int] = []
		var counts: Dictionary = {"wins": 0, "draws": 0, "losses": 0, "capped": 0, "rejected": 0}
		for det: int in range(determinizations):
			var played: Dictionary = {"rejected": true}
			if view != null:
				var det_seed: int = det_seeds[det]
				var copy: MatchEngine = _on_state(engine, deals[det].duplicate(), det_seed)
				played = play(
					copy, seat, candidates[index], policy, det_seed, DEFAULT_CAP, weights_path
				)
			_count(played, values, counts)
		out.append(_summary(values, counts))
	return out


## `k` distinct indices of `count` candidates, ascending (P10): all of them when `k` is at
## least `count`, else the first `k` of a shuffle of 0 .. count - 1 by
## MatchRng.new(MatchRng.derive_seed(label_seed, [CANDIDATE_TAG])). Empty for a `count` or
## `k` below 1.
static func sample_indices(count: int, k: int, label_seed: int) -> Array[int]:
	var out: Array[int] = []
	if count < 1 or k < 1:
		return out
	for index: int in range(count):
		out.append(index)
	if k >= count:
		return out
	var parts: Array[int] = [CANDIDATE_TAG]
	var rng: MatchRng = MatchRng.new(MatchRng.derive_seed(label_seed, parts))
	rng.shuffle_in_place(out)
	var picked: Array[int] = out.slice(0, k)
	picked.sort()
	return picked


# --- Determinization ------------------------------------------------------------------


## The permutation of the hidden `sets` (from _hidden_of) for `det_seed`: each Owner's set
## shuffled by one MatchRng seeded `det_seed`, owner 0's set first; a card to the card that
## takes its place. `sets` is only read.
static func _mapping_of(sets: Array[Array], det_seed: int) -> Dictionary[int, int]:
	var rng: MatchRng = MatchRng.new(det_seed)
	var mapping: Dictionary[int, int] = {}
	for owned: Array in sets:
		var from: Array[int] = []
		from.assign(owned)
		var to: Array[int] = []
		to.assign(owned)
		rng.shuffle_in_place(to)
		for index: int in range(from.size()):
			mapping[from[index]] = to[index]
	return mapping


## The determinized copy: `state` (a copy of `engine`'s, taken over) relabelled through
## `mapping`, see _on_state.
static func _built(
	engine: MatchEngine, state: MatchState, mapping: Dictionary[int, int], det_seed: int
) -> MatchEngine:
	_relabel(state, mapping)
	return _on_state(engine, state, det_seed)


## An engine on `state` (already relabelled, taken over), around a copy of `engine`'s cards,
## its stream seeded MatchRng.derive_seed(det_seed, [ROLLOUT_TAG]) (P7).
static func _on_state(engine: MatchEngine, state: MatchState, det_seed: int) -> MatchEngine:
	var stream_parts: Array[int] = [ROLLOUT_TAG]
	var stream_seed: int = MatchRng.derive_seed(det_seed, stream_parts)
	return MatchEngine.from_state(state, engine.match_cards(), stream_seed)


## The hidden sets of `state` from `view` (its seat's view of the same state): see the
## class comment. [owner 0's, owner 1's], each ascending, without the cards _pinned() keeps.
static func _hidden_of(state: MatchState, cards: MatchCards, view: SeatView) -> Array[Array]:
	var own: MatchState.SeatPiles = state.seats[view.seat]
	var other: MatchState.SeatPiles = state.seats[view.opponent]
	var known: Dictionary[int, bool] = _pinned(state)
	for slot: int in view.looked:
		known[view.looked[slot]] = true
	for card: int in view.deck_top:
		known[card] = true
	var hidden: Array[int] = []
	hidden.append_array(other.hand)
	if state.first_seat == view.opponent:
		hidden.append_array(state.pending)
	for card: int in other.board:
		if not other.is_revealed(card):
			hidden.append(card)
	hidden.append_array(other.deck)
	hidden.append_array(own.deck)
	var by_owner: Array[Array] = [[], []]
	for card: int in hidden:
		var owner: int = cards.origin_of(card)
		if known.has(card) or owner < 0 or owner >= MatchEngine.SEATS:
			continue
		var owned: Array = by_owner[owner]
		owned.append(card)
	var out: Array[Array] = []
	for owned: Array in by_owner:
		var ids: Array[int] = []
		ids.assign(owned)
		ids.sort()
		out.append(ids)
	return out


## The cards the trigger queue names and the open prompt's source: they keep their
## identity in a copy (R18). A queued entry's card and subject; while a drain is paused, the
## kept entry's card and subject, the ids under PAUSED_CARD_LISTS in its data and the
## subjects of the Batches it woke; never any other number (an amount, a slot, a stage).
## Empty at a commit decision.
static func _pinned(state: MatchState) -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	for batch: Dictionary in state.queue.batches:
		var entries: Array = batch.get("entries", [])
		for raw: Variant in entries:
			if raw is Dictionary:
				var entry: Dictionary = raw
				_pin_entry(entry, out)
	if state.queue.is_paused():
		_pin_paused(state.queue.current, out)
	if not state.prompt.is_empty():
		_pin_value(state.prompt.get(Abilities.KEY_CARD, -1), out)
	return out


## Pins a queue entry's card and subject.
static func _pin_entry(entry: Dictionary, out: Dictionary[int, bool]) -> void:
	_pin_value(entry.get("card", -1), out)
	_pin_value(entry.get("subject", -1), out)


## Pins the card ids of a paused drain's kept record (TriggerQueue `current`): its entry's
## card and subject, the card lists of its data and the subjects of the Batches it woke.
static func _pin_paused(current: Dictionary, out: Dictionary[int, bool]) -> void:
	var held_entry: Variant = current.get("entry", {})
	if held_entry is Dictionary:
		var entry: Dictionary = held_entry
		_pin_entry(entry, out)
	var held_data: Variant = current.get("data", {})
	if held_data is Dictionary:
		var data: Dictionary = held_data
		for key: String in PAUSED_CARD_LISTS:
			_pin_list(data.get(key, []), out)
	var woken: Variant = current.get("woken", [])
	if woken is Array:
		var batches: Array = woken
		for raw: Variant in batches:
			if raw is Dictionary:
				var batch: Dictionary = raw
				_pin_list(batch.get(WOKEN_SUBJECTS, []), out)


## Pins each id of `value` when it is a list of card ids.
static func _pin_list(value: Variant, out: Dictionary[int, bool]) -> void:
	if not (value is Array):
		return
	var listed: Array = value
	for item: Variant in listed:
		_pin_value(item, out)


## Pins `value` when it is a whole number naming a card (not negative).
static func _pin_value(value: Variant, out: Dictionary[int, bool]) -> void:
	if not EngineAction.is_whole_number(value):
		return
	var card: int = EngineAction.as_int(value)
	if card >= 0:
		out[card] = true


## Rewrites `state`'s zones through `mapping` (a card to the card that takes its place, a
## permutation within each hidden set) and re-keys the slot records (`card_states`,
## `chosen`); Memory and Dross cards stay keyed by identity.
static func _relabel(state: MatchState, mapping: Dictionary[int, int]) -> void:
	if mapping.is_empty():
		return
	for held: MatchState.SeatPiles in state.seats:
		_map_ids(held.deck, mapping)
		_map_ids(held.hand, mapping)
		_map_ids(held.board, mapping)
	_map_ids(state.pending, mapping)
	var moved: Dictionary[int, CardState] = {}
	for card: int in state.card_states:
		moved[_mapped(card, mapping)] = state.card_states[card]
	state.card_states = moved
	var kept: Dictionary[int, int] = {}
	for source: int in state.chosen:
		kept[_mapped(source, mapping)] = _mapped(state.chosen[source], mapping)
	state.chosen = kept


## Replaces each id of `ids` in place by its mapped id.
static func _map_ids(ids: Array[int], mapping: Dictionary[int, int]) -> void:
	for index: int in range(ids.size()):
		ids[index] = _mapped(ids[index], mapping)


## The id that takes `card`'s place: its mapped id, or itself when it is not hidden.
static func _mapped(card: int, mapping: Dictionary[int, int]) -> int:
	if mapping.has(card):
		return mapping[card]
	return card


# --- Outcomes -------------------------------------------------------------------------


## A refused candidate (R22): no value, the copy unchanged.
static func _rejected(copy: MatchEngine) -> Dictionary:
	var wins: Array = MatchState.plain(copy.round_wins())
	return {
		"value": 0,
		"result": 0,
		"wins": wins,
		"actions": 0,
		"capped": false,
		"rejected": true,
	}


## The outcome of a play-out of `actions` actions on `copy` for `seat` (P8, R21, R22).
static func _outcome(copy: MatchEngine, seat: int, actions: int, capped: bool) -> Dictionary:
	var wins: Array[int] = copy.round_wins()
	var own_wins: int = wins[seat]
	var other_wins: int = wins[1 - seat]
	var result: int = 0
	if not capped:
		var winner: int = copy.match_winner()
		if winner == seat:
			result = 1
		elif winner == 1 - seat:
			result = -1
	return {
		"value": RESULT_WEIGHT * result + WINS_WEIGHT * (own_wins - other_wins),
		"result": result,
		"wins": MatchState.plain(wins),
		"actions": actions,
		"capped": capped,
		"rejected": false,
	}


## Adds one play-out's outcome `played` to a candidate's `values` and `counts`.
static func _count(played: Dictionary, values: Array[int], counts: Dictionary) -> void:
	var refused: bool = played.get("rejected", false)
	if refused:
		_bump(counts, "rejected")
		return
	var value: int = played.get("value", 0)
	var result: int = played.get("result", 0)
	var capped: bool = played.get("capped", false)
	values.append(value)
	var key: String = "draws"
	if result > 0:
		key = "wins"
	elif result < 0:
		key = "losses"
	_bump(counts, key)
	if capped:
		_bump(counts, "capped")


## Adds one to the count under `key`.
static func _bump(counts: Dictionary, key: String) -> void:
	var held: int = counts.get(key, 0)
	counts[key] = held + 1


## One candidate's label from its play-out `values` and `counts` (see label()).
static func _summary(values: Array[int], counts: Dictionary) -> Dictionary:
	var n: int = values.size()
	var total: int = 0
	var squares: int = 0
	for value: int in values:
		total += value
		squares += value * value
	var mean: int = 0
	var spread: int = 0
	if n > 0:
		mean = Scoring.round_half_up(total, n)
		@warning_ignore("integer_division")
		var variance: int = (n * squares - total * total) / (n * n)
		spread = _isqrt(variance)
	return {
		"mean": mean,
		"spread": spread,
		"n": n,
		"wins": counts.get("wins", 0),
		"draws": counts.get("draws", 0),
		"losses": counts.get("losses", 0),
		"capped": counts.get("capped", 0),
		"rejected": counts.get("rejected", 0),
	}


## The floor of the square root of `x` (0 for x below 1), in whole numbers only.
static func _isqrt(x: int) -> int:
	if x < 1:
		return 0
	var root: int = x
	@warning_ignore("integer_division")
	var next: int = (root + x / root) / 2
	while next < root:
		root = next
		@warning_ignore("integer_division")
		next = (root + x / root) / 2
	return root
