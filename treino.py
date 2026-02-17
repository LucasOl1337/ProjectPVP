import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict


def repo_root() -> Path:
    return Path(__file__).resolve().parent


def read_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def bot_name_from_argv(argv) -> str:
    for item in argv[1:]:
        if item.startswith("--") and len(item) > 2 and item not in ("--bot", "--profile", "--help", "-h"):
            return item[2:]
    return ""


def normalize_bot_name(name: str) -> str:
    safe = "".join(ch for ch in name.strip().lower() if ch.isalnum() or ch in ("-", "_"))
    return safe


def build_bot_paths(root: Path, bot: str) -> Dict[str, Path]:
    base = root / "BOTS" / "profiles" / bot
    return {
        "base": base,
        "profile": root / "BOTS" / f"{bot}.json",
        "rewards": base / "rewards.json",
        "bot_p1": base / "bot_p1.json",
        "bot_p2": base / "bot_p2.json",
        "seed": base / "seed_genome.json",
        "state": base / "state",
        "best": base / "best_genome.json",
        "current": base / "current_bot.json",
        "islands_cfg": base / "islands.json",
        "log": base / "logs" / "genetic_log.csv",
    }


def list_profiles(root: Path) -> Dict[str, Path]:
    bots_dir = root / "BOTS"
    if not bots_dir.exists():
        return {}
    result: Dict[str, Path] = {}
    for path in bots_dir.glob("*.json"):
        name = normalize_bot_name(path.stem)
        if name:
            result[name] = path
    return dict(sorted(result.items(), key=lambda kv: kv[0]))


def prompt_choice(title: str, options: list[str], default_index: int = 0) -> int:
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


def prompt_text(label: str, default: str = "") -> str:
    while True:
        raw = input(f"{label}{' (' + default + ')' if default else ''}: ").strip()
        if raw == "" and default != "":
            return default
        if raw != "":
            return raw
        print("Valor inválido")


def prompt_float(label: str, default: float) -> float:
    while True:
        raw = input(f"{label} (enter = {default}): ").strip().replace(",", ".")
        if raw == "":
            return float(default)
        try:
            return float(raw)
        except Exception:
            print("Número inválido")


def build_matchup_config(
    root: Path,
    train_bot: str,
    opponent: str,
    no_sync: bool,
) -> Path:
    profile_path = root / "BOTS" / f"{train_bot}.json"
    profile = read_json(profile_path)
    if not profile:
        raise RuntimeError(f"Perfil não encontrado: {profile_path}")

    train_paths = build_bot_paths(root, train_bot)
    if (not no_sync) or (not train_paths["islands_cfg"].exists()):
        train_paths = write_profile_artifacts(root, train_bot, profile)

    cfg = read_json(train_paths["islands_cfg"])
    if not cfg:
        raise RuntimeError(f"Config islands inválida: {train_paths['islands_cfg']}")

    cfg = dict(cfg)

    cfg["match_rules_path"] = str(Path("BOTS") / "IA" / "config" / "match_rules.json").replace("\\", "/")
    cfg.pop("max_steps", None)
    cfg.pop("max_seconds", None)
    cfg.pop("max_kills", None)

    cfg["progress_path"] = str((root / "BOTS" / "profiles" / train_bot / "progress.json").resolve())
    cfg["league_dir"] = str((Path("BOTS") / "profiles" / train_bot / "league").as_posix())
    cfg["league_max"] = int(cfg.get("league_max", 64))

    if opponent == "baseline":
        cfg["opponent"] = "baseline"
        cfg.pop("opponent_load_path", None)
        cfg["opponent_tag"] = "baseline"
        matchup_dir = train_paths["base"] / "matchups" / "baseline"
    else:
        opp = normalize_bot_name(opponent)
        opp_best = root / "BOTS" / "profiles" / opp / "best_genome.json"
        if not opp_best.exists():
            raise RuntimeError(f"Oponente sem best_genome: {opp_best}")
        opp_tag = opp
        opp_meta = read_json(root / "BOTS" / "profiles" / opp / "current_bot.json")
        if opp_meta:
            if "individual" in opp_meta:
                try:
                    n = int(opp_meta.get("individual", 0))
                    g = int(opp_meta.get("generation_global", opp_meta.get("islands_round", opp_meta.get("round", 0))))
                    if g > 0 and n > 0:
                        opp_tag = f"{opp} (G{g}_N{n})"
                except Exception:
                    pass
            if opp_tag == opp:
                src = str(opp_meta.get("source_rel", opp_meta.get("source", "")))
                m = re.search(r"_G(\d+)_N(\d+)", src)
                if m:
                    opp_tag = f"{opp} (G{int(m.group(1))}_N{int(m.group(2))})"
        cfg["opponent_tag"] = opp_tag
        cfg["opponent"] = "best"
        cfg["opponent_load_path"] = str(opp_best)
        cfg["opponent_pool_dir"] = str((Path("BOTS") / "profiles" / opp / "league").as_posix())
        cfg["opponent_pool_max"] = int(cfg.get("opponent_pool_max", 8))
        cfg["opponent_pool_mode"] = str(cfg.get("opponent_pool_mode", "round_robin"))
        cfg["opponent_pool_include_best"] = True
        matchup_dir = train_paths["base"] / "matchups" / opp

    cfg["state_dir"] = str((matchup_dir / "state").relative_to(root)).replace("\\", "/")
    out_cfg = matchup_dir / "islands.json"
    write_json(out_cfg, cfg)
    return out_cfg


