class_name TestFullMatch
extends FullMatchHarness
## Full bot-vs-bot matches (C11): R33 (replay through JSON reaches an equal full state),
## R37 (the bot is a function of its seed and view, so a seed always plays the same match),
## R38 (the engine never rejects a bot action): seed 1 ends, no hand exceeds the harness's
## HAND_BOUND (rules 7: the Hand size plus the Turn's draw, the discard-down after each
## Commit), no commit exceeds the seat's Budget (the free first card and Memory included),
## no view or redacted event leaks a hidden card (prompts included) and the log replays to
## an equal state. DC-13 T03 (cycle 9 P15): the leak scan treats both Piles as public and
## the other seat's hand, Deck, face-down Commit and unlooked face-down row cards as hidden;
## ten seeds of random against random end, replay and scan clean.
## The 50-seed sweep and its "Sweep: ..." / "Sweep pairing ..." lines live in
## sweep/test_sweep.gd, outside the gate (NSC-133: `make sweep`); the shared play-and-check
## helpers are in fixtures/full_match_harness.gd.
## Cycle 8 (DC-09 T04; R8, R10, R31): the seeded pairing draws from the shipped decks
## (greed and ramp since DC-13 T02); a commit's cost reads the card's memory (an ability's
## cost reduction); the leak scan covers memory on hidden cards (a private STATS_CHANGED or
## CARD_RETURNED never names one to the other seat, and a face-down row entry shows no cost,
## growth or uses).
## DC-09 T06 review: the other seat's redacted STATS_CHANGED shows neutral stats
## (FullMatchRun.check_neutral_stats).
##
## Matches are played as main.gd plays its smoke run: the shipped pool and deck list, each
## seat's deck the seed's own pairing (DeckList.seeded_pick, DC-07 R6, P14, C15), one
## BotRegistry.default_name() bot per seat (`random`, cycle 9 R73) on the engine's
## MatchCards, seeded BotRegistry.seed_for(match_seed, seat) (cycle 7 P15), asked
## only for the awaited seat. A harness cap of MAX_ACTIONS fails a runaway match. Every log
## names both decks and replays with them (R7). Cycle 7 T05: every choose() is timed (the
## test reads the clock, never a bot, R18; the sweep checks the 99th percentile, R17, DC-08).

# GOLDEN (cycle 7 T05, R56: pinned by the orchestrator at verification)
# Seed 1's line under the default bot (tuned, k 24), pinned at DC-08 T11 (the greedy game
# of DC-07 T13): "seed=1 decks=ruin/ruin bot=tuned winner=1 wins=1-4 rounds=5 end=wins
# actions=88". Emptied at DC-09 T04 (Bloom and Echo shipped); re-pinned at T07.
# Seed 1 under the four-deck seeded pairing (Bloom and Echo shipped), pinned at DC-09 T07:
# "seed=1 decks=bloom/ruin bot=tuned winner=0 wins=4-0 rounds=4 end=wins actions=64".
# Emptied at DC-11 T10: the Crew fire (Gardener, Tallyman, Quartermaster; Salvager, Veil),
# so seed 1 plays another match; the orchestrator re-pins it at verification (T14). Still
# empty at DC-11 T11 (the tuned bot may decline an optional Crew prompt, cycle 8 R56, R57).
# Re-pinned at DC-11 T14 (four decks, live Crew, the T11 bot): "seed=1 decks=bloom/ruin
# bot=tuned winner=0 wins=4-0 rounds=4 end=wins actions=74".
# Emptied at DC-13 T01 (cycle 9 R70: only the random bot is left); while empty the golden
# case is skipped and the orchestrator re-pins it from its print.
# Re-pinned at DC-13 T11 (rules 7, greed/ramp, the random bot, C12 to C14): "seed=1
# decks=greed/greed bot=random winner=0 wins=3-1 rounds=7 end=rounds actions=121".
# Emptied at DC-14 T14: six decks change seed 1's seeded pairing (and Crew B fire); the
# orchestrator re-pins it at DC-14 T18 from the Golden print.
const GOLDEN: String = ""
# END GOLDEN

