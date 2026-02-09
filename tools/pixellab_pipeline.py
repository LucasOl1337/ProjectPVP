from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


UUID_RE = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")


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


def _load_pixellab_auth() -> tuple[str, str]:
    cfg = _load_trae_pixellab_config()
    if cfg:
        return cfg
    url = os.environ.get("PIXELLAB_MCP_URL", "https://api.pixellab.ai/mcp").strip()
    token = os.environ.get("PIXELLAB_TOKEN", "").strip()
    if not token:
        raise SystemExit(
            "PIXELLAB_TOKEN não definido e config do Trae não encontrada (APPDATA/Trae/User/mcp.json)."
        )
    return url, f"Bearer {token}"


def _parse_sse_messages(text: str) -> list[Any]:
    out: list[Any] = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[len("data:") :].strip()
        if not payload:
            continue
        try:
            parsed = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, list):
            out.extend(parsed)
        else:
            out.append(parsed)
    return out


def _extract_jsonrpc_messages(body: str) -> list[dict[str, Any]]:
    s = body.strip()
    if not s:
        return []
    if s.startswith("{") or s.startswith("["):
        try:
            parsed = json.loads(s)
        except json.JSONDecodeError:
            return []
        if isinstance(parsed, list):
            return [p for p in parsed if isinstance(p, dict)]
        if isinstance(parsed, dict):
            return [parsed]
        return []
    msgs = _parse_sse_messages(body)
    return [m for m in msgs if isinstance(m, dict)]


