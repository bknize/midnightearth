import json
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List, Tuple

from trainer.store import Store, shard_name

STAMP = "r7-" + "0" * 16


def make_batch(start: int, count: int,
               us: int = 10) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    positions = []
    labels = []
    for i in range(start, start + count):
        positions.append({"index": i, "seed": (1 << 60) | i, "decks": ["a", "b"],
                          "prefix_len": 5 + i, "seat": i % 2})
        for c in range(2):
            labels.append({"position_index": i, "candidate_index": c,
                           "action": {"t": "commit", "card": c}, "mean": 0.5 * c,
                           "spread": 1.0, "n": 16, "wins": 8, "draws": 0, "losses": 8,
                           "capped": False, "us": us})
    return positions, labels


class StoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        self.store = Store(self.dir)
        self.addCleanup(lambda: self.store.close())

    def new_run(self) -> str:
        return self.store.create_run({"run_seed": 3, "positions": 4}, STAMP, "abc123",
                                     run_id="run1")

    def test_round_trip(self) -> None:
        rid = self.new_run()
        run = self.store.get_run(rid)
        assert run is not None
        self.assertEqual(run["state"], "queued")
        self.assertEqual(run["config"]["positions"], 4)
        self.assertEqual(run["run_seed"], 3)
        pos, labs = make_batch(0, 2)
        shard = self.store.commit_batch(rid, 0, pos, labs)
        self.assertEqual(shard.name, shard_name(0))
        lines = shard.read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(lines), 2)
        rec = json.loads(lines[0])
        self.assertEqual(rec["run"], rid)
        self.assertEqual(rec["stamp"], run["stamp"])
        self.assertEqual(rec["commit"], "abc123")
        self.assertEqual(len(rec["candidates"]), 2)
        n = self.store.db.execute("SELECT COUNT(*) FROM labels").fetchone()[0]
        self.assertEqual(n, 4)
        self.assertEqual(self.store.committed_batches(rid), [0])
        self.assertEqual([r["id"] for r in self.store.list_runs()], [rid])

    def test_crash_before_commit_leaves_nothing(self) -> None:
        rid = self.new_run()
        pos, labs = make_batch(0, 2)
        self.store.commit_batch(rid, 0, pos, labs)
        pos2, labs2 = make_batch(2, 2)
        # Simulate a crash after the rename, before the DB commit: shard without rows.
        orphan = self.store.run_dir(rid) / shard_name(1)
        orphan.write_text("{}\n", encoding="utf-8")
        tmp = self.store.run_dir(rid) / (shard_name(2) + ".tmp")
        tmp.write_text("partial", encoding="utf-8")
        before = self.store.digest(rid)
        self.store.close()
        self.store = Store(self.dir)
        self.assertFalse(orphan.exists())
        self.assertFalse(tmp.exists())
        self.assertEqual(self.store.committed_batches(rid), [0])
        self.assertEqual(self.store.resume_point(rid), 2)
        self.assertEqual(self.store.digest(rid), before)
        self.store.commit_batch(rid, 1, pos2, labs2)
        self.assertEqual(self.store.resume_point(rid), 4)

    def test_failed_transaction_rolls_back(self) -> None:
        rid = self.new_run()
        pos, labs = make_batch(0, 2)
        labs[1]["wins"] = None
        with self.assertRaises(Exception):
            self.store.commit_batch(rid, 0, pos, labs)
        self.assertEqual(self.store.resume_point(rid), 0)
        self.assertFalse((self.store.run_dir(rid) / shard_name(0)).exists())

    def test_resume_point(self) -> None:
        rid = self.new_run()
        self.assertEqual(self.store.resume_point(rid), 0)
        self.store.commit_batch(rid, 0, *make_batch(0, 3))
        self.assertEqual(self.store.resume_point(rid), 3)
        self.store.commit_batch(rid, 1, *make_batch(3, 3))
        self.assertEqual(self.store.resume_point(rid), 6)

    def test_digest_stable_and_ignores_timing(self) -> None:
        rid = self.new_run()
        self.store.commit_batch(rid, 0, *make_batch(0, 2, us=10))
        self.store.commit_batch(rid, 1, *make_batch(2, 2, us=11))
        d1 = self.store.digest(rid)
        self.assertEqual(d1, self.store.digest(rid))
        text = (self.store.run_dir(rid) / shard_name(0)).read_text(encoding="utf-8")
        self.assertIn('"us"', text)
        with tempfile.TemporaryDirectory() as other_dir:
            s2 = Store(Path(other_dir))
            try:
                s2.create_run({"run_seed": 3, "positions": 4}, STAMP, "abc123", run_id=rid)
                s2.commit_batch(rid, 0, *make_batch(0, 2, us=77))
                s2.commit_batch(rid, 1, *make_batch(2, 2, us=1))
                self.assertEqual(s2.digest(rid), d1)
                s2.close()
                s3 = Store(Path(other_dir))
                self.assertEqual(s3.digest(rid), d1)
                s3.close()
            finally:
                try:
                    s2.close()
                except Exception:
                    pass

    def test_digest_ignores_the_run_id(self) -> None:
        # Two runs of the same data under different run ids have one digest (spec R36).
        a = self.store.create_run({"run_seed": 3, "positions": 4}, STAMP, "abc123", run_id="a1")
        b = self.store.create_run({"run_seed": 3, "positions": 4}, STAMP, "abc123", run_id="b2")
        for rid in (a, b):
            self.store.commit_batch(rid, 0, *make_batch(0, 2))
        self.assertEqual(self.store.digest(a), self.store.digest(b))

    def test_digest_changes_with_data(self) -> None:
        rid = self.new_run()
        self.store.commit_batch(rid, 0, *make_batch(0, 2))
        d1 = self.store.digest(rid)
        self.store.commit_batch(rid, 1, *make_batch(2, 1))
        self.assertNotEqual(d1, self.store.digest(rid))

    def test_mark_interrupted(self) -> None:
        a = self.store.create_run({"run_seed": 1}, "s", "c", run_id="a", state="running")
        b = self.store.create_run({"run_seed": 1}, "s", "c", run_id="b", state="stopping")
        c = self.store.create_run({"run_seed": 1}, "s", "c", run_id="c", state="stopped")
        d = self.store.create_run({"run_seed": 1}, "s", "c", run_id="d", state="done")
        q = self.store.create_run({"run_seed": 1}, "s", "c", run_id="q", state="queued")
        self.assertEqual(self.store.mark_interrupted(), [a, b, q])
        states = {r["id"]: r["state"] for r in self.store.list_runs()}
        self.assertEqual(states, {a: "interrupted", b: "interrupted", c: "stopped", d: "done",
                                  q: "interrupted"})

    def test_checkpoint_time_and_position_info(self) -> None:
        rid = self.new_run()
        run = self.store.get_run(rid)
        assert run is not None
        self.assertEqual(run["checkpoint"], 0)
        positions, labels = make_batch(0, 1)
        positions[0]["info"] = {"round": 2, "turn": 1, "hand": [{"card": "c1", "name": "One"}]}
        self.store.commit_batch(rid, 0, positions, labels)
        run = self.store.get_run(rid)
        assert run is not None
        self.assertGreater(run["checkpoint"], 0)
        row = self.store.db.execute("SELECT info FROM positions WHERE run_id = ?",
                                    (rid,)).fetchone()
        self.assertEqual(json.loads(row["info"])["round"], 2)

    def test_set_state_validates(self) -> None:
        rid = self.new_run()
        with self.assertRaises(ValueError):
            self.store.set_state(rid, "bogus")
        with self.assertRaises(KeyError):
            self.store.set_state("nope", "running")
        self.store.set_state(rid, "failed", "boom")
        run = self.store.get_run(rid)
        assert run is not None
        self.assertEqual((run["state"], run["last_error"]), ("failed", "boom"))
        self.store.add_restarts(rid, 2)
        run = self.store.get_run(rid)
        assert run is not None
        self.assertEqual(run["restarts"], 2)


if __name__ == "__main__":
    unittest.main()
