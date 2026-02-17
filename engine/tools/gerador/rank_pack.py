from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--top", type=int, default=10)
    args = ap.parse_args()

    jobs_dir = Path("engine") / "tools" / "_cache" / "pixellab_jobs" / "pixellab" / "jobs"
    base = str(args.id).strip()
    rows: list[tuple[float, str, str]] = []
    for p in jobs_dir.glob(base + "__v*.json"):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        score = float(data.get("qa_score") or 0.0)
        char_id = str(data.get("char_id") or p.stem)
        asset_dir = str(data.get("asset_dir") or "")
        rows.append((score, char_id, asset_dir))

    rows.sort(key=lambda x: x[0], reverse=True)
    top = max(1, int(args.top))
    for score, char_id, asset_dir in rows[:top]:
        south = ""
        if asset_dir:
            south = str(Path(asset_dir) / "rotations" / "south.png")
        print(f"qa_score={score:.2f} id={char_id} south={south}")


if __name__ == "__main__":
    main()
