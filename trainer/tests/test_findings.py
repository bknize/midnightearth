import tempfile
import unittest
from pathlib import Path

from trainer.findings import FindingsLog, check_entry, new_entry, new_iteration


class FindingsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "sub" / "findings.jsonl"
        self.log = FindingsLog(self.path)

    def test_append_and_read(self) -> None:
        a = new_entry(1)
        b = new_entry(2, kind="trial", status="interrupted", plan_source="advisor")
        b["iterations"].append(new_iteration(run="r1"))
        self.log.append(a)
        self.log.append(b)
        entries, problems = self.log.read()
        self.assertEqual(problems, [])
        self.assertEqual(entries, [a, b])
        self.assertEqual(self.log.last_block(), 2)

    def test_empty(self) -> None:
        self.assertEqual(self.log.read(), ([], []))
        self.assertEqual(self.log.last_block(), 0)

    def test_only_grows(self) -> None:
        self.log.append(new_entry(1))
        before = self.path.read_bytes()
        self.log.append(new_entry(2))
        after = self.path.read_bytes()
        self.assertTrue(after.startswith(before))
        self.assertGreater(len(after), len(before))

    def test_torn_last_line(self) -> None:
        self.log.append(new_entry(1))
        with open(self.path, "ab") as f:
            f.write(b'{"block": 2, "kin')
        entries, problems = self.log.read()
        self.assertEqual([e["block"] for e in entries], [1])
        self.assertEqual(len(problems), 1)
        self.assertTrue(problems[0].startswith("line 2:"))
        torn = self.path.read_bytes()
        self.log.append(new_entry(3))
        self.assertTrue(self.path.read_bytes().startswith(torn))
        entries, problems = self.log.read()
        self.assertEqual([e["block"] for e in entries], [1, 3])
        self.assertEqual(len(problems), 1)

    def test_after_filter(self) -> None:
        for n in (1, 2, 3):
            self.log.append(new_entry(n))
        entries, _ = self.log.read(after=1)
        self.assertEqual([e["block"] for e in entries], [2, 3])
        entries, _ = self.log.read(after=3)
        self.assertEqual(entries, [])

    def test_check_entry_refuses(self) -> None:
        self.assertEqual(check_entry(new_entry(1)), [])
        for key in ("kind", "status", "plan_source"):
            entry = new_entry(1)
            entry[key] = "x"
            self.assertTrue(check_entry(entry))
            with self.assertRaises(ValueError):
                self.log.append(entry)
        entry = new_entry(1)
        del entry["fault"]
        self.assertTrue(check_entry(entry))
        self.assertFalse(self.path.exists())


if __name__ == "__main__":
    unittest.main()
