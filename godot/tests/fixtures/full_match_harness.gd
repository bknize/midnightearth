class_name FullMatchHarness
extends GdUnitTestSuite
## The shared play-and-check helpers of the full-match suites (test_full_match.gd in the
## gate, tests/sweep/test_sweep.gd outside it): _play runs one bot-vs-bot match checking
## every invariant at every step, and _assert_run asserts them. It holds no test of its own
## and is not a suite (not test_*.gd).
##
## Rules 7 (DC-13 T03; cycle 9 plan P15, spec R57 to R59): the leak scan treats as hidden
## from a seat the other seat's hand, Deck, face-down Commit and the face-down row cards it
## has not looked at; Pile cards are never hidden, and a card that enters a Pile may be
## named from then on. A view must list both Piles in full, show a face-down opposing row
## card with no id, stats or Memory, and name a looked-at card only in its own seat's
## `looked`. Hands are bounded by the Hand size plus the Turn's draw (the discard-down).

## The shipped decks (cycle 9 R61; milestone B's four since DC-14 T14), in file order; the
## sweep's pairings are "a/b" of them.
const DECKS: Array[String] = ["greed", "ramp", "combo", "disruption", "graveyard", "control"]
const MAX_ACTIONS: int = 2000
## Quartermaster's Hand size (rules/crew-v2), the largest any shipped deck sets: no deck
## lists Pantry, so no "+N" adds to it.
const SET_HAND_SIZE: int = 7
## Dross one Litter creates in the opposing hand (rules/cards-v2, DC-14 T12).
const LITTER_DROSS: int = 3
## The largest hand a seat can hold under rules 7 with the six decks, between two of its
## discard-downs (DC-14 T14 raised it: Litter puts Dross into the opposing hand, Twin
## copies itself into its own, Fleeting returns cards from the row, and Reprise makes every
## card Score twice): its Hand size after the discard-down (Quartermaster's 7), plus the
## Turn's draw, plus one Walk's effect draws with every card Scoring twice (four Couriers
## or Wicks of its own and four of the opponent's Bounties: 2 × 2 × MAX_COPIES), the Dross
## of four opposing Litters, four Twins' copies with Encore's retrigger (2 × MAX_COPIES) and
## the returns of a Fleeting row at turn end (Reverb, Reprieve, Veil: 2 × MAX_COPIES).
## Salvager's Discard-then-draw adds nothing. A sanity bound against a runaway, not a tight
## one.
const HAND_BOUND: int = (
	SET_HAND_SIZE
	+ 1
	+ 4 * MatchRules.MAX_COPIES
	+ LITTER_DROSS * MatchRules.MAX_COPIES
	+ 2 * MatchRules.MAX_COPIES
	+ 2 * MatchRules.MAX_COPIES
)

var _cached_db: CardDb = null
var _cached_decks: DeckList = null

# --- Helpers --------------------------------------------------------------------------


## The shipped pool (the 90 Deck cards and the created-only Dross).
func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


## The shipped deck list (DECKS).
func _decks() -> DeckList:
	if _cached_decks == null:
		_cached_decks = DeckList.load_default()
	return _cached_decks


## Both seats' decks left to the seed's own pairing, as main.gd's smoke does.
func _seeded() -> Array[String]:
	var out: Array[String] = ["", ""]
	return out


## A match on `match_seed` under its seeded pairing (not started).
func _new_engine(match_seed: int) -> MatchEngine:
	return MatchEngine.create(match_seed, _db(), _decks(), _seeded(), CrewPool.load_default())


## A match on `match_seed` with the named shipped decks `deck_ids`, seat 0's first (not
## started): the sweep's fixed pairings (DC-14 T14).
func _named_engine(match_seed: int, deck_ids: Array[String]) -> MatchEngine:
	return MatchEngine.create(match_seed, _db(), _decks(), deck_ids, CrewPool.load_default())


## The pairing of a match as "a/b" (seat 0's deck, then seat 1's).
func _pairing(engine: MatchEngine) -> String:
	var ids: Array[String] = engine.deck_ids()
	if ids.size() != MatchEngine.SEATS:
		return "?/?"
	return "%s/%s" % [ids[0], ids[1]]


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


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


