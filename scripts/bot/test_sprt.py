import contextlib
import io
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import driver  # noqa: E402
import records  # noqa: E402
import sprt  # noqa: E402

FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


def simulate(p: float, mode: str, seed: int, cap: int = 20000) -> sprt.Sprt:
    """Pairs of two independent games, each won with probability p."""
    rng = random.Random(seed)
    t = sprt.Sprt(mode, cap)
    while not t.decided():
        t.add(float((rng.random() < p) + (rng.random() < p)))
    return t


class SprtTest(unittest.TestCase):
    def rate(self, p: float, mode: str, state: str) -> int:
        """Count of seeds 1-20 whose run ends on `state` within the cap."""
        return sum(simulate(p, mode, s).state() == state for s in range(1, 21))

    def test_gainer_054_passes_rate(self) -> None:
        # 0.54 is about +28 Elo, just above the upper bound of [0, 25].
        n = self.rate(0.54, "gainer", "H1")
        self.assertGreaterEqual(n, 18, "passed on %d of 20" % n)

    def test_gainer_050_fails_rate(self) -> None:
        n = self.rate(0.50, "gainer", "H0")
        self.assertGreaterEqual(n, 18, "accepted H0 on %d of 20" % n)

    def test_nonreg_050_passes_rate(self) -> None:
        n = self.rate(0.50, "nonreg", "H1")
        self.assertGreaterEqual(n, 18, "passed on %d of 20" % n)

    def test_strong_gainer_passes_on_any_seed(self) -> None:
        for seed in range(5):
            self.assertEqual(simulate(0.56, "gainer", seed).result(), "PASS")

    def test_nonreg_equal_passes_and_worse_fails(self) -> None:
        self.assertEqual(simulate(0.50, "nonreg", 1).result(), "PASS")
        self.assertEqual(simulate(0.44, "nonreg", 1).result(), "FAIL")

    def test_cap(self) -> None:
        t = sprt.Sprt("gainer", 3)
        for pts in (1.0, 1.0, 1.0):
            t.add(pts)
        self.assertEqual(t.state(), "CAP")
        self.assertEqual(t.result(), "CAP")

    def test_bad_points(self) -> None:
        with self.assertRaises(ValueError):
            sprt.Sprt().add(0.25)

    def test_bounds(self) -> None:
        lo, hi = sprt.llr_bounds()
        self.assertAlmostEqual(lo, -2.9444, places=3)
        self.assertAlmostEqual(hi, 2.9444, places=3)


class RecordsTest(unittest.TestCase):
    def test_stamp_shape(self) -> None:
        stamp = records.current_stamp()
        self.assertRegex(stamp, r"^r\d+-[0-9a-f]{16}$")
        self.assertEqual(stamp.split("-")[0], "r%d" % records.rules_version())

    def test_fixture_aggregates(self) -> None:
        a = records.aggregate(records.read_records(os.path.join(FIX, "a.jsonl")))
        self.assertEqual((a["pairs"], a["games"]), (3, 6))
        self.assertAlmostEqual(a["winrate"], 3.5 / 6.0)
        self.assertAlmostEqual(a["first_committer"], 4 / 6.0)
        self.assertEqual((a["p95_us"], a["slowest_us"]), (1900, 2000))

    def test_fixture_merge(self) -> None:
        recs = records.merge([os.path.join(FIX, "a.jsonl"), os.path.join(FIX, "b.jsonl")])
        g = records.aggregate(recs)
        self.assertEqual((g["pairs"], g["games"]), (4, 8))
        self.assertAlmostEqual(g["winrate"], 0.625)
        self.assertAlmostEqual(g["winrate_ci95"], 0.3163, places=4)
        self.assertAlmostEqual(g["first_committer"], 0.5)
        self.assertEqual((g["p95_us"], g["slowest_us"]), (2000, 3000))
        self.assertEqual((g["rejected"], g["overruns"], g["replay_mismatches"]), (1, 2, 3))
        self.assertEqual((g["overruns_a"], g["overruns_b"]), (0, 0))
        self.assertEqual(g["stamps"], ["r4-0123456789abcdef"])


class DriverTest(unittest.TestCase):
    def test_batches(self) -> None:
        self.assertEqual(driver.batches(1, 60), [(1, 25), (26, 50), (51, 60)])

    def test_failing_worker_exits_3_naming_range(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            args = driver.build_parser().parse_args(
                ["eval", "--a", "x", "--b", "y", "--seeds", "1-50", "--reports-dir", tmp])
            factory = lambda a, b, s, e, out: [sys.executable, "-c", "import sys; sys.exit(1)"]  # noqa: E731
            err = tempfile.TemporaryFile("w+")
            old = sys.stderr
            sys.stderr = err
            try:
                code = driver.run_eval(args, factory, workers=2)
            finally:
                sys.stderr = old
            err.seek(0)
            text = err.read()
        self.assertEqual(code, 3)
        self.assertIn("seeds 1-25 exit 1", text)

    def test_gainer_with_overruns_a_cannot_pass(self) -> None:
        script = ("import sys, json\n"
                  "rows = [{'t': 'p', 'seed': i, 'decks': 'x', 'points_a': 1.5 if i % 2 else 1.0} "
                  "for i in range(25)]\n"
                  "rows.append({'t': 'end', 'games': 50, 'rejected': 0, 'overruns': 3, "
                  "'overruns_a': 3, 'overruns_b': 0, 'replay_mismatches': 0, 'p95_us': 1, "
                  "'slowest_us': 1, 'stamp': 'r4-0123456789abcdef'})\n"
                  "open(sys.argv[1], 'w').write('\\n'.join(json.dumps(r) for r in rows) + '\\n')\n")
        with tempfile.TemporaryDirectory() as tmp:
            args = driver.build_parser().parse_args(
                ["eval", "--a", "x", "--b", "y", "--gainer", "--seeds", "1-5000",
                 "--reports-dir", tmp])
            factory = lambda a, b, s, e, out: [sys.executable, "-c", script, out]  # noqa: E731
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = driver.run_eval(args, factory, workers=2)
        self.assertEqual(code, 1)
        self.assertIn("result=FAIL", out.getvalue())
        self.assertIn("reason=overrun", out.getvalue())
        self.assertIn("overruns_a=3 overruns_b=0", out.getvalue())

    def test_fake_worker_pass(self) -> None:
        """A worker that writes 25 pair records of 1.5 points reaches H1."""
        script = ("import sys, json\n"
                  "out = sys.argv[1]\n"
                  "open(out, 'w').write('\\n'.join(json.dumps({'t': 'p', 'seed': i, "
                  "'decks': 'x', 'points_a': 1.5 if i % 2 else 1.0}) for i in range(25)) "
                  "+ '\\n')\n")
        with tempfile.TemporaryDirectory() as tmp:
            args = driver.build_parser().parse_args(
                ["eval", "--a", "x", "--b", "y", "--seeds", "1-5000", "--reports-dir", tmp])
            factory = lambda a, b, s, e, out: [sys.executable, "-c", script, out]  # noqa: E731
            code = driver.run_eval(args, factory, workers=2)
            reports = [os.path.join(r, "report.json") for r, _, f in os.walk(tmp)
                       if "report.json" in f]
        self.assertEqual(code, 0)
        self.assertEqual(len(reports), 1)


if __name__ == "__main__":
    unittest.main()
