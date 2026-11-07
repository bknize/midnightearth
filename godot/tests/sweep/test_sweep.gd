class_name TestSweep
extends FullMatchHarness
## The 50-seed bot-vs-bot sweep (DC-05 T07, R39; moved out of test_full_match.gd at NSC-133).
## It runs outside the gate: `make check` skips res://tests/sweep, `make sweep` (or
## `scripts/check.sh sweep`) runs it, at /cycle test and for bot reruns. The bot is
## BotRegistry.default_name() (`random`, cycle 9 R70, R73) unless the SWEEP_BOT environment
## variable names another; a name the registry cannot build fails every match. Each seed
## plays its seeded pairing of the shipped decks (greed/greed, greed/ramp, ramp/greed,
## ramp/ramp; DeckList.seeded_pick, DC-07 P14).
## The sweep prints (cycle 9 R85, DC-13 T08; no weights or stamp line):
## "Sweep: longest=.. seed=.. longest_walk=.. walk_seed=.. slowest_us=.. prompts=..
## discard_downs=.. empty_draws=.. pile_shuffles=.. looked=.. stalemates=.. draws=..
## pile_seen=.. sets=.. crew_prompts=.. declines=.. memory_hidden=.. bot=.. p95_us=..
## p99_us=.." and per pairing played "Sweep pairing <a>/<b>: seeds=.. longest=.. seed=..
## slowest_us=.. seed=..".
## Every match checks what test_full_match.gd's seed 1 does (FullMatchHarness._assert_run):
## it ends (a stalemate may draw, spec C12), no hand exceeds the harness's HAND_BOUND, no
## commit exceeds the Budget, nothing hidden leaks (the P15 scan: Piles public; hands, Decks,
## face-down and looked-at cards private) and the log replays; the 99th-percentile decision
## stays under DECISION_BUDGET_US. The coverage counters (_assert_coverage), reset at DC-13
## T08 for the random bot's play, are asserted only for the default bot; another SWEEP_BOT
## prints a line saying they were skipped.

const SWEEP_FIRST: int = 1
const SWEEP_LAST: int = 50
## Seeds up to this one are leak-scanned at every step; later seeds only at the steps that
## end a turn (and the start).
const EVERY_STEP_SCAN_LAST: int = 50
## The 99th-percentile decision the sweep allows, in microseconds (R17, NSC-74, C14).
const DECISION_BUDGET_US: int = 10000
## The environment variable naming the bot to sweep instead of the default (NSC-133).
const BOT_ENV: String = "SWEEP_BOT"
## The sweep's counters, in the summary line's order (face_down_seen and redacted_seen are
## asserted but not printed).
const COUNTER_KEYS: Array[String] = [
	"face_down_seen",
	"redacted_seen",
	"prompts",
	"discard_downs",
	"empty_draws",
	"pile_shuffles",
	"looked",
	"stalemates",
	"draws",
	"pile_seen",
	"sets",
	"crew_prompts",
	"declines",
	"memory_hidden",
]
## The counters the default bot's sweep must reach (_assert_coverage).
const COVERED_KEYS: Array[String] = [
	"face_down_seen",
	"redacted_seen",
	"prompts",
	"discard_downs",
	"empty_draws",
	"pile_shuffles",
	"pile_seen",
	"longest_walk",
]

## The longest swept match in accepted actions, and its seed; set by the sweep test.
static var longest_actions: int = 0
static var longest_seed: int = 0
## The slowest single bot choose() call of the sweep, in microseconds, its seed, the 95th
## and 99th percentiles of every decision (nearest rank), and the prompts the sweep's bots
## answered; set by the sweep test (DC-05 T14; cycle 7 T05, R17).
static var slowest_us: int = 0
static var slowest_seed: int = 0
static var p95_us: int = 0
static var p99_us: int = 0
## The bot the sweep played (R19).
static var sweep_bot: String = ""
static var sweep_prompts: int = 0
## The longest single walk of the sweep in pulses, and its seed (DC-06 T03, R25, NSC-74).
static var longest_walk: int = 0
static var longest_walk_seed: int = 0
## Per pairing ("a/b", _pairings()): {seeds, longest, longest_seed, slowest_us, slowest_seed};
## set by the sweep test (DC-07 T08, R38; read at T13 for NSC-74).
static var pairing_records: Dictionary = {}

# --- Helpers --------------------------------------------------------------------------


## Every pairing of DECKS as "a/b" (seat 0's deck, then seat 1's), seat 0's deck major.
static func _pairings() -> Array[String]:
	var out: Array[String] = []
	for first: String in DECKS:
		for second: String in DECKS:
			out.append("%s/%s" % [first, second])
	return out


## The sweep's bot: SWEEP_BOT when set, else the registry default (NSC-133).
func _bot_name() -> String:
	var wanted: String = OS.get_environment(BOT_ENV)
	if wanted != "":
		return wanted
	return BotRegistry.default_name()


