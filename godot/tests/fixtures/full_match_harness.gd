class_name FullMatchHarness
extends GdUnitTestSuite
## The shared play-and-check helpers of the full-match suites (split out of
## test_full_match.gd at NSC-133 so the 50-seed sweep can live in tests/sweep/, outside the
## gate): _play runs one bot-vs-bot match checking every invariant at every step, and
## _assert_run asserts them. It holds no test of its own and is not a suite (not test_*.gd).
## See test_full_match.gd for what a match checks and test_sweep.gd for the sweep.

## The shipped decks (cycle 9 R61, milestone A); the sweep's pairings are every "a/b" of them.
const DECKS: Array[String] = ["greed", "ramp"]
const MAX_ACTIONS: int = 2000
## The largest hand a seat can hold under the DC-13 T02 interim rules: the opening hand plus
## one draw a turn, with no cap and no burn (hands go back to the Deck at round start; the
## discard-down to MatchRules.HAND_SIZE lands with T03).
const HAND_BOUND: int = MatchRules.OPENING_HAND + MatchRules.TURNS

var _cached_db: CardDb = null
var _cached_decks: DeckList = null

# --- Helpers --------------------------------------------------------------------------


## The shipped pool (DC-13 T02: the 30 evergreen, 10 Greed and 10 Ramp cards).
func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


## The shipped deck list (DECKS).
func _decks() -> DeckList:
	if _cached_decks == null:
		_cached_decks = DeckList.load_default()
	return _cached_decks


## Both seats' decks left to the seed's own pairing (R6, P14), as main.gd's smoke does.
func _seeded() -> Array[String]:
	var out: Array[String] = ["", ""]
	return out


## A match on `match_seed` under its seeded pairing (not started).
func _new_engine(match_seed: int) -> MatchEngine:
	return MatchEngine.create(match_seed, _db(), _decks(), _seeded(), CrewPool.load_default())


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


## The cost of one card instance of a match on `deck_ids`, from the pool and the list: its
## origin seat's deck, its index in that deck (DC-07 P3: id = origin * 20 + index), less the
## reduction in its `memory` entry (the full state's "memory", cycle 8 P2, P3), never below
## MatchRules.MIN_COST. An unknown id costs more than any energy.
func _card_cost(deck_ids: Array[String], card: int, memory: Dictionary) -> int:
	var origin: int = card / MatchRules.DECK_SIZE
	if card < 0 or origin >= deck_ids.size():
		return MAX_ACTIONS
	var listed: Array[String] = _decks().card_ids(deck_ids[origin])
	var index: int = card % MatchRules.DECK_SIZE
	if index >= listed.size():
		return MAX_ACTIONS
	var def: CardDef = _db().card_by_id(listed[index])
	if def == null:
		return MAX_ACTIONS
	var kept: Dictionary = memory.get(card, {})
	var reduction: int = kept.get("cost", 0)
	return maxi(def.cost - reduction, MatchRules.MIN_COST)


## The summed cost of a commit whose cards are in slot order, less the leftmost card's when
## `seat` holds the free first card (R10), both read from the full state `state`: computed
## here from the pool, the list and the memory, not through LegalPlays.
func _commit_cost(state: Dictionary, seat: int, cards: Array[int]) -> int:
	var deck_ids: Array[String] = []
	var listed: Array = state["deck_ids"]
	deck_ids.assign(listed)
	var memory: Dictionary = state.get("memory", {})
	var total: int = 0
	for card: int in cards:
		total += _card_cost(deck_ids, card, memory)
	if _free_first(state, seat) and not cards.is_empty():
		total -= _card_cost(deck_ids, cards[0], memory)
	return total


## Whether `seat` holds the free first card in a full-state dictionary.
func _free_first(state: Dictionary, seat: int) -> bool:
	var energy: Dictionary = state["energy"]
	var flags: Array = energy["free_first"]
	var granted: bool = flags[seat]
	return granted


## Every id of `seat`'s cards its opponent may not know in `state`, as a set: its hand,
## deck and burn pile, its share of the face-down commit, and the cards on its row not yet
## revealed (while a prompt pauses a walk, DC-05 T05, or left face down behind the cursor by
## a swap, DC-06 R8), destroyed or not (DC-06 R20), and the entries of its destroyed pile
## whose identity is not public (DC-07 R18). The face-down commit is the first committer's,
## whatever the cards' origin (a recovered card, DC-07 C12).
func _hidden_set(state: Dictionary, seat: int) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["hand", "deck", "burned"]:
		for card: int in _state_list(state, key, seat):
			out[card] = true
	if _state_int(state, "first_seat") == seat:
		for card: int in _state_ints(state, "pending"):
			out[card] = true
	var known: Array[int] = _state_list(state, "destroyed_known", seat)
	for card: int in _state_list(state, "destroyed", seat):
		if not known.has(card):
			out[card] = true
	var revealed: Array[int] = _state_list(state, "revealed", seat)
	for card: int in _state_list(state, "board", seat):
		if not revealed.has(card):
			out[card] = true
	return out


