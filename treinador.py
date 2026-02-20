import os
import sys
import subprocess
import json
from pathlib import Path
import shutil

GA_LAUNCHER = "ga_launcher.py"
PYTHON_CMD = sys.executable
DEFAULT_OPPONENT_POLICY = "handmade"

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def pause():
    input("\nPressione Enter para continuar...")

def _read_json(path: Path) -> dict:
    try:
        if not path.exists():
            return {}
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}

def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

def _resolve_godot_exe() -> str:
    desktop = Path.home() / "Desktop"
    candidates = [
        desktop / "Godot_v4.6-stable_win64.exe" / "Godot_v4.6-stable_win64.exe",
        desktop / "Godot_v4.6-stable_win64.exe",
    ]
    for c in candidates:
        if c.exists() and c.is_file():
            return str(c)
        if c.exists() and c.is_dir():
            same = c / c.name
            if same.exists() and same.is_file():
                return str(same)
            exes = sorted([p for p in c.glob("*.exe") if p.is_file()])
            if exes:
                return str(exes[0])
    for p in sorted(desktop.glob("Godot_v*-stable*_win64*.exe")):
        if p.exists() and p.is_file():
            return str(p)
        if p.exists() and p.is_dir():
            same = p / p.name
            if same.exists() and same.is_file():
                return str(same)
            exes = sorted([x for x in p.glob("*.exe") if x.is_file()])
            if exes:
                return str(exes[0])
    return ""

def _ensure_profile_ready(bot: str, prefer_params_trainer: bool = True) -> None:
    profile_dir = Path("BOTS") / "profiles" / bot
    islands_path = profile_dir / "islands.json"

    needs_sync = not islands_path.exists()
    if not needs_sync:
        cfg = _read_json(islands_path)
        if not isinstance(cfg, dict) or not cfg:
            needs_sync = True

    if needs_sync:
        args = ["sync", bot]
        if prefer_params_trainer:
            args.append("--params-trainer")
            args.append(f"--opponent-policy={DEFAULT_OPPONENT_POLICY}")
        run_launcher(args)

    cfg = _read_json(islands_path)
    if isinstance(cfg, dict):
        rounds_val = int(cfg.get("rounds", 0) or 0)
        if rounds_val > 0:
            last_summary_path = profile_dir / "state" / "last_summary.json"
            last_summary = _read_json(last_summary_path)
            if isinstance(last_summary, dict):
                try:
                    last_round = int(last_summary.get("round", 0) or 0)
                except Exception:
                    last_round = 0
                if last_round >= rounds_val:
                    cfg["rounds"] = 0
        if not bool(cfg.get("live_round_logs", False)):
            cfg["live_round_logs"] = True
        if not bool(cfg.get("trainer_live_rounds", False)):
            cfg["trainer_live_rounds"] = True
        if not bool(cfg.get("trainer_pretty_md9", False)):
            cfg["trainer_pretty_md9"] = True
        if not str(cfg.get("godot_exe", "")).strip():
            exe = _resolve_godot_exe()
            if exe:
                cfg["godot_exe"] = exe.replace("\\", "/")
        _write_json(islands_path, cfg)

def run_launcher(args):
    cmd = [PYTHON_CMD, GA_LAUNCHER] + args
    env = os.environ.copy()
    godot_exe = _resolve_godot_exe()
    if godot_exe:
        env.setdefault("GODOT_EXE", godot_exe)
    return subprocess.call(cmd, env=env)

def get_bots():
    bots_dir = Path("BOTS")
    if not bots_dir.exists():
        return []
    return sorted([p.stem for p in bots_dir.glob("*.json")])

def select_bot():
    bots = get_bots()
    if not bots:
        print("Nenhum bot encontrado!")
        return None
    
    print("\n--- Selecione um Bot ---")
    for i, bot in enumerate(bots):
        print(f"{i+1}. {bot}")
    print("0. Cancelar")
    
    choice = input("Escolha: ").strip()
    if not choice.isdigit():
        return None
    idx = int(choice) - 1
    if 0 <= idx < len(bots):
        return bots[idx]
    return None

