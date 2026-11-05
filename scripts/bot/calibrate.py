"""Calibration (plan P21, spec R55): what each difficulty level means, as a win rate.

  driver.py calibrate [--levels 0,4,8,12,16,20] [--pairings ruin/ruin,...] [--seeds 200]
                      [--bot tuned] [--ref greedy_v1]

Runs levels x pairings, `--seeds` paired seeds per cell, the bot at the level against the
reference at full strength. Pairs are scored and the interval taken by `records.aggregate`,
as `eval` does. Prints a Markdown table `level | pairing | winrate ± ci` and a tier
suggestion by win-rate band; progress goes to stderr.
"""
import argparse
import concurrent.futures
import datetime
import os
import sys
from typing import Any, Callable, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import driver  # noqa: E402
import records  # noqa: E402

DEFAULT_LEVELS = "0,4,8,12,16,20"
DEFAULT_PAIRINGS = "ruin/ruin,drift/drift,ruin/drift,bloom/bloom,echo/echo,bloom/echo"
DEFAULT_SEEDS = 200
# Win-rate bands: tier name -> target winrate; "hard" is the highest measured level.
EASY_TARGET = 0.35
NORMAL_TARGET = 0.50

Cell = Tuple[int, str]  # (level, pairing)
# factory(level, pairing, lo, hi, out) -> argv; runner(argv) -> (exit code, output tail)
CellFactory = Callable[[int, str, int, int, str], List[str]]
Runner = Callable[[List[str]], Tuple[int, str]]
Results = Dict[Cell, Dict[str, Any]]  # cell -> records.aggregate output


def parse_levels(text: str) -> List[int]:
    levels = [int(x) for x in text.split(",") if x.strip() != ""]
    if not levels or any(lv < 0 or lv > 20 for lv in levels):
        raise ValueError("bad levels %r (whole numbers 0..20)" % text)
    return levels


def parse_pairings(text: str) -> List[str]:
    pairings = [x.strip() for x in text.split(",") if x.strip() != ""]
    for p in pairings:
        ids = p.split("/")
        if len(ids) != 2 or not ids[0] or not ids[1]:
            raise ValueError("bad pairing %r (want <deck>/<deck>)" % p)
    if not pairings:
        raise ValueError("no pairings")
    return pairings


def level_rates(results: Results) -> Dict[int, float]:
    """Each level's win rate: the mean of its cells' rates."""
    by_level: Dict[int, List[float]] = {}
    for (level, _), agg in results.items():
        by_level.setdefault(level, []).append(float(agg["winrate"]))
    return {lv: sum(v) / len(v) for lv, v in by_level.items()}


def suggest_tiers(rates: Dict[int, float]) -> Dict[str, Tuple[int, float]]:
    """tier -> (level, rate): easy and normal are the levels nearest their target rates,
    hard is the level with the highest rate (the highest level on a tie)."""
    if not rates:
        return {}
    nearest = lambda target: min(  # noqa: E731
        sorted(rates), key=lambda lv: (abs(rates[lv] - target), lv))
    hard = max(sorted(rates), key=lambda lv: (rates[lv], lv))
    out = {"easy": nearest(EASY_TARGET), "normal": nearest(NORMAL_TARGET), "hard": hard}
    return {tier: (lv, rates[lv]) for tier, lv in out.items()}


def build_table(results: Results, bot: str = "tuned", ref: str = "greedy_v1") -> str:
    lines = ["| level | pairing | winrate ± ci | pairs |", "|---|---|---|---|"]
    for level, pairing in sorted(results):
        agg = results[(level, pairing)]
        lines.append("| %d | %s | %.3f ± %.3f | %d |"
                     % (level, pairing, agg["winrate"], agg["winrate_ci95"], agg["pairs"]))
    rates = level_rates(results)
    lines += ["", "Mean over pairings, `%s` at the level vs `%s`:" % (bot, ref), "",
              "| level | winrate |", "|---|---|"]
    lines += ["| %d | %.3f |" % (lv, rates[lv]) for lv in sorted(rates)]
    tiers = suggest_tiers(rates)
    lines += ["", "Tier suggestion (easy ≈ %.2f, normal ≈ %.2f, hard = the max):"
              % (EASY_TARGET, NORMAL_TARGET), ""]
    for tier in ("easy", "normal", "hard"):
        if tier in tiers:
            lines.append("- %s: level %d (winrate %.3f)" % (tier, tiers[tier][0], tiers[tier][1]))
    return "\n".join(lines)


