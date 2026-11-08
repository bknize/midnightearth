import unittest

from trainer.config import FitConfig, RunConfig


class ConfigTest(unittest.TestCase):
    def test_defaults(self) -> None:
        c = RunConfig.from_dict({})
        self.assertEqual((c.positions, c.k, c.determinizations, c.workers, c.batch),
                         (2000, 8, 16, 16, 25))
        self.assertEqual((c.rollout, c.generator, c.decks, c.hours),
                         ("random", "random", "seeded", 8.0))

    def test_weights_fields(self) -> None:
        c = RunConfig.from_dict({})
        self.assertEqual((c.rollout_weights, c.generator_weights), ("", ""))
        c = RunConfig.from_dict({"rollout_weights": "f1", "generator_weights": "f2"})
        self.assertEqual(RunConfig.from_dict(c.to_dict()), c)
        self.assert_bad({"rollout_weights": 3}, "rollout_weights")
        self.assert_bad({"generator_weights": None}, "generator_weights")

    def test_round_trip(self) -> None:
        c = RunConfig.from_dict({"positions": 50, "run_seed": -7, "decks": "all_pairings"})
        self.assertEqual(RunConfig.from_dict(c.to_dict()), c)

    def assert_bad(self, data: object, field: str) -> None:
        with self.assertRaises(ValueError) as cm:
            RunConfig.from_dict(data)
        self.assertIn(field, str(cm.exception))

    def test_bad(self) -> None:
        self.assert_bad({"bogus": 1}, "bogus")
        self.assert_bad({"positions": "5"}, "positions")
        self.assert_bad({"positions": True}, "positions")
        self.assert_bad({"k": 0}, "k")
        self.assert_bad({"batch": -1}, "batch")
        self.assert_bad({"decks": "some"}, "decks")
        self.assert_bad({"rollout": ""}, "rollout")
        self.assert_bad({"hours": 0}, "hours")
        self.assert_bad({"run_seed": 1.5}, "run_seed")
        self.assert_bad({"run_seed": 1 << 63}, "run_seed")
        self.assert_bad([], "config")


class FitConfigTest(unittest.TestCase):
    def test_defaults_and_roundtrip(self) -> None:
        c = FitConfig.from_dict({"runs": ["a", "b"]})
        self.assertEqual((c.l2, c.iterations, c.holdout, c.seed, c.k),
                         (1e-3, 500, 0.1, 0, 64))
        self.assertEqual(FitConfig.from_dict(c.to_dict()), c)
        self.assertEqual(FitConfig.from_dict({"runs": ["a"], "l2": 0, "holdout": 0}).l2, 0.0)

    def test_bad_fields_are_named(self) -> None:
        bad = [({}, "runs"), ({"runs": []}, "runs"), ({"runs": ["a", "a"]}, "repeat"),
               ({"runs": [""]}, "runs"), ({"runs": ["a"], "l2": -1}, "l2"),
               ({"runs": ["a"], "l2": "x"}, "l2"),
               ({"runs": ["a"], "iterations": 0}, "iterations"),
               ({"runs": ["a"], "iterations": 1.5}, "iterations"),
               ({"runs": ["a"], "holdout": 0.5}, "holdout"),
               ({"runs": ["a"], "holdout": -0.1}, "holdout"),
               ({"runs": ["a"], "seed": True}, "seed"), ({"runs": ["a"], "k": 0}, "k"),
               ({"runs": ["a"], "zzz": 1}, "zzz"), ([], "config")]
        for data, text in bad:
            with self.assertRaises(ValueError) as ctx:
                FitConfig.from_dict(data)
            self.assertIn(text, str(ctx.exception), str(data))


if __name__ == "__main__":
    unittest.main()
