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
]


REPLACEMENTS = [
    ("res://scenes/", "res://engine/scenes/"),
    ("res://scripts/", "res://engine/scripts/"),
    ("res://data/", "res://engine/data/"),
    ("res://tools/", "res://engine/tools/"),
    ("res://mecanicas/", "res://engine/mecanicas/"),
    ("res://assets/", "res://visuals/assets/"),
    (" tools/", " engine/tools/"),
    ('"tools/', '"engine/tools/'),
    ('Path("tools")', 'Path("engine") / "tools"'),
    ("Path('tools')", "Path('engine') / 'tools'"),
]


def _iter_files(root: Path):
    seen = set()
    for glob in TEXT_GLOBS:
        for path in root.rglob(glob):
            if path.is_file():
                key = str(path).lower()
                if key in seen:
                    continue
                seen.add(key)
                yield path


def _read_text(path: Path) -> str | None:
    data = path.read_bytes()
    for enc in ("utf-8", "utf-8-sig", "cp1252", "latin-1"):
        try:
            return data.decode(enc)
        except Exception:
            continue
    return None


def _write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    changed_files: list[Path] = []

    for file_path in _iter_files(root):
        text = _read_text(file_path)
        if text is None:
            continue
        new_text = text
        for src, dst in REPLACEMENTS:
            new_text = new_text.replace(src, dst)
        if new_text != text:
            changed_files.append(file_path)
            if not args.dry_run:
                _write_text(file_path, new_text)

    print(f"updated_files={len(changed_files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