## The Cost of one card instance of a match on `deck_ids`, from the pool and the list
## (id = Owner * DECK_SIZE + index): its printed Cost, or its `cost_on_turn` Cost on the
## Turn that ability names, plus its Memory's `cost_delta` (the full state's "memory"),
## never below MatchRules.MIN_COST. An unknown id costs more than any Budget.
func _card_cost(deck_ids: Array[String], card: int, state: Dictionary) -> int:
	var def: CardDef = _def_of(deck_ids, card, state)
	if def == null:
		return MAX_ACTIONS
	var cost: int = def.cost
	var turn: int = _state_int(state, "turn")
	for ability: CardAbility in def.abilities:
		if ability.verb == Scoring.COST_ON_TURN_VERB and ability.amount_2 == turn:
			cost = ability.amount
	var memory: Dictionary = state.get("memory", {})
	var kept: Dictionary = memory.get(card, {})
	var delta: int = kept.get("cost_delta", 0)
	return maxi(cost + delta, MatchRules.MIN_COST)


## The definition of one card instance of a match on `deck_ids`: a Deck card's from the
## pool and the list (id = Owner * DECK_SIZE + index), a created card's (DC-14 T12) from the
## full state's `created` {def, owner}; null when unknown.
func _def_of(deck_ids: Array[String], card: int, state: Dictionary) -> CardDef:
	if card >= MatchCards.CREATED_BASE:
		var created: Dictionary = state.get("created", {})
		var made: Dictionary = created.get(card, {})
		var def_id: String = made.get("def", "")
		return _db().card_by_id(def_id)
	var origin: int = card / MatchRules.DECK_SIZE
	if card < 0 or origin >= deck_ids.size():
		return null
	var listed: Array[String] = _decks().card_ids(deck_ids[origin])
	var index: int = card % MatchRules.DECK_SIZE
	if index >= listed.size():
		return null
	return _db().card_by_id(listed[index])


## The summed Cost of a Commit whose cards are in slot order, less the leftmost card's when
## `seat` holds the free first card, both read from the full state `state`: computed here
## from the pool, the list and the Memory, not through LegalPlays or Scoring.
func _commit_cost(state: Dictionary, seat: int, cards: Array[int]) -> int:
	var deck_ids: Array[String] = []
	var listed: Array = state["deck_ids"]
	deck_ids.assign(listed)
	var total: int = 0
	for card: int in cards:
		total += _card_cost(deck_ids, card, state)
	if _free_first(state, seat) and not cards.is_empty():
		total -= _card_cost(deck_ids, cards[0], state)
	return total


## Whether `seat` holds the free first card in a full-state dictionary.
func _free_first(state: Dictionary, seat: int) -> bool:
	var energy: Dictionary = state["energy"]
	var flags: Array = energy["free_first"]
	var granted: bool = flags[seat]
	return granted


## Every id of `seat`'s cards its opponent may not know in `state` (P15), as a set: its
## hand and Deck, its share of the face-down Commit (the first committer's `pending`), and
## the cards face down on its row that the opponent has not looked at. Pile cards are
## public and never in it.
func _hidden_set(state: Dictionary, seat: int) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["hand", "deck"]:
		for card: int in _state_list(state, key, seat):
			out[card] = true
	if _state_int(state, "first_seat") == seat:
		for card: int in _state_ints(state, "pending"):
			out[card] = true
	var revealed: Array[int] = _state_list(state, "revealed", seat)
	var looked: Array[int] = _state_list(state, "looked", 1 - seat)
	for card: int in _state_list(state, "board", seat):
		if not revealed.has(card) and not looked.has(card):
			out[card] = true
	return out


## The cards `seat` knows itself in `state`: its hand, row (face up or down), its pending
## Commit when it committed first, and the opposing face-down cards it has looked at.
func _own_set(state: Dictionary, seat: int) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["hand", "board", "looked"]:
		for card: int in _state_list(state, key, seat):
			out[card] = true
	if _state_int(state, "first_seat") == seat:
		for card: int in _state_ints(state, "pending"):
			out[card] = true
	return out


