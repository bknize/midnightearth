"""Tests for the Mac digest and the pull script (cycle 16 R40, R41, R43)."""
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict

from trainer.digest import digest, judge_outcome
from trainer.findings import FindingsLog, new_entry, new_iteration

ROOT = Path(__file__).resolve().parent.parent.parent


def _it(fit: str, fitted: float, held: float, labels: int, secs: float, jr: str = "",
        jc: str = "", became: bool = False) -> Dict[str, Any]:
    return new_iteration(run="r-" + fit, fit=fit, positions=100, labels=labels,
                         label_seconds=secs, agreement_fitted=fitted, agreement_heldout=held,
                         judge_random=jr, judge_champion=jc, became_champion=became)


def _write_fixture(path: Path) -> None:
    log = FindingsLog(path)
    seed = new_entry(1, "seed", "done", "2026-11-10T20:00:00Z", "2026-11-10T21:00:00Z")
    seed["iterations"] = [_it("F0", 0.5, 0.4, 0, 0, "bot-eval: result=PASS", "")]
    seed["champion_after"] = "F0"
    log.append(seed)
    adv = new_entry(2, "full", "done", "2026-11-10T22:00:00Z", "2026-11-11T02:00:00Z",
                    plan={"depth": 3}, plan_source="advisor")
    adv["iterations"] = [
        _it("F1", 0.6, 0.5, 3600, 3600, "bot-eval: result=PASS", "bot-eval: result=FAIL"),
        _it("F2", 0.7, 0.6, 7200, 3600, "bot-eval: result=PASS", "bot-eval: result=PASS",
            True)]
    adv["champion_before"] = "F0"
    adv["champion_after"] = "F2"
    adv["advisor"] = {"model": "m", "prompt_digest": "d", "reason": "go deeper", "seconds": 4}
    log.append(adv)
    fb = new_entry(3, "full", "done", "2026-11-11T03:00:00Z", "2026-11-11T05:30:00Z",
                   plan={"depth": 4}, plan_source="fallback")
    fb["iterations"] = [_it("F3", 0.8, 0.7, 1800, 3600, "bot-eval: result=CAP",
                            "bot-eval: result=garbage")]
    fb["champion_before"] = fb["champion_after"] = "F2"
    fb["plateau"] = True
    fb["refused"] = ["depth=99 over the hard limit"]
    log.append(fb)
    trial = new_entry(4, "trial", "done", "2026-11-12T00:00:00Z", "2026-11-12T00:20:00Z",
                      plan={"depth": 5}, plan_source="advisor")
    trial["trial"] = {"knob": "depth", "value": 5, "outcome": "worse"}
    trial["advisor"] = {"model": "m", "prompt_digest": "e", "reason": "try five", "seconds": 3}
    log.append(trial)
    intr = new_entry(5, "full", "interrupted", "2026-11-12T01:00:00Z", "2026-11-12T02:00:00Z",
                     plan_source="steering")
    intr["fault"] = "stopped by STOP file"
    log.append(intr)
    bad = new_entry(6, "full", "failed", "2026-11-12T03:00:00Z", "2026-11-12T03:30:00Z")
    bad["fault"] = "label worker died"
    bad["plan"] = {"depth": 6}
    del bad["advisor"]  # an entry without the optional field; written raw (append validates)
    with open(path, "ab") as f:
        f.write(json.dumps(bad, sort_keys=True).encode("utf-8") + b"\n")


class DigestTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)

    def test_judge_outcome(self) -> None:
        self.assertEqual(judge_outcome(""), "not run")
        self.assertEqual(judge_outcome("bot-eval: n=10 result=PASS"), "PASS")
        self.assertEqual(judge_outcome("bot-eval: result=cap"), "CAP")
        self.assertEqual(judge_outcome("it broke"), "error")

    def test_figures(self) -> None:
        _write_fixture(self.dir / "findings.jsonl")
        code, line = digest(self.dir)
        self.assertEqual(code, 0)
        self.assertEqual(
            line, "digest: 6 blocks, 9.3 h, 2 champion changes, last block 6 (2026-11-12)")
        fig = json.loads((self.dir / "figures.json").read_text())
        total = fig["total"]
        self.assertEqual(total["blocks"], 6)
        self.assertEqual(total["kinds"], {"seed": 1, "full": 4, "trial": 1})
        self.assertEqual(total["statuses"], {"done": 4, "interrupted": 1, "failed": 1})
        self.assertAlmostEqual(total["hours"], 9.33, places=2)
        self.assertEqual(total["labels"], 12600)
        self.assertEqual(total["iterations"], 4)
        self.assertAlmostEqual(total["labels_per_hour"], 12600 / (10800 / 3600.0), places=1)
        self.assertEqual(total["agreement_heldout_last"], 0.7)
        self.assertEqual(total["agreement_fitted_mean"], 0.65)
        self.assertEqual(total["judge_random"]["PASS"], 3)
        self.assertEqual(total["judge_random"]["CAP"], 1)
        self.assertEqual(total["judge_champion"]["FAIL"], 1)
        self.assertEqual(total["judge_champion"]["error"], 1)
        self.assertEqual(total["judge_champion"]["not run"], 1)
        self.assertEqual(list(fig["days"]), ["2026-11-10", "2026-11-11", "2026-11-12"])
        self.assertEqual(fig["days"]["2026-11-10"]["blocks"], 2)
        self.assertEqual(fig["days"]["2026-11-12"]["statuses"],
                         {"done": 1, "interrupted": 1, "failed": 1})
        self.assertEqual([h["block"] for h in fig["champion_history"]], [1, 2])
        self.assertEqual(fig["champion_history"][1]["from"], "F0")
        self.assertEqual(fig["champion_history"][1]["to"], "F2")
        self.assertTrue(fig["champion_history"][1]["became_champion"])
        self.assertEqual(fig["plan_sources"],
                         {"advisor": 2, "fallback": 1, "steering": 1, "default": 2})
        self.assertEqual(fig["trials"], [{"block": 4, "knob": "depth", "value": 5,
                                          "outcome": "worse"}])
        self.assertEqual(fig["refusals"],
                         [{"block": 3, "item": "depth=99 over the hard limit"}])
        self.assertEqual(fig["plateaus"], [3])
        self.assertEqual([(f["block"], f["status"]) for f in fig["faults"]],
                         [(5, "interrupted"), (6, "failed")])
        self.assertEqual(fig["last_plan"], {"depth": 6})
        self.assertEqual(fig["advisor_last_reason"], "try five")
        md = (self.dir / "figures.md").read_text()
        for needle in ("2026-11-11", "Champion history", "label worker died",
                       "depth=99", "try five"):
            self.assertIn(needle, md)

    def test_bad_line_is_skipped_and_recorded(self) -> None:
        _write_fixture(self.dir / "findings.jsonl")
        with open(self.dir / "findings.jsonl", "ab") as f:
            f.write(b'{"block": 7, "kind": "ful')
        code, line = digest(self.dir)
        self.assertEqual(code, 0)
        self.assertIn("6 blocks", line)
        fig = json.loads((self.dir / "figures.json").read_text())
        self.assertEqual(len(fig["skipped_lines"]), 1)
        self.assertIn("line 7", fig["skipped_lines"][0])
        self.assertIn("Skipped lines", (self.dir / "figures.md").read_text())

    def test_only_bad_lines_exit_one(self) -> None:
        (self.dir / "findings.jsonl").write_bytes(b'{"block": 1, "kind": "ful\n')
        code, line = digest(self.dir)
        self.assertEqual(code, 1)
        self.assertIn("line 1", line)
        self.assertFalse((self.dir / "figures.json").exists())

    def test_pull_script_one_scp(self) -> None:
        fixture = self.dir / "remote.jsonl"
        _write_fixture(fixture)
        calls = self.dir / "calls.txt"
        stub = self.dir / "stub-scp.sh"
        stub.write_text('#!/bin/sh\necho "$@" >> "%s"\ncp "%s" "$3"\n' % (calls, fixture))
        stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
        target = self.dir / "out"
        env = dict(os.environ, SCP=str(stub), TRAINING_DIGEST_DIR=str(target))
        proc = subprocess.run(["bash", str(ROOT / "scripts" / "training-pull.sh")], env=env,
                              capture_output=True, text=True, cwd=str(self.dir))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(len(calls.read_text().strip().splitlines()), 1)
        self.assertIn("midnight-pc:C:/Users/trainer/trainer-data/autopilot/findings.jsonl",
                      calls.read_text())
        self.assertTrue((target / "figures.json").exists())
        self.assertTrue((target / "figures.md").exists())
        self.assertIn("digest: 6 blocks", proc.stdout)

    def test_pull_script_failed_scp_keeps_last_copy(self) -> None:
        target = self.dir / "out"
        target.mkdir()
        (target / "findings.jsonl").write_text("old\n")
        stub = self.dir / "fail-scp.sh"
        stub.write_text("#!/bin/sh\nexit 1\n")
        stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
        env = dict(os.environ, SCP=str(stub), TRAINING_DIGEST_DIR=str(target))
        proc = subprocess.run(["bash", str(ROOT / "scripts" / "training-pull.sh")], env=env,
                              capture_output=True, text=True, cwd=str(self.dir))
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("scp", proc.stderr)
        self.assertEqual((target / "findings.jsonl").read_text(), "old\n")


if __name__ == "__main__":
    unittest.main()
