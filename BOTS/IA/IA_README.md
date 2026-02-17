# IA_README (Project PVP)



```yaml

doc_id: IA_README

doc_role: "documentação viva da IA"

last_verified_by: "Trae IDE"

protocol:

  name: training-bridge

  version: 1

canonical_contracts:

  observation_builder: "engine/scripts/modules/bot_observation_builder.gd"
  action_schema: "engine/scripts/modules/bot_action_frame.gd"
  python_trainer: "engine/tools/training_genetic_ga.py"

```



Este documento descreve **como a IA funciona hoje** no Project PVP (bots in-game + treino externo via Python), quais são os **contratos de dados** (observação/ação/bridge), e como **continuar evoluindo** sem quebrar o jogo, o treino ou os artefatos em `BOTS/IA/`.


## Objetivo e escopo



Este projeto tem dois “modos” principais de IA:



- **Bots in-game (Godot)**: decisões locais por policy (`simple`, `genetic`, `external`), convertidas em input do jogador.

- **Treinamento externo (Python)**: o jogo envia observações e recompensas via TCP/JSON; o agente responde com ações para cada bot.



O diretório `BOTS/IA/` é o **hub de configuração e artefatos**: configs do treino, bots (recompensas por jogador), pesos do genoma e logs.


## Mapa rápido de arquivos (source of truth)



**Entradas principais (Godot)**

- Loop do treino e bridge: [training_manager.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/training_manager.gd), [training_bridge.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/training_bridge.gd)

- Observação (schema canônico): [bot_observation_builder.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/bot_observation_builder.gd)

- Execução de ações como input: [bot_driver.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/bot_driver.gd), [bot_action_frame.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/bot_action_frame.gd)

- Policy genética (inferência local): [bot_policy_genetic.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/bot_policy_genetic.gd)

- Orquestração (toggle treino, auto-start do trainer): [Main.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/Main.gd)



**Entradas principais (Python)**

