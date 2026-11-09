import tempfile
import threading
import unittest
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from trainer import judge as J

LINE = ("bot-eval: a=linear b=%s result=%s bound=%s pairs=40 games=80 winrate=0.700±0.050 "
        "first_committer=0.50 p95_us=900 p99_us=1200 slowest_us=3000 overruns_a=0 "
        "overruns_b=0 stamp=match exit=%d")
CODES = {"PASS": (0, "H1"), "FAIL": (1, "H0"), "CAP": (2, "cap")}


def result_line(b: str, result: str) -> str:
    code, bound = CODES[result]
    return LINE % (b, result, bound, code)


class Stub:
    def __init__(self, results: List[str], stop: Optional[threading.Event] = None) -> None:
        self.results = list(results)
        self.calls: List[List[str]] = []
        self.env: List[Dict[str, str]] = []
        self.stop = stop

    def __call__(self, argv: List[str], cwd: Path, env: Dict[str, str],
                 timeout: float) -> Tuple[int, str]:
        self.calls.append(argv)
        self.env.append(env)
        if self.stop is not None:
            self.stop.set()
        res = self.results.pop(0)
        if res == "ERROR":
            return 1, "Traceback: boom\n"
        if res == "TIMEOUT":
            raise TimeoutError("slow")
        b = argv[argv.index("--b") + 1]
        return CODES[res][0], "noise\n" + result_line(b, res) + "\n"


def make(results: List[str], stop: Optional[threading.Event] = None) -> Tuple[J.Judge, Stub]:
    stub = Stub(results, stop)
    cfg = J.JudgeConfig(cap=50, timeout_s=5, worktree=Path("."), godot_bin="/g/godot",
                        python="py")
    return J.Judge(cfg, stub), stub


class JudgeTest(unittest.TestCase):
    def test_pass_pass(self) -> None:
        jd, stub = make(["PASS", "PASS"])
        r = jd.judge("/f.json", "/c.json")
        self.assertTrue(r.passed)
        self.assertEqual((r.outcome_random, r.outcome_champion), ("pass", "pass"))
        self.assertIn("b=linear", r.line_champion)
        self.assertEqual(stub.calls[0][:3], ["py", "-I", "scripts/bot/driver.py"])
        self.assertIn("--gainer", stub.calls[0])
        self.assertEqual(stub.calls[1][stub.calls[1].index("--weights-b") + 1], "/c.json")
        self.assertEqual(stub.env[0]["GODOT_BIN"], "/g/godot")

    def test_fail_vs_champion_keeps(self) -> None:
        r = make(["PASS", "FAIL"])[0].judge("/f", "/c")
        self.assertFalse(r.passed)
        self.assertEqual(r.outcome_champion, "fail")

    def test_cap_keeps(self) -> None:
        r = make(["CAP"])[0].judge("/f", "/c")
        self.assertFalse(r.passed)
        self.assertEqual((r.outcome_random, r.outcome_champion), ("cap", "skipped"))

    def test_error_no_raise(self) -> None:
        for bad in ("ERROR", "TIMEOUT"):
            r = make([bad])[0].judge("/f", None)
            self.assertFalse(r.passed)
            self.assertEqual(r.outcome_random, "error")
            self.assertEqual(r.line_random, "")

    def test_no_champion_one_game(self) -> None:
        jd, stub = make(["PASS"])
        r = jd.judge("/f", None)
        self.assertTrue(r.passed)
        self.assertEqual(len(stub.calls), 1)
        self.assertEqual(r.outcome_champion, "skipped")

    def test_stop_between_games(self) -> None:
        ev = threading.Event()
        jd, stub = make(["PASS", "PASS"], ev)
        r = jd.judge("/f", "/c", ev)
        self.assertTrue(r.stopped)
        self.assertFalse(r.passed)
        self.assertEqual(len(stub.calls), 1)
        self.assertEqual(r.outcome_champion, "skipped")


class ChampionTest(unittest.TestCase):
    def test_save_load_clear(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            self.assertIsNone(J.load_champion(p))
            J.save_champion(p, "fit1", "st", "fs1", "a", "b", 3)
            c = J.load_champion(p)
            assert c is not None
            self.assertEqual((c["fit_id"], c["block"]), ("fit1", 3))
            self.assertEqual(J.champion_for(p, "fs1")[1], "")
            J.clear_champion(p)
            self.assertIsNone(J.load_champion(p))

    def test_feature_set_change_drops(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            J.save_champion(p, "fit1", "st", "fsA", "a", "", 1)
            c, note = J.champion_for(p, "fsB")
            self.assertIsNone(c)
            self.assertEqual(note, "champion fit1 dropped: feature set fsA differs from fsB")
            self.assertIsNone(J.load_champion(p))
            self.assertTrue((p / "autopilot" / "champion.dropped-st.json").exists())


if __name__ == "__main__":
    unittest.main()
