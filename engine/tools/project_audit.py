from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class MissingRef:
	source: str
	ref: str
	resolved_path: Path


def res_to_path(res_path: str) -> Path:
	if not res_path.startswith("res://"):
		return ROOT / res_path
	return ROOT / res_path.removeprefix("res://")


def read_text(path: Path) -> str:
	return path.read_text(encoding="utf-8", errors="replace")


def parse_project_godot(project_path: Path) -> tuple[str | None, list[str]]:
	text = read_text(project_path)
	main_scene: str | None = None
	autoloads: list[str] = []
	section: str | None = None
	for raw_line in text.splitlines():
		line = raw_line.strip()
		if not line or line.startswith(";"):
			continue
		if line.startswith("[") and line.endswith("]"):
			section = line[1:-1]
			continue
		if section == "application":
			m = re.match(r"run/main_scene\s*=\s*\"(?P<path>[^\"]+)\"", line)
			if m:
				main_scene = m.group("path")
		elif section == "autoload":
			m = re.match(r"[^=]+\s*=\s*\"\*(?P<path>[^\"]+)\"", line)
			if m:
				autoloads.append(m.group("path"))
	return main_scene, autoloads


def parse_tscn_ext_resource_paths(scene_path: Path) -> list[str]:
	text = read_text(scene_path)
	paths: list[str] = []
	for m in re.finditer(r"\bpath=\"(?P<path>res://[^\"]+)\"", text):
		paths.append(m.group("path"))
	return paths


def audit() -> int:
	project_path = ROOT / "project.godot"
	if not project_path.exists():
		print(f"ERRO: não achei {project_path}")
		return 2

	missing: list[MissingRef] = []
	main_scene, autoloads = parse_project_godot(project_path)
	if main_scene:
		p = res_to_path(main_scene)
		if not p.exists():
			missing.append(MissingRef("project.godot:run/main_scene", main_scene, p))
	else:
		print("AVISO: run/main_scene não definido em project.godot")

	for a in autoloads:
		p = res_to_path(a)
		if not p.exists():
			missing.append(MissingRef("project.godot:[autoload]", a, p))

	for scene_path in ROOT.rglob("*.tscn"):
		for res_path in parse_tscn_ext_resource_paths(scene_path):
			p = res_to_path(res_path)
			if not p.exists():
				missing.append(MissingRef(str(scene_path.relative_to(ROOT)), res_path, p))

	if not missing:
		print("OK: não encontrei referências quebradas (arquivos faltando).")
		return 0

	print("Referências quebradas (arquivos faltando):")
	for item in missing:
		rel = item.resolved_path.relative_to(ROOT)
		print(f"- em {item.source}: {item.ref} -> {rel}")
	return 1


if __name__ == "__main__":
	raise SystemExit(audit())

