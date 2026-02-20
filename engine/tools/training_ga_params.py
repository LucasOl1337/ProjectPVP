from __future__ import annotations

import argparse
import json
import math
import os
import random
import select
import socket
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from ga_params_schema_v1 import clamp_genes, defaults_v1, distance, merge_handmade_into_defaults, schema_v1


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _resolve_path(project_root: Path, path: str) -> str:
    raw = str(path or "").strip()
    if not raw:
        return ""
    if raw.startswith("res://"):
        rel = raw.replace("res://", "", 1).lstrip("/").replace("\\", "/")
        return str((project_root / rel).resolve())
    if raw.startswith("user://"):
        rel = raw.replace("user://", "", 1).lstrip("/").replace("\\", "/")
        return str((project_root / ".user" / rel).resolve())
    return str(Path(raw).expanduser().resolve())


def read_json(path: str) -> Dict[str, Any]:
    try:
        p = Path(path)
        if not p.exists():
            return {}
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}


def write_json(path: str, payload: Dict[str, Any]) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def to_vec2(value: Any) -> Tuple[float, float]:
    if isinstance(value, dict) and "x" in value and "y" in value:
        return float(value["x"]), float(value["y"])
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        return float(value[0]), float(value[1])
    return 0.0, 0.0


def _bool(value: Any) -> float:
    return 1.0 if bool(value) else 0.0


def compute_aim(obs: Dict[str, Any]) -> Tuple[float, float]:
    dx, dy = to_vec2(obs.get("delta_position", [0.0, 0.0]))
    d = math.hypot(dx, dy)
    if d > 0:
        return dx / d, dy / d
    return 1.0, 0.0


