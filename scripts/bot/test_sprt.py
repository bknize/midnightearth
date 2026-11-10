import contextlib
import io
import os
import random
import sys
import tempfile
import unittest
from typing import Any, Dict, List, Tuple

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
        self.assertEqual(a["p99_us"], 2000)

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

    def test_batch_flag_sets_batch_size(self) -> None:
        args = driver.build_parser().parse_args(["eval", "--a", "x", "--b", "y"])
        self.assertEqual(args.batch, 25)
        args = driver.build_parser().parse_args(
            ["eval", "--a", "x", "--b", "y", "--batch", "10", "--seeds", "1-30"])
        self.assertEqual(args.batch, 10)
        self.assertEqual(driver.batches(1, 30, args.batch), [(1, 10), (11, 20), (21, 30)])

    def test_batch_flag_reaches_the_workers(self) -> None:
        seen: List[Tuple[int, int]] = []
        script = "import sys; open(sys.argv[1], 'w').write('')\n"
        with tempfile.TemporaryDirectory() as tmp:
            args = driver.build_parser().parse_args(
                ["eval", "--a", "x", "--b", "y", "--batch", "10", "--seeds", "1-30",
                 "--reports-dir", tmp])

            def factory(a: str, b: str, s: int, e: int, out: str) -> List[str]:
                seen.append((s, e))
                return [sys.executable, "-c", script, out]

            with contextlib.redirect_stdout(io.StringIO()):
                driver.run_eval(args, factory, workers=1)
        self.assertEqual(sorted(seen), [(1, 10), (11, 20), (21, 30)])

    def test_worker_argv(self) -> None:
        argv = driver.godot_worker("random", "random", 1, 25, "out.jsonl", "lbl")
        self.assertEqual(argv[1:], [
            "--headless", "--path", "godot", "-s", "res://tools/match_worker.gd", "--",
            "--a=random", "--b=random", "--seeds=1-25", "--decks=seeded",
            "--out=out.jsonl", "--label=lbl"])
        argv = driver.godot_worker("a", "b", 3, 4, "o", "l", "d1/d2", 5000)
        self.assertIn("--decks=d1/d2", argv)
        self.assertEqual(argv[-1], "--budget-us=5000")
        for arg in argv:
            self.assertNotIn("weights", arg)
            self.assertNotIn("level", arg)
        argv = driver.godot_worker("linear", "random", 1, 25, "o", "l",
                                   weights_a="/w/a.json", weights_b="/w/b.json")
        self.assertEqual(argv[-2:], ["--weights-a=/w/a.json", "--weights-b=/w/b.json"])
        argv = driver.godot_worker("linear", "random", 1, 25, "o", "l", weights_a="/w/a.json")
        self.assertEqual(argv[-1], "--weights-a=/w/a.json")
        self.assertFalse([a for a in argv if a.startswith("--weights-b")])

    def test_weights_flags_parse(self) -> None:
        args = driver.build_parser().parse_args(
            ["eval", "--a", "x", "--b", "y", "--weights-a", "a.json", "--weights-b", "b.json"])
        self.assertEqual((args.weights_a, args.weights_b), ("a.json", "b.json"))
        args = driver.build_parser().parse_args(["eval", "--a", "x", "--b", "y"])
        self.assertEqual((args.weights_a, args.weights_b), ("", ""))

    def test_godot_bin_env_accepts_windows_exe(self) -> None:
        exe = "C:\\Godot\\Godot_v4.6_win64.exe"
        old = os.environ.get("GODOT_BIN")
        os.environ["GODOT_BIN"] = exe
        try:
            self.assertEqual(driver.godot_worker("a", "b", 1, 2, "o", "l")[0], exe)
        finally:
            if old is None:
                del os.environ["GODOT_BIN"]
            else:
                os.environ["GODOT_BIN"] = old

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

    def gainer_run(self, us: int, rejected: int = 0, replay: int = 0,
                   overruns_a: int = 0, weights_stamp: str = "none",
                   engine_stamp: str = "") -> Tuple[int, str]:
        """A gainer eval over stub batches whose side-a decisions all take `us` microseconds."""
        script = ("import sys, json\n"
                  "us, rej, rep, ov = [int(x) for x in sys.argv[2:6]]\n"
                  "rows = [{'t': 'p', 'seed': i, 'decks': 'x', 'points_a': 1.5 if i % 2 else 1.0} "
                  "for i in range(25)]\n"
                  "rows.append({'t': 'g', 'seed': 0, 'game': 0, 'a_seat': 1})\n"
                  "rows += [{'t': 'd', 'seed': 0, 'game': 0, 'seat': 1, 'us': us}] * 100\n"
                  "rows += [{'t': 'd', 'seed': 0, 'game': 0, 'seat': 0, 'us': 99999}] * 100\n"
                  "rows.append({'t': 'end', 'games': 50, 'rejected': rej, 'overruns': ov, "
                  "'overruns_a': ov, 'overruns_b': 0, 'replay_mismatches': rep, "
                  "'stamp': sys.argv[6], 'weights_stamp': sys.argv[7]})\n"
                  "open(sys.argv[1], 'w').write('\\n'.join(json.dumps(r) for r in rows) + '\\n')\n")
        with tempfile.TemporaryDirectory() as tmp:
            args = driver.build_parser().parse_args(
                ["eval", "--a", "x", "--b", "y", "--gainer", "--seeds", "1-5000",
                 "--reports-dir", tmp])
            factory = lambda a, b, s, e, out: [  # noqa: E731
                sys.executable, "-c", script, out, str(us), str(rejected), str(replay),
                str(overruns_a), engine_stamp or records.current_stamp(), weights_stamp]
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = driver.run_eval(args, factory, workers=2)
        return code, out.getvalue()

    def test_gainer_p99_over_budget_is_printed_but_does_not_fail(self) -> None:
        # R41 follow-up (C16): the all-core eval only prints the p99; the trainer's quiet
        # sweep judges it
        code, text = self.gainer_run(us=10000, overruns_a=3)
        self.assertEqual(code, 0)
        self.assertIn("result=PASS", text)
        self.assertNotIn("reason=", text)
        self.assertIn("p99_us=10000", text)
        self.assertIn("overruns_a=3 overruns_b=0", text)

    def test_weights_stamp_none_and_match_print_match(self) -> None:
        for ws in ("none", "match"):
            code, text = self.gainer_run(us=2000, weights_stamp=ws)
            self.assertEqual(code, 0)
            self.assertIn("stamp=match exit=0", text)

    def test_weights_stamp_mismatch_prints_mismatch(self) -> None:
        code, text = self.gainer_run(us=2000, weights_stamp="MISMATCH")
        self.assertEqual(code, 0)
        self.assertIn("stamp=MISMATCH", text)

    def test_engine_stamp_inequality_errors_out(self) -> None:
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, _ = self.gainer_run(us=2000, engine_stamp="r4-0123456789abcdef")
        self.assertEqual(code, 3)
        self.assertIn("engine stamp", err.getvalue())

    def test_engine_stamp_mismatch_stops_at_the_first_batch(self) -> None:
        # a stale worker fails fast: the first batch's end record stops the eval, so no
        # second batch is started and no report is written
        script = ("import sys, json\n"
                  "rows = [{'t': 'p', 'seed': i, 'decks': 'x', 'points_a': 1.0} "
                  "for i in range(25)]\n"
                  "rows.append({'t': 'end', 'games': 50, 'rejected': 0, 'overruns': 0, "
                  "'replay_mismatches': 0, 'stamp': 'r4-0123456789abcdef'})\n"
                  "open(sys.argv[1], 'w').write('\\n'.join(json.dumps(r) for r in rows) + '\\n')\n")
        calls: List[Tuple[int, int]] = []

        def factory(a: str, b: str, s: int, e: int, out: str) -> List[str]:
            calls.append((s, e))
            return [sys.executable, "-c", script, out]

        with tempfile.TemporaryDirectory() as tmp:
            args = driver.build_parser().parse_args(
                ["eval", "--a", "x", "--b", "y", "--seeds", "1-5000", "--reports-dir", tmp])
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                code, report = driver.eval_report(args, factory, workers=1)
            reports = [r for r, _, f in os.walk(tmp) if "report.json" in f]
        self.assertEqual(code, driver.EXIT_ERROR)
        self.assertEqual(report, {})
        self.assertEqual(calls, [(1, 25)])
        self.assertEqual(reports, [])
        self.assertIn("engine stamp r4-0123456789abcdef differs", err.getvalue())
        self.assertEqual(driver.batch_stamp_mismatch(
            [{"t": "end", "stamp": records.current_stamp()}, {"t": "p"}],
            records.current_stamp()), "")

    def test_gainer_overruns_alone_do_not_block(self) -> None:
        code, text = self.gainer_run(us=2000, overruns_a=300)
        self.assertEqual(code, 0)
        self.assertIn("result=PASS", text)
        self.assertIn("p99_us=2000", text)
        self.assertIn("overruns_a=300", text)
        self.assertNotIn("reason=", text)

    def test_gainer_rejected_or_replay_cannot_pass(self) -> None:
        code, text = self.gainer_run(us=2000, rejected=1)
        self.assertEqual(code, 1)
        self.assertIn("reason=rejected", text)
        code, text = self.gainer_run(us=2000, replay=2)
        self.assertEqual(code, 1)
        self.assertIn("reason=replay", text)

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



