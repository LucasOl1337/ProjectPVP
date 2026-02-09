import argparse
import json
import math
import socket
import sys
from typing import Any, Dict, List, Tuple

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.distributions import Bernoulli, Categorical

POS_SCALE = 1000.0
VEL_SCALE = 1000.0


def to_vec2(value: Any) -> Tuple[float, float]:
    if isinstance(value, dict) and "x" in value and "y" in value:
        return float(value["x"]), float(value["y"])
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        return float(value[0]), float(value[1])
    return 0.0, 0.0


def _bool(value: Any) -> float:
    return 1.0 if bool(value) else 0.0


def obs_to_features(obs: Dict[str, Any]) -> torch.Tensor:
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
        float(wins.get("1", 0)),
        float(wins.get("2", 0)),
    ]
    return torch.tensor(features, dtype=torch.float32)


def compute_aim(obs: Dict[str, Any]) -> Tuple[float, float]:
    delta_x, delta_y = to_vec2(obs.get("delta_position", [0.0, 0.0]))
    distance = math.hypot(delta_x, delta_y)
    if distance > 0:
        return delta_x / distance, delta_y / distance
    return 1.0, 0.0


class PolicyNet(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int = 128) -> None:
        super().__init__()
        self.backbone = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
        )
        self.axis_head = nn.Linear(hidden_dim, 3)
        self.shoot_head = nn.Linear(hidden_dim, 1)
        self.jump_head = nn.Linear(hidden_dim, 1)
        self.dash_head = nn.Linear(hidden_dim, 1)
        self.melee_head = nn.Linear(hidden_dim, 1)
        self.value_head = nn.Linear(hidden_dim, 1)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, ...]:
        features = self.backbone(x)
        return (
            self.axis_head(features),
            self.shoot_head(features),
            self.jump_head(features),
            self.dash_head(features),
            self.melee_head(features),
            self.value_head(features),
        )

    def act(self, obs: Dict[str, Any], device: torch.device) -> Tuple[Dict[str, Any], torch.Tensor, torch.Tensor, torch.Tensor]:
        x = obs_to_features(obs).to(device)
        axis_logits, shoot_logits, jump_logits, dash_logits, melee_logits, value = self.forward(x)

        axis_dist = Categorical(logits=axis_logits)
        axis_idx = axis_dist.sample()
        axis_map = [-1.0, 0.0, 1.0]
        axis_value = axis_map[int(axis_idx.item())]

        shoot_dist = Bernoulli(logits=shoot_logits)
        jump_dist = Bernoulli(logits=jump_logits)
        dash_dist = Bernoulli(logits=dash_logits)
        melee_dist = Bernoulli(logits=melee_logits)

        shoot_sample = shoot_dist.sample()
        jump_sample = jump_dist.sample()
        dash_sample = dash_dist.sample()
        melee_sample = melee_dist.sample()

        log_prob = (
            axis_dist.log_prob(axis_idx)
            + shoot_dist.log_prob(shoot_sample)
            + jump_dist.log_prob(jump_sample)
            + dash_dist.log_prob(dash_sample)
            + melee_dist.log_prob(melee_sample)
        )
        entropy = (
            axis_dist.entropy()
            + shoot_dist.entropy()
            + jump_dist.entropy()
            + dash_dist.entropy()
            + melee_dist.entropy()
        )

        shoot = bool(shoot_sample.item() > 0.5)
        jump = bool(jump_sample.item() > 0.5)
        dash = bool(dash_sample.item() > 0.5)
        melee = bool(melee_sample.item() > 0.5)

        aim_x, aim_y = compute_aim(obs)
        actions = {
            "axis": axis_value,
            "aim": [aim_x, aim_y],
            "jump_pressed": jump,
            "shoot_pressed": shoot,
            "shoot_is_pressed": shoot,
            "melee_pressed": melee,
            "ult_pressed": False,
            "dash_pressed": ["r1"] if dash else [],
            "actions": {
                "left": axis_value < 0.0,
                "right": axis_value > 0.0,
                "up": False,
                "down": False,
            },
        }
        return actions, log_prob, value.squeeze(-1), entropy


def compute_returns(rewards: List[float], gamma: float) -> List[float]:
    returns: List[float] = []
    running = 0.0
    for reward in reversed(rewards):
        running = reward + gamma * running
        returns.append(running)
    returns.reverse()
    return returns


