import unittest
from typing import Any, Callable, Dict, Optional

from trainer import knobs


class KnobsTest(unittest.TestCase):
    def check(self, plan: Any, last: Optional[Dict[str, Any]] = None,
              extras: Optional[Dict[str, Any]] = None,
              fit_ok: Optional[Callable[[str], bool]] = None) -> knobs.Validation:
        return knobs.validate(plan, last or knobs.plan_defaults(), knobs.default_bounds(),
                              extras or {}, fit_ok)

    def test_in_bounds(self) -> None:
        v = self.check({"positions": 2000, "l2": 0.01, "generator": "linear"})
        self.assertEqual((v.plan["positions"], v.plan["l2"], v.plan["generator"]),
                         (2000, 0.01, "linear"))
        self.assertEqual((v.trial, v.refused, v.notes), (None, [], []))

    def test_out_of_bounds_is_trial(self) -> None:
        v = self.check({"positions": 8000})
        self.assertEqual(v.trial, ("positions", 8000))
        self.assertEqual(v.plan["positions"], 1000)
        self.assertEqual(v.refused, [])

    def test_past_hard_limit_refused(self) -> None:
        for plan in ({"positions": 50000}, {"holdout": 0.5}, {"l2": 0}, {"workers": 17},
                     {"generator": "magic"}):
            v = self.check(plan)
            self.assertIsNone(v.trial, plan)
            self.assertEqual(len(v.refused), 1, plan)

    def test_unknown_and_wrong_type(self) -> None:
        v = self.check({"colour": 3, "k": 8.0, "workers": True})
        self.assertEqual([r["knob"] for r in v.refused], ["colour", "k", "workers"])
        self.assertEqual(v.refused[0]["reason"], "unknown knob")

    def test_two_out_of_bounds_one_trial(self) -> None:
        v = self.check({"positions": 8000, "k": 24})
        self.assertEqual(v.trial, ("positions", 8000))
        self.assertEqual(v.plan["k"], 8)
        self.assertEqual(len(v.notes), 1)

    def test_extras_accepted(self) -> None:
        v = self.check({"positions": 8000}, extras={"positions": [8000]})
        self.assertEqual((v.plan["positions"], v.trial), (8000, None))

    def test_missing_keep_last(self) -> None:
        last = knobs.plan_defaults()
        last["k"] = 12
        v = self.check({"positions": 700}, last=last)
        self.assertEqual((v.plan["k"], v.plan["positions"]), (12, 700))

    def test_fit_predicate(self) -> None:
        v = self.check({"rollout_weights": "f1"}, fit_ok=lambda s: False)
        self.assertEqual(v.refused[0]["knob"], "rollout_weights")
        v = self.check({"rollout_weights": "f1"}, fit_ok=lambda s: True)
        self.assertEqual(v.plan["rollout_weights"], "f1")
        v = self.check({"rollout_weights": "champion"})
        self.assertEqual(v.plan["rollout_weights"], "champion")

    def test_check_bounds(self) -> None:
        self.assertEqual(knobs.check_bounds(knobs.default_bounds()), [])
        self.assertEqual(knobs.check_bounds({"positions": [100, 20000]}), [])
        self.assertTrue(knobs.check_bounds({"positions": [50, 900]}))
        self.assertTrue(knobs.check_bounds({"k": [10, 4]}))
        self.assertTrue(knobs.check_bounds({"nope": [1, 2]}))
        self.assertTrue(knobs.check_bounds({"generator": ["random", "x"]}))
        self.assertTrue(knobs.check_bounds({"holdout": [0.1, 0.5]}))

    def test_fragments(self) -> None:
        p = knobs.plan_defaults()
        self.assertEqual(knobs.fit_fragment(p), {"l2": 1e-3, "iterations": 500, "holdout": 0.1})
        self.assertEqual(set(knobs.run_fragment(p)), set(knobs.RUN_KNOBS))


if __name__ == "__main__":
    unittest.main()
