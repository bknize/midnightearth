"""sync_code over a fake git and a fake godot (the injected run function)."""
import base64
import shutil
import tempfile
import unittest
from pathlib import Path
from typing import List, Mapping, Optional, Tuple

from trainer.sync import stamp_of, sync_code

GOOD = "abc1234" + "0" * 33
OLD = "def5678" + "0" * 33
RULES = "extends RefCounted\nconst RULES_VERSION: int = 7\n"


class Fake:
    def __init__(self, godot_out: str = "Import done", godot_rc: int = 0) -> None:
        self.calls: List[List[str]] = []
        self.godot_out = godot_out
        self.godot_rc = godot_rc
        self.envs: List[Mapping[str, str]] = []
        self.cwds: List[Optional[Path]] = []

    def __call__(self, argv: List[str], cwd: Optional[Path],
                 env: Mapping[str, str]) -> Tuple[int, str]:
        self.calls.append(argv)
        self.cwds.append(cwd)
        self.envs.append(env)
        if argv[0] == "git":
            if "bundle" in argv:
                return (1, "error: bad bundle") if Path(argv[-1]).read_bytes() == b"bad" \
                    else (0, "ok")
            if "init" in argv:
                Path(argv[-1]).mkdir(parents=True)
                return 0, ""
            if "fetch" in argv:
                return (128, "fatal: couldn't find remote ref") if argv[-1] != GOOD else (0, "")
            if "rev-parse" in argv:
                return 0, OLD + "\n"
            if "worktree" in argv and "remove" in argv:
                shutil.rmtree(argv[-1], ignore_errors=True)
                return 0, ""
            if "worktree" in argv:
                work = Path(argv[argv.index("add") + 2])
                (work / ".git").mkdir(parents=True)
                data = work / "godot" / "engine" / "data"
                data.mkdir(parents=True)
                for n in ("cards", "decks", "crew"):
                    (data / (n + ".json")).write_text("{}")
                (work / "godot" / "engine" / "match_rules.gd").write_text(RULES)
                win = work / "trainer" / "windows"
                win.mkdir(parents=True)
                (win / "runner.ps1").write_text("# runner")
                return 0, ""
            return 0, ""
        return self.godot_rc, self.godot_out


class SyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name) / "me"
        self.dest = Path(self._tmp.name) / "trainer" / "runner.ps1"
        self.addCleanup(self._tmp.cleanup)

    def sync(self, fake: Fake, commit: str = GOOD, data: bytes = b"pack",
             **kw: object) -> dict:
        b64 = base64.b64encode(data).decode()
        return sync_code(commit, b64, root=self.root, godot_bin="godot", run=fake, git="git",
                         runner_dest=self.dest, **kw)  # type: ignore[arg-type]

    def test_happy_path(self) -> None:
        fake = Fake()
        out = self.sync(fake)
        self.assertEqual(out["commit"], GOOD)
        self.assertEqual(out["stamp"], stamp_of(self.root / "work"))
        self.assertTrue(out["stamp"].startswith("r7-"))
        self.assertIn("import_s", out)
        self.assertEqual(len(list((self.root / "inbox").glob("*.bundle"))), 1)
        self.assertEqual(fake.envs[-1]["GIT_LFS_SKIP_SMUDGE"], "1")
        self.assertIn("--import", fake.calls[-1])
        # second sync checks out in the existing worktree
        fake2 = Fake()
        self.sync(fake2)
        self.assertIn(["git", "-C", str(self.root / "work"), "checkout", "--detach", GOOD],
                      fake2.calls)

    def test_inbox_file(self) -> None:
        (self.root / "inbox").mkdir(parents=True)
        (self.root / "inbox" / "x.bundle").write_bytes(b"pack")
        out = sync_code(GOOD, inbox_file="x.bundle", root=self.root, godot_bin="godot",
                        run=Fake(), runner_dest=self.dest)
        self.assertEqual(out["commit"], GOOD)
        bad = sync_code(GOOD, inbox_file="../x", root=self.root, godot_bin="godot",
                        run=Fake(), runner_dest=self.dest)
        self.assertIn("error", bad)
        both = sync_code(GOOD, "AAAA", "x.bundle", root=self.root, godot_bin="godot",
                         run=Fake())
        self.assertIn("error", both)

    def test_bad_bundle_changes_nothing(self) -> None:
        out = self.sync(Fake(), data=b"bad")
        self.assertIn("verify", out["error"])
        self.assertFalse((self.root / "repo").exists())
        self.assertFalse((self.root / "work").exists())

    def test_unknown_commit(self) -> None:
        out = self.sync(Fake(), commit="deadbeef" + "0" * 32)
        self.assertIn("fetch failed", out["error"])
        self.assertFalse((self.root / "work").exists())
        self.assertFalse((self.root / "repo").exists())

    def test_import_error_grep(self) -> None:
        out = self.sync(Fake(godot_out="ok\nSCRIPT ERROR: Parse Error: x\n"))
        self.assertIn("import errors", out["error"])
        self.assertFalse(self.dest.exists())

    def test_refused_while_run_active(self) -> None:
        fake = Fake()
        out = self.sync(fake, run_active="run42")
        self.assertIn("run42", out["error"])
        self.assertEqual(fake.calls, [])

    def test_bundle_verify_runs_in_the_repo(self) -> None:
        fake = Fake()
        self.sync(fake)
        i = next(n for n, c in enumerate(fake.calls) if "verify" in c)
        self.assertEqual(fake.cwds[i], self.root / "repo")
        self.assertTrue(any("init" in c for c in fake.calls[:i]))

    def test_short_hash_rejected(self) -> None:
        fake = Fake()
        for short in ("abc1234", "abc1234" + "0" * 32, "g" * 40):
            self.assertIn("40-hex", self.sync(fake, commit=short)["error"])
        self.assertEqual(fake.calls, [])

    def test_failed_import_restores_previous_commit(self) -> None:
        self.sync(Fake())
        fake = Fake(godot_out="SCRIPT ERROR: boom")
        out = self.sync(fake, commit=GOOD)
        self.assertIn("import errors", out["error"])
        self.assertEqual(fake.calls[-1],
                         ["git", "-C", str(self.root / "work"), "checkout", "--detach", OLD])

    def test_failed_first_import_removes_worktree(self) -> None:
        fake = Fake(godot_rc=3, godot_out="boom")
        out = self.sync(fake)
        self.assertIn("exited 3", out["error"])
        self.assertFalse((self.root / "work").exists())

    def test_runner_copied_to_stable_path(self) -> None:
        self.sync(Fake())
        self.assertEqual(self.dest.read_text(), "# runner")


if __name__ == "__main__":
    unittest.main()
