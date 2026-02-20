from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional


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


def bot_profile_path(root: Path, bot: str) -> Path:
    return root / "BOTS" / "profiles" / bot


def bot_def_path(root: Path, bot: str) -> Path:
    return root / "BOTS" / f"{bot}.json"


def ensure_import_tools(root: Path) -> None:
    tools = root / "engine" / "tools"
    if str(tools) not in sys.path:
        sys.path.insert(0, str(tools))


def seed_genome_from_handmade(root: Path, handmade_path: Path) -> Dict[str, Any]:
    ensure_import_tools(root)
    from ga_params_schema_v1 import merge_handmade_into_defaults  # type: ignore

    handmade = read_json(handmade_path)
    genes = merge_handmade_into_defaults(handmade)
    return {
        "genome_version": 1,
        "schema_id": "ga_params_v1",
        "genes": genes,
        "meta": {"created_from": "handmade"},
    }


def build_islands_config(
    root: Path,
    bot: str,
    bot_profile: Dict[str, Any],
    base_cfg: Dict[str, Any],
    use_params_trainer: bool,
    opponent_policy: str,
    handmade_config_res: str,
    opponent_bot: str,
) -> Dict[str, Any]:
    cfg = dict(base_cfg)
    cfg.update(bot_profile.get("islands", {}) if isinstance(bot_profile.get("islands"), dict) else {})

    profile_dir = bot_profile_path(root, bot)
    existing_cfg = read_json(profile_dir / "islands.json")
    if isinstance(existing_cfg, dict):
        prev_godot = str(existing_cfg.get("godot_exe", "") or "").strip()
        if prev_godot:
            cfg["godot_exe"] = prev_godot
        prev_python = str(existing_cfg.get("python_exe", "") or "").strip()
        if prev_python:
            cfg["python_exe"] = prev_python
    cfg["match_rules_path"] = "BOTS/IA/config/match_rules_match.json"
    cfg["state_dir"] = str((Path("BOTS") / "profiles" / bot / "state").as_posix())
    cfg["initial_seed"] = str((Path("BOTS") / "profiles" / bot / "seed_genome.json").as_posix())
    cfg["promote_best"] = True
    cfg["promote_best_path"] = str((Path("BOTS") / "profiles" / bot / "best_genome.json").as_posix())
    cfg["promote_state_path"] = str((Path("BOTS") / "profiles" / bot / "current_bot.json").as_posix())
    cfg["progress_path"] = str((profile_dir / "progress.json").resolve())
    cfg["league_dir"] = str((Path("BOTS") / "profiles" / bot / "league").as_posix())
    cfg["league_max"] = int(cfg.get("league_max", 64))

    p2_cfg_bot = opponent_bot if opponent_bot else bot
    cfg["opponent_tag"] = opponent_bot if opponent_bot else str(cfg.get("opponent_tag", cfg.get("opponent", "")))
    godot_args = [
        f"--rewards-path=res://BOTS/profiles/{bot}/rewards.json",
        f"--bot-config-p1=res://BOTS/profiles/{bot}/bot_p1.json",
        f"--bot-config-p2=res://BOTS/profiles/{p2_cfg_bot}/bot_p2.json",
        "--super-reward-path=res://BOTS/IA/config/super_reward.json",
        "--match-mode",
    ]
    godot_args.append(f"--bot-profile-p1={bot}")
    if opponent_bot:
        godot_args.append(f"--bot-profile-p2={opponent_bot}")
    if opponent_policy and opponent_policy != "external":
        godot_args.append(f"--training-opponent-policy={opponent_policy}")
    cfg["godot_user_args"] = godot_args
    cfg.setdefault("live_round_logs", True)
    cfg.setdefault("trainer_live_rounds", True)
    cfg.setdefault("trainer_pretty_md9", True)

    if use_params_trainer:
        cfg["trainer_script"] = "engine/tools/training_ga_params.py"
        cfg.setdefault("trainer_user_args", [])
        if isinstance(cfg.get("trainer_user_args"), list):
            args: list[str] = [str(x) for x in cfg["trainer_user_args"]]
            handmade_flag = f"--handmade-config-path={handmade_config_res}"
            if handmade_flag not in args:
                args.append(handmade_flag)
            cfg["trainer_user_args"] = args
        cfg["opponent"] = str(cfg.get("opponent", "handmade"))
        if str(cfg["opponent"]) == "handmade":
            cfg["opponent"] = "baseline"
    return cfg


