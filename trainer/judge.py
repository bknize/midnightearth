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
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from trainer.store import write_atomic

Runner = Callable[[List[str], Path, Dict[str, str], float], Tuple[int, str]]

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


@dataclass
class Judgment:
    line_random: str = ""
    line_champion: str = ""
    outcome_random: str = "skipped"
    outcome_champion: str = "skipped"
    passed: bool = False
    stopped: bool = False


def default_runner(argv: List[str], cwd: Path, env: Dict[str, str],
                   timeout: float) -> Tuple[int, str]:
    """Run `argv` in `cwd`; (exit code, stdout and stderr combined). Raises on timeout."""
    proc = subprocess.run(argv, cwd=str(cwd), env=env, timeout=timeout, check=False,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)
    return proc.returncode, proc.stdout or ""


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
    def __init__(self, config: JudgeConfig, run: Optional[Runner] = None) -> None:
        self.config = config
        self.run: Runner = run if run is not None else default_runner

    def _argv(self, fit_path: str, other: str, champion_path: str) -> List[str]:
        cfg = self.config
        argv = [cfg.python, "-I", "scripts/bot/driver.py", "eval", "--a", "linear",
                "--weights-a", str(fit_path), "--b", other]
        if champion_path:
            argv += ["--weights-b", str(champion_path)]
        return argv + ["--gainer", "--cap", str(cfg.cap)]

    def _game(self, fit_path: str, other: str, champion_path: str) -> Tuple[str, str]:
        env = dict(os.environ)
        if self.config.godot_bin:
            env["GODOT_BIN"] = self.config.godot_bin
        try:
            _code, output = self.run(self._argv(fit_path, other, champion_path),
                                     Path(self.config.worktree), env, self.config.timeout_s)
        except Exception:  # timeout, missing binary: an error outcome, never a raise
            return "", "error"
        result_line = last_result_line(output)
        return result_line, outcome_of(result_line)

    def judge(self, fit_weights_path: str, champion_weights_path: Optional[str],
              stop: Optional[threading.Event] = None) -> Judgment:
        j = Judgment()
        j.line_random, j.outcome_random = self._game(fit_weights_path, "random", "")
        if j.outcome_random != "pass":
            return j
        if not champion_weights_path:
            j.passed = True
            return j
        if stop is not None and stop.is_set():  # a safe point between judge games (R36)
            j.stopped = True
            return j
        j.line_champion, j.outcome_champion = self._game(fit_weights_path, "linear",
                                                         champion_weights_path)
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


def champion_for(data_dir: Path, feature_set: str) -> Tuple[Optional[Dict[str, Any]], str]:
    """The champion when its feature set is `feature_set`. Otherwise None and a note, and the
    file is renamed to `champion.dropped-<stamp>.json` (R39)."""
    champ = load_champion(data_dir)
    if champ is None:
        return None, ""
    if str(champ.get("feature_set", "")) == feature_set:
        return champ, ""
    path = champion_path(data_dir)
    tag = str(champ.get("stamp", "")) or "unknown"
    target = path.with_name("champion.dropped-%s.json" % tag)
    n = 1
    while target.exists():
        n += 1
        target = path.with_name("champion.dropped-%s-%d.json" % (tag, n))
    os.replace(path, target)
    note = "champion %s dropped: feature set %s differs from %s" % (
        champ.get("fit_id", ""), champ.get("feature_set", ""), feature_set)
    return None, note
