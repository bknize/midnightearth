"""The training autopilot loop (cycle 16, plan P1 to P6, P10, P11, P14, P16).

A thread inside the trainer service runs blocks forever: a block is a few hours of labelling
runs, each fitted and judged against the champion, and ends with one findings entry. All side
effects go through `service` (the `Service` API, duck-typed), the clock and `sleep` are
injected, and every stage change is written atomically to `<data>/autopilot/state.json`, so a
restarted service resumes the open block and keeps its original wall-clock deadline.

The feature set of the current code is read from `feature_set_fn`; by default that is the
feature set of the most recent finished fit of the current stamp (""  when there is none, in
which case the champion is kept as it is).
"""
import json
import math
import os
import shutil
import statistics
import threading
import time
from dataclasses import asdict, dataclass, field, fields
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from trainer import findings, knobs
from trainer import judge as judge_mod
from trainer.store import ACTIVE, LIVE_FIT, weights_path, write_atomic

STATE_NAME = "state.json"
STOP_NAME = "STOP"
FINDINGS_NAME = "findings.jsonl"
MIN_RUN_S = 60.0  # no labelling run is started with less than this left of its budget
FLOOR_BLOCKS = 8  # the throughput floor is the median of this many full blocks
GB = float(1024 ** 3)
_WEIGHT_KNOBS = ("generator_weights", "rollout_weights")


def _number(data: Dict[str, Any], key: str, low: float, low_open: bool = True) -> None:
    v = data[key]
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):
        raise ValueError("config: %s must be a number" % key)
    if v < low or (low_open and v == low):
        raise ValueError("config: %s must be %s %g" % (key, "above" if low_open else "at least", low))


def _integer(data: Dict[str, Any], key: str, low: int) -> None:
    v = data[key]
    if isinstance(v, bool) or not isinstance(v, int) or v < low:
        raise ValueError("config: %s must be an integer of at least %d" % (key, low))


