#!/usr/bin/env python3
"""Bot strength driver (plan P18): fans out workers, decides by SPRT. No model tokens.

  driver.py eval --a tuned --b greedy_v1 [--gainer|--nonreg] [--seeds 1-5000]
                 [--cap 20000] [--label L]
  driver.py selftest
  driver.py train --bot tuned [--hours 8] [--label L] [--run-seed N]   (see evolve.py)
  driver.py calibrate [--levels 0,4,8,12,16,20] [--pairings a/b,...] [--seeds 200]
                                     (see calibrate.py)

Exit codes: 0 PASS, 1 FAIL, 2 CAP (cap or seed range ended the run), 3 error.
PASS is the H1 bound in both modes (see sprt.py). Summary bound is H1, H0 or cap.
Godot comes from GODOT_BIN (default as scripts/check.sh).
"""
import argparse
import concurrent.futures
import datetime
import json
import os
import subprocess
import sys
import unittest
from typing import Any, Callable, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import records  # noqa: E402
import sprt  # noqa: E402

DEFAULT_GODOT = "/Applications/Godot 4.6.app/Contents/MacOS/Godot"
BATCH_SEEDS = 25
P99_BUDGET_US = 10000  # R17: the 99th-percentile decision stays under 10 ms
EXIT_PASS, EXIT_FAIL, EXIT_CAP, EXIT_ERROR = 0, 1, 2, 3

WorkerFactory = Callable[[str, str, int, int, str], List[str]]


def parse_seeds(text: str) -> Tuple[int, int]:
    lo_s, _, hi_s = text.partition("-")
    lo = int(lo_s)
    hi = int(hi_s) if hi_s else lo
    if lo < 0 or hi < lo:
        raise ValueError("bad seed range %r" % text)
    return lo, hi


def batches(lo: int, hi: int, size: int = BATCH_SEEDS) -> List[Tuple[int, int]]:
    return [(s, min(s + size - 1, hi)) for s in range(lo, hi + 1, size)]


def godot_bin() -> str:
    return os.environ.get("GODOT_BIN", DEFAULT_GODOT)


def weights_path(bot: str) -> Optional[str]:
    p = os.path.join(records.WEIGHTS_DIR, "%s_weights.json" % bot)
    return p if os.path.isfile(p) else None


def godot_worker(a: str, b: str, lo: int, hi: int, out: str, label: str,
                 weights_a: Optional[str] = None,
                 weights_b: Optional[str] = None, decks: str = "seeded",
                 level_a: Optional[int] = None) -> List[str]:
    """The worker's argv. A side's weights file is the given one, none when "" and the
    committed `<bot>_weights.json` (when there is one) when None. `decks` is `seeded` or
    `<id>/<id>`; `level_a` (when given) is A's difficulty level."""
    cmd = [godot_bin(), "--headless", "--path", "godot", "-s", "res://tools/bot_worker.gd",
           "--", "--a=%s" % a, "--b=%s" % b, "--seeds=%d-%d" % (lo, hi),
           "--decks=%s" % decks, "--out=%s" % out, "--label=%s" % label]
    if level_a is not None:
        cmd.append("--level-a=%d" % level_a)
    for flag, bot, given in (("--weights-a=", a, weights_a), ("--weights-b=", b, weights_b)):
        w = weights_path(bot) if given is None else given
        if w:
            cmd.append(flag + w)
    return cmd


def run_worker(argv: List[str]) -> Tuple[int, str]:
    """Run one worker; (exit code, last output lines). A failure to start is code 127."""
    try:
        proc = subprocess.run(argv, cwd=records.REPO_ROOT, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, universal_newlines=True)
    except OSError as e:
        return 127, "failed to start: %s" % e
    tail = "\n".join(proc.stdout.strip().splitlines()[-5:])
    return proc.returncode, tail


