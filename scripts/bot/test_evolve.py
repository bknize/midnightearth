import hashlib
import json
import os
import random
import shutil
import sys
import tempfile
import unittest
from typing import Any, Dict, List, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
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


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.weights = os.path.join(self.tmp, "weights")
        os.makedirs(self.weights)
        shutil.copy(TUNED, self.weights)
        self.lines: List[str] = []

    def trainer(self, evaluate: Any = passing, label: str = "t", **kw: Any) -> evolve.Trainer:
        kw.setdefault("hours", 1.0)
        cfg = evolve.Config(bot="tuned", label=label, run_seed=42, rr_seeds=3,
                            ref_seeds=4, reports_dir=os.path.join(self.tmp, "reports"),
                            workers=2, **kw)
        return evolve.Trainer(cfg, stub_play, evaluate, self.weights, self.lines.append)


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