@dataclass
class AutopilotConfig:
    block_hours: float = 3.0
    grace_minutes: float = 20
    trial_minutes: float = 20
    min_positions: int = 300
    plateau_blocks: int = 6
    disk_floor_gb: float = 5
    judge_cap: int = 400
    candidates: List[str] = field(default_factory=list)
    run_seed_base: int = 0
    reserve_minutes: float = 25
    throughput_share: float = 0.4
    poll_s: float = 30

    @classmethod
    def from_dict(cls, data: Any) -> "AutopilotConfig":
        if not isinstance(data, dict):
            raise ValueError("config: expected an object")
        unknown = sorted(set(data) - {f.name for f in fields(cls)})
        if unknown:
            raise ValueError("config: unknown field(s): " + ", ".join(unknown))
        merged: Dict[str, Any] = {**asdict(cls()), **data}
        for key in ("block_hours", "trial_minutes", "reserve_minutes", "poll_s"):
            _number(merged, key, 0)
        _number(merged, "grace_minutes", 0, low_open=False)
        _number(merged, "disk_floor_gb", 0, low_open=False)
        _number(merged, "throughput_share", 0, low_open=False)
        if merged["throughput_share"] > 1:
            raise ValueError("config: throughput_share must be at most 1")
        _integer(merged, "min_positions", 0)
        _integer(merged, "plateau_blocks", 1)
        _integer(merged, "judge_cap", 1)
        _integer(merged, "run_seed_base", -(1 << 62))
        cands = merged["candidates"]
        if not isinstance(cands, list) or not all(isinstance(c, str) and c for c in cands):
            raise ValueError("config: candidates must be a list of fit ids")
        if merged["reserve_minutes"] >= merged["block_hours"] * 60:
            raise ValueError("config: reserve_minutes must be less than the block length")
        return cls(**merged)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def _iso(t: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def _blank_state() -> Dict[str, Any]:
    return {
        "running": False, "block": 0, "kind": "full", "deadline": None, "block_started": None,
        "plan": {}, "plan_source": "default", "plan_notes": [], "trial": None, "stage": "label",
        "run_id": None, "fit_id": None, "iteration": None, "iterations": [], "champion": "",
        "champion_before": "", "extras": {}, "refused": [], "bounds": knobs.default_bounds(),
        "pins": {}, "avoid": {}, "notes": [], "steering": None, "plateau_count": 0,
        "failed_count": 0, "seed_counter": 0, "seed_done": False, "config": {},
        "advisor": None, "last_plan": None, "last_run": None, "stamp": "", "feature_set": "",
        "fault": "", "halt": False, "entry": None,
    }


class Autopilot:
    def __init__(self, service: Any, advisor: Any = None, judge: Any = None,
                 data_dir: Optional[Any] = None, clock: Callable[[], float] = time.time,
                 sleep: Callable[[float], None] = time.sleep,
                 disk_free_gb: Optional[Callable[[], float]] = None,
                 feature_set_fn: Optional[Callable[[], str]] = None) -> None:
        self.service = service
        self.data_dir = Path(data_dir if data_dir is not None else service.data_dir)
        self.dir = self.data_dir / "autopilot"
        self.clock = clock
        self.sleep = sleep
        self._disk_free_gb: Callable[[], float] = disk_free_gb or (
            lambda: shutil.disk_usage(str(self.data_dir)).free / GB)
        self._feature_set_fn: Callable[[], str] = feature_set_fn or self._default_feature_set
        self.advisor: Any = advisor if advisor is not None else self._default_advisor()
        self.judge: Any = judge if judge is not None else self._default_judge()
        self.log = findings.FindingsLog(self.dir / FINDINGS_NAME)
        self.cfg = AutopilotConfig()
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._lock = threading.RLock()
        self.state: Dict[str, Any] = self._load_state()
        if self.state.get("config"):
            self.cfg = AutopilotConfig.from_dict(self.state["config"])

    # defaults

    def _default_advisor(self) -> Any:
        from trainer import advisor as advisor_mod  # lazily: not needed with an injected advisor
        return advisor_mod.Advisor(self.data_dir)

    def _default_judge(self) -> Any:
        work = Path(getattr(self.service, "root", ".")) / "work"
        return judge_mod.Judge(judge_mod.JudgeConfig(
            worktree=work, godot_bin=os.environ.get("GODOT_BIN", "")))

    def _default_feature_set(self) -> str:
        try:
            stamp_fn = getattr(self.service, "_stamp_fn", None)
            stamp = stamp_fn() if stamp_fn is not None else None
            fits = [f for f in self.service.store.list_fits()
                    if f["state"] == "done" and (stamp is None or f["stamp"] == stamp)]
            fits.sort(key=lambda f: float(f["created"]))
            return str(fits[-1]["feature_set"]) if fits else ""
        except Exception:
            return ""

    # state

    def _load_state(self) -> Dict[str, Any]:
        state = _blank_state()
        try:
            with open(self.dir / STATE_NAME, "r", encoding="utf-8") as fh:
                loaded = json.load(fh)
            if isinstance(loaded, dict):
                state.update(loaded)
        except (OSError, ValueError):
            pass
        return state

    def _save(self) -> None:
        with self._lock:
            self.dir.mkdir(parents=True, exist_ok=True)
            write_atomic(self.dir / STATE_NAME,
                         json.dumps(self.state, indent=2, sort_keys=True, default=str) + "\n")

    def _note(self, text: str) -> None:
        self.state["plan_notes"].append(text)

    def _fault(self, text: str) -> None:
        old = self.state["fault"]
        self.state["fault"] = (old + "; " + text) if old else text

    # public

    def start(self, config: Dict[str, Any]) -> Dict[str, Any]:
        if self.state.get("running") or (self._thread is not None and self._thread.is_alive()):
            return {"error": "autopilot is already running"}
        try:
            cfg = AutopilotConfig.from_dict(config)
        except ValueError as e:
            return {"error": str(e)}
        old = self.state
        st = _blank_state()
        for key in ("seed_counter", "extras", "bounds", "pins", "avoid", "notes", "steering"):
            st[key] = old[key]
        self.cfg = cfg
        self.state = st
        cap = getattr(getattr(self.judge, "config", None), "cap", None)
        if cap is not None:
            self.judge.config.cap = cfg.judge_cap
        champ, note = self._load_champion()
        st["champion"] = str(champ["fit_id"]) if champ else ""
        st["feature_set"] = self._feature_set_fn()
        has = bool(st["champion"])
        st.update(running=True, config=cfg.to_dict(), block=self.log.last_block() + 1,
                  plan=self.advisor.default_plan(has), plan_source="default",
                  plan_notes=[note] if note else [], stage="label")
        st["kind"] = "seed" if (not has and cfg.candidates) else "full"
        self._clear_stop()
        self._save()
        self._spawn()
        return {"started": True, "block": st["block"], "kind": st["kind"]}

    def _load_champion(self) -> Any:
        fs = self._feature_set_fn()
        if fs:
            return judge_mod.champion_for(self.data_dir, fs)
        return judge_mod.load_champion(self.data_dir), ""

    def stop(self) -> Dict[str, Any]:
        if not self.state.get("running"):
            return {"error": "autopilot is not running"}
        self._stop_event.set()
        return {"stopping": True, "block": self.state["block"]}

    def status(self) -> Dict[str, Any]:
        st = dict(self.state)
        entries, _ = self.log.read()
        last: Optional[Dict[str, Any]] = None
        if entries:
            e = entries[-1]
            last = {"block": e.get("block"), "kind": e.get("kind"), "status": e.get("status"),
                    "champion_after": e.get("champion_after"), "plateau": e.get("plateau"),
                    "fault": e.get("fault"), "iterations": len(e.get("iterations") or [])}
        return {"running": bool(st["running"]), "block": st["block"], "kind": st["kind"],
                "stage": st["stage"], "deadline": st["deadline"], "champion": st["champion"],
                "fault": st["fault"], "last_entry": last}

    def resume_if_running(self) -> bool:
        if not self.state.get("running"):
            return False
        self._spawn()
        return True

    def join(self, timeout: Optional[float] = None) -> None:
        t = self._thread
        if t is not None:
            t.join(timeout)

    def _spawn(self) -> None:
        self._thread = threading.Thread(target=self._thread_main, daemon=True)
        self._thread.start()

    def _thread_main(self) -> None:
        try:
            self.run_loop()
        except Exception as e:  # a bug in the loop itself: stop, with the reason recorded
            self.state["running"] = False
            self._fault("autopilot loop crashed: %s: %s" % (type(e).__name__, e))
            self._save()

    # stop flag

    def _clear_stop(self) -> None:
        self._stop_event.clear()
        try:
            (self.dir / STOP_NAME).unlink()
        except OSError:
            pass

    def _stop_requested(self) -> bool:
        if (self.dir / STOP_NAME).exists():
            self._stop_event.set()
        return self._stop_event.is_set()

    def _finish_stop(self) -> None:
        self.state.update(running=False, entry=None, stage="label")
        self._clear_stop()
        self._save()

    def _apply_steering(self) -> None:
        """Hook for the steering inbox (task T07); nothing to apply here."""
        return None

    # the loop

    def run_loop(self) -> None:
        st = self.state
        while st.get("running"):
            if st["stage"] == "boundary" and st.get("entry"):
                self._close_block()
                continue
            if st["block_started"] is None:
                if self._stop_requested():
                    self._finish_stop()
                    break
                self._begin_block()
            self._run_block()
            self._close_block()

    def _begin_block(self) -> None:
        st = self.state
        now = self.clock()
        budget = self.cfg.trial_minutes * 60 if st["kind"] == "trial" else self.cfg.block_hours * 3600
        st.update(block_started=now, deadline=now + budget, stage="label", run_id=None,
                  fit_id=None, iteration=None, iterations=[], fault="", champion_before=st["champion"],
                  entry=None)
        self._save()

    def _open(self) -> bool:
        st = self.state
        return bool(st["run_id"]) or st["stage"] in ("fit", "judge")

    def _run_block(self) -> None:
        st = self.state
        try:
            if st["kind"] == "seed":
                r = self._seed_block()
            elif st["kind"] == "trial":
                r = self._trial_block()
            else:
                r = self._full_block()
        except Exception as e:
            r = "error"
            self._fault("%s: %s" % (type(e).__name__, e))
            if st["run_id"]:
                try:
                    self.service.stop_run(st["run_id"])
                except Exception:
                    pass
        self._compose_entry(r)

    def _compose_entry(self, r: str) -> None:
        st = self.state
        iterations: List[Dict[str, Any]] = list(st["iterations"])
        status = "done"
        if r == "stop":
            status = "interrupted"
        elif r == "halt" or (r == "error" and not iterations):
            status = "failed"
        trial: Optional[Dict[str, Any]] = None
        if st["kind"] == "trial" and st["trial"] and r != "stop":
            trial = self._trial_result(r, iterations)
            if trial["outcome"] == "pass":
                knob, value = st["trial"]
                st["extras"].setdefault(knob, []).append(value)
        if status == "failed":
            st["failed_count"] += 1
        elif status == "done":
            st["failed_count"] = 0
        changed = st["champion"] != st["champion_before"]
        if st["kind"] == "full" and status == "done":
            st["plateau_count"] = 0 if changed else st["plateau_count"] + 1
        elif changed:
            st["plateau_count"] = 0
        if st["kind"] == "full":
            st["last_plan"] = dict(st["plan"])
        if status == "failed" and st["failed_count"] >= 3:
            st["halt"] = True
            self._fault("three failed blocks in a row")
        now = self.clock()
        entry = findings.new_entry(st["block"], st["kind"], status, _iso(st["block_started"]),
                                   _iso(now), st["stamp"], dict(st["plan"]), st["plan_source"])
        entry.update(plan_notes=list(st["plan_notes"]), iterations=iterations,
                     champion_before=st["champion_before"] or None,
                     champion_after=st["champion"] or None,
                     plateau=st["plateau_count"] >= self.cfg.plateau_blocks, trial=trial,
                     refused=list(st["refused"]), steering=st["steering"],
                     fault=st["fault"], advisor=st["advisor"])
        st.update(entry=entry, stage="boundary", run_id=None, fit_id=None, iteration=None)
        self._save()

    def _close_block(self) -> None:
        st = self.state
        entry = st["entry"]
        if self.log.last_block() < entry["block"]:
            self.log.append(entry)
        if st["halt"]:
            st.update(running=False, entry=None)
            self._save()
            return
        if entry["status"] == "interrupted":
            self._finish_stop()
            return
        self._plan_next(entry)

    # planning at the boundary

    def _fit_ok(self, fit_id: str) -> bool:
        return os.path.isfile(weights_path(self.data_dir, fit_id))

    def _plan_next(self, entry: Dict[str, Any]) -> None:
        st = self.state
        self._apply_steering()
        has = bool(st["champion"])
        plan: Dict[str, Any]
        refused: List[Dict[str, Any]] = []
        notes: List[str] = []
        advisor_info: Optional[Dict[str, Any]] = None
        source = "default"
        kind = "full"
        trial: Optional[List[Any]] = None
        tr = entry["trial"]
        if entry["kind"] == "trial" and tr and tr["outcome"] == "pass":
            plan, source, advisor_info = dict(entry["plan"]), entry["plan_source"], entry["advisor"]
            notes.append("trial passed: %s=%r now allowed" % (tr["knob"], tr["value"]))
        elif entry["kind"] == "trial" and tr:
            plan = dict(st["last_plan"] or self.advisor.default_plan(has))
            source = "fallback"
            reason = entry["fault"] or "labels per minute %s below floor %s" % (
                tr["labels_per_minute"], tr["floor"])
            refused.append({"knob": tr["knob"], "value": tr["value"], "reason": reason})
            notes.append("trial failed: fallback to the last plan")
        elif st["last_plan"] is None:
            plan = self.advisor.default_plan(has)
        else:
            plan, source, advisor_info, trial, refused, notes = self._advise(entry)
            if trial is not None:
                kind = "trial"
        st.update(block=st["block"] + 1, kind=kind, plan=plan, plan_source=source,
                  plan_notes=notes, refused=refused, trial=trial, advisor=advisor_info,
                  block_started=None, deadline=None, entry=None, stage="label", fault="",
                  iterations=[], run_id=None, fit_id=None, iteration=None)
        self._save()

    def _advise(self, entry: Dict[str, Any]) -> Any:
        st = self.state
        has = bool(st["champion"])
        entries, _ = self.log.read()
        plateau = st["plateau_count"] >= self.cfg.plateau_blocks
        last_plan: Dict[str, Any] = dict(st["last_plan"])
        try:
            advice = self.advisor.advise(st["block"] + 1, entries[-FLOOR_BLOCKS:], st["bounds"],
                                         st["extras"], st["pins"], st["notes"], plateau,
                                         last_plan, has)
        except Exception as e:
            return (last_plan, "fallback", None, None, [],
                    ["advisor raised %s: %s; kept the last plan" % (type(e).__name__, e)])
        proposed = dict(advice.plan) if isinstance(advice.plan, dict) else advice.plan
        if isinstance(proposed, dict):
            proposed.update(st["pins"])
        val = knobs.validate(proposed, last_plan, st["bounds"], st["extras"], self._fit_ok)
        notes: List[str] = list(val.notes)
        source = "advisor"
        if advice.source == "fallback":
            source = "fallback"
            notes.insert(0, str(advice.fallback_reason))
        info = {"model": advice.model, "prompt_digest": advice.prompt_digest,
                "reason": advice.reason, "seconds": advice.seconds}
        plan = dict(val.plan)
        trial: Optional[List[Any]] = None
        if val.trial is not None:
            trial = [val.trial[0], val.trial[1]]
            plan[val.trial[0]] = val.trial[1]
            notes.append("trial block for %s=%r" % (val.trial[0], val.trial[1]))
        return plan, source, info, trial, list(val.refused), notes

    # blocks

    def _full_block(self) -> str:
        st = self.state
        reserve = self.cfg.reserve_minutes * 60.0
        while True:
            if not self._open():
                if self._stop_requested():
                    return "stop"
                if st["deadline"] - self.clock() - reserve < MIN_RUN_S:
                    return "ok"
            r = self._iteration(True, reserve)
            if r != "ok":
                return r

    def _trial_block(self) -> str:
        st = self.state
        knob = st["trial"][0]
        if knob in knobs.FIT_KNOBS:
            if not self._open():
                last = st["last_run"]
                if not last:
                    self._fault("trial %s: no finished run to fit" % knob)
                    return "error"
                st.update(run_id=last["run_id"], stage="fit", iteration={
                    "run": last["run_id"], "positions": last["positions"],
                    "labels": last["labels"], "label_seconds": last["label_seconds"]})
                self._save()
            return self._iteration(True, 0.0)
        return self._iteration(False, 0.0)

    def _trial_result(self, r: str, iterations: List[Dict[str, Any]]) -> Dict[str, Any]:
        st = self.state
        knob, value = st["trial"]
        secs = sum(float(i["label_seconds"]) for i in iterations)
        labels = sum(int(i["labels"]) for i in iterations)
        lpm = round(labels * 60.0 / secs, 3) if secs > 0 else 0.0
        floor = self._throughput_floor()
        if r != "ok":
            ok = False
        elif knob in knobs.FIT_KNOBS:
            ok = any(i["fit"] for i in iterations)
        else:
            ok = floor is None or lpm >= floor
        return {"knob": knob, "value": value, "outcome": "pass" if ok else "fail",
                "labels_per_minute": lpm, "floor": floor}

    def _throughput_floor(self) -> Optional[float]:
        entries, _ = self.log.read()
        rates: List[float] = []
        for e in [x for x in entries if x.get("kind") == "full"][-FLOOR_BLOCKS:]:
            secs = sum(float(i.get("label_seconds") or 0) for i in e.get("iterations") or [])
            labels = sum(int(i.get("labels") or 0) for i in e.get("iterations") or [])
            if secs > 0:
                rates.append(labels * 60.0 / secs)
        if not rates:
            return None
        return round(self.cfg.throughput_share * statistics.median(rates), 3)

    def _seed_block(self) -> str:
        st = self.state
        for cand in self.cfg.candidates:
            if any(i["fit"] == cand for i in st["iterations"]):
                continue
            if self._stop_requested():
                return "stop"
            st.update(stage="judge", fit_id=cand)
            self._save()
            champ_w = weights_path(self.data_dir, st["champion"]) if st["champion"] else None
            j = self.judge.judge(weights_path(self.data_dir, cand), champ_w, self._stop_event)
            became = False
            if not j.stopped:
                self._judge_notes(cand, j)
                if j.passed:
                    became = True
                    self._promote(cand, j)
            st["iterations"].append(findings.new_iteration(
                fit=cand, judge_random=j.line_random, judge_champion=j.line_champion,
                became_champion=became))
            st.update(stage="label", fit_id=None)
            self._save()
            if j.stopped:
                return "stop"
        st["seed_done"] = True
        return "ok"

    # one iteration: label, fit, judge

    def _disk_low(self) -> bool:
        free = float(self._disk_free_gb())
        if free < self.cfg.disk_floor_gb:
            self.state["halt"] = True
            self._fault("disk free %.1f GB is below the %g GB floor" % (free, self.cfg.disk_floor_gb))
            return True
        return False

    def _run_config(self, reserve_s: float) -> Dict[str, Any]:
        st = self.state
        frag = knobs.run_fragment(st["plan"])
        for name in _WEIGHT_KNOBS:
            if frag.get(name) == "champion":
                frag[name] = st["champion"]
        hours = max(st["deadline"] - self.clock() - reserve_s, MIN_RUN_S) / 3600.0
        frag.update(hours=hours, run_seed=self.cfg.run_seed_base + st["seed_counter"])
        return frag

    def _iteration(self, fit_wanted: bool, reserve_s: float) -> str:
        """Returns ok (iteration closed), stop, error or halt."""
        st = self.state
        if st["stage"] == "label":
            r = self._label(fit_wanted, reserve_s)
            if r != "continue":
                return r
        if st["stage"] == "fit":
            r = self._fit_stage()
            if r != "continue":
                return r
        return self._judge_stage()

    def _close_iteration(self) -> None:
        st = self.state
        it = st["iteration"] or {}
        st["iterations"].append(findings.new_iteration(**{
            k: it[k] for k in findings.ITERATION_KEYS if k in it}))
        st.update(iteration=None, run_id=None, fit_id=None, stage="label")
        self._save()

    def _label(self, fit_wanted: bool, reserve_s: float) -> str:
        st = self.state
        service = self.service
        if self._open():  # resumed after a restart
            run_id = str(st["run_id"])
            s = service.run_status(run_id)
            if "error" in s:
                self._fault("run_status: %s" % s["error"])
                return "error"
            if s.get("state") == "interrupted" and self.clock() < st["deadline"]:
                rr = service.resume_run(run_id)
                if "error" in rr:
                    self._fault("resume_run: %s" % rr["error"])
                    return "error"
        else:
            if self._disk_low():
                return "halt"
            cfg = self._run_config(reserve_s)
            st["seed_counter"] += 1
            self._save()
            reply = service.start_run(cfg)
            if "error" in reply:
                self._fault("start_run: %s" % reply["error"])
                return "error"
            run_id = str(reply["run_id"])
            st.update(run_id=run_id, iteration={"run": run_id}, stage="label")
            if reply.get("stamp"):
                st["stamp"] = reply["stamp"]
            self._save()
        final = self._await_run(run_id)
        if "error" in final:
            self._fault("run_status: %s" % final["error"])
            return "error"
        if final.get("state") == "failed":
            self._fault("run %s failed: %s" % (run_id, final.get("last_error", "")))
            return "error"
        positions = int(final.get("positions_done", 0))
        it = st["iteration"] or {"run": run_id}
        it.update(run=run_id, positions=positions, labels=int(final.get("labels", 0)),
                  label_seconds=float(final.get("elapsed_s", 0.0)))
        st["iteration"] = it
        st["last_run"] = {k: it[k] for k in ("positions", "labels", "label_seconds")}
        st["last_run"]["run_id"] = run_id
        if self._stop_requested():
            self._close_iteration()
            return "stop"
        if not fit_wanted:
            self._close_iteration()
            return "ok"
        if positions < self.cfg.min_positions:
            self._note("run %s: %d positions is below %d; not fitted"
                       % (run_id, positions, self.cfg.min_positions))
            self._close_iteration()
            return "ok"
        st["stage"] = "fit"
        self._save()
        return "continue"

    def _await_run(self, run_id: str) -> Dict[str, Any]:
        sent = False
        while True:
            s: Dict[str, Any] = self.service.run_status(run_id)
            if "error" in s or s.get("state") not in ACTIVE:
                return s
            if not sent and (self._stop_requested() or self.clock() >= self.state["deadline"]):
                self.service.stop_run(run_id)
                sent = True
            self.sleep(self.cfg.poll_s)

    def _late(self) -> bool:
        return self.clock() >= self.state["deadline"] + self.cfg.grace_minutes * 60.0

    def _fit_stage(self) -> str:
        st = self.state
        it = st["iteration"]
        if self._stop_requested():
            self._close_iteration()
            return "stop"
        if self._late():
            self._note("run %s: fit skipped, past the block deadline and grace" % it["run"])
            self._close_iteration()
            return "ok"
        reply = self.service.fit({"runs": [it["run"]], **knobs.fit_fragment(st["plan"])})
        if "error" in reply:
            self._fault("fit: %s" % reply["error"])
            return "error"
        fit_id = str(reply["fit_id"])
        st["fit_id"] = fit_id
        for key in ("stamp", "feature_set"):
            if reply.get(key):
                st[key] = reply[key]
        self._save()
        while True:
            s: Dict[str, Any] = self.service.run_status(fit_id)
            if "error" in s or s.get("state") not in LIVE_FIT:
                break
            self.sleep(self.cfg.poll_s)
        if "error" in s or s.get("state") != "done":
            self._fault("fit %s: %s" % (fit_id, s.get("error") or s.get("last_error") or s.get("state")))
            return "error"
        report = self.service.get_report(fit_id)
        agreement = report.get("agreement") or {}
        it.update(fit=fit_id, agreement_fitted=float(agreement.get("fitted", 0.0)),
                  agreement_heldout=float(agreement.get("heldout", 0.0)))
        st["stage"] = "judge"
        self._save()
        return "continue"

    def _judge_stage(self) -> str:
        st = self.state
        it = st["iteration"]
        fit_id = str(it["fit"])
        if self._stop_requested():
            self._close_iteration()
            return "stop"
        if self._late():
            self._note("fit %s: judge skipped, past the block deadline and grace" % fit_id)
            self._close_iteration()
            return "ok"
        champ_w = weights_path(self.data_dir, st["champion"]) if st["champion"] else None
        j = self.judge.judge(weights_path(self.data_dir, fit_id), champ_w, self._stop_event)
        it.update(judge_random=j.line_random, judge_champion=j.line_champion)
        if j.stopped:
            self._close_iteration()
            return "stop"
        self._judge_notes(fit_id, j)
        if j.passed:
            it["became_champion"] = True
            self._promote(fit_id, j)
        self._close_iteration()
        return "ok"

    def _judge_notes(self, fit_id: str, j: Any) -> None:
        if "error" in (j.outcome_random, j.outcome_champion):
            self._note("fit %s: the judge hit an error" % fit_id)
        elif "cap" in (j.outcome_random, j.outcome_champion):
            self._note("fit %s: the judge hit its cap; champion kept" % fit_id)

    def _promote(self, fit_id: str, j: Any) -> None:
        st = self.state
        judge_mod.save_champion(self.data_dir, fit_id, st["stamp"], st["feature_set"],
                                j.line_random, j.line_champion, st["block"])
        st["champion"] = fit_id
