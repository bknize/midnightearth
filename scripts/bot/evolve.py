"""Self-play evolution of a bot's weights (plan P20, spec R39-R46). No model tokens.

  driver.py train --bot tuned [--hours 8] [--label L] [--run-seed N]

(mu + lambda) with mu = lambda = 8. A genome is the bot's weight vector plus its tunable
integer caps (`k`, and for the matrix bot `k_opp`), each bounded. Offspring are a uniform
recombination of two parents followed by Gaussian mutation. A generation's fitness is the
pentanomial points per pair from a round robin of `rr_seeds` paired seeds between every two
individuals plus `ref_seeds` paired seeds of each against `greedy_v1`; every seed range is
derived from the run seed. After each generation a checkpoint
`godot/reports/bot/<label>/gen-<n>.json` is written; a run with the same label resumes from
the newest one. The generation's best is a candidate when its fitness beats the best so far;
a candidate is promoted only when `eval --gainer` passes against `greedy_v1` and against the
committed weights.

Exit codes: 0 promoted, 2 time limit reached with nothing promoted, 3 error.
At least one generation always runs, so a short `--hours` still produces a checkpoint.
A run stops at its first promotion; start a new label to keep evolving.
"""
import argparse
import concurrent.futures
import copy
import dataclasses
import hashlib
import json
import os
import random
import shutil
import sys
import time
from typing import Any, Callable, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import driver  # noqa: E402
import records  # noqa: E402

EXIT_PROMOTED, EXIT_NONE, EXIT_ERROR = 0, 2, 3
REFERENCE = "greedy_v1"
FORMAT_VERSION = 1
INT_FIELDS = ["k", "k_opp", "samples", "rm_iterations", "push_unit"]
SEED_SPAN = 1_000_000_000
# Tunable integer caps per bot: name -> (lowest, default highest). `k_max` and `k_opp_max`
# in Config replace the highest. The tuned k_max is the shipped 24 (spec C14); the matrix
# defaults keep k * k_opp at the plan's 12 x 12 previews per decision (P11).
TUNABLE: Dict[str, Dict[str, Tuple[int, int]]] = {
    "tuned": {"k": (1, 24)},
    "matrix": {"k": (1, 12), "k_opp": (1, 12)},
}
DEFAULT_DOC: Dict[str, Any] = {
    "k": 24, "k_opp": 12, "samples": 4, "rm_iterations": 200, "push_unit": 10,
    "weights": {"score_diff": 100},
}

Genome = Dict[str, Dict[str, int]]
# play(a_path, b_path, lo, hi, out) -> pair points of A over seeds lo..hi; b_path "" = greedy_v1
PlayFn = Callable[[str, str, int, int, str], List[float]]
# evaluate(reference, candidate_path, generation) -> (exit code, "pairs=… winrate=…")
EvalFn = Callable[[str, str, int], Tuple[int, str]]


class TrainError(Exception):
    pass


@dataclasses.dataclass
class Config:
    bot: str = "tuned"
    hours: float = 8.0
    label: str = ""
    run_seed: Optional[int] = None
    mu: int = 8
    lam: int = 8
    sigma: float = 20.0
    k_sigma: float = 2.0
    rr_seeds: int = 24
    ref_seeds: int = 48
    k_max: Optional[int] = None
    k_opp_max: Optional[int] = None
    weight_max: int = 1000
    eval_seeds: int = 5000
    eval_cap: int = 20000
    max_generations: int = 0       # stop once this generation number is done; 0 = no limit
    reports_dir: str = ""
    workers: int = 0


def derive(run_seed: int, *tags: Any) -> int:
    """A reproducible non-negative int from the run seed and some tags."""
    text = "|".join([str(run_seed)] + [str(t) for t in tags])
    return int.from_bytes(hashlib.sha256(text.encode("utf-8")).digest()[:8], "big")


