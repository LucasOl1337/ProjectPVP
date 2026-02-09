#!/usr/bin/env python3
"""Importa ZIPs do PixelLab para a estrutura do projeto.

Uso:
  python tools/pixellab_import.py <zip_path> --name katarina
  python tools/pixellab_import.py <pasta_com_zips>

Por padrao, extrai para:
  assets/characters/<name>/<variant>/

Onde <variant> padrao = "pixellab".
"""
from __future__ import annotations

import argparse
import json
import shutil
import zipfile
from pathlib import Path

IGNORED_PREFIXES = ("__MACOSX/",)
IGNORED_FILES = {".DS_Store"}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Importa assets PixelLab (ZIP) para o projeto.")
    parser.add_argument(
        "zip_path",
        nargs="+",
        help="ZIP(s) do PixelLab ou diretorio com ZIPs",
    )
    parser.add_argument(
        "--dest-root",
        default="assets/characters",
        help="Diretorio base para assets (default: assets/characters)",
    )
    parser.add_argument(
        "--name",
        default=None,
        help="Nome do personagem/asset (default: nome do ZIP)",
    )
    parser.add_argument(
        "--variant",
        default="pixellab",
        help="Subpasta dentro do personagem (default: pixellab)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Sobrescreve a pasta de destino se ela existir",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Mostra o que seria extraido sem escrever arquivos",
    )
    parser.add_argument(
        "--no-manifest",
        action="store_true",
        help="Nao gera pixellab_manifest.json",
    )
    return parser.parse_args()


def _is_ignored(path: str) -> bool:
    if any(path.startswith(prefix) for prefix in IGNORED_PREFIXES):
        return True
    name = Path(path).name
    return name in IGNORED_FILES


def _common_root(paths: list[str]) -> str:
    parts = [p.split("/") for p in paths if p]
    if not parts:
        return ""
    first = parts[0][0]
    if all(len(p) > 1 and p[0] == first for p in parts):
        return first
    return ""


def _strip_root(path: str, root: str) -> str:
    if root and path.startswith(root + "/"):
        return path[len(root) + 1 :]
    return path


def _safe_relpath(path: str) -> str:
    rel = Path(path)
    if rel.is_absolute() or ".." in rel.parts:
        raise ValueError(f"Path inseguro dentro do zip: {path}")
    return rel.as_posix()


INVALID_TRAILING_CHARS = " ."


def _sanitize_component(name: str) -> str:
    sanitized = name.rstrip(INVALID_TRAILING_CHARS)
    return sanitized or "_"


def _sanitize_relpath(rel: str) -> str:
    if not rel:
        return rel
    parts = rel.split("/")
    return "/".join(_sanitize_component(part) for part in parts)


def _extract_member(zf: zipfile.ZipFile, member: str, dest_dir: Path) -> None:
    rel = _safe_relpath(member)
    rel = _sanitize_relpath(rel)
    target = dest_dir / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    with zf.open(member) as src, open(target, "wb") as dst:
        shutil.copyfileobj(src, dst)


def _load_metadata(zf: zipfile.ZipFile, metadata_path: str) -> dict | None:
    try:
        raw = zf.read(metadata_path)
    except KeyError:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def _summarize_metadata(metadata: dict | None) -> None:
    if not metadata:
        return
    frames = metadata.get("frames", {})
    rotations = frames.get("rotations", {})
    animations = frames.get("animations", {})
    if rotations:
        print(f"Rotations: {sorted(rotations.keys())}")
    if animations:
        anim_names = sorted(animations.keys())
        preview = ", ".join(anim_names[:8])
        suffix = "..." if len(anim_names) > 8 else ""
        print(f"Animations ({len(anim_names)}): {preview}{suffix}")


def _build_manifest(metadata: dict, source_zip: Path) -> dict:
    frames = metadata.get("frames", {})
    rotations = frames.get("rotations", {})
    animations = frames.get("animations", {})
    animation_info: dict[str, dict] = {}
    for anim_name, anim_dirs in animations.items():
        if isinstance(anim_dirs, dict):
            directions = sorted(anim_dirs.keys())
            frame_counts = {}
            for dir_name, frames_list in anim_dirs.items():
                if isinstance(frames_list, list):
                    frame_counts[dir_name] = len(frames_list)
            animation_info[anim_name] = {
                "directions": directions,
                "frame_counts": frame_counts,
            }
    character = metadata.get("character", {})
    size = character.get("size", {})
    return {
        "version": 1,
        "source_zip": source_zip.name,
        "character_id": character.get("id"),
        "name": character.get("name"),
        "prompt": character.get("prompt"),
        "view": character.get("view"),
        "directions": character.get("directions"),
        "size": {
            "width": size.get("width"),
            "height": size.get("height"),
        },
        "rotations": sorted(rotations.keys()),
        "animations": sorted(animations.keys()),
        "animation_detail": animation_info,
    }


def _write_manifest(dest_dir: Path, manifest: dict) -> None:
    manifest_path = dest_dir / "pixellab_manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=True)
        handle.write("\n")


def _resolve_zip_paths(entries: list[str]) -> list[Path]:
    zip_paths: list[Path] = []
    for entry in entries:
        path = Path(entry)
        if path.is_dir():
            zip_paths.extend(sorted(path.rglob("*.zip")))
        else:
            zip_paths.append(path)
    return zip_paths


def main() -> None:
    args = _parse_args()
    zip_paths = _resolve_zip_paths(args.zip_path)
    zip_paths = [p for p in zip_paths if p.exists() and p.suffix.lower() == ".zip"]
    if not zip_paths:
        raise SystemExit("Nenhum ZIP encontrado nos caminhos fornecidos.")

    if args.name and len(zip_paths) > 1:
        raise SystemExit("--name so pode ser usado com um unico ZIP.")

    dest_root = Path(args.dest_root)
    for zip_path in zip_paths:
        name = args.name or zip_path.stem
        dest_dir = dest_root / name / args.variant

        if dest_dir.exists() and any(dest_dir.iterdir()):
            if not args.force:
                raise SystemExit(
                    f"Destino ja existe e nao esta vazio: {dest_dir}. Use --force para sobrescrever."
                )
            if not args.dry_run:
                shutil.rmtree(dest_dir)

        if args.dry_run:
            print(f"[dry-run] Destino: {dest_dir}")
        else:
            dest_dir.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(zip_path) as zf:
            members = [m for m in zf.namelist() if m and not m.endswith("/")]
            members = [m for m in members if not _is_ignored(m)]
            if not members:
                raise SystemExit(f"ZIP vazio ou sem arquivos validos: {zip_path}")

            root = _common_root(members)
            if root and root not in {"rotations", "animations"}:
                members = [_strip_root(m, root) for m in members]
                metadata_path = _strip_root("metadata.json", root)
            else:
                metadata_path = "metadata.json"

            metadata = _load_metadata(zf, metadata_path)
            if args.dry_run:
                for m in members:
                    print(f"[dry-run] {m}")
            else:
                for m in members:
                    rel = _strip_root(m, root) if root else m
                    if not rel:
                        continue
                    _extract_member(zf, rel, dest_dir)

        print(f"Extraido para: {dest_dir}")
        _summarize_metadata(metadata)
        if metadata and not args.no_manifest and not args.dry_run:
            manifest = _build_manifest(metadata, zip_path)
            _write_manifest(dest_dir, manifest)
            print(f"Manifesto: {dest_dir / 'pixellab_manifest.json'}")


if __name__ == "__main__":
    main()
