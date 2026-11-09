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
from typing import Any, Dict, List, Optional, Sequence, Tuple, Union

STATES = ("queued", "running", "stopping", "stopped", "interrupted", "done", "failed")
# A run in one of these has (or is owed) a run thread: one at a time, and no sync under it.
ACTIVE = ("queued", "running", "stopping")
# What the service resumes.
RESUMABLE = ("stopped", "interrupted")
# How a run finishes: Store.finish, from its run thread.
FINISHED_STATES = ("done", "stopped", "failed")
# The run state machine: state -> the states it may be entered from. `running` is entered from
# a finished state by the local `run --resume`, and `failed` -> `interrupted` is a shutdown
# reclaiming a run whose farm it stopped itself (Service.close). Nothing leaves `done`.
ENTERED_FROM: Dict[str, Tuple[str, ...]] = {
    "queued": RESUMABLE,
    "running": ("queued", "stopped", "interrupted", "failed"),
    "stopping": ("queued", "running"),
    "stopped": ACTIVE,
    "interrupted": ACTIVE + ("failed",),
    "done": ACTIVE,
    "failed": ACTIVE}
FIT_STATES = ("queued", "running", "done", "failed")
# The fit states of a fit still in flight (queued or running).
LIVE_FIT = ("queued", "running")
TIMING_FIELDS = ("us",)
# Fields of a shard line that name the run rather than its data: the dataset digest drops
# them, so two runs with the same config and run seed give the same digest (spec R36).
IDENTITY_FIELDS = ("run",)
DB_NAME = "trainer.db"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY, state TEXT NOT NULL, config TEXT NOT NULL, run_seed INTEGER NOT NULL,
  stamp TEXT NOT NULL, "commit" TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL,
  last_error TEXT NOT NULL DEFAULT '', restarts INTEGER NOT NULL DEFAULT 0,
  checkpoint REAL NOT NULL DEFAULT 0, active_s REAL NOT NULL DEFAULT 0,
  feature_set TEXT NOT NULL DEFAULT '', n_positions INTEGER NOT NULL DEFAULT 0,
  n_labels INTEGER NOT NULL DEFAULT 0, n_rollouts INTEGER NOT NULL DEFAULT 0,
  n_skipped INTEGER NOT NULL DEFAULT 0, n_batches INTEGER NOT NULL DEFAULT 0,
  digest TEXT NOT NULL DEFAULT '');
CREATE TABLE IF NOT EXISTS positions (
  run_id TEXT NOT NULL, "index" INTEGER NOT NULL, seed INTEGER NOT NULL, decks TEXT NOT NULL,
  prefix_len INTEGER NOT NULL, seat INTEGER NOT NULL, batch INTEGER NOT NULL,
  info TEXT NOT NULL DEFAULT '{}',
  PRIMARY KEY (run_id, "index"));
CREATE TABLE IF NOT EXISTS labels (
  run_id TEXT NOT NULL, position_index INTEGER NOT NULL, candidate_index INTEGER NOT NULL,
  action TEXT NOT NULL, mean REAL NOT NULL, spread REAL NOT NULL, n INTEGER NOT NULL,
  wins INTEGER NOT NULL, draws INTEGER NOT NULL, losses INTEGER NOT NULL,
  capped INTEGER NOT NULL, features TEXT NOT NULL DEFAULT '[]',
  PRIMARY KEY (run_id, position_index, candidate_index));
CREATE TABLE IF NOT EXISTS fits (
  id TEXT PRIMARY KEY, state TEXT NOT NULL, config TEXT NOT NULL, stamp TEXT NOT NULL,
  feature_set TEXT NOT NULL, runs TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL,
  last_error TEXT NOT NULL DEFAULT '', report TEXT NOT NULL DEFAULT '');
