import asyncio
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
from trainer.server import (BearerMiddleware, Service, TokenError, build_mcp, check_bearer,
                            load_token)

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
        rep = self.svc.get_report(rid)
        self.assertEqual(rep["digest"], st["digest"])
        self.assertEqual(rep["positions"], 40)
        self.assertTrue((self.root / "data" / "runs" / rid / "report.json").is_file())
        self.assertEqual([x["run_id"] for x in self.svc.list_runs()["runs"]], [rid])
        s1 = self.svc.sample_positions(rid, 3, 9)
        self.assertEqual(len(s1["positions"]), 3)
        self.assertEqual(s1, self.svc.sample_positions(rid, 3, 9))
        for p in s1["positions"]:
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
        self.svc.stop_run(rid)
        st = self.wait(rid, ("stopped", "done"))
        if st["state"] == "stopped":
            self.assertIn("error", self.svc.stop_run(rid))
            self.assertNotIn("error", self.svc.resume_run(rid))
            st = self.wait(rid, ("done",))
        self.assertEqual(st["digest"], want)
        self.assertIn("error", self.svc.resume_run(rid))

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
                self.assertEqual(len(names), 9)
            finally:
                svc.close()


if __name__ == "__main__":
    unittest.main()
