"""What the trainer and scripts/bot share about a checkout (plan P13, R36): the repository
root, the code stamp, the Godot binary and git's HEAD, each in one place.

Standard library only, and it imports nothing else of the trainer, so `scripts/bot/records.py`
can load it too (with the repository root on sys.path, since `python -I` leaves it off).
"""
import hashlib
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Union

REPO_ROOT = Path(__file__).resolve().parent.parent
GODOT_ENV = "GODOT_BIN"
# Where SETUP.md installs Godot on the training PC.
WINDOWS_GODOT = r"C:\Users\trainer\tools\godot\Godot_v4.6.3-stable_win64_console.exe"
PathLike = Union[str, "os.PathLike[str]"]
_RULES_RE = re.compile(r"^const\s+RULES_VERSION\s*:\s*int\s*=\s*(\d+)", re.M)


class GodotNotFound(RuntimeError):
    """No Godot binary to run; the message says what was tried."""


def godot_bin() -> str:
    """The Godot binary: $GODOT_BIN when set (it must exist), else the training PC's install,
    else `godot` on PATH. GodotNotFound when none of them is there."""
    env = os.environ.get(GODOT_ENV, "")
    if env:
        if shutil.which(env) is None:
            raise GodotNotFound("Godot not found: %s=%s is not an executable" % (GODOT_ENV, env))
        return env
    if os.name == "nt" and Path(WINDOWS_GODOT).is_file():
        return WINDOWS_GODOT
    found = shutil.which("godot")
    if found is None:
        raise GodotNotFound("Godot not found: set %s (no `godot` on PATH)" % GODOT_ENV)
    return found


def git_head(root: PathLike = REPO_ROOT) -> str:
    """The full commit `root` has checked out, or "" when git cannot say."""
    try:
        done = subprocess.run(["git", "-C", os.fspath(root), "rev-parse", "HEAD"],
                              capture_output=True, text=True, timeout=30, check=False,
                              stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.strip() if done.returncode == 0 else ""


def rules_version(path: PathLike) -> int:
    """RULES_VERSION as match_rules.gd declares it. The file is read as bytes and decoded, so
    a CRLF checkout (Windows) reads the same as an LF one (the Mac)."""
    text = Path(path).read_bytes().decode("utf-8")
    m = _RULES_RE.search(text)
    if m is None:
        raise ValueError("RULES_VERSION not found in %s" % os.fspath(path))
    return int(m.group(1))


def current_stamp(cards: PathLike, decks: PathLike, rules: PathLike, crew: PathLike) -> str:
    """`r<RULES_VERSION>-` and the first 16 hex digits of SHA-256 over the bytes of the card
    pool, the deck list and the Crew pool files, in that order (cycle 11 R1, plan P1): the
    same string as the engine's BotStamp.current() for the same files. Paths may be str or
    pathlib paths in the platform's own form; the files are hashed as raw bytes."""
    h = hashlib.sha256()
    for p in (cards, decks, crew):
        h.update(Path(p).read_bytes())
    return "r%d-%s" % (rules_version(rules), h.hexdigest()[:16])


def stamp_of(work: PathLike) -> str:
    """current_stamp over the data files of the checkout at `work`."""
    engine = Path(work) / "godot" / "engine"
    data = engine / "data"
    return current_stamp(data / "cards.json", data / "decks.json", engine / "match_rules.gd",
                         data / "crew.json")