"""
# The run row's counters (kept by commit_batch, in the batch's own transaction, so reading a
# run's progress costs one row) and the digest of a finished run. Added together, and
# backfilled, by _migrate_counters.
_COUNTER_COLUMNS = (("n_positions", "INTEGER NOT NULL DEFAULT 0"),
                    ("n_labels", "INTEGER NOT NULL DEFAULT 0"),
                    ("n_rollouts", "INTEGER NOT NULL DEFAULT 0"),
                    ("n_skipped", "INTEGER NOT NULL DEFAULT 0"),
                    ("n_batches", "INTEGER NOT NULL DEFAULT 0"),
                    ("digest", "TEXT NOT NULL DEFAULT ''"))


def default_data_dir() -> Path:
    env = os.environ.get("TRAINER_DATA")
    return Path(env) if env else Path.home() / "trainer-data"


WEIGHTS_NAME = "linear_weights.json"


def weights_path(data_dir: Path, fit_id: str) -> str:
    """Where a fit's weights file lives (absolute, as the worker gets it); "" for no fit."""
    if not fit_id:
        return ""
    return str((Path(data_dir) / "fits" / fit_id / WEIGHTS_NAME).resolve())


def write_atomic(path: Path, text: str) -> None:
    """Write `text` to `path` through `<name>.tmp` (flushed and fsynced, then renamed over
    `path`), so a reader never sees half a file."""
    path = Path(path)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def _marks(values: Sequence[Any]) -> str:
    """The `?, ?` of an SQL IN list over `values`."""
    return ", ".join("?" for _ in values)


def shard_name(batch: int) -> str:
    return "labels-%05d.jsonl" % batch


def _strip_timing(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: _strip_timing(v) for k, v in value.items() if k not in TIMING_FIELDS}
    if isinstance(value, list):
        return [_strip_timing(v) for v in value]
    return value