## Both seats' hidden sets (_hidden_set) and own sets (_own_set) of `state`, indexed by seat.
func _sets_of(state: Dictionary) -> FullMatchRun.StateSets:
	var out: FullMatchRun.StateSets = FullMatchRun.StateSets.new()
	for seat: int in range(MatchEngine.SEATS):
		out.hidden.append(_hidden_set(state, seat))
		out.own.append(_own_set(state, seat))
	return out


## Every card id a view names outside `looked`: its card-id fields, each row entry's `card`
## and the open prompt's source `card` (its options are positions, not ids).
func _view_card_ids(view: SeatView) -> Array[int]:
	var out: Array[int] = []
	out.append_array(view.own_hand)
	out.append_array(view.own_pending)
	out.append_array(view.own_board)
	out.append_array(view.opponent_board)
	out.append_array(view.own_pile)
	out.append_array(view.opponent_pile)
	out.append_array(view.pile_entries.keys())
	out.append_array(view.deck_top)
	var entries: Array[Dictionary] = []
	entries.append_array(view.own_row)
	entries.append_array(view.opponent_row)
	for entry: Dictionary in entries:
		var shown: Variant = entry.get(MatchEvent.KEY_CARD)
		if shown is int:
			var card: int = shown
			out.append(card)
	var source: Variant = view.prompt.get(MatchEvent.KEY_CARD)
	if source is int:
		var prompt_card: int = source
		out.append(prompt_card)
	return out


func _has_kind(result: ApplyResult, kind: int) -> bool:
	for event: MatchEvent in result.events:
		if event.kind == kind:
			return true
	return false


## The bot both seats play: the registry's default. The sweep suite overrides it.
func _bot_name() -> String:
	return BotRegistry.default_name()


## One bot per seat on the match's own definitions, as main.gd's smoke builds them:
## _bot_name() from the registry. An entry is null when the registry cannot build the bot.
func _new_bots(match_seed: int, engine: MatchEngine) -> Array[BotPlayer]:
	var bots: Array[BotPlayer] = []
	var bot_name: String = _bot_name()
	var cards: MatchCards = engine.match_cards()
	for seat: int in range(MatchEngine.SEATS):
		var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
		bots.append(BotRegistry.make(bot_name, bot_seed, cards))
	return bots


## Plays `match_seed` bot against bot to the end or the cap, checking every invariant at
## every step. `scan_every_step` false leak-scans only the start and turn-ending steps.
## `deck_ids` names both seats' decks; empty plays the seed's own pairing (_new_engine()).
func _play(
	match_seed: int, scan_every_step: bool, deck_ids: Array[String] = []
) -> FullMatchRun:
	var run: FullMatchRun = FullMatchRun.new()
	run.match_seed = match_seed
	var engine: MatchEngine = null
	if deck_ids.is_empty():
		engine = _new_engine(match_seed)
	else:
		engine = _named_engine(match_seed, deck_ids)
	run.engine = engine
	run.pairing = _pairing(engine)
	var before: Dictionary = engine.full_state()
	var result: ApplyResult = engine.start()
	run.start_ok = result.ok
	if not result.ok:
		return run
	var after: Dictionary = engine.full_state()
	_check_step(run, before, after, result, true)
	var bots: Array[BotPlayer] = _new_bots(match_seed, engine)
	if bots.has(null):
		run.rejections.append("BotRegistry built no %s bot" % _bot_name())
		return run
	run.bot = bots[0].bot_name()
	while not engine.is_over():
		if run.actions >= MAX_ACTIONS:
			run.capped = true
			return run
		var seat: int = engine.awaited_seat()
		if seat < 0 or seat >= MatchEngine.SEATS:
			run.rejections.append("action %d: no seat awaited mid-match" % run.actions)
			return run
		var view: SeatView = engine.view_for(seat)
		var started_us: int = Time.get_ticks_usec()
		var action: EngineAction = bots[seat].choose(view, engine)
		var took_us: int = Time.get_ticks_usec() - started_us
		run.decision_us.append(took_us)
		run.slowest_us = maxi(run.slowest_us, took_us)
		var prompt: Dictionary = engine.open_prompt()
		_check_commit(run, action, seat, engine.budget_for(seat), after, prompt)
		before = after
		run.sets_before = run.sets_after
		run.sets_after = null
		result = engine.apply(action)
		if not result.ok:
			run.rejections.append("action %d rejected, code %d" % [run.actions, result.error])
			return run
		run.actions += 1
		for event: MatchEvent in result.events:
			if event.kind == MatchEvent.Kind.PILE_SHUFFLED_IN:
				run.pile_shuffles += 1
		if _has_kind(result, MatchEvent.Kind.WALK_STARTED):
			run.longest_walk = maxi(run.longest_walk, _walk_pulses(before, action))
		after = engine.full_state()
		var scan: bool = scan_every_step
		if not scan:
			scan = (
				_has_kind(result, MatchEvent.Kind.TURN_ENDED)
				or _has_kind(result, MatchEvent.Kind.MATCH_ENDED)
			)
		_check_step(run, before, after, result, scan)
		_record_end(run, result)
	return run


