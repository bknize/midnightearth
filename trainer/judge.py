"""The autopilot's judge and champion (cycle 16, plan P5 and P6).

The judge plays `scripts/bot/driver.py eval` in the training worktree, a fit against `random`
and, when a champion exists, against the champion. It reads the last `bot-eval:` line of each
and never raises. It writes nothing to the worktree (R12). The champion is one JSON file in
the data directory.
"""

import json
import os
import re
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from trainer.store import write_atomic

Runner = Callable[[List[str], Path, Dict[str, str], float], Tuple[int, str]]
MIN_GAME_S = 60.0  # a game is never given less than this, whatever the block has left
POLL_S = 1.0
KILL_WAIT_S = 10.0


class GameStopped(Exception):
    """The game's subprocess was terminated because the stop event was set."""

CHAMPION_NAME = "champion.json"
_RESULT = re.compile(r"\bresult=(PASS|FAIL|CAP)\b")
_OUTCOMES = {"PASS": "pass", "FAIL": "fail", "CAP": "cap"}


@dataclass
class JudgeConfig:
    cap: int = 400
    timeout_s: float = 3600.0
    worktree: Path = Path(".")
    godot_bin: str = ""
    python: str = "python"
    reports_dir: str = ""  # the driver's --reports-dir; "" leaves its default (inside the worktree)


@dataclass
class Judgment:
    line_random: str = ""
    line_champion: str = ""
    outcome_random: str = "skipped"
    outcome_champion: str = "skipped"
    passed: bool = False
    stopped: bool = False


def _end(proc: Any) -> None:
    """Terminate, then kill, a subprocess."""
    try:
        proc.terminate()
        try:
            proc.wait(KILL_WAIT_S)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(KILL_WAIT_S)
    except OSError:
        pass


def default_runner(argv: List[str], cwd: Path, env: Dict[str, str], timeout: float,
                   stop: Optional[threading.Event] = None, popen: Any = subprocess.Popen,
                   clock: Callable[[], float] = time.monotonic,
                   sleep: Optional[Callable[[float], None]] = None) -> Tuple[int, str]:
    """Run `argv` in `cwd`, polling so that `stop` terminates it: (exit code, stdout and stderr
    combined). Raises TimeoutError on timeout and GameStopped on a stop."""
    nap = sleep if sleep is not None else (stop.wait if stop is not None else time.sleep)
    with tempfile.TemporaryFile("w+", encoding="utf-8", errors="replace") as out:
        proc = popen(argv, cwd=str(cwd), env=env, stdout=out, stderr=subprocess.STDOUT,
                     universal_newlines=True)
        started = clock()
        try:
            while proc.poll() is None:
                if stop is not None and stop.is_set():
                    _end(proc)
                    raise GameStopped()
                if clock() - started >= timeout:
                    _end(proc)
                    raise TimeoutError("judge game timed out after %gs" % timeout)
                nap(POLL_S)
        except BaseException:
            if proc.poll() is None:
                _end(proc)
            raise
        out.seek(0)
        return int(proc.returncode if proc.returncode is not None else 0), out.read()


def last_result_line(output: str) -> str:
    """The last `bot-eval:` line of the driver's output that carries a `result=`; else ''."""
    found = ""
    for text in output.splitlines():
        text = text.strip()
        if text.startswith("bot-eval:") and _RESULT.search(text):
            found = text
    return found


def outcome_of(result_line: str) -> str:
    match = _RESULT.search(result_line) if result_line else None
    return _OUTCOMES[match.group(1)] if match else "error"