class Store:
    def __init__(self, data_dir: Optional[Path] = None, recover_on_open: bool = True) -> None:
        self.data_dir = Path(data_dir) if data_dir is not None else default_data_dir()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(self.data_dir / DB_NAME), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        try:
            self.db.executescript(_SCHEMA)
            self._migrate()
            self.db.commit()
        except BaseException:
            self.db.close()
            raise
        if recover_on_open:
            self.recover()

    def _migrate(self) -> None:
        """Add the columns older databases lack (CREATE IF NOT EXISTS keeps old tables)."""
        for table, column, ddl in (
                ("runs", "checkpoint", "REAL NOT NULL DEFAULT 0"),
                ("runs", "active_s", "REAL NOT NULL DEFAULT 0"),
                ("runs", "feature_set", "TEXT NOT NULL DEFAULT ''"),
                ("labels", "features", "TEXT NOT NULL DEFAULT '[]'"),
                ("positions", "info", "TEXT NOT NULL DEFAULT '{}'")):
            have = {r["name"] for r in self.db.execute("PRAGMA table_info(%s)" % table)}
            if column not in have:
                self.db.execute("ALTER TABLE %s ADD COLUMN %s %s" % (table, column, ddl))
                if column == "active_s":  # best estimate for runs from before the column
                    self.db.execute("UPDATE runs SET active_s = MAX(0, updated - created)")
        self._migrate_counters()

    def _migrate_counters(self) -> None:
        """Add the run row's counters to a database from before them and count what it already
        holds, in one transaction, so a crash here leaves the old schema and the next open
        starts again rather than trusting zeros. Digests are left "": hashing every old
        run's shards at open would be slow, so done_digest stores each on first asking."""
        have = {r["name"] for r in self.db.execute("PRAGMA table_info(runs)")}
        if all(column in have for column, _ in _COUNTER_COLUMNS):
            return
        self.db.commit()  # the migrations above may have left a transaction open
        self.db.execute("BEGIN IMMEDIATE")
        try:
            for column, ddl in _COUNTER_COLUMNS:
                if column not in have:
                    self.db.execute("ALTER TABLE runs ADD COLUMN %s %s" % (column, ddl))
            self.db.execute(
                "UPDATE runs SET"
                " n_positions = (SELECT COUNT(*) FROM positions WHERE run_id = runs.id),"
                " n_batches = (SELECT COUNT(DISTINCT batch) FROM positions"
                " WHERE run_id = runs.id),"
                " n_labels = (SELECT COUNT(*) FROM labels WHERE run_id = runs.id),"
                " n_rollouts = (SELECT COALESCE(SUM(n), 0) FROM labels WHERE run_id = runs.id)")
            skipped: Dict[str, int] = {}
            for row in self.db.execute(
                    "SELECT run_id, info FROM positions WHERE info LIKE '%\"skipped\"%'"):
                if "skipped" in json.loads(row["info"]):
                    skipped[row["run_id"]] = skipped.get(row["run_id"], 0) + 1
            self.db.executemany("UPDATE runs SET n_skipped = ? WHERE id = ?",
                                [(count, rid) for rid, count in skipped.items()])
            self.db.commit()
        except BaseException:
            self.db.rollback()
            raise

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

    def set_feature_set(self, run_id: str, feature_set: str) -> None:
        self.db.execute("UPDATE runs SET feature_set = ? WHERE id = ?", (feature_set, run_id))
        self.db.commit()

    # fits

    def create_fit(self, fit_id: str, config: Dict[str, Any], stamp: str, feature_set: str,
                   runs: List[str], state: str = "queued") -> str:
        if state not in FIT_STATES:
            raise ValueError("unknown fit state %r" % (state,))
        now = time.time()
        self.db.execute(
            "INSERT INTO fits (id, state, config, stamp, feature_set, runs, created, updated)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (fit_id, state, json.dumps(config, sort_keys=True), stamp, feature_set,
             json.dumps(runs), now, now))
        self.db.commit()
        return fit_id

    @staticmethod
    def _fit_from_row(row: sqlite3.Row) -> Dict[str, Any]:
        out: Dict[str, Any] = dict(row)
        out["config"] = json.loads(out["config"])
        out["runs"] = json.loads(out["runs"])
        return out

    def get_fit(self, fit_id: str) -> Optional[Dict[str, Any]]:
        row = self.db.execute("SELECT * FROM fits WHERE id = ?", (fit_id,)).fetchone()
        if row is None:
            return None
        return self._fit_from_row(row)

    def list_fits(self) -> List[Dict[str, Any]]:
        return [self._fit_from_row(row)
                for row in self.db.execute("SELECT * FROM fits ORDER BY created, id")]

    def active_fit_id(self) -> Optional[str]:
        row = self.db.execute("SELECT id FROM fits WHERE state IN ('queued', 'running')"
                              " ORDER BY created, id LIMIT 1").fetchone()
        return None if row is None else str(row["id"])

    def set_fit_state(self, fit_id: str, state: str, last_error: Optional[str] = None,
                      report: Optional[str] = None,
                      only_from: Optional[Sequence[str]] = None) -> bool:
        """Move a fit to `state`. With `only_from` the update is a compare-and-set: it applies
        only while the fit's current state is one of those, and returns False (changing
        nothing) otherwise, so a late finisher cannot overwrite a fit already failed by
        `fail_live_fits`. KeyError for an unknown fit; True when the update applied."""
        if state not in FIT_STATES:
            raise ValueError("unknown fit state %r" % (state,))
        sql = ("UPDATE fits SET state = ?, last_error = COALESCE(?, last_error),"
               " report = COALESCE(?, report), updated = ? WHERE id = ?")
        args: List[Any] = [state, last_error, report, time.time(), fit_id]
        if only_from is not None:
            sql += " AND state IN (%s)" % ", ".join("?" for _ in only_from)
            args.extend(only_from)
        cur = self.db.execute(sql, args)
        applied = cur.rowcount > 0
        if not applied and (only_from is None or self.get_fit(fit_id) is None):
            raise KeyError(fit_id)
        self.db.commit()
        return applied

    def fail_live_fits(self, reason: str) -> List[str]:
        """Every queued or running fit becomes failed (a fit has no resume, and its thread
        died with the service that started it). Returns their ids."""
        live = "('queued', 'running')"
        ids = [r["id"] for r in self.db.execute(
            "SELECT id FROM fits WHERE state IN %s ORDER BY id" % live)]
        self.db.execute("UPDATE fits SET state = 'failed', last_error = ?, updated = ?"
                        " WHERE state IN %s" % live, (reason, time.time()))
        self.db.commit()
        return ids

    def active_run_id(self) -> Optional[str]:
        """Id of the first run (by creation) in a live state, or None."""
        row = self.db.execute(
            "SELECT id FROM runs WHERE state IN (%s) ORDER BY created, id LIMIT 1" % _marks(ACTIVE),
            ACTIVE).fetchone()
        return None if row is None else str(row["id"])

    def list_runs_progress(self) -> List[Dict[str, Any]]:
        """Every run as `list_runs` gives it, plus `done`: the first position index after
        its last committed batch (as `resume_point`), in two queries."""
        done = {r["run_id"]: int(r["done"]) for r in self.db.execute(
            'SELECT run_id, MAX("index") + 1 AS done FROM positions GROUP BY run_id')}
        out: List[Dict[str, Any]] = []
        for row in self.db.execute("SELECT * FROM runs ORDER BY created, id"):
            run: Dict[str, Any] = dict(row)
            run["config"] = json.loads(run["config"])
            run["done"] = done.get(run["id"], 0)
            out.append(run)
        return out

    def counts(self, run_id: str) -> Dict[str, int]:
        """Committed positions, labels, rollouts, skipped positions and batches of a run, from
        its row."""
        row = self.db.execute("SELECT n_positions, n_labels, n_rollouts, n_skipped, n_batches"
                              " FROM runs WHERE id = ?", (run_id,)).fetchone()
        if row is None:
            return {"positions": 0, "labels": 0, "rollouts": 0, "skipped": 0, "batches": 0}
        return {"positions": int(row["n_positions"]), "labels": int(row["n_labels"]),
                "rollouts": int(row["n_rollouts"]), "skipped": int(row["n_skipped"]),
                "batches": int(row["n_batches"])}

    def set_state(self, run_id: str, state: str, last_error: Optional[str] = None,
                  expect: Union[str, Sequence[str], None] = None) -> bool:
        """Compare-and-set: move the run to `state` only while it is in `expect` (by default
        any state ENTERED_FROM allows), else change nothing and return False, so a late writer
        cannot overwrite what another thread has just written. ValueError for an unknown
        state or an `expect` the machine does not allow; KeyError for an unknown run."""
        if state not in STATES:
            raise ValueError("unknown run state %r" % (state,))
        allowed = ENTERED_FROM[state]
        if expect is not None:
            wanted = (expect,) if isinstance(expect, str) else tuple(expect)
            for source in wanted:
                if source not in allowed:
                    raise ValueError("no run transition %s -> %s" % (source, state))
            allowed = wanted
        return self._move(run_id, state, last_error, allowed, "")

    def finish(self, run_id: str, state: str, last_error: Optional[str] = None) -> bool:
        """The run thread's last word: a live run becomes done, stopped or failed. False, and
        nothing changes, when it already left the live states (Service.close reclaimed it,
        or an earlier finish won). A done run's digest is stored with its state: its shards
        never change again."""
        if state not in FINISHED_STATES:
            raise ValueError("a run cannot finish as %r" % (state,))
        digest = ""
        if state == "done":
            try:
                digest = self.digest(run_id)
            except (OSError, ValueError):  # done_digest tries again, and reports it, on asking
                digest = ""
        return self._move(run_id, state, last_error, ACTIVE, digest)

    def _move(self, run_id: str, state: str, last_error: Optional[str],
              sources: Sequence[str], digest: str) -> bool:
        cur = self.db.execute(
            "UPDATE runs SET state = ?, last_error = COALESCE(?, last_error),"
            " digest = CASE WHEN ? = '' THEN digest ELSE ? END, updated = ?"
            " WHERE id = ? AND state IN (%s)" % _marks(sources),
            (state, last_error, digest, digest, time.time(), run_id) + tuple(sources))
        applied = cur.rowcount > 0
        self.db.commit()
        if not applied and self.get_run(run_id) is None:
            raise KeyError(run_id)
        return applied

    def set_error(self, run_id: str, last_error: str) -> None:
        """Record a problem that does not change the run's state."""
        self.db.execute("UPDATE runs SET last_error = ?, updated = ? WHERE id = ?",
                        (last_error, time.time(), run_id))
        self.db.commit()

    def done_digest(self, run_id: str) -> str:
        """A done run's digest: stored at finish, or (a run from before the column) worked out
        once now and stored."""
        run = self.get_run(run_id)
        if run is not None and run["digest"]:
            return str(run["digest"])
        digest = self.digest(run_id)
        self.set_digest(run_id, digest)
        return digest

    def set_digest(self, run_id: str, digest: str) -> None:
        self.db.execute("UPDATE runs SET digest = ? WHERE id = ? AND state = 'done'",
                        (digest, run_id))
        self.db.commit()

    def add_active(self, run_id: str, seconds: float) -> None:
        """Add active run time at a session's end (commit_batch adds the batches' own). `updated`
        moves with it, so `now - updated` is the live session's time since this call."""
        self.db.execute("UPDATE runs SET active_s = active_s + ?, updated = ? WHERE id = ?",
                        (max(0.0, float(seconds)), time.time(), run_id))
        self.db.commit()

    def skipped_count(self, run_id: str) -> int:
        """Positions committed as skipped (their info carries a `skipped` reason)."""
        return self.counts(run_id)["skipped"]

    def mark_interrupted(self) -> List[str]:
        """R37: every queued, running or stopping run becomes interrupted (a queued run's
        workers were still starting when the service died). Returns their ids."""
        marks = _marks(ACTIVE)
        ids = [r["id"] for r in self.db.execute(
            "SELECT id FROM runs WHERE state IN (%s) ORDER BY id" % marks, ACTIVE)]
        self.db.execute("UPDATE runs SET state = 'interrupted', updated = ?"
                        " WHERE state IN (%s)" % marks, (time.time(),) + ACTIVE)
        self.db.commit()
        return ids

    # batches

    def commit_batch(self, run_id: str, batch_index: int, positions: List[Dict[str, Any]],
                     labels: List[Dict[str, Any]], active_s: float = 0.0,
                     restarts: int = 0) -> Path:
        """Write the shard and the DB rows so that both or neither survive a crash.

        positions: dicts with index, seed, decks (JSON-able), prefix_len, seat, and optionally
        info (JSON-able: round, turn, hand; kept in the shard when non-empty).
        labels: dicts with position_index, candidate_index, action, mean, spread, n, wins,
        draws, losses, capped, optionally features (the candidate's integer list) and us (timing:
        kept in the shard, not digested).
        active_s and restarts are the active time and worker restarts since the last commit;
        they join the run row's counters in the batch's transaction.
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
            line: Dict[str, Any] = {
                "run": run_id, "position": int(pos["index"]), "seed": str(int(pos["seed"])),
                "decks": pos["decks"], "prefix_len": int(pos["prefix_len"]),
                "seat": int(pos["seat"]), "stamp": run["stamp"], "commit": run["commit"],
                "feature_set": run["feature_set"], "candidates": cands}
            if pos.get("info"):
                line["info"] = pos["info"]
            lines.append(json.dumps(line, sort_keys=True))
        directory = self.run_dir(run_id)
        directory.mkdir(parents=True, exist_ok=True)
        final = directory / shard_name(batch_index)
        write_atomic(final, "".join(line + "\n" for line in lines))
        # A crash here leaves the shard without rows; recover() removes it.
        try:
            with self.db:
                self.db.executemany(
                    'INSERT INTO positions (run_id, "index", seed, decks, prefix_len, seat,'
                    " batch, info) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    [(run_id, int(p["index"]), int(p["seed"]), json.dumps(p["decks"]),
                      int(p["prefix_len"]), int(p["seat"]), batch_index,
                      json.dumps(p.get("info") or {}, sort_keys=True)) for p in positions])
                self.db.executemany(
                    "INSERT INTO labels (run_id, position_index, candidate_index, action,"
                    " mean, spread, n, wins, draws, losses, capped, features)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [(run_id, int(lab["position_index"]), int(lab["candidate_index"]),
                      json.dumps(lab["action"], sort_keys=True), float(lab["mean"]),
                      float(lab["spread"]), int(lab["n"]), int(lab["wins"]), int(lab["draws"]),
                      int(lab["losses"]), int(bool(lab["capped"])),
                      json.dumps([int(x) for x in lab.get("features", [])]))
                     for lab in labels])
                now = time.time()
                self.db.execute(
                    "UPDATE runs SET updated = ?, checkpoint = ?, n_positions = n_positions + ?,"
                    " n_labels = n_labels + ?, n_rollouts = n_rollouts + ?,"
                    " n_skipped = n_skipped + ?, n_batches = n_batches + ?,"
                    " active_s = active_s + ?, restarts = restarts + ? WHERE id = ?",
                    (now, now, len(positions), len(labels),
                     sum(int(lab["n"]) for lab in labels),
                     sum(1 for p in positions if "skipped" in (p.get("info") or {})),
                     1 if positions else 0, max(0.0, float(active_s)), int(restarts), run_id))
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
        return digest_shards(self.shard_paths(run_id))


def digest_shards(paths: Sequence[Path]) -> str:
    """Store.digest over the shards `paths`, in order; reads only the files, not the DB."""
    h = hashlib.sha256()
    for path in paths:
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