## The pulses of the Walk that `action` starts from `before`: one per slot of both rows at
## Walk start, so both rows as they stood, the first Commit held in `pending` and the
## Commit's cards (an answer to the second seat's discard-down adds none).
func _walk_pulses(before: Dictionary, action: EngineAction) -> int:
	var pulses: int = _state_ints(before, "pending").size() + action.cards.size()
	for seat: int in range(MatchEngine.SEATS):
		pulses += _state_list(before, "board", seat).size()
	return pulses


## The bot's action is for the awaited seat: a Commit costing no more than its Budget (with
## the free first card and each card's Cost read from `state`, the full state the bot chose
## on), or, while a prompt is open, a choice: a set for a multi-select prompt, every index
## offered, none repeated and exactly its `exact` (the discard-down, counted), else a single
## position, or on an optional prompt the decline.
func _check_commit(
	run: FullMatchRun,
	action: EngineAction,
	seat: int,
	energy: int,
	state: Dictionary,
	prompt: Dictionary
) -> void:
	var where: String = "action %d" % run.actions
	if action == null:
		run.rejections.append(where + ": the bot returned null")
		return
	var prompted: bool = not prompt.is_empty()
	var multi: bool = Choice.is_multi_prompt(prompt)
	var kind: int = EngineAction.Kind.COMMIT
	if multi:
		kind = EngineAction.Kind.CHOOSE_SET
		run.set_answers += 1
		if TurnFlow.is_discard_down(prompt):
			run.discard_downs += 1
		if not Choice.is_valid_set(prompt, Choice.zone_of(prompt), action.indices):
			run.rejections.append(where + ": set %s not offered" % [action.indices])
	elif prompted:
		kind = EngineAction.Kind.CHOOSE
		if Choice.is_optional_prompt(prompt) and action.kind == EngineAction.Kind.DECLINE:
			kind = EngineAction.Kind.DECLINE
			run.declines += 1
	if prompted and Choice.crew_of(prompt) != "":
		run.crew_prompts += 1
	if action.kind != kind or action.seat != seat:
		run.rejections.append(where + ": not the awaited action kind for seat %d" % seat)
	if prompted:
		run.choices += 1
		return
	var cost: int = _commit_cost(state, seat, action.cards)
	if cost > energy:
		run.energy_violations.append(where + ": cost %d over energy %d" % [cost, energy])


## The hand bound for both seats after the step, then (when `scan`) the leak scan.
func _check_step(
	run: FullMatchRun, before: Dictionary, after: Dictionary, result: ApplyResult, scan: bool
) -> void:
	for seat: int in range(MatchEngine.SEATS):
		var size: int = _state_list(after, "hand", seat).size()
		run.max_hand = maxi(run.max_hand, size)
		if size > HAND_BOUND:
			run.hand_violations.append(
				"after action %d: seat %d holds %d" % [run.actions, seat, size]
			)
	if scan:
		_scan_leaks(run, before, after, result)


