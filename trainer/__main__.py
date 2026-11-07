"""Trainer CLI: serve, run (stubs until T09/T10) and selftest."""
import sys
import unittest
from pathlib import Path
from typing import List, Optional

# `python -I` leaves the current directory off sys.path, so `-m trainer` cannot find the
# package; `python -I trainer <cmd>` (run as a directory) can, once the repo root is added.
if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def _selftest() -> int:
    root = Path(__file__).resolve().parent.parent
    suite = unittest.defaultTestLoader.discover(str(root / "trainer" / "tests"),
                                                top_level_dir=str(root))
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    return 0 if result.wasSuccessful() else 1


def main(argv: Optional[List[str]] = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    cmd = args[0] if args else ""
    if cmd in ("serve", "run"):
        print("trainer %s: not yet implemented" % cmd)
        return 3
    if cmd == "selftest":
        return _selftest()
    print("usage: python -I -m trainer serve|run|selftest")
    return 2


if __name__ == "__main__":
    sys.exit(main())
