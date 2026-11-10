"""Steering files from the Mac (plan P13; spec R29 to R31).

The Mac copies `steering.json` into the inbox (`~/me/inbox`, or the directory named by the
environment variable TRAINER_INBOX). At a block boundary `take` validates it and moves it to
`<data>/autopilot/steering/<n>.json`; an invalid file goes to `refused-<n>-<k>.json` and the
autopilot keeps the steering already in force.

Rules the autopilot applies once a steering is in force:
- A pinned knob is never offered to the advisor, and its pinned value wins over any proposal.
- A value the advisor proposes that the steering lists under `avoid` is refused with
  "avoided by steering N".
- Steering notes (and the avoid lists) reach the advisor's prompt.
- Narrowing: when new bounds leave the last plan's value outside them, the plan carries the
  nearest in-bounds value instead (never a value outside the steering bounds). If the advisor
  proposes the old, now out-of-bounds value (inside the hard limit), the usual R24 trial runs
  for it, one per boundary; past the hard limit it is refused (R27).
"""
import json
import os
import shutil
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from trainer import knobs

INBOX_ENV = "TRAINER_INBOX"
FILE_NAME = "steering.json"
_TOP_KEYS = ("bounds", "avoid", "pin", "notes", "approved_by", "date")


def inbox_path(inbox: Optional[Any] = None) -> Path:
    """The steering file's path: the argument (a directory), else TRAINER_INBOX, else
    ~/me/inbox, plus `steering.json`."""
    if inbox is not None:
        return Path(inbox) / FILE_NAME
    env = os.environ.get(INBOX_ENV)
    base = Path(env) if env else Path.home() / "me" / "inbox"
    return base / FILE_NAME


@dataclass
class Steering:
    bounds: Dict[str, List[Any]] = field(default_factory=dict)  # merged over the current bounds
    avoid: Dict[str, List[Any]] = field(default_factory=dict)
    pins: Dict[str, Any] = field(default_factory=dict)
    notes: List[str] = field(default_factory=list)
    approved_by: str = ""
    date: str = ""


def parse_steering(doc: Any, current_bounds: Dict[str, List[Any]]
                   ) -> Tuple[Optional[Steering], List[str]]:
    """A Steering from a decoded document, or None and the problems."""
    if not isinstance(doc, dict):
        return None, ["steering: expected an object"]
    problems: List[str] = []
    for key in doc:
        if key not in _TOP_KEYS:
            problems.append("steering: unknown key %r" % (key,))
    approved = doc.get("approved_by")
    if not isinstance(approved, str) or not approved.strip():
        problems.append("steering: approved_by is missing")
    date = doc.get("date", "")
    if not isinstance(date, str):
        problems.append("steering: date must be a string")
    file_bounds = doc.get("bounds", {})
    problems.extend(knobs.check_bounds(file_bounds))
    merged = {k: list(v) for k, v in current_bounds.items()}
    if isinstance(file_bounds, dict):
        for name, b in file_bounds.items():
            if isinstance(b, list):
                merged[name] = list(b)
    avoid = doc.get("avoid", {})
    if not isinstance(avoid, dict):
        problems.append("avoid: expected an object")
        avoid = {}
    for name, values in avoid.items():
        if name not in knobs.KNOBS:
            problems.append("avoid: unknown knob %r" % (name,))
        elif not isinstance(values, list):
            problems.append("avoid: %s must be a list" % name)
        else:
            for v in values:
                if knobs.check_value(name, v) == "wrong type":
                    problems.append("avoid: %s has %r of the wrong type" % (name, v))
    pins = doc.get("pin", {})
    if not isinstance(pins, dict):
        problems.append("pin: expected an object")
        pins = {}
    for name, v in pins.items():
        why = knobs.check_value(name, v)
        if why:
            problems.append("pin: %s=%r %s" % (name, v, why))
    notes = doc.get("notes", [])
    if not isinstance(notes, list) or not all(isinstance(n, str) for n in notes):
        problems.append("notes: expected a list of strings")
        notes = []
    if problems:
        return None, problems
    return Steering(bounds=merged, avoid={k: list(v) for k, v in avoid.items()},
                    pins=dict(pins), notes=list(notes), approved_by=str(approved).strip(),
                    date=str(date)), []


MIN_AGE_S = 5.0  # a file younger than this may still be arriving (scp is writing it)


def _refused_path(out_dir: Path, n: int) -> Path:
    """`refused-<n>-<k>.json` with the first k that is free, so a second refusal of the same
    steering number never overwrites the first."""
    k = 1
    while (out_dir / ("refused-%d-%d.json" % (n, k))).exists():
        k += 1
    return out_dir / ("refused-%d-%d.json" % (n, k))


def take(data_dir: Any, inbox: Optional[Any], current: Dict[str, List[Any]], n: int,
         clock: Callable[[], float] = time.time, min_age_s: float = MIN_AGE_S
         ) -> Tuple[Optional[Steering], Optional[Dict[str, Any]]]:
    """Take the inbox file if there is one that is at least `min_age_s` old. Valid: archived
    as steering/<n>.json, returned. Invalid: archived as steering/refused-<n>-<k>.json,
    returned as a refusal record. A file that cannot be read or moved (the copy is still
    open on Windows) is left for the next boundary."""
    src = inbox_path(inbox)
    try:
        if not src.is_file():
            return None, None
        if clock() - src.stat().st_mtime < min_age_s:
            return None, None
        out_dir = Path(data_dir) / "autopilot" / "steering"
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None, None
    steering: Optional[Steering] = None
    try:
        doc = json.loads(src.read_text(encoding="utf-8-sig"))
        steering, problems = parse_steering(doc, current)
    except UnicodeDecodeError as e:
        problems = ["steering: not readable JSON (%s)" % e]
    except ValueError as e:  # bad JSON
        problems = ["steering: not readable JSON (%s)" % e]
    except OSError:  # locked or vanished: try again at the next boundary
        return None, None
    try:
        if steering is not None:
            shutil.move(str(src), str(out_dir / ("%d.json" % n)))
            return steering, None
        shutil.move(str(src), str(_refused_path(out_dir, n)))
    except OSError:
        return None, None
    return None, {"knob": "steering", "value": n, "reason": "; ".join(problems)}
