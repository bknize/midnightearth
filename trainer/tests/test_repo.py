import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from trainer import repo
from trainer.farm import worker_command

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "bot"))
import records  # noqa: E402


class StampTest(unittest.TestCase):
    def test_the_trainer_and_scripts_bot_share_one_stamp(self) -> None:
        self.assertEqual(repo.stamp_of(ROOT), records.current_stamp())
        self.assertIs(records.repo, repo)
        self.assertEqual(records.rules_version(), repo.rules_version(records.RULES_PATH))

    def test_a_crlf_checkout_reads_the_same_rules_version(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "match_rules.gd"
            path.write_bytes(b"extends RefCounted\r\nconst RULES_VERSION: int = 7\r\n")
            self.assertEqual(repo.rules_version(path), 7)
            path.write_bytes(b"nothing\n")
            with self.assertRaises(ValueError):
                repo.rules_version(path)

    def test_records_imports_under_python_i(self) -> None:
        script = ROOT / "scripts" / "bot" / "driver.py"
        done = subprocess.run([sys.executable, "-I", str(script), "--help"], cwd=str(ROOT),
                              capture_output=True, text=True, timeout=60, check=False)
        self.assertEqual(done.returncode, 0, done.stderr)


class GodotTest(unittest.TestCase):
    def test_the_environment_wins_and_must_exist(self) -> None:
        with mock.patch.dict(os.environ, {"GODOT_BIN": sys.executable}):
            self.assertEqual(repo.godot_bin(), sys.executable)
        with mock.patch.dict(os.environ, {"GODOT_BIN": "/no/such/godot"}):
            with self.assertRaisesRegex(repo.GodotNotFound, "GODOT_BIN=/no/such/godot"):
                repo.godot_bin()

    def test_path_then_a_clear_failure(self) -> None:
        clean = {k: v for k, v in os.environ.items() if k != "GODOT_BIN"}
        no_install = mock.patch.object(repo, "WINDOWS_GODOT", "no-such-install")
        with mock.patch.dict(os.environ, clean, clear=True), no_install:
            with mock.patch("shutil.which", return_value="/somewhere/godot"):
                self.assertEqual(repo.godot_bin(), "/somewhere/godot")
            with mock.patch("shutil.which", return_value=None):
                with self.assertRaisesRegex(repo.GodotNotFound, "set GODOT_BIN"):
                    repo.godot_bin()

    def test_a_given_binary_is_not_looked_up(self) -> None:
        with mock.patch.dict(os.environ, {"GODOT_BIN": "/no/such/godot"}):
            self.assertEqual(worker_command("mine", Path("r"))[0], "mine")
            with self.assertRaises(repo.GodotNotFound):
                worker_command()


class GitHeadTest(unittest.TestCase):
    def test_a_folder_with_no_repository_gives_empty(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(repo.git_head(Path(d) / "gone"), "")


if __name__ == "__main__":
    unittest.main()