def sync_profile(
    root: Path,
    bot: str,
    base_cfg_path: Path,
    use_params_trainer: bool,
    opponent_policy: str,
    handmade_config_res: Optional[str],
    opponent_bot: str,
) -> None:
    profile_json_path = bot_def_path(root, bot)
    profile_dir = bot_profile_path(root, bot)
    profile = read_json(profile_json_path)
    if not profile:
        raise SystemExit(f"Perfil não encontrado: {profile_json_path}")

    rewards = profile.get("rewards", {}) if isinstance(profile.get("rewards"), dict) else {}
    base_rewards = rewards.get("base", {}) if isinstance(rewards.get("base"), dict) else {}
    p1_rewards = rewards.get("p1", {}) if isinstance(rewards.get("p1"), dict) else {}
    p2_rewards = rewards.get("p2", {}) if isinstance(rewards.get("p2"), dict) else {}
    write_json(
        profile_dir / "rewards.json",
        {
            "time_without_kill": float(base_rewards.get("time_without_kill", -0.1)),
            "kill": float(base_rewards.get("kill", 10.0)),
            "death": float(base_rewards.get("death", -5.0)),
            "time_alive": float(base_rewards.get("time_alive", 0.0)),
        },
    )
    write_json(profile_dir / "bot_p1.json", {"name": bot, "reward": dict(p1_rewards)})
    write_json(profile_dir / "bot_p2.json", {"name": bot, "reward": dict(p2_rewards)})

    handmade_res = handmade_config_res or f"res://BOTS/profiles/{bot}/handmade.json"
    handmade_disk = root / handmade_res.replace("res://", "").replace("/", os.sep)
    if not handmade_disk.exists():
        fallback = root / "BOTS" / "profiles" / "default" / "handmade.json"
        handmade_disk = fallback
        handmade_res = "res://BOTS/profiles/default/handmade.json"

    seed_path = profile_dir / "seed_genome.json"
    best_path = profile_dir / "best_genome.json"
    if use_params_trainer:
        seed_payload = seed_genome_from_handmade(root, handmade_disk)
        write_json(seed_path, seed_payload)
        if not best_path.exists():
            write_json(best_path, seed_payload)
    else:
        if not seed_path.exists():
            seed_payload = {"weights": [], "meta": {"created_from": "empty"}}
            write_json(seed_path, seed_payload)
        if not best_path.exists():
            shutil.copyfile(seed_path, best_path)

    base_cfg = read_json(base_cfg_path)
    cfg = build_islands_config(
        root=root,
        bot=bot,
        bot_profile=profile,
        base_cfg=base_cfg,
        use_params_trainer=use_params_trainer,
        opponent_policy=opponent_policy,
        handmade_config_res=handmade_res,
        opponent_bot=opponent_bot,
    )
    write_json(profile_dir / "islands.json", cfg)
    (profile_dir / "league").mkdir(parents=True, exist_ok=True)
    state_dir = profile_dir / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    gdignore = state_dir / ".gdignore"
    if not gdignore.exists():
        gdignore.write_text("", encoding="utf-8")


def cmd_list(root: Path) -> int:
    bots_dir = root / "BOTS"
    profiles = sorted([p.stem for p in bots_dir.glob("*.json")])
    for name in profiles:
        print(name)
    return 0


def cmd_init(root: Path, name: str, template: str) -> int:
    bot = normalize_bot_name(name)
    if not bot:
        raise SystemExit("Nome inválido")
    tpl_path = bot_def_path(root, normalize_bot_name(template))
    tpl = read_json(tpl_path) if tpl_path.exists() else {}
    if not tpl:
        tpl = read_json(root / "BOTS" / "default.json")
    out_path = bot_def_path(root, bot)
    if out_path.exists():
        raise SystemExit(f"Já existe: {out_path}")
    profile = {
        "name": bot,
        "description": f"Perfil criado via ga_launcher.py ({bot}).",
        "rewards": tpl.get("rewards", {"base": {}, "p1": {}, "p2": {}}),
        "islands": tpl.get("islands", {}),
    }
    write_json(out_path, profile)
    bot_profile_path(root, bot).mkdir(parents=True, exist_ok=True)
    print(str(out_path))
    return 0


def cmd_sync(root: Path, bot: str, args: argparse.Namespace) -> int:
    base_cfg = Path(args.base_cfg).resolve() if args.base_cfg else (root / "BOTS" / "IA" / "config" / "islands_fresh.json")
    use_params_trainer = bool(args.params_trainer)
    opponent_policy = str(args.opponent_policy or "handmade")
    handmade_path = str(args.handmade_config or "").strip() or None
    opponent_bot = str(args.opponent_bot or "").strip()
    sync_profile(
        root=root,
        bot=normalize_bot_name(bot),
        base_cfg_path=base_cfg,
        use_params_trainer=use_params_trainer,
        opponent_policy=opponent_policy,
        handmade_config_res=handmade_path,
        opponent_bot=normalize_bot_name(opponent_bot) if opponent_bot else "",
    )
    print(str((bot_profile_path(root, normalize_bot_name(bot)) / "islands.json").resolve()))
    return 0


def cmd_run(root: Path, bot: str, args: argparse.Namespace) -> int:
    bot_n = normalize_bot_name(bot)
    cfg_path = bot_profile_path(root, bot_n) / "islands.json"
    if not cfg_path.exists():
        raise SystemExit(f"Faltando: {cfg_path}. Rode sync antes.")
    cmd = [sys.executable, str(root / "engine" / "tools" / "island_orchestrator.py"), "run", "--config", str(cfg_path)]
    if args.dry_run:
        cmd.append("--dry-run")
    if args.watch:
        cmd.append("--watch")
    print(" ".join(cmd))
    return subprocess.call(cmd, cwd=str(root))


def main() -> int:
    root = repo_root()
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list")

    p_init = sub.add_parser("init")
    p_init.add_argument("name")
    p_init.add_argument("--template", default="default")

    p_sync = sub.add_parser("sync")
    p_sync.add_argument("bot")
    p_sync.add_argument("--base-cfg", default="")
    p_sync.add_argument("--params-trainer", action="store_true")
    p_sync.add_argument("--opponent-policy", default="handmade")
    p_sync.add_argument("--handmade-config", default="")
    p_sync.add_argument("--opponent-bot", default="")

    p_run = sub.add_parser("run")
    p_run.add_argument("bot")
    p_run.add_argument("--dry-run", action="store_true")
    p_run.add_argument("--watch", action="store_true")

    args = parser.parse_args()
    if args.cmd == "list":
        return cmd_list(root)
    if args.cmd == "init":
        return cmd_init(root, str(args.name), str(args.template))
    if args.cmd == "sync":
        return cmd_sync(root, str(args.bot), args)
    if args.cmd == "run":
        return cmd_run(root, str(args.bot), args)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
