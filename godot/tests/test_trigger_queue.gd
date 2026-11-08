class_name TestTriggerQueue
extends GdUnitTestSuite
## The trigger queue (DC-13 T05; cycle 9 plan P11, P12; spec R45 to R56; canon
## [[rules/resolution]] Q1 to Q9): Batches appended after the effect, snapshots read for
## Mute at the pop, Q3 order, the budget of 50 per pulse with `exhausted`, retriggers,
## Scores twice, the On commit and On start brackets, and a prompt pausing a drain inside
## the Walk (D8) in a real match that a replay of its log reaches and resumes the same way.
## Every card here carries the fixture's stub verbs (StubAbilities.StubVerbs) through
## StubAbilities.replace_def; seat 1's instances add MatchRules.DECK_SIZE.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const GUARD: int = 100

# --- Helpers --------------------------------------------------------------------------


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


## Stub-deck definitions (`crew` per seat) whose extra verb table is `verbs`.
func _cards(verbs: StubAbilities.StubVerbs, crew: Array[String] = StubAbilities.CREW) -> MatchCards:
	var cards: MatchCards = StubAbilities.defs(crew)
	cards.set_verb_handler(verbs)
	return cards


## Gives `instances` a stub card named `name` with `abilities` (Power `power`).
func _give(
	cards: MatchCards,
	instances: Array[int],
	name: String,
	abilities: Array[CardAbility],
	power: int = 1
) -> void:
	var def: CardDef = StubAbilities.card_def(name, abilities, power)
	assert_bool(StubAbilities.give(cards, instances, def)).is_true()


func _ability(
	moment: String, verb: String, amount: int = 0, watch: String = "self", zone: String = "row"
) -> Array[CardAbility]:
	var out: Array[CardAbility] = [StubAbilities.ability(moment, verb, amount, watch, zone)]
	return out


func _int_of(event: MatchEvent, key: String) -> int:
	var value: int = event.payload[key]
	return value


func _str_of(event: MatchEvent, key: String) -> String:
	var value: String = event.payload[key]
	return value


## `key` of every event of `kind` in `events`, in order.
func _ints(events: Array[MatchEvent], kind: int, key: String) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		if event.kind == kind:
			out.append(_int_of(event, key))
	return out


func _kinds(events: Array[MatchEvent]) -> Array[int]:
	var out: Array[int] = []
	for event: MatchEvent in events:
		out.append(event.kind)
	return out