def bounds_for(bot: str, k_max: Optional[int] = None,
               k_opp_max: Optional[int] = None) -> Dict[str, Tuple[int, int]]:
    if bot not in TUNABLE:
        raise TrainError("unknown bot %r; trainable bots: %s" % (bot, ", ".join(sorted(TUNABLE))))
    out = dict(TUNABLE[bot])
    if k_max is not None and "k" in out:
        out["k"] = (out["k"][0], max(out["k"][0], k_max))
    if k_opp_max is not None and "k_opp" in out:
        out["k_opp"] = (out["k_opp"][0], max(out["k_opp"][0], k_opp_max))
    return out


def load_base_doc(bot: str, weights_dir: str = records.WEIGHTS_DIR) -> Dict[str, Any]:
    """The bot's committed weights file, or the built-in defaults when there is none."""
    path = os.path.join(weights_dir, "%s_weights.json" % bot)
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                doc = json.load(f)
        except (OSError, ValueError) as e:
            raise TrainError("cannot read %s: %s" % (path, e))
        if not isinstance(doc, dict) or not isinstance(doc.get("weights"), dict):
            raise TrainError("bad weights file %s" % path)
        return doc
    return copy.deepcopy(DEFAULT_DOC)


def genome_of(doc: Dict[str, Any], bounds: Dict[str, Tuple[int, int]],
              weight_max: int) -> Genome:
    ints = {n: int(doc.get(n, DEFAULT_DOC[n])) for n in bounds}
    weights = {str(k): int(v) for k, v in doc["weights"].items()}
    return clamp({"ints": ints, "weights": weights}, bounds, weight_max)


def clamp(g: Genome, bounds: Dict[str, Tuple[int, int]], weight_max: int) -> Genome:
    ints = {n: min(hi, max(lo, int(g["ints"][n]))) for n, (lo, hi) in bounds.items()}
    weights = {k: min(weight_max, max(-weight_max, int(v))) for k, v in g["weights"].items()}
    return {"ints": ints, "weights": weights}


def mutate(g: Genome, rng: random.Random, sigma: float, k_sigma: float,
           bounds: Dict[str, Tuple[int, int]], weight_max: int) -> Genome:
    ints = {n: int(round(v + rng.gauss(0.0, k_sigma))) for n, v in g["ints"].items()}
    weights = {k: int(round(v + rng.gauss(0.0, sigma))) for k, v in g["weights"].items()}
    return clamp({"ints": ints, "weights": weights}, bounds, weight_max)


def recombine(a: Genome, b: Genome, rng: random.Random) -> Genome:
    """Uniform crossover, gene by gene."""
    ints = {n: (a if rng.random() < 0.5 else b)["ints"][n] for n in a["ints"]}
    weights = {k: (a if rng.random() < 0.5 else b)["weights"][k] for k in a["weights"]}
    return {"ints": ints, "weights": weights}


def initial_parents(base: Genome, mu: int, rng: random.Random, sigma: float, k_sigma: float,
                    bounds: Dict[str, Tuple[int, int]], weight_max: int) -> List[Genome]:
    out = [copy.deepcopy(base)]
    while len(out) < mu:
        out.append(mutate(base, rng, sigma, k_sigma, bounds, weight_max))
    return out


def make_offspring(parents: List[Genome], lam: int, rng: random.Random, sigma: float,
                   k_sigma: float, bounds: Dict[str, Tuple[int, int]],
                   weight_max: int) -> List[Genome]:
    out: List[Genome] = []
    for _ in range(lam):
        if len(parents) > 1:
            i, j = rng.sample(range(len(parents)), 2)
            child = recombine(parents[i], parents[j], rng)
        else:
            child = copy.deepcopy(parents[0])
        out.append(mutate(child, rng, sigma, k_sigma, bounds, weight_max))
    return out


def genome_doc(base_doc: Dict[str, Any], g: Genome, bot: str, stamp: str) -> Dict[str, Any]:
    """The weights file for a genome: the loader's key order, uncapped fields from base."""
    doc: Dict[str, Any] = {"version": FORMAT_VERSION, "bot": bot, "stamp": stamp}
    for n in INT_FIELDS:
        doc[n] = g["ints"].get(n, int(base_doc.get(n, DEFAULT_DOC[n])))
    doc["weights"] = dict(g["weights"])
    return doc


