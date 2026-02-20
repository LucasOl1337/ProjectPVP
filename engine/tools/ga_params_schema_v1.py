from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Dict, Tuple


@dataclass(frozen=True)
class GeneSpec:
    type: str
    min: float | None = None
    max: float | None = None
    mut_std: float | None = None


def schema_v1() -> Dict[str, GeneSpec]:
    return {
        "movement.keep_distance": GeneSpec("float", 60.0, 420.0, 25.0),
        "movement.backoff_ratio": GeneSpec("float", 0.15, 0.95, 0.06),
        "movement.approach_deadzone_x": GeneSpec("float", 0.0, 40.0, 3.0),
        "shoot.min_distance": GeneSpec("float", 0.0, 120.0, 6.0),
        "shoot.max_distance": GeneSpec("float", 120.0, 900.0, 30.0),
        "shoot.y_tolerance": GeneSpec("float", 30.0, 420.0, 18.0),
        "shoot.hold_seconds": GeneSpec("float", 0.05, 0.30, 0.02),
        "shoot.intent_cooldown": GeneSpec("float", 0.0, 0.8, 0.06),
        "shoot.dx_min": GeneSpec("float", 0.0, 160.0, 10.0),
        "dash.use": GeneSpec("bool"),
        "dash.range": GeneSpec("float", 100.0, 1200.0, 45.0),
        "dash.probability": GeneSpec("float", 0.0, 1.0, 0.10),
        "dash.intent_cooldown": GeneSpec("float", 0.0, 1.0, 0.08),
        "jump.chase_dy": GeneSpec("float", 40.0, 520.0, 22.0),
        "jump.intent_cooldown": GeneSpec("float", 0.0, 1.0, 0.08),
        "melee.range": GeneSpec("float", 30.0, 180.0, 10.0),
        "melee.intent_cooldown": GeneSpec("float", 0.0, 1.0, 0.08),
        "safety.avoid_ledges": GeneSpec("bool"),
        "safety.avoid_walls": GeneSpec("bool"),
        "safety.wall_stop_distance": GeneSpec("float", 0.0, 90.0, 6.0),
        "safety.max_safe_drop_distance": GeneSpec("float", 0.0, 420.0, 18.0),
        "safety.ceiling_block_distance": GeneSpec("float", 0.0, 160.0, 8.0),
        "safety.air_ground_distance": GeneSpec("float", 0.0, 260.0, 12.0),
        "objective.collect_arrow_weight": GeneSpec("float", 0.0, 2.0, 0.12),
        "objective.fight_weight": GeneSpec("float", 0.0, 2.0, 0.12),
        "objective.pick_interval": GeneSpec("float", 0.02, 0.40, 0.03),
    }


def defaults_v1() -> Dict[str, Any]:
    return {
        "movement.keep_distance": 220.0,
        "movement.backoff_ratio": 0.6,
        "movement.approach_deadzone_x": 10.0,
        "shoot.min_distance": 20.0,
        "shoot.max_distance": 640.0,
        "shoot.y_tolerance": 140.0,
        "shoot.hold_seconds": 0.14,
        "shoot.intent_cooldown": 0.18,
        "shoot.dx_min": 30.0,
        "dash.use": True,
        "dash.range": 650.0,
        "dash.probability": 0.25,
        "dash.intent_cooldown": 0.35,
        "jump.chase_dy": 140.0,
        "jump.intent_cooldown": 0.25,
        "melee.range": 85.0,
        "melee.intent_cooldown": 0.30,
        "safety.avoid_ledges": True,
        "safety.avoid_walls": True,
        "safety.wall_stop_distance": 14.0,
        "safety.max_safe_drop_distance": 85.0,
        "safety.ceiling_block_distance": 18.0,
        "safety.air_ground_distance": 55.0,
        "objective.collect_arrow_weight": 0.7,
        "objective.fight_weight": 1.0,
        "objective.pick_interval": 0.08,
    }


def clamp_genes(genes: Dict[str, Any]) -> Dict[str, Any]:
    spec = schema_v1()
    out: Dict[str, Any] = {}
    for key, s in spec.items():
        if key not in genes:
            out[key] = defaults_v1().get(key)
            continue
        value = genes.get(key)
        if s.type == "bool":
            out[key] = bool(value)
            continue
        try:
            v = float(value)
        except Exception:
            v = float(defaults_v1().get(key, 0.0))
        if s.min is not None:
            v = max(float(s.min), v)
        if s.max is not None:
            v = min(float(s.max), v)
        out[key] = v
    return out


