import argparse

import json

import os

import shutil

import subprocess

import sys

import time

from dataclasses import dataclass

from pathlib import Path

from typing import Dict, List, Optional, Tuple



from typing import Dict, List, Optional, Tuple





def _tail_text(path: Path, limit: int = 18) -> str:

    if not path.exists():

        return ""

    try:

        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()

    except OSError:

        return ""

    tail = lines[-limit:]

    return "\n".join(tail)





def _read_new_lines(path: Path, last_pos: int) -> Tuple[int, List[str]]:

    if not path.exists():

        return 0, []

    try:

        with path.open("r", encoding="utf-8", errors="replace") as f:

            f.seek(max(0, int(last_pos)))

            data = f.read()

            new_pos = f.tell()

    except Exception:

        return 0, []

    if not data:

        return int(new_pos), []

    lines = [ln.rstrip("\r\n") for ln in data.splitlines() if ln.strip()]

    return int(new_pos), lines





def _extract_live_round_line(text: str) -> str:

    if not text:

        return ""

    lines = [ln.strip() for ln in str(text).splitlines() if ln.strip()]

    for ln in reversed(lines):

        if ln.startswith("[ROUND]") or ln.startswith("[MATCH]"):

            return ln

    return ""





ANSI_RESET = "\x1b[0m"

ANSI_BOLD = "\x1b[1m"

ANSI_DIM = "\x1b[2m"

ANSI_RED = "\x1b[31m"

ANSI_GREEN = "\x1b[32m"

ANSI_YELLOW = "\x1b[33m"

ANSI_CYAN = "\x1b[36m"





def _use_color(cfg: Dict) -> bool:

    if bool(cfg.get("no_color", False)):

        return False

    if "NO_COLOR" in os.environ:

        return False

    if bool(cfg.get("force_color", False)):

        return True

    if os.environ.get("FORCE_COLOR", "").strip() not in ("", "0", "false", "False"):

        return True

    return False





def _c(text: str, code: str, enabled: bool) -> str:

    if not enabled:

        return text

    return f"{code}{text}{ANSI_RESET}"





def _primary_total_score(payload: Dict) -> float:

    best_stats = payload.get("best_stats") if isinstance(payload.get("best_stats"), dict) else {}

    if isinstance(best_stats, dict):

        try:

            if "fitness" in best_stats:

                return float(best_stats.get("fitness", float("-inf")))

        except Exception:

            pass

    last_round = best_stats.get("last_round") if isinstance(best_stats.get("last_round"), dict) else {}

    match_score = last_round.get("match_score") if isinstance(last_round.get("match_score"), dict) else {}

    try:

        return float(match_score.get(1, match_score.get("1", float("-inf"))))

    except Exception:

        return float("-inf")





def _is_sweep_5_0(payload: Dict) -> bool:

    best_stats = payload.get("best_stats") if isinstance(payload.get("best_stats"), dict) else {}

    last_round = best_stats.get("last_round") if isinstance(best_stats.get("last_round"), dict) else {}

    wins = last_round.get("wins") if isinstance(last_round.get("wins"), dict) else {}

    try:

        w1 = int(wins.get(1, wins.get("1", 0)))

        w2 = int(wins.get(2, wins.get("2", 0)))

    except Exception:

        return False

    return w1 == 5 and w2 == 0





def _summarize_worker_failure(out_dir: Path) -> str:

    godot_tail = _tail_text(out_dir / "godot.log", limit=18)

    trainer_tail = _tail_text(out_dir / "trainer.log", limit=18)

    parts: List[str] = []

    if godot_tail:

        parts.append("[godot]\n" + godot_tail)

    if trainer_tail:

        parts.append("[trainer]\n" + trainer_tail)

    return "\n\n".join(parts).strip()





def resolve_executable(value: str) -> str:

    if not value:

        return ""

    candidate = value.strip().strip('"')

    if Path(candidate).exists():

        return candidate

    return shutil.which(candidate) or ""





@dataclass

class WorkerSpec:

    worker_id: int

    port: int

    seed_path: str

    out_dir: Path

    attempt: int = 0





@dataclass

class WorkerRun:

    spec: WorkerSpec

    godot_proc: subprocess.Popen

    trainer_proc: subprocess.Popen

    godot_log: object

    trainer_log: object

    started_at: float





def resolve_path(project_root: Path, value: str) -> str:

    if not value:

        return ""

    if value == "python" or value == "python3" or value == "godot4" or value == "godot":

        return value

    if not any(sep in value for sep in ("/", "\\")) and not value.startswith(".") and not value.lower().endswith(".exe"):

        return value

    path = Path(value)

    if path.is_absolute():

        return str(path)

    return str(project_root / path)





def load_match_rules(project_root: Path, cfg: Dict) -> Dict:

    rules_path_cfg = str(cfg.get("match_rules_path", "")).strip()

    rules: Dict = {}

    if rules_path_cfg:

        path = Path(resolve_path(project_root, rules_path_cfg))

        rules = read_json(path)

        if not isinstance(rules, dict):

            rules = {}

    max_steps = int(rules.get("max_steps", cfg.get("max_steps", 0)))

    max_seconds = float(rules.get("max_seconds", cfg.get("max_seconds", 0.0)))

    max_kills = int(rules.get("max_kills", cfg.get("max_kills", 0)))

    return {"max_steps": max_steps, "max_seconds": max_seconds, "max_kills": max_kills}





def _resolve_opponent_pool(project_root: Path, cfg: Dict) -> List[str]:

    paths: List[str] = []

    raw_paths = cfg.get("opponent_pool_paths", [])

    if isinstance(raw_paths, list):

        for p in raw_paths:

            rp = resolve_path(project_root, str(p))

            if rp:

                paths.append(rp)



    pool_dir_cfg = str(cfg.get("opponent_pool_dir", "")).strip()

    pool_max = int(cfg.get("opponent_pool_max", 0))

    if pool_dir_cfg and pool_max != 0:

        pool_dir = Path(resolve_path(project_root, pool_dir_cfg))

        if pool_dir.exists():

            snaps = sorted(pool_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)

            if pool_max > 0:

                snaps = snaps[:pool_max]

            for p in snaps:

                paths.append(str(p))



    if bool(cfg.get("opponent_pool_include_best", True)):

        best_path = str(cfg.get("opponent_load_path", "")).strip()

        if best_path:

            rp = resolve_path(project_root, best_path)

            if rp:

                paths.append(rp)



    seen = set()

    unique: List[str] = []

    for p in paths:

        if p not in seen:

            unique.append(p)

            seen.add(p)

    return unique





def ensure_dir(path: Path) -> None:

    path.mkdir(parents=True, exist_ok=True)





