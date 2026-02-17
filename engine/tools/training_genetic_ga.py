import argparse
import json
import math
import os
import re
import socket
import select
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

POS_SCALE = 1000.0
VEL_SCALE = 1000.0
AXIS_OPTIONS = (-1.0, 0.0, 1.0)
AIM_DIRS = (
    (1.0, 0.0),
    (1.0, -1.0),
    (0.0, -1.0),
    (-1.0, -1.0),
    (-1.0, 0.0),
    (-1.0, 1.0),
    (0.0, 1.0),
    (1.0, 1.0),
    (0.0, 0.0),
)


def to_vec2(value: Any) -> Tuple[float, float]:
    if isinstance(value, dict) and "x" in value and "y" in value:
        return float(value["x"]), float(value["y"])
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        return float(value[0]), float(value[1])
    return 0.0, 0.0


def _bool(value: Any) -> float:
    return 1.0 if bool(value) else 0.0


def obs_to_features(obs: Dict[str, Any]) -> np.ndarray:
    delta_x, delta_y = to_vec2(obs.get("delta_position", [0.0, 0.0]))
    distance = math.hypot(delta_x, delta_y)

    self_state = obs.get("self", {}) if isinstance(obs.get("self"), dict) else {}
    opp_state = obs.get("opponent", {}) if isinstance(obs.get("opponent"), dict) else {}
    match_state = obs.get("match", {}) if isinstance(obs.get("match"), dict) else {}

    self_pos = to_vec2(self_state.get("position", [0.0, 0.0]))
    opp_pos = to_vec2(opp_state.get("position", [0.0, 0.0]))
    self_vel = to_vec2(self_state.get("velocity", [0.0, 0.0]))
    opp_vel = to_vec2(opp_state.get("velocity", [0.0, 0.0]))

    wins = match_state.get("wins", {}) if isinstance(match_state.get("wins"), dict) else {}
    def _win(key: int) -> float:
        if key in wins:
            return float(wins.get(key, 0.0))
        return float(wins.get(str(key), 0.0))

    features = [
        delta_x / POS_SCALE,
        delta_y / POS_SCALE,
        distance / POS_SCALE,
        self_pos[0] / POS_SCALE,
        self_pos[1] / POS_SCALE,
        self_vel[0] / VEL_SCALE,
        self_vel[1] / VEL_SCALE,
        float(self_state.get("facing", 1)),
        _bool(self_state.get("on_floor", False)),
        _bool(self_state.get("on_wall", False)),
        float(self_state.get("arrows", 0)),
        _bool(self_state.get("is_dead", False)),
        opp_pos[0] / POS_SCALE,
        opp_pos[1] / POS_SCALE,
        opp_vel[0] / VEL_SCALE,
        opp_vel[1] / VEL_SCALE,
        float(opp_state.get("facing", 1)),
        _bool(opp_state.get("on_floor", False)),
        _bool(opp_state.get("on_wall", False)),
        float(opp_state.get("arrows", 0)),
        _bool(opp_state.get("is_dead", False)),
        _bool(match_state.get("round_active", False)),
        _bool(match_state.get("match_over", False)),
        _win(1),
        _win(2),
    ]
    return np.asarray(features, dtype=np.float32)


def compute_aim(obs: Dict[str, Any]) -> Tuple[float, float]:
    delta_x, delta_y = to_vec2(obs.get("delta_position", [0.0, 0.0]))
    distance = math.hypot(delta_x, delta_y)
    if distance > 0:
        return delta_x / distance, delta_y / distance
    return 1.0, 0.0


def heuristic_action(obs: Dict[str, Any]) -> Dict[str, Any]:
    delta_x, delta_y = to_vec2(obs.get("delta_position", [0.0, 0.0]))
    distance = math.hypot(delta_x, delta_y)
    approach_distance = 120.0
    shoot_range = 520.0
    dash_range = 620.0

    axis = 0.0
    if distance > approach_distance and abs(delta_x) > 12.0:
        axis = 1.0 if delta_x > 0 else -1.0

    aim_x, aim_y = compute_aim(obs)

    shoot = 40.0 < distance < shoot_range
    melee = distance < 80.0
    jump = delta_y < -120.0
    dash_pressed = ["r1"] if distance > dash_range else []

    frame = int(obs.get("frame", 0) or 0)
    cycle = frame % 24
    shoot_is_pressed = bool(shoot and cycle < 4)
    shoot_pressed = bool(shoot and cycle == 0)
    melee_pressed = bool(melee and (frame % 10 == 0))

    return {
        "axis": axis,
        "aim": [aim_x, aim_y],
        "jump_pressed": jump,
        "shoot_pressed": shoot_pressed,
        "shoot_is_pressed": shoot_is_pressed,
        "melee_pressed": melee_pressed,
        "ult_pressed": False,
        "dash_pressed": dash_pressed,
        "actions": {
            "left": axis < 0.0,
            "right": axis > 0.0,
            "up": False,
            "down": False,
        },
    }


def aim_bins_default() -> int:
    return int(len(AIM_DIRS))


