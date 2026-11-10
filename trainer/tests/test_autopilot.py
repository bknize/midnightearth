import shutil
import tempfile
import threading
import unittest
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from trainer import judge as J
from trainer import knobs
from trainer.autopilot import Autopilot, AutopilotConfig
from trainer.store import weights_path

T0 = 1_000_000.0
CFG: Dict[str, Any] = {"block_hours": 1, "reserve_minutes": 10, "grace_minutes": 20,
                       "trial_minutes": 20, "min_positions": 100, "poll_s": 60,
                       "run_seed_base": 7}


class Crash(BaseException):
    """A simulated process death: not an Exception, so the loop's own handler lets it through."""


class FakeClock:
    def __init__(self) -> None:
        self.t = T0
        self.hooks: List[Callable[[], None]] = []

    def now(self) -> float:
        return self.t

    def sleep(self, s: float) -> None:
        self.t += s
        for hook in list(self.hooks):
            hook()


class FakeService:
    def __init__(self, clock: FakeClock, data_dir: Path) -> None:
        self.clock = clock
        self.data_dir = data_dir
        self.runs: Dict[str, Dict[str, Any]] = {}
        self.fits: Dict[str, Dict[str, Any]] = {}
        self.run_cfgs: List[Dict[str, Any]] = []
        self.fit_cfgs: List[Dict[str, Any]] = []
        self.stopped: List[str] = []
        self.resumed: List[str] = []
        self.rate = 1.0
        self.total = 1500
        self.fit_s = 60.0
        self.fail_start = False
        self.on_fit_done: Optional[Callable[[], None]] = None
        self.lpm_fn: Callable[[Dict[str, Any]], float] = lambda cfg: 100.0

    def start_run(self, cfg: Dict[str, Any]) -> Dict[str, Any]:
        self.run_cfgs.append(cfg)
        if self.fail_start:
            return {"error": "no godot"}
        rid = "r%d" % len(self.run_cfgs)
        self.runs[rid] = {"elapsed": 0.0, "last": self.clock.now(), "state": "running",
                          "stop": False, "rate": self.rate, "total": self.total,
                          "lpm": self.lpm_fn(cfg)}
        return {"run_id": rid, "state": "queued", "stamp": "S1"}

    def _advance(self, r: Dict[str, Any]) -> None:
        if r["state"] != "running":
            return
        now = self.clock.now()
        r["elapsed"] += now - r["last"]
        r["last"] = now
        if r["stop"]:
            r["state"] = "stopped"
        elif int(r["elapsed"] * r["rate"]) >= r["total"]:
            r["state"] = "done"

    def run_status(self, run_id: str) -> Dict[str, Any]:
        if run_id in self.fits:
            f = self.fits[run_id]
            if f["state"] == "running" and self.clock.now() >= f["start"] + self.fit_s:
                f["state"] = "done"
                if self.on_fit_done is not None:
                    self.on_fit_done()
            return {"kind": "fit", "fit_id": run_id, "state": f["state"], "last_error": ""}
        r = self.runs[run_id]
        self._advance(r)
        return {"run_id": run_id, "state": r["state"],
                "positions_done": min(int(r["elapsed"] * r["rate"]), r["total"]),
                "labels": int(r["elapsed"] / 60.0 * r["lpm"]), "elapsed_s": r["elapsed"],
                "last_error": ""}

    def stop_run(self, run_id: str) -> Dict[str, Any]:
        r = self.runs[run_id]
        if r["state"] != "running":
            return {"error": "not running"}
        r["stop"] = True
        self.stopped.append(run_id)
        return {"run_id": run_id, "state": "stopping"}

    def resume_run(self, run_id: str) -> Dict[str, Any]:
        r = self.runs[run_id]
        if r["state"] not in ("stopped", "interrupted"):
            return {"error": "not resumable"}
        r.update(state="running", last=self.clock.now(), stop=False)
        self.resumed.append(run_id)
        return {"run_id": run_id, "state": "queued"}

    def fit(self, cfg: Dict[str, Any]) -> Dict[str, Any]:
        self.fit_cfgs.append(cfg)
        fid = "f%d" % len(self.fit_cfgs)
        self.fits[fid] = {"start": self.clock.now(), "state": "running"}
        return {"fit_id": fid, "state": "queued", "stamp": "S1", "feature_set": "FS1",
                "runs": cfg["runs"]}

    def get_report(self, fit_id: str) -> Dict[str, Any]:
        return {"agreement": {"fitted": 0.8, "heldout": 0.7}, "pairs": {"total": 10}}

    def restart(self) -> None:
        for r in self.runs.values():
            if r["state"] == "running":
                r["state"] = "interrupted"
        for f in self.fits.values():
            if f["state"] == "running":
                f["state"] = "failed"