## For both seats: the view names no id hidden from it now, and its redacted events name
## no id that was hidden from it before or after the step, less a card named while it was
## public within the step, in event order (_public_windows: face up on a row or in a Pile at
## the step's start, from its CARD_REVEALED, its public exit to a Pile, its CARD_DISCARDED or
## its public hand trigger (C14) on, until a Pile shuffle puts it back into a Deck or, after
## its CARD_UNREVEALED, it lies face down). An event naming a card before the card became
## public is a leak, even when the card is public by the step's end (DC-13 T10 review, Ben
## 2a).
func _scan_leaks(
	run: FullMatchRun, before: Dictionary, after: Dictionary, result: ApplyResult
) -> void:
	run.steps_scanned += 1
	if run.sets_before == null:
		run.sets_before = _sets_of(before)
	if run.sets_after == null:
		run.sets_after = _sets_of(after)
	for event: MatchEvent in result.events:
		if event.kind == MatchEvent.Kind.DRAW_EMPTY:
			run.empty_draws += 1
	var windows: PublicWindows = _public_windows(before, after, result)
	for seat: int in range(MatchEngine.SEATS):
		var opp: int = 1 - seat
		var where: String = "after action %d, seat %d" % [run.actions, seat]
		var hidden_now: Dictionary = run.sets_after.hidden[opp]
		var view: SeatView = run.engine.view_for(seat)
		for card: int in _view_card_ids(view):
			if hidden_now.has(card):
				run.leaks.append(where + ": view names hidden card %d" % card)
		if view.opponent_pending_count > 0:
			run.face_down_seen += 1
		_scan_prompt(run, view, where)
		_scan_hidden_rows(run, view, where)
		_scan_piles(run, view, after, where)
		_scan_looked(run, view, after, where)
		var hidden_during: Dictionary = run.sets_before.hidden[opp].duplicate()
		hidden_during.merge(hidden_now)
		var own_known: Dictionary = run.sets_before.own[seat].duplicate()
		own_known.merge(run.sets_after.own[seat])
		var seen: Array[MatchEvent] = result.events_for(seat)
		for at: int in range(seen.size()):
			var event: MatchEvent = seen[at]
			if event.is_private() and event.owner_seat == opp:
				run.redacted_seen += 1
				if FullMatchRun.is_memory_kind(event.kind):
					run.memory_hidden_seen += 1
					run.check_neutral_stats(event, where)
			# A seat's own CARD_LOOKED names what it was shown (Lookout, Delve), even when the
			# card is revealed later in the step and leaves `looked`.
			if event.kind == MatchEvent.Kind.CARD_LOOKED and event.owner_seat == seat:
				continue
			for card: int in FullMatchRun.event_card_ids(event):
				if _public_at(windows, card, at):
					continue
				if hidden_during.has(card) and not own_known.has(card):
					run.leaks.append(
						where + ": event %s names hidden card %d" % [
							MatchEvent.kind_name(event.kind), card
						]
					)


## When each card was public during the step of `result` (event positions): from -1 for a
## card face up on a row or in a Pile in `before`; otherwise from the event that made it
## public: its CARD_REVEALED, its EXIT_RESOLVED to a Pile, its CARD_DISCARDED, or a
## TRIGGER_FIRED / TRIGGER_FIZZLED of it firing from its hand (`from_hand`, C14); until the
## PILE_SHUFFLED_IN that put it into its seat's Deck (one found in that Deck in `after`), or
## the event after its CARD_UNREVEALED: the un-reveal may name the card it flips (Shade,
## Fade; DC-14 T14), but a later event of the step may not unless another window opens
## (DC-14 T17).
func _public_windows(before: Dictionary, after: Dictionary, result: ApplyResult) -> PublicWindows:
	var out: PublicWindows = PublicWindows.new()
	for seat: int in range(MatchEngine.SEATS):
		for key: String in ["revealed", "pile"]:
			for card: int in _state_list(before, key, seat):
				out.since[card] = -1
	for at: int in range(result.events.size()):
		var event: MatchEvent = result.events[at]
		if _opens_window(event):
			for card: int in FullMatchRun.event_card_ids(event):
				out.open(card, at)
		elif event.kind == MatchEvent.Kind.CARD_UNREVEALED:
			# The un-reveal itself names the card it flips (its id was just seen face up);
			# from the next event on it is a face-down card again (DC-14 T17).
			var flipped: int = event.payload.get(MatchEvent.KEY_CARD, MatchEvent.HIDDEN_CARD)
			if flipped >= 0:
				out.close(flipped, at + 1)
		elif event.kind == MatchEvent.Kind.PILE_SHUFFLED_IN:
			var seat: int = event.payload.get("seat", -1)
			if seat < 0 or seat >= MatchEngine.SEATS:
				continue
			for card: int in _state_list(after, "deck", seat):
				out.close(card, at)
	return out