def read_json(path: Path) -> Dict:

    if not path.exists():

        return {}

    try:

        return json.loads(path.read_text(encoding="utf-8"))

    except (json.JSONDecodeError, OSError):

        return {}





def write_json(path: Path, payload: Dict) -> None:

    ensure_dir(path.parent)

    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")





def append_log(path: Path, line: str) -> None:

    ensure_dir(path.parent)

    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")

    with open(path, "a", encoding="utf-8", errors="ignore") as file:

        file.write(f"[{timestamp}] {line}\n")





def _load_progress(path: Path) -> Dict:

    payload = read_json(path)

    if not isinstance(payload, dict):

        payload = {}

    next_generation = int(payload.get("next_generation", 1))

    next_individual = int(payload.get("next_individual", 0))

    if next_generation < 1:

        next_generation = 1

    if next_individual < 0:

        next_individual = 0

    return {"next_generation": next_generation, "next_individual": next_individual}





def _save_progress(path: Path, next_generation: int, next_individual: int) -> None:

    write_json(

        path,

        {

            "next_generation": int(max(1, next_generation)),

            "next_individual": int(max(0, next_individual)),

            "updated_at": int(time.time()),

        },

    )





def build_godot_cmd(

    project_root: Path,

    godot_exe: str,

    port: int,

    time_scale: float,

    quit_idle: float,

    fixed_fps: int,

    max_steps: int,

    max_seconds: float,

    max_kills: int,

    user_dir: Optional[str] = None,

    extra_user_args: Optional[List[str]] = None,

) -> List[str]:

    cmd = [

        godot_exe,

        "--headless",

        "--fixed-fps",

        str(int(fixed_fps)),

    ]

    if user_dir:

        cmd += ["--user-dir", str(user_dir)]

    cmd += [

        "--path",

        str(project_root),

        "--scene",

        "res://engine/scenes/Main.tscn",

        "--",

        "--training",

        f"--port={int(port)}",

        "--no-watch",

        f"--time-scale={float(time_scale)}",

        f"--max-steps={int(max_steps)}",

        f"--max-seconds={float(max_seconds)}",

        f"--max-kills={int(max_kills)}",

        f"--quit-idle={float(quit_idle)}",

    ]

    if extra_user_args:

        cmd += list(extra_user_args)

    return cmd





def build_trainer_cmd(

    project_root: Path,

    python_exe: str,

    port: int,

    seed_path: str,

    save_path: str,

    log_path: str,

    result_path: str,

    generations: int,

    episodes_per_genome: int,

    population: int,

    elite: int,

    mutation_rate: float,

    mutation_std: float,

    win_weight: float,

    reward_scale: float,

    crossover: bool,

    sweep_bonus: float,

    opponent: str,

    opponent_load_path: str,

    opponent_pool_paths: List[str],

    opponent_pool_mode: str,

    time_scale: float,

    connect_retries: int,

    connect_wait: float,

    connect_timeout: float,

    idle_timeout: float,

    quiet: bool,

    learn_aim: bool = False,

    aim_bins: int = 9,

) -> List[str]:

    cmd = [

        python_exe,

        str(project_root / "engine" / "tools" / "training_genetic_ga.py"),
        "--host",

        "127.0.0.1",

        "--port",

        str(int(port)),

        "--no-watch",

        "--time-scale",

        str(float(time_scale)),

        "--population",

        str(int(population)),

        "--elite",

        str(int(elite)),

        "--episodes-per-genome",

        str(int(episodes_per_genome)),

        "--mutation-rate",

        str(float(mutation_rate)),

        "--mutation-std",

        str(float(mutation_std)),

        "--win-weight",

        str(float(win_weight)),

        "--reward-scale",

        str(float(reward_scale)),

        "--sweep-bonus",

        str(float(sweep_bonus)),

        "--opponent",

        str(opponent),

    ]

    cmd.append("--crossover" if bool(crossover) else "--no-crossover")

    if opponent_load_path:

        cmd.extend(["--opponent-load-path", str(opponent_load_path)])

    if opponent_pool_paths:

        for p in opponent_pool_paths:

            if str(p).strip():

                cmd.extend(["--opponent-pool-path", str(p)])

        cmd.extend(["--opponent-pool-mode", str(opponent_pool_mode)])

    cmd += [

        "--generations",

        str(int(generations)),

        "--save-path",

        str(save_path),

        "--log-path",

        str(log_path),

        "--result-path",

        str(result_path),

        "--connect-retries",

        str(int(connect_retries)),

        "--connect-wait",

        str(float(connect_wait)),

        "--connect-timeout",

        str(float(connect_timeout)),

        "--idle-timeout",

        str(float(idle_timeout)),

    ]

    if quiet:

        cmd.append("--quiet")

    if learn_aim:

        cmd.append("--learn-aim")

        cmd.extend(["--aim-bins", str(int(aim_bins))])

    if seed_path:

        cmd.extend(["--load-path", str(seed_path)])

    return cmd





def load_config(project_root: Path, path: str) -> Dict:

    cfg_path = Path(resolve_path(project_root, path))

    cfg = read_json(cfg_path) if cfg_path else {}

    return cfg





