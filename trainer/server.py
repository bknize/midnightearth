"""The trainer MCP server (plan P15, P16; R40 to R50).

Layout. `Service` holds all the logic as plain methods returning JSON-able dicts (errors are
`{"error": text}`), so tests need no `mcp`. `BearerMiddleware` is a pure ASGI wrapper that
answers 401 before any MCP handling. `build_mcp` and `build_app` are the only places that
import `mcp`; `serve` ties them together with uvicorn. Auth uses the middleware path (P15's
fallback): a static bearer token is a poor fit for the OAuth-shaped verifier hook.
"""
import hmac
import json
import os
import platform
import random
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional

from trainer.config import RunConfig
from trainer.farm import REPO_ROOT, Farm, FarmError, godot_bin, worker_command
from trainer.run import execute, git_commit
from trainer.store import Store, default_data_dir
from trainer.sync import RunFn, default_run, stamp_of, sync_code

ACTIVE_STATES = ("queued", "running", "stopping")
LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1")
LOCK_NAME = "serve.lock"
WINDOWS_TOKEN = r"C:\Users\trainer\.trainer\token"
START_CMD = "start-mcp.cmd"
Reply = Dict[str, Any]


class TokenError(Exception):
    pass


def token_path() -> Path:
    env = os.environ.get("TRAINER_TOKEN_FILE")
    if env:
        return Path(env)
    if os.name == "nt":
        return Path(WINDOWS_TOKEN)
    return Path.home() / ".trainer" / "token"


def load_token(path: Optional[Path] = None) -> str:
    """The stripped token, or TokenError with a one-line message (R40). Never echoes it."""
    p = path or token_path()
    try:
        text = p.read_text(encoding="utf-8").strip()
    except OSError:
        raise TokenError("trainer serve: token file missing or unreadable: %s" % p)
    if not text:
        raise TokenError("trainer serve: token file is empty: %s" % p)
    return text


def default_queue() -> Path:
    env = os.environ.get("TRAINER_QUEUE")
    return Path(env) if env else Path.home() / "trainer" / "queue"


def restart_job_text(pid: int, start_cmd: Path) -> str:
    """The runner-queue batch job that restarts the service: wait for the sync reply to go
    out, kill the process that holds the port (the venv launcher above it then ends), wait for
    the port to free, start the service again through its autostart script."""
    lines = ["@echo off",
             "rem restart the trainer service after a sync that changed trainer/",
             "ping -n 4 127.0.0.1 >nul",
             "taskkill /PID %d /F" % pid,
             "ping -n 4 127.0.0.1 >nul",
             "call %s" % start_cmd]
    return "".join(ln + "\r\n" for ln in lines)


def default_root() -> Path:
    env = os.environ.get("TRAINER_ROOT")
    return Path(env) if env else Path.home() / "me"


# --- bearer check -------------------------------------------------------------------------

def check_bearer(header: str, token: str) -> bool:
    scheme, _, value = header.partition(" ")
    if scheme.lower() != "bearer" or not value:
        return False
    return hmac.compare_digest(value.strip().encode("utf-8"), token.encode("utf-8"))


class BearerMiddleware:
    """ASGI wrapper: a missing or wrong bearer token is 401 before the inner app runs."""

    def __init__(self, app: Callable[..., Awaitable[None]], token: str) -> None:
        self.app = app
        self._token = token

    async def __call__(self, scope: Dict[str, Any], receive: Callable[..., Awaitable[Any]],
                       send: Callable[..., Awaitable[None]]) -> None:
        if scope["type"] not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return
        header = ""
        for k, v in scope.get("headers", []):
            if k.lower() == b"authorization":
                header = v.decode("latin-1")
                break
        if check_bearer(header, self._token):
            await self.app(scope, receive, send)
            return
        if scope["type"] == "websocket":
            await send({"type": "websocket.close", "code": 1008})
            return
        body = b'{"error": "unauthorized"}'
        await send({"type": "http.response.start", "status": 401, "headers": [
            (b"content-type", b"application/json"),
            (b"content-length", str(len(body)).encode("ascii")),
            (b"www-authenticate", b"Bearer")]})
        await send({"type": "http.response.body", "body": body})