## Whether `event` makes the cards it names public from its position on (_public_windows).
func _opens_window(event: MatchEvent) -> bool:
	match event.kind:
		MatchEvent.Kind.CARD_REVEALED, MatchEvent.Kind.CARD_DISCARDED:
			return not event.is_private()
		MatchEvent.Kind.CARD_CREATED:
			# A creation is public (DC-14 T12): the new card is named once, then it is the
			# holding seat's hidden hand card like any other.
			return not event.is_private()
		MatchEvent.Kind.EXIT_RESOLVED:
			var to: String = event.payload.get("to", "")
			return not event.is_private() and to == "pile"
		MatchEvent.Kind.TRIGGER_FIRED, MatchEvent.Kind.TRIGGER_FIZZLED:
			var from_hand: bool = event.payload.get(MatchEvent.KEY_FROM_HAND, false)
			return not event.is_private() and from_hand
	return false


## Whether `card` was public at event position `at` of the step (_public_windows).
func _public_at(windows: PublicWindows, card: int, at: int) -> bool:
	if not windows.since.has(card) or windows.since[card] > at:
		return false
	return not windows.until.has(card) or at < windows.until[card]


## An open prompt as `view`'s seat sees it: a prompt for the other seat shows only {open,
## seat}, so a prompt's zone, options, verb and Crew reach the asked seat alone; a Crew
## prompt the asked seat sees is counted (crew_prompts_scanned).
func _scan_prompt(run: FullMatchRun, view: SeatView, where: String) -> void:
	if view.prompt.is_empty():
		return
	var asked: int = view.prompt.get("seat", -1)
	if asked != view.seat:
		var only: bool = view.prompt.size() == 2 and view.prompt.has("open")
		if not only:
			run.leaks.append(where + ": the other seat's prompt shows %s" % [view.prompt.keys()])
		return
	if Choice.crew_of(view.prompt) != "":
		run.crew_prompts_scanned += 1


## A face-down card on the opponent's row shows neither its id nor its stats nor its
## Memory: Power 0, no Bonus, cost 0, grown false, uses_left -1, no statuses, no exit mark.
func _scan_hidden_rows(run: FullMatchRun, view: SeatView, where: String) -> void:
	for slot: int in range(view.opponent_row.size()):
		var entry: Dictionary = view.opponent_row[slot]
		var revealed: bool = entry.get("revealed", false)
		if revealed:
			continue
		var card: int = entry.get(MatchEvent.KEY_CARD, MatchEvent.HIDDEN_CARD)
		var power: int = entry.get("power", 0)
		var mult: int = entry.get("mult", MatchRules.BONUS_ONE)
		var add: int = entry.get("add", 0)
		if card != MatchEvent.HIDDEN_CARD or power != 0 or mult != MatchRules.BONUS_ONE or add != 0:
			run.leaks.append(where + ": face-down slot %d shows its card" % slot)
		var cost: int = entry.get("cost", 0)
		var grown: bool = entry.get("grown", false)
		var uses_left: int = entry.get("uses_left", -1)
		var statuses: Array = entry.get("statuses", [])
		var mark: String = entry.get("exit_mark", "")
		if cost != 0 or grown or uses_left != -1 or not statuses.is_empty() or mark != "":
			run.leaks.append(where + ": face-down slot %d shows its memory" % slot)
		var on_board: int = MatchEvent.HIDDEN_CARD
		if slot < view.opponent_board.size():
			on_board = view.opponent_board[slot]
		if on_board != MatchEvent.HIDDEN_CARD:
			run.leaks.append(where + ": opponent_board names face-down slot %d" % slot)


