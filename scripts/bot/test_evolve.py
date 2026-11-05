import hashlib
import json
import os
import random
import shutil
import sys
import tempfile
import unittest
from unittest import mock
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import driver  # noqa: E402
import evolve  # noqa: E402
import records  # noqa: E402

FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
TUNED = os.path.join(records.WEIGHTS_DIR, "tuned_weights.json")


def read(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def strength(path: str) -> float:
    doc = read(path)
    return doc["weights"].get("score_diff", 0) + 3.0 * doc["k"]


def stub_play(a_path: str, b_path: str, lo: int, hi: int, out: str) -> List[float]:
    """Deterministic pair points from the two files' contents and the seeds."""
    sa = strength(a_path)
    sb = strength(b_path) if b_path else 100.0
    out_points = []
    for seed in range(lo, hi + 1):
        rng = random.Random(seed * 7919 + int(sa * 10) - int(sb * 10))
        p = 1.0 / (1.0 + 10.0 ** (-(sa - sb) / 400.0))
        out_points.append(float((rng.random() < p) + (rng.random() < p)))
    return out_points


def passing(reference: str, path: str, gen: int) -> Tuple[int, str]:
    return 0, "pairs=10 winrate=0.600±0.100"


def quiet(path: str, gen: int) -> Tuple[bool, Optional[int], str]:
    return True, 7000, "exit 0"


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.weights = os.path.join(self.tmp, "weights")
        os.makedirs(self.weights)
        shutil.copy(TUNED, self.weights)
        self.lines: List[str] = []

    def trainer(self, evaluate: Any = passing, label: str = "t", sweep: Any = quiet,
                **kw: Any) -> evolve.Trainer:
        kw.setdefault("hours", 1.0)
        cfg = evolve.Config(bot="tuned", label=label, run_seed=42, rr_seeds=3,
                            ref_seeds=4, reports_dir=os.path.join(self.tmp, "reports"),
                            workers=2, **kw)
        return evolve.Trainer(cfg, stub_play, evaluate, self.weights, self.lines.append,
                              sweep=sweep)


class GenerationTest(Base):
    def test_generation_of_16_is_reproducible(self) -> None:
        cks = []
        for name in ("one", "two"):
            self.setUp()
            tr = self.trainer(lambda r, p, g: (1, "x"), label=name, max_generations=1)
            self.assertEqual(tr.run(), evolve.EXIT_NONE)
            ck = read(os.path.join(tr.run_dir, "gen-1.json"))
            ck.pop("elapsed_s")
            cks.append(ck)
        self.assertEqual(cks[0]["evaluated"], 16)
        self.assertEqual(len(cks[0]["population"]), 8)
        self.assertEqual(cks[0]["run_seed"], 42)
        cks[1]["label"] = cks[0]["label"]
        self.assertEqual(cks[0], cks[1])

    def test_different_run_seed_differs(self) -> None:
        tr = self.trainer(lambda r, p, g: (1, "x"), max_generations=1)
        tr.run()
        a = read(os.path.join(tr.run_dir, "gen-1.json"))
        tr2 = self.trainer(lambda r, p, g: (1, "x"), label="other", max_generations=1)
        tr2.cfg.run_seed = 43
        tr2.run()
        b = read(os.path.join(tr2.run_dir, "gen-1.json"))
        self.assertNotEqual(a["population"], b["population"])


class BoundsTest(unittest.TestCase):
    def check(self, bot: str, path: str, k_max: int) -> None:
        bounds = evolve.bounds_for(bot, k_max=k_max, k_opp_max=7)
        base = evolve.genome_of(read(path), bounds, 300)
        rng = random.Random(5)
        pop = evolve.initial_parents(base, 8, rng, 500.0, 30.0, bounds, 300)
        for _ in range(30):
            pop = evolve.make_offspring(pop, 8, rng, 500.0, 30.0, bounds, 300)
            for g in pop:
                self.assertLessEqual(g["ints"]["k"], k_max)
                self.assertGreaterEqual(g["ints"]["k"], 1)
                for name, (lo, hi) in bounds.items():
                    self.assertTrue(lo <= g["ints"][name] <= hi)
                self.assertEqual(sorted(g["weights"]), sorted(base["weights"]))
                for v in g["weights"].values():
                    self.assertTrue(-300 <= v <= 300)

    def test_tuned_within_bounds(self) -> None:
        self.check("tuned", TUNED, 24)

    def test_matrix_stub_within_bounds(self) -> None:
        self.check("matrix", os.path.join(FIX, "matrix_weights.json"), 12)

    def test_matrix_caps_are_c16(self) -> None:
        self.assertEqual(evolve.bounds_for("matrix"), {"k": (1, 6), "k_opp": (1, 3)})
        # the CLI overrides can only lower a cap, never raise it
        self.assertEqual(evolve.bounds_for("matrix", 12, 12), {"k": (1, 6), "k_opp": (1, 3)})
        self.assertEqual(evolve.bounds_for("matrix", 3, 2), {"k": (1, 3), "k_opp": (1, 2)})
        self.assertEqual(evolve.bounds_for("tuned", 48), {"k": (1, 24)})

    def test_matrix_defaults_are_c16(self) -> None:
        d = evolve.default_doc("matrix")
        self.assertEqual((d["k"], d["k_opp"], d["samples"], d["rm_iterations"]), (6, 3, 2, 50))
        fix = read(os.path.join(FIX, "matrix_weights.json"))
        self.assertEqual((fix["k"], fix["k_opp"], fix["samples"], fix["rm_iterations"]),
                         (6, 3, 2, 50))
        doc = evolve.genome_doc({}, evolve.genome_of({"weights": {"score_diff": 1}},
                                                     evolve.bounds_for("matrix"), 300, "matrix"),
                                "matrix", "r5-x")
        self.assertEqual((doc["k"], doc["k_opp"], doc["samples"], doc["rm_iterations"]),
                         (6, 3, 2, 50))

    def test_unknown_bot_refused(self) -> None:
        with self.assertRaises(evolve.TrainError):
            evolve.bounds_for("nope")


class ResumeTest(Base):
    def test_resume_continues_at_generation_4(self) -> None:
        first = self.trainer(lambda r, p, g: (1, "x"), max_generations=3)
        first.run()
        run_dir = first.run_dir
        for n in (1, 2, 3):
            self.assertTrue(os.path.isfile(os.path.join(run_dir, "gen-%d.json" % n)))
        self.assertFalse(os.path.exists(os.path.join(run_dir, "gen-4.json")))
        gen3 = read(os.path.join(run_dir, "gen-3.json"))
        second = self.trainer(lambda r, p, g: (1, "x"), max_generations=4)
        second.cfg.run_seed = None
        second.run()
        self.assertTrue(any("continuing at generation 4" in s for s in self.lines))
        gen4 = read(os.path.join(run_dir, "gen-4.json"))
        self.assertEqual(gen4["generation"], 4)
        self.assertEqual(gen4["run_seed"], 42)
        self.assertEqual(read(os.path.join(run_dir, "gen-3.json")), gen3)

    def test_wrong_run_seed_refused(self) -> None:
        self.trainer(lambda r, p, g: (1, "x"), max_generations=1).run()
        again = self.trainer(max_generations=2)
        again.cfg.run_seed = 99
        with self.assertRaises(evolve.TrainError):
            again.run()


class LabelAndPendingTest(Base):
    def test_default_label_carries_the_stamp_and_resumes_unfinished(self) -> None:
        stamp = records.current_stamp()
        first = self.trainer(lambda r, p, g: (1, "x"), label="", max_generations=1)
        self.assertEqual(first.label, "tuned-%s" % stamp)
        first.run()
        again = self.trainer(lambda r, p, g: (1, "x"), label="", max_generations=2)
        self.assertEqual(again.label, first.label)
        again.run()
        self.assertTrue(os.path.isfile(os.path.join(again.run_dir, "gen-2.json")))

    def test_default_label_after_promotion_starts_a_fresh_run(self) -> None:
        first = self.trainer(passing, label="", max_generations=1)
        self.assertEqual(first.run(), evolve.EXIT_PROMOTED)
        second = self.trainer(passing, label="", max_generations=1)
        self.assertEqual(second.label, first.label + "-2")
        self.assertEqual(second.run(), evolve.EXIT_PROMOTED)
        self.assertTrue(os.path.isfile(os.path.join(second.run_dir, "gen-1.json")))

    def test_checkpoint_of_another_stamp_refused(self) -> None:
        first = self.trainer(lambda r, p, g: (1, "x"), max_generations=1)
        first.run()
        path = os.path.join(first.run_dir, "gen-1.json")
        ck = read(path)
        ck["stamp"] = "r1-0000000000000000"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(ck, f)
        again = self.trainer(lambda r, p, g: (1, "x"), max_generations=2)
        with self.assertRaises(evolve.TrainError) as ctx:
            again.run()
        self.assertIn("new LABEL", str(ctx.exception))
        # the default label of the new stamp does not meet the old run at all
        self.assertNotEqual(self.trainer(label="").label, "tuned-r1-0000000000000000")

    def test_interrupted_promotion_is_rerun_on_resume(self) -> None:
        def boom(reference: str, path: str, gen: int) -> Tuple[int, str]:
            raise evolve.TrainError("eval crashed")
        first = self.trainer(boom, max_generations=1)
        with self.assertRaises(evolve.TrainError):
            first.run()
        ck = read(os.path.join(first.run_dir, "gen-1.json"))
        self.assertEqual(ck["pending"]["generation"], 1)
        pending = ck["pending"]["genome"]
        seen: List[str] = []

        def ok(reference: str, path: str, gen: int) -> Tuple[int, str]:
            seen.append("%s@%d" % (reference, gen))
            return 0, "pairs=10 winrate=0.600±0.100"
        second = self.trainer(ok, max_generations=1)
        self.assertEqual(second.run(), evolve.EXIT_PROMOTED)
        self.assertEqual(seen, ["greedy_v1@1", "best@1"])  # before any new generation
        self.assertFalse(os.path.exists(os.path.join(second.run_dir, "gen-2.json")))
        done = read(os.path.join(second.run_dir, "gen-1.json"))
        self.assertTrue(done["promoted"])
        self.assertIsNone(done["pending"])
        new = read(os.path.join(self.weights, "tuned_weights.json"))
        self.assertEqual(new["weights"], pending["weights"])
        self.assertTrue(any("pending promotion of gen=1" in s for s in self.lines))

    def test_pending_failing_again_goes_on_to_evolve(self) -> None:
        def boom(reference: str, path: str, gen: int) -> Tuple[int, str]:
            raise evolve.TrainError("eval crashed")
        with self.assertRaises(evolve.TrainError):
            self.trainer(boom, max_generations=1).run()
        second = self.trainer(lambda r, p, g: (1, "x"), max_generations=2)
        self.assertEqual(second.run(), evolve.EXIT_NONE)
        self.assertIsNone(read(os.path.join(second.run_dir, "gen-1.json"))["pending"])
        self.assertTrue(os.path.isfile(os.path.join(second.run_dir, "gen-2.json")))


class EvaluateFaultTest(unittest.TestCase):
    def evaluate(self, codes: List[int]) -> Tuple[int, str]:
        cfg = evolve.Config(bot="tuned")
        fn = evolve.make_godot_evaluate(cfg, "/nowhere", lambda: 1)
        with mock.patch.object(driver, "eval_report",
                               return_value=(driver.EXIT_ERROR, {"worker_exit_codes": codes})):
            return fn("greedy_v1", "/x.json", 1)

    def test_rejected_action_is_a_candidate_fail(self) -> None:
        code, info = self.evaluate([1])
        self.assertEqual(code, driver.EXIT_FAIL)
        self.assertIn("REJECTED", info)

    def test_infrastructure_error_aborts(self) -> None:
        for codes in ([2], [1, 3], [127], []):
            with self.assertRaises(evolve.TrainError):
                self.evaluate(codes)

    def test_candidate_fail_continues_the_run(self) -> None:
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        weights = os.path.join(tmp, "w")
        os.makedirs(weights)
        shutil.copy(TUNED, weights)
        cfg = evolve.Config(bot="tuned", label="f", run_seed=3, rr_seeds=2, ref_seeds=2,
                            hours=1.0, workers=2, max_generations=2,
                            reports_dir=os.path.join(tmp, "r"))
        lines: List[str] = []
        tr = evolve.Trainer(cfg, stub_play, evolve.make_godot_evaluate(cfg, tmp, lambda: 3),
                            weights, lines.append)
        with mock.patch.object(driver, "eval_report",
                               return_value=(driver.EXIT_ERROR, {"worker_exit_codes": [1]})):
            self.assertEqual(tr.run(), evolve.EXIT_NONE)
        self.assertTrue(os.path.isfile(os.path.join(tr.run_dir, "gen-2.json")))


class StampMismatchTest(Base):
    def test_summary_lines_repeat_the_mismatch(self) -> None:
        path = os.path.join(self.weights, "tuned_weights.json")
        doc = read(path)
        doc["stamp"] = "r1-0000000000000000"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(doc, f)
        tr = self.trainer(lambda r, p, g: (1, "x"), max_generations=1)
        tr.run()
        self.assertIn("differs from current", self.lines[0])
        self.assertIn("stamp=%s MISMATCH" % records.current_stamp(), self.lines[-1])

    def test_promoted_summary_repeats_the_mismatch(self) -> None:
        path = os.path.join(self.weights, "tuned_weights.json")
        doc = read(path)
        doc["stamp"] = "r1-0000000000000000"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(doc, f)
        self.trainer(passing, max_generations=1).run()
        self.assertTrue(any(s.startswith("bot-train: PROMOTED") and "MISMATCH" in s
                            for s in self.lines))

    def test_no_mismatch_note_when_stamps_agree(self) -> None:
        doc = read(os.path.join(self.weights, "tuned_weights.json"))
        doc["stamp"] = records.current_stamp()
        with open(os.path.join(self.weights, "tuned_weights.json"), "w", encoding="utf-8") as f:
            json.dump(doc, f)
        self.trainer(lambda r, p, g: (1, "x"), max_generations=1).run()
        self.assertNotIn("MISMATCH", self.lines[-1])


class PromotionTest(Base):
    def run_with(self, results: Dict[str, int]) -> Tuple[int, evolve.Trainer, Dict[str, Any]]:
        def evaluate(reference: str, path: str, gen: int) -> Tuple[int, str]:
            return results[reference], "pairs=10 winrate=0.600±0.100"
        tr = self.trainer(evaluate, max_generations=1)
        code = tr.run()
        return code, tr, read(os.path.join(tr.run_dir, "gen-1.json"))

    def test_refused_when_vs_greedy_fails(self) -> None:
        before = read(TUNED)
        code, tr, ck = self.run_with({"greedy_v1": 1, "best": 0})
        self.assertEqual(code, evolve.EXIT_NONE)
        self.assertEqual(read(os.path.join(self.weights, "tuned_weights.json")), before)
        self.assertFalse(ck["promoted"])
        self.assertFalse(any(s.startswith("bot-train: PROMOTED") for s in self.lines))
        self.assertTrue(any("NOT PROMOTED" in s for s in self.lines))

    def test_refused_when_vs_best_fails(self) -> None:
        before = read(TUNED)
        code, tr, ck = self.run_with({"greedy_v1": 0, "best": 2})
        self.assertEqual(code, evolve.EXIT_NONE)
        self.assertEqual(read(os.path.join(self.weights, "tuned_weights.json")), before)
        self.assertFalse(ck["promoted"])

    def test_time_limit_still_runs_one_generation(self) -> None:
        tr = self.trainer(lambda r, p, g: (1, "x"), hours=0.0)
        self.assertEqual(tr.run(), evolve.EXIT_NONE)
        self.assertTrue(os.path.isfile(os.path.join(tr.run_dir, "gen-1.json")))
        self.assertFalse(os.path.exists(os.path.join(tr.run_dir, "gen-2.json")))

    def test_both_pass_writes_weights_and_keeps_previous(self) -> None:
        before = read(TUNED)
        code, tr, ck = self.run_with({"greedy_v1": 0, "best": 0})
        self.assertEqual(code, evolve.EXIT_PROMOTED)
        self.assertTrue(ck["promoted"])
        new = read(os.path.join(self.weights, "tuned_weights.json"))
        self.assertEqual(new["stamp"], records.current_stamp())
        self.assertEqual(new["bot"], "tuned")
        self.assertLessEqual(new["k"], 24)
        self.assertEqual(read(os.path.join(tr.run_dir, "previous_tuned_weights.json")), before)
        self.assertTrue(any(s.startswith("bot-train: PROMOTED gen=1 stamp=") for s in self.lines))


class QuietSweepTest(Base):
    def run_sweep(self, result: Tuple[bool, Optional[int], str], gens: int = 1,
                  **kw: Any) -> Tuple[int, evolve.Trainer, List[str]]:
        seen: List[str] = []

        def sweep(path: str, gen: int) -> Tuple[bool, Optional[int], str]:
            seen.append(path)
            return result
        tr = self.trainer(passing, sweep=sweep, max_generations=gens, **kw)
        return tr.run(), tr, seen

    def test_p99_over_budget_is_not_promoted_and_the_run_continues(self) -> None:
        before = read(TUNED)
        code, tr, seen = self.run_sweep((True, 12000, "exit 0"), gens=2)
        self.assertEqual(code, evolve.EXIT_NONE)
        self.assertEqual(read(os.path.join(self.weights, "tuned_weights.json")), before)
        ck = read(os.path.join(tr.run_dir, "gen-1.json"))
        self.assertFalse(ck["promoted"])
        self.assertEqual(ck["candidate"]["quiet_sweep"]["reason"], "p99")
        self.assertEqual(ck["candidate"]["quiet_sweep"]["p99_us"], 12000)
        self.assertTrue(os.path.isfile(os.path.join(tr.run_dir, "gen-2.json")))
        self.assertTrue(all(p.endswith(".json") and os.path.isabs(p) for p in seen))
        self.assertTrue(any("quiet sweep FAIL reason=p99" in s for s in self.lines))
        self.assertIn("quiet_sweep=FAIL(p99_us=", self.lines[-1])

    def test_p99_under_budget_is_promoted(self) -> None:
        code, tr, seen = self.run_sweep((True, 8000, "exit 0"))
        self.assertEqual(code, evolve.EXIT_PROMOTED)
        ck = read(os.path.join(tr.run_dir, "gen-1.json"))
        self.assertTrue(ck["promoted"])
        self.assertEqual(ck["candidate"]["quiet_sweep"],
                         {"passed": True, "p99_us": 8000, "info": "exit 0", "reason": ""})
        self.assertEqual(len(seen), 1)
        self.assertTrue(any("quiet_sweep=PASS(p99_us=8000)" in s for s in self.lines))

    def test_p99_exactly_at_budget_is_not_promoted(self) -> None:
        code, tr, _ = self.run_sweep((True, 10000, "exit 0"))
        self.assertEqual(code, evolve.EXIT_NONE)

    def test_other_sweep_failure_is_reason_sweep(self) -> None:
        code, tr, _ = self.run_sweep((False, None, "exit 100: invariant"))
        self.assertEqual(code, evolve.EXIT_NONE)
        ck = read(os.path.join(tr.run_dir, "gen-1.json"))
        self.assertEqual(ck["candidate"]["quiet_sweep"]["reason"], "sweep")

    def test_failed_sweep_with_slow_p99_is_reason_p99(self) -> None:
        code, tr, _ = self.run_sweep((False, 15000, "exit 100"))
        ck = read(os.path.join(tr.run_dir, "gen-1.json"))
        self.assertEqual(ck["candidate"]["quiet_sweep"]["reason"], "p99")

    def test_sweep_is_skipped_when_a_gainer_test_fails(self) -> None:
        seen: List[str] = []

        def sweep(path: str, gen: int) -> Tuple[bool, Optional[int], str]:
            seen.append(path)
            return True, 1, ""
        self.trainer(lambda r, p, g: (1, "x"), sweep=sweep, max_generations=1).run()
        self.assertEqual(seen, [])

    def test_pending_candidate_reruns_the_sweep_on_resume(self) -> None:
        def boom(path: str, gen: int) -> Tuple[bool, Optional[int], str]:
            raise evolve.TrainError("sweep crashed")
        with self.assertRaises(evolve.TrainError):
            self.trainer(passing, sweep=boom, max_generations=1).run()
        seen: List[str] = []

        def sweep(path: str, gen: int) -> Tuple[bool, Optional[int], str]:
            seen.append(path)
            return True, 8000, "exit 0"
        second = self.trainer(passing, sweep=sweep, max_generations=1)
        self.assertEqual(second.run(), evolve.EXIT_PROMOTED)
        self.assertEqual(len(seen), 1)

    def test_parse_sweep_p99(self) -> None:
        line = ("check: sweep: Sweep: longest=300 seed=4 slowest_us=900 bot=tuned p95_us=3000 "
                "p99_us=7123 stamp=match weights=/x/y.json")
        self.assertEqual(evolve.parse_sweep_p99(line), 7123)
        self.assertIsNone(evolve.parse_sweep_p99("Sweep pairing a/b: seeds=3"))


class MatrixStubTest(Base):
    def test_matrix_run_uses_its_own_file_and_caps(self) -> None:
        shutil.copy(os.path.join(FIX, "matrix_weights.json"), self.weights)
        cfg = evolve.Config(bot="matrix", hours=0.0, label="m", run_seed=1, rr_seeds=2,
                            ref_seeds=2, reports_dir=os.path.join(self.tmp, "reports"),
                            workers=2, max_generations=1)
        tr = evolve.Trainer(cfg, stub_play, lambda r, p, g: (1, "x"), self.weights,
                            self.lines.append)
        self.assertEqual(tr.run(), evolve.EXIT_NONE)
        ck = read(os.path.join(tr.run_dir, "gen-1.json"))
        for p in ck["population"]:
            self.assertIn("k_opp", p["genome"]["ints"])
            self.assertIn("own_score", p["genome"]["weights"])


class DeriveTest(unittest.TestCase):
    def test_stable_and_distinct(self) -> None:
        self.assertEqual(evolve.derive(1, "rr", 2), evolve.derive(1, "rr", 2))
        self.assertNotEqual(evolve.derive(1, "rr", 2), evolve.derive(1, "ref", 2))
        self.assertEqual(hashlib.sha256(b"1|rr|2").digest()[:8],
                         evolve.derive(1, "rr", 2).to_bytes(8, "big"))


if __name__ == "__main__":
    unittest.main()
