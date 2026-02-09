from __future__ import annotations

import argparse
import json
import os
import re
import urllib.request
import urllib.error
from pathlib import Path
from typing import Any

def _load_trae_pixellab_config() -> tuple[str, str] | None:
    appdata = os.environ.get("APPDATA")
    if not appdata:
        return None
    cfg_path = Path(appdata) / "Trae" / "User" / "mcp.json"
    if not cfg_path.exists():
        return None
    data = json.loads(cfg_path.read_text(encoding="utf-8"))
    server = (data.get("mcpServers") or {}).get("pixellab")
    if not isinstance(server, dict):
        return None
    url = str(server.get("url") or "").strip()
    headers = server.get("headers") or {}
    auth = str(headers.get("Authorization") or "").strip()
    if not url or not auth:
        return None
    return url, auth

class McpClient:
    def __init__(self, url: str, authorization: str) -> None:
        self.url = url
        self.authorization = authorization

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": self.authorization,
            "Content-Type": "application/json",
            "Accept": "application/json"
        }

    def _post(self, payload: dict[str, Any]) -> tuple[int, str]:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        req = urllib.request.Request(self.url, method="POST", headers=self._headers(), data=data)
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                return int(resp.status), resp.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace") if e.fp else ""
            return int(e.code), body

    def tools_call(self, name: str, arguments: dict[str, Any], call_id: int) -> dict[str, Any]:
        payload = {
            "jsonrpc": "2.0",
            "id": call_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        }
        status, body = self._post(payload)
        
        # Simple extraction for JSON-RPC response (assuming no SSE complexity for this simple client)
        # If the server returns SSE wrapped JSON, we might need to parse "data: "
        # But let's try direct parsing first as most MCP implementations might support standard JSON-RPC HTTP
        
        try:
            resp_json = json.loads(body)
            return resp_json.get("result", {})
        except:
            # Fallback to SSE parsing if needed
            for line in body.splitlines():
                if line.startswith("data:"):
                    try:
                        data = json.loads(line[5:])
                        if data.get("id") == call_id:
                            return data.get("result", {})
                    except:
                        pass
        return {}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uuid", required=True)
    args = parser.parse_args()

    url, auth = _load_trae_pixellab_config()
    if not url:
        print("Config not found")
        return

    client = McpClient(url, auth)
    
    # Initialize (required by protocol usually)
    client._post({
        "jsonrpc": "2.0", "id": 1, "method": "initialize", 
        "params": {"protocolVersion": "2024-11-05", "clientInfo": {"name": "add-anim", "version": "1.0"}, "capabilities": {}}
    })
    client._post({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

    animation_jobs = [
        # Skipping running as it exists
        {
            "animation_name": "dash",
            "template_animation_id": "running-slide",
            "action_description": "a super fast dash with a brief afterimage effect, body low and forward",
        },
        {
            "animation_name": "aiming",
            "template_animation_id": "fight-stance-idle-8-frames",
            "action_description": "aiming a glowing energy bow, steady stance, minimal movement",
        },
        {
            "animation_name": "jump",
            "template_animation_id": "two-footed-jump",
            "action_description": "quick jump with knees tucked slightly, keeping bow close",
        },
        {
            "animation_name": "melee",
            "template_animation_id": "lead-jab",
            "action_description": "a quick dagger slash with the offhand, sharp readable arc",
        },
        {
            "animation_name": "ult",
            "template_animation_id": "fireball",
            "action_description": "ultimate: charging and releasing a shockwave arrow burst",
        },
    ]

    print(f"Queueing animations for {args.uuid}...")
    
    for i, job in enumerate(animation_jobs):
        print(f"Queueing {job['animation_name']}...")
        try:
            res = client.tools_call(
                "animate_character",
                {
                    "character_id": args.uuid,
                    "template_animation_id": job["template_animation_id"],
                    "action_description": job["action_description"],
                    "animation_name": job["animation_name"],
                },
                100 + i
            )
            print(f"Result: {res}")
        except Exception as e:
            print(f"Error: {e}")

if __name__ == "__main__":
    main()
