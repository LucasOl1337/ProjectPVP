import argparse
import json
import math
import socket
import sys
from typing import Any, Dict, Tuple


def to_vec2(value: Any) -> Tuple[float, float]:
    if isinstance(value, dict) and "x" in value and "y" in value:
        return float(value["x"]), float(value["y"])
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        return float(value[0]), float(value[1])
    return 0.0, 0.0


def compute_action(obs: Dict[str, Any]) -> Dict[str, Any]:
    delta_x, delta_y = to_vec2(obs.get("delta_position", [0.0, 0.0]))
    distance = math.hypot(delta_x, delta_y)
    keep_distance = 90.0
    shoot_range = 520.0
    dash_range = 620.0

    axis = 0.0
    if abs(delta_x) > keep_distance:
        axis = 1.0 if delta_x > 0 else -1.0

    aim_x, aim_y = (delta_x, delta_y)
    if distance > 0:
        aim_x /= distance
        aim_y /= distance
    else:
        aim_x = 1.0
        aim_y = 0.0

    shoot = 40.0 < distance < shoot_range
    melee = distance < 80.0
    jump = delta_y < -120.0
    dash_pressed = ["r1"] if distance > dash_range else []

    return {
        "axis": axis,
        "aim": [aim_x, aim_y],
        "jump_pressed": jump,
        "shoot_pressed": shoot,
        "shoot_is_pressed": shoot,
        "melee_pressed": melee,
        "ult_pressed": False,
        "dash_pressed": dash_pressed,
        "actions": {
            "left": axis < 0.0,
            "right": axis > 0.0,
            "up": False,
            "down": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Self-play controller for Project PVP")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=9009, type=int)
    parser.add_argument("--watch", action="store_true", help="Disable training speed-up")
    parser.add_argument("--time-scale", default=6.0, type=float)
    args = parser.parse_args()

    with socket.create_connection((args.host, args.port)) as sock:
        sock_file = sock.makefile("rwb")

        config = {
            "type": "config",
            "watch_mode": bool(args.watch),
            "time_scale": float(args.time_scale),
        }
        sock_file.write((json.dumps(config) + "\n").encode("utf-8"))
        sock_file.flush()

        while True:
            line = sock_file.readline()
            if not line:
                break
            message = json.loads(line.decode("utf-8"))
            msg_type = message.get("type")

            if msg_type == "hello":
                sock_file.write((json.dumps(config) + "\n").encode("utf-8"))
                sock_file.flush()
                continue

            if msg_type != "step":
                continue

            obs = message.get("obs", {})
            action_p1 = compute_action(obs.get("1", {}))
            action_p2 = compute_action(obs.get("2", {}))
            response = {"type": "action", "actions": {"1": action_p1, "2": action_p2}}
            sock_file.write((json.dumps(response) + "\n").encode("utf-8"))
            sock_file.flush()

            if message.get("done"):
                sock_file.write((json.dumps({"type": "reset"}) + "\n").encode("utf-8"))
                sock_file.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
