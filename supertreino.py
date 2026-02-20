import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict


SUPER_REWARD_PATH = "res://BOTS/IA/config/super_reward.json"
MATCH_RULES_PATH = "IA/config/match_rules_match.json"


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


def normalize_bot_name(name: str) -> str:
    return "".join(ch for ch in name.strip().lower() if ch.isalnum() or ch in ("-", "_"))


def build_bot_paths(root: Path, bot: str) -> Dict[str, Path]:
    base = root / "BOTS" / bot
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


def prompt_int(label: str, default: int) -> int:
    while True:
        raw = input(f"{label} (enter = {default}): ").strip()
        if raw == "":
            return int(default)
        if raw.isdigit():
            return int(raw)
        print("Número inválido")


def ensure_seed(root: Path, seed_path: Path) -> None:
    if seed_path.exists():
        return
    generated = root / "IA" / "weights" / "seed_genome.json"
    if not generated.exists():
        cmd = [sys.executable, str(root / "engine" / "tools" / "make_random_genome.py")]
        subprocess.check_call(cmd, cwd=str(root))
    seed_path.parent.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(generated.read_text(encoding="utf-8"), encoding="utf-8")


def write_profile_artifacts(root: Path, bot: str, profile: Dict[str, Any]) -> Dict[str, Path]:
    paths = build_bot_paths(root, bot)
    rewards = profile.get("rewards", {}) if isinstance(profile.get("rewards"), dict) else {}
    base_rewards = rewards.get("base", {}) if isinstance(rewards.get("base"), dict) else {}
    p1_rewards = rewards.get("p1", {}) if isinstance(rewards.get("p1"), dict) else {}
    p2_rewards = rewards.get("p2", {}) if isinstance(rewards.get("p2"), dict) else {}

    write_json(
        paths["rewards"],
        {
            "time_without_kill": float(base_rewards.get("time_without_kill", -0.1)),
            "kill": float(base_rewards.get("kill", 10.0)),
            "death": float(base_rewards.get("death", -5.0)),
            "time_alive": float(base_rewards.get("time_alive", 0.0)),
        },
    )
    write_json(paths["bot_p1"], {"name": bot, "reward": dict(p1_rewards)})
    write_json(paths["bot_p2"], {"name": bot, "reward": dict(p2_rewards)})
    ensure_seed(root, paths["seed"])
    if not paths["best"].exists():
        paths["best"].write_text(paths["seed"].read_text(encoding="utf-8"), encoding="utf-8")

    base_cfg = read_json(root / "IA" / "config" / "islands_fresh.json")
    islands = profile.get("islands", {}) if isinstance(profile.get("islands"), dict) else {}
    cfg = dict(base_cfg)
    cfg.update(islands)

    if "population" not in cfg:
        cfg["population"] = int(islands.get("population", 6))
    if "elite" not in cfg:
        cfg["elite"] = int(islands.get("elite", 2))
    if "crossover" not in cfg:
        cfg["crossover"] = bool(islands.get("crossover", False))
    if "sweep_bonus" not in cfg:
        cfg["sweep_bonus"] = float(islands.get("sweep_bonus", 0.75))

    cfg["match_rules_path"] = str(Path("IA") / "config" / "match_rules.json").replace("\\", "/")
    cfg["match_rules_path"] = MATCH_RULES_PATH
    cfg["rounds"] = 0
    cfg.pop("max_steps", None)
    cfg.pop("max_seconds", None)
    cfg.pop("max_kills", None)
    cfg["state_dir"] = str(paths["state"].relative_to(root)).replace("\\", "/")
    cfg["initial_seed"] = str(paths["best"].relative_to(root)).replace("\\", "/")
    cfg["promote_best_path"] = str(paths["best"].relative_to(root)).replace("\\", "/")
    cfg["promote_state_path"] = str(paths["current"].relative_to(root)).replace("\\", "/")
    cfg["progress_path"] = str((root / "BOTS" / bot / "progress.json").resolve())
    cfg["league_dir"] = str((Path("BOTS") / bot / "league").as_posix())
    cfg["league_max"] = int(cfg.get("league_max", 64))
    cfg["godot_user_args"] = [
        f"--rewards-path=res://BOTS/{bot}/rewards.json",
        f"--bot-config-p1=res://BOTS/{bot}/bot_p1.json",
        f"--bot-config-p2=res://BOTS/{bot}/bot_p2.json",
        f"--super-reward-path={SUPER_REWARD_PATH}",
        "--match-mode",
    ]
    trainer_script = str(cfg.get("trainer_script", "") or "")
    if "training_ga_params.py" in trainer_script and "--training-opponent-policy=handmade" not in cfg["godot_user_args"]:
        cfg["godot_user_args"].append("--training-opponent-policy=handmade")
    if "training_ga_params.py" in trainer_script:
        cfg.setdefault("trainer_user_args", [])
        if isinstance(cfg.get("trainer_user_args"), list) and "--handmade-config-path=res://BOTS/profiles/default/handmade.json" not in cfg["trainer_user_args"]:
            cfg["trainer_user_args"].append("--handmade-config-path=res://BOTS/profiles/default/handmade.json")
    cfg["trainer_live_rounds"] = True
    cfg["live_round_logs"] = True
    cfg["trainer_pretty_md9"] = True
    write_json(paths["islands_cfg"], cfg)
    return paths


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

    desc_default = f"Perfil criado via supertreino.py ({bot})."
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
    print(f"Super reward: {SUPER_REWARD_PATH}")
    return 0


