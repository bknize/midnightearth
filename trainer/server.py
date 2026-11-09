"""The trainer MCP server (plan P15, P16; R40 to R50).

Layout. `Service` holds all the logic as plain methods returning JSON-able dicts (errors are
`{"error": text}`), so tests need no `mcp`. `BearerMiddleware` is a pure ASGI wrapper that
answers 401 before any MCP handling. `build_mcp` and `build_app` are the only places that
import `mcp`; `serve` ties them together with uvicorn. Auth uses the middleware path (P15's
fallback): a static bearer token is a poor fit for the OAuth-shaped verifier hook.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import platform
import random
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional

from trainer.config import FitConfig, RunConfig
from trainer.farm import Farm, FarmError, worker_command
from trainer.fit import REPORT_NAME, FitError, run_fit, validate_runs
from trainer.repo import REPO_ROOT, GodotNotFound, git_head, godot_bin, stamp_of
from trainer.run import execute
from trainer.store import (ACTIVE, LIVE_FIT, RESUMABLE, WEIGHTS_NAME, Store, default_data_dir,
                           digest_shards, weights_path, write_atomic)
from trainer.sync import RunFn, default_run, sync_code

LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1")
LOCK_NAME = "serve.lock"
WINDOWS_TOKEN = r"C:\Users\trainer\.trainer\token"
# The restart after a sync (R36): the service replies, exits with RESTART_EXIT and the loop in
# start-mcp.cmd, which sets RESTART_LOOP_ENV, starts it again. With no loop it stays up.
RESTART_EXIT = 75
RESTART_LOOP_ENV = "TRAINER_RESTART_LOOP"
RESTART_DELAY_S = 3.0  # time for the sync reply to go out
SHUTDOWN_GRACE_S = 10  # uvicorn's wait for open connections
RESTART_DEADLINE_S = 90.0  # a shutdown still hung after this exits hard
Reply = Dict[str, Any]
FitFn = Callable[..., Dict[str, Any]]
# get_artifact serves exactly these files of a fit's own folder (plan P12).
ARTIFACTS = {"weights": WEIGHTS_NAME, "report": REPORT_NAME}
ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


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


def _default_sync(commit: str, bundle_b64: str, inbox_file: str, *, root: Path,
                  run_active: Optional[str] = None) -> Reply:
    try:
        binary = godot_bin()
    except GodotNotFound as e:
        return {"error": str(e)}
    return sync_code(commit, bundle_b64, inbox_file, root=root, godot_bin=binary,
                     run_active=run_active)


class ActiveRun:
    """The run this service last launched: what the service holds on it while it runs. Its
    state lives in the store. `thread` is set before the thread starts; `farm` once the run
    thread has built it."""

    def __init__(self, run_id: str, done0: int) -> None:
        self.run_id = run_id
        self.done0 = done0  # positions committed before this session
        self.started = time.time()
        self.stop = threading.Event()
        self.thread: Optional[threading.Thread] = None
        self.farm: Optional[Farm] = None

    def alive(self) -> bool:
        return self.thread is not None and self.thread.is_alive()


class Service:
    def __init__(self, data_dir: Optional[Path] = None, root: Optional[Path] = None,
                 farm_factory: Optional[Callable[[RunConfig, Path], Farm]] = None,
                 stamp_fn: Optional[Callable[[], str]] = None,
                 sync_fn: Optional[Callable[..., Reply]] = None,
                 run_fn: Optional[RunFn] = None,
                 commit_fn: Optional[Callable[[], str]] = None,
                 fit_fn: Optional[FitFn] = None,
                 restart_fn: Optional[Callable[[], None]] = None) -> None:
        self.root = Path(root) if root is not None else default_root()
        self.store = Store(data_dir)
        self.data_dir = self.store.data_dir
        self.lock = threading.RLock()
        self.started_at = time.time()
        self.interrupted = self.store.mark_interrupted()
        self.store.fail_live_fits("service restarted mid-fit")
        self._fit_fn: FitFn = fit_fn or run_fit
        self._fit_thread: Optional[threading.Thread] = None
        self._fit_stop = threading.Event()
        self._syncing = False
        self._probes: Dict[str, str] = {}
        self._farm_factory = farm_factory or self._default_farm
        self._stamp_fn = stamp_fn or self._default_stamp
        self._sync_fn = sync_fn or _default_sync
        self._run_fn: RunFn = run_fn or default_run
        # Ends this process so that it starts again on the new code; None with no restart loop
        # behind it (`serve` sets it).
        self.restart_fn = restart_fn
        self._restarting = False
        # The commit this process's Python was loaded from: new runs record it, not whatever
        # the checkout holds after a later sync.
        self.service_commit = (commit_fn or (lambda: git_head() or "unknown"))()
        self._run: Optional[ActiveRun] = None

    def close(self, timeout: float = 60.0) -> None:
        """Signal stop, wait up to `timeout` for the run thread, then stop the farm (which
        fails the run's requests so the thread ends) and wait a little more."""
        handle = self._run
        if handle is not None:
            handle.stop.set()
        self._fit_stop.set()
        ft = self._fit_thread
        if ft is not None:
            ft.join(min(timeout, 15.0))
            if ft.is_alive():  # a stuck fit: leave no live state behind
                self.store.fail_live_fits("service shut down mid-fit")
        self.join(timeout)
        if handle is not None and handle.alive():
            if handle.farm is not None:
                handle.farm.stop()
            if handle.thread is not None:
                handle.thread.join(15.0)
            self.store.set_state(handle.run_id, "interrupted", "service shut down mid-run")
        self.store.close()

    def join(self, timeout: Optional[float] = None) -> None:
        handle = self._run
        if handle is not None and handle.thread is not None:
            handle.thread.join(timeout)

    def join_fit(self, timeout: Optional[float] = None) -> None:
        t = self._fit_thread
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

    def _godot_version(self) -> str:
        try:
            return _run_version([godot_bin(), "--version"])
        except GodotNotFound:
            return ""

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
        return git_head(work)

    def health(self) -> Reply:
        try:
            stamp = stamp_of(self._work())
        except (OSError, ValueError) as e:
            stamp = "unavailable: %s" % e
        godot = self._probe("godot", self._godot_version)
        gpu = self._probe("gpu", self._gpu)
        commit = self._probe("commit", self._checked_out)
        with self.lock:
            active = self._active()
            syncing = self._syncing
            handle = self._run
            farm = handle.farm if active and handle is not None else None
        now = time.time()
        return {
            "host": platform.node(), "python": platform.python_version(),
            "mcp": mcp_version(), "numpy": numpy_version(), "godot": godot or "unavailable", "gpu": gpu or "none",
            "free_disk_gb": round(shutil.disk_usage(str(self.data_dir)).free / 1e9, 1),
            "commit": commit or "unknown", "service_commit": self.service_commit,
            "code_stamp": stamp,
            "workers_busy": farm.busy() if farm is not None else 0,
            "workers_total": farm.workers if farm is not None else 0,
            "active_run": active, "syncing": syncing,
            "restart_loop": self.restart_fn is not None,
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
                                   run_active=None)
            if "error" not in result:
                result["restart"] = self._restart_after_sync(str(result.get("commit", commit)))
            return result
        finally:
            with self.lock:
                # While a restart is on its way no new run or sync may start under it.
                self._syncing = self._restarting
                self._probes.clear()

    def _restart_after_sync(self, new: str) -> str:
        """"not needed" when nothing under trainer/ differs between the code this process
        runs and the new commit; else end this process to restart it on the new code
        ("scheduled"), or say a restart is "needed" (no restart loop behind it). The diff base
        is the service's own commit, so a trainer/ change from an earlier sync that was never
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
        if self.restart_fn is None:
            return "needed"
        self._restarting = True
        self.restart_fn()
        return "scheduled"

    def start_run(self, config: Dict[str, Any]) -> Reply:
        try:
            cfg = RunConfig.from_dict(config)
        except ValueError as e:
            return {"error": str(e)}
        for name in ("rollout_weights", "generator_weights"):
            problem = self._check_fit(getattr(cfg, name), name)
            if problem:
                return {"error": problem}
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

    def _check_fit(self, fit_id: str, field: str) -> str:
        """"" when `fit_id` is empty or names a finished fit whose weights file exists, else
        the error text (R21)."""
        if not fit_id:
            return ""
        fit = self.store.get_fit(fit_id)
        if fit is None:
            return "%s: unknown fit %s" % (field, fit_id)
        if fit["state"] != "done":
            return "%s: fit %s is %s, not done" % (field, fit_id, fit["state"])
        if not Path(weights_path(self.data_dir, fit_id)).is_file():
            return "%s: fit %s has no weights file" % (field, fit_id)
        try:  # the workers refuse a weights file of another stamp, so refuse it up front
            current = self._stamp_fn()
        except (OSError, ValueError) as e:
            return "%s: stamp: %s" % (field, e)
        if fit["stamp"] != current:
            return ("%s: fit %s is under stamp %s, the code is at %s"
                    % (field, fit_id, fit["stamp"], current))
        return ""

    def _launch(self, run_id: str) -> None:
        handle = ActiveRun(run_id, self.store.resume_point(run_id))
        handle.thread = threading.Thread(target=self._run_thread, args=(handle,), daemon=True)
        self._run = handle
        handle.thread.start()

    def _run_thread(self, handle: ActiveRun) -> None:
        run_id = handle.run_id
        store = Store(self.data_dir, recover_on_open=False)
        try:
            run = store.get_run(run_id)
            cfg = RunConfig.from_dict(run["config"] if run else {})
            farm = self._farm_factory(cfg, self.data_dir / "logs")
            handle.farm = farm
            try:
                farm.start()
            except FarmError as e:
                store.finish(run_id, "failed", str(e))
                return
            try:
                execute(store, run_id, farm, should_stop=handle.stop.is_set)
            finally:
                farm.stop()
            self._write_report_safely(store, run_id)
        except Exception as e:  # keep the service alive whatever the run does
            try:
                store.finish(run_id, "failed", "%s: %s" % (type(e).__name__, e))
            except Exception:
                pass
        finally:
            # With no thread behind it a live state would block every new run and sync. This
            # changes nothing when the run has finished already.
            try:
                store.finish(run_id, "failed", "run thread ended before the run did")
            except Exception:
                pass
            store.close()

    def _write_report_safely(self, store: Store, run_id: str) -> None:
        """A report that cannot be written never fails a run whose labels are committed: the
        state stays, the error goes to `last_error`, and `get_report` rebuilds on demand."""
        try:
            self._write_report(store, run_id)
        except Exception as e:
            store.set_error(run_id, "report not written: %s: %s" % (type(e).__name__, e))

    def _write_report(self, store: Store, run_id: str) -> None:
        report = self._report(store, run_id)
        write_atomic(store.run_dir(run_id) / "report.json",
                     json.dumps(report, sort_keys=True, indent=1))

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
            "digest": (store.done_digest(run_id)
                       if run.get("state") == "done" else store.digest(run_id)),
            "shards": [str(p) for p in store.shard_paths(run_id)]}

    def run_status(self, run_id: str) -> Reply:
        with self.lock:
            if isinstance(run_id, str) and self.store.get_run(run_id) is None:
                fit = self.store.get_fit(run_id)
                if fit is not None:
                    return self._fit_status(fit)
            run = self._need_run(run_id)
            if "error" in run:
                return run
            c = self.store.counts(run_id)
            cfg = run["config"]
            total = int(cfg.get("positions", 0))
            handle = self._run
            live = (handle if handle is not None and handle.run_id == run_id
                    and run["state"] in ACTIVE else None)
            now = time.time()
            # Active time only: stored seconds plus the live session since its last
            # settlement (`updated` moves with each one), never the stopped gaps.
            elapsed = max(0.0, float(run["active_s"]))
            if live is not None:
                elapsed += max(0.0, now - float(run["updated"]))
            rate = 0.0
            eta: Optional[float] = None
            if live is not None:
                span = now - live.started
                new = c["positions"] - live.done0
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
            done = run["state"] == "done"
            digest = str(run["digest"])
            paths = self.store.shard_paths(run_id) if done and not digest else []
        if done:
            if not digest:  # a run from before the column: hashed once, outside the lock
                digest = digest_shards(paths)
                with self.lock:
                    self.store.set_digest(run_id, digest)
            out["digest"] = digest
        return out

    def stop_run(self, run_id: str) -> Reply:
        with self.lock:
            run = self._need_run(run_id)
            if "error" in run:
                return run
            if run["state"] not in ACTIVE:
                return {"error": "run %s is %s, not running" % (run_id, run["state"])}
            handle = self._run
            if handle is None or handle.run_id != run_id or not handle.alive():
                # No thread behind the run (cannot happen after recovery, but never leave
                # a live state with nobody to end it).
                self.store.set_state(run_id, "stopped", expect=ACTIVE)
                return {"run_id": run_id, "state": "stopped"}
            handle.stop.set()
            # Atomic against the run thread's finish: only a queued or running run becomes
            # stopping, so a run that just finished stays done.
            if not self.store.set_state(run_id, "stopping"):
                after = self.store.get_run(run_id)
                state = after["state"] if after else "unknown"
                if state != "stopping":
                    return {"error": "run %s is %s, not running" % (run_id, state)}
            return {"run_id": run_id, "state": "stopping"}

    def resume_run(self, run_id: str) -> Reply:
        with self.lock:
            run = self._need_run(run_id)
            if "error" in run:
                return run
            if run["state"] not in RESUMABLE:
                return {"error": "run %s is %s; only stopped or interrupted runs resume"
                        % (run_id, run["state"])}
            active = self._active()
            if active:
                return {"error": "run %s is active" % active}
            if self._syncing:
                return {"error": "a sync is in progress"}
            for live in self.store.list_fits():  # its labels must not change under a fit
                if live["state"] in LIVE_FIT and run_id in live["runs"]:
                    return {"error": "fit %s is %s and reads run %s; resume after it ends"
                            % (live["id"], live["state"], run_id)}
            try:
                now_stamp = self._stamp_fn()
            except (OSError, ValueError) as e:
                return {"error": "stamp: %s" % e}
            if now_stamp != run["stamp"]:
                return {"error": "code stamp %s differs from the run's %s"
                        % (now_stamp, run["stamp"])}
            self.store.set_state(run_id, "queued", "", expect=RESUMABLE)
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
            for f in self.store.list_fits():
                runs.append({"run_id": f["id"], "fit_id": f["id"], "kind": "fit",
                             "state": f["state"], "stamp": f["stamp"],
                             "feature_set": f["feature_set"], "created": f["created"],
                             "runs": f["runs"]})
            return {"runs": runs}

    def get_report(self, run_id: str) -> Reply:
        with self.lock:
            if isinstance(run_id, str) and self.store.get_run(run_id) is None:
                fit = self.store.get_fit(run_id)
                if fit is not None:
                    return self._fit_report(fit)
            run = self._need_run(run_id)
            if "error" in run:
                return run
            path = self.store.run_dir(run_id) / "report.json"
            if not path.is_file() and run["state"] == "done":
                try:  # the write failed (see last_error): rebuild it from the store
                    return self._report(self.store, run_id)
                except Exception as e:
                    return {"error": "report unavailable: %s" % e}
            if not path.is_file():
                return {"error": "no report yet: run %s is %s" % (run_id, run["state"])}
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError) as e:
                return {"error": "report unreadable: %s" % e}

    # fits (spec R23 to R28, R30; plan P11, P12)

    def fit_dir(self, fit_id: str) -> Path:
        return self.data_dir / "fits" / fit_id

    def fit(self, config: Dict[str, Any]) -> Reply:
        """Validate a fit config and start the learner job; one fit at a time, and a labelling
        run may be active (the fit reads only finished runs)."""
        try:
            cfg = FitConfig.from_dict(config)
        except ValueError as e:
            return {"error": str(e)}
        with self.lock:
            # Validate and create under one hold of the lock, so resume_run (which takes the
            # same lock) cannot flip a run to queued in between. Only the short database
            # reads and the insert run here; the fit itself runs on its own thread.
            try:
                stamp, feature_set = validate_runs(self.store, cfg.runs)
            except FitError as e:
                return {"error": str(e)}
            active = self.store.active_fit_id()
            if active:
                return {"error": "fit %s is active" % active}
            fit_id = uuid.uuid4().hex[:12]
            self.store.create_fit(fit_id, cfg.to_dict(), stamp, feature_set, sorted(cfg.runs))
            self._fit_stop = threading.Event()
            self._fit_thread = threading.Thread(
                target=self._fit_job, args=(fit_id, cfg, self._fit_stop), daemon=True)
            self._fit_thread.start()
            return {"fit_id": fit_id, "state": "queued", "stamp": stamp,
                    "feature_set": feature_set, "runs": sorted(cfg.runs)}

    def _fit_job(self, fit_id: str, cfg: FitConfig, stop: threading.Event) -> None:
        store = Store(self.data_dir, recover_on_open=False)
        try:
            # Compare-and-set throughout: a fit failed meanwhile (Service.close on a stuck
            # fit) stays failed, whatever this thread does late.
            if not store.set_fit_state(fit_id, "running", only_from=("queued",)):
                return
            report = self._fit_fn(store, fit_id, cfg, self.fit_dir(fit_id), self._work(),
                                  should_stop=stop.is_set)
            store.set_fit_state(fit_id, "done", "", json.dumps(report, sort_keys=True),
                                only_from=LIVE_FIT)
        except Exception as e:  # a failed fit never takes the service with it
            try:
                store.set_fit_state(fit_id, "failed", "%s: %s" % (type(e).__name__, e),
                                    only_from=LIVE_FIT)
            except Exception:
                pass
        finally:
            try:  # never end with the fit in a live state
                row = store.get_fit(fit_id)
                if row is not None and row["state"] in LIVE_FIT:
                    store.set_fit_state(fit_id, "failed",
                                        "fit thread ended while %s" % row["state"],
                                        only_from=LIVE_FIT)
            except Exception:
                pass
            store.close()

    def _fit_status(self, fit: Dict[str, Any]) -> Reply:
        live = fit["state"] in LIVE_FIT
        end = time.time() if live else float(fit["updated"])
        pairs = 0
        if fit["report"]:
            try:
                pairs = int(json.loads(fit["report"])["pairs"]["total"])
            except (ValueError, KeyError, TypeError):
                pairs = 0
        return {"kind": "fit", "fit_id": fit["id"], "state": fit["state"],
                "runs": fit["runs"], "stamp": fit["stamp"], "feature_set": fit["feature_set"],
                "pairs": pairs, "elapsed_s": round(max(0.0, end - float(fit["created"])), 1),
                "last_error": fit["last_error"]}

    def _fit_report(self, fit: Dict[str, Any]) -> Reply:
        if fit["state"] != "done":
            return {"error": "no report yet: fit %s is %s" % (fit["id"], fit["state"])}
        try:
            text = (self.fit_dir(fit["id"]) / REPORT_NAME).read_text(encoding="utf-8")
            return json.loads(text)
        except (OSError, ValueError):
            pass
        try:
            return json.loads(fit["report"])
        except ValueError as e:
            return {"error": "report unreadable: %s" % e}

    def get_artifact(self, fit_id: str, name: str = "weights") -> Reply:
        """A finished fit's weights file or report, inline as base64 with its length and
        SHA-256. Only the two whitelisted files of the fit's own folder are ever read."""
        if not isinstance(fit_id, str) or not ID_PATTERN.match(fit_id):
            return {"error": "fit_id must be a fit id"}
        if not isinstance(name, str) or name not in ARTIFACTS:
            return {"error": "unknown artifact %r; one of %s"
                    % (name, ", ".join(sorted(ARTIFACTS)))}
        fit = self.store.get_fit(fit_id)
        if fit is None:
            return {"error": "no such fit: %s" % fit_id}
        if fit["state"] != "done":
            return {"error": "fit %s is %s, not done" % (fit_id, fit["state"])}
        folder = self.fit_dir(fit_id).resolve()
        path = (folder / ARTIFACTS[name]).resolve()
        if path.parent != folder or not path.is_file():
            return {"error": "fit %s has no %s file" % (fit_id, name)}
        try:
            data = path.read_bytes()
        except OSError as e:
            return {"error": "artifact unreadable: %s" % e}
        return {"fit_id": fit_id, "name": name, "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "base64": base64.b64encode(data).decode("ascii")}

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
    def fit(config: Dict[str, Any]) -> Dict[str, Any]:
        """Learn a weights file from finished runs (one fit at a time); returns the fit id."""
        return guarded(service.fit)(config)

    @mcp.tool()
    def get_artifact(fit_id: str, name: str = "weights") -> Dict[str, Any]:
        """A fit's weights file or report (name: weights or report) as base64 with sha256."""
        return guarded(service.get_artifact)(fit_id, name)

    @mcp.tool()
    def run_status(run_id: str) -> Dict[str, Any]:
        """State, progress, restarts, rate, elapsed, eta and last error of a run or a fit."""
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


def numpy_version() -> str:
    """numpy's version, or "none" when it is not installed (only the learner needs it)."""
    try:
        from importlib.metadata import version
        return version("numpy")
    except Exception:
        return "none"


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


def _serve_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -I trainer serve", allow_abbrev=False)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--data", default="", help="the run store's folder")
    return parser


def exit_later(server: Any, flag: threading.Event, delay: float = RESTART_DELAY_S,
               deadline: Optional[float] = RESTART_DEADLINE_S) -> None:
    """Mark the restart in `flag` and stop the uvicorn `server` after `delay`, so the reply
    in hand goes out first. A shutdown still hung after `deadline` ends the process: no run is
    active across a sync, and the database is committed."""
    flag.set()

    def stop() -> None:
        server.should_exit = True

    def force() -> None:
        os._exit(RESTART_EXIT)

    timers = [threading.Timer(delay, stop)]
    if deadline is not None:
        timers.append(threading.Timer(deadline, force))
    for timer in timers:
        timer.daemon = True
        timer.start()


def serve(args: List[str]) -> int:
    """`serve [--host H] [--port 8765] [--data DIR]`. Exit 2 without a usable token, 1 when
    another serve holds the data dir (checked before the store is opened or recovered), 3 when
    the server cannot start, RESTART_EXIT when a sync asks for a restart."""
    opts = _serve_parser().parse_args(args)
    try:
        token = load_token()
    except TokenError as e:
        print(str(e), file=sys.stderr)
        return 2
    data_dir = Path(opts.data) if opts.data else default_data_dir()
    try:
        lock = acquire_serve_lock(data_dir)
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        return 1
    service = Service(data_dir)
    restart = threading.Event()
    try:
        import uvicorn
        app = build_app(build_mcp(service), token, opts.host)
        server = uvicorn.Server(uvicorn.Config(
            app, host=opts.host, port=opts.port, log_level="info",
            timeout_graceful_shutdown=SHUTDOWN_GRACE_S))
        if os.environ.get(RESTART_LOOP_ENV) == "1":
            service.restart_fn = lambda: exit_later(server, restart)
        server.run()
        if not server.started and not restart.is_set():
            return 3
    finally:
        service.close()
        lock.close()
    return RESTART_EXIT if restart.is_set() else 0
