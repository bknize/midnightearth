# gdlint: disable=max-public-methods
class_name TestAbilitiesControl
extends GdUnitTestSuite
## The Control card abilities (DC-14 T13; cycle 9 plan P3, P10, P12; canon
## [[rules/cards-v2]] section 2.5, AbilitiesGraveyardControl): one case per card text and per
## Flags note. Eddy's Add grows once per Move until end of turn; Pin Anchors until it leaves
## its row; Shepherd swaps (one On moved Batch, the cursor rules decide who Scores) and an
## Anchored Shepherd fizzles; Skip's move happens after D7 and its On moved drains in D8, and
## an Anchored next card stays; Fence Condemns a card that would wrap instead of moving it,
## waking no On moved; Herald is ×1.5 in the rightmost slot; Level sets every card of a row
## to the lowest revealed Power (a Saboteur's -3 sets its row to -3); Shake's chosen Anchored
## card stays and every card that changed slot, displaced or chosen, on both rows, is one On
## moved Batch; Tempest reverses the opposing row around an Anchor; Cull prompts both seats
## in turn and the random bot answers the second. Last, two random bots play whole matches
## with all twenty Graveyard and Control cards, every prompt answered, every log replayed.

const SEED: int = 1
const OTHER: int = MatchRules.DECK_SIZE
const GUARD: int = 60
const MAX_ACTIONS: int = 3000
const MATCH_SEEDS: int = 3
## Saboteur's printed Power (cards-v2 Disruption, T12): Level's Flags note names it.
const SABOTEUR_POWER: int = -3
const SCORED: int = MatchEvent.Kind.CARD_SCORED
const FIRED: int = MatchEvent.Kind.TRIGGER_FIRED
const FIZZLED: int = MatchEvent.Kind.TRIGGER_FIZZLED
const MOVED: int = MatchEvent.Kind.CARD_MOVED
const REVEALED: int = MatchEvent.Kind.CARD_REVEALED
## The twenty Graveyard and Control cards, two copies each: the test deck's 40.
const GC_IDS: Array[String] = [
	"gy01", "gy02", "gy03", "gy04", "gy05", "gy06", "gy07", "gy08", "gy09", "gy10",
	"ct01", "ct02", "ct03", "ct04", "ct05", "ct06", "ct07", "ct08", "ct09", "ct10",
]
const GC_DECK: String = "gc_test"

var _cached_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _cards(verbs: StubAbilities.StubVerbs = null) -> MatchCards:
	var cards: MatchCards = StubAbilities.defs()
	if verbs != null:
		cards.set_verb_handler(verbs)
	return cards


## Gives `instances` the shipped card `id`.
func _put(cards: MatchCards, instances: Array[int], id: String) -> void:
	var def: CardDef = _db().card_by_id(id)
	assert_object(def).is_not_null()
	assert_bool(StubAbilities.give(cards, instances, def)).is_true()


## A whole Walk on `state` that never pauses.
func _walk(state: MatchState, cards: MatchCards, rec: StubAbilities.Recorder) -> void:
	ScoreWalk.begin(state)
	var guard: int = 0
	while state.walk.active and guard < GUARD:
		assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_false()
		guard += 1


func _str_of(event: MatchEvent, key: String) -> String:
	var value: String = event.payload.get(key, "")
	return value


## The position in `rec` of the first event of `kind` about `card` (and of `moment` when not
## empty), -1 when none.
func _at(rec: StubAbilities.Recorder, kind: int, card: int, moment: String = "") -> int:
	for index: int in range(rec.events.size()):
		var event: MatchEvent = rec.events[index]
		var named: int = event.payload.get("card", -1)
		if event.kind != kind or named != card:
			continue
		if moment == "" or _str_of(event, "moment") == moment:
			return index
	return -1


func _turn() -> Dictionary:
	return Statuses.cessation(Statuses.CEASE_TURN)


## A stub card whose On moved records its Batch ("fire <card> batch <id>", StubVerbs).
func _watcher() -> CardDef:
	var abilities: Array[CardAbility] = [
		StubAbilities.ability("on_moved", StubAbilities.VERB_RECORD)
	]
	return StubAbilities.card_def("Watcher", abilities)