@dataclass
class ParamGenome:
    genes: Dict[str, Any]
    meta: Dict[str, Any]
    mutation_steps: int = 0

    shoot_hold_remaining: float = 0.0
    shoot_cooldown_remaining: float = 0.0
    shoot_release_frame: bool = False
    dash_cooldown_remaining: float = 0.0
    jump_cooldown_remaining: float = 0.0
    melee_cooldown_remaining: float = 0.0
    last_jump_intent: bool = False
    last_melee_intent: bool = False

    def reset_controls(self) -> None:
        self.shoot_hold_remaining = 0.0
        self.shoot_cooldown_remaining = 0.0
        self.shoot_release_frame = False
        self.dash_cooldown_remaining = 0.0
        self.jump_cooldown_remaining = 0.0
        self.melee_cooldown_remaining = 0.0
        self.last_jump_intent = False
        self.last_melee_intent = False

    def clone(self) -> "ParamGenome":
        g = ParamGenome(dict(self.genes), dict(self.meta), int(self.mutation_steps))
        return g

    def mutate(self, rng: random.Random, mutation_rate: float, mutation_std: float) -> None:
        if mutation_rate <= 0.0:
            return
        spec = schema_v1()
        for key, s in spec.items():
            if rng.random() >= mutation_rate:
                continue
            if s.type == "bool":
                self.genes[key] = not bool(self.genes.get(key, defaults_v1().get(key, False)))
                continue
            base = float(self.genes.get(key, defaults_v1().get(key, 0.0)))
            std = float(s.mut_std if s.mut_std is not None else mutation_std)
            val = base + float(rng.gauss(0.0, std))
            if s.min is not None:
                val = max(float(s.min), val)
            if s.max is not None:
                val = min(float(s.max), val)
            self.genes[key] = val
        self.genes = clamp_genes(self.genes)
        self.mutation_steps += 1

    @staticmethod
    def crossover(rng: random.Random, a: "ParamGenome", b: "ParamGenome") -> "ParamGenome":
        spec = schema_v1()
        out: Dict[str, Any] = {}
        for key, s in spec.items():
            if s.type == "bool":
                out[key] = bool(a.genes.get(key, False)) if rng.random() < 0.5 else bool(b.genes.get(key, False))
                continue
            av = float(a.genes.get(key, defaults_v1().get(key, 0.0)))
            bv = float(b.genes.get(key, defaults_v1().get(key, 0.0)))
            alpha = float(rng.random())
            val = alpha * av + (1.0 - alpha) * bv
            if s.min is not None:
                val = max(float(s.min), val)
            if s.max is not None:
                val = min(float(s.max), val)
            out[key] = val
        child = ParamGenome(clamp_genes(out), {"created_from": "crossover"}, mutation_steps=max(a.mutation_steps, b.mutation_steps))
        return child

    def to_dict(self) -> Dict[str, Any]:
        return {
            "genome_version": 1,
            "schema_id": "ga_params_v1",
            "genes": dict(self.genes),
            "meta": {"mutation_steps": int(self.mutation_steps), **dict(self.meta)},
        }

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "ParamGenome":
        genes = payload.get("genes", {}) if isinstance(payload.get("genes"), dict) else {}
        meta = payload.get("meta", {}) if isinstance(payload.get("meta"), dict) else {}
        mutation_steps = int(meta.get("mutation_steps", 0))
        g = cls(clamp_genes(genes), dict(meta), mutation_steps=mutation_steps)
        return g

    @classmethod
    def seed_from_handmade(cls, handmade_payload: Dict[str, Any]) -> "ParamGenome":
        genes = merge_handmade_into_defaults(handmade_payload)
        return cls(dict(genes), {"created_from": "handmade"}, mutation_steps=0)

    def act(self, obs: Dict[str, Any], rng: random.Random, dt: float) -> Dict[str, Any]:
        self_state = obs.get("self", {}) if isinstance(obs.get("self"), dict) else {}
        match_state = obs.get("match", {}) if isinstance(obs.get("match"), dict) else {}
        if bool(self_state.get("is_dead", False)) or ("round_active" in match_state and not bool(match_state.get("round_active"))):
            aim_x, aim_y = compute_aim(obs)
            return {
                "axis": 0.0,
                "aim": [aim_x, aim_y],
                "jump_pressed": False,
                "shoot_pressed": False,
                "shoot_is_pressed": False,
                "melee_pressed": False,
                "ult_pressed": False,
                "dash_pressed": [],
                "actions": {"left": False, "right": False, "up": False, "down": False},
            }

        dt = float(dt or 0.0)
        self.shoot_cooldown_remaining = max(0.0, self.shoot_cooldown_remaining - dt)
        self.dash_cooldown_remaining = max(0.0, self.dash_cooldown_remaining - dt)
        self.jump_cooldown_remaining = max(0.0, self.jump_cooldown_remaining - dt)
        self.melee_cooldown_remaining = max(0.0, self.melee_cooldown_remaining - dt)

        dx, dy = to_vec2(obs.get("delta_position", [0.0, 0.0]))
        abs_dx = abs(dx)
        abs_dy = abs(dy)
        distance_v = math.hypot(dx, dy)
        facing = int(self_state.get("facing", 1) or 1)
        arrows = int(self_state.get("arrows", 0) or 0)
        sensors = self_state.get("sensors", {}) if isinstance(self_state.get("sensors"), dict) else {}
        sensor_wall_ahead = bool(sensors.get("wall_ahead", False))
        sensor_ledge_ahead = bool(sensors.get("ledge_ahead", False))
        sensor_front_wall_distance = float(sensors.get("front_wall_distance", float("inf")) or float("inf"))
        sensor_ground_distance = float(sensors.get("ground_distance", float("inf")) or float("inf"))
        sensor_ceiling_distance = float(sensors.get("ceiling_distance", float("inf")) or float("inf"))
        sensor_ledge_ground_distance = float(sensors.get("ledge_ground_distance", float("inf")) or float("inf"))

        keep_distance = float(self.genes["movement.keep_distance"])
        backoff_ratio = float(self.genes["movement.backoff_ratio"])
        deadzone_x = float(self.genes["movement.approach_deadzone_x"])
        backoff_threshold = keep_distance * backoff_ratio

        axis = 0.0
        if abs_dx > max(deadzone_x, keep_distance):
            axis = 1.0 if dx > 0 else -1.0
        elif abs_dx < backoff_threshold:
            if abs_dx < max(2.0, deadzone_x):
                axis = -float(facing)
            else:
                axis = -1.0 if dx > 0 else 1.0

        avoid_ledges = bool(self.genes["safety.avoid_ledges"])
        avoid_walls = bool(self.genes["safety.avoid_walls"])
        wall_stop_distance = float(self.genes["safety.wall_stop_distance"])
        max_safe_drop_distance = float(self.genes["safety.max_safe_drop_distance"])
        ceiling_block_distance = float(self.genes["safety.ceiling_block_distance"])
        air_ground_distance = float(self.genes["safety.air_ground_distance"])
        is_airborne_by_sensor = sensor_ground_distance > air_ground_distance
        if axis != 0.0:
            moving_dir = 1 if axis > 0 else -1
            if moving_dir == facing:
                if avoid_ledges and sensor_ledge_ahead:
                    axis = 0.0
                if avoid_ledges and (not sensor_ledge_ahead) and sensor_ledge_ground_distance > max_safe_drop_distance:
                    axis = 0.0
                if avoid_walls and sensor_wall_ahead:
                    axis = 0.0
                if avoid_walls and sensor_front_wall_distance < wall_stop_distance:
                    axis = 0.0

        aim_x, aim_y = compute_aim(obs)

        shoot_min = float(self.genes["shoot.min_distance"])
        shoot_max = float(self.genes["shoot.max_distance"])
        shoot_y_tol = float(self.genes["shoot.y_tolerance"])
        shoot_dx_min = float(self.genes["shoot.dx_min"])
        want_shoot_window = arrows > 0 and (distance_v > shoot_min) and (distance_v < shoot_max) and (abs_dx > shoot_dx_min) and (abs_dy < shoot_y_tol)

        melee_range = float(self.genes["melee.range"])
        melee_intent_cd = float(self.genes["melee.intent_cooldown"])
        melee_intent = distance_v < melee_range and self.melee_cooldown_remaining <= 0.0

        jump_dy = float(self.genes["jump.chase_dy"])
        jump_intent_cd = float(self.genes["jump.intent_cooldown"])
        jump_intent = (dy < -jump_dy) and (abs_dx > 80.0) and self.jump_cooldown_remaining <= 0.0
        if sensor_ceiling_distance < ceiling_block_distance:
            jump_intent = False
        if is_airborne_by_sensor:
            jump_intent = False

        dash_use = bool(self.genes["dash.use"])
        dash_range = float(self.genes["dash.range"])
        dash_prob = float(self.genes["dash.probability"])
        dash_cd = float(self.genes["dash.intent_cooldown"])
        dash_intent = dash_use and (distance_v > dash_range) and (self.dash_cooldown_remaining <= 0.0) and (float(rng.random()) < dash_prob)
        if is_airborne_by_sensor:
            dash_intent = False

        if want_shoot_window:
            axis = 0.0
            melee_intent = False
            jump_intent = False
            dash_intent = False

        shoot_pressed = False
        shoot_is_pressed = False
        hold_seconds = float(self.genes["shoot.hold_seconds"])
        shoot_intent_cd = float(self.genes["shoot.intent_cooldown"])
        if self.shoot_release_frame:
            self.shoot_release_frame = False
            shoot_pressed = False
            shoot_is_pressed = False
        elif self.shoot_hold_remaining > 0.0:
            self.shoot_hold_remaining = max(0.0, self.shoot_hold_remaining - dt)
            shoot_is_pressed = True
            if self.shoot_hold_remaining <= 0.0:
                self.shoot_release_frame = True
                self.shoot_cooldown_remaining = max(self.shoot_cooldown_remaining, shoot_intent_cd)
        elif want_shoot_window and self.shoot_cooldown_remaining <= 0.0:
            self.shoot_hold_remaining = max(0.01, hold_seconds)
            shoot_pressed = True
            shoot_is_pressed = True

        melee_pressed = False
        if melee_intent and not self.last_melee_intent:
            melee_pressed = True
            self.melee_cooldown_remaining = max(self.melee_cooldown_remaining, melee_intent_cd)
        self.last_melee_intent = melee_intent

        jump_pressed = False
        if jump_intent and not self.last_jump_intent:
            jump_pressed = True
            self.jump_cooldown_remaining = max(self.jump_cooldown_remaining, jump_intent_cd)
        self.last_jump_intent = jump_intent

        dash_pressed = ["r1"] if dash_intent else []
        if dash_intent:
            self.dash_cooldown_remaining = max(self.dash_cooldown_remaining, dash_cd)

        return {
            "axis": float(axis),
            "aim": [float(aim_x), float(aim_y)],
            "jump_pressed": bool(jump_pressed),
            "shoot_pressed": bool(shoot_pressed),
            "shoot_is_pressed": bool(shoot_is_pressed),
            "melee_pressed": bool(melee_pressed),
            "ult_pressed": False,
            "dash_pressed": dash_pressed,
            "actions": {"left": axis < 0.0, "right": axis > 0.0, "up": False, "down": False},
        }