class Genome:
    def __init__(self, weights: List[np.ndarray], mutation_steps: int = 0) -> None:
        self.weights = weights
        self.mutation_steps = int(mutation_steps)
        self._shoot_hold_remaining = 0.0
        self._shoot_cooldown_remaining = 0.0
        self._shoot_release_frame = False
        self._melee_cooldown_remaining = 0.0
        self._last_melee_intent = False
        self._jump_cooldown_remaining = 0.0
        self._last_jump_intent = False

    def reset_controls(self) -> None:
        self._shoot_hold_remaining = 0.0
        self._shoot_cooldown_remaining = 0.0
        self._shoot_release_frame = False
        self._melee_cooldown_remaining = 0.0
        self._last_melee_intent = False
        self._jump_cooldown_remaining = 0.0
        self._last_jump_intent = False

    @staticmethod
    def _init_layer(rng: np.random.Generator, in_dim: int, out_dim: int) -> Tuple[np.ndarray, np.ndarray]:
        scale = 1.0 / math.sqrt(in_dim)
        weight = rng.normal(0.0, scale, size=(in_dim, out_dim)).astype(np.float32)
        bias = rng.normal(0.0, scale, size=(out_dim,)).astype(np.float32)
        return weight, bias

    @classmethod
    def random(cls, rng: np.random.Generator, input_dim: int, hidden_dim: int, output_dim: int) -> "Genome":
        w1, b1 = cls._init_layer(rng, input_dim, hidden_dim)
        w2, b2 = cls._init_layer(rng, hidden_dim, hidden_dim)
        w3, b3 = cls._init_layer(rng, hidden_dim, output_dim)
        return cls([w1, b1, w2, b2, w3, b3], mutation_steps=0)

    def clone(self) -> "Genome":
        return Genome([w.copy() for w in self.weights], mutation_steps=self.mutation_steps)

    def ensure_dims(self, rng: np.random.Generator, input_dim: int, hidden_dim: int, output_dim: int) -> "Genome":
        if len(self.weights) != 6:
            return Genome.random(rng, input_dim, hidden_dim, output_dim)

        w1, b1, w2, b2, w3, b3 = self.weights

        def resize_matrix(old: np.ndarray, new_shape: Tuple[int, int]) -> np.ndarray:
            new = np.zeros(new_shape, dtype=np.float32)
            if old.ndim != 2:
                return new
            r = min(old.shape[0], new_shape[0])
            c = min(old.shape[1], new_shape[1])
            new[:r, :c] = old[:r, :c]
            if r < new_shape[0] or c < new_shape[1]:
                scale = 1.0 / math.sqrt(max(1, new_shape[0]))
                noise = rng.normal(0.0, scale, size=new_shape).astype(np.float32)
                mask = np.zeros(new_shape, dtype=bool)
                mask[:r, :c] = True
                new = np.where(mask, new, noise)
            return new

        def resize_vector(old: np.ndarray, new_len: int) -> np.ndarray:
            new = np.zeros((new_len,), dtype=np.float32)
            if old.ndim != 1:
                return new
            n = min(old.shape[0], new_len)
            new[:n] = old[:n]
            if n < new_len:
                scale = 1.0 / math.sqrt(max(1, new_len))
                new[n:] = rng.normal(0.0, scale, size=(new_len - n,)).astype(np.float32)
            return new

        w1_new = resize_matrix(w1, (input_dim, hidden_dim))
        b1_new = resize_vector(b1, hidden_dim)
        w2_new = resize_matrix(w2, (hidden_dim, hidden_dim))
        b2_new = resize_vector(b2, hidden_dim)
        w3_new = resize_matrix(w3, (hidden_dim, output_dim))
        b3_new = resize_vector(b3, output_dim)
        return Genome([w1_new, b1_new, w2_new, b2_new, w3_new, b3_new], mutation_steps=self.mutation_steps)

    def forward(self, features: np.ndarray) -> np.ndarray:
        w1, b1, w2, b2, w3, b3 = self.weights
        x = np.tanh(features @ w1 + b1)
        x = np.tanh(x @ w2 + b2)
        return x @ w3 + b3

    def act(self, obs: Dict[str, Any], learn_aim: bool, aim_bins: int) -> Dict[str, Any]:
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
                "actions": {
                    "left": False,
                    "right": False,
                    "up": False,
                    "down": False,
                },
            }
        features = obs_to_features(obs)
        output = self.forward(features)
        axis_idx = int(np.argmax(output[:3]))
        axis_value = AXIS_OPTIONS[axis_idx]

        dt = float(obs.get("delta", 0.0) or 0.0)
        self._shoot_cooldown_remaining = max(0.0, self._shoot_cooldown_remaining - dt)
        self._melee_cooldown_remaining = max(0.0, self._melee_cooldown_remaining - dt)
        self._jump_cooldown_remaining = max(0.0, self._jump_cooldown_remaining - dt)

        shoot_intent = output[3] > 0.0
        jump_intent = output[4] > 0.0
        dash = output[5] > 0.0

        shoot_pressed = False
        shoot_is_pressed = False
        if self._shoot_release_frame:
            self._shoot_release_frame = False
            shoot_pressed = False
            shoot_is_pressed = False
        elif self._shoot_hold_remaining > 0.0:
            self._shoot_hold_remaining = max(0.0, self._shoot_hold_remaining - dt)
            shoot_pressed = False
            shoot_is_pressed = True
            if self._shoot_hold_remaining <= 0.0:
                self._shoot_release_frame = True
                self._shoot_cooldown_remaining = 0.18
        elif shoot_intent and self._shoot_cooldown_remaining <= 0.0:
            self._shoot_hold_remaining = 0.08
            shoot_pressed = True
            shoot_is_pressed = True

        melee_intent = output[6] > 0.0
        melee_pressed = False
        if melee_intent and (not self._last_melee_intent) and self._melee_cooldown_remaining <= 0.0:
            melee_pressed = True
            self._melee_cooldown_remaining = 0.30
        self._last_melee_intent = bool(melee_intent)

        jump_pressed = False
        if jump_intent and (not self._last_jump_intent) and self._jump_cooldown_remaining <= 0.0:
            jump_pressed = True
            self._jump_cooldown_remaining = 0.18
        self._last_jump_intent = bool(jump_intent)

        aim_x, aim_y = compute_aim(obs)
        if learn_aim and aim_bins > 0 and output.shape[0] >= 7 + aim_bins:
            aim_logits = output[7 : 7 + aim_bins]
            aim_idx = int(np.argmax(aim_logits))
            aim_idx = max(0, min(aim_idx, aim_bins - 1))
            aim_x, aim_y = AIM_DIRS[aim_idx]
            if aim_x != 0.0 and aim_y != 0.0:
                norm = math.hypot(aim_x, aim_y)
                if norm > 0:
                    aim_x /= norm
                    aim_y /= norm
        return {
            "axis": axis_value,
            "aim": [aim_x, aim_y],
            "jump_pressed": bool(jump_pressed),
            "shoot_pressed": bool(shoot_pressed),
            "shoot_is_pressed": bool(shoot_is_pressed),
            "melee_pressed": bool(melee_pressed),
            "ult_pressed": False,
            "dash_pressed": ["r1"] if dash else [],
            "actions": {
                "left": axis_value < 0.0,
                "right": axis_value > 0.0,
                "up": False,
                "down": False,
            },
        }

    def mutate(self, rng: np.random.Generator, mutation_rate: float, mutation_std: float) -> None:
        if mutation_rate <= 0.0 or mutation_std <= 0.0:
            return
        for idx, weights in enumerate(self.weights):
            mask = rng.random(weights.shape) < mutation_rate
            noise = rng.normal(0.0, mutation_std, size=weights.shape).astype(np.float32)
            self.weights[idx] = weights + noise * mask
        self.mutation_steps += 1

    @staticmethod
    def crossover(rng: np.random.Generator, parent_a: "Genome", parent_b: "Genome") -> "Genome":
        new_weights: List[np.ndarray] = []
        for w_a, w_b in zip(parent_a.weights, parent_b.weights):
            mask = rng.random(w_a.shape) < 0.5
            child = np.where(mask, w_a, w_b)
            new_weights.append(child.astype(np.float32))
        return Genome(new_weights, mutation_steps=max(parent_a.mutation_steps, parent_b.mutation_steps))

    def to_dict(self) -> Dict[str, Any]:
        return {"weights": [w.tolist() for w in self.weights], "meta": {"mutation_steps": int(self.mutation_steps)}}

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "Genome":
        weights_payload = payload.get("weights", [])
        weights = [np.asarray(w, dtype=np.float32) for w in weights_payload]
        meta = payload.get("meta", {}) if isinstance(payload.get("meta"), dict) else {}
        mutation_steps = int(meta.get("mutation_steps", 0))
        return cls(weights, mutation_steps=mutation_steps)


