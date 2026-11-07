"""The run loop (plan P14, R33 to R36) and the local `run` command."""
import json
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from trainer.config import RunConfig
from trainer.farm import REPO_ROOT, Farm, FarmError, RequestFailed, godot_bin, worker_command
from trainer.seeds import label_seed, play_seed, position_pick_seed, wire
from trainer.store import Store

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
                   pairings: List[List[str]]) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    """Play one match, choose a commit decision, label it. Returns (position, labels)."""
    decks = decks_for(cfg, index, pairings)
    seed = play_seed(cfg.run_seed, index)
    try:
        return _label_position(farm, cfg, stamp, index, decks, seed)
    except RequestFailed as e:
        # Only this request failed (timed out twice, crashed its worker 3 times): the
        # position is committed as skipped, with no labels, and the run carries on.
        reason = "%s request: %s" % (e.kind, e.reason)
        position = {"index": index, "seed": seed, "decks": decks, "prefix_len": 0,
                    "seat": 0, "info": {"skipped": reason}}
        return position, []


def _label_position(farm: Farm, cfg: RunConfig, stamp: str, index: int, decks: List[str],
                    seed: int) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    what = "position %d" % index

    def ask(req: Dict[str, Any]) -> Dict[str, Any]:
        try:
            return farm.request(req)
        except RequestFailed as e:
            e.kind = str(req["kind"])
            raise

    played = _checked(ask({
        "kind": "play", "seed": wire(seed), "decks": decks, "generator": cfg.generator}),
        stamp, what + " play")
    commits = played["commits"]
    flat = [(seat, int(i)) for seat in range(2) for i in commits[seat]]
    if not flat:
        raise RunError("%s: the match had no commit decisions" % what)
    seat, prefix_len = flat[(position_pick_seed(cfg.run_seed, index) & ((1 << 64) - 1))
                            % len(flat)]
    actions = played["log"]["actions"][:prefix_len]
    lab = _checked(ask({
        "kind": "label", "seed": wire(seed), "decks": decks, "actions": actions,
        "seat": seat, "k": cfg.k, "determinizations": cfg.determinizations,
        "rollout": cfg.rollout, "label_seed": wire(label_seed(cfg.run_seed, index))}),
        stamp, what + " label")
    seen = _checked(ask({
        "kind": "inspect", "seed": wire(seed), "decks": decks, "actions": actions,
        "seat": seat}), stamp, what + " inspect")
    info = {"round": seen.get("round"), "turn": seen.get("turn"), "hand": seen.get("hand", [])}
    position = {"index": index, "seed": seed, "decks": decks, "prefix_len": prefix_len,
                "seat": seat, "info": info}
    labels = []
    for c, (action, value) in enumerate(zip(lab["candidates"], lab["values"])):
        labels.append({
            "position_index": index, "candidate_index": c, "action": action,
            "mean": value["mean"], "spread": value["spread"], "n": value["n"],
            "wins": value["wins"], "draws": value["draws"], "losses": value["losses"],
            "capped": value["capped"], "us": lab.get("us", 0)})
    return position, labels


def execute(store: Store, run_id: str, farm: Farm,
            should_stop: Callable[[], bool] = lambda: False,
            progress: Optional[Progress] = None,
            clock: Callable[[], float] = time.time) -> str:
    """Run (or resume) `run_id` on a started farm. Returns the final state: done, stopped or
    failed. Batches commit whole; a stop is honoured between batches. The `hours` cap is
    checked after each batch against this session's active time (a resume starts a fresh
    budget): at the cap the run ends stopped, resumable. Active time is added to the run at
    each batch commit and when the session ends."""
    run = store.get_run(run_id)
    if run is None:
        raise KeyError(run_id)
    cfg = RunConfig.from_dict(run["config"])
    stamp = str(run["stamp"])
    if run["state"] != "stopping":  # a stop that landed while queued stays visible
        store.set_state(run_id, "running", "")
    session_t0 = clock()
    mark = [session_t0]  # the clock reading at the last active-time settlement

    def settle() -> None:
        now = clock()
        store.add_active(run_id, now - mark[0])
        mark[0] = now

    try:
        return _execute(store, run_id, farm, cfg, stamp, should_stop, progress, settle,
                        lambda: clock() - session_t0 >= cfg.hours * 3600.0)
    finally:
        settle()


