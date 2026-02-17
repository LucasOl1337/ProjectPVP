import argparse
from pathlib import Path


TEXT_GLOBS = [
    "*.gd",
    "*.tscn",
    "*.tres",
    "*.godot",
    "*.json",
    "*.md",
    "*.py",
    "*.cfg",
    "*.gdshader",
    "*.txt",
    "*.bat",
]


def _iter_files(root: Path):
    seen = set()
    for glob in TEXT_GLOBS:
        for path in root.rglob(glob):
            if not path.is_file():
                continue
            key = str(path).lower()
            if key in seen:
                continue
            seen.add(key)
            yield path


def _decode_bytes(data: bytes) -> str | None:
    for enc in ("utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "cp1252", "latin-1"):
        try:
            return data.decode(enc)
        except Exception:
            continue
    return None


def _normalize_text(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    changed = 0

    for file_path in _iter_files(root):
        data = file_path.read_bytes()
        text = _decode_bytes(data)
        if text is None:
            continue
        new_text = _normalize_text(text)
        out = new_text.encode("utf-8")
        if out != data:
            changed += 1
            if not args.dry_run:
                file_path.write_bytes(out)

    print(f"normalized_files={changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

