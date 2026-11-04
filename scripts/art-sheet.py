"""art-sheet.py - build a labelled contact sheet of a candidate batch (ADR 0003).

    python3 scripts/art-sheet.py art/candidates/<batch> [--cols 5] [--thumb 256]
                                    [--out <path>] [--match <glob>]

Every image in the folder (png, webp, jpg) except earlier sheets is shrunk to a
thumbnail --thumb pixels wide, laid out --cols across, and labelled with its file name.
The sheet is written to <batch>/sheet.png unless --out says otherwise. Folders with more
than 40 images get one sheet per 40 (sheet-1.png, sheet-2.png, ...), so a reviewer can
look at a page at a time. Needs Pillow. Exit codes: 0 ok, 1 no images, 2 bad usage.
"""

from __future__ import annotations

import argparse
import fnmatch
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

EXTS = {".png", ".webp", ".jpg", ".jpeg"}
PER_SHEET = 40
LABEL_H = 22
GAP = 8
BG = (24, 22, 28)
FG = (235, 232, 240)


def build(paths: list[Path], cols: int, thumb: int, out: Path) -> None:
    thumbs: list[Image.Image] = []
    for p in paths:
        with Image.open(p) as im:
            im = im.convert("RGB")
            h = round(im.height * thumb / im.width)
            thumbs.append(im.resize((thumb, h), Image.LANCZOS))
    cell_h = max(t.height for t in thumbs) + LABEL_H
    rows = (len(thumbs) + cols - 1) // cols
    width = GAP + cols * (thumb + GAP)
    height = GAP + rows * (cell_h + GAP)
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for i, (p, t) in enumerate(zip(paths, thumbs)):
        x = GAP + (i % cols) * (thumb + GAP)
        y = GAP + (i // cols) * (cell_h + GAP)
        sheet.paste(t, (x, y))
        draw.text((x + 2, y + t.height + 4), p.name, fill=FG, font=font)
    sheet.save(out)
    print(f"sheet {out} ({len(paths)} images)")


def main() -> int:
    ap = argparse.ArgumentParser(description="Contact sheet of a candidate batch")
    ap.add_argument("batch", type=Path)
    ap.add_argument("--cols", type=int, default=5)
    ap.add_argument("--thumb", type=int, default=256)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--match", default="*")
    args = ap.parse_args()
    if not args.batch.is_dir() or args.cols < 1 or args.thumb < 32:
        ap.print_usage(sys.stderr)
        return 2
    paths = sorted(
        p for p in args.batch.iterdir()
        if p.suffix.lower() in EXTS
        and not p.name.startswith("sheet")
        and fnmatch.fnmatch(p.name, args.match)
    )
    if not paths:
        print(f"art-sheet: no images in {args.batch}", file=sys.stderr)
        return 1
    pages = [paths[i:i + PER_SHEET] for i in range(0, len(paths), PER_SHEET)]
    for n, page in enumerate(pages, start=1):
        if args.out and len(pages) == 1:
            out = args.out
        elif len(pages) == 1:
            out = args.batch / "sheet.png"
        else:
            stem = args.out.with_suffix("") if args.out else args.batch / "sheet"
            out = Path(f"{stem}-{n}.png")
        build(page, args.cols, args.thumb, out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