class GeneticTrainer:
    def __init__(
        self,
        rng: np.random.Generator,
        input_dim: int,
        hidden_dim: int,
        output_dim: int,
        population_size: int,
        elite_size: int,
        mutation_rate: float,
        mutation_std: float,
        episodes_per_genome: int,
        opponent_mode: str,
        crossover: bool,
        seed_genome: Optional[Genome] = None,
        fixed_opponent_genome: Optional[Genome] = None,
        fixed_opponent_pool: Optional[List[Genome]] = None,
        opponent_pool_mode: str = "round_robin",
        win_weight: float = 0.6,
        reward_scale: float = 20.0,
        sweep_bonus: float = 0.0,
        learn_aim: bool = False,
        aim_bins: int = 0,
    ) -> None:
        self.rng = rng
        self.population_size = population_size
        self.elite_size = max(1, min(elite_size, population_size))
        self.mutation_rate = mutation_rate
        self.mutation_std = mutation_std
        self.episodes_per_genome = max(1, episodes_per_genome)
        self.opponent_mode = opponent_mode
        self.use_crossover = crossover
        self.learn_aim = bool(learn_aim)
        self.aim_bins = int(aim_bins)

        if seed_genome is not None:
            seed_genome = seed_genome.ensure_dims(self.rng, input_dim, hidden_dim, output_dim)
            self.population = [seed_genome.clone()]
            for _ in range(population_size - 1):
                child = seed_genome.clone()
                child.mutate(self.rng, mutation_rate, mutation_std)
                self.population.append(child)
        else:
            self.population = [
                Genome.random(rng, input_dim, hidden_dim, output_dim)
                for _ in range(population_size)
            ]

        self.fitness = [0.0 for _ in range(population_size)]
        self.episode_stats: List[Dict[str, Any]] = [{} for _ in range(population_size)]
        self.current_index = 0
        self.current_episode = 0
        self.current_score = 0.0
        self.generation = 1
        self.best_genome: Optional[Genome] = seed_genome.clone() if seed_genome else None
        self.best_fitness = -float("inf")
        self.best_stats: Dict[str, Any] = {}
        self.opponent_genome: Optional[Genome] = None
        self.fixed_opponent_genome: Optional[Genome] = fixed_opponent_genome.clone() if fixed_opponent_genome else None
        self.fixed_opponent_pool: List[Genome] = [g.clone() for g in fixed_opponent_pool] if fixed_opponent_pool else []
        self.opponent_pool_mode = str(opponent_pool_mode)
        self._opponent_pool_index = 0

        self.win_weight = max(0.0, min(1.0, float(win_weight)))
        self.reward_scale = max(1e-9, float(reward_scale))
        self.sweep_bonus = float(sweep_bonus)
        self._wins = 0
        self._losses = 0
        self._start_generation()

    def _select_opponent_from_pool(self) -> Optional[Genome]:
        if not self.fixed_opponent_pool:
            return None
        if self.opponent_pool_mode == "random":
            idx = int(self.rng.integers(0, len(self.fixed_opponent_pool)))
            return self.fixed_opponent_pool[idx].clone()
        idx = int(self._opponent_pool_index % len(self.fixed_opponent_pool))
        return self.fixed_opponent_pool[idx].clone()

    def _advance_opponent_pool(self) -> None:
        if not self.fixed_opponent_pool:
            return
        if self.opponent_pool_mode == "round_robin":
            self._opponent_pool_index += 1

    def get_ga_state(self, mutation_rate: float, mutation_std: float) -> Dict[str, Any]:
        if self.population_size > 0:
            safe_index = min(max(self.current_index, 0), self.population_size - 1)
            p1_genome = self.population[safe_index]
            individual_value = min(self.current_index + 1, self.population_size)
        else:
            p1_genome = None
            individual_value = 0
        p1_state = {
            "generation": int(self.generation),
            "individual": int(individual_value),
            "population": int(self.population_size),
            "episode_in_individual": int(self.current_episode + 1),
            "episodes_per_genome": int(self.episodes_per_genome),
            "mutation_steps": int(p1_genome.mutation_steps) if p1_genome is not None else 0,
            "mutation_rate": float(mutation_rate),
            "mutation_std": float(mutation_std),
        }

        p2_mode = str(self.opponent_mode)
        p2_state: Dict[str, Any] = {"mode": p2_mode}
        if p2_mode == "mirror":
            p2_state.update(
                {
                    "generation": int(self.generation),
                    "individual": int(self.current_index + 1),
                    "episode_in_individual": int(self.current_episode + 1),
                    "episodes_per_genome": int(self.episodes_per_genome),
                    "mutation_steps": int(p1_genome.mutation_steps) if p1_genome is not None else 0,
                    "mutation_rate": float(mutation_rate),
                    "mutation_std": float(mutation_std),
                }
            )
        elif p2_mode == "best" and self.opponent_genome is not None:
            p2_state.update(
                {
                    "generation": int(self.generation),
                    "individual": 0,
                    "episode_in_individual": 0,
                    "episodes_per_genome": 0,
                    "mutation_steps": int(self.opponent_genome.mutation_steps),
                    "mutation_rate": float(mutation_rate),
                    "mutation_std": float(mutation_std),
                }
            )
        else:
            p2_state.update(
                {
                    "generation": 0,
                    "individual": 0,
                    "episode_in_individual": 0,
                    "episodes_per_genome": 0,
                    "mutation_steps": 0,
                    "mutation_rate": 0.0,
                    "mutation_std": 0.0,
                }
            )

        return {"1": p1_state, "2": p2_state}

    def _start_generation(self) -> None:
        self.current_index = 0
        self.current_episode = 0
        self.current_score = 0.0
        self._wins = 0
        self._losses = 0
        self.fitness = [0.0 for _ in range(self.population_size)]
        self.episode_stats = [{} for _ in range(self.population_size)]
        if self.opponent_mode == "best":
            pool_pick = self._select_opponent_from_pool()
            if pool_pick is not None:
                self.opponent_genome = pool_pick
            elif self.fixed_opponent_genome is not None:
                self.opponent_genome = self.fixed_opponent_genome.clone()
            elif self.best_genome is not None:
                self.opponent_genome = self.best_genome.clone()
            else:
                self.opponent_genome = None
        else:
            self.opponent_genome = None

        for genome in self.population:
            genome.reset_controls()
        if self.opponent_genome is not None:
            self.opponent_genome.reset_controls()

    def _select_opponent_action(self, obs: Dict[str, Any]) -> Dict[str, Any]:
        if self.opponent_mode == "mirror":
            return self.population[self.current_index].act(obs, self.learn_aim, self.aim_bins)
        if self.opponent_mode == "best" and self.opponent_genome is not None:
            return self.opponent_genome.act(obs, self.learn_aim, self.aim_bins)
        return heuristic_action(obs)

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

    def _tournament_select_index(self, tournament_size: int = 3) -> int:
        if self.population_size <= 1:
            return 0
        k = max(2, min(int(tournament_size), self.population_size))
        candidates = self.rng.integers(0, self.population_size, size=k)
        best = int(candidates[0])
        best_fit = float(self.fitness[best])
        for idx in candidates[1:]:
            i = int(idx)
            fit = float(self.fitness[i])
            if fit > best_fit:
                best = i
                best_fit = fit
        return best

    def step(self, obs: Dict[str, Any], metrics: Dict[str, Any], done: bool) -> Tuple[Dict[str, Any], Dict[str, Any], bool]:
        obs_p1 = obs.get("1", {}) if isinstance(obs.get("1"), dict) else {}
        obs_p2 = obs.get("2", {}) if isinstance(obs.get("2"), dict) else {}

        action_p1 = self.population[self.current_index].act(obs_p1, self.learn_aim, self.aim_bins)
        action_p2 = self._select_opponent_action(obs_p2)

        advance = False
        if done:
            try:
                self.population[self.current_index].reset_controls()
            except Exception:
                pass
            if self.opponent_genome is not None:
                try:
                    self.opponent_genome.reset_controls()
                except Exception:
                    pass
            reward_p1 = self._extract_episode_reward(metrics, 1)
            reward_p2 = self._extract_episode_reward(metrics, 2)
            score_p1 = self._extract_match_score(metrics, 1)
            if score_p1 == 0.0 and reward_p1 == 0.0 and reward_p2 == 0.0:
                score_p1 = reward_p1
            self.current_score += score_p1

            winner = 0
            if isinstance(metrics, dict):
                try:
                    winner = int(metrics.get("last_winner", 0))
                except Exception:
                    winner = 0
            if winner not in (1, 2):
                s1 = self._extract_match_score(metrics, 1)
                s2 = self._extract_match_score(metrics, 2)
                if s1 > s2:
                    winner = 1
                elif s2 > s1:
                    winner = 2
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
                self.fitness[self.current_index] = composite
                stats_snapshot: Dict[str, Any] = {}
                if isinstance(metrics, dict):
                    last_round = metrics.get("last_round")
                    if isinstance(last_round, dict):
                        stats_snapshot["last_round"] = dict(last_round)
                stats_snapshot["wins"] = int(self._wins)
                stats_snapshot["losses"] = int(self._losses)
                stats_snapshot["avg_score"] = float(avg_score)
                stats_snapshot["fitness"] = float(composite)
                self.episode_stats[self.current_index] = stats_snapshot
                self.current_index += 1
                self.current_episode = 0
                self.current_score = 0.0
                self._wins = 0
                self._losses = 0
                advance = True

            if self.opponent_mode == "best" and self.fixed_opponent_pool:
                self._advance_opponent_pool()
                self.opponent_genome = self._select_opponent_from_pool()
        return action_p1, action_p2, advance

    def finalize_generation(self) -> Dict[str, float]:
        ranked = sorted(range(self.population_size), key=lambda i: self.fitness[i], reverse=True)
        best_index = ranked[0]
        best_genome = self.population[best_index]
        best_fitness = self.fitness[best_index]
        avg_fitness = float(np.mean(self.fitness))

        if best_fitness > self.best_fitness:
            self.best_fitness = best_fitness
            self.best_genome = best_genome.clone()
            try:
                self.best_stats = dict(self.episode_stats[best_index]) if isinstance(self.episode_stats[best_index], dict) else {}
            except Exception:
                self.best_stats = {}

        if self.population_size == 1:
            child = best_genome.clone()
            child.mutate(self.rng, self.mutation_rate, self.mutation_std)
            self.population = [child]
            self.generation += 1
            self._start_generation()
            return {"best": best_fitness, "avg": avg_fitness, "best_ever": self.best_fitness}

        elites_count = max(1, min(self.elite_size, self.population_size))
        elites = [self.population[i].clone() for i in ranked[:elites_count]]

        new_population: List[Genome] = []
        new_population.extend(elites)
        while len(new_population) < self.population_size:
            parent_a = self.population[self._tournament_select_index()]
            if self.use_crossover:
                parent_b = self.population[self._tournament_select_index()]
                child = Genome.crossover(self.rng, parent_a, parent_b)
            else:
                child = parent_a.clone()
            child.mutate(self.rng, self.mutation_rate, self.mutation_std)
            new_population.append(child)

        self.population = new_population
        self.generation += 1
        self._start_generation()

        return {"best": best_fitness, "avg": avg_fitness, "best_ever": self.best_fitness}