def run_cells(cells: List[Cell], lo: int, hi: int, factory: CellFactory, out_dir: str,
              workers: int, runner: Runner = driver.run_worker) -> Tuple[Results, List[str]]:
    """Run every cell's batches on `workers` threads; (aggregates per cell, failures)."""
    jobs: List[Tuple[Cell, str, List[str]]] = []
    for level, pairing in cells:
        for s, e in driver.batches(lo, hi):
            name = "L%d-%s-%d-%d.jsonl" % (level, pairing.replace("/", "_"), s, e)
            out = os.path.join(out_dir, name)
            jobs.append(((level, pairing), out, factory(level, pairing, s, e, out)))
    recs: Dict[Cell, List[Dict[str, Any]]] = {c: [] for c in cells}
    failures: List[str] = []
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        futs = {pool.submit(runner, argv): (cell, out) for cell, out, argv in jobs}
        for fut in concurrent.futures.as_completed(futs):
            cell, out = futs[fut]
            code, tail = fut.result()
            done += 1
            print("bot-calibrate: %d/%d batches (level %d %s)"
                  % (done, len(jobs), cell[0], cell[1]), file=sys.stderr)
            if code != 0:
                failures.append("level %d %s %s exit %d: %s"
                                % (cell[0], cell[1], os.path.basename(out), code,
                                   tail.replace("\n", " | ")))
            else:
                recs[cell].extend(records.read_records(out))
    return {c: records.aggregate(r) for c, r in recs.items()}, failures


def run_calibrate(args: argparse.Namespace, factory: Optional[CellFactory] = None,
                  runner: Runner = driver.run_worker, workers: Optional[int] = None) -> int:
    try:
        levels = parse_levels(args.levels)
        pairings = parse_pairings(args.pairings)
        if args.seeds < 1:
            raise ValueError("--seeds must be at least 1")
    except ValueError as e:
        print("bot-calibrate: %s" % e, file=sys.stderr)
        return driver.EXIT_ERROR
    if factory is None:
        if not os.path.isfile(driver.godot_bin()):
            print("bot-calibrate: Godot not found at %s (set GODOT_BIN)" % driver.godot_bin(),
                  file=sys.stderr)
            return driver.EXIT_ERROR
        label = "calibrate-%s" % args.bot
        factory = lambda lv, pr, s, e, out: driver.godot_worker(  # noqa: E731
            args.bot, args.ref, s, e, out, label, decks=pr, level_a=lv)
    base = args.reports_dir or os.path.join(records.GODOT_DIR, "reports", "bot")
    stamp_day = datetime.date.today().isoformat()
    out_dir = os.path.join(base, "calibrate-%s-%s" % (args.bot, stamp_day))
    os.makedirs(out_dir, exist_ok=True)
    cells = [(lv, pr) for lv in levels for pr in pairings]
    results, failures = run_cells(cells, 1, args.seeds, factory, out_dir,
                                  workers or os.cpu_count() or 1, runner)
    if failures:
        for f in failures:
            print("bot-calibrate: " + f, file=sys.stderr)
        return driver.EXIT_ERROR
    print("Calibration: %s vs %s, %d seeds per cell, stamp %s\n"
          % (args.bot, args.ref, args.seeds, records.current_stamp()))
    print(build_table(results, args.bot, args.ref))
    return driver.EXIT_PASS


def add_calibrate_parser(sub: Any) -> None:
    p = sub.add_parser("calibrate", help="win rate by difficulty level and deck pairing")
    p.add_argument("--levels", default=DEFAULT_LEVELS, help="default %(default)s")
    p.add_argument("--pairings", default=DEFAULT_PAIRINGS,
                   help="deck pairs <id>/<id>, comma separated; default: the spec's three "
                   "(ruin/ruin, drift/drift, ruin/drift) plus bloom/bloom, echo/echo, "
                   "bloom/echo")
    p.add_argument("--seeds", type=int, default=DEFAULT_SEEDS, help="paired seeds per cell")
    p.add_argument("--bot", default="tuned")
    p.add_argument("--ref", default="greedy_v1")
    p.add_argument("--reports-dir", default="", help=argparse.SUPPRESS)