def default_config(project_root: Path) -> Dict:

    return {

        "godot_exe": "godot4",

        "python_exe": sys.executable or "python",

        "workers": 500,

        "topk": 10,

        "rounds": 0,

        "concurrency": max(1, (os.cpu_count() or 8) // 2),

        "base_port": 12000,

        "fixed_fps": 60,

        "time_scale": 8.0,

        "quit_idle": 30.0,

        "generations": 30,

        "episodes_per_genome": 3,

        "population": 6,

        "elite": 2,

        "crossover": False,

        "sweep_bonus": 0.75,

        "mutation_rate": 0.08,

        "mutation_std": 0.2,

        "win_weight": 0.6,

        "reward_scale": 20.0,

        "opponent": "best",

        "learn_aim": False,

        "aim_bins": 9,

        "connect_retries": 300,

        "connect_wait": 0.1,

        "connect_timeout": 2.0,

        "idle_timeout": 30.0,

        "quiet": True,

        "spawn_delay_sec": 0.15,

        "early_godot_exit_grace_sec": 0.35,

        "godot_shutdown_wait_sec": 1.25,

        "isolate_user_dir": True,

        "max_attempts_per_worker": 2,

        "match_rules_path": "BOTS/IA/config/match_rules.json",
        "state_dir": "BOTS/IA/weights/islands",
        "initial_seed": "BOTS/IA/weights/best_genome.json",
        "promote_best": True,

        "promote_best_path": "BOTS/IA/weights/best_genome.json",
        "promote_state_path": "BOTS/IA/weights/current_bot.json",
        "promote_allow_regress": False,

        "promote_on_interrupt": True,

        "league_dir": "",

        "league_max": 64,

        "opponent_pool_dir": "",

        "opponent_pool_max": 0,

        "opponent_pool_mode": "round_robin",

        "opponent_pool_include_best": True,

        "opponent_pool_paths": [],

        "prefer_winner_selection": True,

        "live_round_logs": False,

        "trainer_live_rounds": False,

        "trainer_pretty_md9": False,

        "force_color": False,

        "no_color": False,

    }





def promote_best_genome(project_root: Path, cfg: Dict, summary: Dict) -> None:

    if not bool(cfg.get("promote_best", True)):

        return

    top: List[str] = summary.get("top", []) if isinstance(summary.get("top", []), list) else []

    if not top:

        return

    src = Path(resolve_path(project_root, str(top[0])))

    if not src.exists():

        return

    promote_path = Path(resolve_path(project_root, str(cfg.get("promote_best_path", "BOTS/IA/weights/best_genome.json"))))
    state_path = Path(resolve_path(project_root, str(cfg.get("promote_state_path", "BOTS/IA/weights/current_bot.json"))))


    new_best = float(summary.get("best", 0.0))

    prev_best = float("-inf")

    prev_meta = read_json(state_path) if state_path.exists() else {}

    if isinstance(prev_meta, dict):

        try:

            prev_best = float(prev_meta.get("best_ever", prev_meta.get("best", float("-inf"))))

        except Exception:

            prev_best = float("-inf")

    if not bool(cfg.get("promote_allow_regress", False)) and new_best <= prev_best:

        color_enabled = _use_color(cfg)

        try:

            individual = int((summary.get("best_payload", {}) or {}).get("individual", -1))

            rid = int(summary.get("round", 0))

            if individual > 0 and rid > 0:

                msg = f"Não promovido: G{rid} N{individual} best={new_best:.2f} (prev_best={prev_best:.2f})"

                print(_c(msg, ANSI_DIM, color_enabled))

        except Exception:

            pass

        return



    ensure_dir(promote_path.parent)

    tmp_path = promote_path.with_suffix(promote_path.suffix + ".tmp")

    shutil.copyfile(src, tmp_path)

    os.replace(tmp_path, promote_path)



    best_payload = summary.get("best_payload", {}) if isinstance(summary, dict) else {}

    if not isinstance(best_payload, dict):

        best_payload = {}

    write_json(

        state_path,

        {

            "source": str(src),

            "source_rel": str(top[0]),

            "promoted_to": str(promote_path),

            "round": int(summary.get("round", 0)),

            "best": float(summary.get("best", 0.0)),

            "best_ever": float(max(prev_best, new_best)),

            "best_metric": "fitness",

            "sweep_5_0": bool(best_payload.get("sweep_5_0", False)),

            "worker_id": int(best_payload.get("worker_id", -1)),

            "individual": int(best_payload.get("individual", -1)),

            "islands_round": int(best_payload.get("islands_round", summary.get("round", 0))),

            "generation": int(best_payload.get("generation", -1)),

            "port": int(best_payload.get("port", -1)),

            "episodes_per_genome": int(best_payload.get("episodes_per_genome", -1)),

            "mutation_rate": float(best_payload.get("mutation_rate", cfg.get("mutation_rate", 0.0))),

            "mutation_std": float(best_payload.get("mutation_std", cfg.get("mutation_std", 0.0))),

            "opponent": str(best_payload.get("opponent", cfg.get("opponent", ""))),

            "time_scale": float(best_payload.get("time_scale", cfg.get("time_scale", 1.0))),

            "seed_used": str(best_payload.get("load_path", best_payload.get("seed_path", ""))),

            "result_path": str(best_payload.get("result_path", "")),

            "timestamp": int(time.time()),

        },

    )



    try:

        league_cfg = str(cfg.get("league_dir", "")).strip()

        league_dir = Path(resolve_path(project_root, league_cfg)) if league_cfg else (promote_path.parent / "league")

        ensure_dir(league_dir)



        g = int(best_payload.get("generation_global", summary.get("generation_global", summary.get("round", 0))))

        n = int(best_payload.get("individual", -1))

        score = float(summary.get("best", 0.0))

        if g <= 0:

            g = int(summary.get("round", 0))

        if n <= 0:

            src_name = src.name

            gi = src_name.find("_G")

            ni = src_name.find("_N")

            if gi >= 0 and ni >= 0:

                try:

                    g = int(src_name[gi + 2 :].split("_")[0])

                    n = int(src_name[ni + 2 :].split("_")[0])

                except Exception:

                    pass



        if g > 0 and n > 0:

            snap = league_dir / f"G{g:04d}_N{n:06d}_score_{score:.6f}.json"

            if not snap.exists():

                shutil.copyfile(src, snap)



        league_max = int(cfg.get("league_max", 0))

        if league_max > 0:

            snaps = sorted(league_dir.glob("*.json"), key=lambda p: p.stat().st_mtime)

            excess = len(snaps) - league_max

            for p in snaps[: max(0, excess)]:

                try:

                    p.unlink()

                except OSError:

                    pass

    except Exception:

        pass

    try:

        individual = int(best_payload.get("individual", -1))

        rid = int(summary.get("round", 0))

        if individual > 0 and rid > 0:

            color_enabled = _use_color(cfg)

            msg = f"Promovido: G{rid} N{individual} -> {promote_path}"

            print(_c(msg, ANSI_GREEN, color_enabled))

    except Exception:

        pass





def merge_config(base: Dict, override: Dict) -> Dict:

    out = dict(base)

    for k, v in override.items():

        out[k] = v

    return out





def select_seed(seeds: List[str], idx: int) -> str:

    if not seeds:

        return ""

    return seeds[idx % len(seeds)]





def collect_results(round_dir: Path, workers: int) -> List[Tuple[float, Path, Dict]]:

    results: List[Tuple[float, Path, Dict]] = []

    for wid in range(workers):

        result_path = round_dir / f"worker_{wid}" / "result.json"

        payload = read_json(result_path)

        if not payload:

            continue

        if not bool(payload.get("ok", False)):

            continue

        score = _primary_total_score(payload)

        if not (score == score) or score in (float("inf"), float("-inf")):

            continue

        payload = dict(payload)

        payload["worker_id"] = int(wid)

        payload["result_path"] = str(result_path)

        payload["sweep_5_0"] = bool(_is_sweep_5_0(payload))



        best_stats = payload.get("best_stats") if isinstance(payload.get("best_stats"), dict) else {}

        last_round = best_stats.get("last_round") if isinstance(best_stats.get("last_round"), dict) else {}

        try:

            payload["best_winner"] = int(last_round.get("winner", 0))

        except Exception:

            payload["best_winner"] = 0

        match_score = last_round.get("match_score") if isinstance(last_round.get("match_score"), dict) else {}

        kills = last_round.get("kills") if isinstance(last_round.get("kills"), dict) else {}



        try:

            payload["best_fitness"] = float(best_stats.get("fitness", 0.0)) if isinstance(best_stats, dict) else 0.0

        except Exception:

            payload["best_fitness"] = 0.0

        try:

            payload["best_avg_score"] = float(best_stats.get("avg_score", 0.0)) if isinstance(best_stats, dict) else 0.0

        except Exception:

            payload["best_avg_score"] = 0.0

        try:

            payload["best_score_p1"] = float(match_score.get(1, match_score.get("1", 0.0)))

            payload["best_score_p2"] = float(match_score.get(2, match_score.get("2", 0.0)))

        except Exception:

            payload["best_score_p1"] = 0.0

            payload["best_score_p2"] = 0.0

        try:

            payload["best_kills_p1"] = int(kills.get(1, kills.get("1", 0)))

            payload["best_kills_p2"] = int(kills.get(2, kills.get("2", 0)))

        except Exception:

            payload["best_kills_p1"] = 0

            payload["best_kills_p2"] = 0



        save_path = payload.get("save_path", "")

        genome_path = Path(save_path) if save_path else (round_dir / f"worker_{wid}" / "best.json")

        if not genome_path.exists():

            continue

        payload["genome_path"] = str(genome_path)

        results.append((score, genome_path, payload))

    results.sort(

        key=lambda x: (

            1 if bool(x[2].get("sweep_5_0", False)) else 0,

            float(x[0]),

            int(x[2].get("best_winner", 0)),

            -int(x[2].get("worker_id", 0)),

        ),

        reverse=True,

    )

    return results





def run_round(

    project_root: Path,

    cfg: Dict,

    round_index: int,

    generation_global: int,

    base_individual: int,

    seed_paths: List[str],

    dry_run: bool,

) -> List[str]:

    workers = int(cfg["workers"])

    concurrency = min(int(cfg["concurrency"]), workers)

    spawn_batch = max(1, int(cfg.get("spawn_batch", 16)))

    base_port = int(cfg["base_port"]) + round_index * (workers + 10)

    state_dir = Path(resolve_path(project_root, cfg["state_dir"]))

    round_dir = state_dir / f"round_{round_index:04d}"

    resume_round = bool(cfg.get("resume_round", False))

    if round_dir.exists() and not resume_round:

        shutil.rmtree(round_dir, ignore_errors=True)

    ensure_dir(round_dir)



    outer_ga = bool(cfg.get("outer_ga", False))

    if outer_ga and "matches_per_individual" in cfg and "episodes_per_genome" not in cfg:

        cfg["episodes_per_genome"] = int(cfg.get("matches_per_individual", 1))



    generated_population_paths: List[str] = []

    if outer_ga and not resume_round:

        population_dir = round_dir / "population"

        generated_population_paths = generate_population(

            project_root,

            seed_paths,

            population_dir,

            workers,

            float(cfg.get("mutation_rate", 0.08)),

            float(cfg.get("mutation_std", 0.2)),

            bool(cfg.get("crossover", False)),

            int(cfg.get("seed", 0)) + int(generation_global) * 100000 + int(round_index),

        )



    queue: List[WorkerSpec] = []

    completed = 0

    best_so_far: Optional[float] = None

    best_sweep = False



    for wid in range(workers):

        port = base_port + wid

        out_dir = round_dir / f"worker_{wid}"

        ensure_dir(out_dir)



        if resume_round:

            result_path = out_dir / "result.json"

            payload = read_json(result_path)

            if isinstance(payload, dict) and bool(payload.get("ok", False)):

                completed += 1

                score = _primary_total_score(payload)

                sweep = _is_sweep_5_0(payload)

                if score == score and score not in (float("inf"), float("-inf")):

                    if best_so_far is None:

                        best_so_far = score

                        best_sweep = bool(sweep)

                    else:

                        if (bool(sweep) and not best_sweep) or (bool(sweep) == best_sweep and score > float(best_so_far)):

                            best_so_far = score

                            best_sweep = bool(sweep)

                continue



        queue.append(

            WorkerSpec(

                worker_id=wid,

                port=port,

                seed_path=(

                    generated_population_paths[wid]

                    if outer_ga and wid < len(generated_population_paths)

                    else select_seed(seed_paths, wid)

                ),

                out_dir=out_dir,

                attempt=0,

            )

        )



    running: List[WorkerRun] = []

    started = time.time()

    status_path = state_dir / "status.json"

    log_path = state_dir / "orchestrator.log"

    last_status_write = 0.0



    live_round_logs = bool(cfg.get("live_round_logs", False))

    last_live_by_worker: Dict[int, str] = {}

    live_sample_wid: Optional[int] = None

    trainer_log_pos_by_worker: Dict[int, int] = {}



    append_log(

        log_path,

        (

            f"IslandsRound {round_index} start | workers={workers} topk={cfg['topk']} seeds={len(seed_paths)} "

            f"resume={resume_round} outer_ga={int(outer_ga)} matches={int(cfg.get('episodes_per_genome', 1))}"

        ),

    )

    seed_preview = seed_paths[0] if seed_paths else ""

    print(

        (

            f"IslandsRound {round_index} | launching {workers} workers with concurrency={concurrency} "

            f"(resume={resume_round}) | outer_ga={int(outer_ga)} matches={int(cfg.get('episodes_per_genome', 1))} | seed={seed_preview}"

        )

    )



    color_enabled = _use_color(cfg)



    write_json(

        status_path,

        {

            "round": int(round_index),

            "workers": int(workers),

            "completed": int(completed),

            "running": 0,

            "queued": int(len(queue)),

            "best_so_far": None,

            "elapsed_sec": 0.0,

            "eta_sec": 0.0,

            "concurrency": int(concurrency),

            "updated_at": int(time.time()),

            "error": "",

        },

    )



    try:

        while queue or running:

            spawn_budget = min(spawn_batch, concurrency - len(running), len(queue))

            for _ in range(spawn_budget):

                spec = queue.pop(0)

                godot_exe = resolve_executable(str(cfg["godot_exe"]))

                if not godot_exe:

                    if dry_run:

                        godot_exe = str(cfg["godot_exe"])

                    else:

                        append_log(log_path, f"ERRO: godot_exe inválido: {cfg['godot_exe']}")

                        current = read_json(status_path)

                        current["error"] = f"Godot não encontrado: {cfg['godot_exe']}"

                        current["updated_at"] = int(time.time())

                        write_json(status_path, current)

                        raise FileNotFoundError(f"Godot não encontrado: {cfg['godot_exe']}")



                user_dir = None

                if bool(cfg.get("isolate_user_dir", False)):

                    user_dir_path = spec.out_dir / "user"

                    ensure_dir(user_dir_path)

                    user_dir = str(user_dir_path)



                rules = load_match_rules(project_root, cfg)

                godot_cmd = build_godot_cmd(

                    project_root,

                    godot_exe,

                    spec.port,

                    float(cfg["time_scale"]),

                    float(cfg["quit_idle"]),

                    int(cfg["fixed_fps"]),

                    int(rules.get("max_steps", 0)),

                    float(rules.get("max_seconds", 0.0)),

                    int(rules.get("max_kills", 0)),

                    user_dir=user_dir,

                    extra_user_args=(cfg.get("godot_user_args") if isinstance(cfg.get("godot_user_args"), list) else None),

                )



                generations = int(cfg["generations"])

                episodes_per_genome = int(cfg["episodes_per_genome"])

                population = int(cfg.get("population", 1))

                elite = int(cfg.get("elite", 1))

                mutation_rate = float(cfg["mutation_rate"])

                mutation_std = float(cfg["mutation_std"])

                crossover = bool(cfg.get("crossover", False))

                sweep_bonus = float(cfg.get("sweep_bonus", 0.0))

                if outer_ga:

                    generations = 1

                    population = 1

                    elite = 1

                    mutation_rate = 0.0

                    mutation_std = 0.0

                    crossover = False

                    sweep_bonus = 0.0

                trainer_cmd = build_trainer_cmd(

                    project_root,

                    resolve_path(project_root, cfg["python_exe"]),

                    spec.port,

                    resolve_path(project_root, spec.seed_path),

                    str(spec.out_dir / "best.json"),

                    str(spec.out_dir / "genetic_log.csv"),

                    str(spec.out_dir / "result.json"),

                    int(generations),

                    int(episodes_per_genome),

                    int(population),

                    int(elite),

                    float(mutation_rate),

                    float(mutation_std),

                    float(cfg.get("win_weight", 0.6)),

                    float(cfg.get("reward_scale", 20.0)),

                    bool(crossover),

                    float(sweep_bonus),

                    str(cfg["opponent"]),

                    resolve_path(project_root, str(cfg.get("opponent_load_path", ""))),

                    _resolve_opponent_pool(project_root, cfg),

                    str(cfg.get("opponent_pool_mode", "round_robin")),

                    float(cfg["time_scale"]),

                    int(cfg["connect_retries"]),

                    float(cfg["connect_wait"]),

                    float(cfg.get("connect_timeout", 2.0)),

                    float(cfg.get("idle_timeout", 30.0)),

                    bool(cfg.get("quiet", True)),

                    bool(cfg.get("learn_aim", False)),

                    int(cfg.get("aim_bins", 9)),

                )



                if bool(cfg.get("trainer_live_rounds", False)):

                    trainer_cmd.append("--live-rounds")

                if bool(cfg.get("trainer_pretty_md9", False)):

                    opp_tag = str(cfg.get("opponent_tag", cfg.get("opponent", "")))

                    ind = int(base_individual + (spec.worker_id + 1))

                    trainer_cmd.extend(

                        [

                            "--pretty-md9",

                            "--match-title",

                            f"G{int(generation_global)} N{ind} vs {opp_tag}",

                        ]

                    )



                if dry_run:

                    print("[dry-run] GODOT:", " ".join(godot_cmd))

                    print("[dry-run] TRAIN:", " ".join(trainer_cmd))

                    completed += 1

                    continue



                try:

                    godot_log_path = spec.out_dir / "godot.log"

                    trainer_log_path = spec.out_dir / "trainer.log"

                    godot_log = open(godot_log_path, "w", encoding="utf-8", errors="ignore")

                    trainer_log = open(trainer_log_path, "w", encoding="utf-8", errors="ignore")



                    if float(cfg.get("spawn_delay_sec", 0.0)) > 0:

                        time.sleep(float(cfg.get("spawn_delay_sec", 0.0)))



                    godot_proc = subprocess.Popen(godot_cmd, stdout=godot_log, stderr=godot_log)



                    early_grace = max(0.0, float(cfg.get("early_godot_exit_grace_sec", 0.0)))

                    if early_grace > 0.0:

                        time.sleep(early_grace)



                    if godot_proc.poll() is not None:

                        exit_code = int(godot_proc.poll() or 0)

                        try:

                            godot_log.close()

                        except Exception:

                            pass

                        try:

                            trainer_log.close()

                        except Exception:

                            pass

                        failure = _summarize_worker_failure(spec.out_dir)

                        append_log(

                            log_path,

                            f"worker {spec.worker_id} godot exited early (attempt {spec.attempt}) | code={exit_code} | port={spec.port}",

                        )

                        write_json(

                            spec.out_dir / "result.json",

                            {

                                "ok": False,

                                "exit_code": exit_code,

                                "error": "Godot exited early",

                                "details": failure,

                                "port": int(spec.port),

                                "attempt": int(spec.attempt),

                                "timestamp": int(time.time()),

                            },

                        )

                        max_attempts = int(cfg.get("max_attempts_per_worker", 1))

                        if spec.attempt + 1 < max_attempts:

                            queue.append(

                                WorkerSpec(

                                    worker_id=spec.worker_id,

                                    port=spec.port + (workers + 10),

                                    seed_path=spec.seed_path,

                                    out_dir=spec.out_dir,

                                    attempt=spec.attempt + 1,

                                )

                            )

                        else:

                            completed += 1

                        continue



                    trainer_proc = subprocess.Popen(trainer_cmd, stdout=trainer_log, stderr=trainer_log)

                    running.append(

                        WorkerRun(

                            spec=spec,

                            godot_proc=godot_proc,

                            trainer_proc=trainer_proc,

                            godot_log=godot_log,

                            trainer_log=trainer_log,

                            started_at=time.time(),

                        )

                    )

                except FileNotFoundError as exc:

                    completed += 1

                    append_log(log_path, f"worker {spec.worker_id} spawn fail: {exc}")

                    write_json(

                        spec.out_dir / "result.json",

                        {

                            "ok": False,

                            "exit_code": 127,

                            "error": str(exc),

                            "port": int(spec.port),

                            "timestamp": int(time.time()),

                        },

                    )

                except OSError as exc:

                    completed += 1

                    append_log(log_path, f"worker {spec.worker_id} spawn os error: {exc}")

                    write_json(

                        spec.out_dir / "result.json",

                        {

                            "ok": False,

                            "exit_code": 126,

                            "error": str(exc),

                            "port": int(spec.port),

                            "timestamp": int(time.time()),

                        },

                    )



            now = time.time()

            if now - last_status_write >= 0.5:

                current = read_json(status_path)

                current.update(

                    {

                        "round": int(round_index),

                        "workers": int(workers),

                        "completed": int(completed),

                        "running": int(len(running)),

                        "queued": int(len(queue)),

                        "best_so_far": float(best_so_far) if best_so_far is not None else None,

                        "elapsed_sec": float(now - started),

                        "eta_sec": 0.0,

                        "concurrency": int(concurrency),

                        "updated_at": int(time.time()),

                    }

                )

                write_json(status_path, current)

                last_status_write = now



            if dry_run:

                break



            time.sleep(0.05)

            still_running: List[WorkerRun] = []

            for run in running:

                trainer_done = run.trainer_proc.poll() is not None

                if not trainer_done:

                    still_running.append(run)

                    continue



                result_payload = read_json(run.spec.out_dir / "result.json")

                if result_payload:

                    score = _primary_total_score(result_payload)

                    sweep = _is_sweep_5_0(result_payload)

                    prev_best = best_so_far

                    prev_sweep = best_sweep

                    if best_so_far is None:

                        best_so_far = score

                        best_sweep = bool(sweep)

                    else:

                        if (bool(sweep) and not best_sweep) or (bool(sweep) == best_sweep and score > float(best_so_far)):

                            best_so_far = score

                            best_sweep = bool(sweep)



                    if bool(result_payload.get("ok", False)):

                        gen_end = int(result_payload.get("generation", 0))

                        is_new_best = (

                            prev_best is None

                            or (bool(sweep) and not bool(prev_sweep))

                            or (bool(sweep) == bool(prev_sweep) and score > float(prev_best) + 1e-9)

                        )

                        if is_new_best:

                            global_n = int(base_individual + (run.spec.worker_id + 1))

                            msg = (

                                f"\nIslandsRound {round_index} | NEW BEST ScoreTot {score:.2f} | "

                                f"G{generation_global} N{global_n} | wid {run.spec.worker_id} | gen_end {gen_end}\n"

                            )

                            sys.stdout.write(_c(msg, ANSI_GREEN, color_enabled))

                            sys.stdout.flush()



                        opp_tag = str(cfg.get("opponent_tag", cfg.get("opponent", "")))



                        best_stats = result_payload.get("best_stats") if isinstance(result_payload, dict) else None

                        if not isinstance(best_stats, dict):

                            best_stats = {}

                        last_round = best_stats.get("last_round") if isinstance(best_stats.get("last_round"), dict) else {}

                        match_score = last_round.get("match_score") if isinstance(last_round.get("match_score"), dict) else {}

                        kills = last_round.get("kills") if isinstance(last_round.get("kills"), dict) else {}

                        wins = last_round.get("wins") if isinstance(last_round.get("wins"), dict) else {}



                        w = int(last_round.get("winner", result_payload.get("last_winner", 0))) if isinstance(result_payload, dict) else 0

                        s1 = float(match_score.get(1, match_score.get("1", result_payload.get("best_score_p1", 0.0))))

                        s2 = float(match_score.get(2, match_score.get("2", result_payload.get("best_score_p2", 0.0))))

                        k1 = int(kills.get(1, kills.get("1", result_payload.get("best_kills_p1", 0))))

                        k2 = int(kills.get(2, kills.get("2", result_payload.get("best_kills_p2", 0))))



                        w1 = int(wins.get(1, wins.get("1", 0)))

                        w2 = int(wins.get(2, wins.get("2", 0)))

                        rounds_played = max(1, w1 + w2)

                        avg1 = s1 / rounds_played



                        winner_label = "P1" if w == 1 else ("P2" if w == 2 else "?")

                        sys.stdout.write(

                            "R%d G%d N%d vs %s | W=%s | ScoreTot=%.2f | ScoreAvg=%.2f | OppTot=%.2f | K=%d-%d | Rounds=%d-%d\n"

                            % (

                                int(round_index),

                                int(generation_global),

                                int(base_individual + (run.spec.worker_id + 1)),

                                opp_tag,

                                winner_label,

                                s1,

                                avg1,

                                s2,

                                k1,

                                k2,

                                w1,

                                w2,

                            )

                        )

                        sys.stdout.flush()



                if run.godot_proc.poll() is None:

                    graceful_wait = max(0.0, float(cfg.get("godot_shutdown_wait_sec", 0.0)))

                    if graceful_wait > 0.0:

                        deadline = time.time() + graceful_wait

                        while time.time() < deadline and run.godot_proc.poll() is None:

                            time.sleep(0.05)

                    if run.godot_proc.poll() is None:

                        try:

                            run.godot_proc.terminate()

                        except OSError:

                            pass



                try:

                    exit_code = int(run.trainer_proc.poll() or 0)

                except Exception:

                    exit_code = 0

                max_attempts = int(cfg.get("max_attempts_per_worker", 1))

                should_retry = exit_code != 0 and (run.spec.attempt + 1) < max_attempts

                if should_retry:

                    queue.append(

                        WorkerSpec(

                            worker_id=run.spec.worker_id,

                            port=run.spec.port + (workers + 10),

                            seed_path=run.spec.seed_path,

                            out_dir=run.spec.out_dir,

                            attempt=run.spec.attempt + 1,

                        )

                    )

                else:

                    completed += 1



                if exit_code != 0:

                    failure = _summarize_worker_failure(run.spec.out_dir)

                    if failure:

                        append_log(

                            log_path,

                            f"worker {run.spec.worker_id} trainer exit={exit_code} attempt={run.spec.attempt} port={run.spec.port}\n{failure}",

                        )



                try:

                    run.godot_log.close()

                except Exception:

                    pass

                try:

                    run.trainer_log.close()

                except Exception:

                    pass



            running = still_running

            now = time.time()

            elapsed = now - started

            rate = completed / elapsed if elapsed > 0 else 0.0

            remaining = max(0, workers - completed)

            eta = remaining / rate if rate > 0 else 0.0

            if int(now) % 1 == 0:

                if best_so_far is None:

                    best_text = "N/A"

                else:

                    tag = "SWEEP" if best_sweep else ""

                    best_text = f"{tag}{best_so_far:.2f}" if tag else f"{best_so_far:.2f}"

                sys.stdout.write(

                    f"\rIslandsRound {round_index} | done {completed}/{workers} | running {len(running)} | queued {len(queue)} | "

                    f"best {best_text} | elapsed {elapsed:0.0f}s"

                )

                sys.stdout.flush()



            if now - last_status_write >= 0.5:

                current = read_json(status_path)

                sample = {}

                if running:

                    running_wids = {int(r.spec.worker_id) for r in running}

                    if live_sample_wid is None or live_sample_wid not in running_wids:

                        live_sample_wid = min(running_wids)



                    sample_run = next((r for r in running if int(r.spec.worker_id) == int(live_sample_wid)), running[0])

                    trainer_tail = _tail_text(sample_run.spec.out_dir / "trainer.log", limit=20)

                    sample = {

                        "worker_id": int(sample_run.spec.worker_id),

                        "port": int(sample_run.spec.port),

                        "age_sec": float(now - float(sample_run.started_at)),

                        "godot_tail": _tail_text(sample_run.spec.out_dir / "godot.log", limit=8),

                        "trainer_tail": "\n".join(trainer_tail.splitlines()[-8:]) if trainer_tail else "",

                    }

                    if live_round_logs:

                        wid = int(sample_run.spec.worker_id)

                        log_file = sample_run.spec.out_dir / "trainer.log"

                        last_pos = int(trainer_log_pos_by_worker.get(wid, 0))

                        new_pos, new_lines = _read_new_lines(log_file, last_pos)

                        trainer_log_pos_by_worker[wid] = int(new_pos)



                        for line in new_lines:

                            if line.startswith("MD9:"):

                                sys.stdout.write("\n" + line[4:].lstrip() + "\n")

                                sys.stdout.flush()

                                continue

                            if line.startswith("[ROUND]") or line.startswith("[MATCH]"):

                                prev = last_live_by_worker.get(wid, "")

                                if line != prev:

                                    ind = int(base_individual + (wid + 1))

                                    sys.stdout.write(

                                        f"\n[G{int(generation_global)} N{ind} wid {wid}] {line}\n"

                                    )

                                    sys.stdout.flush()

                                    last_live_by_worker[wid] = line

                current.update(

                    {

                        "round": int(round_index),

                        "workers": int(workers),

                        "completed": int(completed),

                        "running": int(len(running)),

                        "queued": int(len(queue)),

                        "best_so_far": float(best_so_far) if best_so_far is not None else None,

                        "elapsed_sec": float(elapsed),

                        "eta_sec": float(eta),

                        "concurrency": int(concurrency),

                        "updated_at": int(time.time()),

                        "sample": sample,

                    }

                )

                write_json(status_path, current)

                last_status_write = now



    except KeyboardInterrupt:



        try:

            if bool(cfg.get("promote_on_interrupt", True)):

                partial = collect_results(round_dir, workers)

                if partial:

                    score, genome_path, payload = partial[0]

                    best_payload: Dict = dict(payload) if isinstance(payload, dict) else {}

                    best_payload["score"] = float(score)

                    summary = {

                        "round": int(round_index),

                        "generation_global": int(generation_global),

                        "base_individual": int(base_individual),

                        "best": float(score),

                        "top": [str(genome_path)],

                        "best_payload": best_payload,

                        "interrupted": True,

                    }

                    write_json(round_dir / "summary_interrupted.json", summary)

                    write_json(state_dir / "last_summary_interrupted.json", summary)

                    promote_best_genome(project_root, cfg, summary)

        except Exception:

            pass



        append_log(log_path, f"IslandsRound {round_index} interrupted")

        for run in running:

            try:

                write_json(

                    run.spec.out_dir / "result.json",

                    {

                        "ok": False,

                        "exit_code": 130,

                        "error": "Interrupted",

                        "port": int(run.spec.port),

                        "attempt": int(run.spec.attempt),

                        "timestamp": int(time.time()),

                    },

                )

            except Exception:

                pass

            if run.trainer_proc.poll() is None:

                try:

                    run.trainer_proc.terminate()

                except OSError:

                    pass

            if run.godot_proc.poll() is None:

                try:

                    run.godot_proc.terminate()

                except OSError:

                    pass

            try:

                run.godot_log.close()

            except Exception:

                pass

            try:

                run.trainer_log.close()

            except Exception:

                pass

        raise



    if not dry_run:

        sys.stdout.write("\n")

        sys.stdout.flush()



    results = collect_results(round_dir, workers)

    if bool(cfg.get("prefer_winner_selection", True)):

        winners = [r for r in results if int(r[2].get("best_winner", 0)) == 1]

        losers = [r for r in results if int(r[2].get("best_winner", 0)) != 1]

        winners.sort(key=lambda x: x[0], reverse=True)

        losers.sort(key=lambda x: x[0], reverse=True)

        results = winners + losers



    individuals_dir = round_dir / "individuals"

    ensure_dir(individuals_dir)

    for score, genome_path, payload in results:

        try:

            wid = int(payload.get("worker_id", 0))

        except Exception:

            wid = 0

        global_n = int(base_individual + (wid + 1))

        payload["islands_round"] = int(round_index)

        payload["generation_global"] = int(generation_global)

        payload["individual"] = int(global_n)

        record = dict(payload)

        record.update({"score": float(score), "generation": int(generation_global), "individual": int(global_n)})

        out_name = f"G{generation_global:04d}_N{global_n:06d}_R{round_index:04d}_wid{wid:03d}_score_{score:.6f}.json"

        write_json(individuals_dir / out_name, record)

    topk = max(1, int(cfg["topk"]))

    top_dir = round_dir / "top"

    ensure_dir(top_dir)

    next_seeds: List[str] = []

    for idx, (score, genome_path, payload) in enumerate(results[:topk]):

        try:

            wid = int(payload.get("worker_id", 0))

        except Exception:

            wid = 0

        global_n = int(base_individual + (wid + 1))

        target = top_dir / f"seed_{idx+1:02d}_G{generation_global:04d}_N{global_n:06d}_score_{score:.6f}.json"

        if genome_path.exists():

            shutil.copyfile(genome_path, target)

            next_seeds.append(str(target))



    if results:

        best_payload = results[0][2]

        try:

            best_n = int(base_individual + (int(best_payload.get("worker_id", 0)) + 1))

            sweep_txt = " SWEEP(5-0)" if bool(best_payload.get("sweep_5_0", False)) else ""

            print(

                "IslandsRound %d | Melhor atual: G%d N%d | worker %d | best_score_total %.2f%s"

                % (

                    int(round_index),

                    int(generation_global),

                    int(best_n),

                    int(best_payload.get("worker_id", -1)),

                    float(results[0][0]),

                    sweep_txt,

                )

            )

        except Exception:

            pass



    best_payload: Dict = {}

    if results:

        best_payload = dict(results[0][2]) if isinstance(results[0][2], dict) else {}

        best_payload["score"] = float(results[0][0])

        try:

            best_payload["generation_global"] = int(generation_global)

            best_payload["individual"] = int(base_individual + (int(best_payload.get("worker_id", 0)) + 1))

        except Exception:

            pass

    summary = {

        "round": int(round_index),

        "generation_global": int(generation_global),

        "base_individual": int(base_individual),

        "best": float(results[0][0]) if results else 0.0,

        "top": next_seeds,

        "best_payload": best_payload,

    }

    write_json(round_dir / "summary.json", summary)

    write_json(state_dir / "last_summary.json", summary)

    promote_best_genome(project_root, cfg, summary)



    try:

        opp_tag = str(cfg.get("opponent_tag", cfg.get("opponent", "")))

        champion_n = int(best_payload.get("individual", -1))

        champion_wid = int(best_payload.get("worker_id", -1))

        champion_score = float(summary.get("best", 0.0))

        seed_info = str(next_seeds[0]) if next_seeds else ""

        print(

            "Resumo IslandsRound %d | campeão=G%d N%d (wid=%d, score=%.4f) | vs %s"

            % (int(round_index), int(generation_global), int(champion_n), int(champion_wid), champion_score, opp_tag)

        )

        if seed_info:

            print(f"Seed líder (vai gerar próximos rounds): {seed_info}")

        if next_seeds:

            print(f"Seeds geradas para próximo round: {len(next_seeds)} (topk)")

    except Exception:

        pass



    append_log(log_path, f"IslandsRound {round_index} end | best={summary['best']:.6f} | top={len(next_seeds)}")

    return next_seeds





def run_islands(project_root: Path, cfg: Dict, dry_run: bool) -> int:

    rounds = int(cfg["rounds"])

    state_dir = Path(resolve_path(project_root, cfg["state_dir"]))

    last_summary_path = state_dir / "last_summary.json"



    progress_path_cfg = resolve_path(project_root, str(cfg.get("progress_path", "")))

    progress_path = Path(progress_path_cfg) if progress_path_cfg else (state_dir / "progress.json")

    progress_exists = progress_path.exists()

    progress = _load_progress(progress_path)

    generation_global = int(progress.get("next_generation", 1))

    base_individual = int(progress.get("next_individual", 0))



    seeds: List[str] = []

    round_index = 1



    if last_summary_path.exists():

        last = read_json(last_summary_path)

        top = last.get("top") if isinstance(last, dict) else None

        if isinstance(top, list) and top:

            seeds = [resolve_path(project_root, str(p)) for p in top]

            try:

                round_index = int(last.get("round", 0)) + 1

            except Exception:

                round_index = 1



        if not progress_exists:

            try:

                last_round = int(last.get("round", 0))

                if last_round > 0:

                    generation_global = max(1, last_round + 1)

                    base_individual = max(0, last_round * int(cfg["workers"]))

                    _save_progress(progress_path, generation_global, base_individual)

                    progress_exists = True

            except Exception:

                pass



    if not seeds:

        initial_seed = resolve_path(project_root, cfg.get("initial_seed", ""))

        seeds = [initial_seed] if initial_seed else []

    while rounds <= 0 or round_index <= rounds:

        if not seeds:

            print("Sem seed inicial. Configure initial_seed.")

            return 3

        print(

            f"=== IslandsRound {round_index} | G{generation_global} | seeds {len(seeds)} | workers {cfg['workers']} | topk {cfg['topk']} ==="

        )

        seeds = run_round(

            project_root,

            cfg,

            round_index,

            generation_global,

            base_individual,

            seeds,

            dry_run=dry_run,

        )

        if dry_run:

            break

        if not seeds:

            print("IslandsRound terminou sem seeds geradas (nenhum result.json encontrado).")

            return 4



        base_individual += int(cfg["workers"])

        generation_global += 1

        _save_progress(progress_path, generation_global, base_individual)

        round_index += 1

    return 0





def interactive_menu(project_root: Path, cfg_path: str) -> int:

    cfg_file = Path(resolve_path(project_root, cfg_path))

    cfg = merge_config(default_config(project_root), load_config(project_root, cfg_path))

    while True:

        print("\n=== Orquestrador (ilhas/headless) ===")

        print(f"Config: {cfg_file}")

        print(f"godot_exe: {cfg['godot_exe']}")

        print(f"workers: {cfg['workers']} | topk: {cfg['topk']} | rounds: {cfg['rounds']} | concurrency: {cfg['concurrency']}")

        print(f"generations: {cfg['generations']} | episodes_per_genome: {cfg['episodes_per_genome']} | opponent: {cfg['opponent']}")

        print("1) Editar godot_exe")

        print("2) Editar workers/topk/rounds/concurrency")

        print("3) Rodar (dry-run)")

        print("4) Rodar (real)")

        print("5) Salvar config")

        print("0) Sair")



        choice = input("> ").strip()

        if choice == "0":

            return 0

        if choice == "1":

            cfg["godot_exe"] = input("godot_exe: ").strip() or cfg["godot_exe"]

            continue

        if choice == "2":

            cfg["workers"] = int(input("workers: ").strip() or cfg["workers"])

            cfg["topk"] = int(input("topk: ").strip() or cfg["topk"])

            cfg["rounds"] = int(input("rounds (0=infinito): ").strip() or cfg["rounds"])

            cfg["concurrency"] = int(input("concurrency: ").strip() or cfg["concurrency"])

            continue

        if choice == "3":

            run_islands(project_root, cfg, dry_run=True)

            continue

        if choice == "4":

            try:

                return run_islands(project_root, cfg, dry_run=False)

            except KeyboardInterrupt:

                print("\nInterrompido.")

                return 130

        if choice == "5":

            write_json(cfg_file, cfg)

            print(f"Salvo: {cfg_file}")

            continue





def main() -> int:

    project_root = Path(__file__).resolve().parents[1]

    parser = argparse.ArgumentParser(description="Orquestrador de ilhas headless para Project PVP")

    parser.add_argument("mode", choices=("run", "menu"))

    parser.add_argument("--config", default="BOTS/IA/config/islands.json")
    parser.add_argument("--dry-run", action="store_true")

    args = parser.parse_args()



    if args.mode == "menu":

        return interactive_menu(project_root, args.config)



    cfg = merge_config(default_config(project_root), load_config(project_root, args.config))

    try:

        return run_islands(project_root, cfg, dry_run=bool(args.dry_run))

    except FileNotFoundError as exc:

        print(str(exc))

        return 2

    except KeyboardInterrupt:

        print("Interrompido.")

        return 130





if __name__ == "__main__":

    raise SystemExit(main())