## Both Piles are public (R19, P15): the view lists each in full and in Pile order, every
## entry with its stats.
func _scan_piles(run: FullMatchRun, view: SeatView, after: Dictionary, where: String) -> void:
	var own: Array[int] = _state_list(after, "pile", view.seat)
	var theirs: Array[int] = _state_list(after, "pile", view.opponent)
	if view.own_pile != own:
		run.leaks.append(where + ": own Pile shows %s, holds %s" % [view.own_pile, own])
	if view.opponent_pile != theirs:
		run.leaks.append(where + ": opponent Pile shows %s, holds %s" % [view.opponent_pile, theirs])
	run.pile_seen += theirs.size()
	for card: int in own + theirs:
		if not view.pile_entries.has(card):
			run.leaks.append(where + ": Pile card %d has no entry" % card)


## `looked` names only opposing face-down cards this seat has looked at (R59).
func _scan_looked(run: FullMatchRun, view: SeatView, after: Dictionary, where: String) -> void:
	var known: Array[int] = _state_list(after, "looked", view.seat)
	for slot: int in view.looked:
		var card: int = view.looked[slot]
		run.looked_seen += 1
		if not known.has(card):
			run.leaks.append(where + ": looked names %d, not looked at" % card)


func _record_end(run: FullMatchRun, result: ApplyResult) -> void:
	for event: MatchEvent in result.events:
		if event.kind == MatchEvent.Kind.MATCH_ENDED:
			run.end_payload = event.payload.duplicate(true)


## The match result in the smoke line's terms; empty when the match did not end.
func _summary(run: FullMatchRun) -> Dictionary:
	if run.end_payload.is_empty():
		return {}
	var winner: int = run.end_payload["winner"]
	var reason: String = run.end_payload["reason"]
	var rounds: int = run.end_payload["rounds_played"]
	var raw_wins: Array = run.end_payload["wins"]
	var wins: Array[int] = _typed(raw_wins)
	return {
		"decks": run.pairing,
		"winner": winner,
		"wins": "%d-%d" % [wins[0], wins[1]],
		"rounds": rounds,
		"reason": reason,
		"actions": run.actions,
	}


## The match result as one line in the smoke line's terms (GOLDEN's format):
## "seed=.. decks=a/b bot=<name> winner=.. wins=a-b rounds=.. end=<reason> actions=..";
## empty when the match did not end.
func _result_line(run: FullMatchRun) -> String:
	var got: Dictionary = _summary(run)
	if got.is_empty():
		return ""
	var fields: Array = [run.match_seed, got["decks"], run.bot, got["winner"], got["wins"]]
	fields.append_array([got["rounds"], got["reason"], got["actions"]])
	return "seed=%d decks=%s bot=%s winner=%d wins=%s rounds=%d end=%s actions=%d" % fields


## Writes the log to JSON, reads it back and replays it with the shipped pool and list;
## "" when the replayed full state (deck ids included) and log equal the original's, else
## what went wrong.
func _replay_problem(engine: MatchEngine) -> String:
	var text: String = engine.action_log().to_json()
	var parsed: ActionLog = ActionLog.from_json(text)
	var parse_problem: String = _parsed_problem(parsed, engine)
	if parse_problem != "":
		return parse_problem
	var crew: CrewPool = CrewPool.load_default()
	var replayed: ReplayResult = parsed.replay(_db(), _decks(), crew)
	if not replayed.ok:
		return (
			"replay failed: reason %d at index %d, code %d"
			% [replayed.reason, replayed.failed_index, replayed.error]
		)
	if replayed.engine.full_state() != engine.full_state():
		return "replayed full state differs from the original"
	if replayed.engine.action_log().to_json() != text:
		return "replayed log differs from the original"
	return ""


