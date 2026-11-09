"""Append-only findings log of the training autopilot (R13 to R16).

One JSON line per block. Nothing here rewrites or deletes the file.
"""
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

KINDS = ("full", "trial", "seed")
STATUSES = ("done", "interrupted", "failed")
PLAN_SOURCES = ("advisor", "fallback", "steering", "default")

ENTRY_KEYS = (
    "block", "kind", "status", "started", "ended", "stamp", "plan", "plan_source",
    "plan_notes", "iterations", "champion_before", "champion_after", "plateau",
    "trial", "refused", "steering", "fault", "advisor",
)
ITERATION_KEYS = (
    "run", "fit", "positions", "labels", "label_seconds", "agreement_fitted",
    "agreement_heldout", "judge_random", "judge_champion", "became_champion",
)


def new_entry(block: int, kind: str = "full", status: str = "done", started: str = "",
              ended: str = "", stamp: str = "", plan: Optional[Dict[str, Any]] = None,
              plan_source: str = "default") -> Dict[str, Any]:
    """An entry with every field of the schema set to its empty value."""
    return {
        "block": block, "kind": kind, "status": status, "started": started,
        "ended": ended, "stamp": stamp, "plan": plan if plan is not None else {},
        "plan_source": plan_source, "plan_notes": [], "iterations": [],
        "champion_before": None, "champion_after": None, "plateau": False,
        "trial": None, "refused": [], "steering": None, "fault": "", "advisor": None,
    }


def new_iteration(run: str = "", fit: str = "", positions: int = 0, labels: int = 0,
                  label_seconds: float = 0, agreement_fitted: float = 0.0,
                  agreement_heldout: float = 0.0, judge_random: str = "",
                  judge_champion: str = "", became_champion: bool = False) -> Dict[str, Any]:
    return {
        "run": run, "fit": fit, "positions": positions, "labels": labels,
        "label_seconds": label_seconds, "agreement_fitted": agreement_fitted,
        "agreement_heldout": agreement_heldout, "judge_random": judge_random,
        "judge_champion": judge_champion, "became_champion": became_champion,
    }


def check_entry(entry: Any) -> List[str]:
    """Problems with an entry; empty when it is valid."""
    if not isinstance(entry, dict):
        return ["entry is not an object"]
    problems: List[str] = []
    for key in ENTRY_KEYS:
        if key not in entry:
            problems.append("missing key: " + key)
    if "kind" in entry and entry["kind"] not in KINDS:
        problems.append("bad kind: %r" % (entry["kind"],))
    if "status" in entry and entry["status"] not in STATUSES:
        problems.append("bad status: %r" % (entry["status"],))
    if "plan_source" in entry and entry["plan_source"] not in PLAN_SOURCES:
        problems.append("bad plan_source: %r" % (entry["plan_source"],))
    block = entry.get("block")
    if "block" in entry and (not isinstance(block, int) or isinstance(block, bool)):
        problems.append("block is not an integer")
    for key in ("iterations", "refused", "plan_notes"):
        if key in entry and not isinstance(entry[key], list):
            problems.append(key + " is not a list")
    if isinstance(entry.get("iterations"), list):
        for i, it in enumerate(entry["iterations"]):
            if not isinstance(it, dict):
                problems.append("iteration %d is not an object" % i)
                continue
            for key in ITERATION_KEYS:
                if key not in it:
                    problems.append("iteration %d missing key: %s" % (i, key))
    return problems


class FindingsLog:
    def __init__(self, path: Any) -> None:
        self.path = Path(path)

    def append(self, entry: Dict[str, Any]) -> None:
        problems = check_entry(entry)
        if problems:
            raise ValueError("invalid findings entry: " + "; ".join(problems))
        line = json.dumps(entry, sort_keys=True, separators=(",", ":")) + "\n"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        prefix = b"\n" if self._torn() else b""
        with open(self.path, "ab") as f:
            f.write(prefix + line.encode("utf-8"))
            f.flush()
            os.fsync(f.fileno())

    def _torn(self) -> bool:
        try:
            with open(self.path, "rb") as f:
                f.seek(0, os.SEEK_END)
                if f.tell() == 0:
                    return False
                f.seek(-1, os.SEEK_END)
                return f.read(1) != b"\n"
        except FileNotFoundError:
            return False

    def read(self, after: Optional[int] = None) -> Tuple[List[Dict[str, Any]], List[str]]:
        entries: List[Dict[str, Any]] = []
        problems: List[str] = []
        try:
            with open(self.path, "rb") as f:
                raw = f.read()
        except FileNotFoundError:
            return entries, problems
        for n, chunk in enumerate(raw.split(b"\n"), start=1):
            if not chunk.strip():
                continue
            try:
                obj = json.loads(chunk.decode("utf-8"))
            except (ValueError, UnicodeDecodeError) as exc:
                problems.append("line %d: %s" % (n, exc))
                continue
            if not isinstance(obj, dict) or not isinstance(obj.get("block"), int):
                problems.append("line %d: not an entry with a block number" % n)
                continue
            if after is None or obj["block"] > after:
                entries.append(obj)
        return entries, problems

    def last_block(self) -> int:
        entries, _ = self.read()
        return max((int(e["block"]) for e in entries), default=0)
