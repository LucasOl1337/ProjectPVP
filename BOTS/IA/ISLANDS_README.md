# Treino Headless em Ilhas (Orquestrador)



Este modo roda muitos treinos headless isolados (“ilhas”) e, ao fim de cada rodada, seleciona os `topk` melhores indivíduos para servir como seed da próxima rodada.



## Conceito



- Rodada `R`:

  - roda `workers` instâncias headless independentes

  - cada instância treina/evolui a partir de um seed

  - cada instância gera um `best.json` + `result.json`

- Fim da rodada:

  - ordena por `best_ever`

  - copia os `topk` melhores para `round_xxxx/top/`

  - usa esses `topk` como seeds para os próximos `workers`



## Arquivos



- Runner headless do Godot: `res://engine/tools/headless_training_runner.gd`

- Orquestrador: `engine/tools/island_orchestrator.py`
- Config: `BOTS/IA/config/islands.json`


## Como rodar (menu)



1) Ajuste o caminho do Godot em `BOTS/IA/config/islands.json` (campo `godot_exe`).
2) Rode:



```bash

python engine/tools/island_orchestrator.py menu --config BOTS/IA/config/islands.json
```



No menu você pode:

- editar `godot_exe` e parâmetros básicos

- fazer `dry-run` (só imprime comandos)

- rodar de verdade



## Como rodar (CLI)



```bash

python engine/tools/island_orchestrator.py run --config BOTS/IA/config/islands.json
```



Dry-run:



```bash

python engine/tools/island_orchestrator.py run --config BOTS/IA/config/islands.json --dry-run
```



## Saídas / Feedback



- Cada worker salva em `BOTS/IA/weights/islands/round_XXXX/worker_N/`:
  - `best.json` (genoma vencedor daquele worker)

  - `result.json` (fitness final, caminhos e parâmetros)

  - `genetic_log.csv` (log por geração)

- Os `topk` da rodada ficam em `BOTS/IA/weights/islands/round_XXXX/top/`.