class ParamGATrainer:
    def __init__(
        self,
        rng: random.Random,
        population: int,
        elite: int,
        mutation_rate: float,
        mutation_std: float,
        episodes_per_genome: int,
        crossover: bool,
        win_weight: float,
        reward_scale: float,
        sweep_bonus: float,
        seed_genome: Optional[ParamGenome],
        min_diversity: float,
    ) -> None:
        self.rng = rng
        self.population_size = int(population)
        self.elite_size = max(1, min(int(elite), self.population_size))
        self.mutation_rate = float(mutation_rate)
        self.mutation_std = float(mutation_std)
        self.episodes_per_genome = max(1, int(episodes_per_genome))
        self.use_crossover = bool(crossover)
        self.win_weight = max(0.0, min(1.0, float(win_weight)))
        self.reward_scale = max(1e-9, float(reward_scale))
        self.sweep_bonus = float(sweep_bonus)
        self.min_diversity = max(0.0, float(min_diversity))

        if seed_genome is not None:
            seed_genome = seed_genome.clone()
            self.population: List[ParamGenome] = [seed_genome.clone()]
            for _ in range(self.population_size - 1):
                child = seed_genome.clone()
                child.mutate(self.rng, mutation_rate, mutation_std)
                self.population.append(child)
        else:
            self.population = [ParamGenome(dict(defaults_v1()), {"created_from": "default"}) for _ in range(self.population_size)]
            for g in self.population:
                g.mutate(self.rng, 1.0, mutation_std)

        self.fitness = [0.0 for _ in range(self.population_size)]
        self.episode_stats: List[Dict[str, Any]] = [{} for _ in range(self.population_size)]
        self.current_index = 0
        self.current_episode = 0
        self.current_score = 0.0
        self.generation = 1
        self.best_genome: Optional[ParamGenome] = seed_genome.clone() if seed_genome else None
        self.best_fitness = -float("inf")
        self.best_stats: Dict[str, Any] = {}
        self._wins = 0
        self._losses = 0
        self._start_generation()

    def _start_generation(self) -> None:
        self.current_index = 0
        self.current_episode = 0
        self.current_score = 0.0
        self._wins = 0
        self._losses = 0
        self.fitness = [0.0 for _ in range(self.population_size)]
        self.episode_stats = [{} for _ in range(self.population_size)]
        for g in self.population:
            g.reset_controls()

    def get_ga_state(self) -> Dict[str, Any]:
        safe_index = min(max(self.current_index, 0), max(0, self.population_size - 1))
        g = self.population[safe_index] if self.population else None
        return {
            "1": {
                "generation": int(self.generation),
                "individual": int(safe_index + 1),
                "population": int(self.population_size),
                "episode_in_individual": int(self.current_episode + 1),
                "episodes_per_genome": int(self.episodes_per_genome),
                "mutation_steps": int(g.mutation_steps) if g else 0,
                "mutation_rate": float(self.mutation_rate),
                "mutation_std": float(self.mutation_std),
            },
            "2": {"mode": "handmade"},
        }

    def _extract_match_score(self, metrics: Dict[str, Any], player_id: int = 1) -> float:
        if not isinstance(metrics, dict):
            return 0.0
        score_payload = metrics.get("last_match_score")
        if not isinstance(score_payload, dict):
            score_payload = metrics.get("match_score") if isinstance(metrics.get("match_score"), dict) else {}
        if not isinstance(score_payload, dict):
            return 0.0
        if player_id in score_payload:
            return float(score_payload[player_id])
        key = str(player_id)
        if key in score_payload:
            return float(score_payload[key])
        return 0.0

    def _extract_episode_reward(self, metrics: Dict[str, Any], player_id: int = 1) -> float:
        if not isinstance(metrics, dict):
            return 0.0
        score_payload = metrics.get("last_episode_reward")
        if not isinstance(score_payload, dict):
            score_payload = metrics.get("reward") if isinstance(metrics.get("reward"), dict) else {}
        if not isinstance(score_payload, dict):
            return 0.0
        if player_id in score_payload:
            return float(score_payload[player_id])
        key = str(player_id)
        if key in score_payload:
            return float(score_payload[key])
        return 0.0

    def step(self, obs: Dict[str, Any], metrics: Dict[str, Any], done: bool, dt: float) -> Tuple[Dict[str, Any], bool]:
        obs_p1 = obs.get("1", {}) if isinstance(obs.get("1"), dict) else {}
        action_p1 = self.population[self.current_index].act(obs_p1, self.rng, dt)

        advance = False
        if done:
            reward_p1 = self._extract_episode_reward(metrics, 1)
            score_p1 = self._extract_match_score(metrics, 1)
            if score_p1 == 0.0 and reward_p1 != 0.0:
                score_p1 = reward_p1
            self.current_score += float(score_p1)

            winner = 0
            last_round: Dict[str, Any] = {}
            evolution: Dict[str, Any] = {}
            if isinstance(metrics, dict):
                try:
                    winner = int(metrics.get("last_winner", 0))
                except Exception:
                    winner = 0
                last_round_obj = metrics.get("last_round")
                if isinstance(last_round_obj, dict):
                    last_round = dict(last_round_obj)
                evo_obj = metrics.get("evolution")
                if isinstance(evo_obj, dict):
                    evolution = dict(evo_obj)
            if winner == 1:
                self._wins += 1
            elif winner == 2:
                self._losses += 1

            self.current_episode += 1
            if self.current_episode >= self.episodes_per_genome:
                avg_score = self.current_score / float(self.episodes_per_genome)
                score_component = math.tanh(avg_score / self.reward_scale)
                win_component = float(self._wins - self._losses) / float(self.episodes_per_genome)
                composite = (1.0 - self.win_weight) * score_component + self.win_weight * win_component

                if self.sweep_bonus != 0.0 and isinstance(metrics, dict):
                    last_round_obj = metrics.get("last_round")
                    if isinstance(last_round_obj, dict):
                        wins_obj = last_round_obj.get("wins")
                        if isinstance(wins_obj, dict):
                            try:
                                w1 = int(wins_obj.get(1, wins_obj.get("1", 0)))
                                w2 = int(wins_obj.get(2, wins_obj.get("2", 0)))
                                if w1 == 5 and w2 == 0:
                                    composite += float(self.sweep_bonus)
                            except Exception:
                                pass

                self.fitness[self.current_index] = float(composite)
                self.episode_stats[self.current_index] = {
                    "wins": int(self._wins),
                    "losses": int(self._losses),
                    "avg_score": float(avg_score),
                    "fitness": float(composite),
                    "last_winner": int(winner),
                    "last_round": dict(last_round),
                    "evolution": dict(evolution),
                }

                best_eps = 1e-12
                composite_f = float(composite)
                best_f = float(self.best_fitness)
                best_avg = float(self.best_stats.get("avg_score", float("-inf"))) if isinstance(self.best_stats, dict) else float("-inf")
                update_best = False
                if composite_f > best_f + best_eps:
                    update_best = True
                elif abs(composite_f - best_f) <= best_eps and float(avg_score) > best_avg + 1e-6:
                    update_best = True
                if update_best:
                    self.best_fitness = composite_f
                    self.best_genome = self.population[self.current_index].clone()
                    self.best_stats = dict(self.episode_stats[self.current_index])

                self.current_index += 1
                self.current_episode = 0
                self.current_score = 0.0
                self._wins = 0
                self._losses = 0
                advance = True

        return action_p1, advance

    def _tournament_select_index(self, k: int = 3) -> int:
        if self.population_size <= 1:
            return 0
        k = max(2, min(int(k), self.population_size))
        candidates = [int(self.rng.randrange(self.population_size)) for _ in range(k)]
        best = int(candidates[0])
        best_fit = float(self.fitness[best])
        for i in candidates[1:]:
            fit = float(self.fitness[i])
            if fit > best_fit:
                best = i
                best_fit = fit
        return best

    def finalize_generation(self) -> Dict[str, float]:
        ranked = sorted(range(self.population_size), key=lambda i: self.fitness[i], reverse=True)
        best_idx = ranked[0]
        best_fit = float(self.fitness[best_idx])
        avg_fit = (float(sum(self.fitness)) / float(len(self.fitness))) if self.fitness else 0.0

        elites = [self.population[i].clone() for i in ranked[: self.elite_size]]
        new_pop: List[ParamGenome] = []
        new_pop.extend(elites)

        attempts = 0
        while len(new_pop) < self.population_size and attempts < self.population_size * 50:
            attempts += 1
            parent_a = self.population[self._tournament_select_index()]
            if self.use_crossover:
                parent_b = self.population[self._tournament_select_index()]
                child = ParamGenome.crossover(self.rng, parent_a, parent_b)
            else:
                child = parent_a.clone()
                child.meta = {"created_from": "mutation"}
            child.mutate(self.rng, self.mutation_rate, self.mutation_std)
            if self.min_diversity > 0.0:
                ok = True
                for existing in new_pop:
                    if distance(existing.genes, child.genes) < self.min_diversity:
                        ok = False
                        break
                if not ok:
                    continue
            new_pop.append(child)

        while len(new_pop) < self.population_size:
            g = ParamGenome(dict(defaults_v1()), {"created_from": "random"})
            g.mutate(self.rng, 1.0, self.mutation_std)
            new_pop.append(g)

        self.population = new_pop
        self.generation += 1
        self._start_generation()
        return {"best": best_fit, "avg": avg_fit, "best_ever": float(self.best_fitness)}