# --- 50-seed sweep --------------------------------------------------------------------


func test_fifty_seed_sweep_keeps_every_invariant() -> void:
	longest_actions = 0
	longest_seed = 0
	slowest_us = 0
	slowest_seed = 0
	p95_us = 0
	p99_us = 0
	sweep_bot = _bot_name()
	sweep_prompts = 0
	longest_walk = 0
	longest_walk_seed = 0
	pairing_records = {}
	for pairing: String in _pairings():
		pairing_records[pairing] = _empty_record()
	var counts: Dictionary = {}
	for key: String in COUNTER_KEYS:
		counts[key] = 0
	var ended: int = 0
	var decisions: PackedInt32Array = PackedInt32Array()
	for match_seed: int in range(SWEEP_FIRST, SWEEP_LAST + 1):
		var run: FullMatchRun = _play(match_seed, match_seed <= EVERY_STEP_SCAN_LAST)
		_assert_run(run)
		decisions.append_array(run.decision_us)
		_count_run(counts, run)
		_record_pairing(run)
		if run.longest_walk > longest_walk:
			longest_walk = run.longest_walk
			longest_walk_seed = match_seed
		if run.engine.is_over():
			ended += 1
		if run.actions > longest_actions:
			longest_actions = run.actions
			longest_seed = match_seed
		if run.slowest_us > slowest_us:
			slowest_us = run.slowest_us
			slowest_seed = match_seed
	var prompts: int = counts["prompts"]
	sweep_prompts = prompts
	p95_us = _percentile(decisions, 95)
	p99_us = _percentile(decisions, 99)
	# One line for the orchestrator to read at verification (cycle 9 R85, DC-13 T08).
	print(_summary_line(counts))
	_print_pairings()
	_assert_pairings()
	assert_int(ended).is_equal(SWEEP_LAST - SWEEP_FIRST + 1)
	# R17 (NSC-74, DC-08; cycle 9 R85): 99% of the bot's decisions within the budget.
	var too_slow: String = (
		"99th-percentile decision %d us over the %d us budget (slowest %d us, seed %d)"
		% [p99_us, DECISION_BUDGET_US, slowest_us, slowest_seed]
	)
	assert_int(p99_us).override_failure_message(too_slow).is_less(DECISION_BUDGET_US)
	# Coverage (which hidden paths the bots happened to reach) holds only for the default bot,
	# whose play the counters were set for; every invariant above holds for any bot.
	if sweep_bot == BotRegistry.default_name():
		counts["longest_walk"] = longest_walk
		_assert_coverage(counts)
	else:
		print(
			(
				"Sweep: coverage assertions skipped for bot=%s (they hold for the default, %s)"
				% [sweep_bot, BotRegistry.default_name()]
			)
		)
	# The longest match, readable from the static and from this message.
	var longest: String = (
		"longest match: seed %d, %d actions (cap %d)" % [longest_seed, longest_actions, MAX_ACTIONS]
	)
	assert_int(longest_actions).override_failure_message(longest).is_between(1, MAX_ACTIONS - 1)


## Adds one run's counters to `counts` (keyed by COUNTER_KEYS): what the scan met and the
## bots answered, plus a stalemate end (spec C12) and a drawn match (winner -1).
func _count_run(counts: Dictionary, run: FullMatchRun) -> void:
	var seen: Dictionary = {
		"face_down_seen": run.face_down_seen,
		"redacted_seen": run.redacted_seen,
		"prompts": run.choices,
		"discard_downs": run.discard_downs,
		"empty_draws": run.empty_draws,
		"pile_shuffles": run.pile_shuffles,
		"looked": run.looked_seen,
		"stalemates": 0,
		"draws": 0,
		"pile_seen": run.pile_seen,
		"sets": run.set_answers,
		"crew_prompts": run.crew_prompts,
		"declines": run.declines,
		"memory_hidden": run.memory_hidden_seen,
	}
	if not run.end_payload.is_empty():
		var reason: String = run.end_payload.get("reason", "")
		var winner: int = run.end_payload.get("winner", -1)
		if reason == MatchEngine.REASON_STALEMATE:
			seen["stalemates"] = 1
		if winner == -1:
			seen["draws"] = 1
	for key: String in COUNTER_KEYS:
		var total: int = counts.get(key, 0)
		var add: int = seen.get(key, 0)
		counts[key] = total + add


## The "Sweep: ..." summary line (see the class comment) over `counts` and the statics.
func _summary_line(counts: Dictionary) -> String:
	var head: String = (
		"Sweep: longest=%d seed=%d longest_walk=%d walk_seed=%d slowest_us=%d"
		% [longest_actions, longest_seed, longest_walk, longest_walk_seed, slowest_us]
	)
	var parts: PackedStringArray = PackedStringArray([head])
	for key: String in COUNTER_KEYS:
		if key == "face_down_seen" or key == "redacted_seen":
			continue
		var value: int = counts.get(key, 0)
		parts.append("%s=%d" % [key, value])
	parts.append("bot=%s p95_us=%d p99_us=%d" % [sweep_bot, p95_us, p99_us])
	return " ".join(parts)


