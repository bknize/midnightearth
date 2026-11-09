"""The learner (spec R23 to R27; plan P10).

Pairs. Within each labelled position every two candidates whose mean values differ make one
example, the difference of their feature vectors ordered by the higher mean (a model with no
intercept: `score = features . weights`, and a pair is right when the higher-valued
candidate scores higher). Positions whose candidates share one value contribute nothing.

Model. L2 logistic loss on the scaled differences, full-batch gradient descent (Nesterov
momentum, a step from a fixed power iteration) for a fixed number of iterations from a zero
start. Each pair weighs 1 / (pairs in its position), so no position dominates (R34). The fit
seed only picks the held-out positions. The same runs and config give the
same bytes on the same machine: no clock, no thread-dependent reductions of our own, keys
sorted or in feature order, floats rounded before they are written.

numpy is imported inside the functions that need it, so the rest of the trainer (and
`python -I trainer serve`) runs without it; a missing numpy is `FitError("numpy missing")`.
Everything above `run_fit` that touches no array (validation, names) works without numpy.

Threads. A multithreaded BLAS may reduce in a thread-dependent order, which would make the
bytes depend on the machine's core count. `_numpy()` therefore pins OpenBLAS, MKL and OpenMP
to one thread (`BLAS_THREAD_VARS`) before numpy is first imported in the process. The
environment is read when the BLAS library loads, so if numpy was already imported (a test
runner, or a host that imported it itself) the pin cannot take effect; `BLAS_PINNED` records
whether it did, and the digest guarantee then holds only for that process's thread count.
No `threadpoolctl`: no new dependency.
"""
import hashlib
import itertools
import json
import os
import random
import re
import sys
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

from trainer.config import FitConfig
from trainer.store import WEIGHTS_NAME, Store, write_atomic
from trainer.sync import stamp_of

