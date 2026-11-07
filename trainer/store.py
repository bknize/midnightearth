"""The run store (plan P12, R32 to R37): sqlite3 `trainer.db` plus JSONL label shards.

Reload rule. A batch commit writes the shard to a temp file, renames it to
`runs/<id>/labels-<batch:05d>.jsonl`, then commits the DB transaction. The DB is the truth:
a batch exists only if its position rows do. A crash before the rename leaves a stray temp
file; a crash between rename and commit leaves a shard with no DB rows. `recover()` (run
when a Store opens) deletes both, so after a reload either the whole batch is visible
(shard and rows) or none of it is, and re-running that batch rewrites the same shard.
"""
import hashlib
import json
import os
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

STATES = ("queued", "running", "stopping", "stopped", "interrupted", "done", "failed")
TIMING_FIELDS = ("us",)
# Fields of a shard line that name the run rather than its data: the dataset digest drops
# them, so two runs with the same config and run seed give the same digest (spec R36).
IDENTITY_FIELDS = ("run",)
DB_NAME = "trainer.db"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY, state TEXT NOT NULL, config TEXT NOT NULL, run_seed INTEGER NOT NULL,
  stamp TEXT NOT NULL, "commit" TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL,
  last_error TEXT NOT NULL DEFAULT '', restarts INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS positions (
  run_id TEXT NOT NULL, "index" INTEGER NOT NULL, seed INTEGER NOT NULL, decks TEXT NOT NULL,
  prefix_len INTEGER NOT NULL, seat INTEGER NOT NULL, batch INTEGER NOT NULL,
  PRIMARY KEY (run_id, "index"));
CREATE TABLE IF NOT EXISTS labels (
  run_id TEXT NOT NULL, position_index INTEGER NOT NULL, candidate_index INTEGER NOT NULL,
  action TEXT NOT NULL, mean REAL NOT NULL, spread REAL NOT NULL, n INTEGER NOT NULL,
  wins INTEGER NOT NULL, draws INTEGER NOT NULL, losses INTEGER NOT NULL,
  capped INTEGER NOT NULL, PRIMARY KEY (run_id, position_index, candidate_index));