class StoppingRuleTest(unittest.TestCase):
    """R28: the driver stops at the pair that decides the test, not at the batch's end."""

    def test_feed_stops_at_the_deciding_pair(self) -> None:
        recs = [{"t": "p", "seed": i, "points_a": 1.0} for i in range(1, 121)]
        recs += [{"t": "g", "seed": 50, "game": 0}, {"t": "g", "seed": 120, "game": 0},
                 {"t": "end", "overruns_a": 2}]
        test = sprt.Sprt("nonreg")
        kept = driver.feed_until_decided(test, recs)
        self.assertEqual(test.pairs, 100)
        self.assertEqual(test.result(), "PASS")
        agg = records.aggregate(kept)
        self.assertEqual((agg["pairs"], agg["games"], agg["overruns_a"]), (100, 1, 2))


    def test_second_pair_of_an_undecided_seed_is_dropped(self) -> None:
        """B-37: seed 100 has two pairs (decks swapped); the first decides the test, so
        the second pair's p record, games 2 and 3 and their decisions leave the aggregates."""
        recs: List[Dict[str, Any]] = [{"t": "p", "seed": i, "points_a": 1.0}
                                      for i in range(1, 100)]
        recs.append({"t": "p", "seed": 100, "points_a": 1.0})
        recs.append({"t": "p", "seed": 100, "points_a": 1.0})
        for game in range(4):
            recs.append({"t": "g", "seed": 100, "game": game, "a_seat": game % 2,
                         "first_won": True})
            recs.append({"t": "d", "seed": 100, "game": game, "seat": game % 2,
                         "us": 100 if game < 2 else 9000})
        recs.append({"t": "end", "overruns_a": 1})
        test = sprt.Sprt("nonreg")
        kept = driver.feed_until_decided(test, recs)
        self.assertEqual(test.pairs, 100)
        agg = records.aggregate(kept)
        self.assertEqual((agg["pairs"], agg["games"]), (100, 2))
        self.assertEqual((agg["slowest_us"], agg["overruns_a"]), (100, 1))
        self.assertEqual([r["game"] for r in kept if r["t"] == "d"], [0, 1])


class IdenticalBotsTest(unittest.TestCase):
    """Identical deterministic bots split every pair 1-1: zero raw variance."""

    def test_nonreg_passes_and_gainer_fails(self):
        nonreg = sprt.Sprt("nonreg")
        gainer = sprt.Sprt("gainer")
        for _ in range(99):
            nonreg.add(1.0)
            gainer.add(1.0)
        self.assertIsNone(nonreg.state())
        nonreg.add(1.0)
        gainer.add(1.0)
        self.assertEqual(nonreg.result(), "PASS")
        self.assertEqual(gainer.result(), "FAIL")


if __name__ == "__main__":
    unittest.main()