class McpClient:
    def __init__(self, url: str, authorization: str, protocol_version: str = "2025-03-26") -> None:
        self.url = url
        self.authorization = authorization
        self.protocol_version = protocol_version

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": self.authorization,
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
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

    def initialize(self) -> None:
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": self.protocol_version,
                "clientInfo": {"name": "project-pvp", "version": "1.0"},
                "capabilities": {"tools": {}, "resources": {}, "prompts": {}, "logging": {}},
            },
        }
        status, body = self._post(payload)
        if status < 200 or status >= 300:
            raise RuntimeError(f"initialize HTTP {status}: {body[:400]}")
        messages = _extract_jsonrpc_messages(body)
        if not any(m.get("id") == 1 and isinstance(m.get("result"), dict) for m in messages):
            raise RuntimeError(f"initialize sem result: {body[:400]}")
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

    def tools_list(self) -> list[dict[str, Any]]:
        status, body = self._post({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        if status < 200 or status >= 300:
            raise RuntimeError(f"tools/list HTTP {status}: {body[:400]}")
        messages = _extract_jsonrpc_messages(body)
        for m in messages:
            if m.get("id") == 2 and isinstance(m.get("result"), dict):
                tools = m["result"].get("tools")
                if isinstance(tools, list):
                    return [t for t in tools if isinstance(t, dict)]
        raise RuntimeError(f"tools/list sem tools: {body[:400]}")

    def tools_call(self, name: str, arguments: dict[str, Any], call_id: int) -> dict[str, Any]:
        payload = {
            "jsonrpc": "2.0",
            "id": call_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        }
        status, body = self._post(payload)
        if status < 200 or status >= 300:
            raise RuntimeError(f"tools/call {name} HTTP {status}: {body[:400]}")
        messages = _extract_jsonrpc_messages(body)
        for m in messages:
            if m.get("id") == call_id:
                if isinstance(m.get("result"), dict):
                    return m["result"]
                if m.get("error"):
                    raise RuntimeError(f"tools/call {name} error: {m['error']}")
        raise RuntimeError(f"tools/call {name} sem resposta id={call_id}: {body[:400]}")


def _result_text(result: dict[str, Any]) -> str:
    parts: list[str] = []
    content = result.get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text" and isinstance(item.get("text"), str):
                parts.append(item["text"])
    return "\n".join(parts).strip()


def _first_uuid(text: str) -> str:
    m = UUID_RE.search(text or "")
    return m.group(0) if m else ""


def _download(url: str, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=180) as resp:
        out_path.write_bytes(resp.read())


def _decode_b64(data: str, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(base64.b64decode(data))


def cmd_list_tools(client: McpClient) -> int:
    tools = client.tools_list()
    for t in tools:
        print(t.get("name"))
    return 0


def cmd_tool_schema(client: McpClient, tool_name: str) -> int:
    tools = client.tools_list()
    for t in tools:
        if t.get("name") == tool_name:
            print(json.dumps(t, indent=2, ensure_ascii=False))
            return 0
    print(f"Tool não encontrada: {tool_name}")
    return 2


def cmd_get_character(client: McpClient, character_id: str) -> int:
    res = client.tools_call("get_character", {"character_id": character_id}, 99)
    text = _result_text(res)
    print(text or json.dumps(res, indent=2, ensure_ascii=False))
    return 0


def _poll_character_ready(client: McpClient, character_id: str, timeout_s: int) -> dict[str, Any]:
    started = time.time()
    call_id = 300
    while True:
        res = client.tools_call("get_character", {"character_id": character_id}, call_id)
        call_id += 1
        text = _result_text(res)
        if "Status:" in text and "Processing" in text:
            pass

        needed = {"running", "dash", "aiming", "jump", "melee", "ult"}
        present = set()
        for line in text.splitlines():
            line = line.strip()
            if line.startswith("-") and "(" in line and "]" in line:
                continue
            if line.startswith("-"):
                name = line.lstrip("- ").strip()
                name = name.split("(", 1)[0].strip()
                if name:
                    present.add(name)
        if "**Animations:**" in text and "None yet" not in text and needed.issubset(present):
            return {"result": res, "text": text}
        if time.time() - started >= timeout_s:
            raise TimeoutError("Timeout esperando personagem ficar pronto")
        time.sleep(10)


def cmd_create_and_import(client: McpClient, char_id: str, name: str, description: str, timeout_s: int) -> int:
    create = client.tools_call(
        "create_character",
        {"description": description, "name": name, "n_directions": 8},
        10,
    )
    text = _result_text(create)
    created_id = _first_uuid(text)
    if not created_id:
        raise RuntimeError(f"create_character sem id: {create}")
    print(f"character_id={created_id}")

    animation_jobs = [
        {
            "animation_name": "running",
            "template_animation_id": "running-6-frames",
            "action_description": "running with a light cape flutter and bow carried at the side",
        },
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

    toolset = {t.get("name"): t for t in client.tools_list()}
    anim_schema = toolset.get("animate_character", {})
    enums = (((anim_schema.get("inputSchema") or {}).get("properties") or {}).get("template_animation_id") or {}).get(
        "description", ""
    )
    allowed = set()
    m = re.search(r"Available: `(.+)`$", str(enums))
    if m:
        allowed = set(x.strip() for x in m.group(1).split("`, `"))
    for idx, job in enumerate(animation_jobs):
        templ = job["template_animation_id"]
        if allowed and templ not in allowed:
            continue
        try:
            client.tools_call(
                "animate_character",
                {
                    "character_id": created_id,
                    "template_animation_id": templ,
                    "action_description": job["action_description"],
                    "animation_name": job["animation_name"],
                },
                20 + idx,
            )
            print(f"queued_animation={job['animation_name']} template={templ}")
        except Exception as e:
            print(f"queue_failed={job['animation_name']} template={templ} error={e}")

    preview = client.tools_call("get_character", {"character_id": created_id}, 150)
    preview_text = _result_text(preview)
    if preview_text:
        lines = preview_text.splitlines()
        print("status_preview_begin")
        for line in lines[:35]:
            print(line)
        print("status_preview_end")

    ready = _poll_character_ready(client, created_id, timeout_s=timeout_s)
    zip_url = f"https://api.pixellab.ai/mcp/characters/{created_id}/download"

    zip_out = Path("temp") / "pixellab" / f"{char_id}.zip"
    _download(zip_url, zip_out)
    if zip_out.stat().st_size < 1024:
        raise RuntimeError("ZIP baixado muito pequeno (provável erro HTTP 423 em JSON)")

    subprocess.check_call([
        "python",
        "tools/pixellab_import.py",
        str(zip_out),
        "--name",
        char_id,
        "--variant",
        "pixellab",
        "--force",
    ])
    print(f"imported=assets/characters/{char_id}/pixellab")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list-tools")
    sch = sub.add_parser("tool-schema")
    sch.add_argument("--tool", required=True)

    getc = sub.add_parser("get-character")
    getc.add_argument("--character-id", required=True)

    cc = sub.add_parser("create-import")
    cc.add_argument("--id", required=True)
    cc.add_argument("--name", required=True)
    cc.add_argument("--description", required=True)
    cc.add_argument("--timeout", type=int, default=1800)

    args = parser.parse_args()
    url, auth = _load_pixellab_auth()
    client = McpClient(url=url, authorization=auth)
    client.initialize()

    if args.cmd == "list-tools":
        raise SystemExit(cmd_list_tools(client))
    if args.cmd == "tool-schema":
        raise SystemExit(cmd_tool_schema(client, args.tool))
    if args.cmd == "get-character":
        raise SystemExit(cmd_get_character(client, args.character_id))
    if args.cmd == "create-import":
        raise SystemExit(cmd_create_and_import(client, args.id, args.name, args.description, args.timeout))


if __name__ == "__main__":
    main()
