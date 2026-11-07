"""The worker farm (plan P13, R34): a pool of long-lived play-out worker processes.

Each worker slot owns one `subprocess.Popen` (pipes in text mode, UTF-8, line-buffered), a
reader thread that turns the process's stdout into a queue of lines, and a dispatcher thread
that takes requests from the shared queue, writes one line and waits for the matching reply.
A worker that exits is restarted and its request re-queued (counted in `restarts`). A request
with no reply within `timeout` seconds kills the worker, restarts it and is retried once; a
second timeout, or a third crash, fails that request alone (RequestFailed): the slot restarts
its worker and the farm stays up. Only a worker that will not start fails the farm. No
shell, no signals: Windows-safe.
"""
import itertools
import json
import os
import queue
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Dict, IO, List, Optional, Sequence

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TIMEOUT = 600.0
START_TIMEOUT = 180.0
MAX_CRASHES_PER_REQUEST = 3


class FarmError(Exception):
    """The farm cannot go on (a worker will not start, a stamp mismatch)."""


class RequestFailed(FarmError):
    """One request failed (timed out twice, or crashed its worker 3 times) while the farm
    carries on. `reason` is a short stable code ("timeout" or "crash")."""

    def __init__(self, message: str, reason: str) -> None:
        super().__init__(message)
        self.reason = reason
        self.kind = ""  # the request kind, filled in by the caller that knows it


def godot_bin() -> str:
    return os.environ.get("GODOT_BIN", "godot")


def worker_command(binary: Optional[str] = None, repo_root: Optional[Path] = None) -> List[str]:
    root = repo_root if repo_root is not None else REPO_ROOT
    return [binary or godot_bin(), "--headless", "--path", str(root / "godot"), "-s",
            "res://tools/playout_worker.gd"]


class _Job:
    def __init__(self, job_id: int, request: Dict[str, Any]) -> None:
        self.id = job_id
        self.request = request
        self.done = threading.Event()
        self.reply: Optional[Dict[str, Any]] = None
        self.error = ""
        self.reason = ""  # set when only this request failed (not the farm)
        self.timeouts = 0
        self.crashes = 0


class _Proc:
    """One worker process with its reader thread."""

    def __init__(self, command: Sequence[str], log_path: Optional[Path]) -> None:
        self.lines: "queue.Queue[Optional[str]]" = queue.Queue()
        self._log: Optional[IO[bytes]] = None
        if log_path is not None:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            self._log = open(log_path, "ab")
        try:
            self.popen = subprocess.Popen(
                list(command), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=self._log if self._log is not None else subprocess.DEVNULL,
                text=True, encoding="utf-8", bufsize=1)
        except BaseException:
            if self._log is not None:
                self._log.close()
            raise
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _read(self) -> None:
        out = self.popen.stdout
        try:
            if out is not None:
                for line in out:
                    self.lines.put(line)
        except (OSError, ValueError):
            pass
        self.lines.put(None)

    def send(self, request: Dict[str, Any]) -> bool:
        stdin = self.popen.stdin
        if stdin is None:
            return False
        try:
            stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
            stdin.flush()
        except (OSError, ValueError):
            return False
        return True

    def next_object(self, deadline: float) -> Optional[Dict[str, Any]]:
        """The next JSON object line, skipping other lines. None at end of output; raises
        queue.Empty at the deadline."""
        while True:
            line = self.lines.get(timeout=max(0.0, deadline - time.monotonic()))
            if line is None:
                self.lines.put(None)
                return None
            text = line.strip()
            if not text.startswith("{"):
                continue
            try:
                obj = json.loads(text)
            except ValueError:
                continue
            if isinstance(obj, dict):
                return obj

    def kill(self) -> None:
        try:
            self.popen.kill()
        except OSError:
            pass
        for stream in (self.popen.stdin, self.popen.stdout):
            try:
                if stream is not None:
                    stream.close()
            except (OSError, ValueError):
                pass
        try:
            self.popen.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        if self._log is not None:
            self._log.close()

    def quit(self) -> None:
        self.send({"kind": "quit"})
        try:
            if self.popen.stdin is not None:
                self.popen.stdin.close()
        except (OSError, ValueError):
            pass
        try:
            self.popen.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        self.kill()