class JsonlBridgeClient:
    def __init__(self, host: str, port: int, connect_timeout: float) -> None:
        self.host = host
        self.port = int(port)
        self.connect_timeout = float(connect_timeout)
        self.sock: Optional[socket.socket] = None
        self._buffer = b""

    def connect(self) -> None:
        start = time.time()
        while True:
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(self.connect_timeout)
                s.connect((self.host, self.port))
                s.setblocking(False)
                self.sock = s
                return
            except Exception:
                if time.time() - start > self.connect_timeout:
                    raise
                time.sleep(0.05)

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except Exception:
                pass
        self.sock = None

    def send(self, payload: Dict[str, Any]) -> None:
        if self.sock is None:
            return
        line = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
        self.sock.sendall(line)

    def poll(self, timeout: float = 0.0) -> List[Dict[str, Any]]:
        if self.sock is None:
            return []
        r, _, _ = select.select([self.sock], [], [], timeout)
        if not r:
            return []
        try:
            data = self.sock.recv(65536)
        except Exception:
            return []
        if not data:
            return []
        self._buffer += data
        out: List[Dict[str, Any]] = []
        while b"\n" in self._buffer:
            line, self._buffer = self._buffer.split(b"\n", 1)
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line.decode("utf-8"))
                if isinstance(obj, dict):
                    out.append(obj)
            except Exception:
                continue
        return out