func _dicts(events: Array[MatchEvent]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: MatchEvent in events:
		out.append(event.to_dict())
	return out


## The fizzles of `rec` with `reason`.
func _fizzles(rec: StubAbilities.Recorder, reason: String) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for event: MatchEvent in rec.of_kind(FIZZLED):
		if _str_of(event, "reason") == reason:
			out.append(event)
	return out


# --- Q1: a Batch is appended after the effect -----------------------------------------


## A stub On score that wakes two watchers: its effect finishes (nothing is queued yet)
## before either fires, and the two fire from one Batch, in slot order.
func test_a_stub_on_score_appends_one_batch_and_finishes_before_either_fires() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var a: int = 0
	var b: int = 1
	var c: int = 2
	_give(cards, _typed([a]), "Waker", _ability("on_score", StubAbilities.VERB_WAKE_MOVED))
	var watcher: Array[CardAbility] = _ability(
		"on_moved", StubAbilities.VERB_RECORD, 0, "other_own"
	)
	_give(cards, _typed([b, c]), "Watcher", watcher)
	var state: MatchState = StubAbilities.table(_typed([a, b, c]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var batch: Dictionary = TriggerQueue.wake(state, cards, "on_score", _typed([a]))
	assert_int(state.queue.size()).is_equal(1)
	var first: int = batch["id"]
	assert_bool(TriggerQueue.drain(state, cards, MatchRng.new(SEED), rec.record, "D8")).is_false()
	var expected: Array[String] = [
		"done 0", "fire %d batch %d" % [b, first + 1], "fire %d batch %d" % [c, first + 1]
	]
	assert_array(verbs.trace).is_equal(expected)
	assert_array(rec.cards_of(FIRED)).is_equal(_typed([a, b, c]))
	assert_array(_ints(rec.events, FIRED, "resolution")).is_equal(_typed([1, 2, 3]))
	assert_bool(state.queue.is_empty()).is_true()


# --- Q2: the snapshot, Mute read at the pop -------------------------------------------


## One On start Batch of four: the first Condemns the second, the third Mutes the fourth.
## The Condemned card still fires, once; the Muted one does not fire, but its pop still
## counts one toward the budget (P11, "each pop counts one").
func test_condemned_mid_batch_fires_once_and_muted_mid_batch_does_not() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var x: int = 0
	var y: int = 1
	var m: int = 2
	var z: int = 3
	_give(cards, _typed([x]), "Condemner", _ability("on_start", StubAbilities.VERB_CONDEMN_SLOT, 1))
	_give(cards, _typed([y, z]), "Plain", _ability("on_start", StubAbilities.VERB_RECORD))
	_give(cards, _typed([m]), "Muter", _ability("on_start", StubAbilities.VERB_MUTE_SLOT, 3))
	var state: MatchState = StubAbilities.table(_typed([x, y, m, z]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(state, cards, MatchRng.new(SEED), rec.record)).is_false()
	assert_array(rec.cards_of(FIRED)).is_equal(_typed([x, y, m]))
	assert_array(rec.of_kind(FIZZLED)).is_empty()
	assert_str(Statuses.exit_mark_of(state, y)).is_equal(Statuses.CONDEMNED)
	assert_bool(Statuses.has(state, z, Statuses.MUTED)).is_true()
	assert_int(state.queue.resolutions).is_equal(4)


# --- Q3: order ------------------------------------------------------------------------


## Cards first (the Turn's first seat by slot, then the second seat by slot), then Crew by
## slot: seat 1 commits first here, and seat 1's Navigator and Captain watch its Scores.
func test_order_is_first_seat_cards_then_second_seat_cards_then_crew_by_slot() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs, StubAbilities.RAMP_CREW)
	var p0: int = 0
	var q0: int = 1
	var p1: int = OTHER
	var x: int = OTHER + 1
	var any: Array[CardAbility] = _ability("on_score", StubAbilities.VERB_RECORD, 0, "any")
	_give(cards, _typed([p0, q0, p1, x]), "Any", any)
	var state: MatchState = MatchState.new(SEED)
	state.first_seat = 1
	StubAbilities.put_row(state, 0, _typed([p0, q0]), true)
	StubAbilities.put_row(state, 1, _typed([p1, x]), true)
	var listed: Array[Dictionary] = TriggerQueue.watchers(state, cards, "on_score", _typed([x]), -1)
	var shape: Array = []
	for entry: Dictionary in listed:
		shape.append([entry["kind"], entry["seat"], entry["card"], entry["crew_slot"]])
	var expected: Array = [
		["card", 1, p1, -1],
		["card", 1, x, -1],
		["card", 0, p0, -1],
		["card", 0, q0, -1],
		["crew", 1, -1, 0],
		["crew", 1, -1, 1],
	]
	assert_array(shape).is_equal(expected)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	TriggerQueue.wake(state, cards, "on_score", _typed([x]))
	assert_bool(TriggerQueue.drain(state, cards, MatchRng.new(SEED), rec.record, "D8")).is_false()
	assert_array(_kinds(rec.events)).is_equal(_typed([FIRED, FIRED, FIRED, FIRED, FIZZLED, FIZZLED]))
	assert_array(rec.cards_of(FIRED)).is_equal(_typed([p1, x, p0, q0]))
	var crew: Array[String] = []
	for event: MatchEvent in rec.of_kind(FIZZLED):
		crew.append(_str_of(event, "crew"))
	var expected_crew: Array[String] = ["navigator", "captain"]
	assert_array(crew).is_equal(expected_crew)


# --- Q4: the budget -------------------------------------------------------------------


## Two stubs that each Condemn a random enemy card and Score again, each reacting to every
## Score: the pulse stops at exactly 50 resolutions, every entry still queued (52) fizzles
## `exhausted` in public, and the next pulse starts again at 0.
func test_two_stubs_feeding_each_other_stop_at_fifty_and_the_next_pulse_starts_at_zero() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var a: int = 0
	var b: int = 1
	var feed: Array[CardAbility] = _ability("on_score", StubAbilities.VERB_FEED, 0, "any")
	_give(cards, _typed([a, b]), "Feeder", feed)
	var state: MatchState = MatchState.new(SEED)
	StubAbilities.put_row(state, 0, _typed([a, b]), true)
	var pebbles: Array[int] = [OTHER + StubAbilities.PEBBLE, OTHER + StubAbilities.PEBBLE + 1]
	StubAbilities.put_row(state, 1, pebbles, true)
	var rng: MatchRng = MatchRng.new(SEED)
	ScoreWalk.begin(state)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_false()
	assert_int(state.walk.resolutions).is_equal(MatchRules.TRIGGER_BUDGET)
	var numbers: Array[int] = _ints(rec.events, FIRED, "resolution")
	var expected: Array[int] = []
	for number: int in range(1, MatchRules.TRIGGER_BUDGET + 1):
		expected.append(number)
	assert_array(numbers).is_equal(expected)
	var exhausted: Array[MatchEvent] = _fizzles(rec, Abilities.REASON_EXHAUSTED)
	assert_int(exhausted.size()).is_equal(MatchRules.TRIGGER_BUDGET + 2)
	assert_int(rec.of_kind(FIZZLED).size()).is_equal(exhausted.size())
	for event: MatchEvent in exhausted:
		assert_int(event.owner_seat).is_equal(MatchEvent.PUBLIC)
	# Every fizzle comes after the 50th resolution.
	var kinds: Array[int] = _kinds(rec.events)
	assert_int(kinds.find(FIZZLED)).is_greater(kinds.rfind(FIRED))
	assert_bool(state.queue.is_empty()).is_true()
	assert_bool(state.walk.active).is_true()
	# The next pulse (seat 1's slot 0, a Pebble both stubs react to) starts at 0.
	var next: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(ScoreWalk.step(state, cards, rng, next.record)).is_false()
	assert_array(next.cards_of(SCORED).slice(0, 1)).is_equal(_typed([pebbles[0]]))
	assert_array(_ints(next.events, FIRED, "resolution")).is_equal(expected)
	assert_int(_fizzles(next, Abilities.REASON_EXHAUSTED).size()).is_equal(
		MatchRules.TRIGGER_BUDGET + 2
	)


## One resolution left in the pulse: a Muted entry popped first spends it silently (no
## event), so the plain entry after it fizzles `exhausted` (P11, Q2, Q4).
func test_a_muted_pop_counts_one_toward_the_budget() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var m: int = 0
	var x: int = 1
	var any: Array[CardAbility] = _ability("on_score", StubAbilities.VERB_RECORD, 0, "any")
	_give(cards, _typed([m, x]), "Any", any)
	var state: MatchState = StubAbilities.table(_typed([m, x]), true)
	StubAbilities.stub_mute(state, cards, m, Callable())
	state.walk.resolutions = MatchRules.TRIGGER_BUDGET - 1
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	TriggerQueue.wake(state, cards, "on_score", _typed([x]))
	assert_bool(TriggerQueue.drain(state, cards, MatchRng.new(SEED), rec.record, "D8")).is_false()
	assert_array(rec.of_kind(FIRED)).is_empty()
	var exhausted: Array[int] = []
	for event: MatchEvent in _fizzles(rec, Abilities.REASON_EXHAUSTED):
		exhausted.append(_int_of(event, "card"))
	assert_array(exhausted).is_equal(_typed([x]))
	assert_int(state.walk.resolutions).is_equal(MatchRules.TRIGGER_BUDGET)


## The budget runs out with a Muted entry still queued: the plain entries fizzle
## `exhausted`, the Muted one drops silently, as it would under budget (Q2, Q4).
func test_a_muted_entry_left_when_the_budget_runs_out_stays_silent() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var x: int = 0
	var m: int = 1
	var y: int = 2
	var any: Array[CardAbility] = _ability("on_score", StubAbilities.VERB_RECORD, 0, "any")
	_give(cards, _typed([x, m, y]), "Any", any)
	var state: MatchState = StubAbilities.table(_typed([x, m, y]), true)
	StubAbilities.stub_mute(state, cards, m, Callable())
	state.walk.resolutions = MatchRules.TRIGGER_BUDGET - 1
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	TriggerQueue.wake(state, cards, "on_score", _typed([x]))
	assert_bool(TriggerQueue.drain(state, cards, MatchRng.new(SEED), rec.record, "D8")).is_false()
	assert_array(rec.cards_of(FIRED)).is_equal(_typed([x]))
	assert_array(rec.cards_of(FIZZLED)).is_equal(_typed([y]))
	assert_int(_fizzles(rec, Abilities.REASON_EXHAUSTED).size()).is_equal(1)
	assert_bool(state.queue.is_empty()).is_true()


## Cycle 14 R1, R2 (C1, NSC-178): an effect's On empty draw Batch (Q11, `then_draw`) whose
## first trigger refills the Deck spends the pulse's last resolution; the rest of the Batch
## (two cards, then seat 0's Void) fizzles `exhausted`, and the denied draw is still made
## once, right after the Batch's last entry. The draw is a game step: `spent` is unchanged.
func test_the_resumed_draw_survives_an_exhausted_budget() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var r: int = 0
	var x: int = 1
	var y: int = 2
	var refilled: int = StubAbilities.PEBBLE
	_give(cards, _typed([r]), "Refiller", _ability("on_empty_draw", StubAbilities.VERB_REFILL))
	_give(cards, _typed([x, y]), "Plain", _ability("on_empty_draw", StubAbilities.VERB_RECORD))
	var state: MatchState = StubAbilities.table(_typed([r, x, y]), true)
	var piles: MatchState.SeatPiles = state.seats[0]
	piles.deck.clear()
	piles.hand.clear()
	piles.pile.assign(_typed([refilled]))
	state.walk.resolutions = MatchRules.TRIGGER_BUDGET - 1
	var context: Dictionary = {TriggerQueue.KEY_THEN_DRAW: 0}
	var none: Array[int] = []
	var batch: Dictionary = TriggerQueue.wake(state, cards, "on_empty_draw", none, 0, context)
	assert_dict(batch).is_not_empty()
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TriggerQueue.drain(state, cards, MatchRng.new(SEED), rec.record, "D8")).is_false()
	assert_array(rec.cards_of(FIRED)).is_equal(_typed([r]))
	assert_array(_ints(rec.events, FIRED, "resolution")).is_equal(
		_typed([MatchRules.TRIGGER_BUDGET])
	)
	var exhausted: Array[int] = []
	for event: MatchEvent in _fizzles(rec, Abilities.REASON_EXHAUSTED):
		exhausted.append(_int_of(event, "card"))
	assert_array(exhausted).is_equal(_typed([x, y, -1]))
	# The denied draw: once, after the last exhausted entry, from the refilled Deck.
	var kinds: Array[int] = _kinds(rec.events)
	var drawn: Array[int] = rec.cards_of(MatchEvent.Kind.CARD_DRAWN)
	assert_array(drawn).is_equal(_typed([refilled]))
	assert_int(kinds.find(MatchEvent.Kind.CARD_DRAWN)).is_greater(kinds.rfind(FIZZLED))
	var last: int = kinds[kinds.size() - 1]
	assert_int(last).is_equal(MatchEvent.Kind.CARD_DRAWN)
	assert_array(piles.hand).is_equal(_typed([refilled]))
	assert_array(piles.deck).is_empty()
	assert_int(TriggerQueue.spent(state)).is_equal(MatchRules.TRIGGER_BUDGET)
	assert_bool(state.queue.is_empty()).is_true()


# --- Q6: retriggers -------------------------------------------------------------------


## A retrigger set by the first card adds one extra resolution right after the second
## card's On reveal, before the next queued trigger, with a fresh prompt and N read again;
## it never applies to the card that set it, nor to an extra resolution, nor to the other
## seat's card.
func test_stub_retrigger_adds_one_extra_resolution_with_a_fresh_prompt_and_n() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var s: int = 0
	var d: int = 1
	var o: int = OTHER
	_give(cards, _typed([s]), "Encore", _ability("on_reveal", StubAbilities.VERB_RETRIGGER))
	_give(cards, _typed([d]), "Picker", _ability("on_reveal", StubAbilities.VERB_DISCARD_PICK))
	var opposing: Array[CardAbility] = _ability(
		"on_reveal", StubAbilities.VERB_RECORD, 0, "opposing"
	)
	_give(cards, _typed([o]), "Watcher", opposing)
	var state: MatchState = MatchState.new(SEED)
	StubAbilities.put_row(state, 0, _typed([s, d]), false)
	StubAbilities.put_row(state, 1, _typed([o]), true)
	var hand: Array[int] = [StubAbilities.PEBBLE, StubAbilities.PEBBLE + 1, StubAbilities.MOTE + 2]
	state.seats[0].hand.assign(hand)
	var rng: MatchRng = MatchRng.new(SEED)
	ScoreWalk.begin(state)
	var early: StubAbilities.Recorder = StubAbilities.recorder()
	# Pulse 1: s reveals and sets the retrigger (once: never to itself); o fires once.
	assert_bool(ScoreWalk.step(state, cards, rng, early.record)).is_false()
	assert_array(early.cards_of(FIRED)).is_equal(_typed([s, o]))
	# Pulse 2: o Scores.
	assert_bool(ScoreWalk.step(state, cards, rng, early.record)).is_false()
	# Pulse 3: d reveals; its On reveal prompts over three hand cards (D7).
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_str(Choice.step_of(state.prompt)).is_equal("D7")
	assert_str(Choice.resume_of(state.prompt)).is_equal(Choice.RESUME_WALK)
	assert_int(Choice.options_of(state.prompt).size()).is_equal(3)
	var first_pick: Array[int] = [0]
	var paused: bool = TriggerQueue.answer(
		state, cards, rng, rec.record, Choice.Zone.OWN_HAND, first_pick, false
	)
	# The extra resolution comes next, with a fresh prompt over the two cards left.
	assert_bool(paused).is_true()
	assert_int(Choice.options_of(state.prompt).size()).is_equal(2)
	var second_pick: Array[int] = [1]
	paused = TriggerQueue.answer(
		state, cards, rng, rec.record, Choice.Zone.OWN_HAND, second_pick, false
	)
	assert_bool(paused).is_false()
	assert_bool(ScoreWalk.resume_pulse(state, cards, rng, rec.record)).is_false()
	assert_bool(ScoreWalk.run(state, cards, rng, rec.record)).is_false()
	var fired: Array[MatchEvent] = rec.of_kind(FIRED)
	var order: Array = []
	for event: MatchEvent in fired:
		order.append([_int_of(event, "card"), _int_of(event, "resolution")])
	assert_array(order).is_equal([[d, 1], [d, 2], [o, 3]])
	assert_int(rec.of_kind(MatchEvent.Kind.PROMPT_OPENED).size()).is_equal(2)
	var traced: Array[String] = []
	for line: String in verbs.trace:
		if line.begins_with("n "):
			traced.append(line)
	var expected_n: Array[String] = ["n 1", "n 2"]
	assert_array(traced).is_equal(expected_n)
	assert_array(state.seats[0].pile).is_equal(
		_typed([StubAbilities.PEBBLE, StubAbilities.MOTE + 2])
	)
	assert_int(state.card_state_for(d).power_delta).is_equal(3)


# --- Q7: Scores twice -----------------------------------------------------------------


## After a stub sets Scores twice, every later pulse's score stage runs twice: CARD_SCORED
## pass 2 follows pass 1, both On score Batches are queued before the drain, and the card
## counts twice. The pulse that set it Scores once.
func test_stub_scores_twice_runs_the_score_stage_twice() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var t: int = 0
	var m: int = 1
	_give(cards, _typed([t]), "Reprise", _ability("on_reveal", StubAbilities.VERB_SCORES_TWICE))
	_give(cards, _typed([m]), "Scorer", _ability("on_score", StubAbilities.VERB_RECORD), 2)
	var state: MatchState = StubAbilities.table(_typed([t, m]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.run(state, cards, MatchRng.new(SEED), rec.record)).is_false()
	var scored: Array[MatchEvent] = rec.of_kind(SCORED)
	var shape: Array = []
	for event: MatchEvent in scored:
		shape.append([_int_of(event, "card"), _int_of(event, "pass")])
	assert_array(shape).is_equal([[t, 1], [m, 1], [m, 2]])
	var kinds: Array[int] = _kinds(rec.events)
	var at: int = kinds.find(SCORED, kinds.find(SCORED) + 1)
	assert_array(kinds.slice(at, at + 4)).is_equal(_typed([SCORED, SCORED, FIRED, FIRED]))
	assert_int(state.walk.scored_count[0]).is_equal(3)
	assert_int(state.scores[0]).is_equal(1 + 2 + 2)


# --- R54: the On commit and On start brackets -----------------------------------------


## On commit wakes the committing seat's revealed row cards, then its hand cards with
## `zone: hand` (privately), never a card committed this Turn, a face-down card or the other
## seat's; On start wakes revealed row cards only, first seat first.
func test_on_commit_brackets_and_on_start_for_revealed_cards_only() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var in_hand: Array[CardAbility] = [
		StubAbilities.ability("on_commit", StubAbilities.VERB_RECORD, 0, "self", "hand"),
		StubAbilities.ability("on_start", StubAbilities.VERB_RECORD),
	]
	var on_row: Array[CardAbility] = [
		StubAbilities.ability("on_commit", StubAbilities.VERB_RECORD),
		StubAbilities.ability("on_start", StubAbilities.VERB_RECORD),
	]
	var h1: int = 0
	var h2: int = 1
	var r1: int = 2
	var r2: int = 3
	_give(cards, _typed([h1, h2, OTHER]), "Layaway", in_hand)
	_give(cards, _typed([r1, r2, OTHER + 2]), "Idler", on_row)
	var state: MatchState = MatchState.new(SEED)
	StubAbilities.put_row(state, 0, _typed([r1, r2]), false)
	state.seats[0].revealed[r1] = true
	StubAbilities.put_row(state, 1, _typed([OTHER + 2]), true)
	state.seats[0].hand.assign(_typed([h1, h2]))
	state.seats[1].hand.assign(_typed([OTHER]))
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	TurnFlow.accept_commit(state, cards, rec.record, 0, _typed([h2]), _typed([2]))
	var rng: MatchRng = MatchRng.new(SEED)
	var commit: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_commit(state, cards, rng, commit.record, 0)).is_false()
	assert_array(commit.cards_of(FIRED)).is_equal(_typed([r1, h1]))
	var fired: Array[MatchEvent] = commit.of_kind(FIRED)
	assert_int(fired[0].owner_seat).is_equal(MatchEvent.PUBLIC)
	# C14: a trigger fired from the hand is public and names its card for both seats.
	assert_int(fired[1].owner_seat).is_equal(MatchEvent.PUBLIC)
	assert_int(_int_of(fired[1].redacted_for(1), "card")).is_equal(h1)
	assert_str(_str_of(fired[1], "moment")).is_equal("on_commit")
	var start: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(TurnFlow.on_start(state, cards, rng, start.record)).is_false()
	assert_array(start.cards_of(FIRED)).is_equal(_typed([r1, OTHER + 2]))


# --- Q9, R56: a prompt pauses the Walk; replay ----------------------------------------


## Every card of both Decks: On score, choose a card of your hand; then On score, record.
func _chooser_engine(verbs: StubAbilities.StubVerbs) -> MatchEngine:
	var engine: MatchEngine = StubAbilities.engine(SEED)
	var abilities: Array[CardAbility] = [
		StubAbilities.ability("on_score", StubAbilities.VERB_CHOOSE_HAND),
		StubAbilities.ability("on_score", StubAbilities.VERB_RECORD),
	]
	var every: Array[int] = []
	for instance: int in range(2 * MatchRules.DECK_SIZE):
		every.append(instance)
	engine.match_cards().set_verb_handler(verbs)
	_give(engine.match_cards(), every, "Chooser", abilities, 2)
	assert_bool(engine.start().ok).is_true()
	return engine


func _hand_of(engine: MatchEngine, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var hands: Array = state["hand"]
	var hand: Array = hands[seat]
	return _typed(hand)


## Turn 1: the first seat commits one card, the second passes and discards down; the Walk
## reveals and Scores the card and its On score prompts (D8). Returns the prompted seat.
func _to_the_d8_prompt(engine: MatchEngine) -> int:
	var first: int = engine.awaited_seat()
	var picked: Array[int] = [_hand_of(engine, first)[0]]
	assert_bool(engine.apply(EngineAction.commit(first, picked)).ok).is_true()
	var none: Array[int] = []
	assert_bool(engine.apply(EngineAction.commit(1 - first, none)).ok).is_true()
	assert_bool(engine.apply(FixtureDecks.discard_answer(engine)).ok).is_true()
	return first


## A prompt inside D8 pauses the Walk: phase AWAIT_CHOICE, `resume` walk, step D8; a Commit
## is rejected; the answer resumes the drain at the next entry (the second ability fires,
## the first does not fire again).
func test_a_prompt_inside_d8_pauses_and_the_answer_resumes_at_the_next_entry() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var engine: MatchEngine = _chooser_engine(verbs)
	var seat: int = _to_the_d8_prompt(engine)
	var state: Dictionary = engine.full_state()
	assert_int(state["phase"]).is_equal(MatchState.Phase.AWAIT_CHOICE)
	var prompt: Dictionary = engine.open_prompt()
	assert_str(Choice.resume_of(prompt)).is_equal(Choice.RESUME_WALK)
	assert_str(Choice.step_of(prompt)).is_equal("D8")
	assert_int(engine.awaited_seat()).is_equal(seat)
	assert_bool(Choice.is_multi_prompt(prompt)).is_false()
	var none: Array[int] = []
	for who: int in [seat, 1 - seat]:
		var rejected: ApplyResult = engine.apply(EngineAction.commit(who, none))
		assert_bool(rejected.ok).is_false()
		assert_int(rejected.error).is_equal(EngineError.Code.WRONG_SEAT)
	var hand: Array[int] = _hand_of(engine, seat)
	var result: ApplyResult = engine.apply(EngineAction.choose(seat, Choice.Zone.OWN_HAND, 1))
	assert_bool(result.ok).is_true()
	assert_int(result.events[0].kind).is_equal(MatchEvent.Kind.CHOICE_MADE)
	var verbs_fired: Array[String] = []
	for event: MatchEvent in result.events:
		if event.kind == FIRED:
			verbs_fired.append(_str_of(event, "verb"))
	assert_str(verbs_fired[0]).is_equal(StubAbilities.VERB_RECORD)
	assert_int(_int_of(result.events[1], "resolution")).is_equal(2)
	assert_str(verbs.trace[0]).is_equal("chose %d" % hand[1])
	assert_bool(verbs.trace[1].begins_with("fire ")).is_true()
	assert_int(_kinds(result.events).find(MatchEvent.Kind.WALK_ENDED)).is_greater(0)
	assert_dict(engine.open_prompt()).is_empty()


## A full state taken while paused is reached again by replaying the accepted actions on a
## fresh match, and both resume the same way: equal events and equal states.
func test_a_full_state_taken_while_paused_replays_and_resumes_the_same_way() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var engine: MatchEngine = _chooser_engine(verbs)
	var seat: int = _to_the_d8_prompt(engine)
	var paused: Dictionary = engine.full_state()
	var queue: Dictionary = paused["queue"]
	var current: Dictionary = queue["current"]
	assert_dict(current).is_not_empty()
	var copy: MatchState = engine._state.duplicate()
	# full_state() adds `created` from MatchCards (NSC-179: one record); the rest is the state.
	var state_only: Dictionary = paused.duplicate(true)
	state_only.erase("created")
	assert_dict(copy.to_dict()).is_equal(state_only)
	var again_verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var again: MatchEngine = _chooser_engine(again_verbs)
	var guard: int = 0
	for action: EngineAction in engine.accepted_actions():
		assert_bool(again.apply(action).ok).is_true()
		guard += 1
		if guard > GUARD:
			break
	assert_dict(again.full_state()).is_equal(paused)
	var answer: EngineAction = EngineAction.choose(seat, Choice.Zone.OWN_HAND, 0)
	var live: ApplyResult = engine.apply(answer)
	var replayed: ApplyResult = again.apply(answer.copy())
	assert_bool(live.ok).is_true()
	assert_bool(replayed.ok).is_true()
	assert_array(_dicts(replayed.events)).is_equal(_dicts(live.events))
	assert_dict(again.full_state()).is_equal(engine.full_state())
	assert_array(again_verbs.trace).is_equal(verbs.trace)
