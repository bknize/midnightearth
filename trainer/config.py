"""The run config (plan "Run config", R45)."""
from dataclasses import asdict, dataclass, fields
from typing import Any, Dict

DECK_MODES = ("seeded", "all_pairings")


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
        v = merged["hours"]
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            raise ValueError("config: hours must be a number")
        if not v > 0:
            raise ValueError("config: hours must be greater than 0")
        merged["hours"] = float(v)
        return cls(**merged)
