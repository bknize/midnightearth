"""The stamp's three files (cycle 11 R1, plan P1, T01): records.current_stamp() hashes the
card pool, the deck list and the Crew pool in that order, and gives the digest
godot/tests/test_bot_stamp.gd pins for the frozen copy of the data files under
godot/tests/fixtures/stamp/."""
import hashlib
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import records  # noqa: E402

FIXTURES = Path(records.GODOT_DIR) / "tests" / "fixtures" / "stamp"
FIXTURE_CARDS = FIXTURES / "cards.json"
FIXTURE_DECKS = FIXTURES / "decks.json"
FIXTURE_CREW = FIXTURES / "crew.json"
# test_bot_stamp.gd PINNED_DIGEST: the same 16 hex digits on both sides.
PINNED_DIGEST = "857b165d5a5d755e"


def engine_equivalent(cards: Path, decks: Path, crew: Path) -> str:
    """BotStamp.current() spelled out: one SHA-256 over the three files' bytes in order."""
    h = hashlib.sha256()
    for p in (cards, decks, crew):
        with open(p, "rb") as f:
            h.update(f.read())
    return "r%d-%s" % (records.rules_version(), h.hexdigest()[:16])


class StampTest(unittest.TestCase):
    def test_fixture_stamp_matches_the_engine_pin(self) -> None:
        stamp = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=FIXTURE_CREW)
        self.assertEqual(stamp, "r%d-%s" % (records.rules_version(), PINNED_DIGEST))
        self.assertEqual(stamp, engine_equivalent(FIXTURE_CARDS, FIXTURE_DECKS, FIXTURE_CREW))

    def test_str_and_path_arguments_agree(self) -> None:
        as_str = records.current_stamp(str(FIXTURE_CARDS), str(FIXTURE_DECKS),
                                       crew=str(FIXTURE_CREW))
        as_path = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=FIXTURE_CREW)
        self.assertEqual(as_str, as_path)

    def test_the_rules_version_is_nine(self) -> None:
        self.assertEqual(records.rules_version(), 9)
        self.assertEqual(records.rules_version(Path(records.RULES_PATH)), 9)

    def test_a_crlf_rules_file_reads_the_same(self) -> None:
        tmp = tempfile.mkdtemp()
        try:
            crlf = Path(tmp) / "match_rules.gd"
            lf = Path(records.RULES_PATH).read_bytes()
            crlf.write_bytes(lf.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
            self.assertEqual(records.rules_version(crlf), records.rules_version())
        finally:
            shutil.rmtree(tmp)

    def test_default_hashes_the_shipped_files(self) -> None:
        self.assertEqual(Path(records.CREW_PATH),
                         Path(records.GODOT_DIR) / "engine" / "data" / "crew.json")
        explicit = records.current_stamp(records.CARDS_PATH, records.DECKS_PATH,
                                         crew=records.CREW_PATH)
        self.assertEqual(records.current_stamp(), explicit)
        self.assertRegex(explicit, records.STAMP_RE)
        self.assertTrue(explicit.startswith("r9-"))
        self.assertEqual(explicit, engine_equivalent(Path(records.CARDS_PATH),
                                                     Path(records.DECKS_PATH),
                                                     Path(records.CREW_PATH)))

    def test_a_crew_change_changes_the_stamp(self) -> None:
        tmp = tempfile.mkdtemp()
        try:
            crew = Path(tmp) / "crew.json"
            shutil.copyfile(FIXTURE_CREW, crew)
            same = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=crew)
            self.assertEqual(same, records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS,
                                                         crew=FIXTURE_CREW))
            data = bytearray(crew.read_bytes())
            data[0] = (data[0] + 1) % 256
            crew.write_bytes(bytes(data))
            changed = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=crew)
            self.assertNotEqual(changed, same)
        finally:
            shutil.rmtree(tmp)

    def test_aggregate_reads_the_weights_stamp(self) -> None:
        """Cycle 13 R15: the end record's weights_stamp (match, MISMATCH, none) is collected;
        an end record without the field adds nothing."""
        ends = [{"t": "end", "weights_stamp": "none"}, {"t": "end", "weights_stamp": "match"},
                {"t": "end", "weights_stamp": "match"}, {"t": "end"}]
        self.assertEqual(records.aggregate(ends)["weights_stamps"], ["match", "none"])
        ends.append({"t": "end", "weights_stamp": "MISMATCH"})
        self.assertEqual(records.aggregate(ends)["weights_stamps"],
                         ["MISMATCH", "match", "none"])
        self.assertEqual(records.aggregate([])["weights_stamps"], [])

    def test_a_missing_file_raises(self) -> None:
        missing = FIXTURES / "none.json"
        with self.assertRaises(OSError):
            records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=missing)

    def test_the_files_are_hashed_cards_decks_crew(self) -> None:
        stamp = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=FIXTURE_CREW)
        swapped = records.current_stamp(FIXTURE_CREW, FIXTURE_DECKS, crew=FIXTURE_CARDS)
        self.assertNotEqual(stamp, swapped)


if __name__ == "__main__":
    unittest.main()