def merge_handmade_into_defaults(handmade_payload: Dict[str, Any]) -> Dict[str, Any]:
    if not isinstance(handmade_payload, dict):
        return defaults_v1()
    tuning = handmade_payload.get("tuning", {}) if isinstance(handmade_payload.get("tuning"), dict) else {}
    objectives = handmade_payload.get("objectives", {}) if isinstance(handmade_payload.get("objectives"), dict) else {}
    out = dict(defaults_v1())
    if "keep_distance" in tuning:
        out["movement.keep_distance"] = float(tuning.get("keep_distance", out["movement.keep_distance"]))
    if "shoot_range" in tuning:
        out["shoot.max_distance"] = float(tuning.get("shoot_range", out["shoot.max_distance"]))
    if "min_shoot_distance" in tuning:
        out["shoot.min_distance"] = float(tuning.get("min_shoot_distance", out["shoot.min_distance"]))
    if "shoot_hold" in tuning:
        out["shoot.hold_seconds"] = float(tuning.get("shoot_hold", out["shoot.hold_seconds"]))
    if "decision_interval_ms" in tuning:
        out["objective.pick_interval"] = float(tuning.get("decision_interval_ms", 80.0)) / 1000.0
    safety = objectives.get("safety", {}) if isinstance(objectives.get("safety"), dict) else {}
    if "avoid_ledges" in safety:
        out["safety.avoid_ledges"] = bool(safety.get("avoid_ledges", out["safety.avoid_ledges"]))
    if "avoid_walls" in safety:
        out["safety.avoid_walls"] = bool(safety.get("avoid_walls", out["safety.avoid_walls"]))
    return clamp_genes(out)


def handmade_from_genes(genes: Dict[str, Any], base_handmade: Dict[str, Any] | None = None) -> Dict[str, Any]:
    g = clamp_genes(genes if isinstance(genes, dict) else {})
    base = base_handmade if isinstance(base_handmade, dict) else {}

    out: Dict[str, Any] = dict(base)
    tuning = dict(out.get("tuning", {}) if isinstance(out.get("tuning"), dict) else {})
    objectives = dict(out.get("objectives", {}) if isinstance(out.get("objectives"), dict) else {})
    safety = dict(objectives.get("safety", {}) if isinstance(objectives.get("safety"), dict) else {})

    tuning["keep_distance"] = float(g["movement.keep_distance"])
    tuning["shoot_range"] = float(g["shoot.max_distance"])
    tuning["min_shoot_distance"] = float(g["shoot.min_distance"])
    tuning["shoot_y_tolerance"] = float(g["shoot.y_tolerance"])
    tuning["shoot_dx_min"] = float(g["shoot.dx_min"])
    tuning["shoot_hold"] = float(g["shoot.hold_seconds"])
    tuning["dash_range"] = float(g["dash.range"])
    tuning["dash_probability"] = float(g["dash.probability"])
    tuning["melee_range"] = float(g["melee.range"])
    tuning["decision_interval_ms"] = int(round(float(g["objective.pick_interval"]) * 1000.0))

    safety["avoid_ledges"] = bool(g["safety.avoid_ledges"])
    safety["avoid_walls"] = bool(g["safety.avoid_walls"])
    objectives["enabled"] = bool(objectives.get("enabled", True))
    objectives["pick_interval_ms"] = int(tuning["decision_interval_ms"])
    objectives["safety"] = safety

    rules_in = out.get("rules", [])
    rules: list = list(rules_in) if isinstance(rules_in, list) else []

    def upsert(rule: Dict[str, Any]) -> None:
        rid = str(rule.get("id", "") or "").strip()
        if not rid:
            return
        for i in range(len(rules)):
            existing = rules[i]
            if isinstance(existing, dict) and str(existing.get("id", "") or "") == rid:
                rules[i] = rule
                return
        rules.insert(0, rule)

    upsert(
        {
            "id": "ga_avoid_front_wall",
            "when": {"self_sensor_front_wall_distance_lt": float(g["safety.wall_stop_distance"]), "self_on_floor": True},
            "do": {"axis": "stop", "aim": "toward"},
        }
    )
    upsert(
        {
            "id": "ga_avoid_big_drop",
            "when": {"self_sensor_ledge_ground_distance_gt": float(g["safety.max_safe_drop_distance"]), "self_on_floor": True},
            "do": {"axis": "stop", "aim": "toward"},
        }
    )
    upsert(
        {
            "id": "ga_block_jump_low_ceiling",
            "when": {"self_sensor_ceiling_distance_lt": float(g["safety.ceiling_block_distance"])},
            "do": {"jump": False, "dash": False},
        }
    )
    upsert(
        {
            "id": "ga_disable_air_moves",
            "when": {"self_sensor_ground_distance_gt": float(g["safety.air_ground_distance"])},
            "do": {"jump": False, "dash": False},
        }
    )

    out["tuning"] = tuning
    out["objectives"] = objectives
    out["rules"] = rules
    return out


def distance(a: Dict[str, Any], b: Dict[str, Any]) -> float:
    spec = schema_v1()
    d = 0.0
    for key, s in spec.items():
        va = a.get(key)
        vb = b.get(key)
        if s.type == "bool":
            d += 1.0 if bool(va) != bool(vb) else 0.0
            continue
        try:
            fa = float(va)
        except Exception:
            fa = float(defaults_v1().get(key, 0.0))
        try:
            fb = float(vb)
        except Exception:
            fb = float(defaults_v1().get(key, 0.0))
        scale = 1.0
        if s.max is not None and s.min is not None:
            span = float(s.max) - float(s.min)
            if span > 1e-9:
                scale = 1.0 / span
        d += (fa - fb) * (fa - fb) * scale * scale
    return math.sqrt(max(0.0, d))