def _set_one_more_round_limit(root: Path, cfg: Dict[str, Any]) -> None:
    state_dir_raw = str(cfg.get("state_dir", ""))
    if not state_dir_raw:
        return
    state_dir = Path(root / state_dir_raw)
    last_summary = state_dir / "last_summary.json"
    next_round = 1
    if last_summary.exists():
        last = read_json(last_summary)
        try:
            last_round = int(last.get("round", 0)) if isinstance(last, dict) else 0
            if last_round > 0:
                next_round = last_round + 1
        except Exception:
            pass
    cfg["rounds"] = int(next_round)


def _ensure_rounds_not_finished(root: Path, cfg: Dict[str, Any]) -> None:
    try:
        rounds_cfg = int(cfg.get("rounds", 0))
    except Exception:
        rounds_cfg = 0
    if rounds_cfg <= 0:
        return
    state_dir_raw = str(cfg.get("state_dir", ""))
    if not state_dir_raw:
        return
    last_summary = Path(root / state_dir_raw) / "last_summary.json"
    if not last_summary.exists():
        return
    last = read_json(last_summary)
    try:
        last_round = int(last.get("round", 0)) if isinstance(last, dict) else 0
    except Exception:
        last_round = 0
    if last_round >= rounds_cfg:
        cfg["rounds"] = int(last_round + 1)