def write_json(path: str, doc: Dict[str, Any], indent: Any = "\t") -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=indent)
        f.write("\n")
    os.replace(tmp, path)


def checkpoints(run_dir: str) -> Dict[int, str]:
    out: Dict[int, str] = {}
    if os.path.isdir(run_dir):
        for name in os.listdir(run_dir):
            if name.startswith("gen-") and name.endswith(".json"):
                num = name[4:-5]
                if num.isdigit():
                    out[int(num)] = os.path.join(run_dir, name)
    return out


class Trainer:
    def __init__(self, cfg: Config, play: PlayFn, evaluate: EvalFn,
                 weights_dir: str = records.WEIGHTS_DIR,
                 out: Callable[[str], None] = print) -> None:
        self.cfg = cfg
        self.play = play
        self.evaluate = evaluate
        self.weights_dir = weights_dir
        self.say = out
        self.bounds = bounds_for(cfg.bot, cfg.k_max, cfg.k_opp_max)
        self.label = cfg.label or "%s-train" % cfg.bot
        base_reports = cfg.reports_dir or os.path.join(records.GODOT_DIR, "reports", "bot")
        self.run_dir = os.path.abspath(os.path.join(base_reports, self.label))
        self.stamp = records.current_stamp()
        self.run_seed = 0

    def run(self) -> int:
        cfg = self.cfg
        os.makedirs(self.run_dir, exist_ok=True)
        base_doc = load_base_doc(cfg.bot, self.weights_dir)
        ws = records.file_stamp(os.path.join(self.weights_dir, "%s_weights.json" % cfg.bot))
        if ws is not None and ws != self.stamp:
            self.say("bot-train: %s weights stamp %s differs from current %s (R38)"
                     % (cfg.bot, ws, self.stamp))
        state = self.load_state(base_doc)
        started = time.monotonic()
        limit = cfg.hours * 3600.0
        ran = 0
        while True:
            if ran >= 1 and time.monotonic() - started >= limit:
                break
            if cfg.max_generations and state["generation"] >= cfg.max_generations:
                break
            if state.get("promoted"):
                break
            self.generation(state, base_doc, started)
            ran += 1
            if state.get("promoted"):
                return EXIT_PROMOTED
        if state.get("promoted"):
            self.say("bot-train: already promoted at gen=%d" % state["promoted"])
            return EXIT_PROMOTED
        return self.summarize_unpromoted(state, ran)

    def load_state(self, base_doc: Dict[str, Any]) -> Dict[str, Any]:
        cfg = self.cfg
        found = checkpoints(self.run_dir)
        if found:
            newest = max(found)
            with open(found[newest], "r", encoding="utf-8") as f:
                ck = json.load(f)
            if ck.get("bot") != cfg.bot:
                raise TrainError("label %s holds a %s run, not %s" % (self.label, ck.get("bot"), cfg.bot))
            if cfg.run_seed is not None and cfg.run_seed != ck["run_seed"]:
                raise TrainError("label %s was started with run seed %d" % (self.label, ck["run_seed"]))
            if ck.get("stamp") != self.stamp:
                self.say("bot-train: checkpoint stamp %s differs from current %s"
                         % (ck.get("stamp"), self.stamp))
            self.say("bot-train: resuming %s from gen-%d.json, continuing at generation %d"
                     % (self.label, newest, newest + 1))
            self.run_seed = int(ck["run_seed"])
            return {"generation": newest, "run_seed": ck["run_seed"],
                    "parents": [p["genome"] for p in ck["population"]],
                    "best_norm": ck.get("best_norm"), "last_candidate": ck.get("last_candidate"),
                    "promoted": newest if ck.get("promoted") else 0, "last_result": ck.get("candidate"),
                    "best": ck.get("best")}
        seed = cfg.run_seed if cfg.run_seed is not None else int(time.time()) % SEED_SPAN
        self.run_seed = seed
        base = genome_of(base_doc, self.bounds, cfg.weight_max)
        rng = random.Random(derive(seed, "init"))
        parents = initial_parents(base, cfg.mu, rng, cfg.sigma, cfg.k_sigma,
                                  self.bounds, cfg.weight_max)
        self.say("bot-train: %s label=%s run_seed=%d hours=%g" % (cfg.bot, self.label, seed, cfg.hours))
        return {"generation": 0, "run_seed": seed, "parents": parents, "best_norm": None,
                "last_candidate": None, "promoted": 0, "last_result": None, "best": None}

    def seed_range(self, state: Dict[str, Any], tag: str, n: int, count: int) -> Tuple[int, int]:
        lo = derive(state["run_seed"], tag, n) % SEED_SPAN + 1
        return lo, lo + count - 1

    def generation(self, state: Dict[str, Any], base_doc: Dict[str, Any], started: float) -> None:
        cfg = self.cfg
        n = state["generation"] + 1
        rng = random.Random(derive(state["run_seed"], "gen", n))
        parents: List[Genome] = state["parents"]
        kids = make_offspring(parents, cfg.lam, rng, cfg.sigma, cfg.k_sigma,
                              self.bounds, cfg.weight_max)
        pop = parents + kids
        files = os.path.join(self.run_dir, "gen-%d-files" % n)
        work = os.path.join(self.run_dir, "gen-%d-work" % n)
        os.makedirs(files, exist_ok=True)
        os.makedirs(work, exist_ok=True)
        paths = []
        for i, g in enumerate(pop):
            p = os.path.join(files, "ind-%d.json" % i)
            write_json(p, genome_doc(base_doc, g, cfg.bot, self.stamp))
            paths.append(p)
        rr = self.seed_range(state, "rr", n, cfg.rr_seeds)
        ref = self.seed_range(state, "ref", n, cfg.ref_seeds)
        jobs: List[Tuple[int, int, int, int]] = []
        for i in range(len(pop)):
            for j in range(i + 1, len(pop)):
                jobs.append((i, j, rr[0], rr[1]))
        for i in range(len(pop)):
            jobs.append((i, -1, ref[0], ref[1]))

        def run_job(job: Tuple[int, int, int, int]) -> List[float]:
            i, j, lo, hi = job
            out = os.path.join(work, "m-%d-%d.jsonl" % (i, j))
            return self.play(paths[i], paths[j] if j >= 0 else "", lo, hi, out)

        n_workers = max(1, cfg.workers or os.cpu_count() or 1)
        with concurrent.futures.ThreadPoolExecutor(max_workers=n_workers) as pool:
            results = list(pool.map(run_job, jobs))
        shutil.rmtree(work, ignore_errors=True)
        points = [0.0] * len(pop)
        pairs = [0] * len(pop)
        for (i, j, _, _), res in zip(jobs, results):
            total, count = sum(res), len(res)
            points[i] += total
            pairs[i] += count
            if j >= 0:
                points[j] += 2.0 * count - total
                pairs[j] += count
        fit = [round(points[i] / (2.0 * pairs[i]), 6) if pairs[i] else 0.0
               for i in range(len(pop))]
        order = sorted(range(len(pop)), key=lambda i: (-fit[i], i))
        survivors = order[:cfg.mu]
        best = order[0]
        previous = state["best_norm"]
        is_candidate = ((previous is None or fit[best] > previous)
                        and pop[best] != state["last_candidate"])
        state["best_norm"] = fit[best] if previous is None else max(previous, fit[best])
        state["generation"] = n
        state["parents"] = [pop[i] for i in survivors]
        ck: Dict[str, Any] = {
            "version": 1, "bot": cfg.bot, "label": self.label, "run_seed": state["run_seed"],
            "stamp": self.stamp, "generation": n, "evaluated": len(pop),
            "params": {"mu": cfg.mu, "lam": cfg.lam, "sigma": cfg.sigma, "k_sigma": cfg.k_sigma,
                       "rr_seeds": cfg.rr_seeds, "ref_seeds": cfg.ref_seeds,
                       "bounds": {k: list(v) for k, v in self.bounds.items()},
                       "weight_max": cfg.weight_max},
            "seeds": {"rr": list(rr), "ref": list(ref)},
            "population": [{"genome": pop[i], "fitness": fit[i]} for i in survivors],
            "best": {"index": best, "genome": pop[best], "fitness": fit[best]},
            "best_norm": state["best_norm"],
            "last_candidate": pop[best] if is_candidate else state["last_candidate"],
            "candidate": None, "promoted": False, "elapsed_s": round(time.monotonic() - started),
        }
        ck_path = os.path.join(self.run_dir, "gen-%d.json" % n)
        write_json(ck_path, ck, indent=2)
        self.say("bot-train: gen=%d best=%d fitness=%.4f candidate=%s"
                 % (n, best, fit[best], "yes" if is_candidate else "no"))
        state["best"] = ck["best"]
        if is_candidate:
            state["last_candidate"] = pop[best]
            result = self.promote(n, paths[best], pop[best], base_doc)
            ck["candidate"] = result
            ck["promoted"] = bool(result["promoted"])
            state["last_result"] = result
            if result["promoted"]:
                state["promoted"] = n
            write_json(ck_path, ck, indent=2)

    def promote(self, n: int, cand_path: str, genome: Genome,
                base_doc: Dict[str, Any]) -> Dict[str, Any]:
        result: Dict[str, Any] = {"gen": n, "vs_greedy_v1": None, "vs_best": None,
                                  "promoted": False}
        code, info = self.evaluate(REFERENCE, cand_path, n)
        result["vs_greedy_v1"] = {"code": code, "info": info}
        if code == 0:
            code, info = self.evaluate("best", cand_path, n)
            result["vs_best"] = {"code": code, "info": info}
        if result["vs_greedy_v1"]["code"] != 0 or code != 0:
            return result
        target = os.path.join(self.weights_dir, "%s_weights.json" % self.cfg.bot)
        if os.path.isfile(target):
            shutil.copyfile(target, os.path.join(self.run_dir, "previous_%s_weights.json"
                                                 % self.cfg.bot))
        write_json(target, genome_doc(base_doc, genome, self.cfg.bot, self.stamp))
        result["promoted"] = True
        self.say("bot-train: PROMOTED gen=%d stamp=%s vs_greedy_v1=PASS(%s) vs_best=PASS(%s)"
                 % (n, self.stamp, result["vs_greedy_v1"]["info"], result["vs_best"]["info"]))
        return result

    def summarize_unpromoted(self, state: Dict[str, Any], ran: int) -> int:
        best = state.get("best") or {}
        last = state.get("last_result")
        detail = ""
        if last:
            parts = []
            for key in ("vs_greedy_v1", "vs_best"):
                r = last.get(key)
                if r:
                    parts.append("%s=%s(%s)" % (key, "PASS" if r["code"] == 0 else "FAIL(exit %d)"
                                                % r["code"], r["info"]))
            detail = " last_candidate=gen%d %s" % (last["gen"], " ".join(parts))
        self.say("bot-train: NOT PROMOTED label=%s generations=%d (this run %d) best_fitness=%s%s "
                 "exit=2" % (self.label, state["generation"], ran, best.get("fitness"), detail))
        return EXIT_NONE