# --- Eddy -----------------------------------------------------------------------------


## Eddy (Add +0.25 printed): each Move's On moved gives Add +0.25 until end of turn, once per
## Move (two Moves: +0.75 in all); turn end takes the grants back.
func test_eddy_add_grows_once_per_move_until_end_of_turn() -> void:
	var cards: MatchCards = _cards()
	var eddy: int = 0
	_put(cards, _typed([eddy]), "ct01")
	var state: MatchState = StubAbilities.table(_typed([eddy, 1]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var rng: MatchRng = MatchRng.new(SEED)
	assert_int(Scoring.stats(eddy, state, cards).add()).is_equal(25)
	for _move: int in range(2):
		var moved: Array[int] = Movement.shift(state, cards, eddy, Movement.RIGHT, "test", rec.record)
		assert_bool(moved.has(eddy)).is_true()
		TriggerQueue.wake(state, cards, "on_moved", moved)
		assert_bool(TriggerQueue.drain(state, cards, rng, rec.record, "D11")).is_false()
	assert_int(Scoring.stats(eddy, state, cards).add()).is_equal(75)
	assert_int(rec.cards_of(FIRED).count(eddy)).is_equal(2)
	Abilities.end_turn_changes(state)
	assert_int(Scoring.stats(eddy, state, cards).add()).is_equal(25)


# --- Pin ------------------------------------------------------------------------------


## Pin prompts over both rows (both_boards); the chosen opposing card is Anchored (a swap
## naming it fizzles) through turn end while Pin stays, and the Anchor ends when Pin leaves
## its row.
func test_pin_anchors_until_it_leaves_its_row() -> void:
	var cards: MatchCards = _cards()
	var pin: int = 0
	_put(cards, _typed([pin]), "ct02")
	var state: MatchState = StubAbilities.table(_typed([pin]), false)
	StubAbilities.put_row(state, 1, _typed([OTHER, OTHER + 1]), true)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("both_boards")
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 1, 2]))
	var zone: int = Choice.Zone.BOTH_BOARDS
	var picked: Array[int] = [2]
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, picked, false)).is_false()
	assert_bool(Statuses.is_anchored(state, cards, OTHER + 1)).is_true()
	assert_array(StubAbilities.stub_swap(state, cards, OTHER, OTHER + 1, rec.record)).is_empty()
	Statuses.on_turn_end(state, rec.record)
	assert_bool(Statuses.is_anchored(state, cards, OTHER + 1)).is_true()
	Statuses.take_from_row(state, 0, pin, rec.record)
	assert_bool(Statuses.is_anchored(state, cards, OTHER + 1)).is_false()


# --- Shepherd -------------------------------------------------------------------------


## Shepherd swaps with its row's only not Anchored card (Brace is not eligible): both wake
## On moved (two CARD_MOVED); the card landing on the pulsed slot Scores now and Shepherd,
## moved ahead, later.
func test_shepherd_swaps_with_an_eligible_card_and_the_cursor_decides() -> void:
	var cards: MatchCards = _cards()
	var shepherd: int = 0
	var brace: int = StubAbilities.BRACE
	_put(cards, _typed([shepherd]), "ct03")
	var state: MatchState = StubAbilities.table(_typed([shepherd, 1, brace]), false)
	state.seats[0].revealed[1] = true
	state.seats[0].revealed[brace] = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].board).is_equal(_typed([1, shepherd, brace]))
	assert_int(rec.of_kind(MOVED).size()).is_equal(2)
	assert_array(rec.cards_of(SCORED)).is_equal(_typed([1, shepherd, brace]))


