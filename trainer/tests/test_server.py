import asyncio
import base64
import hashlib
import threading
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
from pathlib import Path
from typing import Any, Dict, List

from trainer.config import RunConfig
from trainer.farm import Farm
from trainer.fit import FitError
from trainer.store import Store
from trainer.server import (BearerMiddleware, Service, TokenError, acquire_serve_lock,
                            build_app, build_mcp, check_bearer, load_token, numpy_version)

STUB = str(Path(__file__).resolve().parent / "stub_worker.py")
STAMP = "r7-stub"
ROOT = Path(__file__).resolve().parent.parent.parent

try:
    import mcp.server.mcpserver  # noqa: F401
    HAVE_MCP = True
except ImportError:
    HAVE_MCP = False


def stub_farm(cfg: RunConfig, log_dir: Path) -> Farm:
    return Farm([sys.executable, "-I", STUB, "--stamp", STAMP], cfg.workers, timeout=30.0,
                start_timeout=30.0)


def cfg_dict(**over: Any) -> Dict[str, Any]:
    d = RunConfig(positions=40, k=3, determinizations=4, workers=2, batch=20,
                  run_seed=5).to_dict()
    d.update(over)
    return d


async def call_asgi(app: Any, headers: List[Any]) -> int:
    sent: List[Dict[str, Any]] = []

    async def receive() -> Dict[str, Any]:
        return {"type": "http.request", "body": b""}

    async def send(msg: Dict[str, Any]) -> None:
        sent.append(msg)

    await app({"type": "http", "headers": headers, "path": "/mcp"}, receive, send)
    return int(sent[0]["status"])


class BearerTest(unittest.TestCase):
    def status(self, headers: List[Any]) -> int:
        async def inner(scope: Any, receive: Any, send: Any) -> None:
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b"ok"})
        return asyncio.run(call_asgi(BearerMiddleware(inner, "s3cret"), headers))

    def test_missing_token_is_401(self) -> None:
        self.assertEqual(self.status([]), 401)

    def test_wrong_token_is_401(self) -> None:
        self.assertEqual(self.status([(b"authorization", b"Bearer nope")]), 401)
        self.assertEqual(self.status([(b"authorization", b"s3cret")]), 401)

    def test_right_token_passes(self) -> None:
        self.assertEqual(self.status([(b"authorization", b"Bearer s3cret")]), 200)

    def test_check_bearer(self) -> None:
        self.assertTrue(check_bearer("bearer s3cret", "s3cret"))
        self.assertFalse(check_bearer("Bearer ", "s3cret"))