## The cards `seat` holds itself in `state`: hand, row (face up or down), burn pile,
## destroyed pile, and its pending cards when it committed first.
func _own_set(state: Dictionary, seat: int) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["hand", "board", "burned", "destroyed"]:
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


## Every card id a view names: its card-id fields, each row entry's `card` and the open
## prompt's source `card` (its options are positions, not ids).
func _view_card_ids(view: SeatView) -> Array[int]:
	var out: Array[int] = []
	out.append_array(view.own_hand)
	out.append_array(view.own_pending)
	out.append_array(view.own_board)
	out.append_array(view.opponent_board)
	out.append_array(view.own_destroyed)
	out.append_array(view.opponent_destroyed)
	# The known pile faces (DC-09 T06 review): a hidden pile card must have no entry.
	out.append_array(view.pile_entries.keys())
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


## The bot both seats play: the registry's default. The sweep suite overrides it (NSC-133).
func _bot_name() -> String:
	return BotRegistry.default_name()


## One bot per seat on the match's own definitions (each card through its origin's deck),
## as main.gd's smoke builds them: _bot_name() from the registry. An entry is null when the
## registry cannot build the bot (_play reports it).
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
func _play(match_seed: int, scan_every_step: bool) -> FullMatchRun:
	var run: FullMatchRun = FullMatchRun.new()
	run.match_seed = match_seed
	var engine: MatchEngine = _new_engine(match_seed)
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
		# The seat's budget, not the turn: a carry card raises it (DC-05 T04, R9), and the
		# free first card makes the leftmost card free (R10); `after` is the state chosen on.
		var prompt: Dictionary = engine.open_prompt()
		_check_commit(run, action, seat, engine.budget_for(seat), after, prompt)
		# This step's "before" is the last step's "after": its full state and, when the last
		# step was scanned, its hidden and own sets (NSC-97), so each state is read once.
		before = after
		run.sets_before = run.sets_after
		run.sets_after = null
		result = engine.apply(action)
		if not result.ok:
			run.rejections.append("action %d rejected, code %d" % [run.actions, result.error])
			return run
		run.actions += 1
		# Only the second commit starts a walk (DC-06 T03: the longest walk, R25).
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


## The pulses of the walk that `action` (the second commit) starts from `before`: one per
## slot of both rows at walk start (DC-06 R4), so both rows as they stood, the first
## commit held in `pending` and the second commit's cards. Rows keep their size during a
## walk: a swap moves cards and a destroy marks one in place; only turn end shrinks them.
func _walk_pulses(before: Dictionary, action: EngineAction) -> int:
	var pulses: int = _state_ints(before, "pending").size() + action.cards.size()
	for seat: int in range(MatchEngine.SEATS):
		pulses += _state_list(before, "board", seat).size()
	return pulses


## The bot's action is for the awaited seat: a commit costing no more than its budget (with
## the free first card when the seat holds it, and each card's cost reduction, both read
## from `state`, the full state the bot chose on), or, while a prompt is open (DC-05 T05), a
## choice: a set for a multi-select prompt (DC-07 P7, P13), with every index offered and
## none repeated, else a single position, or on an optional prompt the decline (cycle 8
## R52, R56; counted in `declines`). A Crew prompt answered is counted in `crew_prompts`.
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
		var zone: int = prompt.get(Choice.KEY_ZONE, Choice.NO_ZONE)
		if not Choice.is_valid_set(prompt, zone, action.indices):
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


