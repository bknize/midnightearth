import json
import shutil
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

from trainer import knobs
from trainer.advisor import Advice, AdvisorConfig, FileAdvisor
from trainer.autopilot import Autopilot
from trainer.config import RunConfig
from trainer.farm import Farm
from trainer.server import Service

STUB = str(Path(__file__).resolve().parent / "stub_worker.py")
STAMP = "r7-stub"
CFG: Dict[str, Any] = {"block_hours": 1, "reserve_minutes": 10, "poll_s": 1,
                       "min_positions": 100, "run_seed_base": 7}


def stub_farm(cfg: RunConfig, log_dir: Path) -> Farm:
    return Farm([sys.executable, "-I", STUB, "--stamp", STAMP], cfg.workers, timeout=30.0,
                start_timeout=30.0)


class QuietAdvisor:
    def default_plan(self, has_champion: bool) -> Dict[str, Any]:
        return knobs.plan_defaults()

    def advise(self, *args: Any) -> Advice:
        return Advice(plan=knobs.plan_defaults())


class FakeJudgeConfig:
    def __init__(self) -> None:
        self.cap = 400


class QuietJudge:
    def __init__(self) -> None:
        self.config = FakeJudgeConfig()


class IdleAutopilot(Autopilot):
    """The real start, stop, shutdown and state code, with a loop that only waits for the flag."""

    def run_loop(self) -> None:
        if self.state["block_started"] is None:
            self._begin_block()
        while not self._stop_requested():
            time.sleep(0.01)
        if self._halting:
            self._save()
            return
        self._compose_entry("stop")
        self._close_block()


def make_autopilot(service: Any) -> Autopilot:
    return IdleAutopilot(service, QuietAdvisor(), QuietJudge(), feature_set_fn=lambda: "FS1",
                         disk_free_gb=lambda: 100.0)


class ServerAutopilotTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.sync_calls: List[str] = []

    def service(self, resume: bool = False) -> Service:
        def sync(commit: str, bundle: str, inbox: str, **kw: Any) -> Dict[str, Any]:
            self.sync_calls.append(commit)
            return {"commit": commit}

        s = Service(self.tmp / "data", self.tmp / "me", farm_factory=stub_farm,
                    stamp_fn=lambda: STAMP, sync_fn=sync, commit_fn=lambda: "c1",
                    autopilot_factory=make_autopilot, resume_autopilot=resume)
        self.addCleanup(s.close, 5.0)
        return s

    def wait_stopped(self, svc: Service) -> None:
        svc.autopilot.join(10)
        self.assertFalse(svc.autopilot.state["running"])

    def test_start_status_stop_findings(self) -> None:
        svc = self.service()
        self.assertFalse(svc.autopilot_status()["running"])
        reply = svc.autopilot_start(CFG)
        self.assertNotIn("error", reply)
        self.assertTrue(svc.autopilot_status()["running"])
        self.assertIn("already", svc.autopilot_start(CFG)["error"])
        self.assertEqual(svc.autopilot_stop()["stopping"], True)
        self.wait_stopped(svc)
        self.assertFalse(svc.autopilot_status()["running"])
        found = svc.get_findings()
        self.assertEqual([e["status"] for e in found["entries"]], ["interrupted"])
        self.assertEqual(found["problems"], [])
        self.assertIn("error", svc.autopilot_stop())

    def test_hand_started_run_and_fit_refused_while_autopilot_runs(self) -> None:
        svc = self.service()
        svc.autopilot_start(CFG)
        for reply in (svc.start_run({}), svc.fit({"runs": ["r1"]})):
            self.assertIn("autopilot is running", reply["error"])
            self.assertIn("autopilot_stop", reply["error"])
        svc.autopilot_stop()
        self.wait_stopped(svc)
        self.assertNotIn("autopilot is running", svc.start_run({}).get("error", ""))

    def test_get_findings_after_filters(self) -> None:
        svc = self.service()
        for _ in range(2):
            svc.autopilot_start(CFG)
            svc.autopilot_stop()
            self.wait_stopped(svc)
        self.assertEqual([e["block"] for e in svc.get_findings()["entries"]], [1, 2])
        self.assertEqual([e["block"] for e in svc.get_findings(1)["entries"]], [2])
        self.assertEqual(svc.get_findings(2)["entries"], [])
        path = self.tmp / "data" / "autopilot" / "findings.jsonl"
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("not json\n")
        self.assertEqual(len(svc.get_findings(0)["problems"]), 1)

    def test_sync_refused_while_running(self) -> None:
        svc = self.service()
        svc.autopilot_start(CFG)
        reply = svc.sync_code("abc")
        self.assertIn("autopilot is running (block 1)", reply["error"])
        self.assertIn("autopilot_stop", reply["error"])
        self.assertEqual(self.sync_calls, [])
        svc.autopilot_stop()
        self.wait_stopped(svc)
        self.assertNotIn("error", svc.sync_code("abc"))
        self.assertEqual(self.sync_calls, ["abc"])

    def test_start_refused_with_hand_started_run(self) -> None:
        svc = self.service()
        svc.store.create_run(RunConfig(positions=10).to_dict(), STAMP, "c1")
        self.assertIn("is active", svc.autopilot_start(CFG)["error"])
        self.assertFalse(svc.autopilot_status()["running"])

    def test_restart_resumes_a_running_autopilot(self) -> None:
        first = self.service()
        first.autopilot_start(CFG)
        first.close(5.0)
        state = json.loads((self.tmp / "data" / "autopilot" / "state.json").read_text())
        self.assertTrue(state["running"])  # a shutdown is not a stop
        self.assertEqual(first.get_findings()["entries"], [])
        second = self.service(resume=True)
        self.assertTrue(second.autopilot_status()["running"])
        thread = second.autopilot._thread
        self.assertIsNotNone(thread)
        if thread is not None:
            self.assertTrue(thread.is_alive())
        second.autopilot_stop()
        self.wait_stopped(second)

    def test_no_resume_without_the_flag(self) -> None:
        first = self.service()
        first.autopilot_start(CFG)
        first.close(5.0)
        second = self.service(resume=False)
        self.assertIsNone(second.autopilot._thread)

    def test_resume_applies_judge_cap(self) -> None:
        first = self.service()
        first.autopilot_start({**CFG, "judge_cap": 123})
        first.close(5.0)
        second = self.service()
        self.assertEqual(second.autopilot.judge.config.cap, 123)


