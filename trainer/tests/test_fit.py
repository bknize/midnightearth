import json
import os
import random
import re
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List

from trainer.config import FitConfig
from trainer import fit as fit_module
from trainer.fit import (FitError, engine_feature_names, run_fit, validate_runs,
                         weights_text)
from trainer.sync import stamp_of
from trainer.store import Store

try:
    import numpy  # noqa: F401
    HAVE_NUMPY = True
except ImportError:
    HAVE_NUMPY = False

ROOT = Path(__file__).resolve().parent.parent.parent
STAMP = "r7-synthetic"
SET = "syn-1"
WIDTH = 12
TRUE = [5, -3, 0, 2, 0, 0, -1, 4, 0, 1, 0, -2]
NAMES = ["f%d" % i for i in range(WIDTH)]


def make_run(store: Store, run_id: str, seed: int, positions: int = 300, stamp: str = STAMP,
             feature_set: str = SET, state: str = "done") -> None:
    """A finished run whose candidate values are the true score (TRUE . features) plus a
    little noise, rounded (so some candidates tie), and some positions all-tied."""
    rng = random.Random(seed)
    store.create_run({"positions": positions, "run_seed": seed}, stamp, "c", run_id=run_id,
                     state=state)
    store.set_feature_set(run_id, feature_set)
    pos: List[Dict[str, Any]] = []
    labs: List[Dict[str, Any]] = []
    for i in range(positions):
        pos.append({"index": i, "seed": i, "decks": ["a", "b"], "prefix_len": 3, "seat": i % 2})
        decided = i % 10 == 0  # a decided position: every candidate the same value
        for c in range(6):
            feats = [rng.randint(0, 4) for _ in range(WIDTH)]
            score = sum(t * f for t, f in zip(TRUE, feats)) + rng.gauss(0, 0.1)
            mean = 0.5 if decided else min(1.0, max(0.0, round(0.5 + score * 0.01, 3)))
            labs.append({"position_index": i, "candidate_index": c, "action": {"c": c},
                         "mean": mean, "spread": 0.1, "n": 16, "wins": 8, "draws": 0,
                         "losses": 8, "capped": False, "features": feats})
    store.commit_batch(run_id, 0, pos, labs)


