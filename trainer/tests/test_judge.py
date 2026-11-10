import os
import tempfile
import threading
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from unittest import mock

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
        self.timeouts: List[float] = []
        self.stop = stop
        self.on_call: Any = None

    def __call__(self, argv: List[str], cwd: Path, env: Dict[str, str],
                 timeout: float) -> Tuple[int, str]:
        self.calls.append(argv)
        self.env.append(env)
        self.timeouts.append(timeout)
        if self.on_call is not None:
            self.on_call()
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


class FakeProc:
    def __init__(self, done_after: int) -> None:
        self.done_after = done_after
        self.polls = 0
        self.terminated = False
        self.returncode: Optional[int] = None

    def poll(self) -> Optional[int]:
        if self.returncode is not None:
            return self.returncode
        self.polls += 1
        if self.polls > self.done_after:
            self.returncode = 0
        return self.returncode

    def terminate(self) -> None:
        self.terminated = True
        self.returncode = -15

    def kill(self) -> None:
        self.returncode = -9

    def wait(self, timeout: Optional[float] = None) -> int:
        return int(self.returncode or 0)


class RunnerTest(unittest.TestCase):
    def run_it(self, proc: FakeProc, stop: Optional[threading.Event], timeout: float = 100.0,
               clock_step: float = 1.0) -> Tuple[int, str]:
        t = [0.0]

        def clock() -> float:
            return t[0]

        def sleep(s: float) -> None:
            t[0] += clock_step

        def popen(argv: List[str], **kw: Any) -> FakeProc:
            kw["stdout"].write("hello\n")
            return proc

        return J.default_runner(["x"], Path("."), {}, timeout, stop, popen, clock, sleep)

    def test_finishes(self) -> None:
        code, out = self.run_it(FakeProc(3), None)
        self.assertEqual((code, out), (0, "hello\n"))

    def test_stop_terminates_the_subprocess(self) -> None:
        stop = threading.Event()
        proc = FakeProc(10 ** 6)
        orig = proc.poll

        def poll() -> Optional[int]:
            if proc.polls == 3:
                stop.set()
            return orig()

        proc.poll = poll  # type: ignore[method-assign]
        with self.assertRaises(J.GameStopped):
            self.run_it(proc, stop)
        self.assertTrue(proc.terminated)

    def test_timeout_terminates_the_subprocess(self) -> None:
        proc = FakeProc(10 ** 6)
        with self.assertRaises(TimeoutError):
            self.run_it(proc, None, timeout=5.0)
        self.assertTrue(proc.terminated)


class JudgeBoundTest(unittest.TestCase):
    def cfg(self, **kw: Any) -> J.JudgeConfig:
        return J.JudgeConfig(cap=50, timeout_s=3600, worktree=Path("."), python="py", **kw)

    def test_timeout_is_capped_by_the_budget(self) -> None:
        t = [0.0]
        stub = Stub(["PASS", "PASS"])
        stub.on_call = lambda: t.__setitem__(0, t[0] + 200.0)
        jd = J.Judge(self.cfg(), stub, clock=lambda: t[0])
        jd.judge("/f", "/c", None, 600.0)
        self.assertEqual(stub.timeouts, [600.0, 400.0])

    def test_timeout_floor_and_default(self) -> None:
        stub = Stub(["PASS"])
        J.Judge(self.cfg(), stub).judge("/f", None, None, 5.0)
        self.assertEqual(stub.timeouts, [J.MIN_GAME_S])
        stub = Stub(["PASS"])
        J.Judge(self.cfg(), stub).judge("/f", None)
        self.assertEqual(stub.timeouts, [3600])

    def test_reports_dir_and_unique_labels(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            stub = Stub(["PASS"] * 4)
            jd = J.Judge(self.cfg(reports_dir=d + "/judge"), stub)
            jd.judge("/data/fits/abc/weights.json", "/c")
            jd.judge("/data/fits/abc/weights.json", "/c")
            self.assertTrue(os.path.isdir(d + "/judge"))
        labels: List[str] = []
        for call in stub.calls:
            self.assertEqual(call[call.index("--reports-dir") + 1], d + "/judge")
            labels.append(call[call.index("--label") + 1])
        self.assertEqual(len(set(labels)), 4)
        self.assertEqual(labels[0], "abc-vs-random-1")

    def test_terminated_game_is_stopped_not_error(self) -> None:
        jd = J.Judge(self.cfg())
        with mock.patch.object(J, "default_runner", side_effect=J.GameStopped()):
            r = jd.judge("/f", "/c", threading.Event())
        self.assertTrue(r.stopped)
        self.assertFalse(r.passed)
        self.assertEqual(r.outcome_random, "skipped")


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

    def test_stamp_change_drops(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            J.save_champion(p, "fit1", "stA", "fs1", "a", "", 1)
            self.assertEqual(J.champion_for(p, "fs1", "stA")[1], "")
            c, note = J.champion_for(p, "fs1", "stB")
            self.assertIsNone(c)
            self.assertEqual(note, "champion fit1 dropped: stamp stA differs from stB")
            self.assertIsNone(J.load_champion(p))


if __name__ == "__main__":
    unittest.main()