def make_godot_play(bot: str, label: str) -> PlayFn:
    def play(a_path: str, b_path: str, lo: int, hi: int, out: str) -> List[float]:
        argv = driver.godot_worker(bot, bot if b_path else REFERENCE, lo, hi, out, label,
                                   weights_a=a_path, weights_b=b_path)
        code, tail = driver.run_worker(argv)
        if code != 0:
            raise TrainError("worker seeds %d-%d exit %d (R45): %s"
                             % (lo, hi, code, tail.replace("\n", " | ")))
        recs = records.read_records(out)
        os.remove(out)
        return [float(r["points_a"]) for r in recs if r.get("t") == "p"]
    return play


def make_godot_evaluate(cfg: Config, run_dir: str, run_seed_of: Callable[[], int]) -> EvalFn:
    def evaluate(reference: str, cand_path: str, n: int) -> Tuple[int, str]:
        lo = derive(run_seed_of(), "eval", n, reference) % SEED_SPAN + 1
        ref_bot = REFERENCE if reference == REFERENCE else cfg.bot
        args = argparse.Namespace(
            a=cfg.bot, b=ref_bot, gainer=True, nonreg=False,
            seeds="%d-%d" % (lo, lo + cfg.eval_seeds - 1), cap=cfg.eval_cap,
            label="gen%d-vs-%s" % (n, reference), reports_dir=run_dir,
            weights_a=cand_path, weights_b="")
        code, report = driver.eval_report(args)
        if code == driver.EXIT_ERROR:
            raise TrainError("eval of gen %d vs %s errored" % (n, reference))
        agg = report.get("aggregates", {})
        info = "%s pairs=%s winrate=%.3f±%.3f" % (report.get("result"), agg.get("pairs"),
                                                  agg.get("winrate", 0.0), agg.get("winrate_ci95", 0.0))
        return code, info
    return evaluate