def feed_until_decided(test: sprt.Sprt,
                       recs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Feed a batch's pair records to `test` in order and stop at the first pair that
    decides it (R28: the stopping rule is checked per pair, never per batch). Returns the
    batch's records for the seeds fed: their pairs, games and decisions, plus the batch's
    own `end` record, whose counts (rejected, overruns) cover the whole batch."""
    seeds = set()
    for r in recs:
        if r.get("t") != "p":
            continue
        test.add(float(r["points_a"]))
        seeds.add(r.get("seed"))
        if test.decided():
            break
    return [r for r in recs if r.get("t") == "end" or r.get("seed") in seeds]


def run_eval(args: argparse.Namespace,
             factory: Optional[WorkerFactory] = None,
             workers: Optional[int] = None) -> int:
    return eval_report(args, factory, workers)[0]


def eval_report(args: argparse.Namespace,
                factory: Optional[WorkerFactory] = None,
                workers: Optional[int] = None) -> Tuple[int, Dict[str, Any]]:
    """run_eval's body: (exit code, the report dict; empty when the run errored).
    `args.weights_a` / `args.weights_b` (optional paths) replace a side's committed file."""
    wa = getattr(args, "weights_a", "") or None
    wb = getattr(args, "weights_b", "") or None
    try:
        lo, hi = parse_seeds(args.seeds)
    except ValueError as e:
        print("bot-eval: %s" % e, file=sys.stderr)
        return EXIT_ERROR, {}
    mode = "gainer" if args.gainer else "nonreg"
    label = args.label or "%s-vs-%s" % (args.a, args.b)
    if factory is None:
        if not os.path.isfile(godot_bin()):
            print("bot-eval: Godot not found at %s (set GODOT_BIN)" % godot_bin(),
                  file=sys.stderr)
            return EXIT_ERROR, {}
        factory = lambda a, b, s, e, out: godot_worker(  # noqa: E731
            a, b, s, e, out, label, wa, wb)
    stamp = records.current_stamp()
    mismatch = False
    for bot, given in ((args.a, wa), (args.b, wb)):
        ws = records.file_stamp(given) if given else records.weights_stamp(bot)
        if ws is not None and ws != stamp:
            print("bot-eval: %s weights stamp %s differs from current %s; retrain (R38)"
                  % (bot, ws, stamp))
            mismatch = True
    base = args.reports_dir or os.path.join(records.GODOT_DIR, "reports", "bot")
    out_dir = os.path.join(base, "%s-%s" % (label, datetime.date.today().isoformat()))
    os.makedirs(out_dir, exist_ok=True)

    plan = batches(lo, hi)
    test = sprt.Sprt(mode, args.cap)
    n_workers = max(1, workers or os.cpu_count() or 1)
    done: Dict[int, str] = {}      # batch index -> output path, finished and ok
    fed: List[str] = []            # output paths fed to the SPRT, in seed order
    consumed: List[Dict[str, Any]] = []  # the fed batches' records up to the stopping pair
    failures: List[str] = []
    fail_codes: List[int] = []
    running: Dict[Any, int] = {}
    next_i = 0
    next_feed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=n_workers) as pool:
        while True:
            while (not failures and not test.decided() and next_i < len(plan)
                   and len(running) < n_workers):
                s, e = plan[next_i]
                out = os.path.join(out_dir, "batch-%d-%d.jsonl" % (s, e))
                running[pool.submit(run_worker, factory(args.a, args.b, s, e, out))] = next_i
                next_i += 1
            if not running:
                break
            finished, _ = concurrent.futures.wait(
                list(running), return_when=concurrent.futures.FIRST_COMPLETED)
            for fut in finished:
                i = running.pop(fut)
                code, tail = fut.result()
                s, e = plan[i]
                out = os.path.join(out_dir, "batch-%d-%d.jsonl" % (s, e))
                if code != 0:
                    fail_codes.append(code)
                    failures.append("worker seeds %d-%d exit %d: %s"
                                    % (s, e, code, tail.replace("\n", " | ")))
                    if os.path.exists(out):
                        os.remove(out)  # discard the partial batch (R31)
                else:
                    done[i] = out
            while not failures and next_feed in done and not test.decided():
                path = done[next_feed]
                fed.append(path)
                consumed.extend(feed_until_decided(test, records.read_records(path)))
                next_feed += 1
    if failures:
        for f in failures:
            print("bot-eval: " + f, file=sys.stderr)
        # worker exit codes, so a caller can tell a candidate's own failure (1: rejected
        # action or replay mismatch) from infrastructure (2, 3, 127)
        return EXIT_ERROR, {"worker_exit_codes": sorted(set(fail_codes))}

    agg = records.aggregate(consumed)
    state = test.state()
    result = {"H1": "PASS", "H0": "FAIL"}.get(state or "", "CAP")
    bound = state if state in ("H0", "H1") else "cap"
    code = {"PASS": EXIT_PASS, "FAIL": EXIT_FAIL, "CAP": EXIT_CAP}[result]
    if mismatch or any(s != stamp for s in agg["stamps"]):
        mismatch = True
    if agg["rejected"] or agg["replay_mismatches"]:
        print("bot-eval: invariant counts rejected=%d replay_mismatches=%d"
              % (agg["rejected"], agg["replay_mismatches"]), file=sys.stderr)
    reason = ""
    if args.gainer and result == "PASS":
        # R41 as amended by C16: p99 of side a's decisions under the budget, not zero overruns
        if agg["p99_us"] >= P99_BUDGET_US:
            reason = " reason=p99"
        elif agg["rejected"] > 0:
            reason = " reason=rejected"
        elif agg["replay_mismatches"] > 0:
            reason = " reason=replay"
        if reason:
            result, code = "FAIL", EXIT_FAIL
    summary = ("bot-eval: a=%s b=%s result=%s bound=%s pairs=%d games=%d "
               "winrate=%.3f±%.3f first_committer=%.2f p95_us=%d p99_us=%d slowest_us=%d "
               "overruns_a=%d overruns_b=%d stamp=%s exit=%d%s"
               % (args.a, args.b, result, bound, agg["pairs"], agg["games"], agg["winrate"],
                  agg["winrate_ci95"], agg["first_committer"], agg["p95_us"],
                  agg["p99_us"], agg["slowest_us"], agg["overruns_a"], agg["overruns_b"],
                  "MISMATCH" if mismatch else "match", code, reason))
    report = {"a": args.a, "b": args.b, "mode": mode, "label": label, "seeds": args.seeds,
              "cap": args.cap, "result": result, "bound": bound, "llr": test.llr(),
              "pentanomial": test.counts, "stamp": stamp, "stamp_mismatch": mismatch,
              "aggregates": agg, "batches": [os.path.basename(p) for p in fed],
              "summary": summary, "exit": code}
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, sort_keys=True)
    print(summary)
    return code, report


