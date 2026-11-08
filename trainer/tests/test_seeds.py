import unittest

from trainer import seeds


class SeedsTest(unittest.TestCase):
    def test_pins_from_engine(self) -> None:
        self.assertEqual(seeds.derive(1, [0]), 6791897765849424158)
        self.assertEqual(seeds.derive(12345, [7, 0x706C61]), -3134834727872438388)
        self.assertEqual(seeds.derive(-42, [3, 15]), -2473529868231910617)

    def test_helpers(self) -> None:
        self.assertEqual(seeds.play_seed(9, 4), seeds.derive(9, [4, 0x706C61]))
        self.assertEqual(seeds.position_pick_seed(9, 4), seeds.derive(9, [4, 0x706F73]))
        self.assertEqual(seeds.label_seed(9, 4), seeds.derive(9, [4]))
        self.assertNotEqual(seeds.play_seed(9, 4), seeds.position_pick_seed(9, 4))

    def test_wire_is_decimal_string(self) -> None:
        self.assertEqual(seeds.wire(-3134834727872438388), "-3134834727872438388")

    def test_signed_range(self) -> None:
        for i in range(200):
            v = seeds.derive(i, [i])
            self.assertTrue(-(1 << 63) <= v < (1 << 63))


if __name__ == "__main__":
    unittest.main()
