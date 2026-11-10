import json
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List

from trainer import advisor, findings, knobs

GOOD = json.dumps({"plan": {"positions": 1500, "k": 8}, "reason": "more positions"})
BAD = "not json"
UNKNOWN = json.dumps({"plan": {"warp": 9}, "reason": "x"})


def chat(content: str) -> str:
    return json.dumps({"choices": [{"message": {"content": content}}]})


class Stub:
    """A scripted llama-server stand-in; a float in the script is a delay before GOOD."""

    def __init__(self, replies: List[Any]) -> None:
        self.replies = list(replies)
        stub = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args: Any) -> None:
                pass

            def do_GET(self) -> None:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"{}")

            def do_POST(self) -> None:
                n = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(n)
                item = stub.replies.pop(0)
                if isinstance(item, float):
                    time.sleep(item)
                    item = GOOD
                try:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(chat(item).encode("utf-8"))
                except OSError:
                    pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.port = int(self.server.server_address[1])
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()


class FakeHandle:
    def __init__(self) -> None:
        self.terminated = False

    def terminate(self) -> None:
        self.terminated = True

    def wait(self, timeout: float = 0) -> int:
        return 0

    def kill(self) -> None:
        pass

    def poll(self) -> Any:
        return None


class AdvisorTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.data = Path(self._tmp.name)
        self.handles: List[FakeHandle] = []

    def run_advise(self, replies: List[Any], reply_timeout: float = 5.0,
                   pins: Any = None) -> advisor.Advice:
        stub = Stub(replies)
        self.addCleanup(stub.close)
        cfg = advisor.AdvisorConfig(server_path="/bin/llama-server", model_path="/m/q.gguf",
                                    port=stub.port, reply_timeout_s=reply_timeout,
                                    model_name="q.gguf")

        def launch(argv: List[str]) -> FakeHandle:
            h = FakeHandle()
            self.handles.append(h)
            return h

        adv = advisor.Advisor(cfg, self.data, launch=launch, sleep=lambda s: None)
        return adv.advise(3, [], knobs.default_bounds(), {}, pins or {}, [], False,
                          knobs.plan_defaults(), True)

    def assert_stopped(self) -> None:
        self.assertEqual(len(self.handles), 1)
        self.assertTrue(self.handles[0].terminated)

    def test_valid_reply(self) -> None:
        a = self.run_advise([GOOD])
        self.assertEqual(a.source, "advisor")
        self.assertEqual(a.reason, "more positions")
        self.assertEqual(a.plan["positions"], 1500)
        self.assert_stopped()

    def test_invalid_then_valid(self) -> None:
        a = self.run_advise([BAD, GOOD])
        self.assertEqual(a.source, "advisor")
        self.assert_stopped()

    def test_invalid_twice(self) -> None:
        a = self.run_advise([BAD, BAD])
        self.assertEqual(a.source, "fallback")
        self.assertEqual(a.reason, "")
        self.assertIn("invalid reply", a.fallback_reason)
        self.assertEqual(a.plan, advisor.default_plan(True))
        self.assert_stopped()

    def test_unknown_knob(self) -> None:
        a = self.run_advise([UNKNOWN, UNKNOWN])
        self.assertEqual(a.source, "fallback")
        self.assertIn("unknown knob", a.fallback_reason)
        self.assert_stopped()

    def test_pinned_knob(self) -> None:
        a = self.run_advise([GOOD, GOOD], pins={"positions": 1000})
        self.assertEqual(a.source, "fallback")
        self.assert_stopped()

    def test_timeout(self) -> None:
        a = self.run_advise([1.0], reply_timeout=0.1)
        self.assertEqual(a.source, "fallback")
        self.assertIn("request failed", a.fallback_reason)
        self.assert_stopped()

    def test_record(self) -> None:
        a = self.run_advise([BAD, GOOD])
        rec = json.loads((self.data / "autopilot" / "advisor" / "3.json").read_text())
        self.assertEqual(rec["prompt_digest"], a.prompt_digest)
        self.assertEqual(rec["model"], "q.gguf")
        self.assertEqual(rec["raw_replies"], [BAD, GOOD])
        self.assertEqual(rec["messages"][0]["role"], "system")
        self.assertEqual(advisor.prompt_digest(rec["messages"]), a.prompt_digest)

    def test_missing_server_path(self) -> None:
        adv = advisor.Advisor(advisor.AdvisorConfig(), self.data, sleep=lambda s: None)
        a = adv.advise(1, [], knobs.default_bounds(), {}, {}, [], False, {}, False)
        self.assertEqual(a.source, "fallback")
        self.assertIn("server_path", a.fallback_reason)
        self.assertEqual(a.plan["rollout"], "random")

    def test_missing_config(self) -> None:
        with self.assertRaises(FileNotFoundError):
            advisor.load_config(self.data / "none.json")

    def test_config_fields(self) -> None:
        p = self.data / "config.json"
        p.write_text(json.dumps({"server_path": "x", "bogus": 1}))
        with self.assertRaises(ValueError):
            advisor.load_config(p)
        p.write_text(json.dumps({"server_path": "x", "model_path": "C:\\m\\q.gguf"}))
        cfg = advisor.load_config(p)
        self.assertEqual(cfg.model_name, "q.gguf")
        self.assertEqual(cfg.port, 8080)


class InterruptTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.data = Path(self._tmp.name)
        self.handle = FakeHandle()
        self.cfg = advisor.AdvisorConfig(server_path="/bin/llama-server",
                                         model_path="/m/q.gguf", model_name="q.gguf")

    def advise(self, adv: Any, stop: threading.Event) -> advisor.Advice:
        return adv.advise(3, [], knobs.default_bounds(), {}, {}, [], False,
                          knobs.plan_defaults(), True, stop)

    def test_stop_during_health_wait(self) -> None:
        stop = threading.Event()

        def down(*args: Any) -> Any:
            raise OSError("refused")

        adv = advisor.Advisor(self.cfg, self.data, launch=lambda argv: self.handle, http=down,
                              sleep=lambda s: stop.set())
        a = self.advise(adv, stop)
        self.assertEqual(a.source, "fallback")
        self.assertIn("stopped", a.fallback_reason)
        self.assertTrue(self.handle.terminated)
        self.assertEqual(advisor._LIVE & {self.handle}, set())

    def test_stop_abandons_a_pending_reply(self) -> None:
        stop = threading.Event()
        release = threading.Event()
        self.addCleanup(release.set)

        def http(method: str, url: str, body: Any, timeout: float) -> Any:
            if method == "GET":
                return 200, "{}"
            threading.Timer(0.1, stop.set).start()
            release.wait(10)
            return 200, chat(GOOD)

        adv = advisor.Advisor(self.cfg, self.data, launch=lambda argv: self.handle, http=http)
        began = time.monotonic()
        a = self.advise(adv, stop)
        self.assertLess(time.monotonic() - began, 5.0)
        self.assertEqual(a.source, "fallback")
        self.assertTrue(self.handle.terminated)

    def test_close_terminates_the_live_child(self) -> None:
        holder: List[Any] = []

        def down(*args: Any) -> Any:
            raise OSError("refused")

        def nap(s: float) -> None:
            self.assertIn(self.handle, advisor._LIVE)
            holder[0].close()
            self.assertTrue(self.handle.terminated)
            raise OSError("give up")

        adv = advisor.Advisor(self.cfg, self.data, launch=lambda argv: self.handle, http=down,
                              sleep=nap)
        holder.append(adv)
        self.advise(adv, threading.Event())
        self.assertNotIn(self.handle, advisor._LIVE)

    def test_file_advisor_close_reaches_the_child(self) -> None:
        (self.data / "autopilot").mkdir(parents=True)
        (self.data / "autopilot" / "config.json").write_text(json.dumps(
            {"server_path": "x", "model_path": "m.gguf"}))
        fa = advisor.FileAdvisor(self.data, launch=lambda argv: self.handle,
                                 http=lambda *a: (200, "{}"))
        stop = threading.Event()
        fa.kwargs["sleep"] = lambda s: None
        fa.kwargs["http"] = lambda method, url, body, timeout: (
            (200, "{}") if method == "GET" else (stop.set() or fa.close() or (200, chat(GOOD))))
        a = self.advise(fa, stop)
        self.assertTrue(self.handle.terminated)
        self.assertIn(a.source, ("fallback", "advisor"))


class FallbackTest(unittest.TestCase):
    def entry(self, block: int, before: Any, after: Any, positions: int) -> Dict[str, Any]:
        e = findings.new_entry(block, plan={"positions": positions})
        e["champion_before"], e["champion_after"] = before, after
        return e

    def test_last_champion_change(self) -> None:
        es = [self.entry(1, None, "a", 111), self.entry(2, "a", "a", 222),
              self.entry(3, "a", "b", 333), self.entry(4, "b", "b", 444)]
        plan, which = advisor.fallback_plan(es, True)
        self.assertEqual(plan, {"positions": 333})
        self.assertEqual(which, "plan of block 3")

    def test_default(self) -> None:
        plan, which = advisor.fallback_plan([self.entry(1, "a", "a", 1)], True)
        self.assertEqual(which, "default plan")
        self.assertEqual(plan["rollout"], "linear")
        self.assertEqual(plan["rollout_weights"], "champion")
        plan, _ = advisor.fallback_plan([], False)
        self.assertEqual((plan["rollout"], plan["rollout_weights"]), ("random", ""))

    def test_parse_reply(self) -> None:
        self.assertIsNotNone(advisor.parse_reply(GOOD)[0])
        self.assertIsNone(advisor.parse_reply('{"plan": {}}')[0])
        self.assertIsNone(advisor.parse_reply("[1]")[0])


if __name__ == "__main__":
    unittest.main()
