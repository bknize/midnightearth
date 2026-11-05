"""Pentanomial GSPRT as Fishtest does it (plan P19, spec R28).

A pair of games (both seats, same shuffle) scores 0, 0.5, 1, 1.5 or 2 points for bot A;
divided by two that is the pentanomial outcome in {0, 1/4, 1/2, 3/4, 1}. The log
likelihood ratio uses the normal (second order) approximation with the mean and variance
taken from the sample.

Which side PASS is for:
  gainer   bounds [0, +25]:  H1 = "A is at least 25 Elo stronger" -> PASS; H0 -> FAIL.
  nonreg   bounds [-25, 0]:  H1 = "A is not worse than B" -> PASS; H0 ("A is at least
           25 Elo worse") -> FAIL.
In both modes PASS is the H1 bound.
"""
import math
from typing import List, Optional, Sequence, Tuple

ALPHA = 0.05
BETA = 0.05
DEFAULT_CAP = 20000
ZERO_VAR_MIN_PAIRS = 100
VAR_FLOOR = 1e-4
BOUNDS = {"gainer": (0.0, 25.0), "nonreg": (-25.0, 0.0)}


def logistic(elo: float) -> float:
    return 1.0 / (1.0 + 10.0 ** (-elo / 400.0))


def llr_bounds(alpha: float = ALPHA, beta: float = BETA) -> Tuple[float, float]:
    """(lower, upper): at or below lower accept H0, at or above upper accept H1."""
    return math.log(beta / (1.0 - alpha)), math.log((1.0 - beta) / alpha)


def llr(counts: Sequence[int], elo0: float, elo1: float) -> float:
    """LLR of H1 (elo1) against H0 (elo0) from pentanomial counts [n0..n4]."""
    n = sum(counts)
    if n == 0:
        return 0.0
    mean = sum(c * (i / 4.0) for i, c in enumerate(counts)) / n
    var = sum(c * (i / 4.0 - mean) ** 2 for i, c in enumerate(counts)) / n
    if var <= 0.0:
        # Every pair had the same outcome (identical deterministic bots split each pair
        # 1-1). Undecided on a small sample; after ZERO_VAR_MIN_PAIRS such pairs, treat
        # the variance as VAR_FLOOR so the test settles on the side the mean is on.
        if n < ZERO_VAR_MIN_PAIRS:
            return 0.0
        var = VAR_FLOOR
    s0, s1 = logistic(elo0), logistic(elo1)
    return n * (s1 - s0) * (2.0 * mean - s0 - s1) / (2.0 * var)


def index_of(points: float) -> int:
    i = int(round(points * 2))
    if i < 0 or i > 4 or abs(points * 2 - i) > 1e-9:
        raise ValueError("pair points must be one of 0, 0.5, 1, 1.5, 2: %r" % (points,))
    return i


class Sprt:
    """Accumulates pair results; state() is None, "H0", "H1" or "CAP"."""

    def __init__(self, mode: str = "nonreg", cap: int = DEFAULT_CAP,
                 alpha: float = ALPHA, beta: float = BETA) -> None:
        if mode not in BOUNDS:
            raise ValueError("mode must be gainer or nonreg")
        self.mode = mode
        self.elo0, self.elo1 = BOUNDS[mode]
        self.cap = cap
        self.lower, self.upper = llr_bounds(alpha, beta)
        self.counts: List[int] = [0, 0, 0, 0, 0]

    @property
    def pairs(self) -> int:
        return sum(self.counts)

    def add(self, points: float) -> None:
        self.counts[index_of(points)] += 1

    def llr(self) -> float:
        return llr(self.counts, self.elo0, self.elo1)

    def state(self) -> Optional[str]:
        value = self.llr()
        if value >= self.upper:
            return "H1"
        if value <= self.lower:
            return "H0"
        if self.pairs >= self.cap:
            return "CAP"
        return None

    def decided(self) -> bool:
        return self.state() is not None

    def result(self) -> str:
        """PASS (H1) / FAIL (H0) / CAP."""
        return {"H1": "PASS", "H0": "FAIL"}.get(self.state() or "", "CAP")
