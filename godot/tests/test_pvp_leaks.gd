class_name TestPvpLeaks
extends PvpLeakHarness
## The P15 leak scan over every PVP message (cycle 12 T03; plan P15; spec R21, R33, R67) on
## GATE_SEEDS seeds, inside the gate's 30-second budget (R69). The scan itself lives in
## PvpLeakHarness; tests/sweep/test_pvp_leaks_sweep.gd runs it on SWEEP_SEEDS under
## `make sweep`. Rules 9 (cycle 14 R15, NSC-249): a Crew's stats change on a card in the
## first committer's pending face-down Commit reaches that seat only.

const PENDING_SEED: int = 1
const STATS: int = MatchEvent.Kind.STATS_CHANGED


func test_pvp_matches_send_no_seed_and_no_hidden_card() -> void:
	_scan_seeds(PvpLeakHarness.GATE_SEEDS)


## Seat 0 commits first, face down: its card sits in `pending` when Ramp's Captain (woken
## On score with the slot-0 context) raises its Power. The STATS_CHANGED, cause `captain`,
## goes to seat 0 only (Abilities.hidden_holder); no event seat 1 receives names the card,
## and seat 1's copy shows neutral stats. Once the card is revealed on the row, the next
## change is public.
func test_a_crew_stats_change_on_a_pending_card_reaches_the_first_committer_only() -> void:
	var cards: MatchCards = StubAbilities.defs(StubAbilities.RAMP_CREW)
	var state: MatchState = MatchState.new(PENDING_SEED)
	var card: int = 0
	state.first_seat = 0
	state.pending.assign([card])
	state.pending_slots.assign([0])
	state.reset_crew_uses(cards)
	var rec: StubAbilities.Recorder = _captain_on(state, cards, card)
	var changed: Array[MatchEvent] = rec.of_kind(STATS)
	assert_int(changed.size()).is_equal(1)
	assert_int(changed[0].owner_seat).is_equal(0)
	var cause: String = changed[0].payload["cause"]
	assert_str(cause).is_equal("captain")
	assert_int(rec.of_kind(MatchEvent.Kind.CREW_FIRED).size()).is_equal(1)
	for event: MatchEvent in rec.events:
		var seen: MatchEvent = event.redacted_for(1)
		var named: bool = FullMatchRun.event_card_ids(seen).has(card)
		var kind: String = MatchEvent.kind_name(event.kind)
		assert_bool(named).override_failure_message(kind + " names the pending card").is_false()
		if event.kind != STATS:
			continue
		for key: Variant in MatchEvent.STATS_HIDDEN:
			var neutral: bool = seen.payload.get(key) == MatchEvent.STATS_HIDDEN[key]
			assert_bool(neutral).override_failure_message("seat 1 sees %s" % key).is_true()
	state.pending.clear()
	state.pending_slots.clear()
	StubAbilities.put_row(state, 0, _typed([card]), true)
	var revealed: StubAbilities.Recorder = _captain_on(state, cards, card)
	var public: Array[MatchEvent] = revealed.of_kind(STATS)
	assert_int(public.size()).is_equal(1)
	assert_int(public[0].owner_seat).is_equal(MatchEvent.PUBLIC)


## Wakes `card`'s On score as the slot-0 Score of seat 0 and drains it: Ramp's Captain
## grows the card (Navigator fizzles). The events recorded.
func _captain_on(state: MatchState, cards: MatchCards, card: int) -> StubAbilities.Recorder:
	var rec: StubAbilities.Recorder = StubAbilities.recorder()
	var context: Dictionary = {CrewAbilities.KEY_SLOT: 0}
	var subjects: Array[int] = [card]
	var batch: Dictionary = TriggerQueue.wake(state, cards, "on_score", subjects, -1, context)
	assert_bool(batch.is_empty()).is_false()
	var rng: MatchRng = MatchRng.new(PENDING_SEED)
	assert_bool(TriggerQueue.drain(state, cards, rng, rec.record, "D2")).is_false()
	return rec
