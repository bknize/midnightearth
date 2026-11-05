# gdlint: disable=max-file-lines, max-public-methods
class_name TestSeatView
extends GdUnitTestSuite
## Hidden information (C4): R28 (a redacted view per seat holding the listed fields), R29
## (no opponent hand, deck, face-down or burn id and no seed or deck order in the view or
## in the per-seat events) and R30 (the full-state read holds everything the views omit).
##
## Mid-match states come from scripted actions on known seeds, never from private fields.
## The scripted run is start() plus round 1's 14 commits plus 2 commits into round 2: the
## "player" seat commits the first legal single card each time it is awaited and the
## other seat always passes, so the player wins turns and commits first (a face-down
## commit to hide) and the passer reaches the hand cap and burns (a burn pile to hide).
## Each run is played once with each seat as the player.
## DC-05 R7: while awaited second, a seat sees the first committer's slots but not its
## cards. Both seats' budgets are in every view. DC-05 R34 (T05): the scripted runs answer
## any prompt with its first option; the prompt and choice events and the view's prompt hold
## no hand id for the other seat, and a face-down row card shows no id mid-walk.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
## Large seeds, so a leaked seed cannot hide among the small ints of a view (counts,
## rounds, card ids).
const LEAK_SEEDS: Array[int] = [9_000_000_001, 123_456_789_012, 4_611_686_018_427_387_905]
const SCRIPT_COMMITS: int = 2 * 7 + 2
## Keys whose int values are card instance ids, in views and event payloads.
const CARD_KEYS: Array[String] = [
	"card",
	"cards",
	"target",
	"own_hand",
	"own_pending",
	"own_board",
	"opponent_board",
	"own_destroyed",
	"opponent_destroyed",
]
const VIEW_KEYS: Array[String] = [
	"seat",
	"opponent",
	"deck_ids",
	"own_hand",
	"own_hand_row",
	"own_hand_costs",
	"own_pending",
	"own_board",
	"opponent_board",
	"own_row",
	"opponent_row",
	"own_destroyed",
	"opponent_destroyed",
	# DC-09 T06 review: the known destroyed-pile cards' faces, memory included.
	"pile_entries",
	"opponent_hand_count",
	"opponent_pending_count",
	"opponent_pending_slots",
	"deck_counts",
	"scores",
	"mults",
	"wins",
	"round",
	"turn",
	"energy",
	"budgets",
	"free_first",
	"phase",
	"awaited_seat",
	"first_seat",
	"sudden_death",
	"prompt",
	# DC-11 T08 (cycle 8 R42, R43): both seats' Crew and their uses, public.
	"crew",
	"crew_uses",
]
## Full-state keys that carry what the views omit.
const HIDDEN_STATE_KEYS: Array[String] = ["seed", "rng_state", "deck", "hand", "pending", "burned"]
const PRIVATE_KINDS: Array[int] = [
	MatchEvent.Kind.CARD_DEALT,
	MatchEvent.Kind.CARD_DRAWN,
	MatchEvent.Kind.CARD_BURNED,
	MatchEvent.Kind.COMMITTED,
]
## Private in some cases only (DC-05): the destroy or move of a face-down card, a choice
## of a hand or face-down card, and (public) the burn of a returned, revealed card; the
## turn-end clear of a destroyed card never revealed (DC-06 R21).
const SPLIT_KINDS: Array[int] = [
	MatchEvent.Kind.CARD_DESTROYED,
	MatchEvent.Kind.DESTROYED_CLEARED,
	MatchEvent.Kind.CARD_MOVED,
	MatchEvent.Kind.CHOICE_MADE,
	MatchEvent.Kind.CARD_BURNED,
	MatchEvent.Kind.CARD_RECOVERED,
]
## Kinds that may name a card in a hand, so the R34 case checks them.
const PROMPT_KINDS: Array[int] = [
	MatchEvent.Kind.CHOICE_REQUESTED,
	MatchEvent.Kind.CHOICE_MADE,
	MatchEvent.Kind.CARD_DISCARDED,
]
## Definition index of c09 (draw 2, then discard 1).
const C09_DRAW_DISCARD: int = 8

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## The fixture-vs-fixture definitions over _db() (DC-07 T02), for LegalPlays.
func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	engine.start()
	return engine


func _state_list(state: Dictionary, key: String, seat: int) -> Array[int]:
	var per_seat: Array = state[key]
	var raw: Array = per_seat[seat]
	return _typed(raw)


func _state_ints(state: Dictionary, key: String) -> Array[int]:
	var raw: Array = state[key]
	return _typed(raw)


func _state_int(state: Dictionary, key: String) -> int:
	var value: int = state[key]
	return value


func _hand(engine: MatchEngine, seat: int) -> Array[int]:
	return _state_list(engine.full_state(), "hand", seat)


