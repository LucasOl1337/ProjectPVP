from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageSequence


def extract_gif(gif_path: Path) -> None:
    if not gif_path.exists():
        raise FileNotFoundError(gif_path)
    out_dir = gif_path.parent
    saved = 0
    with Image.open(gif_path) as im:
        for idx, frame in enumerate(ImageSequence.Iterator(im)):
            frame = frame.convert("RGBA")
            out_path = out_dir / f"frame_{idx:03d}.png"
            frame.save(out_path)
            saved += 1
            print(f"Saved {out_path}")
    if saved == 0:
        print(f"[WARN] No frames found in {gif_path}")
    else:
        print(f"[INFO] Extracted {saved} frame(s) from {gif_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract PNG frames from GIF animations")
    parser.add_argument("gifs", nargs="+", help="Path(s) to GIF files")
    args = parser.parse_args()

    for gif in args.gifs:
        extract_gif(Path(gif))


if __name__ == "__main__":
    main()
