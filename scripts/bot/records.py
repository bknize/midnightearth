"""JSONL record reading, merging, aggregates (spec R27) and the stamp (R33, plan P8)."""
import hashlib
import json
import math
import os
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Union

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT_DIR = os.path.join(REPO_ROOT, "godot")
DATA_DIR = os.path.join(GODOT_DIR, "engine", "data")
CARDS_PATH = os.path.join(DATA_DIR, "cards.json")
DECKS_PATH = os.path.join(DATA_DIR, "decks.json")
CREW_PATH = os.path.join(DATA_DIR, "crew.json")
RULES_PATH = os.path.join(GODOT_DIR, "engine", "match_rules.gd")
PathLike = Union[str, "os.PathLike[str]"]
STAMP_RE = re.compile(r"^r\d+-[0-9a-f]{16}$")
Z95 = 1.96


def rules_version(path: PathLike = RULES_PATH) -> int:
    """RULES_VERSION as match_rules.gd declares it. The file is read as bytes and decoded, so
    a CRLF checkout (Windows) reads the same as an LF one (the Mac)."""
    text = Path(path).read_bytes().decode("utf-8")
    m = re.search(r"^const\s+RULES_VERSION\s*:\s*int\s*=\s*(\d+)", text, re.M)
    if m is None:
        raise ValueError("RULES_VERSION not found in %s" % os.fspath(path))
    return int(m.group(1))


def current_stamp(cards: PathLike = CARDS_PATH, decks: PathLike = DECKS_PATH,
                  rules: PathLike = RULES_PATH, crew: PathLike = CREW_PATH) -> str:
    """`r<RULES_VERSION>-` and the first 16 hex digits of SHA-256 over the bytes of the card
    pool, the deck list and the Crew pool files, in that order (cycle 11 R1, plan P1): the
    same string as the engine's BotStamp.current() for the same files. Paths may be str or
    pathlib paths in the platform's own form; the files are hashed as raw bytes."""
    h = hashlib.sha256()
    for p in (cards, decks, crew):
        h.update(Path(p).read_bytes())
    return "r%d-%s" % (rules_version(rules), h.hexdigest()[:16])


def read_records(path: str) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def merge(paths: Iterable[str]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for p in paths:
        out.extend(read_records(p))
    return out


def percentile(values: List[int], q: float) -> int:
    """Nearest rank: the ceil(q * n)-th smallest value; 0 for no values."""
    if not values:
        return 0
    s = sorted(values)
    return s[max(0, math.ceil(q * len(s)) - 1)]


def aggregate(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    pairs = [r for r in records if r.get("t") == "p"]
    games = [r for r in records if r.get("t") == "g"]
    decisions = [r for r in records if r.get("t") == "d"]
    ends = [r for r in records if r.get("t") == "end"]
    scores = [float(r["points_a"]) / 2.0 for r in pairs]
    n = len(scores)
    mean = sum(scores) / n if n else 0.0
    if n > 1:
        var = sum((x - mean) ** 2 for x in scores) / (n - 1)
        ci = Z95 * math.sqrt(var / n)
    else:
        ci = 0.0
    firsts = [bool(r.get("first_won")) for r in games if "first_won" in r]
    us = [int(r["us"]) for r in decisions]
    p95 = percentile(us, 0.95)
    a_seat = {(r.get("seed"), r.get("game")): r.get("a_seat") for r in games}
    us_a = [int(r["us"]) for r in decisions
            if a_seat.get((r.get("seed"), r.get("game"))) == r.get("seat")]
    p99_a = percentile(us_a, 0.99)  # side a's own decisions only (R17, C16)
    slowest = max(us) if us else 0
    for e in ends:  # a worker's own slowest can only raise the figure
        slowest = max(slowest, int(e.get("slowest_us", 0)))
    return {
        "pairs": n,
        "games": len(games),
        "points_a": sum(float(r["points_a"]) for r in pairs),
        "winrate": mean,
        "winrate_ci95": ci,
        "first_committer": (sum(firsts) / len(firsts)) if firsts else 0.0,
        "p95_us": p95,
        "p99_us": p99_a,
        "slowest_us": slowest,
        "rejected": sum(int(e.get("rejected", 0)) for e in ends),
        "overruns": sum(int(e.get("overruns", 0)) for e in ends),
        "overruns_a": sum(int(e.get("overruns_a", 0)) for e in ends),
        "overruns_b": sum(int(e.get("overruns_b", 0)) for e in ends),
        "replay_mismatches": sum(int(e.get("replay_mismatches", 0)) for e in ends),
        "stamps": sorted({str(e["stamp"]) for e in ends if "stamp" in e}),
        # the weights files' stamp check (cycle 13 R15): match, MISMATCH, BROKEN or none
        "weights_stamps": sorted({str(e["weights_stamp"]) for e in ends
                                  if "weights_stamp" in e}),
    }