func _payload_int(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _payload_ints(event: MatchEvent, key: String) -> Array[int]:
	var raw: Array = event.payload[key]
	return _typed(raw)


func _cost(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).cost


func _pass_until_turn(engine: MatchEngine, turn: int) -> void:
	var none: Array[int] = []
	while engine.energy() < turn:
		if not engine.apply(EngineAction.commit(engine.awaited_seat(), none)).ok:
			return


## The first legal set of exactly `size` cards, or an empty list when none exists.
func _find_set(hand: Array[int], energy: int, size: int) -> Array[int]:
	for s: Array in LegalPlays.enumerate(hand, energy, _defs()):
		if s.size() == size:
			return _typed(s)
	var none: Array[int] = []
	return none


## The scripted commit for whoever is awaited (see the suite comment); while a prompt is
## open (DC-05 T05), the prompted seat's first option instead.
## Whether `event` may name a card that was face up on the opponent's row before the step
## and is hidden after it (DC-05 T13; the rule of test_full_match.gd): scored, revealed,
## stats, returned and a public burn, plus the kinds the engine emits for a face-up card in
## a walk that a round end, a destroy or a return then hides (an effect firing, a choice,
## a public destroy or move, the public turn-end clear of a destroyed card, DC-06). Never a
## deal, draw, discard, commit or other private kind.
func _may_name_public_card(event: MatchEvent) -> bool:
	match event.kind:
		MatchEvent.Kind.CARD_SCORED, MatchEvent.Kind.CARD_REVEALED:
			return true
		MatchEvent.Kind.STATS_CHANGED, MatchEvent.Kind.CARD_RETURNED:
			return true
		MatchEvent.Kind.EFFECT_FIRED, MatchEvent.Kind.CHOICE_MADE:
			return true
		MatchEvent.Kind.CARD_BURNED, MatchEvent.Kind.CARD_DESTROYED, MatchEvent.Kind.CARD_MOVED:
			return not event.is_private()
		MatchEvent.Kind.DESTROYED_CLEARED:
			return not event.is_private()
	return false


func _script_action(engine: MatchEngine, player: int) -> EngineAction:
	var prompt: Dictionary = engine.open_prompt()
	if not prompt.is_empty():
		var asked: int = prompt["seat"]
		var zone: int = prompt["zone"]
		var options: Array = prompt["options"]
		var first: int = options[0]
		return EngineAction.choose(asked, zone, first)
	var seat: int = engine.awaited_seat()
	var cards: Array[int] = []
	if seat == player:
		cards = _find_set(_hand(engine, seat), engine.energy(), 1)
	return EngineAction.commit(seat, cards)


## Captures one step: the full state before and after, the result and both views.
func _capture(engine: MatchEngine, before: Dictionary, result: ApplyResult, label: String) -> Step:
	var step: Step = Step.new()
	step.label = label
	step.before = before
	step.after = engine.full_state()
	step.result = result
	step.awaited = engine.awaited_seat()
	step.energy = engine.energy()
	for seat: int in range(2):
		step.views.append(engine.view_for(seat))
	return step


## start() and SCRIPT_COMMITS scripted commits from `match_seed`, every step captured.
func _scripted_steps(match_seed: int, player: int) -> Array[Step]:
	var steps: Array[Step] = []
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	var before: Dictionary = engine.full_state()
	var label: String = "seed %d player %d" % [match_seed, player]
	steps.append(_capture(engine, before, engine.start(), label + " start"))
	for index: int in range(SCRIPT_COMMITS):
		before = engine.full_state()
		var result: ApplyResult = engine.apply(_script_action(engine, player))
		steps.append(_capture(engine, before, result, label + " commit %d" % (index + 1)))
	return steps


## Every id of `seat`'s cards that its opponent may not know in `state`: its hand, deck
## and burn pile, its share of the face-down commit, its row's cards not yet revealed
## (only while a prompt pauses a walk, DC-05 T05) and its destroyed pile's entries whose
## identity is not public (DC-07 R18). The face-down commit is the first committer's,
## whatever the cards' origin (a recovered card, DC-07 C12).
func _hidden_ids(state: Dictionary, seat: int) -> Array[int]:
	var out: Array[int] = []
	for key: String in ["hand", "deck", "burned"]:
		out.append_array(_state_list(state, key, seat))
	if _state_int(state, "first_seat") == seat:
		out.append_array(_state_ints(state, "pending"))
	var known: Array[int] = _state_list(state, "destroyed_known", seat)
	for card: int in _state_list(state, "destroyed", seat):
		if not known.has(card):
			out.append(card)
	var revealed: Array[int] = _state_list(state, "revealed", seat)
	for card: int in _state_list(state, "board", seat):
		if not revealed.has(card):
			out.append(card)
	return out


## `pile_seat`'s destroyed pile as the other seat sees it (DC-07 R18): an entry whose
## identity is not public is HIDDEN_CARD.
func _shown_pile(state: Dictionary, pile_seat: int) -> Array[int]:
	var known: Array[int] = _state_list(state, "destroyed_known", pile_seat)
	var out: Array[int] = []
	for card: int in _state_list(state, "destroyed", pile_seat):
		out.append(card if known.has(card) else MatchEvent.HIDDEN_CARD)
	return out


## `row_seat`'s row as `viewer` sees it: an opponent card not yet revealed is HIDDEN_CARD.
func _shown_board(state: Dictionary, row_seat: int, viewer: int) -> Array[int]:
	var revealed: Array[int] = _state_list(state, "revealed", row_seat)
	var out: Array[int] = []
	for card: int in _state_list(state, "board", row_seat):
		var shown: bool = row_seat == viewer or revealed.has(card)
		out.append(card if shown else MatchEvent.HIDDEN_CARD)
	return out


## Every int under a card key, at any depth.
func _card_ids(value: Variant, key: String, out: Array[int]) -> void:
	if value is Dictionary:
		var d: Dictionary = value
		for k: String in d.keys():
			_card_ids(d[k], k, out)
	elif value is Array:
		var items: Array = value
		for item: Variant in items:
			_card_ids(item, key, out)
	elif value is int and CARD_KEYS.has(key):
		var card: int = value
		out.append(card)


## Every int at any depth, whatever its key.
func _all_ints(value: Variant, out: Array[int]) -> void:
	if value is Dictionary:
		var d: Dictionary = value
		for k: Variant in d.keys():
			_all_ints(d[k], out)
	elif value is Array:
		var items: Array = value
		for item: Variant in items:
			_all_ints(item, out)
	elif value is int:
		var number: int = value
		out.append(number)


## The card ids under card keys in `value` that are in `hidden`.
func _leaks(value: Variant, hidden: Array[int]) -> Array[int]:
	var ids: Array[int] = []
	_card_ids(value, "", ids)
	var out: Array[int] = []
	for card: int in ids:
		if hidden.has(card):
			out.append(card)
	return out


## The ints in `value`, at any depth, that equal a secret (seed or stream state).
func _secrets_in(value: Variant, secrets: Array[int]) -> Array[int]:
	var ints: Array[int] = []
	_all_ints(value, ints)
	var out: Array[int] = []
	for number: int in ints:
		if secrets.has(number):
			out.append(number)
	return out


func _secrets(state: Dictionary) -> Array[int]:
	return [_state_int(state, "seed"), _state_int(state, "rng_state")]


func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys


func _sorted(values: Array) -> Array:
	var out: Array = values.duplicate()
	out.sort()
	return out


## The plan's payload keys for an event kind (the plan's event table).
func _payload_keys(kind: int) -> Array:
	var keys: Array = []
	match kind:
		MatchEvent.Kind.ROUND_STARTED:
			keys = ["round", "sudden_death", "first_seat", "first_by_coin"]
		MatchEvent.Kind.CARD_DEALT, MatchEvent.Kind.CARD_DRAWN, MatchEvent.Kind.CARD_BURNED:
			keys = ["seat", "card"]
		MatchEvent.Kind.TURN_STARTED:
			keys = ["round", "turn", "energy", "budgets", "free_first", "first_seat"]
		MatchEvent.Kind.COMMITTED:
			keys = ["seat", "count", "cards", "slots"]
		MatchEvent.Kind.CARD_REVEALED:
			# "flat" was "power" before DC-05; "slot" is new in DC-05. "order" stays for the
			# board until it reads the walk's events (DC-05 T08, T11). "destroyed" is new in
			# DC-06 (R14). DC-07 T03 (P4, P5): "times" and "plus" replace "bonus". DC-09 T06
			# review (cycle 8 R7, R25): the effective "cost" and the "grown" mark.
			keys = [
				"seat",
				"card",
				"def_id",
				"flat",
				"times",
				"plus",
				"order",
				"slot",
				"destroyed",
				"cost",
				"grown",
			]
		MatchEvent.Kind.WALK_STARTED:
			keys = ["round", "turn", "first_seat"]
		MatchEvent.Kind.CARD_SCORED:
			keys = [
				"seat",
				"card",
				"slot",
				"flat",
				"times",
				"plus",
				"mult",
				"added",
				"score",
				"again",
			]
		MatchEvent.Kind.TURN_ENDED:
			keys = ["round", "turn", "scores", "winner"]
		MatchEvent.Kind.ROUND_ENDED:
			keys = ["round", "scores", "winner", "wins"]
		MatchEvent.Kind.CONCEDED:
			keys = ["seat"]
		MatchEvent.Kind.MATCH_ENDED:
			keys = ["winner", "reason", "wins", "rounds_played"]
		MatchEvent.Kind.EFFECT_FIRED:
			# Cycle 8 P7: the uses left after the firing (-1 unlimited).
			keys = ["seat", "card", "verb", "trigger", "uses_left"]
		MatchEvent.Kind.EFFECT_FIZZLED:
			keys = ["seat", "card", "verb", "reason"]
		MatchEvent.Kind.STATS_CHANGED:
			# Cycle 8 P4: the effective cost and whether the change is to the memory.
			keys = ["seat", "card", "flat", "times", "plus", "cost", "permanent", "cause"]
		MatchEvent.Kind.CARD_DESTROYED:
			keys = ["seat", "card", "slot"]
		MatchEvent.Kind.DESTROYED_CLEARED:
			# DC-07 P6: the card went to its seat's destroyed pile; DC-11 T10 (cycle 8 R51):
			# or, salvaged, to its hand.
			keys = ["seat", "card", "slot", "pile", "salvaged"]
		MatchEvent.Kind.CARD_RECOVERED:
			keys = ["seat", "card", "from_seat", "position"]
		MatchEvent.Kind.BONUS_ZERO_SET, MatchEvent.Kind.FREE_FIRST_SET:
			keys = ["seat"]
		MatchEvent.Kind.ENERGY_CARRIED:
			keys = ["seat", "amount"]
		MatchEvent.Kind.CHOICE_REQUESTED:
			# DC-07 P7: "multi" says whether the prompt takes a set; cycle 8 P9 (T09) adds
			# "optional", "resume" and "crew" (public: Crew are face up, R42).
			keys = [
				"seat", "card", "verb", "text", "zone", "options", "multi", "optional", "resume", "crew"
			]
		MatchEvent.Kind.CHOICE_MADE:
			keys = ["seat", "card", "zone", "index", "target", "auto"]
		MatchEvent.Kind.CARD_MOVED:
			keys = ["seat", "card", "from_slot", "to_slot"]
		MatchEvent.Kind.CARD_RETURNED:
			keys = ["seat", "card", "slot"]
		MatchEvent.Kind.CARD_DISCARDED:
			keys = ["seat", "card"]
		MatchEvent.Kind.MATCH_STARTED:
			# DC-07: the deck ids only; the seed would predict every shuffle. DC-11 T08
			# (cycle 8 R42): both seats' Crew ids.
			keys = ["decks", "crew"]
		MatchEvent.Kind.CHOICE_DECLINED:
			# DC-11 T09 (cycle 8 P10): public.
			keys = ["seat", "card", "crew"]
		MatchEvent.Kind.CREW_FIRED:
			# DC-11 T10 (cycle 8 P13): public; names no card.
			keys = ["seat", "slot", "crew", "verb", "trigger", "uses_left"]
	return keys


## `event`'s payload keys: _payload_keys of its kind, and for a CARD_BURNED of a card burned
## from a row at turn end (it carries `row_seat`) also `slot` and `row_seat` (DC-09 T06
## review), whether or not the card is redacted.
func _event_keys(event: MatchEvent) -> Array:
	var keys: Array = _payload_keys(event.kind)
	if event.kind == MatchEvent.Kind.CARD_BURNED and event.payload.has("row_seat"):
		keys.append_array(["slot", "row_seat"])
	return keys


## `card`'s entry in the full state's `memory` (cycle 8 P2), or {} when it has none.
func _memory_of(state: Dictionary, card: int) -> Dictionary:
	var all_memory: Dictionary = state["memory"]
	if not all_memory.has(card):
		return {}
	var kept: Dictionary = all_memory[card]
	return kept


## `card`'s cycle 8 view values from the full state (R4, R6, R7, P3, P7) as [cost, grown,
## uses_left]: the printed cost less the memory's reduction, floored at MatchRules.MIN_COST;
## grown when the memory is not empty; uses_left -1 for an unlimited (or no) effect, else
## the memory's count once read, else the effect's uses.
func _memory_values(state: Dictionary, card: int) -> Array[int]:
	var def: CardDef = _db().card_at(card % MatchRules.DECK_SIZE)
	var kept: Dictionary = _memory_of(state, card)
	var cost: int = def.cost
	var grown: int = 0
	var uses: int = -1
	if def.effect != null and def.effect.uses > 0:
		uses = def.effect.uses
	if not kept.is_empty():
		var reduction: int = kept["cost"]
		var left: int = kept["uses_left"]
		cost = maxi(cost - reduction, MatchRules.MIN_COST)
		grown = 0 if MemoryFixture.from_dict(kept).is_empty() else 1
		if uses >= 0 and left >= 0:
			uses = left
	var out: Array[int] = [cost, grown, uses]
	return out


## `card`'s shown stats from the full state (DC-07 P5) as [flat, times, plus]: its
## definition's flat and bonus (or the base a copy stored, both parts), then its entry in
## `card_states` (flat delta, temp plus, no bonus), which effects write since DC-05 T04.
func _shown_stats(state: Dictionary, card: int) -> Array[int]:
	var def: CardDef = _db().card_at(card % MatchRules.DECK_SIZE)
	var flat: int = def.flat
	var times: int = def.bonus if def.bonus_kind == CardDef.BonusKind.TIMES else MatchRules.MULT_ONE
	var plus: int = def.bonus if def.bonus_kind == CardDef.BonusKind.PLUS else 0
	var held_all: Dictionary = state["card_states"]
	var held: Dictionary = {}
	if held_all.has(card):
		held = held_all[card]
		var has_base: bool = held["has_base"]
		if has_base:
			# A copy stores both bonus parts (DC-07 R34, C22).
			flat = held["base_flat"]
			times = held["base_times"]
			plus = held["base_plus"]
	# Cycle 8 R3: the card's match memory adds after the base, before the board changes.
	var kept: Dictionary = _memory_of(state, card)
	if not kept.is_empty():
		var kept_flat: int = kept["flat"]
		var kept_times: int = kept["times"]
		var kept_plus: int = kept["plus"]
		flat += kept_flat
		times += kept_times
		plus += kept_plus
	if not held.is_empty():
		var delta: int = held["flat_delta"]
		var temp: int = held["temp_plus"]
		flat += delta
		plus += temp
		var cleared: bool = held["no_bonus"]
		if cleared:
			times = MatchRules.MULT_ONE
			plus = 0
	var out: Array[int] = [flat, times, plus]
	return out


## Whether `card` carries the destroyed mark in the full state's `card_states` (DC-06 R22).
func _is_destroyed(state: Dictionary, card: int) -> bool:
	var held_all: Dictionary = state["card_states"]
	if not held_all.has(card):
		return false
	var held: Dictionary = held_all[card]
	var destroyed: bool = held["destroyed"]
	return destroyed


## A view row (own_row or opponent_row) against `row_seat`'s board in `state`: one entry
## per card in slot order with its revealed flag and its shown stats. A shown card shows
## its effective flat, ×-part and +-part (_shown_stats; DC-07 P5); an opponent card not yet
## revealed shows flat 0 and no bonus (times 100, plus 0).
func _assert_row(row: Array[Dictionary], state: Dictionary, row_seat: int, own: bool) -> void:
	var board: Array[int] = _state_list(state, "board", row_seat)
	var revealed: Array[int] = _state_list(state, "revealed", row_seat)
	assert_int(row.size()).is_equal(board.size())
	for slot: int in range(mini(row.size(), board.size())):
		var entry: Dictionary = row[slot]
		var keys: Array = [
			"card",
			"flat",
			"times",
			"plus",
			"revealed",
			"destroyed",
			"cost",
			"grown",
			"uses_left",
		]
		assert_array(_sorted_keys(entry)).is_equal(_sorted(keys))
		var cost: int = entry["cost"]
		var grown: bool = entry["grown"]
		var uses_left: int = entry["uses_left"]
		var card: int = entry["card"]
		var flat: int = entry["flat"]
		var times: int = entry["times"]
		var plus: int = entry["plus"]
		var shown: bool = entry["revealed"]
		assert_bool(shown).is_equal(revealed.has(board[slot]))
		# The destroyed flag is public for every card (DC-06 R20).
		var destroyed: bool = entry["destroyed"]
		assert_bool(destroyed).is_equal(_is_destroyed(state, board[slot]))
		if own or shown:
			assert_int(card).is_equal(board[slot])
		else:
			# Face down on the opponent's row (a walk paused on a prompt): no id (R29).
			assert_int(card).is_equal(MatchEvent.HIDDEN_CARD)
		if own or shown:
			var stats: Array[int] = _shown_stats(state, card)
			assert_int(flat).is_equal(stats[0])
			assert_int(times).is_equal(stats[1])
			assert_int(plus).is_equal(stats[2])
			# Cycle 8 (R4, R6, R7): the effective cost, the grown mark and the uses left.
			var remembered: Array[int] = _memory_values(state, card)
			assert_int(cost).is_equal(remembered[0])
			assert_bool(grown).is_equal(remembered[1] == 1)
			assert_int(uses_left).is_equal(remembered[2])
		else:
			assert_int(flat).is_equal(0)
			assert_int(times).is_equal(MatchRules.MULT_ONE)
			assert_int(plus).is_equal(0)
			# A hidden card's memory stays hidden (R8): 0, false, -1.
			assert_int(cost).is_equal(0)
			assert_bool(grown).is_false()
			assert_int(uses_left).is_equal(-1)


## `pile_entries` against the full state (DC-09 T06 review): an entry for exactly every card
## of `seat`'s destroyed pile and every public entry of the opponent's, each with the
## hand-row keys and its effective stats, cost, grown mark and uses left (memory included).
func _assert_pile_entries(view: SeatView, state: Dictionary, seat: int) -> void:
	var want: Array[int] = _state_list(state, "destroyed", seat)
	for card: int in _shown_pile(state, 1 - seat):
		if card != MatchEvent.HIDDEN_CARD:
			want.append(card)
	want.sort()
	var have: Array[int] = []
	have.assign(view.pile_entries.keys())
	have.sort()
	assert_array(have).is_equal(want)
	for card: int in have:
		var entry: Dictionary = view.pile_entries[card]
		var keys: Array = ["card", "cost", "flat", "grown", "plus", "times", "uses_left"]
		assert_array(_sorted_keys(entry)).is_equal(keys)
		var stats: Array[int] = _shown_stats(state, card)
		var remembered: Array[int] = _memory_values(state, card)
		var shown: Array[int] = [entry["card"], entry["flat"], entry["times"], entry["plus"]]
		assert_array(shown).is_equal([card, stats[0], stats[1], stats[2]])
		var cost: int = entry["cost"]
		var grown: bool = entry["grown"]
		var uses_left: int = entry["uses_left"]
		assert_int(cost).is_equal(remembered[0])
		assert_bool(grown).is_equal(remembered[1] == 1)
		assert_int(uses_left).is_equal(remembered[2])


## The view agrees with the full state on every R28 field.
func _assert_view_matches_state(view: SeatView, step: Step, seat: int) -> void:
	var state: Dictionary = step.after
	var opp: int = 1 - seat
	assert_int(view.seat).is_equal(seat)
	assert_int(view.opponent).is_equal(opp)
	assert_array(view.own_hand).is_equal(_state_list(state, "hand", seat))
	assert_array(view.own_board).is_equal(_state_list(state, "board", seat))
	assert_array(view.opponent_board).is_equal(_shown_board(state, opp, seat))
	assert_array(view.board_of(seat)).is_equal(view.own_board)
	assert_array(view.board_of(opp)).is_equal(view.opponent_board)
	assert_array(view.own_destroyed).is_equal(_state_list(state, "destroyed", seat))
	assert_array(view.opponent_destroyed).is_equal(_shown_pile(state, opp))
	_assert_pile_entries(view, state, seat)
	assert_int(view.opponent_hand_count).is_equal(_state_list(state, "hand", opp).size())
	var pending: Array[int] = _state_ints(state, "pending")
	var pending_slots: Array[int] = _state_ints(state, "pending_slots")
	var none: Array[int] = []
	var phase: int = _state_int(state, "phase")
	var first: int = _state_int(state, "first_seat")
	if phase == MatchState.Phase.AWAIT_SECOND and first == seat:
		assert_array(view.own_pending).is_equal(pending)
		assert_int(view.opponent_pending_count).is_equal(0)
		assert_array(view.opponent_pending_slots).is_equal(none)
	elif phase == MatchState.Phase.AWAIT_SECOND:
		assert_array(view.own_pending).is_equal(none)
		assert_int(view.opponent_pending_count).is_equal(pending.size())
		assert_array(view.opponent_pending_slots).is_equal(pending_slots)
	else:
		assert_array(view.own_pending).is_equal(none)
		assert_int(view.opponent_pending_count).is_equal(0)
		assert_array(view.opponent_pending_slots).is_equal(none)
	var deck_counts: Array[int] = [
		_state_list(state, "deck", 0).size(), _state_list(state, "deck", 1).size()
	]
	assert_array(view.deck_counts).is_equal(deck_counts)
	assert_array(view.scores).is_equal(_state_ints(state, "scores"))
	var walk: Dictionary = state["walk"]
	assert_array(view.mults).is_equal(_state_ints(walk, "mult"))
	_assert_row(view.own_row, state, seat, true)
	_assert_row(view.opponent_row, state, opp, false)
	assert_array(view.wins).is_equal(_state_ints(state, "wins"))
	assert_int(view.round_number).is_equal(_state_int(state, "round"))
	assert_int(view.turn).is_equal(_state_int(state, "turn"))
	# Each budget is the turn plus that seat's carry (R9; the carry card can be played in the
	# scripted run since DC-05 T04), and `energy` is this seat's budget.
	assert_int(step.energy).is_equal(view.turn)
	var energy: Dictionary = state["energy"]
	var carry: Array[int] = _state_ints(energy, "carry")
	assert_array(view.budgets).is_equal([view.turn + carry[0], view.turn + carry[1]])
	assert_int(view.budgets[seat]).is_equal(view.energy)
	# The seat's own free-first grant only (R10, DC-05 T07).
	var free_flags: Array = energy["free_first"]
	var own_free: bool = free_flags[seat]
	assert_bool(view.free_first).is_equal(own_free)
	assert_int(view.phase).is_equal(phase)
	assert_int(view.awaited_seat).is_equal(step.awaited)
	assert_bool(view.is_awaited()).is_equal(step.awaited == seat)
	assert_int(view.first_seat).is_equal(first)
	var sudden: bool = state["sudden_death"]
	assert_bool(view.sudden_death).is_equal(sudden)


# --- R28: the view's fields -----------------------------------------------------------


func test_view_at_start_holds_the_seat_fields() -> void:
	var engine: MatchEngine = _started(SEED)
	for seat: int in range(2):
		var view: SeatView = engine.view_for(seat)
		assert_object(view).is_not_null()
		assert_int(view.seat).is_equal(seat)
		assert_int(view.own_hand.size()).is_equal(MatchRules.OPENING_HAND + 1)
		assert_array(view.own_hand).is_equal(_hand(engine, seat))
		assert_int(view.opponent_hand_count).is_equal(MatchRules.OPENING_HAND + 1)
		var deck_left: int = MatchRules.DECK_SIZE - MatchRules.OPENING_HAND - 1
		assert_array(view.deck_counts).is_equal([deck_left, deck_left])
		assert_array(view.own_board).is_empty()
		assert_array(view.opponent_board).is_empty()
		assert_array(view.own_pending).is_empty()
		assert_int(view.opponent_pending_count).is_equal(0)
		assert_array(view.scores).is_equal([0, 0])
		assert_array(view.wins).is_equal([0, 0])
		assert_int(view.round_number).is_equal(1)
		assert_int(view.turn).is_equal(1)
		assert_int(view.energy).is_equal(1)
		assert_int(view.phase).is_equal(MatchState.Phase.AWAIT_FIRST)
		assert_int(view.awaited_seat).is_equal(engine.awaited_seat())


func test_view_matches_the_full_state_at_every_scripted_step() -> void:
	for player: int in range(2):
		for step: Step in _scripted_steps(SEED, player):
			assert_bool(step.result.ok).override_failure_message(step.label).is_true()
			for seat: int in range(2):
				_assert_view_matches_state(step.views[seat], step, seat)


func test_view_to_dict_has_exactly_the_view_keys() -> void:
	var engine: MatchEngine = _started(SEED)
	for seat: int in range(2):
		var view: Dictionary = engine.view_for(seat).to_dict()
		assert_array(_sorted_keys(view)).is_equal(_sorted(VIEW_KEYS))


## Spec scenario: seat 0 awaited on turn 3 commits cards costing 1 and 2; seat 1's view
## shows a face-down count of 2 and no card identities, and seat 1 is awaited.
func test_face_down_commit_shows_only_a_count_to_the_opponent() -> void:
	var found: bool = false
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _started(match_seed)
		_pass_until_turn(engine, 3)
		if engine.awaited_seat() != 0:
			continue
		var cards: Array[int] = _cost_one_and_two(_hand(engine, 0))
		if cards.is_empty():
			continue
		found = true
		var result: ApplyResult = engine.apply(EngineAction.commit(0, cards))
		assert_bool(result.ok).is_true()
		assert_int(engine.awaited_seat()).is_equal(1)
		var opponent_view: SeatView = engine.view_for(1)
		assert_int(opponent_view.opponent_pending_count).is_equal(2)
		# The slots show (R7): no slots given on the empty row, so they append at 0 and 1.
		assert_array(opponent_view.opponent_pending_slots).is_equal([0, 1])
		assert_bool(opponent_view.is_awaited()).is_true()
		assert_array(_leaks(opponent_view.to_dict(), cards)).is_empty()
		var redacted: Array[MatchEvent] = result.events_for(1)
		assert_int(redacted.size()).is_equal(1)
		assert_int(redacted[0].kind).is_equal(MatchEvent.Kind.COMMITTED)
		assert_int(_payload_int(redacted[0], "seat")).is_equal(0)
		assert_int(_payload_int(redacted[0], "count")).is_equal(2)
		assert_array(_payload_ints(redacted[0], "cards")).is_equal([-1, -1])
		assert_array(_payload_ints(redacted[0], "slots")).is_equal([0, 1])
		var own_view: SeatView = engine.view_for(0)
		assert_array(own_view.own_pending).is_equal(cards)
		assert_int(own_view.opponent_pending_count).is_equal(0)
		assert_array(_payload_ints(result.events_for(0)[0], "cards")).is_equal(cards)
		break
	assert_bool(found).override_failure_message("no seed gives the turn-3 hand").is_true()


## A card costing 1 and a card costing 2 from the hand, or an empty list.
func _cost_one_and_two(hand: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for cost: int in [1, 2]:
		for card: int in hand:
			if _cost(card) == cost:
				out.append(card)
				break
	if out.size() != 2:
		out.clear()
	return out


func test_view_after_the_match_ends() -> void:
	var engine: MatchEngine = _started(SEED)
	engine.apply(EngineAction.concede(0))
	for seat: int in range(2):
		var view: SeatView = engine.view_for(seat)
		assert_int(view.phase).is_equal(MatchState.Phase.OVER)
		assert_int(view.awaited_seat).is_equal(-1)
		assert_bool(view.is_awaited()).is_false()


func test_view_for_an_unknown_seat_is_null() -> void:
	var engine: MatchEngine = _started(SEED)
	assert_object(engine.view_for(-1)).is_null()
	assert_object(engine.view_for(2)).is_null()


func test_mutating_a_view_leaves_the_engine_alone() -> void:
	var engine: MatchEngine = _started(SEED)
	var before: Dictionary = engine.full_state()
	var view: SeatView = engine.view_for(0)
	view.own_hand.clear()
	view.deck_counts[0] = 99
	view.scores[1] = 99
	assert_dict(engine.full_state()).is_equal(before)
	assert_array(engine.view_for(0).own_hand).is_equal(_hand(engine, 0))


# --- R29: no leaks ----------------------------------------------------------------------


## At every step of the scripted runs, for both seats: the view and the redacted events
## hold no id from the opponent's hand, deck, face-down commit or burn, nor the seed or
## stream state, and carry no key beyond the plan's.
func test_views_and_redacted_events_never_leak() -> void:
	var seen_pending: Array[int] = [0, 0]
	var seen_burn: Array[int] = [0, 0]
	var seen_redacted: Array[int] = [0, 0]
	for match_seed: int in LEAK_SEEDS:
		for player: int in range(2):
			for step: Step in _scripted_steps(match_seed, player):
				assert_bool(step.result.ok).override_failure_message(step.label).is_true()
				var secrets: Array[int] = []
				secrets.append_array(_secrets(step.before))
				secrets.append_array(_secrets(step.after))
				var revealed: Array[int] = []
				for event: MatchEvent in step.result.events:
					if event.kind == MatchEvent.Kind.CARD_REVEALED:
						revealed.append(_payload_int(event, "card"))
				for seat: int in range(2):
					var opp: int = 1 - seat
					var where: String = "%s seat %d" % [step.label, seat]
					# The view, against the state it was built from.
					var view: SeatView = step.views[seat]
					var view_dict: Dictionary = view.to_dict()
					var hidden_now: Array[int] = _hidden_ids(step.after, opp)
					assert_array(_sorted_keys(view_dict)).is_equal(_sorted(VIEW_KEYS))
					var leaked: Array[int] = _leaks(view_dict, hidden_now)
					assert_array(leaked).override_failure_message(where).is_empty()
					var seeds: Array[int] = _secrets_in(view_dict, secrets)
					assert_array(seeds).override_failure_message(where).is_empty()
					if view.opponent_pending_count > 0:
						seen_pending[seat] += 1
					if not _state_list(step.after, "burned", opp).is_empty():
						seen_burn[seat] += 1
					# The events, against what was hidden before or after the step, less
					# the cards this step revealed in public.
					# Cards face up on the opponent's row before the step were public too: the
					# walk scores them by id even when a round end then hides them again, so
					# the on-row kinds may name them (_may_name_public_card; every other kind
					# is held to `hidden_strict`). A card still face down there (a walk paused
					# on a prompt) was not public.
					var public_before: Array[int] = _state_list(step.before, "revealed", opp)
					var hidden_strict: Array[int] = []
					var hidden_during: Array[int] = []
					for card: int in _hidden_ids(step.before, opp) + hidden_now:
						if revealed.has(card) or hidden_strict.has(card):
							continue
						hidden_strict.append(card)
						if not public_before.has(card):
							hidden_during.append(card)
					var redacted: Array[MatchEvent] = step.result.events_for(seat)
					assert_int(redacted.size()).is_equal(step.result.events.size())
					for event: MatchEvent in redacted:
						assert_array(_sorted_keys(event.payload)).is_equal(
							_sorted(_event_keys(event))
						)
						var at: String = "%s event %d" % [where, event.kind]
						var held_to: Array[int] = hidden_strict
						if _may_name_public_card(event):
							held_to = hidden_during
						var event_leaks: Array[int] = _leaks(event.payload, held_to)
						assert_array(event_leaks).override_failure_message(at).is_empty()
						var event_seeds: Array[int] = _secrets_in(event.payload, secrets)
						assert_array(event_seeds).override_failure_message(at).is_empty()
						if event.is_private() and event.owner_seat == opp:
							seen_redacted[seat] += 1
	# The runs really exercised every hidden pile from both sides.
	for seat: int in range(2):
		assert_int(seen_pending[seat]).override_failure_message("no face-down").is_greater(0)
		assert_int(seen_burn[seat]).override_failure_message("no burn").is_greater(0)
		assert_int(seen_redacted[seat]).override_failure_message("no redaction").is_greater(0)


## Private events show the owner everything and the opponent the seat and count only;
## public events pass through unchanged for both seats.
func test_redaction_hides_card_ids_from_the_opponent_only() -> void:
	var seen: Array[int] = []
	for player: int in range(2):
		for step: Step in _scripted_steps(SEED, player):
			var events: Array[MatchEvent] = step.result.events
			for seat: int in range(2):
				var redacted: Array[MatchEvent] = step.result.events_for(seat)
				for i: int in range(events.size()):
					var original: MatchEvent = events[i]
					var copy: MatchEvent = redacted[i]
					_assert_privacy(original, step.before)
					if not seen.has(original.kind):
						seen.append(original.kind)
					assert_int(copy.kind).is_equal(original.kind)
					assert_int(copy.owner_seat).is_equal(original.owner_seat)
					if not original.is_private() or original.owner_seat == seat:
						assert_dict(copy.to_dict()).is_equal(original.to_dict())
						continue
					_assert_redacted(copy, original)
	for kind: int in PRIVATE_KINDS:
		assert_bool(seen.has(kind)).override_failure_message("kind %d unseen" % kind).is_true()


## Which kinds are private: PRIVATE_KINDS and the discard always; SPLIT_KINDS only for a
## hand or face-down card (DC-05), a burn being public only for a card that was on a row
## before the step (a returned card at the hand cap); every other kind never.
func _assert_privacy(event: MatchEvent, before: Dictionary) -> void:
	var label: String = "kind %d" % event.kind
	if event.kind == MatchEvent.Kind.CARD_BURNED and not event.is_private():
		var card: int = _payload_int(event, "card")
		var seat: int = _payload_int(event, "seat")
		var was_shown: bool = _state_list(before, "revealed", seat).has(card)
		assert_bool(was_shown).override_failure_message(label).is_true()
		return
	if SPLIT_KINDS.has(event.kind):
		return
	var expect_private: bool = (
		PRIVATE_KINDS.has(event.kind) or event.kind == MatchEvent.Kind.CARD_DISCARDED
	)
	assert_bool(event.is_private()).override_failure_message(label).is_equal(expect_private)


## A redacted private event keeps the seat (and a commit's count) and hides each card id;
## a private CHOICE_MADE keeps its (revealed) source card and hides its target.
func _assert_redacted(copy: MatchEvent, original: MatchEvent) -> void:
	assert_int(_payload_int(copy, "seat")).is_equal(_payload_int(original, "seat"))
	assert_int(_payload_int(copy, "seat")).is_equal(original.owner_seat)
	if original.kind == MatchEvent.Kind.CHOICE_MADE:
		assert_int(_payload_int(copy, "target")).is_equal(MatchEvent.HIDDEN_CARD)
		assert_int(_payload_int(copy, "card")).is_equal(_payload_int(original, "card"))
		assert_int(_payload_int(copy, "index")).is_equal(_payload_int(original, "index"))
	elif original.kind == MatchEvent.Kind.COMMITTED:
		var count: int = _payload_int(original, "count")
		assert_int(_payload_int(copy, "count")).is_equal(count)
		var hidden: Array[int] = []
		for _i: int in range(count):
			hidden.append(MatchEvent.HIDDEN_CARD)
		assert_array(_payload_ints(copy, "cards")).is_equal(hidden)
		# Slots are public (R7): the redacted copy keeps them.
		assert_array(_payload_ints(copy, "slots")).is_equal(_payload_ints(original, "slots"))
	else:
		assert_int(_payload_int(copy, "card")).is_equal(MatchEvent.HIDDEN_CARD)
	if original.kind == MatchEvent.Kind.STATS_CHANGED:
		_assert_neutral_stats(copy, original)


## A redacted private STATS_CHANGED (a growth on a hidden card) shows neutral stats: flat 0,
## ×1.00, +0, cost 0, not permanent, with its seat and cause kept (cycle 8 R8, R73; DC-09 T06
## review), since the real values with the public deck list would name the card.
func _assert_neutral_stats(copy: MatchEvent, original: MatchEvent) -> void:
	var neutral: Dictionary = {
		"seat": _payload_int(original, "seat"),
		"card": MatchEvent.HIDDEN_CARD,
		"flat": 0,
		"times": MatchRules.MULT_ONE,
		"plus": 0,
		"cost": 0,
		"permanent": false,
		"cause": original.payload["cause"],
	}
	assert_dict(copy.payload).is_equal(neutral)


func test_a_seat_outside_the_match_sees_no_private_card() -> void:
	var result: ApplyResult = FixtureDecks.engine(SEED, _db()).start()
	for event: MatchEvent in result.events:
		var copy: MatchEvent = event.redacted_for(MatchEvent.PUBLIC)
		if event.is_private():
			_assert_redacted(copy, event)
		else:
			assert_dict(copy.to_dict()).is_equal(event.to_dict())


func test_redaction_never_mutates_the_original_events() -> void:
	var checked: int = 0
	for step: Step in _scripted_steps(SEED, 0):
		var events: Array[MatchEvent] = step.result.events
		var snapshot: Array[Dictionary] = []
		for event: MatchEvent in events:
			snapshot.append(event.to_dict())
		var copies: Array[MatchEvent] = []
		copies.append_array(step.result.events_for(0))
		copies.append_array(step.result.events_for(1))
		for event: MatchEvent in events:
			copies.append(event.redacted_for(0))
			copies.append(event.redacted_for(1))
		# Scribble over every copy; none of it may reach the originals.
		for copy: MatchEvent in copies:
			for original: MatchEvent in events:
				assert_bool(is_same(copy, original)).is_false()
				assert_bool(is_same(copy.payload, original.payload)).is_false()
			if copy.payload.has("card"):
				copy.payload["card"] = 99
			if copy.payload.has("cards"):
				var cards: Array = copy.payload["cards"]
				cards.append(99)
			copy.payload["seat"] = 7
		for i: int in range(events.size()):
			assert_dict(events[i].to_dict()).is_equal(snapshot[i])
			# The unredacted private events still hold the real ids.
			var ids: Array[int] = []
			_card_ids(events[i].payload, "", ids)
			for card: int in ids:
				assert_int(card).is_between(0, 2 * MatchRules.DECK_SIZE - 1)
				checked += 1
	assert_int(checked).is_greater(0)


# --- DC-05 R34: prompts and choices hide hand cards -------------------------------------


## A started engine paused on a hand prompt (c09, draw 2 then discard 1): turn 3, the first
## committer plays its c09 alone and the other passes. Null when no seed in the search
## range deals the first committer its c09 by turn 3. Scripted, no private fields.
func _discard_prompt_engine() -> MatchEngine:
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _started(match_seed)
		_pass_until_turn(engine, 3)
		var first: int = engine.awaited_seat()
		var c09: int = first * MatchRules.DECK_SIZE + C09_DRAW_DISCARD
		if not _hand(engine, first).has(c09):
			continue
		var play: Array[int] = [c09]
		var none: Array[int] = []
		if not engine.apply(EngineAction.commit(first, play)).ok:
			continue
		if not engine.apply(EngineAction.commit(1 - first, none)).ok:
			continue
		if not engine.open_prompt().is_empty():
			return engine
	return null


## No card key in `events` (prompt kinds only) holds an id from `hidden`.
func _prompt_event_leaks(events: Array[MatchEvent], hidden: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		if PROMPT_KINDS.has(event.kind):
			out.append_array(_leaks(event.payload, hidden))
	return out


func test_prompt_and_choice_events_hold_no_hand_id_for_the_other_seat() -> void:
	var engine: MatchEngine = _discard_prompt_engine()
	assert_object(engine).override_failure_message("no seed gives c09 by turn 3").is_not_null()
	if engine == null:
		return
	var asked: int = engine.awaited_seat()
	var other: int = 1 - asked
	var state: Dictionary = engine.full_state()
	var hand: Array[int] = _state_list(state, "hand", asked)
	var log_size: int = engine.accepted_action_count()
	# The views: the prompted seat sees the zone and positions, the other only that it is open.
	var own_prompt: Dictionary = engine.view_for(asked).prompt
	var zone: int = own_prompt["zone"]
	assert_int(zone).is_equal(Choice.Zone.OWN_HAND)
	var options: Array = own_prompt["options"]
	var positions: Array = range(hand.size())
	assert_array(options).is_equal(positions)
	assert_dict(engine.view_for(other).prompt).is_equal({"open": true, "seat": asked})
	assert_array(_leaks(engine.view_for(other).to_dict(), hand)).is_empty()
	# The answer: CHOICE_MADE hides its target and CARD_DISCARDED its card from the other.
	var discarded: int = hand[1]
	var before: Dictionary = engine.full_state()
	var result: ApplyResult = engine.apply(EngineAction.choose(asked, zone, 1))
	assert_bool(result.ok).is_true()
	assert_int(engine.accepted_action_count()).is_equal(log_size + 1)
	var hidden: Array[int] = _hidden_ids(before, asked) + _hidden_ids(engine.full_state(), asked)
	var theirs: Array[MatchEvent] = result.events_for(other)
	assert_array(_prompt_event_leaks(theirs, hidden)).is_empty()
	var kinds: Array[int] = []
	for event: MatchEvent in theirs:
		kinds.append(event.kind)
		if event.kind == MatchEvent.Kind.CHOICE_MADE:
			assert_int(_payload_int(event, "target")).is_equal(MatchEvent.HIDDEN_CARD)
			assert_int(_payload_int(event, "index")).is_equal(1)
		if event.kind == MatchEvent.Kind.CARD_DISCARDED:
			assert_int(_payload_int(event, "card")).is_equal(MatchEvent.HIDDEN_CARD)
	assert_bool(kinds.has(MatchEvent.Kind.CHOICE_MADE)).is_true()
	assert_bool(kinds.has(MatchEvent.Kind.CARD_DISCARDED)).is_true()
	# The prompted seat's own copies name the discarded card.
	for event: MatchEvent in result.events_for(asked):
		if event.kind == MatchEvent.Kind.CHOICE_MADE:
			assert_int(_payload_int(event, "target")).is_equal(discarded)
		if event.kind == MatchEvent.Kind.CARD_DISCARDED:
			assert_int(_payload_int(event, "card")).is_equal(discarded)
	assert_bool(_hand(engine, asked).has(discarded)).is_false()
	assert_dict(engine.view_for(other).prompt).is_empty()


## The request itself, as the other seat sees it: positions only, no hand id.
func test_choice_requested_names_positions_not_hand_ids() -> void:
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = _started(match_seed)
		_pass_until_turn(engine, 3)
		var first: int = engine.awaited_seat()
		var c09: int = first * MatchRules.DECK_SIZE + C09_DRAW_DISCARD
		if not _hand(engine, first).has(c09):
			continue
		var play: Array[int] = [c09]
		var none: Array[int] = []
		engine.apply(EngineAction.commit(first, play))
		var before: Dictionary = engine.full_state()
		var result: ApplyResult = engine.apply(EngineAction.commit(1 - first, none))
		assert_bool(result.ok).is_true()
		var hidden: Array[int] = (
			_hidden_ids(before, first) + _hidden_ids(engine.full_state(), first)
		)
		# The source, c09, was face down (pending) before this step and is revealed by it in
		# public (CARD_REVEALED), so naming it in CHOICE_REQUESTED's `card` leaks nothing.
		for event: MatchEvent in result.events:
			if event.kind == MatchEvent.Kind.CARD_REVEALED:
				var shown: int = _payload_int(event, "card")
				while hidden.has(shown):
					hidden.erase(shown)
		assert_bool(hidden.has(c09)).is_false()
		var theirs: Array[MatchEvent] = result.events_for(1 - first)
		assert_array(_prompt_event_leaks(theirs, hidden)).is_empty()
		var requested: int = 0
		for event: MatchEvent in theirs:
			if event.kind != MatchEvent.Kind.CHOICE_REQUESTED:
				continue
			requested += 1
			assert_bool(event.is_private()).is_false()
			var zone_name: String = event.payload["zone"]
			assert_str(zone_name).is_equal("own_hand")
			var options: Array = event.payload["options"]
			assert_array(options).is_equal(range(_hand(engine, first).size()))
		assert_int(requested).is_equal(1)
		return
	fail("no seed gives c09 by turn 3")


# --- DC-07 T02: deck ids ----------------------------------------------------------------


## Both seats see both deck ids (public, DC-07 R5), as the engine resolved them, from
## before start() to the end; the full state holds the same pair.
func test_views_carry_both_deck_ids() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	for seat: int in range(2):
		assert_array(engine.view_for(seat).deck_ids).is_equal(FixtureDecks.ids())
	engine.start()
	for seat: int in range(2):
		var view: SeatView = engine.view_for(seat)
		assert_array(view.deck_ids).is_equal(engine.deck_ids())
		var shown: Array = view.to_dict()["deck_ids"]
		assert_array(shown).is_equal(["fixture", "fixture"])
	var state: Dictionary = engine.full_state()
	var held: Array = state["deck_ids"]
	assert_array(held).is_equal(["fixture", "fixture"])


# --- DC-07 T03: row stats as {flat, times, plus} ----------------------------------------


## Each row entry carries the effective flat, ×-part (hundredths) and +-part (DC-07 P5),
## and `mults` is in hundredths, ×1.00 before any walk. An opponent card still face down
## shows flat 0 and no bonus.
func test_row_entries_carry_times_and_plus() -> void:
	# Seat 0: c11 (flat 3, ×1.25) and c08 (flat 4) with a stored base of (2, +1). Seat 1:
	# c04 (flat 3) revealed, then c11 face down.
	var c04_1: int = MatchRules.DECK_SIZE + 3
	var c11_1: int = MatchRules.DECK_SIZE + 10
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].board.assign([10, 7])
	state.seats[1].board.assign([c04_1, c11_1])
	state.seats[1].revealed[c04_1] = true
	var held: CardState = state.card_state_for(7)
	held.has_base = true
	held.base_flat = 2
	held.base_times = MatchRules.MULT_ONE
	held.base_plus = 1
	var budgets: Array[int] = [1, 1]
	var view: SeatView = SeatView.build(state, 0, 0, budgets, _defs())
	assert_array(view.mults).is_equal([100, 100])
	# Cycle 8 (DC-09 T01): every entry also carries cost, grown and uses_left; a hidden one
	# shows 0, false and -1.
	var own: Array[Dictionary] = [
		_printed(
			{"card": 10, "flat": 3, "times": 125, "plus": 0, "revealed": false, "destroyed": false},
			3
		),
		_printed(
			{"card": 7, "flat": 2, "times": 100, "plus": 1, "revealed": false, "destroyed": false},
			2
		),
	]
	var hidden: int = MatchEvent.HIDDEN_CARD
	var theirs: Array[Dictionary] = [
		_printed(
			{
				"card": c04_1,
				"flat": 3,
				"times": 100,
				"plus": 0,
				"revealed": true,
				"destroyed": false
			},
			1
		),
		_printed(
			{
				"card": hidden,
				"flat": 0,
				"times": 100,
				"plus": 0,
				"revealed": false,
				"destroyed": false
			},
			0
		),
	]
	assert_int(view.own_row.size()).is_equal(own.size())
	assert_int(view.opponent_row.size()).is_equal(theirs.size())
	for i: int in range(own.size()):
		assert_dict(view.own_row[i]).is_equal(own[i])
		assert_dict(view.opponent_row[i]).is_equal(theirs[i])
	var plain: Array = view.to_dict()["own_row"]
	var first: Dictionary = plain[0]
	assert_dict(first).is_equal(own[0])


## `entry` with the cycle 8 keys of a card with no memory and an unlimited (or no) effect:
## cost `cost`, grown false, uses_left -1.
func _printed(entry: Dictionary, cost: int) -> Dictionary:
	var out: Dictionary = entry.duplicate()
	out["cost"] = cost
	out["grown"] = false
	out["uses_left"] = -1
	return out


# --- Cycle 8 (DC-09 T01): card memory in the views (R7, R8, plan P3) -------------------


## own_hand_row carries, per hand card in hand order, its effective cost and stats and the
## grown mark; own_hand_costs is parallel to own_hand. A reduction and a growth on a hand
## card show at once.
func test_own_hand_row_carries_cost() -> void:
	var engine: MatchEngine = _started(SEED)
	var seat: int = 0
	var hand: Array[int] = _hand(engine, seat)
	assert_int(hand.size()).is_greater(1)
	var view: SeatView = engine.view_for(seat)
	assert_array(view.own_hand).is_equal(hand)
	assert_int(view.own_hand_row.size()).is_equal(hand.size())
	assert_int(view.own_hand_costs.size()).is_equal(hand.size())
	for i: int in range(hand.size()):
		var entry: Dictionary = view.own_hand_row[i]
		var keys: Array = entry.keys()
		keys.sort()
		assert_array(keys).is_equal(["card", "cost", "flat", "grown", "plus", "times", "uses_left"])
		var card: int = entry["card"]
		var cost: int = entry["cost"]
		var grown: bool = entry["grown"]
		assert_int(card).is_equal(hand[i])
		assert_int(cost).is_equal(_cost(hand[i]))
		assert_int(view.own_hand_costs[i]).is_equal(_cost(hand[i]))
		assert_bool(grown).is_false()
	var target: int = hand[0]
	var kept: CardMemory = engine._state.memory_for(target)
	kept.cost = 1
	kept.flat = 2
	var grown_view: SeatView = engine.view_for(seat)
	var grown_entry: Dictionary = grown_view.own_hand_row[0]
	var shown_cost: int = grown_entry["cost"]
	var shown_flat: int = grown_entry["flat"]
	var shown_grown: bool = grown_entry["grown"]
	var expected_cost: int = maxi(_cost(target) - 1, 0)
	assert_int(shown_cost).is_equal(expected_cost)
	assert_int(grown_view.own_hand_costs[0]).is_equal(expected_cost)
	assert_int(shown_flat).is_equal(_db().card_at(target % MatchRules.DECK_SIZE).flat + 2)
	assert_bool(shown_grown).is_true()
	var plain: Dictionary = grown_view.to_dict()
	var plain_row: Array = plain["own_hand_row"]
	assert_dict(plain_row[0]).is_equal(grown_entry)


## R8: a memory on a card in seat 0's hand reaches nothing in seat 1's view: no entry names
## the card, no cost or grown mark of it shows, and the view is the same as before the
## memory was written. A revealed row card's memory is public on both sides.
func test_the_opponents_view_holds_no_entry_for_a_hand_cards_memory() -> void:
	var engine: MatchEngine = _started(SEED)
	var hand: Array[int] = _hand(engine, 0)
	var before: Dictionary = engine.view_for(1).to_dict()
	var target: int = hand[0]
	var kept: CardMemory = engine._state.memory_for(target)
	kept.flat = 2
	kept.times = 50
	kept.cost = 1
	var after: SeatView = engine.view_for(1)
	assert_dict(after.to_dict()).is_equal(before)
	for entry: Dictionary in after.own_hand_row:
		var card: int = entry["card"]
		assert_int(card).is_not_equal(target)
	var named: Array[int] = []
	_card_ids(after.to_dict(), "", named)
	assert_bool(named.has(target)).is_false()
	# A hidden row card's entry stays blank too; once revealed its memory is public.
	var state: MatchState = MatchState.new(SEED)
	var c11: int = 10
	state.seats[0].board.assign([c11])
	state.memory_for(c11).times = 25
	var budgets: Array[int] = [1, 1]
	var theirs: SeatView = SeatView.build(state, 1, 0, budgets, _defs())
	var blank: Dictionary = theirs.opponent_row[0]
	(
		assert_dict(blank)
		. is_equal(
			_printed(
				{
					"card": MatchEvent.HIDDEN_CARD,
					"flat": 0,
					"times": 100,
					"plus": 0,
					"revealed": false,
					"destroyed": false,
				},
				0
			)
		)
	)
	state.seats[0].revealed[c11] = true
	var revealed_entry: Dictionary = SeatView.build(state, 1, 0, budgets, _defs()).opponent_row[0]
	var times: int = revealed_entry["times"]
	var shown_grown: bool = revealed_entry["grown"]
	assert_int(times).is_equal(150)
	assert_bool(shown_grown).is_true()


# --- DC-09 T06 review: the known pile faces and the hidden growth ----------------------


## pile_entries: seat 0 sees its own grown destroyed card with its memory and the opponent's
## public pile card, not the opponent's hidden one; seat 1 sees both of its own and nothing
## of seat 0's pile card, which left its row face down.
func test_pile_entries_show_known_pile_cards_with_their_memory() -> void:
	var c11: int = 10
	var c04_1: int = MatchRules.DECK_SIZE + 3
	var c08_1: int = MatchRules.DECK_SIZE + 7
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].destroyed.assign([c11])
	state.seats[1].destroyed.assign([c04_1, c08_1])
	state.seats[1].destroyed_known[c08_1] = true
	state.memory_for(c11).times = 25
	state.memory_for(c11).cost = 1
	state.memory_for(c04_1).flat = 2
	var budgets: Array[int] = [1, 1]
	var mine: SeatView = SeatView.build(state, 0, 0, budgets, _defs())
	var ids: Array[int] = []
	ids.assign(mine.pile_entries.keys())
	ids.sort()
	assert_array(ids).is_equal([c11, c08_1])
	assert_bool(mine.pile_entries.has(c04_1)).is_false()
	var grown: Dictionary = {
		"card": c11, "cost": 2, "flat": 3, "times": 150, "plus": 0, "grown": true, "uses_left": -1
	}
	assert_dict(mine.pile_entries[c11]).is_equal(grown)
	var known: Dictionary = {
		"card": c08_1,
		"cost": 2,
		"flat": 4,
		"times": 100,
		"plus": 0,
		"grown": false,
		"uses_left": -1
	}
	assert_dict(mine.pile_entries[c08_1]).is_equal(known)
	# to_dict() lists the entries in id order; the hidden card's id is nowhere in the view.
	assert_array(mine.to_dict()["pile_entries"]).is_equal([grown, known])
	var named: Array[int] = []
	_card_ids(mine.to_dict(), "", named)
	assert_bool(named.has(c04_1)).is_false()
	var theirs: SeatView = SeatView.build(state, 1, 0, budgets, _defs())
	ids.assign(theirs.pile_entries.keys())
	ids.sort()
	assert_array(ids).is_equal([c04_1, c08_1])
	var flat: int = theirs.pile_entries[c04_1]["flat"]
	assert_int(flat).is_equal(5)


## R8, R73: a growth on a hand card is private to its holder; the other seat's copy names no
## card and shows neutral stats (flat 0, ×1.00, +0, cost 0, not permanent), so the grown
## values cannot name the card through the deck list. The holder's copy keeps everything.
func test_a_hidden_growth_shows_the_other_seat_neutral_stats() -> void:
	var c11: int = 10
	var state: MatchState = MatchState.new(SEED)
	state.seats[0].hand.assign([c11])
	var targets: Array[int] = [c11]
	for stat: String in [BloomEffects.STAT_TIMES, BloomEffects.STAT_COST]:
		var outcome: EffectResolver.Outcome = EffectResolver.Outcome.new()
		BloomEffects.grow(state, _defs(), 0, targets, stat, 1, outcome)
		assert_int(outcome.events.size()).is_equal(1)
		var event: MatchEvent = outcome.events[0]
		assert_int(event.owner_seat).is_equal(0)
		assert_bool(event.payload["permanent"]).is_true()
		assert_dict(event.redacted_for(0).to_dict()).is_equal(event.to_dict())
		var copy: MatchEvent = event.redacted_for(1)
		_assert_redacted(copy, event)
		var cause: String = copy.payload["cause"]
		var expected: String = "cost" if stat == BloomEffects.STAT_COST else "grow"
		assert_str(cause).is_equal(expected)


# --- R30: the full-state read ---------------------------------------------------------


## The full state holds every key the views drop, accounts for all 40 cards exactly once,
## and every card id a view holds is in it.
func test_full_state_includes_everything_the_views_omit() -> void:
	var seed_checked: bool = false
	for match_seed: int in LEAK_SEEDS:
		for step: Step in _scripted_steps(match_seed, 0):
			var state: Dictionary = step.after
			for key: String in HIDDEN_STATE_KEYS:
				assert_bool(state.has(key)).override_failure_message(key).is_true()
			assert_int(_state_int(state, "seed")).is_equal(match_seed)
			seed_checked = true
			var all_ids: Array[int] = []
			for seat: int in range(2):
				for key: String in ["deck", "hand", "board", "burned", "destroyed"]:
					all_ids.append_array(_state_list(state, key, seat))
			all_ids.append_array(_state_ints(state, "pending"))
			all_ids.sort()
			var every: Array[int] = []
			for card: int in range(2 * MatchRules.DECK_SIZE):
				every.append(card)
			assert_array(all_ids).override_failure_message(step.label).is_equal(every)
			for seat: int in range(2):
				var view_dict: Dictionary = step.views[seat].to_dict()
				for key: String in HIDDEN_STATE_KEYS:
					assert_bool(view_dict.has(key)).is_false()
				var view_ids: Array[int] = []
				_card_ids(view_dict, "", view_ids)
				for card: int in view_ids:
					# HIDDEN_CARD stands for a face-down opponent card mid-walk (DC-05 T05).
					if card != MatchEvent.HIDDEN_CARD:
						assert_bool(all_ids.has(card)).is_true()
				# What the view counts, the full state names.
				var opp: int = 1 - seat
				var opp_hand: Array[int] = _state_list(state, "hand", opp)
				assert_int(opp_hand.size()).is_equal(step.views[seat].opponent_hand_count)
	assert_bool(seed_checked).is_true()


func test_full_state_is_a_copy() -> void:
	var engine: MatchEngine = _started(SEED)
	var before: Dictionary = engine.full_state()
	var state: Dictionary = engine.full_state()
	var hands: Array = state["hand"]
	var hand: Array = hands[0]
	hand.clear()
	state["seed"] = 0
	assert_dict(engine.full_state()).is_equal(before)


## One captured scripted step.
class Step:
	extends RefCounted

	var label: String = ""
	var before: Dictionary = {}
	var after: Dictionary = {}
	var result: ApplyResult = null
	var awaited: int = -1
	var energy: int = 0
	var views: Array[SeatView] = []
