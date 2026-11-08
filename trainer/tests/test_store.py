import json
import sqlite3
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


CYCLE_A_SCHEMA = """
CREATE TABLE runs (
  id TEXT PRIMARY KEY, state TEXT NOT NULL, config TEXT NOT NULL, run_seed INTEGER NOT NULL,
  stamp TEXT NOT NULL, "commit" TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL,
  last_error TEXT NOT NULL DEFAULT '', restarts INTEGER NOT NULL DEFAULT 0);
CREATE TABLE positions (
  run_id TEXT NOT NULL, "index" INTEGER NOT NULL, seed INTEGER NOT NULL, decks TEXT NOT NULL,
  prefix_len INTEGER NOT NULL, seat INTEGER NOT NULL, batch INTEGER NOT NULL,
  PRIMARY KEY (run_id, "index"));
CREATE TABLE labels (
  run_id TEXT NOT NULL, position_index INTEGER NOT NULL, candidate_index INTEGER NOT NULL,
  action TEXT NOT NULL, mean REAL NOT NULL, spread REAL NOT NULL, n INTEGER NOT NULL,
  wins INTEGER NOT NULL, draws INTEGER NOT NULL, losses INTEGER NOT NULL,
  capped INTEGER NOT NULL, PRIMARY KEY (run_id, position_index, candidate_index));
"""


class MigrationTest(unittest.TestCase):
    def test_cycle_a_database_opens_and_migrates(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            db = sqlite3.connect(str(Path(d) / "trainer.db"))
            db.executescript(CYCLE_A_SCHEMA)
            db.execute("INSERT INTO runs VALUES ('old', 'done', '{\"run_seed\": 1}', 1, 's',"
                       " 'c', 100.0, 160.0, '', 0)")
            db.execute("INSERT INTO positions VALUES ('old', 0, 1, '[]', 3, 0, 0)")
            db.execute("INSERT INTO labels VALUES ('old', 0, 0, '{}', 0.5, 1.0, 4, 2, 0, 2, 0)")
            db.commit()
            db.close()
            store = Store(Path(d))
            try:
                run = store.get_run("old") or {}
                self.assertEqual(run["feature_set"], "")
                self.assertEqual(run["active_s"], 60.0)
                row = store.db.execute("SELECT features FROM labels").fetchone()
                self.assertEqual(row["features"], "[]")
                self.assertEqual(store.counts("old")["labels"], 1)
                self.assertIsNone(store.get_fit("nope"))
                store.create_fit("f1", {"l2": 0.1}, "s", "fs1", ["old"])
                self.assertEqual((store.get_fit("f1") or {})["runs"], ["old"])
                store.create_run({"run_seed": 2}, "s", "c", run_id="new")
                pos, labs = make_batch(0, 1)
                labs[0]["features"] = [1, 2]
                store.commit_batch("new", 0, pos, labs)
            finally:
                store.close()
            again = Store(Path(d))  # opening a migrated database again is a no-op
            again.close()


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

    def test_active_s_migrates_from_an_old_database(self) -> None:
        import sqlite3
        with tempfile.TemporaryDirectory() as d:
            db = sqlite3.connect(str(Path(d) / "trainer.db"))
            db.execute('CREATE TABLE runs (id TEXT PRIMARY KEY, state TEXT NOT NULL,'
                       ' config TEXT NOT NULL, run_seed INTEGER NOT NULL, stamp TEXT NOT NULL,'
                       ' "commit" TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL,'
                       " last_error TEXT NOT NULL DEFAULT '',"
                       " restarts INTEGER NOT NULL DEFAULT 0)")
            db.execute("INSERT INTO runs VALUES ('o', 'done', '{}', 0, 's', 'c', 100.0, 160.0,"
                       " '', 0)")
            db.commit()
            db.close()
            store = Store(Path(d))
            try:
                run = store.get_run("o")
                assert run is not None
                self.assertEqual(run["active_s"], 60.0)
                store.add_active("o", 5.0)
                again = store.get_run("o")
                assert again is not None
                self.assertEqual(again["active_s"], 65.0)
            finally:
                store.close()


    def test_features_in_db_and_shard_lines(self) -> None:
        rid = self.new_run()
        self.store.set_feature_set(rid, "fs1")
        pos, labs = make_batch(0, 2)
        for lab in labs:
            lab["features"] = [lab["candidate_index"], 7, -1]
        path = self.store.commit_batch(rid, 0, pos, labs)
        lines = [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines()]
        self.assertEqual(lines[0]["feature_set"], "fs1")
        self.assertEqual(lines[0]["candidates"][1]["features"], [1, 7, -1])
        row = self.store.db.execute(
            "SELECT features FROM labels WHERE position_index = 1 AND candidate_index = 1"
        ).fetchone()
        self.assertEqual(json.loads(row["features"]), [1, 7, -1])

    def test_digest_ignores_us_but_not_features(self) -> None:
        digests = []
        for us, feats in ((10, [1]), (99, [1]), (10, [2])):
            with tempfile.TemporaryDirectory() as d:
                store = Store(Path(d))
                store.create_run({"run_seed": 3}, STAMP, "abc", run_id="x")
                pos, labs = make_batch(0, 1, us=us)
                for lab in labs:
                    lab["features"] = feats
                store.commit_batch("x", 0, pos, labs)
                digests.append(store.digest("x"))
                store.close()
        self.assertEqual(digests[0], digests[1])
        self.assertNotEqual(digests[0], digests[2])

class FitStateTest(unittest.TestCase):
    def test_fit_states_active_and_restart(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            store = Store(Path(d))
            try:
                store.create_fit("f1", {"k": 1}, STAMP, "f1", ["r"])
                store.create_fit("f2", {}, STAMP, "f1", ["r"], state="done")
                self.assertEqual(store.active_fit_id(), "f1")
                store.set_fit_state("f1", "running")
                store.set_fit_state("f1", "done", "", '{"pairs": {"total": 3}}')
                self.assertIsNone(store.active_fit_id())
                self.assertEqual((store.get_fit("f1") or {})["report"],
                                 '{"pairs": {"total": 3}}')
                self.assertEqual([f["id"] for f in store.list_fits()], ["f1", "f2"])
                store.create_fit("f3", {}, STAMP, "f1", ["r"], state="running")
                self.assertEqual(store.fail_live_fits("gone"), ["f3"])
                self.assertEqual((store.get_fit("f3") or {})["last_error"], "gone")
                with self.assertRaises(KeyError):
                    store.set_fit_state("nope", "done")
                with self.assertRaises(ValueError):
                    store.set_fit_state("f1", "stopped")
            finally:
                store.close()


if __name__ == "__main__":
    unittest.main()
