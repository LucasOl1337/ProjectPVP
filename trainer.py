import json
import os
import signal
import subprocess
import sys
import time
import shutil
from pathlib import Path
from typing import Dict, List


def read_json(path: Path) -> Dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def tail_lines(path: Path, limit: int = 12) -> List[str]:
    if not path.exists():
        return []
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        return lines[-limit:]
    except OSError:
        return []


def clear_screen() -> None:
    if os.name == "nt":
        os.system("cls")
    else:
        os.system("clear")


def find_default_config(project_root: Path) -> Path:
    primary = project_root / "IA" / "config" / "islands.json"
    if primary.exists():
        return primary
    fallback = project_root / "IA" / "config" / "islands_small.json"
    return fallback


def resolve_executable(value: str) -> str:
    if not value:
        return ""
    candidate = value.strip().strip('"')
    if Path(candidate).exists():
        return candidate
    found = shutil.which(candidate)
    return found or ""


def discover_godot_candidates() -> List[str]:
    candidates: List[Path] = []
    base_dirs: List[Path] = []
    for env_key in ("ProgramFiles", "ProgramFiles(x86)"):
        value = os.environ.get(env_key, "").strip()
        if value:
            base_dirs.append(Path(value))

    user_profile = os.environ.get("USERPROFILE", "").strip()
    if user_profile:
        base_dirs.append(Path(user_profile) / "Downloads")

    local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
    if local_app_data:
        base_dirs.append(Path(local_app_data))

        winget_packages = Path(local_app_data) / "Microsoft" / "WinGet" / "Packages"
        if winget_packages.exists():
            for pattern in ("Godot*_console.exe", "Godot*.exe"):
                try:
                    for exe in winget_packages.rglob(pattern):
                        if "godot" in exe.name.lower() and exe.suffix.lower() == ".exe":
                            candidates.append(exe)
                except OSError:
                    pass

    for base in base_dirs:
        if not base.exists():
            continue
        try:
            for entry in base.iterdir():
                name = entry.name.lower()
                if not entry.is_dir():
                    continue
                if "godot" not in name:
                    continue
                for exe in entry.glob("*.exe"):
                    if "godot" in exe.name.lower():
                        candidates.append(exe)
                for sub in entry.glob("*"):
                    if sub.is_dir() and "godot" in sub.name.lower():
                        for exe in sub.glob("*.exe"):
                            if "godot" in exe.name.lower():
                                candidates.append(exe)
        except OSError:
            continue

    filtered: List[Path] = []
    seen = set()
    for exe in candidates:
        key = str(exe).lower()
        if key in seen:
            continue
        seen.add(key)
        filtered.append(exe)

    def score(p: Path) -> float:
        name = p.name.lower()
        s = 0.0
        if "v4" in name:
            s += 10.0
        if "win64" in name:
            s += 5.0
        try:
            s += p.stat().st_mtime / 1e9
        except OSError:
            pass
        return s

    filtered.sort(key=score, reverse=True)
    return [str(p) for p in filtered[:10]]


def update_json(path: Path, patch: Dict) -> None:
    existing = read_json(path)
    merged = dict(existing)
    merged.update(patch)
    path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")