## Hand cap for both seats after the step, then (when `scan`) the leak scan.
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
## no id that was hidden from it before or after the step, less the cards this step
## revealed in public (the approach of test_seat_view.gd).
## The hidden and own sets of `before` and `after` are built once per state and kept on the
## run (FullMatchRun.sets_before, sets_after), so a step reuses the last step's `after` sets
## as its `before` sets; each is copied before it is merged into.
func _scan_leaks(
	run: FullMatchRun, before: Dictionary, after: Dictionary, result: ApplyResult
) -> void:
	run.steps_scanned += 1
	if run.sets_before == null:
		run.sets_before = _sets_of(before)
	if run.sets_after == null:
		run.sets_after = _sets_of(after)
	var revealed: Dictionary = {}
	for event: MatchEvent in result.events:
		if event.kind == MatchEvent.Kind.CARD_REVEALED:
			for card: int in FullMatchRun.event_card_ids(event):
				revealed[card] = true
		elif event.kind == MatchEvent.Kind.CARD_RECOVERED:
			run.recoveries_seen += 1
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
		_scan_destroyed_pile(run, view, after, where)
		var hidden_during: Dictionary = run.sets_before.hidden[opp].duplicate()
		hidden_during.merge(hidden_now)
		for card: Variant in revealed.keys():
			hidden_during.erase(card)
		# Cards face up on the opponent's row before the step were public; the walk scores
		# them by id even when a round end then shuffles them back into a hidden pile. Only
		# the on-row kinds may name them (_may_name_public_card); a card still face down
		# there (a walk paused on a prompt) stays hidden for every kind.
		var public_before: Array[int] = _state_list(before, "revealed", opp)
		# DC-07 R18, R19: a destroyed-pile entry whose identity was public may be named by
		# its recovery, and a card recovered into this seat's hand or burn pile is its own to
		# know, whatever pile it came from.
		for pile_seat: int in range(MatchEngine.SEATS):
			public_before.append_array(_state_list(before, "destroyed_known", pile_seat))
		var own_after: Array[int] = _state_list(after, "hand", seat)
		own_after.append_array(_state_list(after, "burned", seat))
		# DC-07 R19, C12: a recovered card changes controller and goes home at round start,
		# so it can sit in this seat's own zones while its origin is the opponent's. A card
		# this seat holds, has on its row or in its destroyed pile, before or after the
		# step, is its own to know, whatever deck it came from.
		var own_known: Dictionary = run.sets_before.own[seat].duplicate()
		own_known.merge(run.sets_after.own[seat])
		for event: MatchEvent in result.events_for(seat):
			if event.is_private() and event.owner_seat == opp:
				run.redacted_seen += 1
				if _is_destroy_kind(event.kind):
					run.destroyed_hidden_seen += 1
				if event.kind == MatchEvent.Kind.CARD_RECOVERED:
					run.hidden_recoveries_seen += 1
				if FullMatchRun.is_memory_kind(event.kind):
					run.memory_hidden_seen += 1
					run.check_neutral_stats(event, where)
			var exempt: bool = _may_name_public_card(event)
			for card: int in FullMatchRun.event_card_ids(event):
				if not hidden_during.has(card) or own_known.has(card):
					continue
				if exempt and public_before.has(card):
					continue
				if _is_recovery_kind(event.kind) and own_after.has(card):
					continue
				run.leaks.append(where + ": event %d names hidden card %d" % [event.kind, card])


## An open prompt as `view`'s seat sees it (cycle 8 R73, DC-11 T11): a prompt for the other
## seat shows only {open, seat} (SeatView.prompt), so a Crew prompt's zone, options, verb and
## Crew reach the asked seat alone; a Crew prompt the asked seat sees is counted
## (crew_prompts_scanned). Its source card is -1 and its options are positions; the rest
## of the view is scanned by _view_card_ids as for any prompt.
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


## A face-down card on the opponent's row shows neither its id nor its stats (DC-06 R20: a
## destroyed one still shows its slot as destroyed), nor its memory (cycle 8 R8, DC-09 T04):
## cost 0, grown false and uses_left -1, whatever its card remembers.
func _scan_hidden_rows(run: FullMatchRun, view: SeatView, where: String) -> void:
	for slot: int in range(view.opponent_row.size()):
		var entry: Dictionary = view.opponent_row[slot]
		var revealed: bool = entry.get("revealed", false)
		if revealed:
			continue
		var destroyed: bool = entry.get("destroyed", false)
		if destroyed:
			run.destroyed_hidden_seen += 1
		var card: int = entry.get(MatchEvent.KEY_CARD, MatchEvent.HIDDEN_CARD)
		var flat: int = entry.get("flat", 0)
		var times: int = entry.get("times", MatchRules.BONUS_ONE)
		var plus: int = entry.get("plus", 0)
		var no_bonus: bool = times == MatchRules.BONUS_ONE and plus == 0
		if card != MatchEvent.HIDDEN_CARD or flat != 0 or not no_bonus:
			run.leaks.append(where + ": face-down slot %d shows its card" % slot)
		var cost: int = entry.get("cost", 0)
		var grown: bool = entry.get("grown", false)
		var uses_left: int = entry.get("uses_left", -1)
		if cost != 0 or grown or uses_left != -1:
			run.leaks.append(where + ": face-down slot %d shows its memory" % slot)
		var on_board: int = MatchEvent.HIDDEN_CARD
		if slot < view.opponent_board.size():
			on_board = view.opponent_board[slot]
		if on_board != MatchEvent.HIDDEN_CARD:
			run.leaks.append(where + ": opponent_board names face-down slot %d" % slot)


