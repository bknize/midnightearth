"""The autopilot's knobs, their bounds and hard limits (plan P9; spec R18, R23 to R28).

Pure: no I/O. The "fit exists with this feature set" check is injected by the caller."""
import math
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

CHOICE = "choice"
WEIGHTS = "weights"
INT = "int"
FLOAT = "float"

# kind, default bounds, hard limit. Numbers: [lo, hi]; choices: allowed names.
# `open_lo` / `open_hi` mark a hard limit end that is excluded.
_TABLE: Dict[str, Dict[str, Any]] = {
    "generator": {"kind": CHOICE, "bounds": ["random", "linear"], "hard": ["random", "linear"]},
    "rollout": {"kind": CHOICE, "bounds": ["random", "linear"], "hard": ["random", "linear"]},
    "generator_weights": {"kind": WEIGHTS, "bounds": ["", "champion"]},
    "rollout_weights": {"kind": WEIGHTS, "bounds": ["", "champion"]},
    "positions": {"kind": INT, "bounds": [500, 4000], "hard": [100, 20000]},
    "determinizations": {"kind": INT, "bounds": [8, 32], "hard": [1, 128]},
    "k": {"kind": INT, "bounds": [4, 16], "hard": [2, 32]},
    "workers": {"kind": INT, "bounds": [8, 16], "hard": [1, 16]},
    "l2": {"kind": FLOAT, "bounds": [1e-4, 1e-1], "hard": [0.0, 10.0], "open_lo": True},
    "fit_iterations": {"kind": INT, "bounds": [200, 2000], "hard": [50, 10000]},
    "holdout": {"kind": FLOAT, "bounds": [0.1, 0.3], "hard": [0.0, 0.5], "open_hi": True},
}

KNOBS: Tuple[str, ...] = tuple(_TABLE)
RUN_KNOBS: Tuple[str, ...] = ("generator", "rollout", "generator_weights", "rollout_weights",
                              "positions", "determinizations", "k", "workers")
FIT_KNOBS: Tuple[str, ...] = ("l2", "fit_iterations", "holdout")
# FitConfig field names for the fit knobs.
_FIT_FIELD = {"l2": "l2", "fit_iterations": "iterations", "holdout": "holdout"}


def plan_defaults() -> Dict[str, Any]:
    """A full plan with in-bounds values."""
    return {"generator": "random", "rollout": "random", "generator_weights": "",
            "rollout_weights": "", "positions": 1000, "determinizations": 16, "k": 8,
            "workers": 16, "l2": 1e-3, "fit_iterations": 500, "holdout": 0.1}


def default_bounds() -> Dict[str, List[Any]]:
    """The default bounds: knob -> [lo, hi] (numbers) or a list of allowed names (choices)."""
    return {name: list(spec["bounds"]) for name, spec in _TABLE.items()}


def run_fragment(plan: Dict[str, Any]) -> Dict[str, Any]:
    """The RunConfig fields a plan sets."""
    return {name: plan[name] for name in RUN_KNOBS if name in plan}


def fit_fragment(plan: Dict[str, Any]) -> Dict[str, Any]:
    """The FitConfig fields a plan sets (`fit_iterations` becomes `iterations`)."""
    return {_FIT_FIELD[name]: plan[name] for name in FIT_KNOBS if name in plan}


def _is_number(v: Any) -> bool:
    return not isinstance(v, bool) and isinstance(v, (int, float)) and math.isfinite(v)


def _type_ok(name: str, value: Any) -> bool:
    kind = _TABLE[name]["kind"]
    if kind == INT:
        return isinstance(value, int) and not isinstance(value, bool)
    if kind == FLOAT:
        return _is_number(value)
    return isinstance(value, str)


def _in_hard(name: str, value: Any) -> bool:
    spec = _TABLE[name]
    if spec["kind"] == WEIGHTS:
        return True  # the caller's predicate decides
    if spec["kind"] == CHOICE:
        return value in spec["hard"]
    lo, hi = spec["hard"]
    if value < lo or value > hi:
        return False
    if spec.get("open_lo") and value == lo:
        return False
    if spec.get("open_hi") and value == hi:
        return False
    return True


def _in_bounds(name: str, value: Any, bounds: Dict[str, List[Any]]) -> bool:
    spec = _TABLE[name]
    b = bounds.get(name, spec["bounds"])
    if spec["kind"] in (CHOICE, WEIGHTS):
        return value in b
    return bool(b[0] <= value <= b[1])


