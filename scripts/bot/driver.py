#!/usr/bin/env python3
"""Bot strength driver (plan P18): fans out workers, decides by SPRT. No model tokens.

  driver.py eval --a random --b random [--gainer|--nonreg] [--seeds 1-5000]
                 [--cap 20000] [--batch 25] [--decks seeded] [--budget-us N] [--label L]
                 [--weights-a PATH] [--weights-b PATH]
  driver.py selftest

Exit codes: 0 PASS, 1 FAIL, 2 CAP (cap or seed range ended the run), 3 error.
PASS is the H1 bound in both modes (see sprt.py). Summary bound is H1, H0 or cap.
Godot comes from GODOT_BIN (default as scripts/check.sh).
"""
import argparse
import concurrent.futures
import datetime
import json
import os
import shutil
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


def godot_found(path: str) -> bool:
    """True when `path` names a Godot binary: a file, a command on PATH, or (Windows) a path
    given without its `.exe`."""
    return (os.path.isfile(path) or shutil.which(path) is not None
            or os.path.isfile(path + ".exe"))


def godot_worker(a: str, b: str, lo: int, hi: int, out: str, label: str,
                 decks: str = "seeded", budget_us: Optional[int] = None,
                 weights_a: str = "", weights_b: str = "") -> List[str]:
    """The match worker's argv (no shell). `decks` is `seeded` or `<id>/<id>`."""
    cmd = [godot_bin(), "--headless", "--path", "godot", "-s", "res://tools/match_worker.gd",
           "--", "--a=%s" % a, "--b=%s" % b, "--seeds=%d-%d" % (lo, hi),
           "--decks=%s" % decks, "--out=%s" % out, "--label=%s" % label]
    if budget_us is not None:
        cmd.append("--budget-us=%d" % budget_us)
    if weights_a:
        cmd.append("--weights-a=%s" % weights_a)
    if weights_b:
        cmd.append("--weights-b=%s" % weights_b)
    return cmd


def run_worker(argv: List[str]) -> Tuple[int, str]:
    """Run one worker; (exit code, last output lines). A failure to start is code 127."""
    try:
        proc = subprocess.run(argv, cwd=records.REPO_ROOT, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                              errors="replace")
    except OSError as e:
        return 127, "failed to start: %s" % e
    tail = "\n".join(proc.stdout.strip().splitlines()[-5:])
    return proc.returncode, tail