def menu_create_bot():
    print("\n--- Criar Novo Bot ---")
    name = input("Nome do novo bot: ").strip()
    if not name: return
    
    print("Template (default):")
    template = input("Nome do template [Enter para default]: ").strip() or "default"
    
    run_launcher(["init", name, "--template", template])
    pause()

def menu_sync_bot():
    bot = select_bot()
    if not bot: return
    
    print(f"\n--- Sincronizando {bot} ---")
    print("Usar Trainer Paramétrico (GA v1)? [S/n]")
    use_params = input("Opção: ").strip().lower() != "n"
    
    cmd = ["sync", bot]
    if use_params:
        cmd.append("--params-trainer")
        cmd.append("--opponent-policy=handmade")
    
    run_launcher(cmd)
    pause()

def menu_train_bot():
    bot = select_bot()
    if not bot: return
    
    print(f"\n--- Treinando {bot} (Headless) ---")
    print("Para parar, pressione Ctrl+C.")
    try:
        _ensure_profile_ready(bot, prefer_params_trainer=True)
        run_launcher(["run", bot])
    except KeyboardInterrupt:
        print("\nTreino interrompido pelo usuário.")
    pause()

def menu_watch_bot():
    bot = select_bot()
    if not bot: return
    
    print(f"\n--- Assistir Partida: {bot} ---")
    print("Iniciando modo 'Watch' (Treino com GUI e velocidade 1.0)...")
    print("Para bots 'external' (GA Paramétrico), isso rodará o trainer em paralelo.")
    print("Para bots 'native', o trainer ficará ocioso (ignorar).")
    try:
        _ensure_profile_ready(bot, prefer_params_trainer=True)
        run_launcher(["run", bot, "--watch"])
    except KeyboardInterrupt:
        print("\nVisualização interrompida.")
    pause()

def menu_train_bot_vs_bot():
    bot = select_bot()
    if not bot:
        return
    print("\n--- Selecione o Oponente ---")
    opp = select_bot()
    if not opp:
        return
    if opp == bot:
        print("Oponente não pode ser o mesmo bot.")
        pause()
        return

    print(f"\n--- Treinando {bot} vs {opp} (Headless) ---")
    print("Para parar, pressione Ctrl+C.")
    try:
        run_launcher(
            [
                "sync",
                bot,
                "--params-trainer",
                f"--opponent-bot={opp}",
                "--opponent-policy=ga_params",
            ]
        )
        _ensure_profile_ready(bot, prefer_params_trainer=True)
        run_launcher(["run", bot])
    except KeyboardInterrupt:
        print("\nTreino interrompido pelo usuário.")
    pause()

def main():
    should_clear = True
    while True:
        if should_clear:
            clear_screen()
        should_clear = True
        print("========================================")
        print("        TREINADOR PROJETO PVP           ")
        print("========================================")
        print("1. [List] Listar Perfis de Bots")
        print("2. [Init] Criar Novo Perfil")
        print("3. [Sync] Sincronizar/Configurar Perfil")
        print("4. [Run ] Treinar Bot (Headless)")
        print("5. [View] Assistir Partida (GUI)")
        print("6. [Duel] Treinar Bot vs Bot (Headless)")
        print("----------------------------------------")
        print("0. Sair")
        print("========================================")
        
        opt = input("Opção: ").strip()
        
        if opt == "0":
            print("Saindo...")
            break
        elif opt == "1":
            bots = get_bots()
            print("\nBots encontrados:")
            for b in bots: print(f" - {b}")
            pause()
        elif opt == "2":
            menu_create_bot()
        elif opt == "3":
            menu_sync_bot()
        elif opt == "4":
            menu_train_bot()
            should_clear = False
        elif opt == "5":
            menu_watch_bot()
            should_clear = False
        elif opt == "6":
            menu_train_bot_vs_bot()
            should_clear = False
        else:
            print("Opção inválida!")
            pause()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nSaindo...")
