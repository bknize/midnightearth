"""The Mac's digest of the autopilot findings log (spec R41, plan P17). Standard library only.

`digest(dir)` reads `<dir>/findings.jsonl`, computes the figures with no LLM and writes
`figures.json` and `figures.md` beside it.
"""
import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from trainer.findings import FindingsLog

JUDGE_RE = re.compile(r"result=([A-Za-z_]+)")
OUTCOMES = ("PASS", "FAIL", "CAP", "error", "not run")


def _parse_time(text: Any) -> Optional[datetime]:
    if not isinstance(text, str) or not text:
        return None
    try:
        value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _day(entry: Dict[str, Any]) -> str:
    started = _parse_time(entry.get("started"))
    return started.strftime("%Y-%m-%d") if started else "unknown"


def _hours(entry: Dict[str, Any]) -> float:
    start, end = _parse_time(entry.get("started")), _parse_time(entry.get("ended"))
    if start is None or end is None or end < start:
        return 0.0
    return (end - start).total_seconds() / 3600.0


def judge_outcome(line: Any) -> str:
    """PASS, FAIL, CAP, error or not run, from a judge line's `result=` field."""
    if not isinstance(line, str) or not line.strip():
        return "not run"
    match = JUDGE_RE.search(line)
    if match is None:
        return "error"
    word = match.group(1).upper()
    return word if word in ("PASS", "FAIL", "CAP") else "error"


def _num(value: Any) -> float:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return 0.0


def _iterations(entry: Dict[str, Any]) -> List[Dict[str, Any]]:
    its = entry.get("iterations")
    return [i for i in its if isinstance(i, dict)] if isinstance(its, list) else []


def _mean(values: List[float]) -> Optional[float]:
    return round(sum(values) / len(values), 4) if values else None


def _champion_changed(entry: Dict[str, Any]) -> bool:
    after = entry.get("champion_after")
    return after is not None and after != entry.get("champion_before")


