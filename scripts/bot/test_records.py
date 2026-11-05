"""The stamp's three files (cycle 8 R58, plan P15; DC-11 T11): records.current_stamp() hashes
the card pool, the deck list and the Crew pool in that order, and gives the digest
godot/tests/test_bot_stamp.gd pins for the frozen DC-05 fixtures."""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import records  # noqa: E402

GODOT_FIXTURES = os.path.join(records.GODOT_DIR, "tests", "fixtures")
FIXTURE_CARDS = os.path.join(GODOT_FIXTURES, "dc05_cards.json")
FIXTURE_DECKS = os.path.join(GODOT_FIXTURES, "dc05_decks.json")
FIXTURE_CREW = os.path.join(GODOT_FIXTURES, "dc05_crew.json")
# test_bot_stamp.gd PINNED_DIGEST: the same 16 hex digits on both sides.
PINNED_DIGEST = "c8bbaeae375ceee6"


class StampTest(unittest.TestCase):
    def test_fixture_stamp_matches_the_engine_pin(self) -> None:
        stamp = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=FIXTURE_CREW)
        self.assertEqual(stamp, "r%d-%s" % (records.rules_version(), PINNED_DIGEST))

    def test_default_hashes_the_shipped_crew_file(self) -> None:
        self.assertEqual(records.CREW_PATH,
                         os.path.join(records.GODOT_DIR, "engine", "data", "crew.json"))
        explicit = records.current_stamp(records.CARDS_PATH, records.DECKS_PATH,
                                         crew=records.CREW_PATH)
        self.assertEqual(records.current_stamp(), explicit)
        self.assertRegex(explicit, records.STAMP_RE)

    def test_a_crew_change_changes_the_stamp(self) -> None:
        tmp = tempfile.mkdtemp()
        try:
            crew = os.path.join(tmp, "crew.json")
            shutil.copyfile(FIXTURE_CREW, crew)
            same = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=crew)
            self.assertEqual(same, records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS,
                                                         crew=FIXTURE_CREW))
            with open(crew, "ab") as f:
                f.write(b"\n")
            changed = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=crew)
            self.assertNotEqual(changed, same)
        finally:
            shutil.rmtree(tmp)

    def test_the_files_are_hashed_cards_decks_crew(self) -> None:
        stamp = records.current_stamp(FIXTURE_CARDS, FIXTURE_DECKS, crew=FIXTURE_CREW)
        swapped = records.current_stamp(FIXTURE_CREW, FIXTURE_DECKS, crew=FIXTURE_CARDS)
        self.assertNotEqual(stamp, swapped)


if __name__ == "__main__":
    unittest.main()
