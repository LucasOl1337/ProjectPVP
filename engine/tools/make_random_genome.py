import json
import math
import os
from pathlib import Path


def _ensure_parent_dir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _randn(rng, scale: float) -> float:
    u1 = max(1e-12, float(rng.random()))
    u2 = max(1e-12, float(rng.random()))
    z0 = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
    return float(z0) * float(scale)


def _make_matrix(rng, rows: int, cols: int, scale: float):
    return [[_randn(rng, scale) for _ in range(cols)] for _ in range(rows)]


def _make_vector(rng, n: int, scale: float):
    return [_randn(rng, scale) for _ in range(n)]


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    out_path = project_root / "BOTS" / "IA" / "weights" / "seed_genome.json"

    try:
        import numpy as np  # type: ignore

        rng = np.random.default_rng()
        rand = rng.standard_normal
        use_numpy = True
    except Exception:
        import random

        rng = random.Random()
        rand = None
        use_numpy = False

    input_dim = 25
    hidden_dim = 128
    output_dim = 7
    scale = 1.0 / math.sqrt(max(1, input_dim))

    if use_numpy:
        w1 = (rand((input_dim, hidden_dim)) * scale).astype(float).tolist()
        b1 = (rand((hidden_dim,)) * scale).astype(float).tolist()
        w2 = (rand((hidden_dim, hidden_dim)) * (1.0 / math.sqrt(max(1, hidden_dim)))).astype(float).tolist()
        b2 = (rand((hidden_dim,)) * (1.0 / math.sqrt(max(1, hidden_dim)))).astype(float).tolist()
        w3 = (rand((hidden_dim, output_dim)) * (1.0 / math.sqrt(max(1, hidden_dim)))).astype(float).tolist()
        b3 = (rand((output_dim,)) * (1.0 / math.sqrt(max(1, hidden_dim)))).astype(float).tolist()
    else:
        w1 = _make_matrix(rng, input_dim, hidden_dim, scale)
        b1 = _make_vector(rng, hidden_dim, scale)
        h_scale = 1.0 / math.sqrt(max(1, hidden_dim))
        w2 = _make_matrix(rng, hidden_dim, hidden_dim, h_scale)
        b2 = _make_vector(rng, hidden_dim, h_scale)
        w3 = _make_matrix(rng, hidden_dim, output_dim, h_scale)
        b3 = _make_vector(rng, output_dim, h_scale)

    payload = {
        "weights": [w1, b1, w2, b2, w3, b3],
        "schema": {"genome_version": 1, "input_dim": input_dim, "hidden_dim": hidden_dim, "output_dim": output_dim},
    }
    _ensure_parent_dir(out_path)
    out_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    print(str(out_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

