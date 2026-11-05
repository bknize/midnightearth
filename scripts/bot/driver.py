#!/usr/bin/env python3
"""Bot strength driver (plan P18): fans out workers, decides by SPRT. No model tokens.

  driver.py eval --a tuned --b greedy_v1 [--gainer|--nonreg] [--seeds 1-5000]
                 [--cap 20000] [--label L]
  driver.py selftest
  driver.py train | calibrate        (milestone B: not yet implemented, exit 3)

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


def godot_worker(a: str, b: str, lo: int, hi: int, out: str, label: str) -> List[str]:
    cmd = [godot_bin(), "--headless", "--path", "godot", "-s", "res://tools/bot_worker.gd",
           "--", "--a=%s" % a, "--b=%s" % b, "--seeds=%d-%d" % (lo, hi),
           "--decks=seeded", "--out=%s" % out, "--label=%s" % label]
    for flag, bot in (("--weights-a=", a), ("--weights-b=", b)):
        w = weights_path(bot)
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


def run_eval(args: argparse.Namespace,
             factory: Optional[WorkerFactory] = None,
             workers: Optional[int] = None) -> int:
    try:
        lo, hi = parse_seeds(args.seeds)
    except ValueError as e:
        print("bot-eval: %s" % e, file=sys.stderr)
        return EXIT_ERROR
    mode = "gainer" if args.gainer else "nonreg"
    label = args.label or "%s-vs-%s" % (args.a, args.b)
    if factory is None:
        if not os.path.isfile(godot_bin()):
            print("bot-eval: Godot not found at %s (set GODOT_BIN)" % godot_bin(),
                  file=sys.stderr)
            return EXIT_ERROR
        factory = lambda a, b, s, e, out: godot_worker(a, b, s, e, out, label)  # noqa: E731
    stamp = records.current_stamp()
    mismatch = False
    for bot in (args.a, args.b):
        ws = records.weights_stamp(bot)
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
    failures: List[str] = []
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
                    failures.append("worker seeds %d-%d exit %d: %s"
                                    % (s, e, code, tail.replace("\n", " | ")))
                    if os.path.exists(out):
                        os.remove(out)  # discard the partial batch (R31)
                else:
                    done[i] = out
            while not failures and next_feed in done and not test.decided():
                path = done[next_feed]
                fed.append(path)
                for r in records.read_records(path):
                    if r.get("t") == "p":
                        test.add(float(r["points_a"]))
                next_feed += 1
    if failures:
        for f in failures:
            print("bot-eval: " + f, file=sys.stderr)
        return EXIT_ERROR

    recs = records.merge(fed)
    agg = records.aggregate(recs)
    state = test.state()
    result = {"H1": "PASS", "H0": "FAIL"}.get(state or "", "CAP")
    bound = state if state in ("H0", "H1") else "cap"
    code = {"PASS": EXIT_PASS, "FAIL": EXIT_FAIL, "CAP": EXIT_CAP}[result]
    if mismatch or any(s != stamp for s in agg["stamps"]):
        mismatch = True
    if agg["rejected"] or agg["overruns"] or agg["replay_mismatches"]:
        print("bot-eval: invariant counts rejected=%d overruns=%d replay_mismatches=%d"
              % (agg["rejected"], agg["overruns"], agg["replay_mismatches"]), file=sys.stderr)
    summary = ("bot-eval: a=%s b=%s result=%s bound=%s pairs=%d games=%d "
               "winrate=%.3f±%.3f first_committer=%.2f p95_us=%d slowest_us=%d "
               "stamp=%s exit=%d"
               % (args.a, args.b, result, bound, agg["pairs"], agg["games"], agg["winrate"],
                  agg["winrate_ci95"], agg["first_committer"], agg["p95_us"],
                  agg["slowest_us"], "MISMATCH" if mismatch else "match", code))
    report = {"a": args.a, "b": args.b, "mode": mode, "label": label, "seeds": args.seeds,
              "cap": args.cap, "result": result, "bound": bound, "llr": test.llr(),
              "pentanomial": test.counts, "stamp": stamp, "stamp_mismatch": mismatch,
              "aggregates": agg, "batches": [os.path.basename(p) for p in fed],
              "summary": summary, "exit": code}
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, sort_keys=True)
    print(summary)
    return code


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
    sub.add_parser("selftest", help="run the unit tests")
    sub.add_parser("train", help="not yet implemented (milestone B)")
    sub.add_parser("calibrate", help="not yet implemented (milestone B)")
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