class Dead:
    def poll(self) -> int:
        return 1

    def terminate(self) -> None:
        return None

    def wait(self, timeout: Optional[float] = None) -> int:
        return 1


class FileAdvisorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        (self.tmp / "autopilot").mkdir()
        self.launched: List[List[str]] = []

    def launch(self, argv: List[str]) -> Any:
        self.launched.append(argv)
        return Dead()

    def advise(self) -> Advice:
        fa = FileAdvisor(self.tmp, launch=self.launch)
        return fa.advise(1, [], knobs.default_bounds(), {}, {}, [], False, {}, True)

    def write(self, text: str) -> None:
        (self.tmp / "autopilot" / "config.json").write_text(text, encoding="utf-8")

    def test_no_config_falls_back(self) -> None:
        a = self.advise()
        self.assertEqual(a.source, "fallback")
        self.assertIn("no advisor config", a.fallback_reason)
        self.assertEqual(self.launched, [])

    def test_bad_config_falls_back(self) -> None:
        self.write("{not json")
        a = self.advise()
        self.assertEqual(a.source, "fallback")
        self.assertIn("not JSON", a.fallback_reason)
        self.write(json.dumps({"bogus": 1}))
        self.assertIn("bogus", self.advise().fallback_reason)
        self.assertEqual(self.launched, [])

    def test_valid_config_is_read_each_call(self) -> None:
        self.write(json.dumps({"server_path": "/wrong/llama-server", "model_path": "m.gguf"}))
        a = self.advise()
        self.assertEqual(a.source, "fallback")
        self.assertIn("server exited", a.fallback_reason)
        self.assertEqual(self.launched[0][0], "/wrong/llama-server")
        self.write(json.dumps({"server_path": "/other/llama-server", "model_path": "m.gguf"}))
        self.advise()
        self.assertEqual(self.launched[1][0], "/other/llama-server")
        self.assertEqual(AdvisorConfig().port, 8080)

    def test_default_plan(self) -> None:
        self.assertEqual(FileAdvisor(self.tmp).default_plan(False)["rollout"], "random")


if __name__ == "__main__":
    unittest.main()