class FakeJudge:
    def __init__(self, script: List[str]) -> None:
        self.script = list(script)
        self.calls: List[Any] = []
        self.budgets: List[Optional[float]] = []
        self.on_stop: Callable[[], None] = lambda: None

    def judge(self, fit_w: str, champ_w: Optional[str],
              stop: Optional[threading.Event] = None,
              budget_s: Optional[float] = None) -> J.Judgment:
        self.calls.append((fit_w, champ_w, stop))
        self.budgets.append(budget_s)
        item = self.script.pop(0) if self.script else "fail"
        if item == "crash":
            raise Crash()
        if item == "stopped":
            self.on_stop()
            return J.Judgment(line_random="bot-eval: random pass", stopped=True)
        res = "pass" if item == "pass" else "fail"
        return J.Judgment(line_random="bot-eval: random " + item,
                          line_champion="bot-eval: champ " + item if champ_w else "",
                          outcome_random=res, outcome_champion=res if champ_w else "skipped",
                          passed=item == "pass")


@dataclass
class Advice:
    plan: Dict[str, Any] = field(default_factory=dict)
    reason: str = "because"
    source: str = "advisor"
    fallback_reason: str = ""
    model: str = "fake-model"
    prompt_digest: str = "abc123"
    seconds: float = 1.5


class FakeAdvisor:
    def __init__(self) -> None:
        self.script: List[Advice] = []
        self.calls: List[Dict[str, Any]] = []
        self.defaults: List[bool] = []
        self.ap: Optional[Autopilot] = None
        self.stop_after = 0

    def _maybe_stop(self) -> None:
        if self.ap is not None and self.stop_after and self.ap.log.last_block() >= self.stop_after:
            self.ap.stop()

    def default_plan(self, has_champion: bool) -> Dict[str, Any]:
        self.defaults.append(has_champion)
        self._maybe_stop()
        plan = knobs.plan_defaults()
        if has_champion:
            plan.update(rollout="linear", rollout_weights="champion")
        return plan

    def advise(self, block: int, entries: List[Dict[str, Any]], bounds: Any, extras: Any,
               pins: Any, notes: Any, plateau: bool, last_plan: Any,
               has_champion: bool, stop: Any = None) -> Advice:
        self.calls.append({"block": block, "entries": entries, "plateau": plateau,
                           "last_plan": last_plan, "has_champion": has_champion})
        self._maybe_stop()
        return self.script.pop(0) if self.script else Advice()


class AutopilotCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.clock = FakeClock()
        self.service = FakeService(self.clock, self.tmp)
        self.advisor = FakeAdvisor()
        self.judge = FakeJudge(["pass"])
        self.ap = self.make(self.advisor, self.judge)
        self.advisor.ap = self.ap

    def make(self, advisor: FakeAdvisor, judge: FakeJudge) -> Autopilot:
        ap = Autopilot(self.service, advisor, judge, data_dir=self.tmp, clock=self.clock.now,
                       sleep=self.clock.sleep, disk_free_gb=lambda: 100.0,
                       feature_set_fn=lambda: "FS1")
        ap._spawn = lambda: None  # type: ignore[method-assign]  # tests run the loop inline
        return ap

    def go(self, stop_after: int = 0, **cfg: Any) -> Dict[str, Any]:
        self.advisor.stop_after = stop_after
        reply = self.ap.start({**CFG, **cfg})
        self.assertNotIn("error", reply)
        self.ap.run_loop()
        return reply

    def entries(self) -> List[Dict[str, Any]]:
        return self.ap.log.read()[0]

    def stop_file(self) -> Path:
        return self.tmp / "autopilot" / "STOP"

    # config

    def test_unknown_field_refused(self) -> None:
        reply = self.ap.start({"block_hours": 1, "bogus": 3, "other": 1})
        self.assertIn("bogus", reply["error"])
        self.assertIn("other", reply["error"])
        self.assertFalse(self.ap.state["running"])
        with self.assertRaises(ValueError):
            AutopilotConfig.from_dict({"nope": 1})
        self.assertEqual(AutopilotConfig.from_dict({}).judge_cap, 400)

    def test_start_twice_refused(self) -> None:
        self.assertNotIn("error", self.ap.start(CFG))
        self.assertIn("already", self.ap.start(CFG)["error"])

    # blocks

    def test_three_full_blocks_one_entry_each(self) -> None:
        self.go(stop_after=3)
        es = self.entries()
        self.assertEqual([e["block"] for e in es], [1, 2, 3])
        for e in es:
            self.assertEqual((e["kind"], e["status"], len(e["iterations"])), ("full", "done", 2))
            self.assertEqual(e["plan_source"], "default" if e["block"] == 1 else "advisor")
        seeds = [c["run_seed"] for c in self.service.run_cfgs]
        self.assertEqual(len(seeds), len(set(seeds)))
        self.assertEqual(seeds[0], 7)
        self.assertAlmostEqual(self.service.run_cfgs[0]["hours"], (3600 - 600) / 3600.0)
        self.assertFalse(self.ap.state["running"])
        self.assertEqual(es[0]["champion_after"], "f1")
        self.assertTrue(es[0]["iterations"][0]["became_champion"])
        self.assertEqual(es[0]["iterations"][0]["agreement_heldout"], 0.7)

    def test_deadline_mid_run_fits_above_min_positions(self) -> None:
        self.service.total = 100000
        self.go(stop_after=1)
        e = self.entries()[0]
        self.assertEqual(self.service.stopped, ["r1"])
        self.assertEqual(len(e["iterations"]), 1)
        self.assertEqual(e["iterations"][0]["fit"], "f1")
        self.assertEqual(len(self.judge.calls), 1)
        self.assertEqual(e["status"], "done")

    def test_deadline_mid_run_below_min_positions_not_fitted(self) -> None:
        self.service.total = 100000
        self.service.rate = 0.01
        self.go(stop_after=1)
        e = self.entries()[0]
        self.assertEqual(e["iterations"][0]["fit"], "")
        self.assertEqual(self.service.fit_cfgs, [])
        self.assertTrue(any("not fitted" in n for n in e["plan_notes"]))

    def test_champion_weights_knob_resolves(self) -> None:
        self.go(stop_after=2)
        self.assertEqual(self.service.run_cfgs[0]["rollout_weights"], "")
        later = [c for c in self.service.run_cfgs[2:]]
        self.assertTrue(later)
        self.assertNotEqual(later[0].get("rollout_weights"), "champion")

    # trials

    def test_trial_pass_extends_extras(self) -> None:
        self.advisor.script = [Advice(plan={"positions": 9000})]
        self.go(stop_after=3)
        es = self.entries()
        self.assertEqual([e["kind"] for e in es], ["full", "trial", "full"])
        t = es[1]["trial"]
        self.assertEqual((t["knob"], t["value"], t["outcome"]), ("positions", 9000, "pass"))
        self.assertEqual(t["floor"], 40.0)
        self.assertIn("labels_per_minute", t)
        self.assertEqual(self.ap.state["extras"], {"positions": [9000]})
        self.assertEqual(es[2]["plan"]["positions"], 9000)
        self.assertEqual(self.service.run_cfgs[-1]["positions"], 9000)
        self.assertEqual(len(self.advisor.calls), 2)  # no advice after a trial block

    def test_fallback_outside_bounds_is_clamped_not_trialled(self) -> None:
        """A fallback plan is never an experiment (R20): its value outside narrowed bounds is
        carried as the nearest in-bounds value (T14 on the PC ran a trial from a fallback)."""
        self.advisor.script = [Advice(source="fallback", fallback_reason="empty reply",
                                      plan={"positions": 9000})]
        self.go(stop_after=2)
        es = self.entries()
        self.assertEqual([e["kind"] for e in es], ["full", "full"])
        self.assertEqual(es[1]["plan_source"], "fallback")
        self.assertIsNone(es[1]["trial"])
        self.assertEqual(es[1]["plan"]["positions"], 4000)
        self.assertTrue(any("no trial" in n for n in es[1]["plan_notes"]))

    def test_trial_fail_refused_with_fallback(self) -> None:
        self.service.lpm_fn = lambda cfg: 100.0 if cfg["positions"] <= 4000 else 5.0
        self.advisor.script = [Advice(plan={"positions": 9000})]
        self.go(stop_after=3)
        es = self.entries()
        self.assertEqual(es[1]["trial"]["outcome"], "fail")
        self.assertEqual(self.ap.state["extras"], {})
        self.assertEqual(es[2]["plan_source"], "fallback")
        self.assertEqual(es[2]["plan"]["positions"], 1000)
        self.assertEqual(es[2]["refused"][0]["knob"], "positions")
        self.assertEqual(es[2]["refused"][0]["value"], 9000)

    # plateau, faults

    def test_plateau_flagged_at_six(self) -> None:
        self.judge.script = []
        self.go(stop_after=6)
        self.assertEqual([e["plateau"] for e in self.entries()],
                         [False, False, False, False, False, True])
        self.assertEqual([c["plateau"] for c in self.advisor.calls],
                         [False, False, False, False, False, True])

    def test_three_failed_blocks_stop_the_loop(self) -> None:
        self.service.fail_start = True
        self.go()
        es = self.entries()
        self.assertEqual([e["status"] for e in es], ["failed"] * 3)
        self.assertIn("no godot", es[0]["fault"])
        self.assertIn("three failed", es[2]["fault"])
        self.assertFalse(self.ap.state["running"])

    def test_low_disk_stops_with_fault(self) -> None:
        self.ap._disk_free_gb = lambda: 1.0
        self.go()
        es = self.entries()
        self.assertEqual((len(es), es[0]["status"]), (1, "failed"))
        self.assertIn("disk", es[0]["fault"])
        self.assertFalse(self.ap.state["running"])
        self.assertEqual(self.service.run_cfgs, [])

    # advisor

    def test_fallback_advice_recorded_with_reason(self) -> None:
        self.advisor.script = [Advice(source="fallback", fallback_reason="timed out", model="m")]
        self.go(stop_after=2)
        e = self.entries()[1]
        self.assertEqual(e["plan_source"], "fallback")
        self.assertIn("timed out", e["plan_notes"])
        self.assertEqual(e["advisor"]["model"], "m")
        self.assertEqual(set(e["advisor"]), {"model", "prompt_digest", "reason", "seconds"})

    # seed

    def test_seed_judging_makes_champion(self) -> None:
        self.judge.script = ["pass", "fail"]
        self.go(stop_after=1, candidates=["c1", "c2"])
        e = self.entries()[0]
        self.assertEqual(e["kind"], "seed")
        self.assertEqual([i["fit"] for i in e["iterations"]], ["c1", "c2"])
        self.assertEqual([i["became_champion"] for i in e["iterations"]], [True, False])
        self.assertEqual(e["champion_after"], "c1")
        self.assertEqual(J.load_champion(self.tmp)["fit_id"], "c1")
        self.assertEqual(self.judge.calls[0][1], None)
        self.assertEqual(self.judge.calls[1][1], weights_path(self.tmp, "c1"))
        self.assertEqual(self.advisor.defaults, [False, True])
        self.assertIsInstance(self.judge.calls[0][2], threading.Event)

    def test_seed_champion_takes_the_fit_records_stamp(self) -> None:
        """A seeded champion is saved with its fit's stamp and feature set, not the seed block's
        blank ones, so the next start keeps it (T14 on the PC)."""
        class Store:
            def get_fit(self, fit_id: str) -> Dict[str, Any]:
                return {"fit_id": fit_id, "stamp": "S1", "feature_set": "FS1", "state": "done"}
        self.service.store = Store()  # type: ignore[attr-defined]
        self.judge.script = ["pass"]
        self.go(stop_after=1, candidates=["c1"])
        champ = J.load_champion(self.tmp)
        self.assertEqual((champ["stamp"], champ["feature_set"]), ("S1", "FS1"))
        kept, note = J.champion_for(self.tmp, "FS1", "S1")
        self.assertEqual((kept["fit_id"] if kept else None, note), ("c1", ""))

    # stop

    def test_stop_during_labelling(self) -> None:
        self.service.total = 100000
        self.clock.hooks.append(self.ap.stop)
        self.go()
        e = self.entries()[0]
        self.assertEqual(e["status"], "interrupted")
        self.assertEqual(self.service.stopped, ["r1"])
        self.assertEqual(self.service.fit_cfgs, [])
        self.assertFalse(self.ap.state["running"])
        self.assertFalse(self.stop_file().exists())

    def test_stop_file_during_labelling(self) -> None:
        self.service.total = 100000

        def drop() -> None:
            self.stop_file().parent.mkdir(parents=True, exist_ok=True)
            self.stop_file().write_text("")
        self.clock.hooks.append(drop)
        self.go()
        self.assertEqual(self.entries()[0]["status"], "interrupted")
        self.assertFalse(self.stop_file().exists())
        self.assertFalse(self.ap.state["running"])

    def test_stop_between_fit_and_judge(self) -> None:
        self.service.on_fit_done = self.ap.stop
        self.go()
        e = self.entries()[0]
        self.assertEqual(e["status"], "interrupted")
        self.assertEqual(e["iterations"][0]["fit"], "f1")
        self.assertEqual(self.judge.calls, [])
        self.assertFalse(self.stop_file().exists())
        self.assertFalse(self.ap.state["running"])

    def test_stop_between_judge_games(self) -> None:
        self.judge.script = ["stopped"]
        self.judge.on_stop = self.ap.stop
        self.go()
        e = self.entries()[0]
        self.assertEqual(e["status"], "interrupted")
        self.assertEqual(e["iterations"][0]["judge_random"], "bot-eval: random pass")
        self.assertFalse(e["iterations"][0]["became_champion"])
        self.assertEqual(e["champion_after"], None)
        self.assertFalse(self.ap.state["running"])

    # resume

    def crash_when(self, cond: Callable[[], bool]) -> None:
        def hook() -> None:
            if cond():
                self.clock.hooks.remove(hook)
                raise Crash()
        self.clock.hooks.append(hook)

    def restart(self, judge: Optional[FakeJudge] = None) -> Autopilot:
        self.service.restart()
        self.clock.t += 300
        self.clock.hooks.clear()
        adv = FakeAdvisor()
        adv.stop_after = 1
        ap2 = self.make(adv, judge or self.judge)
        adv.ap = ap2
        self.assertTrue(ap2.resume_if_running())
        return ap2

    def start_and_crash(self) -> None:
        self.advisor.stop_after = 1
        self.assertNotIn("error", self.ap.start(CFG))
        with self.assertRaises(Crash):
            self.ap.run_loop()
        self.assertTrue(self.ap.state["running"])

    def test_resume_from_label_keeps_original_deadline(self) -> None:
        self.service.total = 100000
        self.crash_when(lambda: self.clock.t >= T0 + 120)
        self.start_and_crash()
        self.assertEqual(self.ap.state["stage"], "label")
        ap2 = self.restart()
        deadline = ap2.state["deadline"]
        self.assertEqual(deadline, T0 + 3600)
        ap2.run_loop()
        self.assertEqual(self.service.resumed, ["r1"])
        e = ap2.log.read()[0][0]
        self.assertEqual((e["block"], e["status"], len(e["iterations"])), (1, "done", 1))
        self.assertEqual(e["iterations"][0]["fit"], "f1")
        self.assertLess(self.clock.t, deadline + 1200)

    def test_resume_from_fit_refits(self) -> None:
        self.crash_when(lambda: any(f["state"] == "running" for f in self.service.fits.values()))
        self.start_and_crash()
        self.assertEqual(self.ap.state["stage"], "fit")
        ap2 = self.restart()
        ap2.run_loop()
        self.assertEqual(len(self.service.fit_cfgs), 3)  # f1 lost, refit f2, next run's f3
        e = ap2.log.read()[0][0]
        self.assertEqual(e["iterations"][0]["fit"], "f2")
        self.assertEqual(len(self.judge.calls), 2)  # one after the refit, one on the next run

    def test_resume_from_judge_judges_again(self) -> None:
        self.judge.script = ["crash", "pass"]
        self.start_and_crash()
        self.assertEqual(self.ap.state["stage"], "judge")
        ap2 = self.restart()
        ap2.run_loop()
        self.assertEqual(len(self.service.fit_cfgs), 2)  # only the second run's fit is new
        e = ap2.log.read()[0][0]
        self.assertEqual(e["iterations"][0]["fit"], "f1")
        self.assertTrue(e["iterations"][0]["became_champion"])
        self.assertEqual(J.load_champion(self.tmp)["fit_id"], "f1")

    # shutdown is not a stop (R37)

    def shutdown_when(self, cond: Callable[[], bool]) -> None:
        def hook() -> None:
            if cond():
                self.clock.hooks.remove(hook)
                self.ap.shutdown()
        self.clock.hooks.append(hook)

    def halt_at(self, stage: str, **cfg: Any) -> None:
        """Run until the shutdown hook fired; the block must be left open at `stage`."""
        self.advisor.stop_after = 1
        self.assertNotIn("error", self.ap.start({**CFG, **cfg}))
        self.ap.run_loop()
        st = self.ap.state
        self.assertTrue(st["running"])
        self.assertEqual((st["stage"], st["block"], st["deadline"]), (stage, 1, T0 + 3600))
        self.assertEqual(self.service.stopped, [])
        self.assertEqual(self.service.resumed, [])

    def assert_resumed_block_one(self, ap2: Autopilot) -> Dict[str, Any]:
        self.assertEqual((ap2.state["block"], ap2.state["deadline"]), (1, T0 + 3600))
        ap2.run_loop()
        es = ap2.log.read()[0]
        self.assertEqual((es[0]["block"], es[0]["status"]), (1, "done"))
        self.assertEqual(es[0]["fault"], "")
        self.assertNotIn("failed", [e["status"] for e in es])
        return es[0]

    def test_shutdown_while_labelling_resumes_the_same_run(self) -> None:
        self.shutdown_when(lambda: self.clock.t >= T0 + 120)
        self.halt_at("label")
        self.assertEqual(self.entries(), [])
        self.assertEqual(self.ap.state["run_id"], "r1")
        e = self.assert_resumed_block_one(self.restart())
        self.assertEqual(self.service.resumed, ["r1"])
        self.assertEqual(e["iterations"][0]["run"], "r1")

    def test_shutdown_while_fitting_refits_after_resume(self) -> None:
        self.shutdown_when(lambda: any(f["state"] == "running" for f in self.service.fits.values()))
        self.halt_at("fit")
        self.assertEqual(self.entries(), [])
        e = self.assert_resumed_block_one(self.restart())
        self.assertEqual(e["iterations"][0]["run"], "r1")
        self.assertEqual(e["iterations"][0]["fit"], "f2")

    def test_shutdown_while_judging_judges_again(self) -> None:
        self.judge.script = ["stopped"]
        self.judge.on_stop = self.ap.shutdown
        self.halt_at("judge")
        self.assertEqual(self.entries(), [])
        self.assertEqual(self.ap.state["iterations"], [])
        e = self.assert_resumed_block_one(self.restart(FakeJudge(["pass"])))
        self.assertEqual(e["iterations"][0]["fit"], "f1")
        self.assertTrue(e["iterations"][0]["became_champion"])

    def test_shutdown_while_judging_seed_candidates(self) -> None:
        self.judge.script = ["stopped"]
        self.judge.on_stop = self.ap.shutdown
        self.halt_at("judge", candidates=["c1"])
        self.assertEqual((self.ap.state["fit_id"], self.ap.state["iterations"]), ("c1", []))
        self.assertEqual(self.entries(), [])
        e = self.assert_resumed_block_one(self.restart(FakeJudge(["pass"])))
        self.assertEqual((e["kind"], e["champion_after"]), ("seed", "c1"))

    def test_shutdown_at_the_advisor_boundary(self) -> None:
        orig = self.advisor.advise

        def advise(*a: Any, **kw: Any) -> Advice:
            self.ap.shutdown()
            return orig(*a, **kw)

        self.advisor.advise = advise  # type: ignore[method-assign]
        self.advisor.stop_after = 1
        self.assertNotIn("error", self.ap.start(CFG))
        self.ap.run_loop()
        self.assertEqual([e["block"] for e in self.entries()], [1])
        self.assertEqual((self.ap.state["stage"], self.ap.state["block"]), ("boundary", 1))
        ap2 = self.restart()
        ap2.run_loop()
        es = ap2.log.read()[0]
        self.assertEqual([(e["block"], e["status"]) for e in es], [(1, "done")])
        self.assertEqual(ap2.state["block"], 2)  # planned once, on resume

    def test_shutdown_failure_of_the_fit_is_not_recorded(self) -> None:
        """A fit that fails because the service closed must not become a `failed` block."""
        def fail_and_shutdown() -> None:
            for f in self.service.fits.values():
                f["state"] = "failed"
            self.ap.shutdown()

        self.shutdown_when(lambda: any(f["state"] == "running" for f in self.service.fits.values()))
        self.clock.hooks.append(lambda: fail_and_shutdown() if self.service.fits else None)
        self.halt_at("fit")
        self.assertEqual((self.ap.state["fault"], self.ap.state["failed_count"]), ("", 0))
        self.assertEqual(self.entries(), [])

    # boundary faults

    def test_findings_append_oserror_does_not_stop_the_loop(self) -> None:
        real = self.ap.log.append
        calls = [0]

        def flaky(entry: Dict[str, Any]) -> Any:
            calls[0] += 1
            if calls[0] == 1:
                raise OSError("disk full")
            return real(entry)

        self.ap.log.append = flaky  # type: ignore[method-assign]
        self.advisor.stop_after = 3
        self.assertNotIn("error", self.ap.start(CFG))
        self.ap._thread_main()
        es = self.entries()
        self.assertEqual([e["block"] for e in es], [1, 2, 3])
        self.assertTrue(any("disk full" in n for n in es[1]["plan_notes"]))
        self.assertFalse(self.ap.state["running"])  # only the stop ended it

    def test_plan_next_exception_is_retried(self) -> None:
        real = self.advisor.advise
        calls = [0]

        def flaky(*a: Any, **kw: Any) -> Advice:
            calls[0] += 1
            if calls[0] == 1:
                raise KeyError("boom")
            return real(*a, **kw)

        self.advisor.advise = flaky  # type: ignore[method-assign]
        self.advisor.stop_after = 2
        self.ap.start(CFG)
        self.ap._thread_main()
        self.assertEqual([e["block"] for e in self.entries()], [1, 2])

    # champion stamp (R39)

    def test_champion_of_another_stamp_is_dropped(self) -> None:
        J.save_champion(self.tmp, "cX", "S0", "FS1", "a", "", 1)
        setattr(self.service, "_stamp_fn", lambda: "S1")
        self.assertNotIn("error", self.ap.start(CFG))
        self.assertEqual(self.ap.state["champion"], "")
        self.assertIn("champion cX dropped: stamp S0 differs from S1",
                      self.ap.state["plan_notes"])
        self.assertTrue((self.tmp / "autopilot" / "champion.dropped-S0.json").exists())

    def test_champion_of_the_current_stamp_is_kept(self) -> None:
        J.save_champion(self.tmp, "cX", "S1", "FS1", "a", "", 1)
        setattr(self.service, "_stamp_fn", lambda: "S1")
        self.ap.start(CFG)
        self.assertEqual(self.ap.state["champion"], "cX")

    def test_champion_dropped_when_no_feature_set_is_known(self) -> None:
        J.save_champion(self.tmp, "cX", "S0", "FS1", "a", "", 1)
        setattr(self.service, "_stamp_fn", lambda: "S1")
        self.ap._feature_set_fn = lambda: ""
        self.ap.start(CFG)
        self.assertEqual(self.ap.state["champion"], "")

    # bounds of one judge game, the fit, the budget (R5, R36)

    def test_judge_gets_the_time_left_to_deadline_and_grace(self) -> None:
        self.go(stop_after=1)
        self.assertEqual(self.judge.budgets[0], 3600 + 1200 - 1560)  # the run and the fit have taken 1560 s

    def test_fit_that_would_end_past_the_grace_is_skipped(self) -> None:
        self.ap.start(CFG)
        self.ap.state["deadline"] = T0 + 10
        self.clock.t = T0 + 10 + 1100
        self.assertFalse(self.ap._late(0.0))
        self.assertTrue(self.ap._late(300.0))

    def test_stop_during_an_uninterruptible_fit_gives_up_after_the_grace(self) -> None:
        self.service.fit_s = 10 ** 7
        self.clock.hooks.append(
            lambda: self.ap.stop() if any(f["state"] == "running" for f in self.service.fits.values())
            else None)
        self.go()
        e = self.entries()[0]
        self.assertEqual(e["status"], "interrupted")
        self.assertTrue(any("gave up waiting" in n for n in e["plan_notes"]))
        self.assertLess(self.clock.t, T0 + 1500 + 1200 + 600)

    # start and stop corners

    def test_second_start_refused_while_the_thread_lives(self) -> None:
        self.release = threading.Event()
        self.ap._thread = threading.Thread(target=self.release.wait, daemon=True)
        self.ap._thread.start()
        self.addCleanup(self.release.set)
        self.assertIn("already", self.ap.start(CFG)["error"])

    def test_stop_before_resume_is_honoured(self) -> None:
        self.shutdown_when(lambda: self.clock.t >= T0 + 120)
        self.halt_at("label")
        ap2 = self.restart()
        ap2.stop()
        ap2.run_loop()
        self.assertEqual(ap2.log.read()[0][0]["status"], "interrupted")
        self.assertFalse(ap2.state["running"])

    def test_stale_stop_is_cleared_when_nothing_runs(self) -> None:
        self.stop_file().parent.mkdir(parents=True, exist_ok=True)
        self.stop_file().write_text("")
        self.assertFalse(self.ap.resume_if_running())
        self.assertFalse(self.stop_file().exists())
        self.assertNotIn("error", self.ap.start(CFG))


if __name__ == "__main__":
    unittest.main()


class JudgeGodotTest(unittest.TestCase):
    """The judge gets the service's Godot: the driver's default is the Mac's path (T14 on the
    PC: every seed judgment errored with GODOT_BIN unset)."""

    def test_uses_the_service_lookup(self) -> None:
        from unittest import mock
        from trainer import autopilot as ap
        with mock.patch.object(ap, "godot_bin", return_value=r"C:\godot\godot.exe"):
            self.assertEqual(ap._judge_godot(), r"C:\godot\godot.exe")

    def test_empty_when_no_godot(self) -> None:
        from unittest import mock
        from trainer import autopilot as ap
        from trainer.repo import GodotNotFound

        def missing() -> str:
            raise GodotNotFound("none")
        with mock.patch.object(ap, "godot_bin", side_effect=missing):
            self.assertEqual(ap._judge_godot(), "")