## The sweep's coverage counters (`counts`, keyed by COUNTER_KEYS plus `longest_walk`) for
## the default bot, reset at DC-13 T08 for the random bot's play on the milestone A decks:
## the scan really met face-down and redacted cards and public Pile entries, and the bots
## answered prompts and discard-downs, met empty draws, shuffled a Pile into a Deck
## (Dredger) and played a Walk. Looked-at cards, stalemates and draws are printed, not
## asserted: no Greed or Ramp card looks at a card (Lookout and Delve are evergreen, in
## neither deck), and a stalemate is rare (spec C12: 7 in 200 seeds), so 50 seeds may meet
## none. A SWEEP_BOT other than the default skips them.
func _assert_coverage(counts: Dictionary) -> void:
	for key: String in COVERED_KEYS:
		var value: int = counts.get(key, 0)
		var missing: String = "the sweep met no %s" % key
		assert_int(value).override_failure_message(missing).is_greater(0)


## A pairing's record before any seed: no seeds, no match, no decision.
func _empty_record() -> Dictionary:
	return {"seeds": 0, "longest": 0, "longest_seed": 0, "slowest_us": 0, "slowest_seed": 0}


## Folds one run into its pairing's record (DC-07 T08, R38): the seed count, the longest
## match in accepted actions and the slowest single bot decision, each with its seed.
func _record_pairing(run: FullMatchRun) -> void:
	if not pairing_records.has(run.pairing):
		pairing_records[run.pairing] = _empty_record()
	var record: Dictionary = pairing_records[run.pairing]
	var seeds: int = record["seeds"]
	var longest: int = record["longest"]
	var slowest: int = record["slowest_us"]
	record["seeds"] = seeds + 1
	if run.actions > longest:
		record["longest"] = run.actions
		record["longest_seed"] = run.match_seed
	if run.slowest_us > slowest:
		record["slowest_us"] = run.slowest_us
		record["slowest_seed"] = run.match_seed


## One line per pairing played for the orchestrator to read at verification (DC-07 T13,
## NSC-74): "Sweep pairing <a>/<b>: seeds=.. longest=.. seed=.. slowest_us=.. seed=..".
func _print_pairings() -> void:
	for pairing: String in _pairings():
		var record: Dictionary = pairing_records.get(pairing, _empty_record())
		var seeds: int = record["seeds"]
		if seeds == 0:
			continue
		var longest: int = record["longest"]
		var longest_at: int = record["longest_seed"]
		var slowest: int = record["slowest_us"]
		var slowest_at: int = record["slowest_seed"]
		print(
			(
				"Sweep pairing %s: seeds=%d longest=%d seed=%d slowest_us=%d seed=%d"
				% [pairing, seeds, longest, longest_at, slowest, slowest_at]
			)
		)


## Every swept seed played one of the four pairings of DECKS, and the seeded pairing put
## every deck on each seat at least once (C15: the sweep exercises every deck on both
## seats).
func _assert_pairings() -> void:
	var known_pairings: Array[String] = _pairings()
	var total: int = 0
	var on_seat: Array[Dictionary] = [{}, {}]
	for key: Variant in pairing_records.keys():
		var pairing: String = key
		var known: String = "unexpected pairing %s" % pairing
		assert_bool(known_pairings.has(pairing)).override_failure_message(known).is_true()
		var record: Dictionary = pairing_records[pairing]
		var seeds: int = record["seeds"]
		total += seeds
		var decks: PackedStringArray = pairing.split("/")
		for seat: int in range(mini(decks.size(), MatchEngine.SEATS)):
			if seeds > 0:
				on_seat[seat][decks[seat]] = true
	for seat: int in range(MatchEngine.SEATS):
		for deck_id: String in DECKS:
			var never: String = "no seed of the sweep played %s on seat %d" % [deck_id, seat]
			assert_bool(on_seat[seat].has(deck_id)).override_failure_message(never).is_true()
	assert_int(total).is_equal(SWEEP_LAST - SWEEP_FIRST + 1)


## The `pct` percentile of `times` by nearest rank: the value at rank ceil(pct / 100 * n) of
## the sorted times (integer arithmetic); 0 for no times. `times` is left unsorted.
static func _percentile(times: PackedInt32Array, pct: int) -> int:
	if times.is_empty():
		return 0
	var sorted: PackedInt32Array = times.duplicate()
	sorted.sort()
	return sorted[(pct * sorted.size() + 99) / 100 - 1]
