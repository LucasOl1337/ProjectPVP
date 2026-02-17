from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def load_trae_pixellab_config() -> tuple[str, str]:
    appdata = os.environ.get("APPDATA")
    if not appdata:
        raise RuntimeError("APPDATA não encontrado")
    cfg_path = Path(appdata) / "Trae" / "User" / "mcp.json"
    if not cfg_path.exists():
        raise RuntimeError("mcp.json não encontrado")
    data = json.loads(cfg_path.read_text(encoding="utf-8"))
    server = (data.get("mcpServers") or {}).get("pixellab")
    if not isinstance(server, dict):
        raise RuntimeError("mcpServers.pixellab inválido")
    url = str(server.get("url") or "").strip()
    headers = server.get("headers") or {}
    auth = str(headers.get("Authorization") or "").strip()
    if not url or not auth:
        raise RuntimeError("url/auth não configurados para pixellab")
    return url, auth


class McpClient:
    def __init__(self, url: str, authorization: str) -> None:
        self.url = url
        self.authorization = authorization
        self._id = 1

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": self.authorization,
            "Content-Type": "application/json",
            "Accept": "application/json",
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

    def _next_id(self) -> int:
        self._id += 1
        return self._id

    def initialize(self) -> None:
        call_id = self._next_id()
        self._post(
            {
                "jsonrpc": "2.0",
                "id": call_id,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "clientInfo": {"name": "gerador", "version": "1.0"},
                    "capabilities": {},
                },
            }
        )
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

    def tools_call(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        call_id = self._next_id()
        payload = {
            "jsonrpc": "2.0",
            "id": call_id,
            "method": "engine/tools/call",
            "params": {"name": name, "arguments": arguments},
        }
        status, body = self._post(payload)
        if status >= 400:
            raise RuntimeError(f"HTTP {status}: {body[:500]}")
        try:
            resp = json.loads(body)
            if "error" in resp:
                raise RuntimeError(str(resp["error"]))
            return resp.get("result", {})
        except json.JSONDecodeError:
            for line in body.splitlines():
                if not line.startswith("data:"):
                    continue
                raw = line[5:].strip()
                if not raw:
                    continue
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if msg.get("id") == call_id:
                    if "error" in msg:
                        raise RuntimeError(str(msg["error"]))
                    return msg.get("result", {})
        return {}

