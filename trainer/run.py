"""The run loop (plan P14, R33 to R36) and the local `run` command."""
import argparse
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from trainer.config import RunConfig
from trainer.farm import Farm, FarmError, RequestFailed, worker_command
from trainer.repo import REPO_ROOT, GodotNotFound, git_head, godot_bin
from trainer.seeds import label_seed, play_seed, position_pick_seed, wire
from trainer.store import Store, weights_path

DECKS_JSON = REPO_ROOT / "godot" / "engine" / "data" / "decks.json"
Progress = Callable[[Dict[str, Any]], None]


class RunError(Exception):
    pass


def deck_ids(path: Optional[Path] = None) -> List[str]:
    with open(path or DECKS_JSON, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    return [str(d["id"]) for d in data["decks"]]


def ordered_pairings(ids: List[str]) -> List[List[str]]:
    """Every ordered pair of deck ids, mirrors included (n * n pairings)."""
    return [[a, b] for a in ids for b in ids]


def decks_for(cfg: RunConfig, index: int, pairings: List[List[str]]) -> List[str]:
    if cfg.decks == "all_pairings":
        return list(pairings[index % len(pairings)])
    return []


def _checked(reply: Dict[str, Any], stamp: str, what: str) -> Dict[str, Any]:
    if "error" in reply:
        raise RunError("%s: worker error: %s" % (what, reply["error"]))
    if reply.get("stamp") != stamp:
        raise RunError("%s: stamp %r differs from the run's %r"
                       % (what, reply.get("stamp"), stamp))
    return reply


def label_position(farm: Farm, cfg: RunConfig, stamp: str, index: int,
                   pairings: List[List[str]], rollout_path: str = "",
                   generator_path: str = "") -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    """Play one match, choose a commit decision, label it. Returns (position, labels)."""
    decks = decks_for(cfg, index, pairings)
    seed = play_seed(cfg.run_seed, index)
    try:
        return _label_position(farm, cfg, stamp, index, decks, seed, rollout_path,
                               generator_path)
    except RequestFailed as e:
        # Only this request failed (timed out twice, crashed its worker 3 times): the
        # position is committed as skipped, with no labels, and the run carries on.
        reason = "%s request: %s" % (e.kind, e.reason)
        position = {"index": index, "seed": seed, "decks": decks, "prefix_len": 0,
                    "seat": 0, "info": {"skipped": reason}}
        return position, []


def _label_position(farm: Farm, cfg: RunConfig, stamp: str, index: int, decks: List[str],
                    seed: int, rollout_path: str,
                    generator_path: str) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    what = "position %d" % index

    def ask(req: Dict[str, Any]) -> Dict[str, Any]:
        try:
            return farm.request(req)
        except RequestFailed as e:
            e.kind = str(req["kind"])
            raise

    play_req: Dict[str, Any] = {
        "kind": "play", "seed": wire(seed), "decks": decks, "generator": cfg.generator}
    if generator_path:
        play_req["generator_weights"] = generator_path
    played = _checked(ask(play_req), stamp, what + " play")
    commits = played["commits"]
    flat = [(seat, int(i)) for seat in range(2) for i in commits[seat]]
    if not flat:
        raise RunError("%s: the match had no commit decisions" % what)
    seat, prefix_len = flat[(position_pick_seed(cfg.run_seed, index) & ((1 << 64) - 1))
                            % len(flat)]
    actions = played["log"]["actions"][:prefix_len]
    label_req: Dict[str, Any] = {
        "kind": "label", "seed": wire(seed), "decks": decks, "actions": actions,
        "seat": seat, "k": cfg.k, "determinizations": cfg.determinizations,
        "rollout": cfg.rollout, "label_seed": wire(label_seed(cfg.run_seed, index))}
    if rollout_path:
        label_req["rollout_weights"] = rollout_path
    lab = _checked(ask(label_req), stamp, what + " label")
    features = lab.get("features", [])
    if len(features) != len(lab["candidates"]):
        raise RunError("%s label: %d feature lists for %d candidates"
                       % (what, len(features), len(lab["candidates"])))
    info = {"round": lab.get("round"), "turn": lab.get("turn"), "hand": lab.get("hand", [])}
    position = {"index": index, "seed": seed, "decks": decks, "prefix_len": prefix_len,
                "seat": seat, "info": info}
    labels = []
    for c, (action, value) in enumerate(zip(lab["candidates"], lab["values"])):
        labels.append({
            "position_index": index, "candidate_index": c, "action": action,
            "mean": value["mean"], "spread": value["spread"], "n": value["n"],
            "wins": value["wins"], "draws": value["draws"], "losses": value["losses"],
            "capped": value["capped"], "features": features[c],
            "us": lab.get("us", 0)})
    return position, labels


class _ActiveTime:
    """The active time not yet added to the run. read() and then settled(): a commit that
    fails between them leaves the time to the next read."""

    def __init__(self, clock: Callable[[], float]) -> None:
        self._clock = clock
        self.started = clock()
        self._mark = self.started
        self._now = self.started

    def read(self) -> float:
        self._now = self._clock()
        return self._now - self._mark

    def settled(self) -> None:
        self._mark = self._now

    def session(self) -> float:
        return self._clock() - self.started


def execute(store: Store, run_id: str, farm: Farm,
            should_stop: Callable[[], bool] = lambda: False,
            progress: Optional[Progress] = None,
            clock: Callable[[], float] = time.time) -> str:
    """Run (or resume) `run_id` on a started farm and finish it. Returns the final state: done,
    stopped or failed. Batches commit whole; a stop is honoured between batches. The `hours`
    cap is checked after each batch against this session's active time (a resume starts a
    fresh budget): at the cap the run ends stopped, resumable. Active time is added to the run
    at each batch commit and when the session ends."""
    run = store.get_run(run_id)
    if run is None:
        raise KeyError(run_id)
    cfg = RunConfig.from_dict(run["config"])
    stamp = str(run["stamp"])
    # Compare-and-set: a stop that landed while queued stays visible, a done run stays done.
    store.set_state(run_id, "running", "")
    active = _ActiveTime(clock)
    try:
        state, error = _execute(store, run_id, farm, cfg, stamp, should_stop, progress, active,
                                lambda: active.session() >= cfg.hours * 3600.0)
    finally:
        store.add_active(run_id, active.read())
    store.finish(run_id, state, error)
    return state


def _execute(store: Store, run_id: str, farm: Farm, cfg: RunConfig, stamp: str,
             should_stop: Callable[[], bool], progress: Optional[Progress],
             active: _ActiveTime,
             hours_reached: Callable[[], bool]) -> Tuple[str, Optional[str]]:
    """The labelling loop: the state the run should finish in, and its error if any."""
    pairings = ordered_pairings(deck_ids())
    seen_restarts = farm.restarts
    try:
        if farm.stamp != stamp:
            raise RunError("workers are at stamp %r, the run is at %r" % (farm.stamp, stamp))
        stored = store.get_run(run_id)
        have = str(stored["feature_set"]) if stored else ""
        fs = str(farm.feature_set)
        if not have:
            store.set_feature_set(run_id, fs)
        elif fs and fs != have:
            raise RunError("workers use feature set %r, the run was labelled with %r"
                           % (fs, have))
        rollout_path = weights_path(store.data_dir, cfg.rollout_weights)
        generator_path = weights_path(store.data_dir, cfg.generator_weights)
        start = store.resume_point(run_id)
        pool = ThreadPoolExecutor(max_workers=max(1, min(cfg.workers, cfg.batch)))
        try:
            while start < cfg.positions:
                if should_stop():
                    return "stopped", None
                end = min(start + cfg.batch, cfg.positions)
                futures = [pool.submit(label_position, farm, cfg, stamp, i, pairings,
                                       rollout_path, generator_path)
                           for i in range(start, end)]
                results = [f.result() for f in futures]
                delta = farm.restarts - seen_restarts
                store.commit_batch(run_id, start // cfg.batch, [r[0] for r in results],
                                   [lab for r in results for lab in r[1]],
                                   active_s=active.read(), restarts=delta)
                active.settled()
                seen_restarts += delta
                if progress is not None:
                    progress({"batch": start // cfg.batch, "done": end,
                              "positions": cfg.positions, "restarts": farm.restarts})
                start = end
                if start < cfg.positions and hours_reached():
                    return "stopped", "hours cap reached (%g h); resume to continue" % cfg.hours
        finally:
            pool.shutdown(wait=True, cancel_futures=True)
    except (RunError, FarmError) as e:
        return "failed", str(e)
    return "done", None


def _run_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -I trainer run", allow_abbrev=False)
    parser.add_argument("--config", help="the run's config file (JSON)")
    parser.add_argument("--data", help="the run store's folder")
    parser.add_argument("--resume", metavar="RUN_ID", help="resume this run instead")
    return parser


def cli_run(args: List[str]) -> int:
    """`run --config run.json [--data DIR] [--resume RUN_ID]`."""
    parser = _run_parser()
    opts = parser.parse_args(args)
    if not opts.resume and not opts.config:
        parser.print_usage()
        return 2
    resume = opts.resume
    store = Store(Path(opts.data) if opts.data else None)
    try:
        if resume:
            run = store.get_run(resume)
            if run is None:
                print("run: no run %s" % resume)
                return 3
            cfg = RunConfig.from_dict(run["config"])
        else:
            with open(opts.config, "r", encoding="utf-8") as fh:
                cfg = RunConfig.from_dict(json.load(fh))
        log_dir = store.data_dir / "logs"
        try:
            farm = Farm(worker_command(godot_bin()), cfg.workers, log_dir=log_dir)
            farm.start()
        except (FarmError, GodotNotFound) as e:
            print("run: %s" % e)
            return 3
        try:
            run_id = resume or store.create_run(cfg.to_dict(), farm.stamp,
                                                git_head() or "unknown")

            def show(p: Dict[str, Any]) -> None:
                print("batch %d: %d/%d positions, %d restarts"
                      % (p["batch"], p["done"], p["positions"], p["restarts"]))
                sys.stdout.flush()

            state = execute(store, run_id, farm, progress=show)
        finally:
            farm.stop()
        run = store.get_run(run_id) or {}
        print("run %s %s: %d positions, %d restarts, digest %s%s"
              % (run_id, state, store.resume_point(run_id), farm.restarts,
                 store.digest(run_id),
                 (", error: %s" % run.get("last_error")) if state == "failed" else ""))
        return 0 if state == "done" else 1
    finally:
        store.close()