def interactive_menu(root: Path) -> int:
    profiles = list_profiles(root)
    if not profiles:
        print("Nenhum perfil encontrado em BOTS/*.json")
        return 2

    names = list(profiles.keys())
    default_idx = names.index("default") if "default" in profiles else 0

    while True:
        print("\n=== Treino (Perfis BOTS/profiles/) ===")
        print("Indivíduo global: N = (round-1)*workers + (worker_id+1)")
        print("Arquivos por indivíduo: BOTS/profiles/<perfil>/matchups/<oponente>/state/round_xxxx/individuals/")
        print("1) Treinar bot selecionado (P1 vs P2)")
        print("2) Treinar bot vs outro bot (alternando P1/P2)")
        print("3) Gerar novo bot")
        print("0) Sair")
        choice = input("> ").strip()
        if choice == "0":
            return 0
        if choice not in ("1", "2", "3"):
            print("Opção inválida")
            continue

        if choice == "3":
            template_name = "default" if "default" in profiles else names[0]
            template_profile = read_json(profiles.get(template_name, Path("")))
            create_bot_wizard(root, template_profile)
            profiles = list_profiles(root)
            names = list(profiles.keys())
            default_idx = names.index("default") if "default" in profiles else 0
            continue

        if choice == "1":
            p1_idx = prompt_choice("Selecione o bot a treinar (P1)", names, default_idx)
            train_bot = names[p1_idx]
            progress_path = root / "BOTS" / "profiles" / train_bot / "progress.json"
            progress = read_json(progress_path)
            if progress:
                try:
                    print(
                        "Progresso atual: próximo G=%d | próximo N começa em %d"
                        % [int(progress.get("next_generation", 1)), int(progress.get("next_individual", 0)) + 1]
                    )
                except Exception:
                    pass
            opp_options = ["baseline"] + [n for n in names if n != train_bot]
            opp_idx = prompt_choice("Selecione o oponente (P2)", opp_options, 0)
            opponent = opp_options[opp_idx]
            cfg_path = build_matchup_config(root, train_bot, opponent, no_sync=False)
            print(f"\nRodando: {cfg_path}")
            return run_islands(root, cfg_path)

        if choice == "2":
            p1_idx = prompt_choice("Escolha P1", names, default_idx)
            p2_idx = prompt_choice("Escolha P2", names, default_idx if default_idx != p1_idx else 0)
            p1 = names[p1_idx]
            p2 = names[p2_idx]
            if p1 == p2:
                print("P1 e P2 precisam ser perfis diferentes")
                continue
            raw_cycles = input("Quantos ciclos? (enter = 1) ").strip()
            cycles = 1
            if raw_cycles.isdigit():
                cycles = max(1, int(raw_cycles))
            for i in range(cycles):
                print(f"\n=== Ciclo {i+1}/{cycles}: treinando {p1} vs {p2} ===")
                cfg1 = build_matchup_config(root, p1, p2, no_sync=False)
                code = run_islands(root, cfg1)
                if code != 0:
                    return code
                print(f"\n=== Ciclo {i+1}/{cycles}: treinando {p2} vs {p1} ===")
                cfg2 = build_matchup_config(root, p2, p1, no_sync=False)
                code = run_islands(root, cfg2)
                if code != 0:
                    return code
            return 0


