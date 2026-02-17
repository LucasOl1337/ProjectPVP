from __future__ import annotations

import argparse
import json

from pixellab_pipeline import McpClient, _load_pixellab_auth


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tool", required=True)
    args = parser.parse_args()

    url, auth = _load_pixellab_auth()
    client = McpClient(url, auth)
    tools = client.tools_list()
    for t in tools:
        if t.get("name") == args.tool:
            schema = t.get("inputSchema") or {}
            props = (schema.get("properties") or {})
            print(f"tool={args.tool}")
            print(f"fields={len(props)}")
            for k in sorted(props.keys()):
                print(k)
            print("\nraw:")
            print(json.dumps(t, indent=2, ensure_ascii=False))
            return

    raise SystemExit(f"Tool não encontrada: {args.tool}")


if __name__ == "__main__":
    main()