def _group(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    kinds: Dict[str, int] = {}
    statuses: Dict[str, int] = {}
    seconds = 0.0
    labels = 0
    iterations = 0
    fitted: List[float] = []
    heldout: List[float] = []
    judge_random = {k: 0 for k in OUTCOMES}
    judge_champion = {k: 0 for k in OUTCOMES}
    for e in entries:
        kinds[str(e.get("kind"))] = kinds.get(str(e.get("kind")), 0) + 1
        statuses[str(e.get("status"))] = statuses.get(str(e.get("status")), 0) + 1
        for it in _iterations(e):
            iterations += 1
            labels += int(_num(it.get("labels")))
            seconds += _num(it.get("label_seconds"))
            if it.get("run") and it.get("fit"):  # a fit of this block's run: seed candidates,
                # trials and interrupted iterations have no agreement and would read as 0.0
                fitted.append(_num(it.get("agreement_fitted")))
                heldout.append(_num(it.get("agreement_heldout")))
            judge_random[judge_outcome(it.get("judge_random"))] += 1
            judge_champion[judge_outcome(it.get("judge_champion"))] += 1
    hours = sum(_hours(e) for e in entries)
    label_hours = seconds / 3600.0
    return {
        "blocks": len(entries), "kinds": kinds, "statuses": statuses,
        "hours": round(hours, 2), "labels": labels,
        "label_hours": round(label_hours, 2),
        "labels_per_hour": round(labels / label_hours, 1) if label_hours > 0 else None,
        "iterations": iterations,
        "agreement_fitted_mean": _mean(fitted),
        "agreement_fitted_last": fitted[-1] if fitted else None,
        "agreement_heldout_mean": _mean(heldout),
        "agreement_heldout_last": heldout[-1] if heldout else None,
        "judge_random": judge_random, "judge_champion": judge_champion,
        "champion_changes": sum(1 for e in entries if _champion_changed(e)),
    }


def compute(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    entries = sorted(entries, key=lambda e: int(e["block"]))
    days: Dict[str, List[Dict[str, Any]]] = {}
    for e in entries:
        days.setdefault(_day(e), []).append(e)
    history: List[Dict[str, Any]] = []
    sources: Dict[str, int] = {"advisor": 0, "fallback": 0, "steering": 0, "default": 0}
    trials: List[Dict[str, Any]] = []
    refusals: List[Dict[str, Any]] = []
    plateaus: List[int] = []
    faults: List[Dict[str, Any]] = []
    for e in entries:
        block = int(e["block"])
        became = [str(i.get("fit")) for i in _iterations(e) if i.get("became_champion")]
        if _champion_changed(e) or became:
            history.append({"block": block, "fit": became[-1] if became else None,
                            "from": e.get("champion_before"), "to": e.get("champion_after"),
                            "became_champion": bool(became)})
        src = str(e.get("plan_source"))
        sources[src] = sources.get(src, 0) + 1
        trial = e.get("trial")
        if trial:
            item: Dict[str, Any] = {"block": block}
            if isinstance(trial, dict):
                item["knob"] = trial.get("knob")
                item["value"] = trial.get("value")
                item["outcome"] = trial.get("outcome")
            else:
                item["outcome"] = str(trial)
            trials.append(item)
        refused = e.get("refused")
        for r in refused if isinstance(refused, list) else []:
            refusals.append({"block": block, "item": r})
        if e.get("plateau") is True:
            plateaus.append(block)
        if e.get("fault"):
            faults.append({"block": block, "status": e.get("status"), "fault": str(e["fault"])})
    last_reason: Optional[Any] = None
    for e in entries:
        adv = e.get("advisor")
        if isinstance(adv, dict) and adv.get("reason"):
            last_reason = adv["reason"]
    last = entries[-1] if entries else None
    return {
        "total": _group(entries),
        "days": {d: _group(days[d]) for d in sorted(days)},
        "champion_history": history, "plan_sources": sources, "trials": trials,
        "refusals": refusals, "plateaus": plateaus, "faults": faults,
        "last_plan": last.get("plan") if last else None,
        "last_plan_block": last["block"] if last else None,
        "advisor_last_reason": last_reason,
        "last_block": last["block"] if last else None,
        "last_day": _day(last) if last else None,
    }


def _f(value: Any) -> str:
    return "-" if value is None else str(value)


def _judge(d: Dict[str, int]) -> str:
    return " ".join("%s %d" % (k, d[k]) for k in OUTCOMES if d[k]) or "-"


def _row(label: str, g: Dict[str, Any]) -> str:
    kinds = ", ".join("%s %d" % kv for kv in sorted(g["kinds"].items())) or "-"
    stat = ", ".join("%s %d" % kv for kv in sorted(g["statuses"].items())) or "-"
    cells = [label, str(g["blocks"]), kinds, stat, str(g["hours"]), str(g["labels"]),
             _f(g["labels_per_hour"]), str(g["iterations"]),
             "%s / %s" % (_f(g["agreement_fitted_mean"]), _f(g["agreement_fitted_last"])),
             "%s / %s" % (_f(g["agreement_heldout_mean"]), _f(g["agreement_heldout_last"])),
             _judge(g["judge_random"]), _judge(g["judge_champion"]),
             str(g["champion_changes"])]
    return "| " + " | ".join(cells) + " |"


def render(fig: Dict[str, Any]) -> str:
    out: List[str] = ["# Training figures", "", "## By day", ""]
    out.append("| Day | Blocks | Kinds | Statuses | Hours | Labels | Labels/h | Iterations "
               "| Fitted mean / last | Held-out mean / last | Vs random | Vs champion "
               "| Champion changes |")
    out.append("|" + "---|" * 13)
    for day, g in fig["days"].items():
        out.append(_row(day, g))
    out.append(_row("**Total**", fig["total"]))
    out += ["", "## Champion history", ""]
    if fig["champion_history"]:
        out += ["| Block | Fit | From | To | Became champion |", "|---|---|---|---|---|"]
        for h in fig["champion_history"]:
            out.append("| %d | %s | %s | %s | %s |" % (
                h["block"], _f(h["fit"]), _f(h["from"]), _f(h["to"]),
                "yes" if h["became_champion"] else "no"))
    else:
        out.append("None.")
    out += ["", "## Plan sources", "", "| Source | Blocks |", "|---|---|"]
    for k, v in fig["plan_sources"].items():
        out.append("| %s | %d |" % (k, v))
    out += ["", "## Trials", ""]
    if fig["trials"]:
        out += ["| Block | Knob | Value | Outcome |", "|---|---|---|---|"]
        for t in fig["trials"]:
            out.append("| %d | %s | %s | %s |" % (
                t["block"], _f(t.get("knob")), _f(t.get("value")), _f(t.get("outcome"))))
    else:
        out.append("None.")
    out += ["", "## Refusals", ""]
    refusal_lines = ["- block %d: %s" % (r["block"], json.dumps(r["item"]))
                     for r in fig["refusals"]]
    out += refusal_lines or ["None."]
    out += ["", "## Plateaus", ""]
    out.append(", ".join("block %d" % b for b in fig["plateaus"]) or "None.")
    out += ["", "## Faults", ""]
    fault_lines = ["- block %d (%s): %s" % (f["block"], f["status"], f["fault"])
                   for f in fig["faults"]]
    out += fault_lines or ["None."]
    out += ["", "## Last plan", ""]
    if fig["last_plan"] is None:
        out.append("None.")
    else:
        out.append("Block %s: `%s`" % (fig["last_plan_block"],
                                       json.dumps(fig["last_plan"], sort_keys=True)))
    if fig.get("skipped_lines"):
        out += ["", "## Skipped lines", ""]
        out += ["- findings.jsonl %s" % p for p in fig["skipped_lines"]]
    out += ["", "Advisor's last reason: %s" % _f(fig["advisor_last_reason"]), ""]
    return "\n".join(out)


def digest(directory: Path) -> Tuple[int, str]:
    """Write figures.json and figures.md; returns (exit code, summary or error line)."""
    directory = Path(directory)
    entries, problems = FindingsLog(directory / "findings.jsonl").read()
    for p in problems:  # a torn line stays in the log for good: warn, skip, carry on
        print("digest: findings.jsonl " + p + " (skipped)", file=sys.stderr)
    if problems and not entries:
        return 1, "digest: findings.jsonl " + problems[0]
    fig = compute(entries)
    fig["skipped_lines"] = list(problems)
    (directory / "figures.json").write_text(
        json.dumps(fig, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (directory / "figures.md").write_text(render(fig), encoding="utf-8")
    if not entries:
        return 0, "digest: 0 blocks"
    total = fig["total"]
    return 0, "digest: %d blocks, %.1f h, %d champion changes, last block %d (%s)" % (
        total["blocks"], total["hours"], total["champion_changes"],
        fig["last_block"], fig["last_day"])


def cli_digest(args: List[str]) -> int:
    default = Path(__file__).resolve().parent.parent / "godot" / "reports" / "bot" / "autopilot"
    parser = argparse.ArgumentParser(prog="trainer digest")
    parser.add_argument("--dir", default=str(default))
    ns = parser.parse_args(args)
    code, line = digest(Path(ns.dir))
    if code == 0:
        print(line)
    return code
