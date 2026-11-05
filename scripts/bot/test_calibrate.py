import argparse
import json
import os
import shutil
import sys
import tempfile
import unittest
from typing import Any, Dict, List, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import calibrate  # noqa: E402
import driver  # noqa: E402
import records  # noqa: E402

# Pair points of A (0..2) for fixture cells, by level.
PAIRS = {0: [0.0, 0.0, 1.0, 0.0], 10: [1.0, 1.0, 1.0, 1.0], 20: [2.0, 2.0, 1.0, 2.0]}


def agg(points: List[float]) -> Dict[str, Any]:
    return records.aggregate([{"t": "p", "points_a": p} for p in points])


class TableTest(unittest.TestCase):
    def results(self) -> Dict[Tuple[int, str], Dict[str, Any]]:
        return {(lv, pr): agg(PAIRS[lv]) for lv in PAIRS for pr in ("ruin/ruin", "ruin/drift")}

    def test_table_rows_and_intervals(self) -> None:
        table = calibrate.build_table(self.results())
        self.assertIn("| level | pairing | winrate ± ci | pairs |", table)
        self.assertIn("| 0 | ruin/ruin | 0.125 ± 0.", table)
        self.assertIn("| 10 | ruin/drift | 0.500 ± 0.000 | 4 |", table)
        self.assertIn("| 20 | ruin/ruin | 0.875 ± 0.", table)

    def test_band_mapping(self) -> None:
        rates = {0: 0.10, 4: 0.34, 8: 0.52, 12: 0.60, 20: 0.80}
        tiers = calibrate.suggest_tiers(rates)
        self.assertEqual(tiers["easy"][0], 4)
        self.assertEqual(tiers["normal"][0], 8)
        self.assertEqual(tiers["hard"], (20, 0.80))
        self.assertEqual(calibrate.suggest_tiers({}), {})

    def test_tier_lines_in_table(self) -> None:
        table = calibrate.build_table(self.results())
        self.assertIn("- normal: level 10 (winrate 0.500)", table)
        self.assertIn("- hard: level 20 (winrate 0.875)", table)

    def test_parsers(self) -> None:
        self.assertEqual(calibrate.parse_levels("0, 4,20"), [0, 4, 20])
        with self.assertRaises(ValueError):
            calibrate.parse_levels("21")
        self.assertEqual(len(calibrate.parse_pairings(calibrate.DEFAULT_PAIRINGS)), 6)
        with self.assertRaises(ValueError):
            calibrate.parse_pairings("ruin")


class RunTest(unittest.TestCase):
    def test_run_with_stub_workers(self) -> None:
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)

        def factory(level: int, pairing: str, lo: int, hi: int, out: str) -> List[str]:
            return [str(level), pairing, str(lo), str(hi), out]

        def runner(argv: List[str]) -> Tuple[int, str]:
            level, lo, hi = int(argv[0]), int(argv[2]), int(argv[3])
            with open(argv[4], "w", encoding="utf-8") as f:
                for seed in range(lo, hi + 1):
                    pts = 2.0 if level >= 10 else 0.0
                    f.write(json.dumps({"t": "p", "seed": seed, "points_a": pts}) + "\n")
            return 0, ""

        args = argparse.Namespace(levels="0,20", pairings="ruin/ruin", seeds=30, bot="tuned",
                                  ref="greedy_v1", reports_dir=tmp)
        results, failures = calibrate.run_cells(
            [(0, "ruin/ruin"), (20, "ruin/ruin")], 1, 30, factory, tmp, 2, runner)
        self.assertEqual(failures, [])
        self.assertEqual(results[(0, "ruin/ruin")]["pairs"], 30)
        self.assertEqual(results[(20, "ruin/ruin")]["winrate"], 1.0)
        self.assertEqual(calibrate.run_calibrate(args, factory, runner, 2), driver.EXIT_PASS)

    def test_worker_argv_fixes_pairing_and_level(self) -> None:
        argv = driver.godot_worker("tuned", "greedy_v1", 1, 25, "o", "l",
                                   decks="bloom/echo", level_a=8)
        self.assertIn("--decks=bloom/echo", argv)
        self.assertIn("--level-a=8", argv)


if __name__ == "__main__":
    unittest.main()