def check_value(name: str, value: Any) -> str:
    """Why `value` is not a legal value for knob `name` ("" when it is): unknown knob, wrong
    type, or past the hard limit. Weights names are not checked against the fit store."""
    if name not in _TABLE:
        return "unknown knob"
    if not _type_ok(name, value):
        return "wrong type"
    if not _in_hard(name, value):
        return "past the hard limit"
    return ""


def in_bounds(name: str, value: Any, bounds: Dict[str, List[Any]]) -> bool:
    """Whether `value` lies inside the bounds for a known knob."""
    return _in_bounds(name, value, bounds)


def clamp(name: str, value: Any, bounds: Dict[str, List[Any]]) -> Any:
    """`value` moved inside the bounds: the nearest end for numbers, the first allowed name
    for choices and weights."""
    b = bounds.get(name, _TABLE[name]["bounds"])
    if _in_bounds(name, value, bounds):
        return value
    if _TABLE[name]["kind"] in (CHOICE, WEIGHTS):
        return b[0]
    return b[0] if value < b[0] else b[1]


def check_bounds(bounds: Any) -> List[str]:
    """Problems with a bounds mapping (empty when fine): unknown knob, malformed bound, a bound
    past the hard limit, lo above hi."""
    if not isinstance(bounds, dict):
        return ["bounds: expected an object"]
    problems: List[str] = []
    for name, b in bounds.items():
        if name not in _TABLE:
            problems.append("bounds: unknown knob %r" % (name,))
            continue
        spec = _TABLE[name]
        if not isinstance(b, list) or not b:
            problems.append("bounds: %s must be a non-empty list" % name)
        elif spec["kind"] in (CHOICE, WEIGHTS):
            for v in b:
                if not isinstance(v, str):
                    problems.append("bounds: %s names must be strings" % name)
                elif spec["kind"] == CHOICE and v not in spec["hard"]:
                    problems.append("bounds: %s has %r past the hard limit" % (name, v))
        elif len(b) != 2 or not all(_is_number(v) for v in b) or (
                spec["kind"] == INT and not all(_type_ok(name, v) for v in b)):
            problems.append("bounds: %s must be [lo, hi] of %s" % (name, spec["kind"]))
        else:
            if b[0] > b[1]:
                problems.append("bounds: %s has lo above hi" % name)
            for v in b:
                if not _in_hard(name, v):
                    problems.append("bounds: %s has %r past the hard limit" % (name, v))
    return problems


@dataclass
class Validation:
    plan: Dict[str, Any] = field(default_factory=dict)
    trial: Optional[Tuple[str, Any]] = None
    refused: List[Dict[str, Any]] = field(default_factory=list)
    notes: List[str] = field(default_factory=list)


def validate(plan: Any, last_plan: Dict[str, Any], bounds: Dict[str, List[Any]],
             extras: Dict[str, List[Any]],
             fit_ok: Optional[Callable[[str], bool]] = None) -> Validation:
    """Check a proposed plan. The result's plan has every knob; a knob not proposed, refused,
    dropped or held for a trial keeps `last_plan`'s value (the plan default if absent).
    A weights knob may name any fit id that `fit_ok` accepts (all, when it is None)."""
    base = plan_defaults()
    base.update({k: v for k, v in last_plan.items() if k in _TABLE})
    out = Validation(plan=dict(base))
    if not isinstance(plan, dict):
        out.refused.append({"knob": "", "value": plan, "reason": "plan is not an object"})
        return out
    for name, value in plan.items():
        is_fit_id = name in ("generator_weights", "rollout_weights") \
            and isinstance(value, str) and value not in ("", "champion")
        if name not in _TABLE:
            out.refused.append({"knob": name, "value": value, "reason": "unknown knob"})
        elif not _type_ok(name, value):
            out.refused.append({"knob": name, "value": value, "reason": "wrong type"})
        elif not _in_hard(name, value):
            out.refused.append({"knob": name, "value": value, "reason": "past the hard limit"})
        elif is_fit_id and fit_ok is not None and not fit_ok(value):
            out.refused.append({"knob": name, "value": value,
                                "reason": "no such fit with this feature set"})
        elif is_fit_id or _in_bounds(name, value, bounds) or value in extras.get(name, []):
            out.plan[name] = value
        elif out.trial is None:
            out.trial = (name, value)
        else:
            out.notes.append("%s=%r is outside its bounds and a trial is already pending; "
                             "kept %r" % (name, value, base[name]))
    return out
