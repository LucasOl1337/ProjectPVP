from __future__ import annotations

import argparse
import json
from pathlib import Path

from gerador.mcp_client import McpClient, load_trae_pixellab_config


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--character-id", required=True)
    ap.add_argument("--preset", required=True)
    args = ap.parse_args()

    preset_path = Path(args.preset)
    data = json.loads(preset_path.read_text(encoding="utf-8"))
    animations = data.get("animations") or []
    if not isinstance(animations, list) or not animations:
        raise SystemExit("Preset inválido: animations vazio")

    url, auth = load_trae_pixellab_config()
    client = McpClient(url=url, authorization=auth)
    client.initialize()

    character_id = str(args.character_id).strip()
    for job in animations:
        name = str(job.get("animation_name") or "").strip()
        template_id = str(job.get("template_animation_id") or "").strip()
        desc = str(job.get("action_description") or "").strip()
        if not name or not template_id:
            continue
        res = client.tools_call(
            "animate_character",
            {
                "character_id": character_id,
                "template_animation_id": template_id,
                "action_description": desc,
                "animation_name": name,
            },
        )
        print(f"queued={name} result={bool(res)}", flush=True)


if __name__ == "__main__":
    main()