def feed_until_decided(test: sprt.Sprt,
                       recs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Feed a batch's pair records to `test` in order and stop at the first pair that
    decides it (R28: the stopping rule is checked per pair, never per batch). Returns the
    records of the pairs fed (NSC-206): each fed pair's `p` record and the games and
    decisions of its two games (a seed's k-th pair owns games 2k and 2k+1), plus the
    batch's own `end` record, whose counts (rejected, overruns) cover the whole batch."""
    seen: Dict[Any, int] = {}
    fed = set()
    for r in recs:
        if r.get("t") != "p":
            continue
        seed = r.get("seed")
        k = seen.get(seed, 0)
        seen[seed] = k + 1
        test.add(float(r["points_a"]))
        fed.add((seed, k))
        if test.decided():
            break
    kept: List[Dict[str, Any]] = []
    counted: Dict[Any, int] = {}
    for r in recs:
        kind = r.get("t")
        if kind == "end":
            kept.append(r)
        elif kind == "p":
            seed = r.get("seed")
            k = counted.get(seed, 0)
            counted[seed] = k + 1
            if (seed, k) in fed:
                kept.append(r)
        elif (r.get("seed"), int(r.get("game", 0)) // 2) in fed:
            kept.append(r)
    return kept


def batch_stamp_mismatch(recs: List[Dict[str, Any]], stamp: str) -> str:
    """The engine stamps of a batch's end records that are not `stamp`, joined by ", ";
    "" when every end record carries `stamp` (or none carries a stamp)."""
    other = sorted({str(r["stamp"]) for r in recs
                    if r.get("t") == "end" and "stamp" in r and str(r["stamp"]) != stamp})
    return ", ".join(other)


def run_eval(args: argparse.Namespace,
             factory: Optional[WorkerFactory] = None,
             workers: Optional[int] = None) -> int:
    return eval_report(args, factory, workers)[0]


def eval_report(args: argparse.Namespace,
                factory: Optional[WorkerFactory] = None,
                workers: Optional[int] = None) -> Tuple[int, Dict[str, Any]]:
    """run_eval's body: (exit code, the report dict; worker exit codes when it errored)."""
    try:
        lo, hi = parse_seeds(args.seeds)
    except ValueError as e:
        print("bot-eval: %s" % e, file=sys.stderr)
        return EXIT_ERROR, {}
    mode = "gainer" if args.gainer else "nonreg"
    label = args.label or "%s-vs-%s" % (args.a, args.b)
    if factory is None:
        if not godot_found(godot_bin()):
            print("bot-eval: Godot not found at %s (set GODOT_BIN)" % godot_bin(),
                  file=sys.stderr)
            return EXIT_ERROR, {}
        decks = args.decks
        budget = args.budget_us
        wa, wb = args.weights_a, args.weights_b
        factory = lambda a, b, s, e, out: godot_worker(  # noqa: E731
            a, b, s, e, out, label, decks, budget, wa, wb)
    stamp = records.current_stamp()
    base = args.reports_dir or os.path.join(records.GODOT_DIR, "reports", "bot")
    out_dir = os.path.join(base, "%s-%s" % (label, datetime.date.today().isoformat()))
    os.makedirs(out_dir, exist_ok=True)

    plan = batches(lo, hi, max(1, args.batch))
    test = sprt.Sprt(mode, args.cap)
    n_workers = max(1, workers or os.cpu_count() or 1)
    done: Dict[int, str] = {}      # batch index -> output path, finished and ok
    fed: List[str] = []            # output paths fed to the SPRT, in seed order
    consumed: List[Dict[str, Any]] = []  # the fed batches' records up to the stopping pair
    failures: List[str] = []
    fail_codes: List[int] = []
    running: Dict[Any, int] = {}
    stale = ""                     # a batch's engine stamp, when it is not the driver's
    next_i = 0
    next_feed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=n_workers) as pool:
        while True:
            while (not failures and not stale and not test.decided() and next_i < len(plan)
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
                    if not stale:
                        stale = batch_stamp_mismatch(records.read_records(out), stamp)
            while (not failures and not stale and next_feed in done
                   and not test.decided()):
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
    if stale:
        # a stale worker fails fast: nothing is scheduled after the first stamp mismatch
        print("bot-eval: engine stamp %s differs from the driver's %s" % (stale, stamp),
              file=sys.stderr)
        return EXIT_ERROR, {}

    agg = records.aggregate(consumed)
    state = test.state()
    result = {"H1": "PASS", "H0": "FAIL"}.get(state or "", "CAP")
    bound = state if state in ("H0", "H1") else "cap"
    code = {"PASS": EXIT_PASS, "FAIL": EXIT_FAIL, "CAP": EXIT_CAP}[result]
    if any(s != stamp for s in agg["stamps"]):
        # cycle 11: a worker built on other card data than the driver's is an error
        print("bot-eval: engine stamp %s differs from the driver's %s"
              % (", ".join(agg["stamps"]), stamp), file=sys.stderr)
        return EXIT_ERROR, {}
    # plan P7: `none` (no weights file) is not a mismatch
    mismatch = any(s not in ("match", "none") for s in agg["weights_stamps"])
    if agg["rejected"] or agg["replay_mismatches"]:
        print("bot-eval: invariant counts rejected=%d replay_mismatches=%d"
              % (agg["rejected"], agg["replay_mismatches"]), file=sys.stderr)
    reason = ""
    if args.gainer and result == "PASS":
        # R41 (C16 follow-up): p99_us is printed but not judged here; the trainer measures it
        # in a quiet sweep of the candidate, since all-core contention inflates it.
        if agg["rejected"] > 0:
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
    ev.add_argument("--batch", type=int, default=BATCH_SEEDS,
                    help="seeds per worker process (default %d)" % BATCH_SEEDS)
    ev.add_argument("--decks", default="seeded", help="seeded or <id>/<id>")
    ev.add_argument("--budget-us", type=int, default=None, help="decision budget override")
    ev.add_argument("--weights-a", default="", help="weights file for side a (optional)")
    ev.add_argument("--weights-b", default="", help="weights file for side b (optional)")
    sub.add_parser("selftest", help="run the unit tests")
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.cmd == "eval":
        return run_eval(args)
    if args.cmd == "selftest":
        return run_selftest()
    print("driver.py %s: not yet implemented" % args.cmd, file=sys.stderr)
    return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