const SEED: int = 1
## The seeds 1..TEN_SEEDS of the gate's multi-seed case (DC-13 T03).
const TEN_SEEDS: int = 10
const GOLDEN_SKIP_NOTE: String = "GOLDEN is empty (DC-14 T14): pin it from the Golden print"
const REASONS: Array[String] = [
	MatchEngine.REASON_WINS,
	MatchEngine.REASON_ROUNDS,
	MatchEngine.REASON_SUDDEN_DEATH,
	MatchEngine.REASON_STALEMATE,
	MatchEngine.REASON_CONCEDE,
]

# --- Seed 1 ---------------------------------------------------------------------------


func test_seed_1_plays_to_the_end_and_replays() -> void:
	var run: FullMatchRun = _play(SEED, true)
	_assert_run(run)
	print("Golden: %s" % _result_line(run))
	var summary: Dictionary = _summary(run)
	assert_bool(summary.is_empty()).is_false()
	if summary.is_empty():
		return
	var winner: int = summary["winner"]
	var reason: String = summary["reason"]
	var rounds: int = summary["rounds"]
	# A stalemate (spec C12) may end in a draw (winner -1); every other end has a winner.
	var drawn: bool = winner == -1 and reason == MatchEngine.REASON_STALEMATE
	var won: bool = winner == 0 or winner == 1
	assert_bool(won or drawn).override_failure_message("winner %d" % winner).is_true()
	assert_bool(REASONS.has(reason)).override_failure_message(reason).is_true()
	# Bots never concede, and a match needs at least WINS_TO_TAKE rounds otherwise.
	assert_str(reason).is_not_equal(MatchEngine.REASON_CONCEDE)
	assert_int(rounds).is_greater_equal(MatchRules.WINS_TO_TAKE)
	# The action count, the log and the full state agree.
	assert_int(run.engine.accepted_action_count()).is_equal(run.actions)
	assert_int(run.engine.action_log().actions.size()).is_equal(run.actions)
	var applied: int = run.engine.full_state()["actions_applied"]
	assert_int(applied).is_equal(run.actions)
	# The face-down commit and the redacted private events were really scanned.
	assert_int(run.face_down_seen).is_greater(0)
	assert_int(run.redacted_seen).is_greater(0)
	# Rules 7: the bots answered discard-downs and the scan read public Pile entries.
	assert_int(run.discard_downs).is_greater(0)
	assert_int(run.pile_seen).is_greater(0)


## DC-13 T03 (cycle 9 R67, P15): ten seeds of random against random each end with no
## rejected action, keep every hand within its bound and every commit within its Budget,
## leak nothing at any step (Piles public, hands, Decks and face-down cards private) and
## replay through JSON to an equal full state.
func test_ten_seeds_of_random_vs_random_end_replay_and_scan_clean() -> void:
	var ended: int = 0
	for match_seed: int in range(1, TEN_SEEDS + 1):
		var run: FullMatchRun = _play(match_seed, true)
		_assert_run(run)
		if run.engine.is_over():
			ended += 1
	assert_int(ended).is_equal(TEN_SEEDS)


## R37: the bots are functions of their seeds and views, so seed 1 plays the same match
## every time, action for action.
func test_seed_1_is_the_same_match_every_time() -> void:
	var first: FullMatchRun = _play(SEED, false)
	var second: FullMatchRun = _play(SEED, false)
	assert_str(second.engine.action_log().to_json()).is_equal(first.engine.action_log().to_json())
	assert_dict(second.engine.full_state()).is_equal(first.engine.full_state())
	assert_dict(_summary(second)).is_equal(_summary(first))


## The pinned golden result: seed 1 under its own seeded pairing and the default bot, decks
## and bot name included (C15, R53; cycle 7 R56). Prints "Golden: <line>" every run; while
## GOLDEN is empty the case is skipped with GOLDEN_SKIP_NOTE, and the orchestrator pins it
## from the same print in test_seed_1_plays_to_the_end_and_replays at verification.
func test_seed_1_matches_the_golden_result(
	_do_skip: bool = GOLDEN == "", _skip_reason: String = GOLDEN_SKIP_NOTE
) -> void:
	var line: String = _result_line(_play(SEED, false))
	print("Golden: %s" % line)
	assert_str(line).override_failure_message("seed 1 did not end").is_not_empty()
	var message: String = "seed 1 played %s, golden is %s" % [line, GOLDEN]
	assert_str(line).override_failure_message(message).is_equal(GOLDEN)