def run_selftest() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    suite = unittest.defaultTestLoader.discover(here, pattern="test_*.py")
    res = unittest.TextTestRunner(verbosity=1).run(suite)
    return EXIT_PASS if res.wasSuccessful() else EXIT_FAIL


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="driver.py", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    ev = sub.add_parser("eval", help="SPRT strength comparison of two bots")
    ev.add_argument("--a", required=True)
    ev.add_argument("--b", required=True)
    mode = ev.add_mutually_exclusive_group()
    mode.add_argument("--gainer", action="store_true", help="bounds [0, +25]")
    mode.add_argument("--nonreg", action="store_true", help="bounds [-25, 0] (default)")
    ev.add_argument("--seeds", default="1-5000")
    ev.add_argument("--cap", type=int, default=sprt.DEFAULT_CAP, help="max pairs")
    ev.add_argument("--label", default="")
    ev.add_argument("--reports-dir", default="", help=argparse.SUPPRESS)
    ev.add_argument("--weights-a", default="", help="weights file for A (default: committed)")
    ev.add_argument("--weights-b", default="", help="weights file for B (default: committed)")
    sub.add_parser("selftest", help="run the unit tests")
    import evolve  # noqa: E402  (evolve imports this module; only its parser is needed)
    evolve.add_train_parser(sub)
    import calibrate  # noqa: E402  (calibrate imports this module; only its parser is needed)
    calibrate.add_calibrate_parser(sub)
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.cmd == "eval":
        return run_eval(args)
    if args.cmd == "selftest":
        return run_selftest()
    if args.cmd == "train":
        import evolve
        return evolve.run_train(args)
    if args.cmd == "calibrate":
        import calibrate
        return calibrate.run_calibrate(args)
    print("driver.py %s: not yet implemented" % args.cmd, file=sys.stderr)
    return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