## "" when the parsed log holds every accepted action and names the decks the match
## played, else what went wrong.
func _parsed_problem(parsed: ActionLog, engine: MatchEngine) -> String:
	if parsed == null:
		return "the log's JSON did not parse back"
	if parsed.actions.size() != engine.accepted_action_count():
		return "parsed %d actions of %d" % [parsed.actions.size(), engine.accepted_action_count()]
	if parsed.deck_ids != engine.deck_ids():
		return "the log names decks %s, the match played %s" % [parsed.deck_ids, engine.deck_ids()]
	return ""


## Every invariant of one run, each failure labelled with the seed.
func _assert_run(run: FullMatchRun) -> void:
	var label: String = "seed %d: " % run.match_seed
	var capped: String = label + "not over after %d actions" % MAX_ACTIONS
	var no_end: String = label + "no MATCH_ENDED event"
	assert_bool(run.start_ok).override_failure_message(label + "start failed").is_true()
	assert_bool(run.capped).override_failure_message(capped).is_false()
	_assert_none(run.rejections, label + "rejected or malformed bot action")
	assert_bool(run.engine.is_over()).override_failure_message(label + "did not end").is_true()
	assert_bool(run.end_payload.is_empty()).override_failure_message(no_end).is_false()
	_assert_none(run.hand_violations, label + "hand over the bound")
	var cap: int = HAND_BOUND
	assert_int(run.max_hand).override_failure_message(label + "hand over bound").is_less_equal(cap)
	_assert_none(run.energy_violations, label + "commit over energy")
	_assert_none(run.leaks, label + "hidden card leaked")
	var scanned: String = label + "nothing leak-scanned"
	assert_int(run.steps_scanned).override_failure_message(scanned).is_greater(0)
	var replay_problem: String = _replay_problem(run.engine)
	assert_str(replay_problem).override_failure_message(label + replay_problem).is_empty()


func _assert_none(found: Array[String], what: String) -> void:
	var message: String = "%s: %s" % [what, found]
	assert_array(found).override_failure_message(message).is_empty()


## Plays `match_seed` bot against bot under its seeded pairing, as _play() does but with no
## checks, keeping both seats' views after the start and after every action, and every
## event of each step in full and as each seat's redacted copy (cycle 12 T01's round
## trips).
func _played_steps(match_seed: int) -> PlayedSteps:
	var played: PlayedSteps = PlayedSteps.new()
	var engine: MatchEngine = _new_engine(match_seed)
	var result: ApplyResult = engine.start()
	if not result.ok:
		return played
	played.keep(engine, result)
	var bots: Array[BotPlayer] = _new_bots(match_seed, engine)
	if bots.has(null):
		return played
	while not engine.is_over() and played.actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		if seat < 0 or seat >= MatchEngine.SEATS:
			return played
		result = engine.apply(bots[seat].choose(engine.view_for(seat), engine))
		if not result.ok:
			return played
		played.actions += 1
		played.keep(engine, result)
	played.over = engine.is_over()
	return played


## One played match's views and events (_played_steps).
class PlayedSteps:
	extends RefCounted

	var over: bool = false
	var actions: int = 0
	var views: Array[SeatView] = []
	var events: Array[MatchEvent] = []

	## Both seats' views of `engine` now, and `result`'s events in full and redacted.
	func keep(engine: MatchEngine, result: ApplyResult) -> void:
		events.append_array(result.events)
		for seat: int in range(MatchEngine.SEATS):
			views.append(engine.view_for(seat))
			events.append_array(result.events_for(seat))


## The positions of a step's events between which each card was public (_public_windows).
class PublicWindows:
	extends RefCounted

	var since: Dictionary[int, int] = {}
	var until: Dictionary[int, int] = {}

	## `card` is public from position `at` on, unless it already is.
	func open(card: int, at: int) -> void:
		if not since.has(card) or until.has(card):
			since[card] = at
			if until.erase(card):
				pass  # Public again from this event.

	## `card` stops being public at position `at`, if it was public.
	func close(card: int, at: int) -> void:
		if since.has(card) and not until.has(card):
			until[card] = at
