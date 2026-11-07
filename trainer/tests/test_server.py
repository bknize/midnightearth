import asyncio
import threading
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any, Dict, List

from trainer.config import RunConfig
from trainer.farm import Farm
from trainer.store import Store
from trainer.server import (BearerMiddleware, Service, TokenError, acquire_serve_lock,
                            build_app, build_mcp, check_bearer, load_token)

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

    def wait(self, run_id: str, states: Any = ("done", "stopped", "failed")) -> Dict[str, Any]:
        for _ in range(600):
            st = self.svc.run_status(run_id)
            if st["state"] in states:
                self.svc.join(30)
                return self.svc.run_status(run_id)
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
    def test_nine_tools_registered(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            svc = Service(Path(d) / "data", Path(d) / "me", farm_factory=stub_farm,
                          stamp_fn=lambda: STAMP)
            try:
                mcp = build_mcp(svc)
                tools = asyncio.run(mcp.list_tools())
                names = {t.name for t in getattr(tools, "tools", tools)}
                self.assertEqual(names, {
                    "health", "sync_code", "start_run", "run_status", "stop_run", "resume_run",
                    "list_runs", "get_report", "sample_positions"})
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
