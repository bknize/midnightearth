import json
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Dict, List
from unittest import mock

from trainer.config import RunConfig
from trainer.farm import Farm, FarmError, RequestFailed
from trainer.run import execute, ordered_pairings
from trainer.seeds import play_seed
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


def run_all(farm: Farm, reqs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    with ThreadPoolExecutor(len(reqs)) as pool:
        return list(pool.map(farm.request, reqs))


class FarmTest(unittest.TestCase):
    def test_ordering_and_ids_across_workers(self) -> None:
        with make_farm(4) as farm:
            replies = run_all(farm, [play_req(1000 + i) for i in range(40)])
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
            replies = run_all(farm, [play_req(i) for i in range(10)])
            self.assertEqual([r["log"]["seed"] for r in replies], [str(i) for i in range(10)])
            self.assertEqual(farm.restarts, 3)

    def test_timeout_retries_once_then_fails_that_request_only(self) -> None:
        farm = make_farm(1, 0.5, "--hang-seed", "1")
        farm.start()
        try:
            with self.assertRaises(RequestFailed) as ctx:
                farm.request(play_req(1))
            self.assertIn("timed out", str(ctx.exception))
            self.assertEqual(ctx.exception.reason, "timeout")
            self.assertEqual(farm.restarts, 2)
            self.assertEqual(farm.request(play_req(2))["log"]["seed"], "2")  # farm still up
        finally:
            farm.stop()

    def test_three_crashes_fail_that_request_only(self) -> None:
        with make_farm(1, 30.0, "--crash-seed", "1") as farm:
            with self.assertRaises(RequestFailed) as ctx:
                farm.request(play_req(1))
            self.assertEqual(ctx.exception.reason, "crash")
            self.assertEqual(farm.request(play_req(2))["log"]["seed"], "2")

    def test_bad_command_fails_start(self) -> None:
        farm = Farm([sys.executable, "-I", "-c", "pass"], 1, start_timeout=10.0)
        with self.assertRaises(FarmError):
            farm.start()


    def test_request_after_stop_or_failure_errors_at_once(self) -> None:
        farm = make_farm(1)
        farm.start()
        farm.stop()
        with self.assertRaises(FarmError):
            farm.request(play_req(1))
        with self.assertRaises(FarmError):
            farm.request(play_req(2))
        failed = make_farm(1)
        failed.start()
        try:
            failed._close("boom")
            with self.assertRaises(FarmError) as ctx:
                failed.request(play_req(2))
            self.assertNotIsInstance(ctx.exception, RequestFailed)
        finally:
            failed.stop()

    def test_proc_closes_log_when_popen_fails(self) -> None:
        import trainer.farm as farm_mod
        opened: List[Any] = []
        real_open = open

        def spy(*a: Any, **kw: Any) -> Any:
            fh = real_open(*a, **kw)
            opened.append(fh)
            return fh

        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(farm_mod.subprocess, "Popen", side_effect=OSError("nope")), \
                    mock.patch("builtins.open", spy):
                with self.assertRaises(OSError):
                    farm_mod._Proc(["x"], Path(d) / "w.log")
            self.assertEqual(len(opened), 1)
            self.assertTrue(opened[0].closed)

    def test_unexpected_exception_in_slot_fails_the_job(self) -> None:
        farm = make_farm(1)

        def boom(slot: int, proc: Any, job: Any) -> Any:
            raise RuntimeError("boom")

        farm._serve = boom  # type: ignore[method-assign]
        farm.start()
        try:
            with self.assertRaises(FarmError) as ctx:
                farm.request(play_req(1))
            self.assertIn("boom", str(ctx.exception))
            with self.assertRaises(FarmError):
                farm.request(play_req(2))
        finally:
            farm.stop()


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

    def test_shard_lines_carry_features_and_feature_set(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=20)
        with make_farm(2) as farm:
            self.assertEqual(execute(store, rid, farm), "done")
        self.assertEqual((store.get_run(rid) or {})["feature_set"], "stub-1")
        lines = [json.loads(x) for p in store.shard_paths(rid)
                 for x in p.read_text(encoding="utf-8").splitlines()]
        self.assertEqual(len(lines), 20)
        for x in lines:
            self.assertEqual(x["feature_set"], "stub-1")
            self.assertEqual(set(x["info"]), {"round", "turn", "hand"})
            self.assertEqual(len(x["info"]["hand"]), 5)
            for c in x["candidates"]:
                self.assertEqual(len(c["features"]), 4)
                self.assertTrue(all(isinstance(v, int) for v in c["features"]))
        row = store.db.execute("SELECT features FROM labels LIMIT 1").fetchone()
        self.assertEqual(len(json.loads(row["features"])), 4)

    def test_no_inspect_request_and_weights_in_requests(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=20, rollout_weights="fa", generator_weights="fb")
        seen: List[Dict[str, Any]] = []
        with make_farm(1) as farm:
            real = farm.request

            def spy(req: Dict[str, Any]) -> Dict[str, Any]:
                seen.append(req)
                return real(req)

            farm.request = spy  # type: ignore[method-assign]
            self.assertEqual(execute(store, rid, farm), "done")
        kinds = [r["kind"] for r in seen]
        self.assertEqual(set(kinds), {"play", "label"})
        self.assertEqual(kinds.count("play"), kinds.count("label"))
        want_roll = str((self.root / "a" / "fits" / "fa" / "linear_weights.json").resolve())
        want_gen = str((self.root / "a" / "fits" / "fb" / "linear_weights.json").resolve())
        for r in seen:
            if r["kind"] == "label":
                self.assertEqual(r["rollout_weights"], want_roll)
                self.assertNotIn("generator_weights", r)
            else:
                self.assertEqual(r["generator_weights"], want_gen)
                self.assertNotIn("rollout_weights", r)

    def test_no_weights_sends_no_weights_members(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=20)
        seen: List[Dict[str, Any]] = []
        with make_farm(1) as farm:
            real = farm.request

            def spy(req: Dict[str, Any]) -> Dict[str, Any]:
                seen.append(req)
                return real(req)

            farm.request = spy  # type: ignore[method-assign]
            execute(store, rid, farm)
        for r in seen:
            self.assertNotIn("rollout_weights", r)
            self.assertNotIn("generator_weights", r)

    def test_feature_set_mismatch_on_resume_fails(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=20)
        store.set_feature_set(rid, "other-set")
        with make_farm(1) as farm:
            self.assertEqual(execute(store, rid, farm), "failed")
        self.assertIn("feature set", (store.get_run(rid) or {})["last_error"])

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

    def test_worker_error_reply_fails_the_run_not_the_position(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=20)
        with make_farm(2, 30.0, "--error-label") as farm:
            state = execute(store, rid, farm)
        self.assertEqual(state, "failed")
        run = store.get_run(rid) or {}
        self.assertIn("worker error", run["last_error"])
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

    def skip_run(self, name: str, *extra: str) -> Store:
        """40 positions with position 5's play seed hanging or crashing its worker."""
        store = self.store(name)
        self.new_run(store, positions=40)
        seed = play_seed(77, 5)
        with make_farm(3, 0.5, *extra, str(seed)) as farm:
            self.assertEqual(execute(store, "r1", farm), "done")
        return store

    def test_hung_position_is_skipped_and_run_carries_on(self) -> None:
        store = self.skip_run("a", "--hang-seed")
        self.assertEqual(store.resume_point("r1"), 40)
        self.assertEqual(store.skipped_count("r1"), 1)
        line = [json.loads(x) for p in store.shard_paths("r1")
                for x in p.read_text(encoding="utf-8").splitlines()][5]
        self.assertEqual(line["position"], 5)
        self.assertEqual(line["candidates"], [])
        self.assertEqual(line["info"], {"skipped": "play request: timeout"})

    def test_crashing_position_is_skipped_and_digest_is_stable(self) -> None:
        a = self.skip_run("a", "--crash-seed")
        b = self.skip_run("b", "--crash-seed")
        self.assertEqual(a.skipped_count("r1"), 1)
        self.assertEqual(a.digest("r1"), b.digest("r1"))
        clean = self.store("c")
        self.new_run(clean, positions=40)
        with make_farm(3) as farm:
            execute(clean, "r1", farm)
        self.assertNotEqual(a.digest("r1"), clean.digest("r1"))

    def test_skipped_position_stays_skipped_on_resume(self) -> None:
        whole = self.skip_run("whole", "--hang-seed")
        part = self.store("part")
        self.new_run(part, positions=40)
        seen: List[int] = []
        seed = str(play_seed(77, 5))
        with make_farm(2, 0.5, "--hang-seed", seed) as farm:
            execute(part, "r1", farm, should_stop=lambda: bool(seen),
                    progress=lambda p: seen.append(int(p["done"])))
        self.assertEqual(part.resume_point("r1"), 20)
        with make_farm(3, 0.5, "--hang-seed", seed) as farm:
            self.assertEqual(execute(part, "r1", farm), "done")
        self.assertEqual(part.digest("r1"), whole.digest("r1"))

    def test_stamp_mismatch_is_not_a_skip(self) -> None:
        store = self.store("a")
        rid = self.new_run(store, positions=20)
        with make_farm(2, 30.0, "--reply-stamp", "r7-other") as farm:
            self.assertEqual(execute(store, rid, farm), "failed")
        self.assertEqual(store.skipped_count(rid), 0)

    def test_hours_cap_stops_run_and_resume_gets_fresh_budget(self) -> None:
        store = self.store("a")
        self.new_run(store, positions=100, hours=1e-9)
        with make_farm(2) as farm:
            self.assertEqual(execute(store, "r1", farm), "stopped")
        run = store.get_run("r1") or {}
        self.assertEqual(store.resume_point("r1"), 20)  # one batch, then the cap
        self.assertIn("hours cap", run["last_error"])
        with make_farm(2) as farm:
            self.assertEqual(execute(store, "r1", farm), "stopped")
        self.assertEqual(store.resume_point("r1"), 40)
        # a generous budget runs to the end
        store.db.execute("UPDATE runs SET config = ? WHERE id = 'r1'",
                         (json.dumps(config(positions=100, hours=8.0), sort_keys=True),))
        store.db.commit()
        with make_farm(2) as farm:
            self.assertEqual(execute(store, "r1", farm), "done")

    def test_active_time_accumulates_per_batch(self) -> None:
        store = self.store("a")
        self.new_run(store, positions=40)
        ticks = iter(range(0, 1000, 10))
        with make_farm(2) as farm:
            execute(store, "r1", farm, clock=lambda: float(next(ticks)))
        # clock reads: start 0, settle 10, hours check 20, settle 30, final settle 40; the
        # settlements add up to the whole session.
        self.assertEqual((store.get_run("r1") or {})["active_s"], 40.0)


if __name__ == "__main__":
    unittest.main()
