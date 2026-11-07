import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List

from trainer.config import RunConfig
from trainer.farm import Farm, FarmError
from trainer.run import execute, ordered_pairings
from trainer.store import Store

STUB = str(Path(__file__).resolve().parent / "stub_worker.py")
STAMP = "r7-stub"


def make_farm(workers: int = 3, timeout: float = 30.0, *extra: str) -> Farm:
    cmd = [sys.executable, "-I", STUB] + list(extra)
    return Farm(cmd, workers, timeout=timeout, start_timeout=30.0)


def config(**over: Any) -> Dict[str, Any]:
    cfg = RunConfig(positions=100, k=3, determinizations=4, workers=4, batch=20,
                    run_seed=77).to_dict()
    cfg.update(over)
    return cfg


def play_req(seed: int) -> Dict[str, Any]:
    return {"kind": "play", "seed": str(seed), "decks": [], "generator": "random"}


class FarmTest(unittest.TestCase):
    def test_ordering_and_ids_across_workers(self) -> None:
        with make_farm(4) as farm:
            replies = farm.map([play_req(1000 + i) for i in range(40)])
            self.assertEqual(farm.stamp, STAMP)
        for i, rep in enumerate(replies):
            self.assertEqual(rep["log"]["seed"], str(1000 + i))
        self.assertEqual(len({r["id"] for r in replies}), 40)

    def test_banner_before_hello_is_skipped(self) -> None:
        with make_farm(1, 30.0, "--banner") as farm:
            rep = farm.request(play_req(5))
            self.assertEqual(rep["log"]["seed"], "5")

    def test_restart_counted_after_crash(self) -> None:
        with make_farm(1, 30.0, "--crash-after", "3") as farm:
            replies = farm.map([play_req(i) for i in range(10)])
            self.assertEqual([r["log"]["seed"] for r in replies], [str(i) for i in range(10)])
            self.assertEqual(farm.restarts, 3)

    def test_timeout_retries_once_then_fails(self) -> None:
        farm = make_farm(1, 0.5, "--hang-after", "0")
        farm.start()
        try:
            with self.assertRaises(FarmError) as ctx:
                farm.request(play_req(1))
            self.assertIn("timed out", str(ctx.exception))
            self.assertEqual(farm.restarts, 1)
        finally:
            farm.stop()

    def test_bad_command_fails_start(self) -> None:
        farm = Farm([sys.executable, "-I", "-c", "pass"], 1, start_timeout=10.0)
        with self.assertRaises(FarmError):
            farm.start()


class RunTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def store(self, name: str) -> Store:
        s = Store(self.root / name)
        self.addCleanup(s.close)
        return s

    def new_run(self, store: Store, **over: Any) -> str:
        return store.create_run(config(**over), STAMP, "abc", run_id="r1")

    def test_full_run_and_batch_layout(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=45, batch=20)
        with make_farm(4) as farm:
            state = execute(store, rid, farm)
        self.assertEqual(state, "done")
        self.assertEqual(store.committed_batches(rid), [0, 1, 2])
        self.assertEqual(store.resume_point(rid), 45)
        lines: List[Dict[str, Any]] = []
        for path in store.shard_paths(rid):
            lines += [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines()]
        self.assertEqual([x["position"] for x in lines], list(range(45)))
        for x in lines:
            self.assertTrue(1 <= len(x["candidates"]) <= 3)

    def test_stop_at_40_resume_matches_uninterrupted(self) -> None:
        whole = self.store("whole")
        rid = self.new_run(whole)
        with make_farm(4) as farm:
            self.assertEqual(execute(whole, rid, farm), "done")
        want = whole.digest(rid)

        part = self.store("part")
        self.new_run(part)
        seen: List[int] = []

        def note(p: Dict[str, Any]) -> None:
            seen.append(int(p["done"]))

        with make_farm(2) as farm:
            state = execute(part, "r1", farm,
                            should_stop=lambda: bool(seen) and seen[-1] >= 40, progress=note)
        self.assertEqual(state, "stopped")
        self.assertEqual(part.resume_point("r1"), 40)
        self.assertEqual((part.get_run("r1") or {})["state"], "stopped")
        with make_farm(3) as farm:
            self.assertEqual(execute(part, "r1", farm), "done")
        self.assertEqual(part.resume_point("r1"), 100)
        self.assertEqual(part.digest("r1"), want)

    def test_digest_independent_of_worker_count_and_crashes(self) -> None:
        a = self.store("a")
        self.new_run(a, positions=40)
        with make_farm(1) as farm:
            execute(a, "r1", farm)
        b = self.store("b")
        self.new_run(b, positions=40)
        with make_farm(4, 30.0, "--crash-after", "7") as farm:
            self.assertEqual(execute(b, "r1", farm), "done")
            self.assertGreater(farm.restarts, 0)
            restarts = farm.restarts
        self.assertEqual(a.digest("r1"), b.digest("r1"))
        self.assertEqual((b.get_run("r1") or {})["restarts"], restarts)

    def test_stamp_mismatch_fails_run_and_commits_nothing(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=20)
        with make_farm(2, 30.0, "--reply-stamp", "r7-other") as farm:
            state = execute(store, rid, farm)
        self.assertEqual(state, "failed")
        run = store.get_run(rid) or {}
        self.assertEqual(run["state"], "failed")
        self.assertIn("stamp", run["last_error"])
        self.assertEqual(store.committed_batches(rid), [])

    def test_run_stamp_differs_from_workers(self) -> None:
        store = self.store("a")
        rid = store.create_run(config(positions=20), "r7-old", "abc", run_id="r1")
        with make_farm(1) as farm:
            self.assertEqual(execute(store, rid, farm), "failed")

    def test_all_pairings_cycle(self) -> None:
        self.assertEqual(len(ordered_pairings(["a", "b", "c"])), 9)
        store = self.store("a")
        rid = self.new_run(store, positions=40, decks="all_pairings")
        with make_farm(2) as farm:
            self.assertEqual(execute(store, rid, farm), "done")
        row = store.db.execute('SELECT decks FROM positions WHERE "index" = 1').fetchone()
        self.assertEqual(len(json.loads(row["decks"])), 2)

    def test_timeout_fails_run(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=20)
        farm = make_farm(1, 0.5, "--hang-after", "0")
        farm.start()
        try:
            self.assertEqual(execute(store, rid, farm), "failed")
        finally:
            farm.stop()
        self.assertIn("timed out", (store.get_run(rid) or {})["last_error"])


if __name__ == "__main__":
    unittest.main()