def build_matchup_config(
    root: Path,
    train_bot: str,
    opponent: str,
    no_sync: bool,
    single_round: bool,
    override_generations: int | None = None,
    override_rounds: int | None = None,
    override_population: int | None = None,
    override_elite: int | None = None,
    override_crossover: bool | None = None,
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
    cfg["match_rules_path"] = str(Path("IA") / "config" / "match_rules.json").replace("\\", "/")
    cfg["match_rules_path"] = MATCH_RULES_PATH
    cfg.pop("max_steps", None)
    cfg.pop("max_seconds", None)
    cfg.pop("max_kills", None)

    cfg["progress_path"] = str((root / "BOTS" / train_bot / "progress.json").resolve())
    cfg["league_dir"] = str((Path("BOTS") / train_bot / "league").as_posix())
    cfg["league_max"] = int(cfg.get("league_max", 64))

    if override_generations is not None:
        cfg["generations"] = int(max(1, override_generations))

    if override_population is not None:
        cfg["population"] = int(max(1, override_population))
    if override_elite is not None:
        cfg["elite"] = int(max(1, min(int(override_elite), int(cfg.get("population", 1)))))
    if override_crossover is not None:
        cfg["crossover"] = bool(override_crossover)

    if override_rounds is not None:
        cfg["rounds"] = int(max(0, override_rounds))

    if opponent == "baseline":
        cfg["opponent"] = "baseline"
        cfg.pop("opponent_load_path", None)
        cfg["opponent_tag"] = "baseline"
        matchup_dir = train_paths["base"] / "matchups" / "baseline"
    else:
        opp = normalize_bot_name(opponent)
        opp_best = root / "BOTS" / opp / "best_genome.json"
        if not opp_best.exists():
            raise RuntimeError(f"Oponente sem best_genome: {opp_best}")
        opp_tag = opp
        opp_meta = read_json(root / "BOTS" / opp / "current_bot.json")
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
        cfg["opponent_pool_dir"] = str((Path("BOTS") / opp / "league").as_posix())
        cfg["opponent_pool_max"] = int(cfg.get("opponent_pool_max", 8))
        cfg["opponent_pool_mode"] = str(cfg.get("opponent_pool_mode", "round_robin"))
        cfg["opponent_pool_include_best"] = True
        matchup_dir = train_paths["base"] / "matchups" / opp

    cfg["state_dir"] = str((matchup_dir / "state").relative_to(root)).replace("\\", "/")
    if single_round:
        _set_one_more_round_limit(root, cfg)
    else:
        _ensure_rounds_not_finished(root, cfg)
    out_cfg = matchup_dir / "islands.json"
    write_json(out_cfg, cfg)
    return out_cfg


def run_islands(root: Path, cfg_path: Path) -> int:
    cmd = [sys.executable, str(root / "engine" / "tools" / "island_orchestrator.py"), "run", "--config", str(cfg_path)]
    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    return subprocess.call(cmd, cwd=str(root), env=env)


def interactive_menu(root: Path) -> int:
    profiles = list_profiles(root)
    if not profiles:
        print("Nenhum perfil encontrado em BOTS/*.json")
        return 2
    names = list(profiles.keys())
    default_idx = names.index("default") if "default" in profiles else 0

    while True:
        print("\n=== Supertreino (Perfis BOTS/) ===")
        print(f"Super reward ativo: {SUPER_REWARD_PATH}")
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
            opp_options = ["baseline"] + [n for n in names if n != train_bot]
            opp_idx = prompt_choice("Selecione o oponente (P2)", opp_options, 0)
            opponent = opp_options[opp_idx]
            profile = read_json(profiles.get(train_bot, Path("")))
            default_gen = int(profile.get("islands", {}).get("generations", 6)) if isinstance(profile, dict) else 6
            gens = prompt_int("Quantas generations por worker", default_gen)
            pop = prompt_int("Population (por worker)", int(profile.get("islands", {}).get("population", 6)) if isinstance(profile, dict) else 6)
            elite = prompt_int("Elite (por worker)", int(profile.get("islands", {}).get("elite", 2)) if isinstance(profile, dict) else 2)
            crossover = (input("Crossover? (s/N) ").strip().lower() == "s")

            rounds = prompt_int("Quantos rounds (0=infinito)", 0)

            cfg_path = build_matchup_config(
                root,
                train_bot,
                opponent,
                no_sync=False,
                single_round=False,
                override_generations=gens,
                override_rounds=rounds,
                override_population=pop,
                override_elite=elite,
                override_crossover=crossover,
            )
            print(f"\nRodando: {cfg_path}")
            print(f"Edite ao vivo: {SUPER_REWARD_PATH}")
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

            profile1 = read_json(profiles.get(p1, Path("")))
            default_gen = int(profile1.get("islands", {}).get("generations", 6)) if isinstance(profile1, dict) else 6
            gens = prompt_int("Quantas generations por worker", default_gen)
            pop = prompt_int("Population (por worker)", int(profile1.get("islands", {}).get("population", 6)) if isinstance(profile1, dict) else 6)
            elite = prompt_int("Elite (por worker)", int(profile1.get("islands", {}).get("elite", 2)) if isinstance(profile1, dict) else 2)
            crossover = (input("Crossover? (s/N) ").strip().lower() == "s")
            for i in range(cycles):
                print(f"\n=== Ciclo {i+1}/{cycles}: treinando {p1} vs {p2} ===")
                cfg1 = build_matchup_config(
                    root,
                    p1,
                    p2,
                    no_sync=False,
                    single_round=True,
                    override_generations=gens,
                    override_population=pop,
                    override_elite=elite,
                    override_crossover=crossover,
                )
                code = run_islands(root, cfg1)
                if code != 0:
                    return code
                print(f"\n=== Ciclo {i+1}/{cycles}: treinando {p2} vs {p1} ===")
                cfg2 = build_matchup_config(
                    root,
                    p2,
                    p1,
                    no_sync=False,
                    single_round=True,
                    override_generations=gens,
                    override_population=pop,
                    override_elite=elite,
                    override_crossover=crossover,
                )
                code = run_islands(root, cfg2)
                if code != 0:
                    return code
            return 0


def main() -> int:
    if len(sys.argv) == 1:
        return interactive_menu(repo_root())

    parser = argparse.ArgumentParser(prog="supertreino.py")
    parser.add_argument("--bot", default="", help="Nome do perfil (ex: agressivo)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-sync", action="store_true")
    args = parser.parse_args(sys.argv[1:])

    bot = normalize_bot_name(str(args.bot))
    if not bot:
        print("Informe um perfil. Ex: python supertreino.py --bot agressivo")
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
    print(f"Super reward: {SUPER_REWARD_PATH}")
    if args.dry_run:
        return 0
    return run_islands(root, paths["islands_cfg"])


if __name__ == "__main__":
    raise SystemExit(main())
