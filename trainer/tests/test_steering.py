import json
import shutil
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

from trainer import knobs, steering
from trainer.autopilot import Autopilot
from trainer.tests.test_autopilot import (CFG, Advice, FakeAdvisor, FakeClock, FakeJudge,
                                          FakeService)


class RecordingAdvisor(FakeAdvisor):
    def __init__(self) -> None:
        super().__init__()
        self.args: List[Dict[str, Any]] = []

    def advise(self, block: int, entries: List[Dict[str, Any]], bounds: Any, extras: Any,
               pins: Any, notes: Any, plateau: bool, last_plan: Any,
               has_champion: bool) -> Advice:
        self.args.append({"bounds": bounds, "pins": pins, "notes": list(notes)})
        return super().advise(block, entries, bounds, extras, pins, notes, plateau, last_plan,
                              has_champion)


class ParseCase(unittest.TestCase):
    def doc(self, **extra: Any) -> Dict[str, Any]:
        return {"approved_by": "Ben", "date": "2026-11-09", **extra}

    def test_narrow_and_widen_inside_hard_limit(self) -> None:
        s, problems = steering.parse_steering(
            self.doc(bounds={"positions": [100, 200], "k": [2, 32]}), knobs.default_bounds())
        self.assertEqual(problems, [])
        assert s is not None
        self.assertEqual(s.bounds["positions"], [100, 200])
        self.assertEqual(s.bounds["k"], [2, 32])
        self.assertEqual(s.bounds["workers"], [8, 16])  # merged over the current bounds

    def test_widen_past_hard_limit_refused(self) -> None:
        s, problems = steering.parse_steering(
            self.doc(bounds={"positions": [100, 99999]}), knobs.default_bounds())
        self.assertIsNone(s)
        self.assertIn("past the hard limit", problems[0])

    def test_missing_approval_and_unknown_key_refused(self) -> None:
        s, problems = steering.parse_steering({"bounds": {}, "extra": 1}, knobs.default_bounds())
        self.assertIsNone(s)
        self.assertEqual(len(problems), 2)

    def test_bad_pin_and_avoid_refused(self) -> None:
        s, problems = steering.parse_steering(
            self.doc(pin={"positions": 999999, "nope": 1}, avoid={"k": ["x"]}),
            knobs.default_bounds())
        self.assertIsNone(s)
        self.assertEqual(len(problems), 3)

    def test_inbox_path(self) -> None:
        self.assertEqual(steering.inbox_path("/x"), Path("/x/steering.json"))


class SteeringCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.inbox = self.tmp / "inbox"
        self.inbox.mkdir()
        self.clock = FakeClock()
        self.service = FakeService(self.clock, self.tmp)
        self.advisor = RecordingAdvisor()
        self.ap = Autopilot(self.service, self.advisor, FakeJudge(["pass"]), data_dir=self.tmp,
                            clock=self.clock.now, sleep=self.clock.sleep,
                            disk_free_gb=lambda: 100.0, feature_set_fn=lambda: "FS1",
                            inbox=self.inbox)
        self.ap._spawn = lambda: None  # type: ignore[method-assign]
        self.advisor.ap = self.ap

    def send(self, doc: Any) -> None:
        text = doc if isinstance(doc, str) else json.dumps(doc)
        (self.inbox / "steering.json").write_text(text)

    def run_blocks(self, n: int) -> List[Dict[str, Any]]:
        self.advisor.stop_after = n
        self.assertNotIn("error", self.ap.start(dict(CFG)))
        self.ap.run_loop()
        return self.ap.log.read()[0]

    def archive(self, name: str) -> Path:
        return self.tmp / "autopilot" / "steering" / name

    def valid(self, **extra: Any) -> Dict[str, Any]:
        return {"approved_by": "Ben", "date": "2026-11-09", **extra}

    def test_valid_file_archived_and_noted(self) -> None:
        self.send(self.valid(bounds={"positions": [500, 8000]}))
        es = self.run_blocks(2)
        self.assertTrue(self.archive("1.json").is_file())
        self.assertFalse((self.inbox / "steering.json").exists())
        self.assertEqual(self.ap.state["steering"], 1)
        self.assertEqual(self.ap.state["bounds"]["positions"], [500, 8000])
        self.assertEqual(es[1]["steering"], 1)
        self.assertTrue(any("steering 1 applied" in n for n in es[1]["plan_notes"]))

    def test_widen_inside_hard_limit_runs_without_trial(self) -> None:
        self.send(self.valid(bounds={"positions": [500, 9000]}))
        self.advisor.script = [Advice(plan={"positions": 9000})]
        es = self.run_blocks(2)
        self.assertEqual([e["kind"] for e in es], ["full", "full"])
        self.assertEqual(es[1]["plan"]["positions"], 9000)

    def test_narrow_below_last_value_clamps_then_trial_when_proposed(self) -> None:
        self.send(self.valid(bounds={"positions": [100, 200]}))
        es = self.run_blocks(2)  # the advisor proposes nothing: the old 1000 is clamped
        self.assertEqual(es[1]["plan"]["positions"], 200)
        self.assertEqual(es[1]["kind"], "full")

    def test_narrow_then_advisor_keeps_old_value_is_one_trial(self) -> None:
        self.send(self.valid(bounds={"positions": [100, 200]}))
        self.advisor.script = [Advice(plan={"positions": 1000})]
        es = self.run_blocks(2)
        self.assertEqual(es[1]["kind"], "trial")
        self.assertEqual(es[1]["trial"]["knob"], "positions")
        self.assertEqual(es[1]["plan"]["positions"], 1000)

    def test_pin_overrides_and_is_not_offered(self) -> None:
        self.send(self.valid(pin={"k": 12}))
        self.advisor.script = [Advice(plan={"k": 5, "positions": 2000})]
        es = self.run_blocks(2)
        self.assertEqual(es[1]["plan"]["k"], 12)
        self.assertEqual(es[1]["plan"]["positions"], 2000)
        self.assertNotIn("k", self.advisor.args[0]["bounds"])
        self.assertEqual(self.advisor.args[0]["pins"], {"k": 12})
        self.assertEqual(es[1]["kind"], "full")

    def test_avoid_refuses_advisor_value(self) -> None:
        self.send(self.valid(avoid={"positions": [2000]}))
        self.advisor.script = [Advice(plan={"positions": 2000})]
        es = self.run_blocks(2)
        self.assertEqual(es[1]["plan"]["positions"], 1000)
        self.assertEqual(es[1]["refused"],
                         [{"knob": "positions", "value": 2000,
                           "reason": "avoided by steering 1"}])

    def test_notes_reach_the_advisor(self) -> None:
        self.send(self.valid(notes=["prefer linear rollouts"], avoid={"k": [4]}))
        self.run_blocks(2)
        notes = self.advisor.args[0]["notes"]
        self.assertIn("prefer linear rollouts", notes)
        self.assertTrue(any("k" in n and "4" in n for n in notes if n.startswith("Avoid")))

    def refuse_check(self, text: Any, reason: Optional[str] = None) -> None:
        self.send(self.valid(pin={"k": 12}))
        self.advisor.script = [Advice(), Advice()]
        self.advisor.stop_after = 3
        self.ap.start(dict(CFG))
        # block 1 boundary takes the valid file; drop the bad one for the second boundary
        orig = self.advisor.advise

        def advise(*a: Any, **kw: Any) -> Advice:
            if not self.advisor.calls:  # the first boundary has taken the valid file already
                self.send(text)
            return orig(*a, **kw)

        self.advisor.advise = advise  # type: ignore[method-assign]
        self.ap.run_loop()
        es = self.ap.log.read()[0]
        self.assertTrue(self.archive("1.json").is_file())
        self.assertTrue(self.archive("refused-2.json").is_file())
        self.assertEqual(self.ap.state["steering"], 1)
        self.assertEqual(self.ap.state["pins"], {"k": 12})
        self.assertEqual(es[2]["refused"][0]["knob"], "steering")
        self.assertEqual(es[2]["refused"][0]["value"], 2)
        if reason:
            self.assertIn(reason, es[2]["refused"][0]["reason"])
        self.assertEqual(es[2]["plan"]["k"], 12)  # the old steering stays in force

    def test_bad_json_refused_old_steering_kept(self) -> None:
        self.refuse_check("{not json", "not readable JSON")

    def test_missing_approved_by_refused_old_steering_kept(self) -> None:
        self.refuse_check(json.dumps({"pin": {"k": 3}}), "approved_by")


if __name__ == "__main__":
    unittest.main()