class ValidationTest(unittest.TestCase):
    """No numpy needed: the refusals happen before any array is built."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.store = Store(Path(self._tmp.name))
        self.addCleanup(self.store.close)

    def test_shared_stamp_and_feature_set_are_returned(self) -> None:
        make_run(self.store, "a", 1, positions=4)
        make_run(self.store, "b", 2, positions=4, state="stopped")
        self.assertEqual(validate_runs(self.store, ["a", "b"]), (STAMP, SET))

    def test_refusals_name_the_run(self) -> None:
        make_run(self.store, "a", 1, positions=4)
        make_run(self.store, "live", 2, positions=4, state="running")
        make_run(self.store, "other", 3, positions=4, stamp="r7-other")
        make_run(self.store, "set2", 4, positions=4, feature_set="syn-2")
        cases = [(["nope"], "no such run: nope"), (["a", "live"], "run live is running"),
                 (["a", "other"], "run other is under stamp"),
                 (["a", "set2"], "run set2 has feature set"), ([], "no runs")]
        for ids, text in cases:
            with self.assertRaises(FitError) as ctx:
                validate_runs(self.store, ids)
            self.assertIn(text, str(ctx.exception))

    def test_run_without_a_feature_set_is_refused(self) -> None:
        make_run(self.store, "old", 1, positions=4, feature_set="")
        with self.assertRaises(FitError) as ctx:
            validate_runs(self.store, ["old"])
        self.assertIn("old", str(ctx.exception))


class NamesTest(unittest.TestCase):
    def test_engine_names_match_the_committed_weights_file(self) -> None:
        names = engine_feature_names(ROOT, "f1")
        self.assertEqual(names[:2], ["pass", "committed_count"])
        self.assertEqual(names[32], "budget_diff")
        self.assertTrue(names[33].startswith("card:"))
        self.assertEqual(len(set(names)), len(names))
        committed = json.loads((ROOT / "godot" / "engine" / "bot" / "data"
                                / "linear_weights.json").read_text(encoding="utf-8"))
        self.assertTrue(set(committed["weights"]) <= set(names))

    def test_other_feature_set_is_refused(self) -> None:
        with self.assertRaises(FitError):
            engine_feature_names(ROOT, "f0")

    def test_weight_scale_mirrors_the_loaders_limit(self) -> None:
        gd = (ROOT / "godot" / "engine" / "bot" / "bot_weights.gd").read_text(encoding="utf-8")
        found = re.search(r"^const MAX_WEIGHT: int = (\d+)", gd, re.M)
        self.assertIsNotNone(found)
        self.assertEqual(fit_module.WEIGHT_SCALE, int(found.group(1)) if found else -1)

    def test_checkout_stamp_must_equal_the_runs(self) -> None:
        names = engine_feature_names(ROOT, "f1", stamp_of(ROOT))
        self.assertEqual(names, engine_feature_names(ROOT, "f1"))
        with self.assertRaises(FitError) as ctx:
            engine_feature_names(ROOT, "f1", "r7-other")
        self.assertIn("code stamp", str(ctx.exception))

    def test_blas_is_pinned_to_one_thread_before_numpy_loads(self) -> None:
        if HAVE_NUMPY:
            self.skipTest("numpy is installed; the pin is covered by the first import")
        for var in fit_module.BLAS_THREAD_VARS:
            os.environ.pop(var, None)
        with self.assertRaises(FitError):  # numpy missing, but the pin comes first
            fit_module._numpy()
        for var in fit_module.BLAS_THREAD_VARS:
            self.assertEqual(os.environ[var], "1")
        self.assertTrue(fit_module.BLAS_PINNED)

    def test_missing_numpy_is_a_clear_error(self) -> None:
        if HAVE_NUMPY:
            self.skipTest("numpy is installed")
        with tempfile.TemporaryDirectory() as d:
            store = Store(Path(d))
            try:
                make_run(store, "a", 1, positions=4)
                with self.assertRaises(FitError) as ctx:
                    run_fit(store, "x", FitConfig(runs=["a"]), Path(d) / "out", ROOT,
                            names=NAMES)
                self.assertEqual(str(ctx.exception), "numpy missing")
            finally:
                store.close()


@unittest.skipUnless(HAVE_NUMPY, "numpy is not installed")
class LearnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        self.store = Store(self.dir / "data")
        self.addCleanup(self.store.close)
        make_run(self.store, "a", 1)

    def fit(self, out: str, **over: Any) -> Dict[str, Any]:
        cfg = FitConfig(runs=["a"], seed=3, **over)
        return run_fit(self.store, "fit1", cfg, self.dir / out, ROOT, names=NAMES)

    def test_recovers_the_true_ranking(self) -> None:
        report = self.fit("out")
        self.assertGreater(report["agreement"]["heldout"], 0.95)
        self.assertGreater(report["agreement"]["heldout_quantized"], 0.95)
        self.assertGreater(report["agreement"]["fitted"], 0.95)
        self.assertGreater(report["pairs"]["heldout"], 0)
        self.assertEqual(report["pairs"]["total"],
                         report["pairs"]["fitted"] + report["pairs"]["heldout"])
        self.assertLess(report["paired_positions"], report["positions"])  # decided drop out
        doc = json.loads((self.dir / "out" / "linear_weights.json").read_text(encoding="utf-8"))
        weights = doc["weights"]
        for index in sorted(range(WIDTH), key=lambda i: -abs(TRUE[i]))[:4]:
            self.assertEqual(weights[NAMES[index]] > 0, TRUE[index] > 0, NAMES[index])
        self.assertEqual(max(abs(v) for v in weights.values()),
                         fit_module.WEIGHT_SCALE)
        self.assertTrue(all(isinstance(v, int) for v in weights.values()))
        top = report["top_weights"]
        self.assertLessEqual(len(top), 10)
        self.assertIn(NAMES[0], [t["name"] for t in top][:3])  # TRUE[0] is the largest

    def test_weights_file_has_the_godot_shape(self) -> None:
        self.fit("out", k=16)
        doc = json.loads((self.dir / "out" / "linear_weights.json").read_text(encoding="utf-8"))
        self.assertEqual(doc["version"], 2)
        self.assertEqual((doc["bot"], doc["stamp"], doc["features"], doc["k"]),
                         ("linear", STAMP, SET, 16))
        self.assertEqual(doc["fit"]["id"], "fit1")
        self.assertEqual(doc["fit"]["runs"], ["a"])
        self.assertEqual(len(doc["fit"]["digest"]), 64)
        self.assertTrue(set(doc["weights"]) <= set(NAMES))
        self.assertTrue(all(abs(v) <= 1000000 for v in doc["weights"].values()))

    def test_same_config_gives_byte_equal_files(self) -> None:
        self.fit("one")
        self.fit("two")
        for name in ("linear_weights.json", "report.json"):
            self.assertEqual((self.dir / "one" / name).read_bytes(),
                             (self.dir / "two" / name).read_bytes(), name)

    def test_no_holdout_reports_none(self) -> None:
        report = self.fit("out", holdout=0.0)
        self.assertEqual(report["pairs"]["heldout"], 0)
        self.assertIsNone(report["agreement"]["heldout"])

    def test_a_run_under_another_stamp_is_refused(self) -> None:
        make_run(self.store, "b", 2, positions=20, stamp="r7-other")
        cfg = FitConfig(runs=["a", "b"])
        with self.assertRaises(FitError):
            run_fit(self.store, "fit1", cfg, self.dir / "out", ROOT, names=NAMES)
        self.assertFalse((self.dir / "out").exists())

    def test_all_decided_positions_leave_no_pairs(self) -> None:
        self.store.db.execute("UPDATE labels SET mean = 0.5")
        self.store.db.commit()
        with self.assertRaises(FitError) as ctx:
            self.fit("out")
        self.assertIn("no pairs", str(ctx.exception))

    def test_wrong_name_count_and_stop(self) -> None:
        cfg = FitConfig(runs=["a"])
        with self.assertRaises(FitError):
            run_fit(self.store, "f", cfg, self.dir / "o", ROOT, names=NAMES[:-1])
        with self.assertRaises(FitError) as ctx:
            run_fit(self.store, "f", cfg, self.dir / "o", ROOT, names=NAMES,
                    should_stop=lambda: True)
        self.assertIn("stopped", str(ctx.exception))

    def test_checkout_under_another_stamp_is_refused(self) -> None:
        # The runs' stamp (r7-synthetic) is not the checkout's: the names read from the
        # checkout would misname the weights, so the fit stops before writing anything.
        cfg = FitConfig(runs=["a"])
        with self.assertRaises(FitError) as ctx:
            run_fit(self.store, "fit1", cfg, self.dir / "out", ROOT)
        self.assertIn("code stamp", str(ctx.exception))
        self.assertFalse((self.dir / "out").exists())

    def test_two_runs_are_learned_together(self) -> None:
        make_run(self.store, "b", 2, positions=100)
        cfg = FitConfig(runs=["b", "a"], seed=3)
        report = run_fit(self.store, "fit1", cfg, self.dir / "two", ROOT, names=NAMES)
        self.assertEqual(report["runs"], ["a", "b"])
        self.assertEqual(report["positions"], 400)


class WeightsTextTest(unittest.TestCase):
    def test_weights_follow_feature_order(self) -> None:
        doc = {"version": 2, "weights": {"b": 1, "a": 2}}
        text = weights_text(doc, ["a", "b"])
        self.assertLess(text.index('"a"'), text.index('"b"'))
        self.assertTrue(text.endswith("\n"))


if __name__ == "__main__":
    unittest.main()
