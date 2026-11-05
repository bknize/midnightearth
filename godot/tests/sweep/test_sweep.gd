class_name TestSweep
extends FullMatchHarness
## The 50-seed bot-vs-bot sweep (DC-05 T07, R39; moved out of test_full_match.gd at NSC-133).
## It runs outside the gate: `make check` skips res://tests/sweep, `make sweep` (or
## `scripts/check.sh sweep`) runs it, at /cycle test and for the bot rerun provision. The
## bot is BotRegistry.default_name() unless the SWEEP_BOT environment variable names another
## (`make sweep BOT=matrix`).
## The sweep prints "Sweep: longest=.. seed=.. longest_walk=.. walk_seed=.. slowest_us=..
## prompts=.. destroyed_hidden=.. pile_hidden=.. recoveries=.. recoveries_hidden=.. sets=..
## memory_hidden=.. bot=.. p95_us=.. p99_us=.. stamp=match|MISMATCH" and per pairing played
## "Sweep pairing <a>/<b>: seeds=.. longest=.. seed=.. slowest_us=.. seed=.." (DC-07 T08;
## cycle 7 T05, R17, R19, R35, R56).
## Every match checks what test_full_match.gd's seed 1 does (FullMatchHarness._assert_run):
## it ends, no hand exceeds 7, no commit exceeds the budget, nothing hidden leaks and the log
## replays; the 99th-percentile decision stays under DECISION_BUDGET_US; the weights' stamp
## is printed, never asserted (R35). The coverage counters (_assert_coverage: the scan met
## face-down cards, prompts, hidden destroys and so on) are asserted only for the default bot,
## whose play they were set for; another SWEEP_BOT prints a line saying they were skipped.

const SWEEP_FIRST: int = 1
const SWEEP_LAST: int = 50
## Seeds up to this one are leak-scanned at every step; later seeds only at the steps that
## end a turn (and the start).
const EVERY_STEP_SCAN_LAST: int = 50
## The 99th-percentile decision the sweep allows, in microseconds (R17, NSC-74, C14).
const DECISION_BUDGET_US: int = 10000
## The environment variable naming the bot to sweep instead of the default (NSC-133).
const BOT_ENV: String = "SWEEP_BOT"

## The longest swept match in accepted actions, and its seed; set by the sweep test.
static var longest_actions: int = 0
static var longest_seed: int = 0
## The slowest single bot choose() call of the sweep, in microseconds, its seed, the 95th
## and 99th percentiles of every decision (nearest rank), and the prompts the sweep's bots answered;
## set by the sweep test (DC-05 T14; cycle 7 T05, R17).
static var slowest_us: int = 0
static var slowest_seed: int = 0
static var p95_us: int = 0
static var p99_us: int = 0
## The bot the sweep played and its stamp check, STAMP_MATCH or STAMP_MISMATCH (R19, R35).
static var sweep_bot: String = ""
static var sweep_stamp: String = ""
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
	sweep_stamp = stamp_status(BotRegistry.default_weights_path(sweep_bot))
	sweep_prompts = 0
	longest_walk = 0
	longest_walk_seed = 0
	pairing_records = {}
	for pairing: String in _pairings():
		pairing_records[pairing] = _empty_record()
	var memory_hidden: int = 0
	var destroyed_hidden: int = 0
	var pile_hidden: int = 0
	var recoveries: int = 0
	var recoveries_hidden: int = 0
	var set_answers: int = 0
	var face_down_seen: int = 0
	var redacted_seen: int = 0
	var choices: int = 0
	var ended: int = 0
	var decisions: PackedInt32Array = PackedInt32Array()
	for match_seed: int in range(SWEEP_FIRST, SWEEP_LAST + 1):
		var run: FullMatchRun = _play(match_seed, match_seed <= EVERY_STEP_SCAN_LAST)
		_assert_run(run)
		decisions.append_array(run.decision_us)
		face_down_seen += run.face_down_seen
		redacted_seen += run.redacted_seen
		choices += run.choices
		destroyed_hidden += run.destroyed_hidden_seen
		pile_hidden += run.pile_hidden_seen
		recoveries += run.recoveries_seen
		recoveries_hidden += run.hidden_recoveries_seen
		memory_hidden += run.memory_hidden_seen
		set_answers += run.set_answers
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
	sweep_prompts = choices
	p95_us = _percentile(decisions, 95)
	p99_us = _percentile(decisions, 99)
	# One line for the orchestrator to read at verification (DC-05 T14, DC-06 T09; cycle 7
	# T05: the bot, its decision times and the stamp check, R17, R19, R35, R56).
	print(
		(
			(
				"Sweep: longest=%d seed=%d longest_walk=%d walk_seed=%d"
				+ " slowest_us=%d prompts=%d destroyed_hidden=%d pile_hidden=%d"
				+ " recoveries=%d recoveries_hidden=%d sets=%d memory_hidden=%d bot=%s"
				+ " p95_us=%d p99_us=%d stamp=%s"
			)
			% [
				longest_actions,
				longest_seed,
				longest_walk,
				longest_walk_seed,
				slowest_us,
				sweep_prompts,
				destroyed_hidden,
				pile_hidden,
				recoveries,
				recoveries_hidden,
				set_answers,
				memory_hidden,
				sweep_bot,
				p95_us,
				p99_us,
				sweep_stamp,
			]
		)
	)
	_print_pairings()
	_assert_pairings()
	assert_int(ended).is_equal(SWEEP_LAST - SWEEP_FIRST + 1)
	# R17 (NSC-74, DC-08): 99% of the shipped bot's decisions within the budget.
	var too_slow: String = (
		"99th-percentile decision %d us over the %d us budget (slowest %d us, seed %d)"
		% [p99_us, DECISION_BUDGET_US, slowest_us, slowest_seed]
	)
	assert_int(p99_us).override_failure_message(too_slow).is_less(DECISION_BUDGET_US)
	# Coverage (which hidden paths the bots happened to reach) holds only for the default bot,
	# whose play the counters were set for; every invariant above holds for any bot.
	if sweep_bot == BotRegistry.default_name():
		var counts: Dictionary = {
			"face_down_seen": face_down_seen,
			"redacted_seen": redacted_seen,
			"choices": choices,
			"destroyed_hidden": destroyed_hidden,
			"pile_hidden": pile_hidden,
			"recoveries": recoveries,
			"memory_hidden": memory_hidden,
			"longest_walk": longest_walk,
		}
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