def _unset_evaluate(reference: str, cand_path: str, n: int) -> Tuple[int, str]:
    raise TrainError("evaluate not wired")


def add_train_parser(sub: Any) -> None:
    t = sub.add_parser("train", help="evolve a bot's weights by self-play")
    t.add_argument("--bot", default="tuned")
    t.add_argument("--hours", type=float, default=8.0)
    t.add_argument("--label", default="")
    t.add_argument("--run-seed", type=int, default=None)
    t.add_argument("--mu", type=int, default=8)
    t.add_argument("--lam", type=int, default=8)
    t.add_argument("--sigma", type=float, default=20.0, help="weight mutation, hundredths")
    t.add_argument("--rr-seeds", type=int, default=24)
    t.add_argument("--ref-seeds", type=int, default=48)
    t.add_argument("--k-max", type=int, default=None)
    t.add_argument("--k-opp-max", type=int, default=None)
    t.add_argument("--weight-max", type=int, default=1000)
    t.add_argument("--eval-seeds", type=int, default=5000)
    t.add_argument("--max-generations", type=int, default=0, help=argparse.SUPPRESS)
    t.add_argument("--reports-dir", default="", help=argparse.SUPPRESS)


def run_train(args: argparse.Namespace) -> int:
    cfg = Config(bot=args.bot, hours=args.hours, label=args.label, run_seed=args.run_seed,
                 mu=args.mu, lam=args.lam, sigma=args.sigma, rr_seeds=args.rr_seeds,
                 ref_seeds=args.ref_seeds, k_max=args.k_max, k_opp_max=args.k_opp_max,
                 weight_max=args.weight_max, eval_seeds=args.eval_seeds,
                 max_generations=args.max_generations, reports_dir=args.reports_dir)
    try:
        if min(cfg.mu, cfg.lam, cfg.rr_seeds, cfg.ref_seeds, cfg.eval_seeds) < 1 or cfg.hours < 0:
            raise TrainError("--mu, --lam, --rr-seeds, --ref-seeds, --eval-seeds must be >= 1 "
                             "and --hours >= 0")
        if not os.path.isfile(driver.godot_bin()):
            raise TrainError("Godot not found at %s (set GODOT_BIN)" % driver.godot_bin())
        label = cfg.label or "%s-train" % cfg.bot
        trainer = Trainer(cfg, make_godot_play(cfg.bot, label), _unset_evaluate)
        trainer.evaluate = make_godot_evaluate(cfg, trainer.run_dir, lambda: trainer.run_seed)
        return trainer.run()
    except TrainError as e:
        print("bot-train: %s" % e, file=sys.stderr)
        return EXIT_ERROR