# --- the service --------------------------------------------------------------------------

def _run_version(argv: List[str]) -> str:
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=30, check=False,
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return ""
    text = (p.stdout or p.stderr).strip()
    return text.splitlines()[0] if text else ""


class Service:
    def __init__(self, data_dir: Optional[Path] = None, root: Optional[Path] = None,
                 farm_factory: Optional[Callable[[RunConfig, Path], Farm]] = None,
                 stamp_fn: Optional[Callable[[], str]] = None,
                 sync_fn: Optional[Callable[..., Reply]] = None,
                 queue_dir: Optional[Path] = None, run_fn: Optional[RunFn] = None,
                 commit_fn: Optional[Callable[[], str]] = None,
                 is_windows: Optional[bool] = None) -> None:
        self.root = Path(root) if root is not None else default_root()
        self.store = Store(data_dir)
        self.data_dir = self.store.data_dir
        self.lock = threading.RLock()
        self.started_at = time.time()
        self.interrupted = self.store.mark_interrupted()
        self._syncing = False
        self._farm: Optional[Farm] = None
        self._probes: Dict[str, str] = {}
        self._farm_factory = farm_factory or self._default_farm
        self._stamp_fn = stamp_fn or self._default_stamp
        self._sync_fn = sync_fn or sync_code
        self.queue_dir = Path(queue_dir) if queue_dir is not None else default_queue()
        self._run_fn: RunFn = run_fn or default_run
        self._windows = os.name == "nt" if is_windows is None else is_windows
        # The commit this process's Python was loaded from: new runs record it, not whatever
        # the checkout holds after a later sync.
        self.service_commit = (commit_fn or (lambda: git_commit(True)))()
        self._thread: Optional[threading.Thread] = None
        self._active_id: Optional[str] = None
        self._stop_flag = threading.Event()
        self._session: Dict[str, Any] = {}

    def close(self, timeout: float = 60.0) -> None:
        """Signal stop, wait up to `timeout` for the run thread, then stop the farm (which
        fails the run's requests so the thread ends) and wait a little more."""
        self._stop_flag.set()
        self.join(timeout)
        t = self._thread
        if t is not None and t.is_alive():
            farm = self._farm
            if farm is not None:
                farm.stop()
            t.join(15.0)
            rid = self._active_id
            run = self.store.get_run(rid) if rid else None
            if run is not None and run["state"] in ("failed",) + ACTIVE_STATES:
                self.store.set_state(run["id"], "interrupted", "service shut down mid-run")
        self.store.close()

    def join(self, timeout: Optional[float] = None) -> None:
        t = self._thread
        if t is not None:
            t.join(timeout)

    # helpers

    def _work(self) -> Path:
        work = self.root / "work"
        return work if (work / "godot").is_dir() else REPO_ROOT

    def _default_stamp(self) -> str:
        return stamp_of(self._work())

    def _default_farm(self, cfg: RunConfig, log_dir: Path) -> Farm:
        cmd = worker_command(godot_bin(), self._work())
        return Farm(cmd, cfg.workers, log_dir=log_dir)

    def _active(self) -> Optional[str]:
        """Id of the run in a live state, or None. Caller holds the lock."""
        return self.store.active_run_id()

    def _counts(self, run_id: str) -> Dict[str, int]:
        return self.store.counts(run_id)

    def _need_run(self, run_id: str) -> Any:
        if not isinstance(run_id, str) or not run_id:
            return {"error": "run_id must be a non-empty string"}
        run = self.store.get_run(run_id)
        if run is None:
            return {"error": "no such run: %s" % run_id}
        return run

    # tools

    def _probe(self, key: str, fn: Callable[[], str]) -> str:
        """A slow version probe, run outside the service lock and cached until a sync."""
        cached = self._probes.get(key)
        if cached is None:
            cached = fn()
            if cached:  # a failed probe is not remembered
                self._probes[key] = cached
        return cached

    def _gpu(self) -> str:
        smi = shutil.which("nvidia-smi")
        if not smi:
            return ""
        return _run_version([smi, "--query-gpu=name,memory.total", "--format=csv,noheader"])

    def _checked_out(self) -> str:
        work = self.root / "work"
        if not (work / ".git").exists():
            return ""
        return _run_version(["git", "-C", str(work), "rev-parse", "HEAD"])

    def health(self) -> Reply:
        try:
            stamp = stamp_of(self._work())
        except (OSError, ValueError) as e:
            stamp = "unavailable: %s" % e
        godot = self._probe("godot", lambda: _run_version([godot_bin(), "--version"]))
        gpu = self._probe("gpu", self._gpu)
        commit = self._probe("commit", self._checked_out)
        with self.lock:
            active = self._active()
            syncing = self._syncing
            farm = self._farm if active else None
        now = time.time()
        return {
            "host": platform.node(), "python": platform.python_version(),
            "mcp": mcp_version(), "godot": godot or "unavailable", "gpu": gpu or "none",
            "free_disk_gb": round(shutil.disk_usage(str(self.data_dir)).free / 1e9, 1),
            "commit": commit or "unknown", "service_commit": self.service_commit,
            "code_stamp": stamp,
            "workers_busy": farm.busy() if farm is not None else 0,
            "workers_total": farm.workers if farm is not None else 0,
            "active_run": active, "syncing": syncing,
            "interrupted_at_start": list(self.interrupted),
            "started_at": self.started_at, "uptime_s": round(now - self.started_at, 1)}

    def sync_code(self, commit: str, bundle_b64: str = "", inbox_file: str = "") -> Reply:
        # The claim is taken under the lock; the minutes of git and Godot work run outside
        # it, so run_status and the other tools stay answerable.
        with self.lock:
            active = self._active()
            if active:
                return {"error": "run %s is active; stop it before syncing" % active}
            if self._syncing:
                return {"error": "a sync is already in progress"}
            self._syncing = True
        try:
            result = self._sync_fn(commit, bundle_b64, inbox_file, root=self.root,
                                   godot_bin=godot_bin(), run_active=None)
            if "error" not in result:
                result["restart"] = self._restart_after_sync(str(result.get("commit", commit)))
            return result
        finally:
            with self.lock:
                self._syncing = False
                self._probes.clear()

    def _restart_after_sync(self, new: str) -> str:
        """"not needed" when nothing under trainer/ differs between the code this process
        runs and the new commit; else schedule a restart through the runner queue
        ("scheduled"), or say one is "needed" (no queue, or not Windows). The diff base is
        the service's own commit, so a trainer/ change from an earlier sync that was never
        restarted is still caught."""
        base = self.service_commit
        if base in ("", "unknown"):
            return "needed"
        if base == new:
            return "not needed"
        rc, out = self._run_fn(["git", "-C", str(self.root / "work"), "diff", "--name-only",
                                base, new, "--", "trainer"], None, dict(os.environ))
        if rc != 0:
            return "needed"
        if not out.strip():
            return "not needed"
        if not self._windows or not self.queue_dir.is_dir():
            return "needed"
        stamp = "%s-%03d" % (time.strftime("%Y%m%d-%H%M%S"), int(time.time() * 1000) % 1000)
        job = self.queue_dir / ("restart-mcp-%s.cmd" % stamp)
        tmp = self.queue_dir / ("restart-mcp-%s.tmp" % stamp)  # the runner only takes *.cmd
        start_cmd = self.queue_dir.parent / "autostart" / START_CMD
        try:
            with open(tmp, "w", encoding="ascii", newline="") as fh:
                fh.write(restart_job_text(os.getpid(), start_cmd))
            os.replace(tmp, job)
        except OSError:
            return "needed"
        return "scheduled"

    def start_run(self, config: Dict[str, Any]) -> Reply:
        try:
            cfg = RunConfig.from_dict(config)
        except ValueError as e:
            return {"error": str(e)}
        with self.lock:
            active = self._active()
            if active:
                return {"error": "run %s is active" % active}
            if self._syncing:
                return {"error": "a sync is in progress"}
            try:
                stamp = self._stamp_fn()
            except (OSError, ValueError) as e:
                return {"error": "stamp: %s" % e}
            run_id = self.store.create_run(cfg.to_dict(), stamp, self.service_commit)
            self._launch(run_id)
            return {"run_id": run_id, "state": "queued", "stamp": stamp,
                    "positions": cfg.positions}

    def _launch(self, run_id: str) -> None:
        self._stop_flag = threading.Event()
        self._active_id = run_id
        self._session = {"t0": time.time(), "done0": self.store.resume_point(run_id)}
        self._thread = threading.Thread(target=self._run_thread,
                                        args=(run_id, self._stop_flag), daemon=True)
        self._thread.start()

    def _run_thread(self, run_id: str, stop: threading.Event) -> None:
        store = Store(self.data_dir, recover_on_open=False)
        try:
            run = store.get_run(run_id)
            cfg = RunConfig.from_dict(run["config"] if run else {})
            farm = self._farm_factory(cfg, self.data_dir / "logs")
            self._farm = farm
            try:
                farm.start()
            except FarmError as e:
                store.set_state(run_id, "failed", str(e))
                return
            try:
                execute(store, run_id, farm, should_stop=stop.is_set)
            finally:
                farm.stop()
            self._write_report(store, run_id)
        except Exception as e:  # keep the service alive whatever the run does
            try:
                store.set_state(run_id, "failed", "%s: %s" % (type(e).__name__, e))
            except Exception:
                pass
        finally:
            self._finalize(store, run_id, stop)
            store.close()

    def _finalize(self, store: Store, run_id: str, stop: threading.Event) -> None:
        """The thread never ends with its run in a live state: with no thread behind it,
        `stopping` (or `running`) would block every new run and sync."""
        try:
            run = store.get_run(run_id)
            if run is None or run["state"] not in ACTIVE_STATES:
                return
            total = int(run["config"].get("positions", 0))
            if store.resume_point(run_id) >= total:
                store.set_state(run_id, "done")
            elif stop.is_set():
                store.set_state(run_id, "stopped")
            else:
                store.set_state(run_id, "failed", "run thread ended while %s" % run["state"])
        except Exception:
            pass

    def _write_report(self, store: Store, run_id: str) -> None:
        report = self._report(store, run_id)
        path = store.run_dir(run_id) / "report.json"
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(report, sort_keys=True, indent=1), encoding="utf-8")
        os.replace(tmp, path)

    def _report(self, store: Store, run_id: str) -> Reply:
        run = store.get_run(run_id) or {}
        c = store.counts(run_id)
        hist: Dict[str, int] = {}
        spreads: List[float] = []
        for row in store.db.execute(
                "SELECT position_index, COUNT(*) AS c, MAX(mean) - MIN(mean) AS s FROM labels"
                " WHERE run_id = ? GROUP BY position_index", (run_id,)):
            hist[str(row["c"])] = hist.get(str(row["c"]), 0) + 1
            spreads.append(float(row["s"]))
        wall = max(0.0, float(run.get("active_s", 0.0)))  # active time, not created to updated
        rollouts = c["rollouts"]
        return {
            "run_id": run_id, "state": run.get("state"), "config": run.get("config"),
            "stamp": run.get("stamp"), "commit": run.get("commit"), "positions": c["positions"],
            "skipped": c["skipped"], "labels": c["labels"], "rollouts": rollouts, "wall_s": round(wall, 2),
            "rollouts_per_s": round(rollouts / wall, 2) if wall > 0 else 0.0,
            "restarts": run.get("restarts", 0), "candidate_count_histogram": hist,
            "mean_value_spread": round(sum(spreads) / len(spreads), 4) if spreads else 0.0,
            "digest": store.digest(run_id),
            "shards": [str(p) for p in store.shard_paths(run_id)]}

    def run_status(self, run_id: str) -> Reply:
        with self.lock:
            run = self._need_run(run_id)
            if "error" in run:
                return run
            c = self._counts(run_id)
            cfg = run["config"]
            total = int(cfg.get("positions", 0))
            live = run["state"] in ACTIVE_STATES and self._active_id == run_id
            now = time.time()
            # Active time only: stored seconds plus the live session since its last
            # settlement (`updated` moves with each one), never the stopped gaps.
            elapsed = max(0.0, float(run["active_s"]))
            if live:
                elapsed += max(0.0, now - float(run["updated"]))
            rate = 0.0
            eta: Optional[float] = None
            if live:
                span = now - float(self._session.get("t0", now))
                new = c["positions"] - int(self._session.get("done0", 0))
                if span > 0 and new > 0:
                    eta = round((total - c["positions"]) * span / new, 1)
                    rate = round(new / span, 3)
            checkpoint = float(run.get("checkpoint", 0.0))
            out: Reply = {
                "run_id": run_id, "state": run["state"], "positions_done": c["positions"],
                "positions_total": total, "skipped": c["skipped"], "batches": c["batches"], "labels": c["labels"],
                "rollouts": c["rollouts"], "restarts": run["restarts"],
                "positions_per_s": rate,
                "rollouts_per_s": round(c["rollouts"] / elapsed, 2) if elapsed > 0 else 0.0,
                "rollouts_per_min": round(c["rollouts"] * 60 / elapsed, 1) if elapsed > 0 else 0.0,
                "labels_per_hour": round(c["labels"] * 3600 / elapsed, 1) if elapsed > 0 else 0.0,
                "last_checkpoint": checkpoint if checkpoint > 0 else None,
                "elapsed_s": round(elapsed, 1), "eta_s": eta,
                "last_error": run["last_error"]}
            if run["state"] == "done":
                out["digest"] = self.store.digest(run_id)
            return out

    def stop_run(self, run_id: str) -> Reply:
        with self.lock:
            run = self._need_run(run_id)
            if "error" in run:
                return run
            if run["state"] not in ACTIVE_STATES:
                return {"error": "run %s is %s, not running" % (run_id, run["state"])}
            t = self._thread
            live = self._active_id == run_id and t is not None and t.is_alive()
            if not live:
                # No thread behind the run (cannot happen after recovery, but never leave
                # a live state with nobody to end it).
                self.store.set_state(run_id, "stopped")
                return {"run_id": run_id, "state": "stopped"}
            self._stop_flag.set()
            # Atomic against the run thread's own final write: only a queued or running
            # run becomes stopping, so a run that just finished stays done.
            if not self.store.request_stop(run_id):
                after = self.store.get_run(run_id)
                state = after["state"] if after else "unknown"
                if state == "stopping":
                    return {"run_id": run_id, "state": "stopping"}
                return {"error": "run %s is %s, not running" % (run_id, state)}
            return {"run_id": run_id, "state": "stopping"}

    def resume_run(self, run_id: str) -> Reply:
        with self.lock:
            run = self._need_run(run_id)
            if "error" in run:
                return run
            if run["state"] not in ("stopped", "interrupted"):
                return {"error": "run %s is %s; only stopped or interrupted runs resume"
                        % (run_id, run["state"])}
            active = self._active()
            if active:
                return {"error": "run %s is active" % active}
            if self._syncing:
                return {"error": "a sync is in progress"}
            try:
                now_stamp = self._stamp_fn()
            except (OSError, ValueError) as e:
                return {"error": "stamp: %s" % e}
            if now_stamp != run["stamp"]:
                return {"error": "code stamp %s differs from the run's %s"
                        % (now_stamp, run["stamp"])}
            self.store.set_state(run_id, "queued", "")
            self._launch(run_id)
            return {"run_id": run_id, "state": "queued",
                    "resume_from": self.store.resume_point(run_id)}

    def list_runs(self) -> Reply:
        with self.lock:
            runs = []
            for r in self.store.list_runs_progress():
                runs.append({"run_id": r["id"], "state": r["state"], "stamp": r["stamp"],
                             "commit": r["commit"], "created": r["created"],
                             "positions_done": r["done"],
                             "positions_total": r["config"].get("positions")})
            return {"runs": runs}

    def get_report(self, run_id: str) -> Reply:
        with self.lock:
            run = self._need_run(run_id)
            if "error" in run:
                return run
            path = self.store.run_dir(run_id) / "report.json"
            if not path.is_file():
                return {"error": "no report yet: run %s is %s" % (run_id, run["state"])}
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError) as e:
                return {"error": "report unreadable: %s" % e}

    def sample_positions(self, run_id: str, n: int = 5, seed: int = 0) -> Reply:
        with self.lock:
            run = self._need_run(run_id)
            if "error" in run:
                return run
            if isinstance(n, bool) or not isinstance(n, int) or n < 1:
                return {"error": "n must be a positive integer"}
            if isinstance(seed, bool) or not isinstance(seed, int):
                return {"error": "seed must be an integer"}
            db = self.store.db
            indexes = [r["index"] for r in db.execute(
                'SELECT "index" FROM positions WHERE run_id = ? ORDER BY "index"', (run_id,))]
            picked = sorted(random.Random(seed).sample(indexes, min(n, len(indexes))))
            out = []
            for i in picked:
                p = db.execute('SELECT * FROM positions WHERE run_id = ? AND "index" = ?',
                               (run_id, i)).fetchone()
                cands = []
                for c in db.execute(
                        "SELECT * FROM labels WHERE run_id = ? AND position_index = ?"
                        " ORDER BY mean DESC, candidate_index", (run_id, i)):
                    cands.append({"candidate_index": c["candidate_index"],
                                  "action": json.loads(c["action"]), "mean": c["mean"],
                                  "spread": c["spread"], "n": c["n"], "wins": c["wins"],
                                  "draws": c["draws"], "losses": c["losses"],
                                  "capped": bool(c["capped"])})
                info = json.loads(p["info"])
                out.append({"position": i, "seat": p["seat"], "round": info.get("round"),
                            "turn": info.get("turn"), "hand": info.get("hand", []),
                            "prefix_len": p["prefix_len"], "seed": str(p["seed"]),
                            "decks": json.loads(p["decks"]), "candidates": cands})
            return {"run_id": run_id, "positions": out}