class Judge:
    def __init__(self, config: JudgeConfig, run: Optional[Runner] = None,
                 clock: Callable[[], float] = time.monotonic) -> None:
        self.config = config
        self.run: Optional[Runner] = run  # None: the interruptible default runner
        self.clock = clock
        self._games = 0

    def _argv(self, fit_path: str, other: str, champion_path: str, label: str = "") -> List[str]:
        cfg = self.config
        argv = [cfg.python, "-I", "scripts/bot/driver.py", "eval", "--a", "linear",
                "--weights-a", str(fit_path), "--b", other]
        if champion_path:
            argv += ["--weights-b", str(champion_path)]
        argv += ["--gainer", "--cap", str(cfg.cap)]
        if cfg.reports_dir:
            argv += ["--reports-dir", str(cfg.reports_dir)]
        if label:
            argv += ["--label", label]
        return argv

    def _label(self, fit_path: str, other: str) -> str:
        self._games += 1
        p = Path(fit_path)
        stem = re.sub(r"[^A-Za-z0-9_.-]", "_", p.parent.name or p.stem or "fit")
        return "%s-vs-%s-%d" % (stem, other, self._games)

    def _game(self, fit_path: str, other: str, champion_path: str,
              timeout_s: float, stop: Optional[threading.Event]) -> Tuple[str, str]:
        env = dict(os.environ)
        if self.config.godot_bin:
            env["GODOT_BIN"] = self.config.godot_bin
        argv = self._argv(fit_path, other, champion_path, self._label(fit_path, other))
        try:
            if self.config.reports_dir:
                os.makedirs(self.config.reports_dir, exist_ok=True)
            cwd = Path(self.config.worktree)
            if self.run is not None:
                _code, output = self.run(argv, cwd, env, timeout_s)
            else:
                _code, output = default_runner(argv, cwd, env, timeout_s, stop)
        except GameStopped:
            return "", "stopped"
        except Exception:  # timeout, missing binary: an error outcome, never a raise
            return "", "error"
        result_line = last_result_line(output)
        return result_line, outcome_of(result_line)

    def judge(self, fit_weights_path: str, champion_weights_path: Optional[str],
              stop: Optional[threading.Event] = None,
              budget_s: Optional[float] = None) -> Judgment:
        """Play the games. `budget_s` is the time the caller can spare for all of them: each game
        gets the configured timeout or what is left of the budget, whichever is less (never
        under MIN_GAME_S). A stop terminates the running game: `stopped`, never an error."""
        j = Judgment()
        started = self.clock()

        def timeout() -> float:
            if budget_s is None:
                return self.config.timeout_s
            left = budget_s - (self.clock() - started)
            return min(self.config.timeout_s, max(MIN_GAME_S, left))

        j.line_random, j.outcome_random = self._game(fit_weights_path, "random", "",
                                                     timeout(), stop)
        if j.outcome_random == "stopped":
            j.outcome_random = "skipped"
            j.stopped = True
            return j
        if j.outcome_random != "pass":
            return j
        if not champion_weights_path:
            j.passed = True
            return j
        if stop is not None and stop.is_set():  # a safe point between judge games (R36)
            j.stopped = True
            return j
        j.line_champion, j.outcome_champion = self._game(
            fit_weights_path, "linear", champion_weights_path, timeout(), stop)
        if j.outcome_champion == "stopped":
            j.outcome_champion = "skipped"
            j.stopped = True
            return j
        j.passed = j.outcome_champion == "pass"
        return j


def champion_path(data_dir: Path) -> Path:
    return Path(data_dir) / "autopilot" / CHAMPION_NAME


def load_champion(data_dir: Path) -> Optional[Dict[str, Any]]:
    try:
        with open(champion_path(data_dir), "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def save_champion(data_dir: Path, fit_id: str, stamp: str, feature_set: str,
                  line_random: str, line_champion: str, block: int) -> Dict[str, Any]:
    record: Dict[str, Any] = {"fit_id": fit_id, "stamp": stamp, "feature_set": feature_set,
                              "line_random": line_random, "line_champion": line_champion,
                              "block": block}
    path = champion_path(data_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(path, json.dumps(record, indent=2, sort_keys=True) + "\n")
    return record


def clear_champion(data_dir: Path) -> None:
    try:
        champion_path(data_dir).unlink()
    except OSError:
        pass


def champion_for(data_dir: Path, feature_set: str,
                 stamp: Optional[str] = None) -> Tuple[Optional[Dict[str, Any]], str]:
    """The champion when its feature set is `feature_set` (and, when `stamp` is given, its code
    stamp is `stamp`: a fit of other code cannot be judged against). Otherwise None and a note,
    and the file is renamed to `champion.dropped-<stamp>.json` (R39)."""
    champ = load_champion(data_dir)
    if champ is None:
        return None, ""
    fs_ok = str(champ.get("feature_set", "")) == feature_set
    stamp_ok = stamp is None or str(champ.get("stamp", "")) == stamp
    if fs_ok and stamp_ok:
        return champ, ""
    path = champion_path(data_dir)
    tag = str(champ.get("stamp", "")) or "unknown"
    target = path.with_name("champion.dropped-%s.json" % tag)
    n = 1
    while target.exists():
        n += 1
        target = path.with_name("champion.dropped-%s-%d.json" % (tag, n))
    os.replace(path, target)
    if not fs_ok:
        note = "champion %s dropped: feature set %s differs from %s" % (
            champ.get("fit_id", ""), champ.get("feature_set", ""), feature_set)
    else:
        note = "champion %s dropped: stamp %s differs from %s" % (
            champ.get("fit_id", ""), champ.get("stamp", ""), stamp)
    return None, note