def main() -> int:
    project_root = repo_root()
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--no-watch", action="store_true")
    parser.add_argument("--time-scale", type=float, default=8.0)
    parser.add_argument("--fixed-dt", type=float, default=1.0 / 60.0)
    parser.add_argument("--population", type=int, default=8)
    parser.add_argument("--elite", type=int, default=2)
    parser.add_argument("--episodes-per-genome", type=int, default=3)
    parser.add_argument("--generations", type=int, default=0)
    parser.add_argument("--mutation-rate", type=float, default=0.10)
    parser.add_argument("--mutation-std", type=float, default=0.25)
    parser.add_argument("--win-weight", type=float, default=0.6)
    parser.add_argument("--reward-scale", type=float, default=20.0)
    parser.add_argument("--sweep-bonus", type=float, default=0.75)
    parser.add_argument("--crossover", action="store_true")
    parser.add_argument("--no-crossover", action="store_true")
    parser.add_argument("--connect-timeout", type=float, default=2.0)
    parser.add_argument("--connect-retries", type=int, default=300)
    parser.add_argument("--connect-wait", type=float, default=0.1)
    parser.add_argument("--idle-timeout", type=float, default=30.0)
    parser.add_argument("--save-path", default="")
    parser.add_argument("--result-path", default="")
    parser.add_argument("--log-path", default="")
    parser.add_argument("--load-path", default="")
    parser.add_argument("--handmade-config-path", default="")
    parser.add_argument("--min-diversity", type=float, default=0.0)
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--opponent", default="handmade")
    parser.add_argument("--opponent-load-path", default="")
    parser.add_argument("--opponent-pool-path", action="append", default=[])
    parser.add_argument("--opponent-pool-mode", default="round_robin")
    parser.add_argument("--learn-aim", action="store_true")
    parser.add_argument("--aim-bins", type=int, default=9)
    parser.add_argument("--live-rounds", action="store_true")
    parser.add_argument("--pretty-md9", action="store_true")
    parser.add_argument("--match-title", default="")
    args = parser.parse_args()

    use_crossover = bool(args.crossover) and not bool(args.no_crossover)
    rng = random.Random()

    handmade_cfg_path = _resolve_path(project_root, str(args.handmade_config_path or ""))
    handmade_payload = read_json(handmade_cfg_path) if handmade_cfg_path else {}

    seed_genome: Optional[ParamGenome] = None
    load_path = _resolve_path(project_root, str(args.load_path or ""))
    if load_path:
        payload = read_json(load_path)
        genes_payload = payload.get("genes") if isinstance(payload, dict) else None
        schema_id = str(payload.get("schema_id", "")) if isinstance(payload, dict) else ""
        if isinstance(genes_payload, dict) and genes_payload and (schema_id == "" or schema_id == "ga_params_v1"):
            seed_genome = ParamGenome.from_dict(payload)
    if seed_genome is None:
        seed_genome = ParamGenome.seed_from_handmade(handmade_payload)

    trainer = ParamGATrainer(
        rng=rng,
        population=int(args.population),
        elite=int(args.elite),
        mutation_rate=float(args.mutation_rate),
        mutation_std=float(args.mutation_std),
        episodes_per_genome=int(args.episodes_per_genome),
        crossover=use_crossover,
        win_weight=float(args.win_weight),
        reward_scale=float(args.reward_scale),
        sweep_bonus=float(args.sweep_bonus),
        seed_genome=seed_genome,
        min_diversity=float(args.min_diversity),
    )

    client = JsonlBridgeClient(str(args.host), int(args.port), float(args.connect_timeout))
    last_err: Optional[BaseException] = None
    for _ in range(max(1, int(args.connect_retries))):
        try:
            client.connect()
            last_err = None
            break
        except BaseException as exc:
            last_err = exc
            time.sleep(max(0.0, float(args.connect_wait)))
    if last_err is not None:
        raise last_err
    client.send({"type": "hello", "protocol": 1})

    last_recv = time.time()
    configured = False
    ga_metrics: Dict[str, Any] = {}
    generation_target = int(args.generations)
    save_path = _resolve_path(project_root, str(args.save_path or ""))
    result_path = _resolve_path(project_root, str(args.result_path or ""))
    log_path = _resolve_path(project_root, str(args.log_path or ""))
    match_title = str(args.match_title or "").strip()

    def emit_stdout(line: str) -> None:
        if bool(args.quiet):
            return
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    def emit_config() -> None:
        nonlocal configured
        configured = True
        client.send(
            {
                "type": "config",
                "watch_mode": False,
                "time_scale": float(args.time_scale),
                "ga_state": trainer.get_ga_state(),
                "action_version": 1,
                "notes": "ga_params_v1_vs_handmade",
            }
        )

    def maybe_save_best(extra: Dict[str, Any]) -> None:
        if not save_path:
            return
        best = trainer.best_genome.clone() if trainer.best_genome else None
        if best is None:
            return
        payload = best.to_dict()
        payload_meta = payload.get("meta", {}) if isinstance(payload.get("meta"), dict) else {}
        payload_meta.update(extra)
        payload["meta"] = payload_meta
        write_json(save_path, payload)

    def log_line(obj: Dict[str, Any]) -> None:
        if not log_path:
            return
        p = Path(log_path)
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")

    emit_config()

    while True:
        msgs = client.poll(0.05)
        if msgs:
            last_recv = time.time()
        for msg in msgs:
            msg_type = str(msg.get("type", ""))
            if msg_type == "step":
                obs = msg.get("obs", {}) if isinstance(msg.get("obs"), dict) else {}
                done = bool(msg.get("done", False))
                metrics = msg.get("metrics", {}) if isinstance(msg.get("metrics"), dict) else {}
                step_dt = float(msg.get("dt", msg.get("delta", args.fixed_dt)) or args.fixed_dt)
                action_p1, advanced = trainer.step(obs, metrics, done, step_dt)
                client.send({"type": "action", "actions": {"1": action_p1}})

                ga_metrics = {
                    "ga_state": trainer.get_ga_state(),
                    "generation": int(trainer.generation),
                    "individual": int(trainer.current_index + 1),
                    "population": int(trainer.population_size),
                    "best_ever": float(trainer.best_fitness),
                }
                if bool(args.live_rounds) and done:
                    winner = 0
                    if isinstance(metrics, dict):
                        try:
                            winner = int(metrics.get("last_winner", 0))
                        except Exception:
                            winner = 0
                    prefix = f"[MATCH] {match_title} " if match_title else "[MATCH] "
                    emit_stdout(f"{prefix}winner={winner} best_ever={trainer.best_fitness:.4f}")

                if bool(args.live_rounds) and advanced:
                    last = max(0, int(trainer.current_index - 1))
                    stats = trainer.episode_stats[last] if 0 <= last < len(trainer.episode_stats) else {}
                    fval = float(stats.get("fitness", 0.0)) if isinstance(stats, dict) else 0.0
                    avg_score = float(stats.get("avg_score", 0.0)) if isinstance(stats, dict) else 0.0
                    wins = int(stats.get("wins", 0)) if isinstance(stats, dict) else 0
                    losses = int(stats.get("losses", 0)) if isinstance(stats, dict) else 0
                    prefix = f"[ROUND] {match_title} " if match_title else "[ROUND] "
                    emit_stdout(f"{prefix}ind={last+1}/{trainer.population_size} fitness={fval:.4f} avg_score={avg_score:.2f} w={wins} l={losses}")
                if advanced and trainer.current_index >= trainer.population_size:
                    summary = trainer.finalize_generation()
                    log_line(
                        {
                            "type": "generation_end",
                            "generation": int(trainer.generation - 1),
                            "summary": summary,
                            "best_stats": dict(trainer.best_stats),
                        }
                    )
                    maybe_save_best({"saved_at_gen": int(trainer.generation - 1), "best_fitness": float(trainer.best_fitness)})
                    if bool(args.pretty_md9):
                        md9 = f"G{int(trainer.generation - 1)} best={summary.get('best_ever', 0.0):.4f} avg={summary.get('avg', 0.0):.4f}"
                        if match_title:
                            md9 = f"{match_title} | {md9}"
                        emit_stdout("MD9: " + md9)
                    emit_config()
                    if generation_target > 0 and int(trainer.generation) > int(generation_target):
                        if result_path:
                            write_json(
                                result_path,
                                {
                                    "ok": True,
                                    "best_fitness": float(trainer.best_fitness),
                                    "best_stats": dict(trainer.best_stats),
                                    "generations": int(trainer.generation - 1),
                                    "schema_id": "ga_params_v1",
                                },
                            )
                        return 0


            elif msg_type == "save_model":
                meta = msg.get("meta", {}) if isinstance(msg.get("meta"), dict) else {}
                maybe_save_best({"saved_from": "save_model", **dict(meta)})
            elif msg_type == "ping":
                client.send({"type": "pong"})

        if time.time() - last_recv > float(args.idle_timeout):
            if result_path:
                write_json(
                    result_path,
                    {
                        "ok": False,
                        "error": "idle_timeout",
                        "best_fitness": float(trainer.best_fitness),
                        "best_stats": dict(trainer.best_stats),
                        "schema_id": "ga_params_v1",
                    },
                )
            return 2


if __name__ == "__main__":
    raise SystemExit(main())