def ensure_seed(root: Path, seed_path: Path) -> None:
    if seed_path.exists():
        return
    generated = root / "BOTS" / "IA" / "weights" / "seed_genome.json"
    if not generated.exists():
        cmd = [sys.executable, str(root / "engine" / "tools" / "make_random_genome.py")]
        subprocess.check_call(cmd, cwd=str(root))
    seed_path.parent.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(generated.read_text(encoding="utf-8"), encoding="utf-8")


def create_bot_wizard(root: Path, template_profile: Dict[str, Any]) -> int:
    name_raw = prompt_text("Nome do novo bot (ex: defensivo)")
    bot = normalize_bot_name(name_raw)
    if not bot:
        print("Nome inválido")
        return 2
    profile_path = root / "BOTS" / f"{bot}.json"
    if profile_path.exists():
        print(f"Já existe: {profile_path}")
        return 3

    desc_default = f"Perfil criado via treino.py ({bot})."
    description = prompt_text("Descrição", desc_default)

    base_rewards: Dict[str, Any] = {}
    tpl_rewards = template_profile.get("rewards", {}) if isinstance(template_profile.get("rewards"), dict) else {}
    tpl_base = tpl_rewards.get("base", {}) if isinstance(tpl_rewards.get("base"), dict) else {}
    base_rewards["time_without_kill"] = prompt_float(
        "Reward: time_without_kill (punição por ficar sem matar)",
        float(tpl_base.get("time_without_kill", -0.1)),
    )
    base_rewards["kill"] = prompt_float("Reward: kill", float(tpl_base.get("kill", 10.0)))
    base_rewards["death"] = prompt_float("Reward: death", float(tpl_base.get("death", -5.0)))
    base_rewards["time_alive"] = prompt_float("Reward: time_alive", float(tpl_base.get("time_alive", 0.0)))

    new_profile: Dict[str, Any] = {
        "name": bot,
        "description": description,
        "rewards": {"base": base_rewards, "p1": {}, "p2": {}},
        "islands": dict(template_profile.get("islands", {})) if isinstance(template_profile.get("islands"), dict) else {},
    }

    write_json(profile_path, new_profile)
    paths = write_profile_artifacts(root, bot, new_profile)
    print(f"Criado: {profile_path}")
    print(f"Pasta: {paths['base']}")
    print(f"Config islands: {paths['islands_cfg']}")
    print(f"Seed: {paths['seed']}")
    return 0