## DC-07 R16-R18, P6: the opponent's destroyed pile shows its full size in pile order, and
## an entry whose identity is not public (`destroyed_known`) only as HIDDEN_CARD; a known
## entry shows its id. (Hidden ids in the view are also caught by _view_card_ids.)
func _scan_destroyed_pile(
	run: FullMatchRun, view: SeatView, after: Dictionary, where: String
) -> void:
	var pile: Array[int] = _state_list(after, "destroyed", view.opponent)
	var known: Array[int] = _state_list(after, "destroyed_known", view.opponent)
	if view.opponent_destroyed.size() != pile.size():
		run.leaks.append(
			where + ": opponent pile shows %d of %d" % [view.opponent_destroyed.size(), pile.size()]
		)
		return
	for index: int in range(pile.size()):
		var card: int = pile[index]
		var shown: int = view.opponent_destroyed[index]
		var want: int = card if known.has(card) else MatchEvent.HIDDEN_CARD
		if want == MatchEvent.HIDDEN_CARD:
			run.pile_hidden_seen += 1
		if shown != want:
			run.leaks.append(where + ": opponent pile entry %d shows %d" % [index, shown])


## The destroy kinds (DC-06): the destroy itself and its turn-end clear.
func _is_destroy_kind(kind: int) -> bool:
	return kind == MatchEvent.Kind.CARD_DESTROYED or kind == MatchEvent.Kind.DESTROYED_CLEARED


## Whether `event` may name a card that was face up on the opponent's row before the step
## and is hidden after it (DC-05 T13): the on-row kinds that report that card in public
## (scored, revealed, stats, returned, a public burn), plus those the engine emits for a
## face-up card in a walk that a round end, a destroy or a return then hides: an effect
## firing (c06's flat-up, c05's carry), a choice (its source, or a face-up target such as
## c17's), and a public destroy or move. Never a deal, draw, discard, commit or any other
## private kind: those must not name a card that was public.
## DC-07 P9: CARD_UNREVEALED is a face-up card flipping down in public; the face-down rules
## hide it from then on. DC-07 R25: a declined set ("Destroy 0") fizzles the face-up source
## in public. DC-06: the turn-end clear of a destroyed card is public once it was revealed;
## DC-07: so is the recovery of a pile card whose identity was public. Cycle 8 R8 (DC-09
## T04): a private STATS_CHANGED or CARD_RETURNED (memory on a hand or face-down card, a
## face-down card's return) never names a card to the other seat, even one public before.
func _may_name_public_card(event: MatchEvent) -> bool:
	match event.kind:
		MatchEvent.Kind.CARD_SCORED, MatchEvent.Kind.CARD_REVEALED:
			return true
		MatchEvent.Kind.CARD_UNREVEALED, MatchEvent.Kind.CHOICE_MADE:
			return true
		MatchEvent.Kind.EFFECT_FIRED, MatchEvent.Kind.EFFECT_FIZZLED:
			return true
		MatchEvent.Kind.CARD_BURNED, MatchEvent.Kind.CARD_DESTROYED, MatchEvent.Kind.CARD_MOVED:
			return not event.is_private()
		MatchEvent.Kind.DESTROYED_CLEARED, MatchEvent.Kind.CARD_RECOVERED:
			return not event.is_private()
	return FullMatchRun.is_memory_kind(event.kind) and not event.is_private()


## The kinds a recovery emits for the recovering seat (DC-07 R19): the choice, the recovery
## and, at the hand cap, the burn. They may name the card to the seat that now holds it.
func _is_recovery_kind(kind: int) -> bool:
	return (
		kind == MatchEvent.Kind.CHOICE_MADE
		or kind == MatchEvent.Kind.CARD_RECOVERED
		or kind == MatchEvent.Kind.CARD_BURNED
	)


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


## Writes the log to JSON, reads it back and replays it with the shipped pool and list
## (R33; DC-07 R7: the header's decks rebuild the match); "" when the replayed full state
## (deck ids included) and log equal the original's, else what went wrong.
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
	_assert_none(run.hand_violations, label + "hand over the cap")
	var cap: int = HAND_BOUND
	assert_int(run.max_hand).override_failure_message(label + "hand over cap").is_less_equal(cap)
	_assert_none(run.energy_violations, label + "commit over energy")
	_assert_none(run.leaks, label + "hidden card leaked")
	var scanned: String = label + "nothing leak-scanned"
	assert_int(run.steps_scanned).override_failure_message(scanned).is_greater(0)
	var replay_problem: String = _replay_problem(run.engine)
	assert_str(replay_problem).override_failure_message(label + replay_problem).is_empty()


func _assert_none(found: Array[String], what: String) -> void:
	var message: String = "%s: %s" % [what, found]
	assert_array(found).override_failure_message(message).is_empty()
