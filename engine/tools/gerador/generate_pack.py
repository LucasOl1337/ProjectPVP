from __future__ import annotations

import argparse
import subprocess
import sys


def run(cmd: list[str]) -> int:
    p = subprocess.run(cmd, check=False)
    return int(p.returncode)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--description", required=True)
    ap.add_argument("--preset", default="premium_side_128")
    ap.add_argument("--lore", default="")
    ap.add_argument("--style", default="")
    ap.add_argument("--styles", default="")
    ap.add_argument("--shape", default="")
    ap.add_argument("--shapes", default="")
    ap.add_argument("--count", type=int, default=10)
    ap.add_argument("--timeout", type=int, default=7200)
    ap.add_argument("--interval", type=int, default=25)
    ap.add_argument("--no-animations", action="store_true")
    args = ap.parse_args()

    pipeline = [sys.executable, "engine/tools/pixellab_pipeline.py"]

    submit = pipeline + [
        "submit-batch",
        "--id",
        args.id,
        "--name",
        args.name,
        "--description",
        args.description,
        "--preset",
        args.preset,
        "--lore",
        args.lore,
        "--style",
        args.style,
        "--styles",
        args.styles,
        "--shape",
        args.shape,
        "--shapes",
        args.shapes,
        "--count",
        str(int(args.count)),
    ]
    if args.no_animations:
        submit.append("--no-animations")

    rc = run(submit)
    if rc != 0:
        raise SystemExit(rc)

    imp = pipeline + [
        "import-batch",
        "--id",
        args.id,
        "--count",
        str(int(args.count)),
        "--timeout",
        str(int(args.timeout)),
        "--interval",
        str(int(args.interval)),
    ]
    rc = run(imp)
    raise SystemExit(rc)


if __name__ == "__main__":
    main()