def write_profile_artifacts(root: Path, bot: str, profile: Dict[str, Any]) -> Dict[str, Path]:
    paths = build_bot_paths(root, bot)
    rewards = profile.get("rewards", {}) if isinstance(profile.get("rewards"), dict) else {}
    base_rewards = rewards.get("base", {}) if isinstance(rewards.get("base"), dict) else {}
    p1_rewards = rewards.get("p1", {}) if isinstance(rewards.get("p1"), dict) else {}
    p2_rewards = rewards.get("p2", {}) if isinstance(rewards.get("p2"), dict) else {}

    write_json(paths["rewards"], {
        "time_without_kill": float(base_rewards.get("time_without_kill", -0.1)),
        "kill": float(base_rewards.get("kill", 10.0)),
        "death": float(base_rewards.get("death", -5.0)),
        "time_alive": float(base_rewards.get("time_alive", 0.0)),
    })
    write_json(paths["bot_p1"], {"name": bot, "reward": dict(p1_rewards)})
    write_json(paths["bot_p2"], {"name": bot, "reward": dict(p2_rewards)})
    ensure_seed(root, paths["seed"])
    if not paths["best"].exists():
        paths["best"].write_text(paths["seed"].read_text(encoding="utf-8"), encoding="utf-8")

    base_cfg = read_json(root / "BOTS" / "IA" / "config" / "islands_fresh.json")
    islands = profile.get("islands", {}) if isinstance(profile.get("islands"), dict) else {}
    cfg = dict(base_cfg)
    cfg.update(islands)

    cfg["match_rules_path"] = str(Path("BOTS") / "IA" / "config" / "match_rules.json").replace("\\", "/")
    cfg.pop("max_steps", None)
    cfg.pop("max_seconds", None)
    cfg.pop("max_kills", None)
    cfg["state_dir"] = str(paths["state"].relative_to(root)).replace("\\", "/")
    cfg["initial_seed"] = str(paths["best"].relative_to(root)).replace("\\", "/")
    cfg["promote_best_path"] = str(paths["best"].relative_to(root)).replace("\\", "/")
    cfg["promote_state_path"] = str(paths["current"].relative_to(root)).replace("\\", "/")
    cfg["progress_path"] = str((root / "BOTS" / "profiles" / bot / "progress.json").resolve())
    cfg["league_dir"] = str((Path("BOTS") / "profiles" / bot / "league").as_posix())
    cfg["league_max"] = int(cfg.get("league_max", 64))
    cfg["godot_user_args"] = [
        f"--rewards-path=res://BOTS/profiles/{bot}/rewards.json",
        f"--bot-config-p1=res://BOTS/profiles/{bot}/bot_p1.json",
        f"--bot-config-p2=res://BOTS/profiles/{bot}/bot_p2.json",
    ]
    write_json(paths["islands_cfg"], cfg)
    return paths


def run_islands(root: Path, cfg_path: Path) -> int:
    cmd = [sys.executable, str(root / "engine" / "tools" / "island_orchestrator.py"), "run", "--config", str(cfg_path)]
    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    return subprocess.call(cmd, cwd=str(root), env=env)


def main() -> int:
    implicit = bot_name_from_argv(sys.argv)

    if len(sys.argv) == 1:
        return interactive_menu(repo_root())

    parser = argparse.ArgumentParser(prog="treino.py")
    parser.add_argument("--bot", default=implicit, help="Nome do perfil (ex: agressivo)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--no-sync",
        action="store_true",
        help="Não sobrescreve BOTS/<bot>/*.json a partir do perfil; usa arquivos existentes.",
    )
    argv = sys.argv[1:]
    if implicit:
        argv = [a for a in argv if a != f"--{implicit}"]
    args = parser.parse_args(argv)

    bot = normalize_bot_name(str(args.bot))
    if not bot:
        print("Informe um perfil. Ex: python treino.py --agressivo")
        return 2

    root = repo_root()
    profile_path = root / "BOTS" / f"{bot}.json"
    profile = read_json(profile_path)
    if not profile:
        print(f"Perfil não encontrado: {profile_path}")
        return 3

    paths = build_bot_paths(root, bot)
    if not args.no_sync:
        paths = write_profile_artifacts(root, bot, profile)
    else:
        if not paths["islands_cfg"].exists():
            paths = write_profile_artifacts(root, bot, profile)
    print(f"Perfil: {bot}")
    print(f"Config islands: {paths['islands_cfg']}")
    print(f"Best: {paths['best']}")
    if args.dry_run:
        return 0
    return run_islands(root, paths["islands_cfg"])


if __name__ == "__main__":
    raise SystemExit(main())