REPORT_NAME = "report.json"
FORMAT_VERSION = 2
TOP_WEIGHTS = 10
# The largest whole weight a fit writes, in hundredths. It mirrors MAX_WEIGHT of
# godot/engine/bot/bot_weights.gd (the loader's limit), so the full range is used and wide
# features (total_diff reaches about 5,800) do not quantize to 0 to 2. Keep the two equal.
# int64 safety of LinearBot.score: 124 features x 1e6 x a feature magnitude; features are
# counts, sums and differences of game quantities (well under 1e6), so a score stays below
# 124 x 1e6 x 1e6 = 1.24e14, far inside int64 (9.2e18). Even a feature of 1e9 gives 1.24e17.
WEIGHT_SCALE = 1_000_000
# Pairs x features allowed in one fit. The int64 chunks, the concatenated copy, the split
# copies (x_fit, x_hold) and the float64 `xs` are all live at the peak: about 4 to 5 times
# the cap in 8-byte cells, so 150 M cells is about 1.2 GB per copy and 5 to 6 GB at the peak.
MAX_CELLS = 150_000_000
BLAS_THREAD_VARS = ("OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "OMP_NUM_THREADS")
BLAS_PINNED = False  # whether _numpy() pinned BLAS before numpy first loaded; stays False
# when numpy was imported by someone else first
FEATURES_GD = Path("godot") / "engine" / "bot" / "bot_features.gd"
CARDS_JSON = Path("godot") / "engine" / "data" / "cards.json"
FINISHED = ("done", "stopped")
# Run config fields that must agree across the runs of one fit (R35): a run's labels are
# values under its rollout and generator policy, and values under different policies are not
# on one scale.
POLICY_FIELDS = ("rollout", "rollout_weights", "generator_weights")
# What the report's `pair_weighting` field says, so a later fit can be reproduced.
PAIR_WEIGHTING = ("1/pairs in the pair's position, then normalised to sum 1 over the fitted"
                  " pairs")
REPLACE_TRIES = 5  # write_outputs retries a PermissionError from os.replace this often
REPLACE_PAUSE_S = 0.05
# Power iteration under-estimates the top eigenvalue; the step allows this margin (never
# past the trace, which bounds it from above).
POWER_MARGIN = 1.1


class FitError(Exception):
    """A fit that cannot start or finish; the message is for the caller."""


def _numpy() -> Any:
    global BLAS_PINNED
    if "numpy" not in sys.modules:  # the BLAS reads these when numpy first loads
        for var in BLAS_THREAD_VARS:
            os.environ[var] = "1"
        BLAS_PINNED = True
    try:
        import numpy
    except ImportError:
        raise FitError("numpy missing")
    return numpy


# --- validation and names (no numpy) ----------------------------------------------------------

def validate_runs(store: Store, run_ids: Sequence[str]) -> Tuple[str, str]:
    """(stamp, feature_set) shared by `run_ids`, or FitError naming the run at fault (R23)."""
    stamp = ""
    feature_set = ""
    first = ""
    first_config: Dict[str, Any] = {}
    for rid in run_ids:
        run = store.get_run(rid)
        if run is None:
            raise FitError("no such run: %s" % rid)
        if run["state"] not in FINISHED:
            raise FitError("run %s is %s; only done or stopped runs can be fitted"
                           % (rid, run["state"]))
        if not run["feature_set"]:
            raise FitError("run %s has no feature set (labelled before features)" % rid)
        if not first:
            first, stamp, feature_set = rid, str(run["stamp"]), str(run["feature_set"])
            first_config = dict(run["config"])
            continue
        if run["stamp"] != stamp:
            raise FitError("run %s is under stamp %s, run %s under %s"
                           % (rid, run["stamp"], first, stamp))
        if run["feature_set"] != feature_set:
            raise FitError("run %s has feature set %s, run %s has %s"
                           % (rid, run["feature_set"], first, feature_set))
        for field in POLICY_FIELDS:
            mine = run["config"].get(field, "")
            theirs = first_config.get(field, "")
            if mine != theirs:
                raise FitError("run %s has %s %r, run %s has %r"
                               % (rid, field, mine, first, theirs))
    if not first:
        raise FitError("no runs named")
    return stamp, feature_set


def engine_feature_names(repo_root: Path, feature_set: str,
                         stamp: Optional[str] = None) -> List[str]:
    """The feature names in vector order, read from the checkout the workers run: the
    COMPACT list of bot_features.gd, then `card:<id>` per card of cards.json. FitError when
    the checkout's feature set is not `feature_set`, or (given `stamp`) when its code stamp
    (as trainer/sync.py computes it) is not the runs' `stamp`, since a renamed or reordered
    card would misname the weights."""
    root = Path(repo_root)
    if stamp is not None:
        try:
            have = stamp_of(root)
        except (OSError, ValueError) as e:
            raise FitError("cannot compute the checkout's code stamp: %s" % (e,))
        if have != stamp:
            raise FitError("the checkout's code stamp is %s, the runs' is %s" % (have, stamp))
    try:
        gd = (root / FEATURES_GD).read_text(encoding="utf-8")
        cards = json.loads((root / CARDS_JSON).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise FitError("cannot read the feature names from %s: %s" % (root, e))
    version = re.search(r'^const SET_VERSION: String = "([^"]*)"', gd, re.M)
    if version is None or version.group(1) != feature_set:
        raise FitError("the checkout's feature set is %s, the runs' is %s"
                       % (version.group(1) if version else "unknown", feature_set))
    block = re.search(r"^const COMPACT: Array\[String\] = \[(.*?)\]", gd, re.M | re.S)
    prefix = re.search(r'^const CARD_PREFIX: String = "([^"]*)"', gd, re.M)
    if block is None or prefix is None:
        raise FitError("bot_features.gd: COMPACT or CARD_PREFIX not found")
    names = re.findall(r'"([^"]+)"', block.group(1))
    try:
        names.extend(prefix.group(1) + str(c["id"]) for c in cards["cards"])
    except (KeyError, TypeError) as e:
        raise FitError("cards.json: bad shape (%s)" % (e,))
    return names


def datasets_digest(store: Store, run_ids: Sequence[str]) -> str:
    """SHA-256 over the runs' dataset digests in run-id order (plan P10)."""
    h = hashlib.sha256()
    for rid in sorted(run_ids):
        h.update(store.digest(rid).encode("ascii"))
        h.update(b"\n")
    return h.hexdigest()


# --- the data -------------------------------------------------------------------------------

def _load_pairs(store: Store, run_ids: Sequence[str]) -> Tuple[Any, Any, Any, int]:
    """(X, group, weight, positions): the pair difference matrix (int64, pairs x features),
    each pair's position group number, each pair's weight (1 / the pairs of its position, so a
    position with many candidates does not dominate; R34), and how many positions were read."""
    np = _numpy()
    chunks: List[Any] = []
    groups: List[Any] = []
    weights: List[Any] = []
    width = -1
    group = 0
    positions = 0
    cells = 0
    for rid in sorted(run_ids):
        rows = store.db.execute(
            "SELECT position_index, candidate_index, mean, features FROM labels"
            " WHERE run_id = ? ORDER BY position_index, candidate_index", (rid,)).fetchall()
        # Fetched whole, so the read lock is not held through the numpy work below (a
        # labelling run may be committing batches). Ordered by position, so each position's
        # candidates are one group.
        for _, grouped in itertools.groupby(rows, key=lambda r: r["position_index"]):
            cands = list(grouped)
            positions += 1
            vectors = [json.loads(r["features"]) for r in cands]
            for v in vectors:
                if width < 0:
                    width = len(v)
                if len(v) != width or width == 0:
                    raise FitError("run %s: feature vectors of length %d and %d (or none)"
                                   % (rid, width, len(v)))
            if len(cands) < 2:
                continue
            feats = np.array(vectors, dtype=np.int64)
            means = np.array([float(r["mean"]) for r in cands], dtype=np.float64)
            a, b = np.triu_indices(len(cands), 1)
            keep = means[a] != means[b]
            a, b = a[keep], b[keep]
            if a.size == 0:
                continue
            a_wins = means[a] > means[b]
            hi = np.where(a_wins, a, b)
            lo = np.where(a_wins, b, a)
            cells += int(a.size) * width
            if cells > MAX_CELLS:
                raise FitError("too many pairs to hold in memory (%d cells)" % cells)
            chunks.append(feats[hi] - feats[lo])
            groups.append(np.full(a.size, group, dtype=np.int64))
            weights.append(np.full(a.size, 1.0 / a.size, dtype=np.float64))
            group += 1
    if not chunks:
        raise FitError("no pairs: every position's candidates share one value")
    return np.concatenate(chunks), np.concatenate(groups), np.concatenate(weights), positions


def _agreement(np: Any, x: Any, w: Any) -> Tuple[int, int]:
    """(pairs ordered correctly, pairs): a tie of scores is not correct."""
    return int(np.count_nonzero(x @ w > 0)), int(x.shape[0])


def _share(right: int, total: int) -> Optional[float]:
    return round(right / total, 6) if total > 0 else None


# --- the fit --------------------------------------------------------------------------------

def run_fit(store: Store, fit_id: str, config: FitConfig, out_dir: Path, repo_root: Path,
            names: Optional[List[str]] = None,
            should_stop: Optional[Callable[[], bool]] = None) -> Dict[str, Any]:
    """Learn from the runs of `config`, write `linear_weights.json` and `report.json` in
    `out_dir`, and return the report. `names` overrides the names read from `repo_root`."""
    np = _numpy()
    run_ids = sorted(config.runs)
    stamp, feature_set = validate_runs(store, run_ids)
    x_all, group, weight_all, positions = _load_pairs(store, run_ids)
    width = int(x_all.shape[1])
    feature_names = list(names) if names is not None else engine_feature_names(
        repo_root, feature_set, stamp=stamp)
    if len(feature_names) != width:
        raise FitError("the labels hold %d features, the feature set names %d"
                       % (width, len(feature_names)))

    # Hold out a fraction of the positions that make pairs, chosen by the fit seed.
    groups = int(group.max()) + 1
    held_count = min(int(round(config.holdout * groups)), groups - 1)
    held = random.Random(config.seed).sample(range(groups), held_count)
    flag = np.zeros(groups, dtype=bool)
    if held:
        flag[np.array(held, dtype=np.int64)] = True
    is_held = flag[group]
    x_fit = x_all[~is_held]
    x_hold = x_all[is_held]
    pair_weight = weight_all[~is_held]
    pair_weight = pair_weight / pair_weight.sum()  # sums to 1 over the fitted pairs

    # Scale each column by its largest magnitude over the fitted pairs.
    scale = np.abs(x_fit).max(axis=0).astype(np.float64)
    scale[scale == 0] = 1.0
    xf = x_fit.astype(np.float64)
    xs = xf / scale
    xw = xs * np.sqrt(pair_weight)[:, None]  # xw.T @ xw is the weighted Gram matrix
    if not xw.any():
        raise FitError("every fitted pair has an all-zero difference")

    # A fixed step from the top eigenvalue of that matrix: power iteration from the stated
    # vector 1 + i/width (not the ones vector, which rows that sum to zero are orthogonal to).
    # The iteration under-estimates the eigenvalue, so the step allows a margin, capped by
    # the trace, which bounds it from above.
    vec = 1.0 + np.arange(width, dtype=np.float64) / width
    vec = vec / np.linalg.norm(vec)
    lam = 0.0
    for _ in range(100):
        nxt = xw.T @ (xw @ vec)
        lam = float(np.linalg.norm(nxt))
        if lam == 0.0:
            break
        vec = nxt / lam
    trace = float((xw * xw).sum())
    # lam stays 0 only when the start vector is orthogonal to every row; the trace still bounds.
    lam = min(lam * POWER_MARGIN, trace) if lam > 0.0 else trace
    lipschitz = 0.275 * lam + config.l2
    step = 1.0 / lipschitz

    w = np.zeros(width)
    y = w
    t = 1.0
    for _ in range(config.iterations):
        if should_stop is not None and should_stop():
            raise FitError("fit stopped")
        z = xs @ y
        s = 0.5 * (1.0 - np.tanh(z / 2.0))  # the logistic of -z, without overflow
        grad = -(xs.T @ (pair_weight * s)) + config.l2 * y
        w_next = y - step * grad
        t_next = (1.0 + np.sqrt(1.0 + 4.0 * t * t)) / 2.0
        y = w_next + ((t - 1.0) / t_next) * (w_next - w)
        w = w_next
        t = t_next
    loss = float((pair_weight * np.logaddexp(0.0, -(xs @ w))).sum() + 0.5 * config.l2 * float(w @ w))

    # Back to raw features, then whole numbers: the largest weight is WEIGHT_SCALE.
    raw = w / scale
    peak = float(np.abs(raw).max())
    if peak == 0.0:
        whole = np.zeros(width, dtype=np.int64)
    else:
        whole = np.rint(raw * (WEIGHT_SCALE / peak)).astype(np.int64)
    fit_right, fit_total = _agreement(np, xf, raw)
    hold_right, hold_total = _agreement(np, x_hold.astype(np.float64), raw)
    fit_q_right, _ = _agreement(np, x_fit, whole)
    hold_q_right, _ = _agreement(np, x_hold, whole)

    nonzero = [(feature_names[i], int(whole[i])) for i in range(width) if whole[i] != 0]
    top = sorted(nonzero, key=lambda p: (-abs(p[1]), p[0]))[:TOP_WEIGHTS]
    digest = datasets_digest(store, run_ids)
    weights_doc = {
        "version": FORMAT_VERSION, "bot": "linear", "stamp": stamp, "features": feature_set,
        "k": config.k,
        "fit": {"id": fit_id, "runs": run_ids, "digest": digest},
        "weights": {name: value for name, value in nonzero}}
    report = {
        "fit_id": fit_id, "kind": "fit", "config": config.to_dict(), "runs": run_ids,
        "stamp": stamp, "feature_set": feature_set, "digest": digest,
        "features": width, "positions": positions, "paired_positions": groups,
        "heldout_positions": held_count,
        "pair_weighting": PAIR_WEIGHTING,
        "pairs": {"total": fit_total + hold_total, "fitted": fit_total, "heldout": hold_total},
        "agreement": {
            "fitted": _share(fit_right, fit_total), "heldout": _share(hold_right, hold_total),
            "fitted_quantized": _share(fit_q_right, fit_total),
            "heldout_quantized": _share(hold_q_right, hold_total)},
        "loss": round(loss, 6), "nonzero_weights": len(nonzero),
        "top_weights": [{"name": a, "weight": b} for a, b in top]}
    write_outputs(Path(out_dir), weights_doc, report, feature_names)
    return report


def weights_text(doc: Dict[str, Any], feature_names: Sequence[str]) -> str:
    """The weights file's text: tab-indented, the header then weights in feature order."""
    order = {name: i for i, name in enumerate(feature_names)}
    weights = dict(sorted(doc["weights"].items(), key=lambda p: order.get(p[0], len(order))))
    ordered = dict(doc)
    ordered["weights"] = weights
    return json.dumps(ordered, indent="\t", ensure_ascii=True) + "\n"


def write_outputs(out_dir: Path, doc: Dict[str, Any], report: Dict[str, Any],
                  feature_names: Sequence[str]) -> None:
    """The weights file, then the report (a report on disk means the fit finished); each
    through a temp file, so a reader never sees half a file."""
    out_dir.mkdir(parents=True, exist_ok=True)
    texts = ((WEIGHTS_NAME, weights_text(doc, feature_names)),
             (REPORT_NAME, json.dumps(report, sort_keys=True, indent=1) + "\n"))
    for name, text in texts:
        for attempt in range(REPLACE_TRIES):
            try:
                write_atomic(out_dir / name, text)
                break
            except PermissionError:  # Windows: a reader (get_artifact) holds the file open
                if attempt == REPLACE_TRIES - 1:
                    raise
                time.sleep(REPLACE_PAUSE_S)