class TokenTest(unittest.TestCase):
    def test_load_token_strips_and_rejects_empty(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "token"
            with self.assertRaises(TokenError):
                load_token(p)
            p.write_text("  \n", encoding="utf-8")
            with self.assertRaises(TokenError):
                load_token(p)
            p.write_text(" abc \n", encoding="utf-8")
            self.assertEqual(load_token(p), "abc")

    def test_serve_exits_2_without_token(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            env = dict(os.environ, TRAINER_TOKEN_FILE=str(Path(d) / "missing"))
            p = subprocess.run([sys.executable, "-I", str(ROOT / "trainer"), "serve",
                                "--data", d], env=env, capture_output=True, text=True,
                               timeout=60)
            self.assertEqual(p.returncode, 2)
            self.assertEqual(len(p.stderr.strip().splitlines()), 1)
            self.assertEqual(p.stdout, "")


class ServeLockTest(unittest.TestCase):
    def test_second_lock_refused_and_released(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            first = acquire_serve_lock(Path(d))
            with self.assertRaises(RuntimeError):
                acquire_serve_lock(Path(d))
            first.close()
            acquire_serve_lock(Path(d)).close()

    def test_second_serve_exits_1_and_touches_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            data = Path(d) / "data"
            tmp = data / "runs" / "r1" / "labels-00000.jsonl.tmp"
            tmp.parent.mkdir(parents=True)
            tmp.write_text("in flight", encoding="utf-8")
            token = Path(d) / "token"
            token.write_text("s3cret", encoding="utf-8")
            held = acquire_serve_lock(data)
            try:
                env = dict(os.environ, TRAINER_TOKEN_FILE=str(token))
                p = subprocess.run([sys.executable, "-I", str(ROOT / "trainer"), "serve",
                                    "--data", str(data), "--port", "0"], env=env,
                                   capture_output=True, text=True, timeout=60)
            finally:
                held.close()
            self.assertEqual(p.returncode, 1)
            self.assertIn("another serve", p.stderr)
            self.assertNotIn("s3cret", p.stderr + p.stdout)
            self.assertTrue(tmp.is_file())
            self.assertFalse((data / "trainer.db").exists())


class ServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.svc = self.service()

    def service(self, sync_fn: Any = None) -> Service:
        s = Service(self.root / "data", self.root / "me", farm_factory=stub_farm,
                    stamp_fn=lambda: STAMP, sync_fn=sync_fn)
        self.addCleanup(s.close)
        return s

    def wait(self, run_id: str, states: Any = ("done", "stopped", "failed"),
             svc: Any = None) -> Dict[str, Any]:
        svc = svc or self.svc
        for _ in range(600):
            st = svc.run_status(run_id)
            if st["state"] in states:
                svc.join(30)
                return svc.run_status(run_id)
            time.sleep(0.1)
        self.fail("run did not finish")
        return {}

    def test_run_to_done_report_and_sample(self) -> None:
        r = self.svc.start_run(cfg_dict())
        self.assertNotIn("error", r)
        rid = r["run_id"]
        st = self.wait(rid)
        self.assertEqual(st["state"], "done", st)
        self.assertEqual((st["positions_done"], st["positions_total"], st["batches"]),
                         (40, 40, 2))
        self.assertEqual(len(st["digest"]), 64)
        self.assertGreater(st["labels"], 0)
        self.assertGreater(st["rollouts"], 0)
        self.assertGreater(st["last_checkpoint"], 0)
        self.assertIn("labels_per_hour", st)
        self.assertIn("rollouts_per_min", st)
        rep = self.svc.get_report(rid)
        self.assertEqual(rep["digest"], st["digest"])
        self.assertEqual(rep["positions"], 40)
        self.assertTrue((self.root / "data" / "runs" / rid / "report.json").is_file())
        self.assertEqual([x["run_id"] for x in self.svc.list_runs()["runs"]], [rid])
        s1 = self.svc.sample_positions(rid, 3, 9)
        self.assertEqual(len(s1["positions"]), 3)
        self.assertEqual(s1, self.svc.sample_positions(rid, 3, 9))
        for p in s1["positions"]:
            self.assertIsInstance(p["round"], int)
            self.assertIsInstance(p["turn"], int)
            self.assertEqual(len(p["hand"]), 5)
            self.assertEqual(set(p["hand"][0]), {"instance", "card", "name"})
            means = [c["mean"] for c in p["candidates"]]
            self.assertEqual(means, sorted(means, reverse=True))

    def test_start_run_resolves_fit_ids_and_refuses_unknown(self) -> None:
        for field in ("rollout_weights", "generator_weights"):
            r = self.svc.start_run(cfg_dict(**{field: "nofit"}))
            self.assertIn("unknown fit", r["error"])
        self.svc.store.create_fit("f1", {}, STAMP, "stub-1", [], state="running")
        self.assertIn("not done", self.svc.start_run(cfg_dict(rollout_weights="f1"))["error"])
        # a finished fit under another stamp is refused
        old = self.root / "data" / "fits" / "f1"
        old.mkdir(parents=True)
        (old / "linear_weights.json").write_text("{}", encoding="utf-8")
        self.svc.store.db.execute("UPDATE fits SET state = 'done', stamp = 'r7-old'")
        self.svc.store.db.commit()
        self.assertIn("stamp", self.svc.start_run(cfg_dict(rollout_weights="f1"))["error"])
        (old / "linear_weights.json").unlink()
        old.rmdir()
        self.svc.store.db.execute("UPDATE fits SET state = 'running', stamp = ?", (STAMP,))
        self.svc.store.db.commit()
        self.svc.store.db.execute("UPDATE fits SET state = 'done'")
        self.svc.store.db.commit()
        self.assertIn("no weights file",
                      self.svc.start_run(cfg_dict(rollout_weights="f1"))["error"])
        fits = self.root / "data" / "fits" / "f1"
        fits.mkdir(parents=True)
        (fits / "linear_weights.json").write_text("{}", encoding="utf-8")
        r = self.svc.start_run(cfg_dict(positions=20, rollout_weights="f1"))
        self.assertNotIn("error", r)
        self.assertEqual(self.wait(r["run_id"])["state"], "done")

    # fits

    def fit_service(self, gate: Any = None, fail: bool = False) -> Service:
        """A service whose learner is a stand-in that writes the two files (no numpy)."""
        def fake_fit(store: Store, fit_id: str, cfg: Any, out_dir: Path, repo_root: Path,
                     should_stop: Any = None) -> Dict[str, Any]:
            while gate is not None and not gate.wait(0.05):
                if should_stop is not None and should_stop():
                    raise FitError("fit stopped")
            if fail:
                raise FitError("numpy missing")
            out_dir.mkdir(parents=True, exist_ok=True)
            (out_dir / "linear_weights.json").write_text(
                json.dumps({"fit": {"id": fit_id}, "weights": {"a": 1}}), encoding="utf-8")
            report = {"fit_id": fit_id, "pairs": {"total": 7}}
            (out_dir / "report.json").write_text(json.dumps(report), encoding="utf-8")
            return report
        s = Service(self.root / "data2", self.root / "me", farm_factory=stub_farm,
                    stamp_fn=lambda: STAMP, fit_fn=fake_fit)
        self.addCleanup(s.close)
        return s

    def done_run(self, svc: Service, **over: Any) -> str:
        rid = svc.start_run(cfg_dict(positions=20, **over))["run_id"]
        for _ in range(600):
            if svc.run_status(rid)["state"] == "done":
                svc.join(30)
                return rid
            time.sleep(0.1)
        self.fail("run did not finish")
        return rid

    def wait_fit(self, svc: Service, fit_id: str) -> Dict[str, Any]:
        for _ in range(600):
            st = svc.run_status(fit_id)
            if st["state"] in ("done", "failed"):
                svc.join_fit(30)
                return st
            time.sleep(0.05)
        self.fail("fit did not finish")
        return {}

    def test_fit_job_status_list_report_and_artifacts(self) -> None:
        svc = self.fit_service()
        rid = self.done_run(svc)
        r = svc.fit({"runs": [rid], "iterations": 10})
        self.assertNotIn("error", r, r)
        fid = r["fit_id"]
        st = self.wait_fit(svc, fid)
        self.assertEqual((st["kind"], st["state"], st["runs"], st["pairs"]),
                         ("fit", "done", [rid], 7))
        self.assertEqual(st["last_error"], "")
        self.assertEqual(svc.get_report(fid), {"fit_id": fid, "pairs": {"total": 7}})
        listed = {x["run_id"]: x for x in svc.list_runs()["runs"]}
        self.assertEqual(listed[fid]["kind"], "fit")
        self.assertEqual(listed[fid]["state"], "done")
        self.assertIn(rid, listed)
        art = svc.get_artifact(fid, "weights")
        raw = base64.b64decode(art["base64"])
        path = self.root / "data2" / "fits" / fid / "linear_weights.json"
        self.assertEqual(raw, path.read_bytes())
        self.assertEqual(art["bytes"], len(raw))
        self.assertEqual(art["sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(svc.get_artifact(fid)["sha256"], art["sha256"])
        rep = svc.get_artifact(fid, "report")
        self.assertEqual(json.loads(base64.b64decode(rep["base64"]))["fit_id"], fid)
        # a finished fit can be named by a run
        self.assertNotIn("error", svc.start_run(cfg_dict(positions=20, rollout_weights=fid)))

    def test_get_artifact_errors_and_no_traversal(self) -> None:
        svc = self.fit_service()
        rid = self.done_run(svc)
        fid = svc.fit({"runs": [rid]})["fit_id"]
        self.wait_fit(svc, fid)
        secret = self.root / "data2" / "secret.txt"
        secret.write_text("x", encoding="utf-8")
        for bad_id in ("nofit", "", "..", "../x", fid + "/..", "a/b", "..\\x", rid):
            self.assertIn("error", svc.get_artifact(bad_id, "weights"), bad_id)
        for bad_name in ("nope", "../../secret.txt", "linear_weights.json", "", "report.json"):
            self.assertIn("error", svc.get_artifact(fid, bad_name), bad_name)
        self.assertNotIn("error", svc.get_artifact(fid, "report"))
        (self.root / "data2" / "fits" / fid / "report.json").unlink()
        self.assertIn("no report file", svc.get_artifact(fid, "report")["error"])

    def test_fit_refusals(self) -> None:
        svc = self.fit_service()
        rid = self.done_run(svc)
        self.assertIn("no such run", svc.fit({"runs": ["nope"]})["error"])
        self.assertIn("runs", svc.fit({"runs": []})["error"])
        self.assertIn("holdout", svc.fit({"runs": [rid], "holdout": 0.5})["error"])
        self.assertIn("unknown field", svc.fit({"runs": [rid], "bogus": 1})["error"])
        self.assertIn("iterations", svc.fit({"runs": [rid], "iterations": 0})["error"])
        slow = svc.start_run(cfg_dict(positions=2000, workers=1, batch=1))["run_id"]
        self.assertIn("only done or stopped", svc.fit({"runs": [slow]})["error"])
        svc.stop_run(slow)
        self.wait(slow, ("stopped", "done", "failed"), svc)

    def test_mixed_stamps_are_refused_by_name(self) -> None:
        svc = self.fit_service()
        rid = self.done_run(svc)
        other = svc.store.create_run({"positions": 1}, "r7-other", "c", state="done")
        svc.store.set_feature_set(other, "stub-1")
        err = svc.fit({"runs": [rid, other]})["error"]
        self.assertIn(other, err)
        self.assertIn("stamp", err)

    def test_one_fit_at_a_time_and_a_run_may_start_meanwhile(self) -> None:
        gate = threading.Event()
        svc = self.fit_service(gate=gate)
        rid = self.done_run(svc)
        first = svc.fit({"runs": [rid]})
        self.assertNotIn("error", first)
        self.assertIn(svc.run_status(first["fit_id"])["state"], ("queued", "running"))
        self.assertIn("is active", svc.fit({"runs": [rid]})["error"])
        second_run = svc.start_run(cfg_dict(positions=20))
        self.assertNotIn("error", second_run)
        gate.set()
        self.assertEqual(self.wait_fit(svc, first["fit_id"])["state"], "done")
        self.assertNotIn("error", svc.fit({"runs": [rid]}))
        svc.join_fit(30)
        self.wait(second_run["run_id"], svc=svc)

    def test_resume_is_refused_while_a_live_fit_reads_the_run(self) -> None:
        gate = threading.Event()
        svc = self.fit_service(gate=gate)
        rid = self.done_run(svc)
        fid = svc.fit({"runs": [rid]})["fit_id"]
        svc.store.set_state(rid, "stopped")  # as if the run had been stopped before the fit
        err = svc.resume_run(rid)["error"]
        self.assertIn("fit %s" % fid, err)
        gate.set()
        self.assertEqual(self.wait_fit(svc, fid)["state"], "done")
        self.assertNotIn("error", svc.resume_run(rid))
        svc.join(30)

    def test_a_late_fit_finish_does_not_overwrite_a_failed_fit(self) -> None:
        started = threading.Event()
        released = threading.Event()

        def late_fit(store: Store, fit_id: str, cfg: Any, out_dir: Path, repo_root: Path,
                     should_stop: Any = None) -> Dict[str, Any]:
            started.set()
            released.wait(30)  # ignores should_stop: a stuck learner that finishes late
            return {"fit_id": fit_id, "pairs": {"total": 1}}
        svc = Service(self.root / "data2", self.root / "me", farm_factory=stub_farm,
                      stamp_fn=lambda: STAMP, fit_fn=late_fit)
        self.addCleanup(svc.close)
        rid = self.done_run(svc)
        fid = svc.fit({"runs": [rid]})["fit_id"]
        self.assertTrue(started.wait(30))
        svc.store.fail_live_fits("service shut down mid-fit")
        released.set()
        svc.join_fit(30)
        row = svc.store.get_fit(fid) or {}
        self.assertEqual(row["state"], "failed")
        self.assertEqual(row["last_error"], "service shut down mid-fit")
        self.assertFalse(row["report"])

    def test_failed_fit_records_the_error_and_serves_nothing(self) -> None:
        svc = self.fit_service(fail=True)
        rid = self.done_run(svc)
        fid = svc.fit({"runs": [rid]})["fit_id"]
        st = self.wait_fit(svc, fid)
        self.assertEqual(st["state"], "failed")
        self.assertIn("numpy missing", st["last_error"])
        self.assertIn("error", svc.get_report(fid))
        self.assertIn("not done", svc.get_artifact(fid)["error"])
        self.assertIn("not done", svc.start_run(cfg_dict(rollout_weights=fid))["error"])

    def test_live_fit_is_failed_at_start(self) -> None:
        svc = self.fit_service()
        svc.store.create_fit("stale", {}, STAMP, "stub-1", [], state="running")
        svc.close()
        again = Service(self.root / "data2", self.root / "me", farm_factory=stub_farm,
                        stamp_fn=lambda: STAMP)
        self.addCleanup(again.close)
        st = again.run_status("stale")
        self.assertEqual(st["state"], "failed")
        self.assertIn("restarted", st["last_error"])
        self.assertIsNone(again.store.active_fit_id())

    def test_close_stops_a_hung_fit(self) -> None:
        gate = threading.Event()
        svc = self.fit_service(gate=gate)
        rid = self.done_run(svc)
        fid = svc.fit({"runs": [rid]})["fit_id"]
        t0 = time.time()
        svc.close(timeout=1.0)
        self.assertLess(time.time() - t0, 25)
        svc.join_fit(30)
        check = Store(self.root / "data2")
        self.addCleanup(check.close)
        fit = check.get_fit(fid) or {}
        self.assertEqual(fit["state"], "failed")
        self.assertIsNone(check.active_fit_id())

    def test_health_reports_numpy_or_none(self) -> None:
        self.assertIsInstance(self.svc.health()["numpy"], str)
        with mock.patch("importlib.metadata.version", side_effect=Exception("absent")):
            self.assertEqual(numpy_version(), "none")

    def test_report_failure_keeps_run_done_and_report_is_rebuilt(self) -> None:
        with mock.patch.object(Service, "_write_report", side_effect=OSError("disk full")):
            rid = self.svc.start_run(cfg_dict())["run_id"]
            st = self.wait(rid)
        self.assertEqual(st["state"], "done", st)
        self.assertIn("report not written", st["last_error"])
        self.assertIn("disk full", st["last_error"])
        self.assertFalse((self.root / "data" / "runs" / rid / "report.json").exists())
        rep = self.svc.get_report(rid)
        self.assertEqual(rep["digest"], st["digest"])
        self.assertEqual(rep["positions"], 40)

    def test_start_refused_while_active_and_bad_config(self) -> None:
        self.assertIn("error", self.svc.start_run({"positions": 0}))
        self.assertIn("error", self.svc.start_run({"bogus": 1}))
        rid = self.svc.start_run(cfg_dict(positions=400))["run_id"]
        again = self.svc.start_run(cfg_dict())
        self.assertIn("is active", again.get("error", ""))
        self.assertIn("is active", self.svc.sync_code("abcdef1", inbox_file="x.b")["error"])
        self.svc.stop_run(rid)
        self.assertEqual(self.wait(rid)["state"], "stopped")

    def test_stop_then_resume_matches_whole(self) -> None:
        whole = self.svc.start_run(cfg_dict(positions=60))["run_id"]
        want = self.wait(whole)["digest"]
        rid = self.svc.start_run(cfg_dict(positions=60))["run_id"]
        # The flag is set before the thread has even started its workers, so the run must
        # end stopped (never done): no vacuous branch.
        self.assertEqual(self.svc.stop_run(rid)["state"], "stopping")
        st = self.wait(rid, ("stopped", "done"))
        self.assertEqual(st["state"], "stopped")
        self.assertIn("error", self.svc.stop_run(rid))
        self.assertNotIn("error", self.svc.resume_run(rid))
        st = self.wait(rid, ("done",))
        self.assertEqual(st["state"], "done")
        self.assertEqual(st["digest"], want)
        self.assertIn("error", self.svc.resume_run(rid))

    def test_stop_after_finish_keeps_done(self) -> None:
        rid = self.svc.start_run(cfg_dict(positions=20))["run_id"]
        self.assertEqual(self.wait(rid)["state"], "done")
        self.assertIn("error", self.svc.stop_run(rid))
        self.assertEqual(self.svc.run_status(rid)["state"], "done")
        self.assertFalse(self.svc.store.request_stop(rid))

    def test_no_live_state_without_a_thread(self) -> None:
        rid = self.svc.store.create_run(cfg_dict(), STAMP, "abc", state="stopping")
        self.assertEqual(self.svc.stop_run(rid)["state"], "stopped")
        run = self.svc.store.create_run(cfg_dict(positions=5), STAMP, "abc", state="running")
        self.svc._finalize(self.svc.store, run, threading.Event())
        self.assertEqual(self.svc.run_status(run)["state"], "failed")
        run2 = self.svc.store.create_run(cfg_dict(positions=5), STAMP, "abc", state="stopping")
        flag = threading.Event()
        flag.set()
        self.svc._finalize(self.svc.store, run2, flag)
        self.assertEqual(self.svc.run_status(run2)["state"], "stopped")

    def test_queued_run_is_interrupted_at_start(self) -> None:
        rid = self.svc.store.create_run(cfg_dict(), STAMP, "abc", state="queued")
        s2 = self.service()
        self.assertEqual(s2.interrupted, [rid])
        self.assertNotIn("error", s2.start_run(cfg_dict(positions=20)))
        s2.join(60)

    def test_sync_does_not_hold_the_lock(self) -> None:
        entered = threading.Event()
        release = threading.Event()

        def slow(commit: str, bundle: str, inbox: str, **kw: Any) -> Dict[str, Any]:
            entered.set()
            release.wait(30)
            return {"commit": commit, "stamp": STAMP, "import_s": 0.0}

        svc = self.service(slow)
        result: List[Dict[str, Any]] = []
        t = threading.Thread(target=lambda: result.append(svc.sync_code("a" * 40, "", "x.b")))
        t.start()
        try:
            self.assertTrue(entered.wait(30))
            t0 = time.monotonic()
            self.assertIn("error", svc.run_status("nope"))
            self.assertTrue(svc.health()["syncing"])
            self.assertLess(time.monotonic() - t0, 5.0)
            self.assertIn("sync", svc.start_run(cfg_dict())["error"])
            self.assertIn("in progress", svc.sync_code("a" * 40, "", "x.b")["error"])
        finally:
            release.set()
            t.join(30)
        self.assertEqual(result[0]["commit"], "a" * 40)
        self.assertFalse(svc.health()["syncing"])
        self.assertNotIn("error", svc.start_run(cfg_dict(positions=20)))
        svc.join(60)

    def test_close_stops_a_hung_run(self) -> None:
        def hung(cfg: RunConfig, log_dir: Path) -> Farm:
            return Farm([sys.executable, "-I", STUB, "--stamp", STAMP, "--hang-after", "0"],
                        1, timeout=60.0, start_timeout=30.0)

        svc = Service(self.root / "data2", self.root / "me", farm_factory=hung,
                      stamp_fn=lambda: STAMP)
        rid = svc.start_run(cfg_dict(workers=1))["run_id"]
        for _ in range(100):
            if svc.run_status(rid)["state"] == "running":
                break
            time.sleep(0.1)
        t0 = time.monotonic()
        svc.close(timeout=0.5)
        self.assertLess(time.monotonic() - t0, 25.0)
        store = Store(self.root / "data2", recover_on_open=False)
        try:
            run = store.get_run(rid)
            assert run is not None
            self.assertEqual(run["state"], "interrupted")
        finally:
            store.close()

    def test_interrupted_on_start_and_resume(self) -> None:
        rid = self.svc.store.create_run(cfg_dict(), STAMP, "abc", state="running")
        s2 = self.service()
        self.assertEqual(s2.interrupted, [rid])
        self.assertEqual(s2.health()["interrupted_at_start"], [rid])
        self.assertEqual(s2.run_status(rid)["state"], "interrupted")
        self.assertNotIn("error", s2.resume_run(rid))
        s2.join(60)

    def test_unknown_run_and_health(self) -> None:
        for fn in (self.svc.run_status, self.svc.stop_run, self.svc.resume_run,
                   self.svc.get_report, self.svc.sample_positions):
            self.assertIn("error", fn("nope"))
        h = self.svc.health()
        self.assertIsNone(h["active_run"])
        self.assertIn("uptime_s", h)
        for key in ("mcp", "commit", "workers_busy", "workers_total", "godot", "gpu"):
            self.assertIn(key, h)
        json.dumps(h)

    def test_sync_code_passes_active_run(self) -> None:
        seen: Dict[str, Any] = {}

        def fake(commit: str, bundle: str, inbox: str, **kw: Any) -> Dict[str, Any]:
            seen.update(kw, commit=commit)
            return {"commit": commit, "stamp": STAMP, "import_s": 0.0}

        svc = self.service(fake)
        self.assertEqual(svc.sync_code("abcdef1", inbox_file="a.bundle")["commit"], "abcdef1")
        self.assertIsNone(seen["run_active"])
        self.assertEqual(seen["root"], self.root / "me")


NEW = "b" * 40
OLD = "a" * 40


class RestartAfterSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.queue = self.root / "trainer" / "queue"
        self.queue.mkdir(parents=True)
        self.diffs: List[List[str]] = []

    def service(self, changed: str = "trainer/server.py\n", windows: bool = True,
                queue: Any = "default") -> Service:
        def run(argv: List[str], cwd: Any, env: Any) -> Any:
            self.diffs.append(argv)
            return 0, changed

        def sync(commit: str, bundle: str, inbox: str, **kw: Any) -> Dict[str, Any]:
            return {"commit": commit, "stamp": STAMP, "import_s": 0.0}

        s = Service(self.root / "data", self.root / "me", farm_factory=stub_farm,
                    stamp_fn=lambda: STAMP, sync_fn=sync, run_fn=run,
                    commit_fn=lambda: OLD, is_windows=windows,
                    queue_dir=self.queue if queue == "default" else queue)
        self.addCleanup(s.close)
        return s

    def test_scheduled_job_file(self) -> None:
        out = self.service().sync_code(NEW, inbox_file="x.bundle")
        self.assertEqual(out["restart"], "scheduled")
        self.assertEqual(self.diffs[-1][-4:], [OLD, NEW, "--", "trainer"])
        self.assertIn("diff", self.diffs[-1])
        jobs = sorted(self.queue.iterdir())
        self.assertEqual(len(jobs), 1)
        self.assertRegex(jobs[0].name, r"^restart-mcp-\d{8}-\d{6}-\d{3}\.cmd$")
        text = jobs[0].read_bytes().decode("ascii")
        self.assertIn("\r\n", text)
        self.assertIn("taskkill /PID %d /F" % os.getpid(), text)
        lines = text.splitlines()
        self.assertTrue(any(ln.startswith("ping -n") for ln in lines))
        self.assertTrue(lines[-1].startswith("call "))
        self.assertTrue(lines[-1].endswith("autostart/start-mcp.cmd")
                        or lines[-1].endswith("autostart\\start-mcp.cmd"))
        self.assertLess([i for i, ln in enumerate(lines) if ln.startswith("ping")][0],
                        [i for i, ln in enumerate(lines) if "taskkill" in ln][0])

    def test_not_needed_when_trainer_unchanged(self) -> None:
        out = self.service(changed="").sync_code(NEW, inbox_file="x.bundle")
        self.assertEqual(out["restart"], "not needed")
        self.assertEqual(list(self.queue.iterdir()), [])
        same = self.service(changed="trainer/x.py").sync_code(OLD, inbox_file="x.bundle")
        self.assertEqual(same["restart"], "not needed")

    def test_needed_without_queue_or_off_windows(self) -> None:
        self.assertEqual(self.service(windows=False).sync_code(NEW, inbox_file="x")["restart"],
                         "needed")
        self.assertEqual(list(self.queue.iterdir()), [])
        gone = self.service(queue=self.root / "nope")
        self.assertEqual(gone.sync_code(NEW, inbox_file="x")["restart"], "needed")

    def test_failed_sync_has_no_restart_key(self) -> None:
        s = self.service()
        s._sync_fn = lambda *a, **k: {"error": "boom"}
        self.assertEqual(s.sync_code(NEW, inbox_file="x"), {"error": "boom"})

    def test_new_runs_record_the_service_commit(self) -> None:
        s = self.service()
        rid = s.start_run(cfg_dict(positions=20))["run_id"]
        s.join(60)
        run = s.store.get_run(rid)
        assert run is not None
        self.assertEqual(run["commit"], OLD)
        self.assertEqual(s.health()["service_commit"], OLD)
        self.assertIn("commit", s.health())


class ProbeAndRateTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.svc = Service(self.root / "data", self.root / "me", farm_factory=stub_farm,
                           stamp_fn=lambda: STAMP, commit_fn=lambda: OLD)
        self.addCleanup(self.svc.close)

    def test_probe_caches_only_non_empty(self) -> None:
        answers = iter(["", "", "Godot 4.6.3"])
        calls: List[int] = []

        def fn() -> str:
            calls.append(1)
            return next(answers)

        self.assertEqual(self.svc._probe("godot", fn), "")
        self.assertEqual(self.svc._probe("godot", fn), "")
        self.assertEqual(self.svc._probe("godot", fn), "Godot 4.6.3")
        self.assertEqual(self.svc._probe("godot", fn), "Godot 4.6.3")
        self.assertEqual(len(calls), 3)

    def test_rates_use_active_time_not_gaps(self) -> None:
        store = self.svc.store
        rid = store.create_run(cfg_dict(), STAMP, OLD, state="running")
        pos = {"index": 0, "seed": 1, "decks": [], "prefix_len": 1, "seat": 0}
        lab = {"position_index": 0, "candidate_index": 0, "action": {}, "mean": 0.5,
               "spread": 0.1, "n": 100, "wins": 50, "draws": 0, "losses": 50, "capped": 0}
        store.commit_batch(rid, 0, [pos], [lab])
        store.add_active(rid, 50.0)
        store.set_state(rid, "stopped")
        # a long gap: stopped for a day, then the run record looks old
        day = 86400.0
        store.db.execute("UPDATE runs SET created = created - ?, updated = updated - ?"
                         " WHERE id = ?", (day, 0.0, rid))
        store.db.commit()
        st = self.svc.run_status(rid)
        self.assertEqual(st["elapsed_s"], 50.0)
        self.assertEqual(st["rollouts_per_s"], 2.0)
        store.set_state(rid, "queued", "")
        store.add_active(rid, 50.0)
        store.set_state(rid, "stopped")
        st = self.svc.run_status(rid)
        self.assertEqual(st["elapsed_s"], 100.0)
        self.assertEqual(st["rollouts_per_s"], 1.0)
        self.assertEqual(st["skipped"], 0)
        report = self.svc._report(store, rid)
        self.assertEqual(report["wall_s"], 100.0)
        self.assertEqual(report["rollouts_per_s"], 1.0)
        self.assertEqual(report["skipped"], 0)


@unittest.skipUnless(HAVE_MCP, "mcp is not installed")
class McpTest(unittest.TestCase):
    def test_eleven_tools_registered(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            svc = Service(Path(d) / "data", Path(d) / "me", farm_factory=stub_farm,
                          stamp_fn=lambda: STAMP)
            try:
                mcp = build_mcp(svc)
                tools = asyncio.run(mcp.list_tools())
                names = {t.name for t in getattr(tools, "tools", tools)}
                self.assertEqual(names, {
                    "health", "sync_code", "start_run", "run_status", "stop_run", "resume_run",
                    "list_runs", "get_report", "sample_positions", "fit", "get_artifact"})
            finally:
                svc.close()

    def test_lan_host_passes_dns_rebinding_check_with_token(self) -> None:
        from starlette.testclient import TestClient
        with tempfile.TemporaryDirectory() as d:
            svc = Service(Path(d) / "data", Path(d) / "me", farm_factory=stub_farm,
                          stamp_fn=lambda: STAMP)
            try:
                app = build_app(build_mcp(svc), "s3cret", "0.0.0.0")
                headers = {"Accept": "application/json, text/event-stream",
                           "Content-Type": "application/json"}
                body = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                    "protocolVersion": "2025-03-26", "capabilities": {},
                    "clientInfo": {"name": "t", "version": "0"}}}
                with TestClient(app, base_url="http://192.168.68.63:8765") as client:
                    bad = client.post("/mcp", json=body, headers=headers)
                    self.assertEqual(bad.status_code, 401)
                    ok = client.post("/mcp", json=body,
                                     headers=dict(headers, Authorization="Bearer s3cret"))
                    self.assertNotIn(ok.status_code, (401, 421), ok.text)
            finally:
                svc.close()


if __name__ == "__main__":
    unittest.main()