def save_genome(path: str, genome: Genome) -> None:
    ensure_parent_dir(path)
    payload = genome.to_dict()
    with open(path, "w", encoding="utf-8") as file:
        json.dump(payload, file)


def save_genome_with_meta(path: str, genome: Genome, meta: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    payload = genome.to_dict()
    payload_meta = payload.get("meta", {}) if isinstance(payload.get("meta"), dict) else {}
    payload_meta.update(meta)
    payload["meta"] = payload_meta
    with open(path, "w", encoding="utf-8") as file:
        json.dump(payload, file)


def load_genome(path: str) -> Genome:
    with open(path, "r", encoding="utf-8") as file:
        payload = json.load(file)
    return Genome.from_dict(payload)


def ensure_parent_dir(path: str) -> None:
    if not path:
        return
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)


def ensure_log_header(path: str) -> None:
    if not path:
        return
    if os.path.exists(path):
        return
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as file:
        file.write(
            "timestamp,generation,best,avg,best_ever,population,elite,mutation_rate,mutation_std,"
            "episodes_per_genome,opponent,crossover\n"
        )


def append_generation_log(
    path: str,
    generation: int,
    stats: Dict[str, float],
    population: int,
    elite: int,
    mutation_rate: float,
    mutation_std: float,
    episodes_per_genome: int,
    opponent: str,
    crossover: bool,
) -> None:
    if not path:
        return
    ensure_log_header(path)
    timestamp = int(time.time())
    with open(path, "a", encoding="utf-8") as file:
        file.write(
            f"{timestamp},{generation},{stats['best']:.6f},{stats['avg']:.6f},{stats['best_ever']:.6f},"
            f"{population},{elite},{mutation_rate:.6f},{mutation_std:.6f},{episodes_per_genome},"
            f"{opponent},{int(crossover)}\n"
        )