def _execute(store: Store, run_id: str, farm: Farm, cfg: RunConfig, stamp: str,
             should_stop: Callable[[], bool], progress: Optional[Progress],
             settle: Callable[[], None], hours_reached: Callable[[], bool]) -> str:
    pairings = ordered_pairings(deck_ids())
    seen_restarts = farm.restarts
    try:
        if farm.stamp != stamp:
            raise RunError("workers are at stamp %r, the run is at %r" % (farm.stamp, stamp))
        start = store.resume_point(run_id)
        pool = ThreadPoolExecutor(max_workers=max(1, min(cfg.workers, cfg.batch)))
        try:
            while start < cfg.positions:
                if should_stop():
                    store.set_state(run_id, "stopped")
                    return "stopped"
                end = min(start + cfg.batch, cfg.positions)
                futures = [pool.submit(label_position, farm, cfg, stamp, i, pairings)
                           for i in range(start, end)]
                results = [f.result() for f in futures]
                store.commit_batch(run_id, start // cfg.batch, [r[0] for r in results],
                                   [lab for r in results for lab in r[1]])
                settle()
                delta = farm.restarts - seen_restarts
                if delta:
                    store.add_restarts(run_id, delta)
                    seen_restarts += delta
                if progress is not None:
                    progress({"batch": start // cfg.batch, "done": end,
                              "positions": cfg.positions, "restarts": farm.restarts})
                start = end
                if start < cfg.positions and hours_reached():
                    store.set_state(run_id, "stopped",
                                    "hours cap reached (%g h); resume to continue" % cfg.hours)
                    return "stopped"
        finally:
            pool.shutdown(wait=True, cancel_futures=True)
    except (RunError, FarmError) as e:
        store.set_state(run_id, "failed", str(e))
        return "failed"
    store.set_state(run_id, "done")
    return "done"


def git_commit(full: bool = True) -> str:
    argv = ["git", "rev-parse", "HEAD"] if full else ["git", "rev-parse", "--short", "HEAD"]
    try:
        out = subprocess.run(argv, cwd=str(REPO_ROOT),
                             capture_output=True, text=True, timeout=30)
        return out.stdout.strip() or "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


def _arg(args: List[str], name: str) -> Optional[str]:
    if name in args:
        i = args.index(name)
        if i + 1 < len(args):
            return args[i + 1]
    return None


def cli_run(args: List[str]) -> int:
    """`run --config run.json [--data DIR] [--resume RUN_ID]`."""
    config_path = _arg(args, "--config")
    data = _arg(args, "--data")
    resume = _arg(args, "--resume")
    store = Store(Path(data) if data else None)
    try:
        if resume:
            run = store.get_run(resume)
            if run is None:
                print("run: no run %s" % resume)
                return 3
            cfg = RunConfig.from_dict(run["config"])
        else:
            if not config_path:
                print("usage: python -I trainer run --config run.json [--data DIR]"
                      " [--resume RUN_ID]")
                return 2
            with open(config_path, "r", encoding="utf-8") as fh:
                cfg = RunConfig.from_dict(json.load(fh))
        log_dir = store.data_dir / "logs"
        farm = Farm(worker_command(godot_bin()), cfg.workers, log_dir=log_dir)
        try:
            farm.start()
        except FarmError as e:
            print("run: %s" % e)
            return 3
        try:
            run_id = resume or store.create_run(cfg.to_dict(), farm.stamp, git_commit())

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