def ensure_python_deps(python_exe: str) -> None:
    try:
        import numpy  # noqa: F401
        return
    except Exception:
        pass

    try:
        subprocess.run(
            [str(python_exe), "-m", "pip", "install", "--quiet", "numpy"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return


def main() -> int:
    project_root = Path(__file__).resolve().parent
    cfg_env = os.environ.get("PVP_TRAINER_CONFIG", "").strip()
    cfg_path = Path(cfg_env) if cfg_env else find_default_config(project_root)
    if not cfg_path.is_absolute():
        cfg_path = (project_root / cfg_path).resolve()
    cfg = read_json(cfg_path)

    godot_exe_value = str(cfg.get("godot_exe", "godot4"))
    resolved_godot = resolve_executable(godot_exe_value)
    auto_candidates = discover_godot_candidates()
    if not resolved_godot and auto_candidates:
        resolved_godot = resolve_executable(auto_candidates[0])
        if resolved_godot:
            update_json(cfg_path, {"godot_exe": resolved_godot})
            cfg["godot_exe"] = resolved_godot

    while not resolved_godot:
        clear_screen()
        print("=== Project PVP | Trainer Dashboard ===")
        print(f"Config: {cfg_path}")
        print("")
        print("ERRO: Não encontrei o executável do Godot.")
        print(f"Config atual godot_exe = {godot_exe_value}")
        if auto_candidates:
            print("")
            print("Sugestões encontradas:")
            for i, p in enumerate(auto_candidates[:6], start=1):
                print(f"{i}) {p}")
        print("")
        print("Informe o caminho completo do Godot (ex.: C:\\Godot\\Godot_v4.x_win64.exe)")
        print("ou digite o número de uma sugestão acima.")
        value = input("godot_exe> ").strip()

        if value.isdigit() and auto_candidates:
            idx = int(value)
            if 1 <= idx <= len(auto_candidates):
                godot_exe_value = auto_candidates[idx - 1]
            else:
                godot_exe_value = value
        elif value:
            godot_exe_value = value
        elif auto_candidates:
            godot_exe_value = auto_candidates[0]
        else:
            godot_exe_value = "godot4"

        resolved_godot = resolve_executable(godot_exe_value)
        if resolved_godot:
            update_json(cfg_path, {"godot_exe": resolved_godot})
            cfg["godot_exe"] = resolved_godot

    state_dir_value = cfg.get("state_dir", "IA/weights/islands")
    state_dir = (project_root / state_dir_value).resolve() if not Path(state_dir_value).is_absolute() else Path(state_dir_value)
    status_path = state_dir / "status.json"
    summary_path = state_dir / "last_summary.json"
    log_path = state_dir / "orchestrator.log"

    python_exe = cfg.get("python_exe", "python")
    update_json(cfg_path, {"python_exe": str(python_exe)})

    ensure_python_deps(str(python_exe))

    orchestrator_cmd = [
        str(python_exe),
        str(project_root / "tools" / "island_orchestrator.py"),
        "run",
        "--config",
        str(cfg_path),
    ]
    if os.environ.get("PVP_DRY_RUN", "").strip() in ("1", "true", "yes"):
        orchestrator_cmd.append("--dry-run")

    state_dir.mkdir(parents=True, exist_ok=True)

    try:
        summary_path.write_text("{}", encoding="utf-8")
    except Exception:
        pass
    try:
        status_path.write_text("{}", encoding="utf-8")
    except Exception:
        pass
    try:
        log_path.write_text("", encoding="utf-8")
    except Exception:
        pass

    orch_out = open(state_dir / "orchestrator.stdout.log", "w", encoding="utf-8", errors="ignore")
    orch_err = open(state_dir / "orchestrator.stderr.log", "w", encoding="utf-8", errors="ignore")

    creationflags = 0
    if os.name == "nt":
        creationflags = subprocess.CREATE_NEW_PROCESS_GROUP

    popen_kwargs = {
        "cwd": str(project_root),
        "stdout": orch_out,
        "stderr": orch_err,
    }
    if creationflags:
        popen_kwargs["creationflags"] = creationflags

    proc = subprocess.Popen(orchestrator_cmd, **popen_kwargs)

    last_render = 0.0
    try:
        while True:
            exit_code = proc.poll()
            now = time.time()
            if now - last_render >= 0.25:
                clear_screen()
                status = read_json(status_path)
                summary = read_json(summary_path)
                logs = tail_lines(log_path, limit=12)
                err_tail = tail_lines(state_dir / "orchestrator.stderr.log", limit=8)

                print("=== Project PVP | Trainer Dashboard ===")
                print(f"Config: {cfg_path}")
                print(f"State:  {state_dir}")
                print(f"PID:    {proc.pid} | status: {'RUNNING' if exit_code is None else f'EXIT {exit_code}'}")
                print("")

                if status:
                    error_text = str(status.get("error", "") or "").strip()
                    if error_text:
                        print(f"ERRO: {error_text}")
                        print("")
                    print(
                        "Rodada {round} | done {completed}/{workers} | running {running} | best {best_so_far:.4f} | eta {eta_sec:.0f}s".format(
                            round=status.get("round", 0),
                            completed=status.get("completed", 0),
                            workers=status.get("workers", 0),
                            running=status.get("running", 0),
                            best_so_far=float(status.get("best_so_far", 0.0)),
                            eta_sec=float(status.get("eta_sec", 0.0)),
                        )
                    )
                    print(
                        "Concurr {concurrency} | queued {queued} | elapsed {elapsed_sec:.0f}s".format(
                            concurrency=status.get("concurrency", 0),
                            queued=status.get("queued", 0),
                            elapsed_sec=float(status.get("elapsed_sec", 0.0)),
                        )
                    )
                else:
                    print("Aguardando status... (primeiros segundos)")

                if summary:
                    print("")
                    print(f"Última rodada finalizada: {summary.get('round', 0)} | best {float(summary.get('best', 0.0)):.6f}")
                    top = summary.get("top", [])
                    if isinstance(top, list) and top:
                        print("Top seeds:")
                        for p in top[:10]:
                            print(f"- {p}")

                print("")
                print("Log:")
                if logs:
                    for line in logs:
                        print(line)
                else:
                    print("(sem logs ainda)")

                if err_tail:
                    print("\nOrquestrador (stderr):")
                    for line in err_tail:
                        print(line)

                print("\nCtrl+C para interromper.")
                last_render = now

            if exit_code is not None:
                try:
                    orch_out.close()
                except Exception:
                    pass
                try:
                    orch_err.close()
                except Exception:
                    pass
                return int(exit_code)
            time.sleep(0.05)

    except KeyboardInterrupt:
        try:
            if os.name == "nt":
                try:
                    subprocess.run(
                        ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                except Exception:
                    proc.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                proc.send_signal(signal.SIGINT)
        except Exception:
            try:
                proc.terminate()
            except OSError:
                pass
        try:
            orch_out.close()
        except Exception:
            pass
        try:
            orch_err.close()
        except Exception:
            pass
        try:
            return int(proc.wait(timeout=5))
        except Exception:
            return 130


if __name__ == "__main__":
    raise SystemExit(main())