- Treinador genético + bridge client: [training_genetic_ga.py](file:///c:/Users/user/CascadeProjects/Project%20PVP/tools/training_genetic_ga.py)



**Contratos documentados**

- Protocolo TCP/JSON: [bridge.md](file:///c:/Users/user/CascadeProjects/Project%20PVP/IA/connections/bridge.md)



## Estrutura da pasta `BOTS/IA/`


- `BOTS/IA/config/`
  - `training.json`: host/porta do treino, watch mode, time scale (consumido pelo Python).

  - `ga.json`: hiperparâmetros do algoritmo genético, paths de logs e pesos.

  - `rewards.json`: pesos default de recompensa/punição.

  - `rounds.json`: limites de episódio/rodada e logging de rodada/evolução.

  - `trainer.json`: config do **auto-start do Python pelo Godot** (quando treino está ON).

- `BOTS/` (novo sistema)

  - `agressivo.json`, `estrategista.json`: nomes + reward override por jogador.

- `BOTS/IA/weights/`
  - `best_genome.json`: genoma salvo (pesos) usado pela policy `genetic`.

- `BOTS/IA/logs/`
  - `genetic_log.csv`: log por geração (Python).

  - `round_stats.csv`, `evolution.csv`: logs de rodada/janela de evolução (Godot).

  - `*.translation` / `*.import`: artefatos auxiliares para abrir/plotar CSVs (mantidos no repo).

- `BOTS/IA/scripts/`
  - `run_training.bat`: forma rápida de rodar o treino (instala `numpy` e executa o trainer).



## Como funciona (visão de alto nível)



### 1) Bots in-game (sem treino externo)



1. O jogo chama `BotDriver.step(delta)` quando bots estão habilitados.

2. O `BotDriver` gera uma observação via `BotObservationBuilder.build(...)`.

3. A policy selecionada produz um `Dictionary` de ação (`simple`/`genetic`/`external`).

4. A ação é convertida em um frame de input via `BotActionFrame.build(frame_number, action)`.

5. O frame é injetado no `PlayerInput` do jogador (`push_frame`), e o `Player` consome como se fosse input real.



### 2) Treino externo (Godot ↔ Python)



1. Com treino ON, o Godot sobe um servidor TCP local (`TrainingBridge`), e opcionalmente inicia o Python automaticamente.

2. O `TrainingManager` emite mensagens `step` em taxa fixa (60 Hz) contendo `obs`, `reward`, `done` + `metrics/info`.

3. O Python lê cada `step`, escolhe ações para P1/P2 e responde com uma mensagem `action`.

4. O Godot aplica as ações recebidas nos bots via `BotDriver.set_external_action(...)`, e a policy `external` passa a “devolver” a última ação recebida.

5. Quando `done` é true, o Python envia `reset`; o Godot reseta o episódio e reinicia a rodada.



## Contrato de dados (canônico)



Esta seção é a referência para **compatibilidade**. Mudanças aqui exigem atualização coordenada no Godot e no Python.



### Protocolo (Training Bridge) — TCP/JSON por linha



- Transporte: TCP, JSON newline-delimited (`\n` no final).

- Servidor: Godot (`TrainingBridge`). Cliente: Python (`socket.create_connection`).



**Mensagens do Godot → Python**

- `{"type":"hello","protocol":1}`: enviado quando o bridge conecta (e pode ser reenviado).

- `{"type":"step", ...}`: enviado a cada tick de treino.

- `{"type":"episode_start"}`: emitido quando o Godot reseta métricas de episódio (útil para sincronização; o Python pode ignorar).



**Mensagens do Python → Godot**

- `{"type":"config","watch_mode":bool,"time_scale":float,"ga_state":{...}}`: configura visualização/velocidade e (opcional) estado do GA para overlay.

- `{"type":"action","actions":{ "1":{...}, "2":{...} }}`: ação por jogador.

- `{"type":"reset"}`: solicita reset de episódio/rodada.



**Compatibilidade**

- Campos extras devem ser adicionados de forma opcional (sempre usando `.get(...)` com default no leitor).

- Não remova campos existentes sem bump de `protocol`.



### Mensagem `step` (estrutura)



Campos reais enviados hoje (ver [training_manager.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/training_manager.gd)):



- `type`: `"step"`

- `frame`: `int`

- `obs`: `{ "1": Observation, "2": Observation }`

- `reward`: `{ "1": float, "2": float }`

- `done`: `bool`

- `info`: `{ "round_index": int, "match_over": bool }`

- `metrics`: objeto grande com telemetria do treino/rodada/GA (usado pelo HUD/overlay)



### Observation (schema)



Schema produzido por `BotObservationBuilder.build(...)` (ver [bot_observation_builder.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/bot_observation_builder.gd)):



- `frame`: `int`

- `delta`: `float` (delta do tick de treino)

- `self`: snapshot “limpo” do jogador

  - `position`: `Vector2` (no Godot) / `{x,y}` ou `[x,y]` (quando serializado)

  - `velocity`: `Vector2`

  - `facing`: `int`

  - `is_dead`: `bool`

  - `arrows`: `int`

  - `on_floor`: `bool`

  - `on_wall`: `bool`

- `opponent`: mesmo schema de `self`

- `delta_position`: `Vector2` (`opponent_position - self_position`)

- `distance`: `float`

- `match`:

  - `round_active`: `bool`

  - `match_over`: `bool`

  - `wins`: `Dictionary` (keys podem vir como `"1"/"2"` ou `1/2`)

- `raw`: snapshots brutos (`get_state()` dos players), úteis para debug/expansão



### Features (vetor usado pela rede)



O treino Python e a policy genética do Godot usam (intencionalmente) o **mesmo conjunto de features** (normalizadas por `POS_SCALE/VEL_SCALE`).



Referência:

- Python: função `obs_to_features` em [training_genetic_ga.py](file:///c:/Users/user/CascadeProjects/Project%20PVP/tools/training_genetic_ga.py)

- Godot: `_obs_to_features` em [bot_policy_genetic.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/bot_policy_genetic.gd)



Se você adicionar/remover features, precisa atualizar ambos para manter compatibilidade de pesos.



### Action (schema)



Action é um `Dictionary` que será convertido em frame de input via `BotActionFrame.build(...)`.



Campos usados atualmente (Python/Godot):



- `axis`: `float` (esperado -1/0/1 na policy genética; heurísticas podem gerar contínuo)

- `aim`: `Vector2` no Godot, ou `[x,y]` no Python

- `jump_pressed`: `bool`

- `shoot_pressed`: `bool`

- `shoot_is_pressed`: `bool`

- `dash_pressed`: `Array` (ex.: `["r1"]` ou `[]`)

- `melee_pressed`: `bool`

- `ult_pressed`: `bool`

- `actions`: `Dictionary` com `left/right/up/down` (compatibilidade com leitores legados)



Notas práticas:

- Para a policy `external`, qualquer campo ausente vira default no `BotActionFrame.build(...)`.

- Mantenha o schema estável: é o ponto de integração entre treino externo e simulação.



## Como o algoritmo genético funciona hoje (Python)



O `tools/training_genetic_ga.py` implementa um GA simples em cima de uma MLP:



- Rede (genoma): 3 camadas (input → hidden → hidden → output), ativação `tanh` nas duas primeiras camadas.

- Output: 7 valores

  - `0..2`: escolha do `axis` via `argmax` em `(-1, 0, 1)`

  - `3`: shoot (limiar > 0)

  - `4`: jump

  - `5`: dash

  - `6`: melee



Loop resumido:



- Cada genoma joga `episodes_per_genome` episódios.

- Fitness é acumulada a partir das recompensas do jogo (via `reward["1"]` principalmente, conforme lógica do trainer).

- Ao finalizar população:

  - escolhe elite (`elite`)

  - gera novos indivíduos por mutação (e opcionalmente crossover)

  - salva `best_genome.json` e escreve `genetic_log.csv`.



## Configurações (como cada arquivo impacta o sistema)



### `BOTS/IA/config/training.json`


- `host`, `port`: onde o Python conecta.

- `watch`: quando true, o Godot limita `time_scale` a no máximo `1.0`.

- `time_scale`: velocidade do jogo durante treino.



### `BOTS/IA/config/trainer.json` (auto-start do Python pelo Godot)


Consumido em [Main.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/Main.gd):



- `python_path`: executável (ex.: `python`)

- `script_path`: caminho do trainer (padrão `tools/training_genetic_ga.py`)

- `script_args`: args extras (ex.: `--host 127.0.0.1`)



O Godot sempre complementa args essenciais (`--port`, `--time-scale`, `--watch/--no-watch`).



### `BOTS/<perfil>.json` e `BOTS/<perfil>/rewards.json`



- `rewards.json` define defaults globais.

- `bots/agressivo.json` e `bots/estrategista.json` podem sobrescrever rewards por jogador.



Aplicação das recompensas no Godot (ver [training_manager.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/training_manager.gd)):



- `time_without_kill`: aplicado continuamente por `step_delta`.

- `time_alive`: aplicado enquanto vivo por `step_delta`.

- `kill/death`: aplicados quando detecta transição vivo → morto.



### `BOTS/IA/config/rounds.json`


- `max_steps`, `max_seconds`, `max_kills`: condições de término (`done`).

- `history_max`: janela para estatísticas de evolução.

- `log_path`: CSV de rounds (`round_stats.csv`).



### `BOTS/IA/config/ga.json`


Consumido pelo Python:



- `population`, `elite`, `mutation_rate`, `mutation_std`, `episodes_per_genome`, `crossover`

- `generations`: `0` significa infinito.

- `opponent`: modo do oponente (`best`, `baseline`, `mirror`).

- `save_path`, `load_path`, `log_path`



## Pesos (genoma) — formato e compatibilidade



`BOTS/IA/weights/best_genome.json` é lido pela policy `genetic` no Godot (ver [bot_policy_genetic.gd](file:///c:/Users/user/CascadeProjects/Project%20PVP/scripts/modules/bot_policy_genetic.gd)).


Formato esperado:



```json

{"weights":[w1,b1,w2,b2,w3,b3]}

```



Onde:



- `w1/w2/w3`: matrizes (arrays 2D)

- `b1/b2/b3`: vetores (arrays 1D)



Compatibilidade crítica:



- Se mudar o número/ordem das features ou a arquitetura da rede, pesos antigos deixam de funcionar no Godot e no Python.



## Logs e telemetria



- `IA/logs/genetic_log.csv`: por geração (Python). Campos principais: best, avg, best_ever, population, elite, mutation_rate/std, episodes_per_genome.

- `IA/logs/round_stats.csv`: por rodada/episódio (Godot). Contém winner, kills, deaths, alive_time e score.

- `IA/logs/evolution.csv`: estatísticas agregadas em janela (`history_max`) (Godot): winrate, avg_kills, avg_alive, avg_score.

- `user://training_metrics.csv`: opcional quando `logging_enabled` no treino (Godot).



Observação: em builds/export, `res://` tende a ser read-only. O `TrainingManager` tenta abrir `res://BOTS/IA/logs/...` e pode cair para `user://...` se não conseguir.


## Como continuar o desenvolvimento (extensões típicas)



### A) Adicionar campos na observação



Objetivo: enriquecer o estado para a IA.



Mudanças mínimas e coordenadas:



- Atualize `BotObservationBuilder.build(...)` para incluir o campo.

- Atualize `obs_to_features` (Python) e `_obs_to_features` (Godot) se a rede for consumir o novo campo.

- Garanta defaults seguros (`0`, `false`, `{}`) para não quebrar treinos antigos.



### B) Adicionar um novo “comando”/ação



Objetivo: permitir novos inputs (ex.: habilidade nova).



Mudanças mínimas e coordenadas:



- Atualize `BotActionFrame.build(...)` para transformar a action em input.

- Atualize as policies que produzem actions (`simple`, `genetic`, e o trainer Python) para preencher esse campo.

- Atualize o contrato desta seção (Action schema) e `IA/connections/bridge.md` se o campo transitar via bridge.



### C) Evoluir o protocolo do bridge



Recomendação:



- Só adicione campos opcionais primeiro.

- Se for mudança breaking, aumente `protocol` e mantenha compatibilidade por 1 ciclo (o leitor aceita os dois formatos).



## Regras de manutenção deste documento (para atualizações grandes)



Este arquivo deve ser tratado como “documentação viva” e precisa ser atualizado sempre que mudar comportamento/contratos.



Atualize **obrigatoriamente** as seções abaixo quando alterar os pontos correspondentes:



- **Contratos (Observation/Action/Step/Bridge)**: se mexer em `BotObservationBuilder`, `BotActionFrame`, `TrainingManager` ou no trainer Python.

- **Features**: se mexer em `obs_to_features` (Python) ou `_obs_to_features` (Godot).

- **Configurações**: se adicionar/remover keys em `BOTS/IA/config/*.json`.
- **Pesos**: se mudar arquitetura da rede ou formato de `best_genome.json`.

- **Fluxo de treino**: se mudar semântica de `done`, `reward`, reset ou tick rate.



Formato recomendado para manter fácil para IA ler e atualizar:



- Mantenha os nomes dos campos exatamente como no código (`snake_case` dos JSONs e keys do payload).

- Quando adicionar um campo novo, documente em 3 lugares: (1) contrato aqui, (2) `IA/connections/bridge.md` se trafegar no socket, (3) comentários de release no final (changelog).



## Changelog (documentação)



- 2026-02-03: criação do `IA_README.md` com contratos e mapa de fontes.