## An Anchored Shepherd cannot swap: it fizzles `no_target` and the row stays.
func test_anchored_shepherd_fizzles() -> void:
	var cards: MatchCards = _cards()
	var shepherd: int = 0
	_put(cards, _typed([shepherd]), "ct03")
	var state: MatchState = StubAbilities.table(_typed([shepherd, 1]), false)
	state.seats[0].revealed[1] = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	Statuses.apply(state, cards, shepherd, Statuses.ANCHORED, _turn(), "test", rec.record)
	_walk(state, cards, rec)
	assert_array(state.seats[0].board).is_equal(_typed([shepherd, 1]))
	var fizzled: Array[MatchEvent] = rec.of_kind(FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	assert_str(_str_of(fizzled[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)


# --- Skip -----------------------------------------------------------------------------


## Skip, then Eddy revealed next: Eddy moves after its reveal stage's D7 (the reveal-stage
## hook) to the only other free slot (Skip and Brace are Anchored), the Mote it displaces
## lands on the pulsed slot and Scores now, and Eddy's On moved fires in D8, after that
## Score; Eddy, moved ahead, is reached later with its Add grown.
func test_skip_moves_after_d7_and_its_on_moved_drains_in_d8() -> void:
	var cards: MatchCards = _cards()
	var skip: int = 0
	var eddy: int = 1
	var mote: int = 2
	var brace: int = StubAbilities.BRACE
	_put(cards, _typed([skip]), "ct04")
	_put(cards, _typed([eddy]), "ct01")
	var state: MatchState = StubAbilities.table(_typed([skip, eddy, brace, mote]), false)
	state.seats[0].revealed[brace] = true
	state.seats[0].revealed[mote] = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	Statuses.apply(state, cards, skip, Statuses.ANCHORED, _turn(), "test", rec.record)
	_walk(state, cards, rec)
	assert_array(state.seats[0].board).is_equal(_typed([skip, mote, brace, eddy]))
	var revealed: int = _at(rec, REVEALED, eddy)
	var moved: int = _at(rec, MOVED, eddy)
	var landed: int = _at(rec, SCORED, mote)
	var woke: int = _at(rec, FIRED, eddy, "on_moved")
	assert_bool(revealed >= 0 and revealed < moved).is_true()
	assert_bool(moved < landed).is_true()
	assert_bool(landed < woke).is_true()
	assert_array(rec.cards_of(SCORED)).is_equal(_typed([skip, mote, brace, eddy]))
	assert_int(Scoring.stats(eddy, state, cards).add()).is_equal(50)
	assert_int(state.walk.hook_pending).is_equal(0)
	assert_int(state.walk.hook_card).is_equal(-1)


## The next card revealed after Skip is Anchored (Brace): the hook is spent on it and
## nothing moves.
func test_skip_does_not_move_an_anchored_card() -> void:
	var cards: MatchCards = _cards()
	var skip: int = 0
	var brace: int = StubAbilities.BRACE
	_put(cards, _typed([skip]), "ct04")
	var state: MatchState = StubAbilities.table(_typed([skip, brace, 1]), false)
	state.seats[0].revealed[1] = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_array(state.seats[0].board).is_equal(_typed([skip, brace, 1]))
	assert_array(rec.of_kind(MOVED)).is_empty()
	assert_int(state.walk.hook_pending).is_equal(0)


# --- Fence ----------------------------------------------------------------------------


## With Fence read, Nudge at the rightmost slot of the opposing row would wrap: it is
## Condemned instead, nothing moves (no CARD_MOVED) and the Eddy it would displace wakes no
## On moved. Squelched (not read), the same Nudge wraps and Eddy fires.
func test_fence_condemns_a_card_that_would_wrap_and_wakes_no_on_moved() -> void:
	var cards: MatchCards = _cards()
	var fence: int = 0
	var eddy: int = OTHER + 1
	var nudge: int = OTHER + StubAbilities.NUDGE
	_put(cards, _typed([fence]), "ct05")
	_put(cards, _typed([eddy]), "ct01")
	var state: MatchState = StubAbilities.table(_typed([fence]), true)
	StubAbilities.put_row(state, 1, _typed([eddy, nudge]), false)
	state.seats[1].revealed[eddy] = true
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_str(Statuses.exit_mark_of(state, nudge)).is_equal(Statuses.CONDEMNED)
	assert_array(state.seats[1].board).is_equal(_typed([eddy, nudge]))
	assert_array(rec.of_kind(MOVED)).is_empty()
	assert_int(_at(rec, FIRED, eddy, "on_moved")).is_equal(-1)
	var open: MatchState = StubAbilities.table(_typed([fence]), true)
	StubAbilities.put_row(open, 1, _typed([eddy, nudge]), false)
	open.seats[1].revealed[eddy] = true
	var quiet: StubAbilities.Recorder = StubAbilities.recorder()
	assert_bool(StubAbilities.stub_squelch(open, cards, fence, quiet.record).ok()).is_true()
	_walk(open, cards, quiet)
	assert_str(Statuses.exit_mark_of(open, nudge)).is_empty()
	assert_array(open.seats[1].board).is_equal(_typed([nudge, eddy]))
	assert_bool(_at(quiet, FIRED, eddy, "on_moved") >= 0).is_true()


## Fence on a row with no ring (C15 3a): a lone Nudge on the opposing row has no other
## non-Anchored slot to step to, so Fence Condemns nothing and nothing moves.
func test_fence_does_nothing_on_a_ringless_row() -> void:
	var cards: MatchCards = _cards()
	var fence: int = 0
	var nudge: int = OTHER + StubAbilities.NUDGE
	_put(cards, _typed([fence]), "ct05")
	var state: MatchState = StubAbilities.table(_typed([fence]), true)
	StubAbilities.put_row(state, 1, _typed([nudge]), false)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(state, cards, rec)
	assert_str(Statuses.exit_mark_of(state, nudge)).is_empty()
	assert_array(state.seats[1].board).is_equal(_typed([nudge]))
	assert_array(rec.of_kind(MOVED)).is_empty()
	assert_array(rec.of_kind(MatchEvent.Kind.EXIT_MARKED)).is_empty()


## Fence leaves a move that does not wrap alone: Nudge at slot 0 moves right.
func test_fence_lets_an_inner_move_happen() -> void:
	var cards: MatchCards = _cards()
	var fence: int = 0
	var nudge: int = StubAbilities.NUDGE
	_put(cards, _typed([fence]), "ct05")
	var state: MatchState = StubAbilities.table(_typed([nudge, 1, fence]), false)
	state.seats[0].revealed[1] = true
	state.seats[0].revealed[fence] = true
	_walk(state, cards, StubAbilities.recorder())
	assert_array(state.seats[0].board).is_equal(_typed([1, nudge, fence]))
	assert_str(Statuses.exit_mark_of(state, nudge)).is_empty()


# --- Herald ---------------------------------------------------------------------------


## Herald's Mult is ×1.5 only in the rightmost slot of its row, and not while Squelched.
func test_herald_is_x1_5_in_the_rightmost_slot() -> void:
	var cards: MatchCards = _cards()
	var herald: int = 0
	_put(cards, _typed([herald]), "ct06")
	var right: MatchState = StubAbilities.table(_typed([1, herald]), true)
	assert_int(Scoring.stats(herald, right, cards).mult()).is_equal(150)
	assert_int(Scoring.stats(herald, right, cards).bonus_value()).is_equal(15000)
	var left: MatchState = StubAbilities.table(_typed([herald, 1]), true)
	assert_int(Scoring.stats(herald, left, cards).mult()).is_equal(100)
	assert_bool(StubAbilities.stub_squelch(right, cards, herald, Callable()).ok()).is_true()
	assert_int(Scoring.stats(herald, right, cards).mult()).is_equal(100)


# --- Level ----------------------------------------------------------------------------


## Level read on seat 0's row: every card of a row has the lowest Power among that row's
## revealed cards, read before any Level (Level 4, Pebble 3, Mote 2 all read 2; a face-down
## Wisp does not count but is set too); its own row included. A Saboteur-like card (Power
## -3, Saboteur's number) on the opposing row sets that row to -3, so its Walk Scores -6.
## Squelched, Level changes nothing.
func test_level_sets_each_row_to_its_lowest_revealed_power() -> void:
	var cards: MatchCards = _cards()
	var level: int = 0
	var pebble: int = StubAbilities.PEBBLE
	var wisp: int = StubAbilities.WISP
	var saboteur: int = OTHER
	_put(cards, _typed([level]), "ct07")
	var none: Array[CardAbility] = []
	var sabotage: CardDef = StubAbilities.card_def("Saboteur", none, SABOTEUR_POWER)
	assert_bool(StubAbilities.give(cards, _typed([saboteur]), sabotage)).is_true()
	var state: MatchState = StubAbilities.table(_typed([level, pebble, 1, wisp]), false)
	for card: int in [level, pebble, 1]:
		state.seats[0].revealed[card] = true
	StubAbilities.put_row(state, 1, _typed([saboteur, OTHER + pebble]), true)
	for card: int in [level, pebble, 1, wisp]:
		assert_int(Scoring.stats(card, state, cards).power).is_equal(2)
	assert_int(Scoring.stats(saboteur, state, cards).power).is_equal(SABOTEUR_POWER)
	assert_int(Scoring.stats(OTHER + pebble, state, cards).power).is_equal(SABOTEUR_POWER)
	_walk(state, cards, StubAbilities.recorder())
	assert_int(state.scores[1]).is_equal(2 * SABOTEUR_POWER)
	assert_bool(StubAbilities.stub_squelch(state, cards, level, Callable()).ok()).is_true()
	assert_int(Scoring.stats(pebble, state, cards).power).is_equal(3)
	assert_int(Scoring.stats(OTHER + pebble, state, cards).power).is_equal(3)


# --- Shake ----------------------------------------------------------------------------


## C28: a chosen Anchored card (Brace) stays; a chosen mover passes over it to the next
## free slot on its left, and the card it displaces moves too: both are returned (one On
## moved Batch).
func test_shake_row_keeps_a_chosen_anchored_card() -> void:
	var cards: MatchCards = _cards()
	var brace: int = StubAbilities.BRACE
	var pebble: int = StubAbilities.PEBBLE
	var state: MatchState = StubAbilities.table(_typed([1, brace, pebble, 2]), true)
	var chosen: Array[int] = [brace, pebble]
	var moved: Array[int] = AbilitiesGraveyardControl.shake_row(state, cards, 0, chosen, Callable())
	assert_array(state.seats[0].board).is_equal(_typed([pebble, brace, 1, 2]))
	assert_array(moved).is_equal(_typed([pebble, 1]))


## Adjacent chosen cards step left together: A B C with B and C chosen becomes B C A; the
## leftmost chosen card wraps to the rightmost slot.
func test_shake_row_adjacent_chosen_step_together() -> void:
	var cards: MatchCards = _cards()
	var state: MatchState = StubAbilities.table(_typed([1, 2, 3]), true)
	var chosen: Array[int] = [2, 3]
	var moved: Array[int] = AbilitiesGraveyardControl.shake_row(state, cards, 0, chosen, Callable())
	assert_array(state.seats[0].board).is_equal(_typed([2, 3, 1]))
	assert_int(moved.size()).is_equal(3)
	var wrap: MatchState = StubAbilities.table(_typed([1, 2, 3]), true)
	var first: Array[int] = [1]
	AbilitiesGraveyardControl.shake_row(wrap, cards, 0, first, Callable())
	assert_array(wrap.seats[0].board).is_equal(_typed([3, 2, 1]))


## Shake's reveal over two rows of four: a random two of each move; Brace never moves; every
## card that changed slot, on either row, fires its On moved from one and the same Batch.
func test_shake_moves_half_of_each_row_as_one_on_moved_batch() -> void:
	var verbs: StubAbilities.StubVerbs = StubAbilities.StubVerbs.new()
	var cards: MatchCards = _cards(verbs)
	var shake: int = 0
	var brace: int = StubAbilities.BRACE
	_put(cards, _typed([shake]), "ct08")
	var watchers: Array[int] = [1, 2, OTHER, OTHER + 1, OTHER + 2, OTHER + 3]
	assert_bool(StubAbilities.give(cards, watchers, _watcher())).is_true()
	var state: MatchState = StubAbilities.table(_typed([shake, 1, brace, 2]), true)
	state.seats[0].revealed.erase(shake)
	StubAbilities.put_row(state, 1, _typed([OTHER, OTHER + 1, OTHER + 2, OTHER + 3]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_false()
	assert_int(state.seats[0].board.find(brace)).is_equal(2)
	var moved: Array[int] = rec.cards_of(MOVED)
	assert_bool(moved.has(brace)).is_false()
	var seat_one: int = 0
	for card: int in moved:
		if card >= OTHER:
			seat_one += 1
	assert_bool(seat_one >= 2).is_true()
	var batches: Dictionary[String, bool] = {}
	var fired: Array[int] = []
	for line: String in verbs.trace:
		var parts: PackedStringArray = line.split(" ")
		if parts.size() == 4 and parts[0] == "fire":
			fired.append(parts[1].to_int())
			batches[parts[3]] = true
	assert_int(batches.size()).is_equal(1)
	for card: int in moved:
		assert_bool(fired.has(card) or not watchers.has(card)).is_true()
	assert_int(fired.size()).is_equal(moved.size() - (1 if moved.has(shake) else 0))


# --- Tempest --------------------------------------------------------------------------


## Tempest reverses the opposing row; the Anchored Brace keeps its slot and the rest are
## reversed around it; only the cards whose slot changed move.
func test_tempest_reverses_the_opposing_row_around_an_anchor() -> void:
	var cards: MatchCards = _cards()
	var tempest: int = 0
	var brace: int = OTHER + StubAbilities.BRACE
	var pebble: int = OTHER + StubAbilities.PEBBLE
	_put(cards, _typed([tempest]), "ct09")
	var state: MatchState = StubAbilities.table(_typed([tempest]), false)
	StubAbilities.put_row(state, 1, _typed([OTHER, brace, pebble, OTHER + 1]), true)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, MatchRng.new(SEED), rec.record)).is_false()
	assert_array(state.seats[1].board).is_equal(_typed([OTHER + 1, brace, pebble, OTHER]))
	assert_array(rec.cards_of(MOVED)).is_equal(_typed([OTHER + 1, OTHER]))


# --- Cull -----------------------------------------------------------------------------


## Cull with seven cards on its row and six on the other: seat 0 chooses five (exact 5,
## own_board), then seat 1 is prompted over its own row and the random bot answers it with
## exactly five of the offered positions; every card not kept is Condemned on both rows.
func test_cull_prompts_both_seats_and_condemns_the_rest() -> void:
	var cards: MatchCards = _cards()
	var cull: int = 0
	_put(cards, _typed([cull]), "ct10")
	var own: Array[int] = [cull, 1, 2, 3, 4, 5, 6]
	var state: MatchState = StubAbilities.table(own, true)
	state.seats[0].revealed.erase(cull)
	var enemy: Array[int] = [OTHER, OTHER + 1, OTHER + 2, OTHER + 3, OTHER + 4, OTHER + 5]
	StubAbilities.put_row(state, 1, enemy, true)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var zone: int = Choice.Zone.OWN_BOARD
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	assert_int(state.prompt.get("seat", -1)).is_equal(0)
	assert_int(Choice.exact_of(state.prompt)).is_equal(5)
	var kept: Array[int] = [0, 1, 2, 3, 4]
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, kept, false)).is_true()
	assert_int(state.prompt.get("seat", -1)).is_equal(1)
	assert_str(Choice.zone_name(Choice.zone_of(state.prompt))).is_equal("own_board")
	assert_array(Choice.options_of(state.prompt)).is_equal(_typed([0, 1, 2, 3, 4, 5]))
	var view: SeatView = SeatView.build(state, 1, 1, cards)
	var bot: RandomBot = RandomBot.new(7, cards)
	var action: EngineAction = bot.choose(view, null)
	assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
	assert_int(action.seat).is_equal(1)
	assert_int(action.indices.size()).is_equal(5)
	assert_bool(Choice.is_valid_set(state.prompt, action.zone, action.indices)).is_true()
	assert_bool(
		TriggerQueue.answer(state, cards, rng, rec.record, action.zone, action.indices, false)
	).is_false()
	assert_array(_marked(state, own)).is_equal(_typed([5, 6]))
	var dropped: Array[int] = _marked(state, enemy)
	assert_int(dropped.size()).is_equal(1)
	assert_bool(action.indices.has(enemy.find(dropped[0]))).is_false()


## A seat with five or fewer cards is unaffected: only seat 0 is prompted; with both rows at
## five or fewer Cull fizzles `no_target`.
func test_cull_leaves_a_row_of_five_alone() -> void:
	var cards: MatchCards = _cards()
	var cull: int = 0
	_put(cards, _typed([cull, cull + 1]), "ct10")
	var own: Array[int] = [cull, 2, 3, 4, 5, 6]
	var state: MatchState = StubAbilities.table(own, true)
	state.seats[0].revealed.erase(cull)
	var enemy: Array[int] = [OTHER, OTHER + 1, OTHER + 2, OTHER + 3, OTHER + 4]
	StubAbilities.put_row(state, 1, enemy, true)
	var rng: MatchRng = MatchRng.new(SEED)
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	ScoreWalk.begin(state)
	assert_bool(ScoreWalk.step(state, cards, rng, rec.record)).is_true()
	var zone: int = Choice.Zone.OWN_BOARD
	var kept: Array[int] = [1, 2, 3, 4, 5]
	assert_bool(TriggerQueue.answer(state, cards, rng, rec.record, zone, kept, false)).is_false()
	assert_array(_marked(state, own)).is_equal(_typed([cull]))
	assert_array(_marked(state, enemy)).is_empty()
	var small: MatchState = StubAbilities.table(_typed([cull + 1, 2]), false)
	var none: StubAbilities.Recorder = StubAbilities.recorder()
	_walk(small, cards, none)
	var fizzled: Array[MatchEvent] = none.of_kind(FIZZLED)
	assert_int(fizzled.size()).is_equal(1)
	assert_str(_str_of(fizzled[0], "reason")).is_equal(Abilities.REASON_NO_TARGET)


func _marked(state: MatchState, row: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for card: int in row:
		if Statuses.exit_mark_of(state, card) == Statuses.CONDEMNED:
			out.append(card)
	return out


# --- The random bot over every prompt -------------------------------------------------


## A deck list with GC_DECK: the twenty Graveyard and Control cards, two copies each.
func _gc_decks() -> DeckList:
	var listed: Array = []
	for id: String in GC_IDS:
		listed.append(id)
		listed.append(id)
	var deck: Dictionary = {
		"id": GC_DECK,
		"name": "Graveyard and Control (T13 test)",
		"tag": "control",
		"theme": "Every T13 card in one deck, for the random bot's prompts.",
		"cards": listed,
		"crew": ["tallyman", "void", "dredger"],
	}
	var text: String = JSON.stringify({"version": DeckList.FORMAT_VERSION, "decks": [deck]})
	return DeckList.from_json(text)


## Two random bots play whole matches of the twenty-card deck against itself: the engine
## accepts every action (every prompt the T13 verbs open, both-seat Cull included, gets a
## legal answer), each match ends, and its log replays to the same full state.
func test_random_bots_answer_every_prompt_of_the_twenty_cards() -> void:
	var decks: DeckList = _gc_decks()
	assert_bool(decks.is_valid()).override_failure_message(decks.load_error()).is_true()
	var crew: CrewPool = CrewPool.load_default()
	var ids: Array[String] = [GC_DECK, GC_DECK]
	var verbs: Dictionary[String, bool] = {}
	for match_seed: int in range(1, MATCH_SEEDS + 1):
		var engine: MatchEngine = MatchEngine.create(match_seed, _db(), decks, ids, crew)
		assert_bool(engine.start().ok).is_true()
		var bots: Array[RandomBot] = []
		for seat: int in range(MatchEngine.SEATS):
			bots.append(RandomBot.new(BotRegistry.seed_for(match_seed, seat), engine.match_cards()))
		var actions: int = 0
		while not engine.is_over() and actions < MAX_ACTIONS:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			var verb: String = view.prompt.get("verb", "")
			if verb != "":
				verbs[verb] = true
			var result: ApplyResult = engine.apply(bots[seat].choose(view, engine))
			assert_bool(result.ok).override_failure_message(
				"seed %d action %d rejected (%s)" % [match_seed, actions, verb]
			).is_true()
			if not result.ok:
				return
			actions += 1
		assert_bool(engine.is_over()).override_failure_message("seed %d" % match_seed).is_true()
		var replayed: ReplayResult = engine.action_log().replay(_db(), decks, crew)
		assert_bool(replayed.ok).is_true()
		if replayed.ok:
			assert_dict(replayed.engine.full_state()).is_equal(engine.full_state())
	assert_bool(verbs.size() > 1).override_failure_message(str(verbs.keys())).is_true()
