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


LEDGER_MIN = ("---\ntype: planning\nupdated: 2026-01-01\n---\n\n# Bot ladder\n\n## Ledger\n\n"
              "| a |\n\n## Rerun after an engine change\n\ntext\n")


class LedgerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.path = os.path.join(self.tmp, "ladder.md")
        with open(self.path, "w", encoding="utf-8") as f:
            f.write(LEDGER_MIN)

    def read(self) -> str:
        with open(self.path, "r", encoding="utf-8") as f:
            return f.read()

    def test_section_created_before_rerun_and_replaced_on_each_run(self) -> None:
        calibrate.update_ledger(self.path, "FIRST RUN", "2026-11-05")
        first = self.read()
        self.assertEqual(first.count(calibrate.SECTION), 1)
        self.assertLess(first.index(calibrate.SECTION), first.index("## Rerun after"))
        self.assertIn("%s\n\nFIRST RUN\n\n%s" % (calibrate.BEGIN_MARK, calibrate.END_MARK),
                      first)
        self.assertIn("updated: 2026-11-05", first)
        calibrate.update_ledger(self.path, "SECOND RUN", "2026-11-06")
        second = self.read()
        self.assertNotIn("FIRST RUN", second)
        self.assertIn("SECOND RUN", second)
        self.assertEqual(second.count(calibrate.BEGIN_MARK), 1)
        self.assertEqual(second.count(calibrate.SECTION), 1)
        self.assertTrue(second.endswith("text\n"))

    def test_heading_without_markers_gets_them(self) -> None:
        with open(self.path, "w", encoding="utf-8") as f:
            f.write(LEDGER_MIN.replace("## Rerun", "## Calibration\n\nnotes\n\n## Rerun"))
        calibrate.update_ledger(self.path, "BLOCK", "2026-11-05")
        text = self.read()
        self.assertEqual(text.count("## Calibration"), 1)
        self.assertIn("%s\n\nBLOCK\n\n%s" % (calibrate.BEGIN_MARK, calibrate.END_MARK), text)

    def test_run_writes_ledger_with_stamp_seeds_and_tiers(self) -> None:
        args = argparse.Namespace(levels="0,20", pairings="ruin/ruin", seeds=30, bot="tuned",
                                  ref="greedy_v1", reports_dir=self.tmp, no_ledger=False,
                                  ledger=self.path)
        factory = lambda lv, pr, s, e, out: [str(lv), pr, str(s), str(e), out]  # noqa: E731

        def runner(argv: List[str]) -> Tuple[int, str]:
            with open(argv[4], "w", encoding="utf-8") as f:
                for seed in range(int(argv[2]), int(argv[3]) + 1):
                    pts = 2.0 if int(argv[0]) >= 10 else 0.0
                    f.write(json.dumps({"t": "p", "seed": seed, "points_a": pts}) + "\n")
            return 0, ""
        self.assertEqual(calibrate.run_calibrate(args, factory, runner, 2), driver.EXIT_PASS)
        text = self.read()
        self.assertIn("30 paired seeds per cell", text)
        self.assertIn(records.current_stamp(), text)
        self.assertIn("- hard: level 20 (winrate 1.000)", text)
        self.assertIn("| 20 | ruin/ruin | 1.000 ± 0.000 | 30 |", text)

    def test_no_ledger_flag_leaves_the_file_alone(self) -> None:
        args = argparse.Namespace(levels="0", pairings="ruin/ruin", seeds=2, bot="tuned",
                                  ref="greedy_v1", reports_dir=self.tmp, no_ledger=True,
                                  ledger=self.path)
        factory = lambda lv, pr, s, e, out: [out]  # noqa: E731

        def runner(argv: List[str]) -> Tuple[int, str]:
            with open(argv[0], "w", encoding="utf-8") as f:
                f.write(json.dumps({"t": "p", "seed": 1, "points_a": 1.0}) + "\n")
            return 0, ""
        self.assertEqual(calibrate.run_calibrate(args, factory, runner, 1), driver.EXIT_PASS)
        self.assertEqual(self.read(), LEDGER_MIN)

    def test_parser_has_the_flag(self) -> None:
        a = driver.build_parser().parse_args(["calibrate", "--no-ledger"])
        self.assertTrue(a.no_ledger)
        self.assertFalse(driver.build_parser().parse_args(["calibrate"]).no_ledger)


class StampNoteTest(unittest.TestCase):
    def test_mismatch_and_match(self) -> None:
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        with open(os.path.join(tmp, "tuned_weights.json"), "w", encoding="utf-8") as f:
            json.dump({"stamp": "r1-0000000000000000", "weights": {}}, f)
        note = calibrate.stamp_note("tuned", "r5-aaaaaaaaaaaaaaaa", tmp)
        self.assertIn("MISMATCH", note)
        self.assertTrue(note.startswith("r5-aaaaaaaaaaaaaaaa"))
        self.assertEqual(calibrate.stamp_note("tuned", "r1-0000000000000000", tmp),
                         "r1-0000000000000000")
        self.assertEqual(calibrate.stamp_note("nope", "r5-x", tmp), "r5-x")

    def test_table_ends_with_the_stamp_note(self) -> None:
        res = {(0, "ruin/ruin"): agg([1.0, 1.0])}
        table = calibrate.build_table(res, stamp="r5-x MISMATCH (...)")
        self.assertTrue(table.endswith("Stamp: r5-x MISMATCH (...)"))


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
                                  ref="greedy_v1", reports_dir=tmp, no_ledger=True, ledger="")
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