## The sweep's coverage counters (`counts`, keyed by name, set by the sweep test) for the
## default bot: the scan really met face-down and redacted cards, prompts, hidden destroys,
## hidden pile entries, recoveries, hidden memory and a walk. Each depends on how the bot
## happens to play, so a SWEEP_BOT other than the default skips them.
func _assert_coverage(counts: Dictionary) -> void:
	var face_down_seen: int = counts["face_down_seen"]
	var redacted_seen: int = counts["redacted_seen"]
	var choices: int = counts["choices"]
	var destroyed_hidden: int = counts["destroyed_hidden"]
	var pile_hidden: int = counts["pile_hidden"]
	var recoveries: int = counts["recoveries"]
	var memory_hidden: int = counts["memory_hidden"]
	var walk: int = counts["longest_walk"]
	assert_int(face_down_seen).is_greater(0)
	assert_int(redacted_seen).is_greater(0)
	# The sweep really answered prompts, so their leak scan and replay ran (DC-05 T05).
	assert_int(choices).override_failure_message("no prompt in the sweep").is_greater(0)
	# A destroyed face-down card was really scanned (DC-06 R20, R21): a redacted destroy or
	# clear, or a destroyed face-down slot in a view.
	var no_hidden_destroy: String = "no destroyed face-down card in the sweep"
	assert_int(destroyed_hidden).override_failure_message(no_hidden_destroy).is_greater(0)
	assert_int(walk).override_failure_message("no walk in the sweep").is_greater(0)
	# DC-07 T08: the scan really covered the piles and recoveries. An opponent's pile entry
	# whose identity is not public was shown (as a hidden entry) to some view, and a card
	# left a destroyed pile for a hand (Grave Robber, R19).
	var no_pile: String = "no hidden destroyed-pile entry in the sweep"
	assert_int(pile_hidden).override_failure_message(no_pile).is_greater(0)
	var no_recovery: String = "no recovery in the sweep"
	assert_int(recoveries).override_failure_message(no_recovery).is_greater(0)
	# Cycle 8 R8, R31: memory on a hidden card really reached the scan, redacted for the
	# other seat (a growth on a hand card: Rain, Redwood, Vine).
	var no_memory: String = "no private memory event in the sweep"
	assert_int(memory_hidden).override_failure_message(no_memory).is_greater(0)


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


## Every swept seed played one of the sixteen pairings of DECKS, and the seeded pairing put
## every deck on each seat at least once (C15: the sweep exercises every deck on both
## seats; with four decks, 50 seeds need not reach all sixteen pairings, cycle 8 R31).
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
