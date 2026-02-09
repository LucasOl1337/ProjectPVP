import argparse
import re
import shutil
import time
from pathlib import Path


def _parse_score(path: Path) -> float:
    m = re.search(r"_score_(-?\d+(?:\.\d+)?)", path.name)
    if not m:
        return float("-inf")
    try:
        return float(m.group(1))
    except Exception:
        return float("-inf")


def _parse_gen_n(path: Path) -> tuple[int, int]:
    mg = re.search(r"_G(\d{4})_", path.name)
    mn = re.search(r"_N(\d{6})_", path.name)
    g = int(mg.group(1)) if mg else 0
    n = int(mn.group(1)) if mn else 0
    return g, n


def _parse_round_seed(path: Path) -> tuple[int, int]:
    mr = re.search(r"round_(\d{4})", str(path))
    ms = re.search(r"seed_(\d{2})_", path.name)
    rid = int(mr.group(1)) if mr else 0
    sid = int(ms.group(1)) if ms else 99
    return rid, sid


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Restaura o best_genome.json a partir da liga")
    parser.add_argument("--bot", required=True, help="Nome do bot (ex: agressivo)")
    parser.add_argument("--mode", default="best_score", choices=("best_score", "latest"))
    parser.add_argument(
        "--source",
        default="league",
        choices=("league", "matchups"),
        help="Origem para restauração: 'league' ou 'matchups' (state/top)",
    )
    args = parser.parse_args()

    bot = "".join(ch for ch in str(args.bot).strip().lower() if ch.isalnum() or ch in ("-", "_"))
    if not bot:
        return 2

    source_label = str(args.source)
    if args.source == "matchups":
        matchups_dir = root / "BOTS" / bot / "matchups"
        if not matchups_dir.exists():
            print(f"Matchups não encontrado: {matchups_dir}")
            return 3
        snaps = list(matchups_dir.glob("**/state/round_*/top/*.json"))
        if not snaps:
            print(f"Sem seeds em state/top: {matchups_dir}")
            return 4
    else:
        league_dir = root / "BOTS" / bot / "league"
        if not league_dir.exists():
            print(f"Liga não encontrada: {league_dir}")
            return 3
        snaps = list(league_dir.glob("*.json"))
        if not snaps:
            print(f"Liga vazia: {league_dir}")
            return 4

    if args.mode == "latest":
        if args.source == "matchups":
            chosen = max(
                snaps,
                key=lambda p: (
                    _parse_round_seed(p)[0],
                    _parse_gen_n(p)[0],
                    -_parse_round_seed(p)[1],
                    p.stat().st_mtime,
                ),
            )
        else:
            snaps.sort(key=lambda p: p.stat().st_mtime, reverse=True)
            chosen = snaps[0]
    else:
        snaps.sort(key=_parse_score, reverse=True)
        chosen = snaps[0]

    g, n = _parse_gen_n(chosen)
    score = _parse_score(chosen)

    best_path = root / "BOTS" / bot / "best_genome.json"
    shutil.copyfile(chosen, best_path)

    meta_path = root / "BOTS" / bot / "current_bot.json"
    meta_path.write_text(
        (
            "{\n"
            f"  \"source\": \"{str(chosen)}\",\n"
            f"  \"source_rel\": \"{str(chosen)}\",\n"
            f"  \"promoted_to\": \"{str(best_path)}\",\n"
            "  \"round\": 0,\n"
            f"  \"best\": {float(score if score == score else 0.0)},\n"
            f"  \"best_ever\": {float(score if score == score else 0.0)},\n"
            "  \"worker_id\": -1,\n"
            f"  \"individual\": {int(n)},\n"
            "  \"islands_round\": 0,\n"
            f"  \"generation\": {int(g)},\n"
            "  \"port\": 0,\n"
            "  \"episodes_per_genome\": 0,\n"
            "  \"mutation_rate\": 0.0,\n"
            "  \"mutation_std\": 0.0,\n"
            "  \"opponent\": \"\",\n"
            "  \"time_scale\": 0.0,\n"
            "  \"seed_used\": \"\",\n"
            "  \"result_path\": \"\",\n"
            f"  \"timestamp\": {int(time.time())}\n"
            "}\n"
        ),
        encoding="utf-8",
    )

    print(f"Restaurado {bot} ({source_label}): {chosen.name} -> best_genome.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
