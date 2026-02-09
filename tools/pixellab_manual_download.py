from __future__ import annotations

import argparse
import json
import os
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

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
    # Fallback env var se necessario
    return "", ""

def _download(url: str, out_path: Path, auth_header: str) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, method="GET")
    # PixelLab download endpoint might need auth, usually it does not for signed urls but 
    # here we are constructing the URL manually so we might need headers if the endpoint expects them.
    # The original script didn't add headers to download, let's try without first or add if needed.
    # Actually, looking at previous script, it didn't use headers for download.
    
    # However, if the API requires auth for the download endpoint (which is likely if it's user specific),
    # we should add it.
    if auth_header:
        req.add_header("Authorization", auth_header)
        
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = resp.read()
            out_path.write_bytes(data)
            print(f"Downloaded {len(data)} bytes to {out_path}")
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code}: {e.read().decode('utf-8', errors='replace')}")
        raise

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--uuid", required=True, help="PixelLab Character UUID")
    parser.add_argument("--name", required=True, help="Local folder name (e.g. nyx_ranger)")
    args = parser.parse_args()

    url, auth = _load_pixellab_auth()
    if not url:
        print("Could not load PixelLab auth config")
        return

    # Construct download URL
    # Based on: https://api.pixellab.ai/mcp/characters/{created_id}/download
    # Note: url variable from config is usually the base endpoint for MCP, e.g. https://api.pixellab.ai/mcp
    # We should ensure we don't double slash if url ends with /
    base_url = url.rstrip("/")
    download_url = f"{base_url}/characters/{args.uuid}/download"
    
    print(f"Downloading from: {download_url}")
    
    zip_out = Path("temp") / "pixellab" / f"{args.name}.zip"
    
    _download(download_url, zip_out, auth)
    
    if not zip_out.exists() or zip_out.stat().st_size < 1000:
        print("Error: Downloaded file is too small or does not exist.")
        return

    print("Running import script...")
    cmd = [
        "python",
        "tools/pixellab_import.py",
        str(zip_out),
        "--name",
        args.name,
        "--variant",
        "pixellab",
        "--force",
    ]
    subprocess.check_call(cmd)
    print(f"Successfully imported to assets/characters/{args.name}")

if __name__ == "__main__":
    main()