"""


def default_data_dir() -> Path:
    env = os.environ.get("TRAINER_DATA")
    return Path(env) if env else Path.home() / "trainer-data"


def shard_name(batch: int) -> str:
    return "labels-%05d.jsonl" % batch


def _strip_timing(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: _strip_timing(v) for k, v in value.items() if k not in TIMING_FIELDS}
    if isinstance(value, list):
        return [_strip_timing(v) for v in value]
    return value


class Store:
    def __init__(self, data_dir: Optional[Path] = None) -> None:
        self.data_dir = Path(data_dir) if data_dir is not None else default_data_dir()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(self.data_dir / DB_NAME))
        self.db.row_factory = sqlite3.Row
        self.db.executescript(_SCHEMA)
        self.db.commit()
        self.recover()

    def close(self) -> None:
        self.db.close()

    def run_dir(self, run_id: str) -> Path:
        return self.data_dir / "runs" / run_id

    # runs

    def create_run(self, config: Dict[str, Any], stamp: str, commit: str,
                   run_id: Optional[str] = None, state: str = "queued") -> str:
        if state not in STATES:
            raise ValueError("unknown run state %r" % (state,))
        rid = run_id or uuid.uuid4().hex[:12]
        now = time.time()
        self.db.execute(
            'INSERT INTO runs (id, state, config, run_seed, stamp, "commit", created, updated)'
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (rid, state, json.dumps(config, sort_keys=True), int(config.get("run_seed", 0)),
             stamp, commit, now, now))
        self.db.commit()
        self.run_dir(rid).mkdir(parents=True, exist_ok=True)
        return rid

    def get_run(self, run_id: str) -> Optional[Dict[str, Any]]:
        row = self.db.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
        if row is None:
            return None
        out: Dict[str, Any] = dict(row)
        out["config"] = json.loads(out["config"])
        return out

    def list_runs(self) -> List[Dict[str, Any]]:
        ids = [r["id"] for r in self.db.execute("SELECT id FROM runs ORDER BY created, id")]
        out: List[Dict[str, Any]] = []
        for i in ids:
            run = self.get_run(i)
            if run is not None:
                out.append(run)
        return out

    def set_state(self, run_id: str, state: str, last_error: Optional[str] = None) -> None:
        if state not in STATES:
            raise ValueError("unknown run state %r" % (state,))
        if last_error is None:
            cur = self.db.execute("UPDATE runs SET state = ?, updated = ? WHERE id = ?",
                                  (state, time.time(), run_id))
        else:
            cur = self.db.execute(
                "UPDATE runs SET state = ?, last_error = ?, updated = ? WHERE id = ?",
                (state, last_error, time.time(), run_id))
        if cur.rowcount == 0:
            raise KeyError(run_id)
        self.db.commit()

    def add_restarts(self, run_id: str, count: int = 1) -> None:
        self.db.execute("UPDATE runs SET restarts = restarts + ?, updated = ? WHERE id = ?",
                        (count, time.time(), run_id))
        self.db.commit()

    def mark_interrupted(self) -> List[str]:
        """R37: every running or stopping run becomes interrupted. Returns their ids."""
        ids = [r["id"] for r in self.db.execute(
            "SELECT id FROM runs WHERE state IN ('running', 'stopping') ORDER BY id")]
        self.db.execute("UPDATE runs SET state = 'interrupted', updated = ? "
                        "WHERE state IN ('running', 'stopping')", (time.time(),))
        self.db.commit()
        return ids

    # batches

    def commit_batch(self, run_id: str, batch_index: int, positions: List[Dict[str, Any]],
                     labels: List[Dict[str, Any]]) -> Path:
        """Write the shard and the DB rows so that both or neither survive a crash.

        positions: dicts with index, seed, decks (JSON-able), prefix_len, seat.
        labels: dicts with position_index, candidate_index, action, mean, spread, n, wins,
        draws, losses, capped, and optionally us (timing: kept in the shard, not digested).
        """
        run = self.get_run(run_id)
        if run is None:
            raise KeyError(run_id)
        by_pos: Dict[int, List[Dict[str, Any]]] = {}
        for lab in labels:
            by_pos.setdefault(int(lab["position_index"]), []).append(lab)
        lines = []
        for pos in positions:
            cands = sorted(by_pos.get(int(pos["index"]), []),
                           key=lambda c: int(c["candidate_index"]))
            lines.append(json.dumps({
                "run": run_id, "position": int(pos["index"]), "seed": str(int(pos["seed"])),
                "decks": pos["decks"], "prefix_len": int(pos["prefix_len"]),
                "seat": int(pos["seat"]), "stamp": run["stamp"], "commit": run["commit"],
                "candidates": cands}, sort_keys=True))
        directory = self.run_dir(run_id)
        directory.mkdir(parents=True, exist_ok=True)
        final = directory / shard_name(batch_index)
        tmp = directory / (shard_name(batch_index) + ".tmp")
        with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("".join(line + "\n" for line in lines))
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, final)
        # A crash here leaves the shard without rows; recover() removes it.
        try:
            with self.db:
                self.db.executemany(
                    'INSERT INTO positions (run_id, "index", seed, decks, prefix_len, seat,'
                    " batch) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    [(run_id, int(p["index"]), int(p["seed"]), json.dumps(p["decks"]),
                      int(p["prefix_len"]), int(p["seat"]), batch_index) for p in positions])
                self.db.executemany(
                    "INSERT INTO labels (run_id, position_index, candidate_index, action,"
                    " mean, spread, n, wins, draws, losses, capped)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [(run_id, int(lab["position_index"]), int(lab["candidate_index"]),
                      json.dumps(lab["action"], sort_keys=True), float(lab["mean"]),
                      float(lab["spread"]), int(lab["n"]), int(lab["wins"]), int(lab["draws"]),
                      int(lab["losses"]), int(bool(lab["capped"]))) for lab in labels])
                self.db.execute("UPDATE runs SET updated = ? WHERE id = ?",
                                (time.time(), run_id))
        except Exception:
            if batch_index not in self.committed_batches(run_id):
                final.unlink(missing_ok=True)
            raise
        return final

    def committed_batches(self, run_id: str) -> List[int]:
        return [r["batch"] for r in self.db.execute(
            "SELECT DISTINCT batch FROM positions WHERE run_id = ? ORDER BY batch", (run_id,))]

    def resume_point(self, run_id: str) -> int:
        """The first position index after the last committed batch (0 when none)."""
        row = self.db.execute(
            'SELECT MAX("index") AS m FROM positions WHERE run_id = ?', (run_id,)).fetchone()
        return 0 if row["m"] is None else int(row["m"]) + 1

    def recover(self) -> None:
        """Apply the reload rule: drop temp files and shards with no committed batch."""
        runs_dir = self.data_dir / "runs"
        if not runs_dir.is_dir():
            return
        for d in sorted(p for p in runs_dir.iterdir() if p.is_dir()):
            committed = {shard_name(b) for b in self.committed_batches(d.name)}
            for f in sorted(d.iterdir()):
                if f.name.endswith(".tmp"):
                    f.unlink()
                elif (f.name.startswith("labels-") and f.name.endswith(".jsonl")
                        and f.name not in committed):
                    f.unlink()

    def shard_paths(self, run_id: str) -> List[Path]:
        return [self.run_dir(run_id) / shard_name(b) for b in self.committed_batches(run_id)]

    def digest(self, run_id: str) -> str:
        """SHA-256 over the committed shards' lines in batch order, timing fields and the run
        id removed."""
        h = hashlib.sha256()
        for path in self.shard_paths(run_id):
            with open(path, "r", encoding="utf-8", newline="") as fh:
                for line in fh:
                    line = line.rstrip("\r\n")
                    if not line:
                        continue
                    record = _strip_timing(json.loads(line))
                    if isinstance(record, dict):
                        for key in IDENTITY_FIELDS:
                            record.pop(key, None)
                    canon = json.dumps(record, sort_keys=True, separators=(",", ":"))
                    h.update(canon.encode("utf-8"))
                    h.update(b"\n")
        return h.hexdigest()
