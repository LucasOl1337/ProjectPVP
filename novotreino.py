import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def resolve_python_exe(root: Path) -> str:
    venv_py = root / ".venv" / "Scripts" / "python.exe"
    if venv_py.exists():
        return str(venv_py)
    return sys.executable


def check_ppo_dependencies(python_exe: str) -> Optional[str]:
    cmd = [
        python_exe,
        "-c",
        "import torch, gymnasium, stable_baselines3, tensorboard, tqdm, rich; print('ok')",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except Exception as exc:
        return str(exc)
    if proc.returncode == 0:
        return None
    msg = (proc.stderr or proc.stdout or "deps faltando").strip()
    return msg.splitlines()[-1] if msg else "deps faltando"


def repo_root() -> Path:
    return Path(__file__).resolve().parent


def config_path(root: Path) -> Path:
    return root / "BOTS" / "IA" / "config" / "novotreino.json"


def load_config(root: Path) -> Dict:
    path = config_path(root)
    base = {
        "godot_exe": "",
        "port": 20001,
        "time_scale": 8.0,
        "intents": 5,
        "intent_horizon": 15,
        "total_timesteps": 2_000_000,
        "bot_name": "bot",
        "opponent_policy": "handmade",
        "opponent_profile": "handmade",
    }
    data = read_json(path)
    if not isinstance(data, dict):
        data = {}
    base.update(data)
    return base


def save_config(root: Path, cfg: Dict) -> None:
    path = config_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


def normalize_profile_name(name: str) -> str:
    return "".join(ch for ch in name.strip().lower() if ch.isalnum() or ch in ("-", "_"))


def list_handmade_profiles(root: Path) -> List[str]:
    bots_dir = root / "BOTS" / "profiles"
    if not bots_dir.exists():
        return []
    names: List[str] = []
    for child in bots_dir.iterdir():
        if not child.is_dir():
            continue
        if child.name.startswith("."):
            continue
        if (child / "handmade.json").exists():
            names.append(child.name)
    names.sort()
    return names


def create_handmade_bot(root: Path, bot_name: str, template_profile: str = "handmade") -> Path:
    bot = normalize_profile_name(bot_name)
    if not bot:
        raise RuntimeError("Nome inválido")
    src = root / "BOTS" / "profiles" / template_profile / "handmade.json"
    if not src.exists():
        raise RuntimeError(f"Template não encontrado: {src}")
    dst_dir = root / "BOTS" / "profiles" / bot
    dst = dst_dir / "handmade.json"
    if dst.exists():
        raise RuntimeError(f"Já existe: {dst}")
    dst_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    return dst


def read_json(path: Path) -> Dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def resolve_godot_exe(root: Path) -> str:
    cfg = load_config(root)
    cfg_godot = str(cfg.get("godot_exe", "")).strip()
    if cfg_godot:
        return cfg_godot
    env = os.environ.get("GODOT_EXE", "").strip()
    if env:
        return env
    cfg = root / "BOTS" / "legal" / "islands.json"
    payload = read_json(cfg)
    godot = str(payload.get("godot_exe", "")).strip()
    return godot


def prompt_choice(title: str, options: List[str], default_index: int = 0) -> int:
    print("\n" + title)
    for i, opt in enumerate(options, start=1):
        suffix = " (default)" if i - 1 == default_index else ""
        print(f"{i}) {opt}{suffix}")
    while True:
        raw = input("> ").strip()
        if raw == "" and 0 <= default_index < len(options):
            return default_index
        if raw.isdigit():
            idx = int(raw) - 1
            if 0 <= idx < len(options):
                return idx
        print("Opção inválida")


def prompt_int(label: str, default: int) -> int:
    while True:
        raw = input(f"{label} (enter = {default}): ").strip()
        if raw == "":
            return int(default)
        if raw.isdigit() or (raw.startswith("-") and raw[1:].isdigit()):
            return int(raw)
        print("Número inválido")


def prompt_float(label: str, default: float) -> float:
    while True:
        raw = input(f"{label} (enter = {default}): ").strip().replace(",", ".")
        if raw == "":
            return float(default)
        try:
            return float(raw)
        except Exception:
            print("Número inválido")


@dataclass
class Session:
    godot_proc: Optional[subprocess.Popen] = None
    ppo_proc: Optional[subprocess.Popen] = None
    last_port: int = 20001
    last_time_scale: float = 8.0
    last_intents: int = 5
    last_intent_horizon: int = 15
    last_opponent_policy: str = "handmade"
    last_opponent_profile: str = "handmade"
    last_total_timesteps: int = 2_000_000


def is_running(proc: Optional[subprocess.Popen]) -> bool:
    return proc is not None and proc.poll() is None


def stop_process(proc: Optional[subprocess.Popen], label: str) -> None:
    if proc is None:
        return
    if proc.poll() is not None:
        return
    try:
        proc.terminate()
    except Exception:
        return
    for _ in range(40):
        if proc.poll() is not None:
            return
        time.sleep(0.05)
    try:
        proc.kill()
    except Exception:
        pass


def launch_godot(root: Path, godot_exe: str, port: int, time_scale: float, watch: bool) -> subprocess.Popen:
    if not godot_exe:
        raise RuntimeError("Godot não encontrado. Defina GODOT_EXE ou configure BOTS/legal/islands.json")
    watch_flag = "--watch" if watch else "--no-watch"
    cmd = [
        godot_exe,
        "--headless",
        "--fixed-fps",
        "60",
        "--path",
        str(root),
        "--scene",
        "res://engine/scenes/Main.tscn",
        "--",
        "--training",
        f"--port={int(port)}",
        watch_flag,
        f"--time-scale={float(time_scale)}",
        "--max-steps=0",
        "--max-seconds=0.0",
        "--max-kills=0",
        "--quit-idle=30",
        "--match-mode",
    ]
    return subprocess.Popen(cmd, cwd=str(root))


def wait_for_port(host: str, port: int, timeout_sec: float = 15.0) -> bool:
    deadline = time.time() + float(timeout_sec)
    while time.time() < deadline:
        try:
            sock = socket.create_connection((host, int(port)), timeout=0.2)
            sock.close()
            return True
        except OSError:
            time.sleep(0.1)
    return False


def run_smoketest(root: Path, port: int, time_scale: float, opponent_policy: str, opponent_profile: str) -> int:
    cmd = [
        sys.executable,
        "-m",
        "tools.rl_smoketest",
        "--host",
        "127.0.0.1",
        "--port",
        str(int(port)),
        "--time-scale",
        str(float(time_scale)),
        "--opponent-policy",
        str(opponent_policy),
        "--opponent-profile",
        str(opponent_profile),
        "--steps",
        "300",
    ]
    return subprocess.call(cmd, cwd=str(root))


def launch_ppo(
    root: Path,
    python_exe: str,
    port: int,
    time_scale: float,
    intents: int,
    intent_horizon: int,
    opponent_policy: str,
    opponent_profile: str,
    total_timesteps: int,
    save_dir: Path,
) -> subprocess.Popen:
    cmd = [
        python_exe,
        "-m",
        "tools.train_rl_ppo",
        "--host",
        "127.0.0.1",
        "--port",
        str(int(port)),
        "--time-scale",
        str(float(time_scale)),
        "--intents",
        str(int(intents)),
        "--intent-horizon",
        str(int(intent_horizon)),
        "--opponent-policy",
        str(opponent_policy),
        "--opponent-profile",
        str(opponent_profile),
        "--total-timesteps",
        str(int(total_timesteps)),
        "--save-dir",
        str(save_dir),
    ]
    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    return subprocess.Popen(cmd, cwd=str(root), env=env)


def interactive_menu() -> int:
    root = repo_root()
    session = Session()
    cfg = load_config(root)
    python_exe = resolve_python_exe(root)
    try:
        session.last_port = int(cfg.get("port", session.last_port))
        session.last_time_scale = float(cfg.get("time_scale", session.last_time_scale))
        session.last_intents = int(cfg.get("intents", session.last_intents))
        session.last_intent_horizon = int(cfg.get("intent_horizon", session.last_intent_horizon))
        session.last_total_timesteps = int(cfg.get("total_timesteps", session.last_total_timesteps))
        session.last_opponent_policy = str(cfg.get("opponent_policy", session.last_opponent_policy))
        session.last_opponent_profile = str(cfg.get("opponent_profile", session.last_opponent_profile))
    except Exception:
        pass
    godot_exe = resolve_godot_exe(root)
    profiles = list_handmade_profiles(root)
    if "handmade" not in profiles and (root / "BOTS" / "handmade" / "handmade.json").exists():
        profiles = ["handmade"] + profiles

    default_profile = "handmade" if "handmade" in profiles else (profiles[0] if profiles else "handmade")
    session.last_opponent_profile = default_profile

    print("\n=== Novo Treino (RL PPO hierárquico) ===")

    while True:
        godot_state = "ON" if is_running(session.godot_proc) else "OFF"
        ppo_state = "ON" if is_running(session.ppo_proc) else "OFF"
        deps_missing = check_ppo_dependencies(python_exe)
        deps_state = "OK" if deps_missing is None else "MISSING"
        print("\n--- Status ---")
        print(f"Godot: {godot_state} | Treino PPO: {ppo_state} | deps: {deps_state}")
        print(
            "Config: port=%d time_scale=%.2f intents=%d horizon=%d opponent=%s/%s"
            % (
                session.last_port,
                session.last_time_scale,
                session.last_intents,
                session.last_intent_horizon,
                session.last_opponent_policy,
                session.last_opponent_profile,
            )
        )
        print("\n1) Ligar Godot")
        print("2) Criar novo bot")
        print("3) Treinar bot")
        print("0) Sair")
        choice = input("> ").strip()

        if choice == "0":
            stop_process(session.ppo_proc, "PPO")
            stop_process(session.godot_proc, "Godot")
            return 0

        if choice == "1":
            if is_running(session.godot_proc):
                print("Godot já está rodando")
                continue
            watch = False
            session.godot_proc = launch_godot(
                root, godot_exe, session.last_port, session.last_time_scale, watch=watch
            )
            time.sleep(0.4)
            print(f"Godot iniciado (pid={session.godot_proc.pid})")
            continue

        if choice == "2":
            if not profiles:
                profiles = list_handmade_profiles(root)
            template = default_profile
            if profiles:
                idx = prompt_choice("Template para novo bot", profiles, profiles.index(template) if template in profiles else 0)
                template = profiles[idx]
            name_raw = input("Nome do novo bot: ").strip()
            try:
                created = create_handmade_bot(root, name_raw, template_profile=template)
                profiles = list_handmade_profiles(root)
                print(f"Criado: {created}")
            except Exception as exc:
                print(f"Erro: {exc}")
            continue

        if choice == "3":
            deps_missing = check_ppo_dependencies(python_exe)
            if deps_missing is not None:
                print(
                    "Dependência ausente: %s\n"
                    "Tentando instalar automaticamente com:\n"
                    "  %s -m pip install -r IA/requirements_ppo.txt\n" % (deps_missing, python_exe)
                )
                try:
                    subprocess.check_call([python_exe, "-m", "pip", "install", "-r", "IA/requirements_ppo.txt"], cwd=str(root))
                except Exception as exc:
                    print(f"Falha ao instalar deps: {exc}")
                    continue
                deps_missing = check_ppo_dependencies(python_exe)
                if deps_missing is not None:
                    print(
                        "Ainda faltam dependências após instalar: %s\n"
                        "Tente manualmente: %s -m pip install -r IA/requirements_ppo.txt" % (deps_missing, python_exe)
                    )
                    continue
            if not profiles:
                profiles = list_handmade_profiles(root)
            cfg = load_config(root)
            bot_name_norm = normalize_profile_name(str(cfg.get("bot_name", "bot"))) or "bot"
            session.last_port = int(cfg.get("port", session.last_port))
            session.last_time_scale = float(cfg.get("time_scale", session.last_time_scale))
            session.last_intents = max(2, int(cfg.get("intents", session.last_intents)))
            session.last_intent_horizon = max(1, int(cfg.get("intent_horizon", session.last_intent_horizon)))
            session.last_total_timesteps = max(10_000, int(cfg.get("total_timesteps", session.last_total_timesteps)))
            session.last_opponent_policy = str(cfg.get("opponent_policy", session.last_opponent_policy))
            session.last_opponent_profile = str(cfg.get("opponent_profile", session.last_opponent_profile))
            if session.last_opponent_policy == "handmade" and profiles and session.last_opponent_profile not in profiles:
                session.last_opponent_profile = profiles[0]

            if not is_running(session.godot_proc):
                session.godot_proc = launch_godot(root, godot_exe, session.last_port, session.last_time_scale, watch=False)
                if not wait_for_port("127.0.0.1", int(session.last_port), timeout_sec=15.0):
                    print("Godot ainda não abriu a porta do treino. Tentando continuar mesmo assim...")
                print(f"Godot iniciado (pid={session.godot_proc.pid})")

            if is_running(session.ppo_proc):
                stop_process(session.ppo_proc, "PPO")
                session.ppo_proc = None

            save_dir = root / "IA" / "weights" / "rl" / bot_name_norm
            save_dir.mkdir(parents=True, exist_ok=True)
            session.ppo_proc = launch_ppo(
                root,
                python_exe,
                session.last_port,
                session.last_time_scale,
                session.last_intents,
                session.last_intent_horizon,
                session.last_opponent_policy,
                session.last_opponent_profile,
                session.last_total_timesteps,
                save_dir=save_dir,
            )
            print(f"Treino iniciado (pid={session.ppo_proc.pid}) | save_dir={save_dir}")
            continue

        print("Opção inválida")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(prog="novotreino.py")
    parser.add_argument("--auto-train", action="store_true", help="Executa um treino PPO e sai")
    parser.add_argument("--smoke-timesteps", type=int, default=4096, help="Timesteps para --auto-train")
    args = parser.parse_args()

    if not args.auto_train:
        raise SystemExit(interactive_menu())

    root = repo_root()
    cfg = load_config(root)
    godot_exe = resolve_godot_exe(root)
    python_exe = resolve_python_exe(root)

    deps_missing = check_ppo_dependencies(python_exe)
    if deps_missing is not None:
        print(
            "Dependência ausente: %s\n"
            "Instalando automaticamente com:\n"
            "  %s -m pip install -r IA/requirements_ppo.txt\n" % (deps_missing, python_exe)
        )
        subprocess.check_call([python_exe, "-m", "pip", "install", "-r", "IA/requirements_ppo.txt"], cwd=str(root))

    port = int(cfg.get("port", 20001))
    time_scale = float(cfg.get("time_scale", 8.0))
    intents = int(cfg.get("intents", 5))
    horizon = int(cfg.get("intent_horizon", 15))
    opponent_policy = str(cfg.get("opponent_policy", "handmade"))
    opponent_profile = str(cfg.get("opponent_profile", "handmade"))

    godot_proc = launch_godot(root, godot_exe, port, time_scale, watch=False)
    try:
        if not wait_for_port("127.0.0.1", port, timeout_sec=20.0):
            raise SystemExit("Godot não abriu a porta do treino a tempo")

        save_dir = root / "IA" / "weights" / "rl" / "_auto"
        save_dir.mkdir(parents=True, exist_ok=True)

        cmd = [
            python_exe,
            "-m",
            "tools.train_rl_ppo",
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
            "--time-scale",
            str(time_scale),
            "--intents",
            str(intents),
            "--intent-horizon",
            str(horizon),
            "--opponent-policy",
            opponent_policy,
            "--opponent-profile",
            opponent_profile,
            "--total-timesteps",
            str(int(args.smoke_timesteps)),
            "--save-dir",
            str(save_dir),
        ]
        print("Executando:", " ".join(cmd))
        subprocess.check_call(cmd, cwd=str(root))
        return_code = 0
    finally:
        stop_process(godot_proc, "Godot")
    raise SystemExit(return_code)