def _load_config_json(path: Path) -> Dict[str, Any]:
    if not path or not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def _resolve_path(project_root: Path, value: str) -> str:
    if not value:
        return value
    path = Path(value)
    if path.is_absolute():
        return str(path)
    return str(project_root / path)


def send_message(sock_file, payload: Dict[str, Any]) -> None:
    sock_file.write((json.dumps(payload) + "\n").encode("utf-8"))
    sock_file.flush()


def sanitize_model_name(value: str) -> str:
    text = str(value or "").strip().lower()
    text = re.sub(r"\s+", "_", text)
    text = re.sub(r"[^a-z0-9_\-\.]+", "", text)
    text = re.sub(r"_+", "_", text).strip("_-.")
    return text[:64]


def unique_path(path: Path) -> Path:
    if not path.exists():
        return path
    stem = path.stem
    suffix = path.suffix
    parent = path.parent
    for idx in range(2, 1000):
        candidate = parent / f"{stem}_{idx}{suffix}"
        if not candidate.exists():
            return candidate
    return parent / f"{stem}_{int(time.time())}{suffix}"


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    default_config_dir = project_root / "BOTS" / "IA" / "config"

    pre_parser = argparse.ArgumentParser(add_help=False)
    pre_parser.add_argument("--config-dir", default=str(default_config_dir))
    pre_args, _ = pre_parser.parse_known_args()

    config_dir = Path(pre_args.config_dir)
    training_cfg = _load_config_json(config_dir / "training.json")
    ga_cfg = _load_config_json(config_dir / "ga.json")

    def cfg_get(cfg: Dict[str, Any], key: str, default: Any) -> Any:
        return cfg.get(key, default)

    parser = argparse.ArgumentParser(description="Genetic trainer for Project PVP")
    parser.add_argument("--config-dir", default=str(config_dir))
    parser.add_argument("--host", default=cfg_get(training_cfg, "host", "127.0.0.1"))
    parser.add_argument("--port", default=cfg_get(training_cfg, "port", 9009), type=int)
    parser.add_argument("--connect-retries", default=60, type=int)
    parser.add_argument("--connect-wait", default=0.1, type=float)
    parser.add_argument("--connect-timeout", default=2.0, type=float)
    parser.add_argument("--idle-timeout", default=30.0, type=float)
    parser.add_argument(
        "--learn-aim",
        default=cfg_get(ga_cfg, "learn_aim", False),
        action=argparse.BooleanOptionalAction,
    )
    parser.add_argument("--aim-bins", default=cfg_get(ga_cfg, "aim_bins", aim_bins_default()), type=int)
    parser.add_argument(
        "--watch",
        default=cfg_get(training_cfg, "watch", False),
        action=argparse.BooleanOptionalAction,
        help="Disable training speed-up",
    )
    parser.add_argument("--time-scale", default=cfg_get(training_cfg, "time_scale", 6.0), type=float)
    parser.add_argument(
        "--generation-per-round",
        default=cfg_get(ga_cfg, "generation_per_round", False),
        action=argparse.BooleanOptionalAction,
        help="Se true, força population=1, elite=1 e episodes_per_genome=1",
    )
    parser.add_argument("--population", default=cfg_get(ga_cfg, "population", 24), type=int)
    parser.add_argument("--elite", default=cfg_get(ga_cfg, "elite", 4), type=int)
    parser.add_argument("--hidden", default=cfg_get(ga_cfg, "hidden", 128), type=int)
    parser.add_argument("--mutation-rate", default=cfg_get(ga_cfg, "mutation_rate", 0.08), type=float)
    parser.add_argument("--mutation-std", default=cfg_get(ga_cfg, "mutation_std", 0.2), type=float)
    parser.add_argument("--episodes-per-genome", default=cfg_get(ga_cfg, "episodes_per_genome", 1), type=int)
    parser.add_argument("--opponent", default=cfg_get(ga_cfg, "opponent", "best"), choices=("best", "baseline", "mirror"))
    parser.add_argument(
        "--opponent-load-path",
        default=cfg_get(ga_cfg, "opponent_load_path", ""),
        help="Carrega um genoma fixo para o oponente (usado quando --opponent=best)",
    )
    parser.add_argument(
        "--opponent-pool-path",
        action="append",
        default=cfg_get(ga_cfg, "opponent_pool_paths", []),
        help="Adiciona um genoma na pool de oponentes (pode repetir). Usado quando --opponent=best",
    )
    parser.add_argument(
        "--opponent-pool-mode",
        default=cfg_get(ga_cfg, "opponent_pool_mode", "round_robin"),
        choices=("round_robin", "random"),
        help="Como alternar o oponente quando uma pool é usada",
    )
    parser.add_argument(
        "--win-weight",
        default=cfg_get(ga_cfg, "win_weight", 0.6),
        type=float,
        help="Peso da vitória/derrota na fitness (0..1)",
    )
    parser.add_argument(
        "--reward-scale",
        default=cfg_get(ga_cfg, "reward_scale", 20.0),
        type=float,
        help="Escala do reward para normalização via tanh",
    )
    parser.add_argument(
        "--sweep-bonus",
        default=cfg_get(ga_cfg, "sweep_bonus", 0.0),
        type=float,
        help="Bônus aditivo na fitness quando o bot faz 5-0",
    )
    parser.add_argument(
        "--crossover",
        default=cfg_get(ga_cfg, "crossover", False),
        action=argparse.BooleanOptionalAction,
    )
    parser.add_argument("--generations", default=cfg_get(ga_cfg, "generations", 0), type=int, help="0 = infinite")
    parser.add_argument("--seed", default=cfg_get(ga_cfg, "seed", 0), type=int)
    parser.add_argument(
        "--save-path",
        default=cfg_get(ga_cfg, "save_path", "BOTS/IA/weights/best_genome.json"),
        help="Save best genome path (json)",
    )
    parser.add_argument("--load-path", default=cfg_get(ga_cfg, "load_path", ""), help="Load genome path (json)")
    parser.add_argument(
        "--log-path",
        default=cfg_get(ga_cfg, "log_path", "BOTS/IA/logs/genetic_log.csv"),
        help="Generation log path (csv)",
    )
    parser.add_argument(
        "--result-path",
        default=cfg_get(ga_cfg, "result_path", ""),
        help="Resultado final path (json)",
    )
    parser.add_argument(
        "--debug-steps",
        default=0,
        type=int,
        help="Imprime resumo dos primeiros N steps recebidos (debug do bridge)",
    )
    parser.add_argument(
        "--live-rounds",
        action="store_true",
        help="Imprime eventos de fim de round e fim de partida (wins) em tempo real",
    )
    parser.add_argument(
        "--pretty-md9",
        action="store_true",
        help="Imprime blocos mais organizados por partida (MD9) no stdout",
    )
    parser.add_argument(
        "--match-title",
        default="",
        help="Título usado nos logs bonitos (ex: 'G12 N276 vs bobo2 (G3_N51)')",
    )
    parser.add_argument("--quiet", action="store_true", help="Reduz logs no stdout")
    args = parser.parse_args()

    if args.generation_per_round:
        args.population = 1
        args.elite = 1
        args.episodes_per_genome = 1

    rng = np.random.default_rng(args.seed if args.seed != 0 else None)

    debug_steps_remaining = int(args.debug_steps)

    live_rounds = bool(args.live_rounds)
    pretty_md9 = bool(args.pretty_md9)
    match_title = str(args.match_title or "").strip()
    last_wins: Optional[Tuple[int, int]] = None
    last_match_over = False
    last_live_score: Optional[Tuple[float, float]] = None
    match_index = 0

    def _extract_live_score(metrics_obj: Dict[str, Any], pid: int) -> float:
        if not isinstance(metrics_obj, dict):
            return 0.0
        score_payload = metrics_obj.get("match_score")
        if not isinstance(score_payload, dict):
            score_payload = metrics_obj.get("last_match_score") if isinstance(metrics_obj.get("last_match_score"), dict) else {}
        if not isinstance(score_payload, dict):
            return 0.0
        if pid in score_payload:
            return float(score_payload[pid])
        key = str(pid)
        if key in score_payload:
            return float(score_payload[key])
        return 0.0

    sample_features = obs_to_features({})
    input_dim = int(sample_features.shape[0])
    learn_aim = bool(args.learn_aim)
    aim_bins = int(args.aim_bins) if learn_aim else 0
    aim_bins = max(0, min(aim_bins, len(AIM_DIRS)))
    output_dim = 7 + aim_bins if learn_aim else 7

    save_path = _resolve_path(project_root, args.save_path)
    load_path = _resolve_path(project_root, args.load_path)
    log_path = _resolve_path(project_root, args.log_path)
    result_path = _resolve_path(project_root, args.result_path)

    seed_genome = None
    if load_path:
        try:
            seed_genome = load_genome(load_path)
        except Exception as exc:
            if not args.quiet:
                print(f"[trainer] seed inválida ({load_path}): {exc}")

    fixed_opponent_genome = None
    opponent_load_path = _resolve_path(project_root, str(args.opponent_load_path or ""))
    if opponent_load_path:
        try:
            fixed_opponent_genome = load_genome(opponent_load_path)
        except Exception as exc:
            if not args.quiet:
                print(f"[trainer] oponente inválido ({opponent_load_path}): {exc}")

    opponent_pool: List[Genome] = []
    pool_paths: List[str] = []
    if isinstance(args.opponent_pool_path, list):
        pool_paths = [str(p) for p in args.opponent_pool_path if str(p).strip()]
    for p in pool_paths:
        resolved = _resolve_path(project_root, p)
        if not resolved:
            continue
        try:
            opponent_pool.append(load_genome(resolved))
        except Exception as exc:
            if not args.quiet:
                print(f"[trainer] pool inválida ({resolved}): {exc}")

    last_episode_reward: Dict[str, float] = {"1": 0.0, "2": 0.0}
    last_match_score: Dict[str, float] = {"1": 0.0, "2": 0.0}
    last_winner: int = 0
    if save_path:
        ensure_parent_dir(save_path)
    if log_path:
        ensure_log_header(log_path)
    trainer = GeneticTrainer(
        rng=rng,
        input_dim=input_dim,
        hidden_dim=args.hidden,
        output_dim=output_dim,
        population_size=args.population,
        elite_size=args.elite,
        mutation_rate=args.mutation_rate,
        mutation_std=args.mutation_std,
        episodes_per_genome=args.episodes_per_genome,
        opponent_mode=args.opponent,
        crossover=args.crossover,
        seed_genome=seed_genome,
        fixed_opponent_genome=fixed_opponent_genome,
        fixed_opponent_pool=opponent_pool,
        opponent_pool_mode=str(args.opponent_pool_mode),
        win_weight=float(args.win_weight),
        reward_scale=float(args.reward_scale),
        sweep_bonus=float(args.sweep_bonus),
        learn_aim=learn_aim,
        aim_bins=aim_bins,
    )

    config = {
        "type": "config",
        "watch_mode": bool(args.watch),
        "time_scale": float(args.time_scale),
        "ga_state": trainer.get_ga_state(args.mutation_rate, args.mutation_std),
        "action_version": 2 if learn_aim else 1,
    }

    generations_limit = int(args.generations)
    done_generations = 0

    exit_code = 0
    last_error = ""
    try:
        sock = None
        connect_timeout = max(0.1, float(args.connect_timeout))
        for _ in range(max(1, int(args.connect_retries))):
            try:
                sock = socket.create_connection((args.host, args.port), timeout=connect_timeout)
                break
            except OSError:
                time.sleep(max(0.0, float(args.connect_wait)))
        if sock is None:
            raise ConnectionError("Falha ao conectar")

        with sock:
            sock.settimeout(None)
            sock_file = sock.makefile("rwb")
            send_message(sock_file, config)

            idle_timeout = max(0.1, float(args.idle_timeout))
            last_message_at = time.time()

            while True:
                ready, _, _ = select.select([sock], [], [], idle_timeout)
                if not ready:
                    raise ConnectionError("Timeout aguardando mensagens do jogo")
                line = sock_file.readline()
                if not line:
                    break

                text = line.decode("utf-8", errors="ignore").strip()
                if "{" in text and not text.startswith("{"):
                    text = text[text.index("{") :]
                if not text:
                    continue

                try:
                    message = json.loads(text)
                except json.JSONDecodeError:
                    if not args.quiet:
                        print(f"[trainer] ignorando linha inválida: {text[:80]}")
                    continue

                last_message_at = time.time()

                msg_type = message.get("type")

                if msg_type == "hello":
                    send_message(sock_file, config)
                    continue

                if msg_type == "save_model":
                    player_id = int(message.get("player_id", 1))
                    raw_name = str(message.get("name", ""))
                    safe_name = sanitize_model_name(raw_name)
                    if not safe_name:
                        safe_name = f"p{player_id}_gen{trainer.generation}_ind{min(trainer.current_index + 1, trainer.population_size)}"
                    filename = safe_name if safe_name.endswith(".json") else f"{safe_name}.json"

                    target_genome: Optional[Genome] = None
                    if player_id == 1:
                        if trainer.population_size > 0:
                            safe_index = min(max(trainer.current_index, 0), trainer.population_size - 1)
                            target_genome = trainer.population[safe_index].clone()
                    elif player_id == 2:
                        if trainer.opponent_mode == "mirror":
                            if trainer.population_size > 0:
                                safe_index = min(max(trainer.current_index, 0), trainer.population_size - 1)
                                target_genome = trainer.population[safe_index].clone()
                        elif trainer.opponent_mode == "best" and trainer.opponent_genome is not None:
                            target_genome = trainer.opponent_genome.clone()

                    if target_genome is None:
                        send_message(sock_file, {"type": "event", "text": f"Falha ao salvar modelo: bot {player_id} sem genoma"})
                        continue

                    out_dir = project_root / "BOTS" / "IA" / "weights" / "models"
                    out_path = unique_path(out_dir / filename)
                    save_genome_with_meta(
                        str(out_path),
                        target_genome,
                        {
                            "saved_name": safe_name,
                            "player_id": player_id,
                            "generation": int(trainer.generation),
                            "individual": int(min(trainer.current_index + 1, trainer.population_size)),
                            "opponent_mode": str(trainer.opponent_mode),
                            "timestamp": int(time.time()),
                        },
                    )

                    rel = out_path.relative_to(project_root) if out_path.is_absolute() else out_path
                    send_message(sock_file, {"type": "event", "text": f"Modelo salvo: {rel}"})
                    continue

                if msg_type != "step":
                    continue

                obs = message.get("obs", {}) if isinstance(message.get("obs"), dict) else {}
                metrics = message.get("metrics", {}) if isinstance(message.get("metrics"), dict) else {}
                done = bool(message.get("done", False))

                if live_rounds and isinstance(obs, dict):
                    try:
                        o1 = obs.get("1")
                        if isinstance(o1, dict):
                            match_state = o1.get("match") if isinstance(o1.get("match"), dict) else {}
                            wins = match_state.get("wins") if isinstance(match_state.get("wins"), dict) else {}
                            w1 = int(wins.get(1, wins.get("1", 0)))
                            w2 = int(wins.get(2, wins.get("2", 0)))
                            match_over = bool(match_state.get("match_over", False))
                            now_wins = (w1, w2)
                            score1 = _extract_live_score(metrics, 1)
                            score2 = _extract_live_score(metrics, 2)

                            if last_wins is None:
                                match_index += 1
                                last_wins = now_wins
                                last_match_over = match_over
                                last_live_score = (score1, score2)
                                if pretty_md9:
                                    title = match_title if match_title else "MD9"
                                    print("MD9: ___________")
                                    print(f"MD9: Começando MD9 | {title} | Match #{match_index}")
                                    print("MD9: Resultados de cada round")
                                    sys.stdout.flush()
                            elif now_wins != last_wins:
                                prev_w1, prev_w2 = last_wins
                                prev_s1, prev_s2 = last_live_score if last_live_score is not None else (score1, score2)
                                delta_s1 = score1 - prev_s1
                                delta_s2 = score2 - prev_s2
                                round_no = int(w1 + w2)
                                if pretty_md9:
                                    print(
                                        f"MD9: R{round_no:02d} | wins={w1}-{w2} | "
                                        f"dScore={delta_s1:+.2f}/{delta_s2:+.2f} | "
                                        f"ScoreTot={score1:.2f}/{score2:.2f}"
                                    )
                                else:
                                    print(f"[ROUND] wins={w1}-{w2}")
                                sys.stdout.flush()
                                last_wins = now_wins
                                last_live_score = (score1, score2)

                            if match_over and not last_match_over:
                                if pretty_md9:
                                    print("MD9: Resultado final")
                                    print(
                                        f"MD9: FINAL | wins={w1}-{w2} | ScoreTot={score1:.2f}/{score2:.2f}"
                                    )
                                    print("MD9: ___________")
                                else:
                                    print(f"[MATCH] over wins={w1}-{w2}")
                                sys.stdout.flush()
                                last_match_over = True
                    except Exception:
                        pass

                if debug_steps_remaining > 0:
                    try:
                        o1 = obs.get("1") if isinstance(obs, dict) else None
                        if isinstance(o1, dict):
                            dp = o1.get("delta_position")
                            s = o1.get("self", {}) if isinstance(o1.get("self"), dict) else {}
                            m = o1.get("match", {}) if isinstance(o1.get("match"), dict) else {}
                            sp = s.get("position")
                            op = (o1.get("opponent", {}) if isinstance(o1.get("opponent"), dict) else {}).get("position")
                            print(
                                f"[DBG step] frame={int(message.get('frame', -1))} "
                                f"round_active={m.get('round_active')} self_pos={sp} opp_pos={op} "
                                f"delta_position={dp} arrows={s.get('arrows')} aim_hold_active={s.get('aim_hold_active')} "
                                f"shoot_was_pressed={s.get('shoot_was_pressed')}"
                            )
                            af = message.get("actions_frame")
                            if isinstance(af, dict):
                                print(f"[DBG af  ] {af.get('1')} | {af.get('2')}")
                            bp = message.get("bot_policy")
                            if isinstance(bp, dict):
                                print(f"[DBG pol ] {bp}")
                            sys.stdout.flush()
                    except Exception:
                        pass

                    try:
                        sr = metrics.get("super_reward") if isinstance(metrics, dict) else None
                        if isinstance(sr, dict):
                            lc = sr.get("last_components") if isinstance(sr.get("last_components"), dict) else {}
                            print(f"[DBG super] sig={sr.get('signature')} p1={lc.get(1, lc.get('1'))}")
                            sys.stdout.flush()
                    except Exception:
                        pass

                action_p1, action_p2, advance = trainer.step(obs, metrics, done)
                if debug_steps_remaining > 0:
                    try:
                        print(f"[DBG act ] p1={action_p1} p2={action_p2}")
                        sys.stdout.flush()
                    except Exception:
                        pass
                    debug_steps_remaining -= 1
                response = {"type": "action", "actions": {"1": action_p1, "2": action_p2}}
                send_message(sock_file, response)

                if done:
                    try:
                        m = metrics if isinstance(metrics, dict) else {}
                        ler = m.get("last_episode_reward")
                        if isinstance(ler, dict):
                            last_episode_reward = {
                                "1": float(ler.get("1", ler.get(1, 0.0))),
                                "2": float(ler.get("2", ler.get(2, 0.0))),
                            }
                        lms = m.get("last_match_score")
                        if isinstance(lms, dict):
                            last_match_score = {
                                "1": float(lms.get("1", lms.get(1, 0.0))),
                                "2": float(lms.get("2", lms.get(2, 0.0))),
                            }
                        last_winner = int(m.get("last_winner", 0))
                    except Exception:
                        pass

                if done:
                    if advance and trainer.current_index < trainer.population_size:
                        send_message(
                            sock_file,
                            {
                                "type": "config",
                                "watch_mode": bool(args.watch),
                                "time_scale": float(args.time_scale),
                                "ga_state": trainer.get_ga_state(args.mutation_rate, args.mutation_std),
                            },
                        )

                    send_message(sock_file, {"type": "reset"})

                    if live_rounds:
                        last_wins = None
                        last_match_over = False
                        last_live_score = None

                    if advance and trainer.current_index >= trainer.population_size:
                        stats = trainer.finalize_generation()
                        done_generations += 1
                        if not args.quiet:
                            print(
                                f"gen {trainer.generation - 1} | best {stats['best']:.3f} | "
                                f"avg {stats['avg']:.3f} | best_ever {stats['best_ever']:.3f}"
                            )
                            sys.stdout.flush()

                        if save_path and trainer.best_genome is not None:
                            save_genome(save_path, trainer.best_genome)
                        append_generation_log(
                            log_path,
                            trainer.generation - 1,
                            stats,
                            args.population,
                            args.elite,
                            args.mutation_rate,
                            args.mutation_std,
                            args.episodes_per_genome,
                            args.opponent,
                            args.crossover,
                        )

                        send_message(
                            sock_file,
                            {
                                "type": "config",
                                "watch_mode": bool(args.watch),
                                "time_scale": float(args.time_scale),
                                "ga_state": trainer.get_ga_state(args.mutation_rate, args.mutation_std),
                            },
                        )

                        if generations_limit > 0 and done_generations >= generations_limit:
                            break

    except (ConnectionError, OSError) as exc:
        exit_code = 2
        last_error = str(exc)
    finally:
        if result_path:
            ensure_parent_dir(result_path)
            payload = {
                "ok": exit_code == 0,
                "exit_code": int(exit_code),
                "error": last_error,
                "host": str(args.host),
                "port": int(args.port),
                "generation": int(trainer.generation),
                "population": int(args.population),
                "elite": int(args.elite),
                "episodes_per_genome": int(args.episodes_per_genome),
                "opponent": str(args.opponent),
                "crossover": bool(args.crossover),
                "mutation_rate": float(args.mutation_rate),
                "mutation_std": float(args.mutation_std),
                "win_weight": float(args.win_weight),
                "reward_scale": float(args.reward_scale),
                "best_ever": float(trainer.best_fitness),
                "best_stats": dict(trainer.best_stats) if isinstance(trainer.best_stats, dict) else {},
                "load_path": str(load_path),
                "opponent_load_path": str(opponent_load_path),
                "save_path": str(save_path),
                "last_episode_reward": dict(last_episode_reward),
                "last_match_score": dict(last_match_score),
                "last_winner": int(last_winner),
                "timestamp": int(time.time()),
            }
            with open(result_path, "w", encoding="utf-8") as file:
                json.dump(payload, file)

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
