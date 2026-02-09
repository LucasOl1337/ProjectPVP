# IA (Inteligência Artificial)

Esta pasta centraliza toda a configuração e artefatos da IA do Project PVP.

## Estrutura

- `config/`
  - `training.json`: conexão com o jogo (host/porta), watch mode e time scale.
  - `rewards.json`: pesos de recompensa/punição.
  - `rounds.json`: limites de rodada (tempo/steps). Use `0` para desativar.
  - `ga.json`: hiperparâmetros do algoritmo genético, caminhos de pesos/logs.
- `connections/`
  - `bridge.md`: documentação do protocolo TCP/JSON com o jogo.
- `weights/`
  - pesos salvos (ex.: `best_genome.json`).
- `logs/`
  - logs de treinamento (ex.: `genetic_log.csv`).
- `scripts/`
  - scripts auxiliares (ex.: `run_training.bat`).

## Como usar

1. Abra o jogo em modo treino (Training ON) na porta configurada.
2. Ajuste as configs em `IA/config/`.
3. Rode o treinamento:

```bat
IA\scripts\run_training.bat
```

Ou direto via Python:

```bash
python tools/training_genetic_ga.py
```

## Controle de rodada e gerações
- **Tempo/steps da rodada**: `IA/config/rounds.json` (`max_seconds`, `max_steps`).
- **Gerações**: `IA/config/ga.json` (`generations`).
- **Mutação por rodada**: use `episodes_per_genome = 1` e `population = 1` se quiser mutar a cada rodada.