def update_policy(
    optimizer: torch.optim.Optimizer,
    trajectories: List[Dict[str, torch.Tensor]],
    gamma: float,
    value_coef: float,
    entropy_coef: float,
    device: torch.device,
) -> Dict[str, float]:
    rewards = [float(t["reward"]) for t in trajectories]
    returns = compute_returns(rewards, gamma)

    returns_t = torch.tensor(returns, dtype=torch.float32, device=device)
    values = torch.stack([t["value"] for t in trajectories]).to(device)
    log_probs = torch.stack([t["log_prob"] for t in trajectories]).to(device)
    entropies = torch.stack([t["entropy"] for t in trajectories]).to(device)

    advantages = returns_t - values.detach()
    policy_loss = -(log_probs * advantages).mean()
    value_loss = F.mse_loss(values, returns_t)
    entropy_loss = -entropies.mean()

    loss = policy_loss + value_coef * value_loss + entropy_coef * entropy_loss

    optimizer.zero_grad()
    loss.backward()
    torch.nn.utils.clip_grad_norm_(optimizer.param_groups[0]["params"], 1.0)
    optimizer.step()

    return {
        "loss": float(loss.item()),
        "policy_loss": float(policy_loss.item()),
        "value_loss": float(value_loss.item()),
        "entropy": float(entropies.mean().item()),
    }


def send_message(sock_file, payload: Dict[str, Any]) -> None:
    sock_file.write((json.dumps(payload) + "\n").encode("utf-8"))
    sock_file.flush()


def main() -> int:
    parser = argparse.ArgumentParser(description="Torch A2C trainer for Project PVP")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=9009, type=int)
    parser.add_argument("--watch", action="store_true", help="Disable training speed-up")
    parser.add_argument("--time-scale", default=6.0, type=float)
    parser.add_argument("--gamma", default=0.99, type=float)
    parser.add_argument("--lr", default=3e-4, type=float)
    parser.add_argument("--value-coef", default=0.5, type=float)
    parser.add_argument("--entropy-coef", default=0.01, type=float)
    parser.add_argument("--hidden", default=128, type=int)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--save-path", default="", help="Save checkpoint path")
    parser.add_argument("--load-path", default="", help="Load checkpoint path")
    args = parser.parse_args()

    device = torch.device(args.device)
    sample_features = obs_to_features({})
    model = PolicyNet(sample_features.numel(), args.hidden).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)

    if args.load_path:
        checkpoint = torch.load(args.load_path, map_location=device)
        model.load_state_dict(checkpoint.get("model", checkpoint))
        if "optimizer" in checkpoint:
            optimizer.load_state_dict(checkpoint["optimizer"])

    config = {
        "type": "config",
        "watch_mode": bool(args.watch),
        "time_scale": float(args.time_scale),
    }

    episode = 0
    traj_p1: List[Dict[str, torch.Tensor]] = []
    traj_p2: List[Dict[str, torch.Tensor]] = []
    ep_reward_p1 = 0.0
    ep_reward_p2 = 0.0

    with socket.create_connection((args.host, args.port)) as sock:
        sock_file = sock.makefile("rwb")
        send_message(sock_file, config)

        while True:
            line = sock_file.readline()
            if not line:
                break
            message = json.loads(line.decode("utf-8"))
            msg_type = message.get("type")

            if msg_type == "hello":
                send_message(sock_file, config)
                continue

            if msg_type != "step":
                continue

            obs = message.get("obs", {})
            rewards = message.get("reward", {}) if isinstance(message.get("reward"), dict) else {}
            done = bool(message.get("done", False))

            obs_p1 = obs.get("1", {}) if isinstance(obs.get("1"), dict) else {}
            obs_p2 = obs.get("2", {}) if isinstance(obs.get("2"), dict) else {}

            action_p1, logprob1, value1, entropy1 = model.act(obs_p1, device)
            action_p2, logprob2, value2, entropy2 = model.act(obs_p2, device)

            reward_p1 = float(rewards.get("1", 0.0))
            reward_p2 = float(rewards.get("2", 0.0))

            traj_p1.append({
                "log_prob": logprob1,
                "value": value1,
                "entropy": entropy1,
                "reward": torch.tensor(reward_p1, dtype=torch.float32),
            })
            traj_p2.append({
                "log_prob": logprob2,
                "value": value2,
                "entropy": entropy2,
                "reward": torch.tensor(reward_p2, dtype=torch.float32),
            })

            ep_reward_p1 += reward_p1
            ep_reward_p2 += reward_p2

            response = {"type": "action", "actions": {"1": action_p1, "2": action_p2}}
            send_message(sock_file, response)

            if done:
                episode += 1
                combined = traj_p1 + traj_p2
                stats = update_policy(
                    optimizer,
                    combined,
                    args.gamma,
                    args.value_coef,
                    args.entropy_coef,
                    device,
                )
                print(
                    f"episode {episode} | reward_p1 {ep_reward_p1:.3f} | reward_p2 {ep_reward_p2:.3f} "
                    f"| loss {stats['loss']:.4f} | entropy {stats['entropy']:.4f}"
                )
                sys.stdout.flush()

                traj_p1.clear()
                traj_p2.clear()
                ep_reward_p1 = 0.0
                ep_reward_p2 = 0.0

                if args.save_path:
                    torch.save(
                        {"model": model.state_dict(), "optimizer": optimizer.state_dict()},
                        args.save_path,
                    )

                send_message(sock_file, {"type": "reset"})

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