# --- mcp wiring (the only code that imports mcp) --------------------------------------------

def build_mcp(service: Service) -> Any:
    from mcp.server.mcpserver import MCPServer
    mcp = MCPServer("bot-trainer")

    def guarded(fn: Callable[..., Reply]) -> Callable[..., Reply]:
        def call(*args: Any, **kwargs: Any) -> Reply:
            try:
                return fn(*args, **kwargs)
            except Exception as e:
                return {"error": "%s: %s" % (type(e).__name__, e)}
        return call

    @mcp.tool()
    def health() -> Dict[str, Any]:
        """Host, Python, Godot, GPU, free disk, code stamp, active run, uptime."""
        return guarded(service.health)()

    @mcp.tool()
    def sync_code(commit: str, bundle_b64: str = "", inbox_file: str = "") -> Dict[str, Any]:
        """Bring a git bundle (inline or from the inbox) in and check the commit out."""
        return guarded(service.sync_code)(commit, bundle_b64, inbox_file)

    @mcp.tool()
    def start_run(config: Dict[str, Any]) -> Dict[str, Any]:
        """Start a labelling run; refused while another run is active."""
        return guarded(service.start_run)(config)

    @mcp.tool()
    def run_status(run_id: str) -> Dict[str, Any]:
        """State, progress, restarts, rate, elapsed, eta and last error of a run."""
        return guarded(service.run_status)(run_id)

    @mcp.tool()
    def stop_run(run_id: str) -> Dict[str, Any]:
        """Stop a run at the next batch boundary."""
        return guarded(service.stop_run)(run_id)

    @mcp.tool()
    def resume_run(run_id: str) -> Dict[str, Any]:
        """Resume a stopped or interrupted run."""
        return guarded(service.resume_run)(run_id)

    @mcp.tool()
    def list_runs() -> Dict[str, Any]:
        """Every run with its state."""
        return guarded(service.list_runs)()

    @mcp.tool()
    def get_report(run_id: str) -> Dict[str, Any]:
        """The report.json of a finished or stopped run."""
        return guarded(service.get_report)(run_id)

    @mcp.tool()
    def sample_positions(run_id: str, n: int = 5, seed: int = 0) -> Dict[str, Any]:
        """n labelled positions chosen with the seed, candidates ordered by mean."""
        return guarded(service.sample_positions)(run_id, n, seed)

    return mcp