class Farm:
    def __init__(self, command: Sequence[str], workers: int = 1,
                 timeout: float = DEFAULT_TIMEOUT, log_dir: Optional[Path] = None,
                 start_timeout: float = START_TIMEOUT) -> None:
        self.command = list(command)
        self.workers = max(1, int(workers))
        self.timeout = timeout
        self.start_timeout = start_timeout
        self.log_dir = log_dir
        self.stamp = ""
        self.restarts = 0
        self.error = ""
        self._lock = threading.Lock()
        self._jobs: "queue.Queue[_Job]" = queue.Queue()
        self._pending: Dict[int, _Job] = {}
        self._ids = itertools.count(1)
        self._stop = threading.Event()
        self._inflight = 0
        self._closed = False  # set under _lock once the farm has failed or stopped
        self._ready: List[threading.Event] = []
        self._threads: List[threading.Thread] = []
        self._procs: Dict[int, _Proc] = {}

    # lifecycle

    def start(self) -> None:
        for slot in range(self.workers):
            ready = threading.Event()
            self._ready.append(ready)
            t = threading.Thread(target=self._slot_loop, args=(slot, ready), daemon=True)
            self._threads.append(t)
            t.start()
        for ready in self._ready:
            ready.wait()
        if self.error:
            self.stop()
            raise FarmError(self.error)

    def stop(self) -> None:
        self._close("farm stopped")
        # Kill the workers first: a slot blocked on a reply sees end-of-output at once
        # instead of waiting out its request timeout.
        with self._lock:
            live = list(self._procs.values())
        for p in live:
            p.kill()
        for t in self._threads:
            t.join(timeout=30)
        with self._lock:
            procs = list(self._procs.values())
            self._procs.clear()
        for p in procs:
            p.kill()

    def __enter__(self) -> "Farm":
        self.start()
        return self

    def __exit__(self, *exc: Any) -> None:
        self.stop()

    def busy(self) -> int:
        """Workers serving a request right now."""
        with self._lock:
            return self._inflight

    # requests

    def request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Send a request (the farm sets its `id`), block for the reply. Raises FarmError."""
        job = _Job(next(self._ids), dict(request, id=0))
        job.request["id"] = job.id
        self._enqueue(job)
        job.done.wait()
        with self._lock:
            self._pending.pop(job.id, None)
        if job.reply is None:
            raise self._failure(job)
        return job.reply

    def map(self, requests: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Replies in request order, the requests running across the workers."""
        jobs: List[_Job] = []
        for req in requests:
            job = _Job(next(self._ids), dict(req))
            job.request["id"] = job.id
            jobs.append(job)
            self._enqueue(job)
        out: List[Dict[str, Any]] = []
        for job in jobs:
            job.done.wait()
            with self._lock:
                self._pending.pop(job.id, None)
            if job.reply is None:
                raise self._failure(job)
            out.append(job.reply)
        return out

    # internals

    def _failure(self, job: _Job) -> FarmError:
        if job.reason:
            return RequestFailed(job.error, job.reason)
        return FarmError(job.error or self.error or "farm stopped")

    def _fail_job(self, job: _Job, message: str, reason: str) -> None:
        """Only this request fails; the slot restarts its worker and carries on."""
        job.error = message
        job.reason = reason
        job.done.set()

    def _enqueue(self, job: _Job) -> None:
        """Queue a job, or fail it at once when the farm has failed or stopped (so a late
        request never waits for a slot that is gone)."""
        with self._lock:
            if self._closed:
                job.error = self.error or "farm stopped"
                job.done.set()
            else:
                self._pending[job.id] = job
                self._jobs.put(job)

    def _close(self, message: str) -> None:
        """Close the farm: every pending job gets an error, later requests fail at once."""
        with self._lock:
            self._closed = True
            if message != "farm stopped" and not self.error:
                self.error = message
            pending = list(self._pending.values())
            reason = self.error or message
        for job in pending:
            if not job.done.is_set():
                job.error = reason
                job.done.set()
        self._stop.set()

    def _fail(self, message: str) -> None:
        self._close(message)

    def _spawn(self, slot: int) -> _Proc:
        """Start a worker and wait for its hello line."""
        log_path = None
        if self.log_dir is not None:
            log_path = self.log_dir / ("worker-%d.log" % slot)
        proc = _Proc(self.command, log_path)
        with self._lock:
            old = self._procs.get(slot)
            self._procs[slot] = proc
        if old is not None:
            old.kill()
        deadline = time.monotonic() + self.start_timeout
        try:
            hello = proc.next_object(deadline)
        except queue.Empty:
            proc.kill()
            raise FarmError("worker %d: no hello within %.0f s" % (slot, self.start_timeout))
        if hello is None or not hello.get("hello"):
            proc.kill()
            raise FarmError("worker %d: exited before hello (see its log)" % slot)
        stamp = str(hello.get("stamp", ""))
        with self._lock:
            if not self.stamp:
                self.stamp = stamp
            mismatch = stamp != self.stamp
        if mismatch:
            proc.kill()
            raise FarmError("worker %d: stamp %s differs from %s" % (slot, stamp, self.stamp))
        return proc

    def _restart(self, slot: int, proc: _Proc) -> _Proc:
        proc.kill()
        with self._lock:
            self.restarts += 1
        return self._spawn(slot)

    def _slot_loop(self, slot: int, ready: threading.Event) -> None:
        proc: Optional[_Proc] = None
        try:
            try:
                proc = self._spawn(slot)
            except Exception as e:
                self._fail(str(e) if isinstance(e, FarmError) else
                           "%s: %s" % (type(e).__name__, e))
                return
            finally:
                ready.set()
            while not self._stop.is_set():
                try:
                    job = self._jobs.get(timeout=0.1)
                except queue.Empty:
                    continue
                if job.done.is_set():
                    continue
                with self._lock:
                    self._inflight += 1
                try:
                    proc = self._serve(slot, proc, job)
                except Exception as e:  # whatever it is, the job gets an error reply
                    job.error = "%s: %s" % (type(e).__name__, e)
                    self._fail(str(e) if isinstance(e, FarmError) else job.error)
                    return
                finally:
                    with self._lock:
                        self._inflight -= 1
        finally:
            ready.set()
            if proc is not None and self._stop.is_set():
                proc.quit()
                with self._lock:
                    self._procs.pop(slot, None)

    def _serve(self, slot: int, proc: _Proc, job: _Job) -> _Proc:
        """Run one job on this slot; returns the (possibly restarted) process."""
        sent = proc.send(job.request)
        reply: Optional[Dict[str, Any]] = None
        timed_out = False
        if sent:
            deadline = time.monotonic() + self.timeout
            while True:
                try:
                    reply = proc.next_object(deadline)
                except queue.Empty:
                    timed_out = True
                    break
                if reply is None or reply.get("id") == job.id:
                    break
                # A reply for another id: a stale line from before a restart; drop it.
        if self._stop.is_set():
            raise FarmError(self.error or "farm stopped")
        if timed_out:
            job.timeouts += 1
            proc = self._restart(slot, proc)
            if job.timeouts > 1:
                self._fail_job(job, "request %d timed out twice (%.0f s each)"
                               % (job.id, self.timeout), "timeout")
            else:
                self._jobs.put(job)
            return proc
        if reply is None:
            job.crashes += 1
            proc = self._restart(slot, proc)
            if job.crashes >= MAX_CRASHES_PER_REQUEST:
                self._fail_job(job, "request %d crashed its worker %d times"
                               % (job.id, job.crashes), "crash")
            else:
                self._jobs.put(job)
            return proc
        job.reply = reply
        job.done.set()
        return proc
