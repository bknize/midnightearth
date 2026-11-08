"""Seed derivation: a bit-for-bit port of MatchRng.derive_seed (godot/engine/match_rng.gd)."""
from typing import List

_MASK = (1 << 64) - 1
_GOLDEN_GAMMA = 0x9E3779B97F4A7C15
_MIX_MUL_1 = 0xBF58476D1CE4E5B9
_MIX_MUL_2 = 0x94D049BB133111EB
PLAY_TAG = 0x706C61  # "pla"
POSITION_TAG = 0x706F73  # "pos"


def _to_signed(x: int) -> int:
    x &= _MASK
    return x - (1 << 64) if x >> 63 else x


def _splitmix64(x: int) -> int:
    """One splitmix64 step on wrapping 64-bit values; shifts are logical (values are kept
    unsigned inside, which makes them so)."""
    z = (x + _GOLDEN_GAMMA) & _MASK
    z = ((z ^ (z >> 30)) * _MIX_MUL_1) & _MASK
    z = ((z ^ (z >> 27)) * _MIX_MUL_2) & _MASK
    return z ^ (z >> 31)


def derive(base: int, parts: List[int]) -> int:
    """splitmix64 over the seed, then over each part with XOR; returns a signed 64-bit int."""
    h = _splitmix64(base & _MASK)
    for part in parts:
        h = _splitmix64(h ^ (part & _MASK))
    return _to_signed(h)


def play_seed(run_seed: int, index: int) -> int:
    return derive(run_seed, [index, PLAY_TAG])


def position_pick_seed(run_seed: int, index: int) -> int:
    return derive(run_seed, [index, POSITION_TAG])


def label_seed(run_seed: int, index: int) -> int:
    return derive(run_seed, [index])


def wire(seed: int) -> str:
    """A seed as the decimal string the play-out worker takes (JSON numbers above 2^53 lose
    precision in Godot)."""
    return str(int(seed))
