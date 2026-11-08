"""The run config (plan "Run config", R45)."""
from dataclasses import asdict, dataclass, field, fields
from typing import Any, Dict, List

DECK_MODES = ("seeded", "all_pairings")
MAX_ITERATIONS = 100000


@dataclass
class RunConfig:
    positions: int = 2000
    k: int = 8
    determinizations: int = 16
    rollout: str = "random"
    generator: str = "random"
    decks: str = "seeded"
    workers: int = 16
    batch: int = 25
    run_seed: int = 0
    hours: float = 8.0
    rollout_weights: str = ""  # a fit id; "" is the committed weights
    generator_weights: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Any) -> "RunConfig":
        """The config, or ValueError naming the bad field."""
        if not isinstance(data, dict):
            raise ValueError("config: expected an object")
        known = {f.name for f in fields(cls)}
        for key in data:
            if key not in known:
                raise ValueError("config: unknown field %r" % (key,))
        merged = cls().to_dict()
        merged.update(data)
        for name in ("positions", "k", "determinizations", "workers", "batch"):
            v = merged[name]
            if isinstance(v, bool) or not isinstance(v, int):
                raise ValueError("config: %s must be an integer" % name)
            if v < 1:
                raise ValueError("config: %s must be at least 1" % name)
        v = merged["run_seed"]
        if isinstance(v, bool) or not isinstance(v, int):
            raise ValueError("config: run_seed must be an integer")
        if not -(1 << 63) <= v < (1 << 63):
            raise ValueError("config: run_seed out of 64-bit range")
        for name in ("rollout", "generator"):
            v = merged[name]
            if not isinstance(v, str) or not v:
                raise ValueError("config: %s must be a non-empty string" % name)
        if merged["decks"] not in DECK_MODES:
            raise ValueError("config: decks must be one of %s" % ", ".join(DECK_MODES))
        for name in ("rollout_weights", "generator_weights"):
            if not isinstance(merged[name], str):
                raise ValueError("config: %s must be a string (a fit id)" % name)
        v = merged["hours"]
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            raise ValueError("config: hours must be a number")
        if not v > 0:
            raise ValueError("config: hours must be greater than 0")
        merged["hours"] = float(v)
        return cls(**merged)


@dataclass
class FitConfig:
    """A learner job (spec R23; plan P11)."""
    runs: List[str] = field(default_factory=list)
    l2: float = 1e-3
    iterations: int = 500
    holdout: float = 0.1
    seed: int = 0
    k: int = 64

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Any) -> "FitConfig":
        """The config, or ValueError naming the bad field."""
        if not isinstance(data, dict):
            raise ValueError("config: expected an object")
        known = {f.name for f in fields(cls)}
        for key in data:
            if key not in known:
                raise ValueError("config: unknown field %r" % (key,))
        merged = cls().to_dict()
        merged.update(data)
        runs = merged["runs"]
        if not isinstance(runs, list) or not runs:
            raise ValueError("config: runs must be a non-empty list of run ids")
        for r in runs:
            if not isinstance(r, str) or not r:
                raise ValueError("config: runs must hold non-empty strings")
        if len(set(runs)) != len(runs):
            raise ValueError("config: runs must not repeat a run id")
        for name in ("iterations", "k"):
            v = merged[name]
            if isinstance(v, bool) or not isinstance(v, int):
                raise ValueError("config: %s must be an integer" % name)
            if v < 1:
                raise ValueError("config: %s must be at least 1" % name)
        if merged["iterations"] > MAX_ITERATIONS:
            raise ValueError("config: iterations must be at most %d" % MAX_ITERATIONS)
        v = merged["seed"]
        if isinstance(v, bool) or not isinstance(v, int):
            raise ValueError("config: seed must be an integer")
        for name in ("l2", "holdout"):
            v = merged[name]
            if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v:
                raise ValueError("config: %s must be a number" % name)
            merged[name] = float(v)
        if not 0.0 <= merged["l2"] < float("inf"):
            raise ValueError("config: l2 must be finite and at least 0")
        if not 0.0 <= merged["holdout"] < 0.5:
            raise ValueError("config: holdout must be at least 0 and below 0.5")
        merged["runs"] = list(runs)
        return cls(**merged)