def build_app(mcp: Any, token: str, host: str = "127.0.0.1") -> Any:
    """The streamable-HTTP ASGI app of the MCP server, behind the bearer check.

    `host` is the address the server binds. mcp 2.x turns DNS-rebinding protection on for a
    loopback bind and then accepts only loopback Host headers; a LAN bind would answer 421
    to every request. For a non-loopback bind the protection is switched off explicitly:
    the bearer token (checked first, in BearerMiddleware) is the guard on the LAN."""
    make = getattr(mcp, "streamable_http_app", None)
    if make is None:
        raise RuntimeError("this mcp version has no streamable_http_app()")
    kwargs: Dict[str, Any] = {"host": host}
    if host not in LOOPBACK_HOSTS:
        from mcp.server.transport_security import TransportSecuritySettings
        kwargs["transport_security"] = TransportSecuritySettings(
            enable_dns_rebinding_protection=False)
    return BearerMiddleware(make(**kwargs), token)


def mcp_version() -> str:
    try:
        from importlib.metadata import version
        return version("mcp")
    except Exception:
        return "unavailable"


def _opt(args: List[str], name: str, default: str) -> str:
    if name in args:
        i = args.index(name)
        if i + 1 < len(args):
            return args[i + 1]
    return default


def acquire_serve_lock(data_dir: Path) -> Any:
    """Take the exclusive serve lock in the data dir and return the open file, to be held for
    the life of the process (the OS drops it on exit, however the process dies). Raises
    RuntimeError when another serve holds it. Touches nothing else in the data dir."""
    data_dir.mkdir(parents=True, exist_ok=True)
    fh = open(data_dir / LOCK_NAME, "a+b")
    try:
        if os.name == "nt":
            import msvcrt
            fh.seek(0)
            msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)  # type: ignore[attr-defined]
        else:
            import fcntl
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fh.close()
        raise RuntimeError("trainer serve: another serve already uses %s" % data_dir)
    return fh


def serve(args: List[str]) -> int:
    """`serve [--host H] [--port 8765] [--data DIR]`. Exit 2 without a usable token, 1 when
    another serve holds the data dir (checked before the store is opened or recovered)."""
    try:
        token = load_token()
    except TokenError as e:
        print(str(e), file=sys.stderr)
        return 2
    host = _opt(args, "--host", "0.0.0.0")
    port = int(_opt(args, "--port", "8765"))
    data = _opt(args, "--data", "")
    data_dir = Path(data) if data else default_data_dir()
    try:
        lock = acquire_serve_lock(data_dir)
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        return 1
    service = Service(data_dir)
    try:
        import uvicorn
        app = build_app(build_mcp(service), token, host)
        uvicorn.run(app, host=host, port=port, log_level="info")
    finally:
        service.close()
        lock.close()
    return 0
