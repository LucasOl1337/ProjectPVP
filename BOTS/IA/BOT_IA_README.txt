BOT IA — Guia do sistema (Perfis em BOTS/)

Visão geral
Este projeto usa um único sistema de IA baseado em perfis, localizado na pasta BOTS/.
Cada perfil define parâmetros de treino e pesos de score (rewards). O treino gera e atualiza automaticamente o melhor genoma (best_genome.json) dentro da pasta do perfil.

Objetivo
- Treinar bots diferentes (ex.: default, agressivo) do zero, com parâmetros próprios.
- Salvar tudo isolado por perfil, sem misturar pesos/estados.
- Permitir escolher, no menu inicial do jogo, qual perfil controla P1 e qual perfil controla P2.

Conceitos
1) Perfil (BOTS/<perfil>.json)
Um arquivo de perfil descreve:
- rewards: pesos de score
- islands: parâmetros do treino paralelo (workers)

2) Artefatos do perfil (BOTS/<perfil>/...)
Ao iniciar um treino pelo runner, são gerados/atualizados arquivos dentro de uma pasta do perfil:
- rewards.json: pesos base usados pelo jogo/headless para calcular rewards
- bot_p1.json / bot_p2.json: overrides por jogador (opcional)
- seed_genome.json: genoma inicial do perfil
- best_genome.json: melhor genoma atual do perfil (atualizado automaticamente)
- current_bot.json: metadados do melhor atual (round, generation, worker, best, etc.)
- state/: histórico do treino paralelo (rounds/workers/logs)

3) Bot Policy (no jogo)
O jogo tem políticas internas (simple/external/genetic/objective), mas o sistema de perfis usa apenas:
- genetic: carrega um genoma e decide ações via rede neural

No menu inicial (CharacterSelect), quando o bot está ativado, a policy usada é genetic e o genoma vem de:
res://BOTS/<perfil>/best_genome.json

Como o score (fitness) é medido
O treino calcula fitness baseada no reward por episódio.
No fluxo padrão:
- a cada step: soma termos de tempo (ex.: time_without_kill, time_alive) multiplicados por delta
- em eventos: kill e death

O reward base é definido em BOTS/<perfil>/rewards.json e tem estes campos:
- time_without_kill (geralmente negativo): penaliza enrolar sem kill
- kill (positivo): recompensa matar
- death (negativo): penaliza morrer
- time_alive (opcional): recompensa sobreviver

O reward é calculado no jogo (headless) e enviado para o trainer via bridge.
O trainer então otimiza para maximizar a fitness (maior = melhor). É normal fitness começar negativa e melhorar com o tempo.

Score vs oponente (por que “60” pode enganar)
- Um score alto pode acontecer porque o oponente é fraco ou porque o episódio tem limite de kills/tempo.
- Se você treina sempre contra o mesmo oponente, o bot pode “overfit” e parecer ótimo só naquele matchup.

Estratégia recomendada (score mais realista)
1) Treinar contra uma liga (pool) de oponentes
- Em vez de medir um indivíduo contra 1 oponente fixo, ele joga contra uma pool de oponentes (baseline + vários campeões passados).
- A fitness vira uma média do desempenho contra diferentes níveis, o que reduz dependência de um único adversário.
2) Manter snapshots de campeões
- A cada round, o campeão promovido é salvo em `BOTS/<bot>/league/` (com G/N e score).
- Essa liga vira automaticamente a pool usada para treinar bot vs bot.
3) Ajustar limites do episódio quando necessário
- Se o score “bate no teto” (ex.: sempre 60), aumente `max_kills` ou diminua `kill` no reward para dar mais resolução.
- Se o bot faz “stall”, aumente penalidade de tempo sem kill.

Arquitetura do treino (islands)
O treino paralelo funciona assim:
- O orquestrador sobe vários Godot headless (workers) em paralelo.
- Cada worker roda episódios e conversa com um trainer Python via socket/bridge (porta por worker).
- Cada worker termina e grava um result.json com best_ever e geração final.
- O orquestrador seleciona os melhores (topk) como seeds para o próximo round.
- O melhor global do perfil é promovido para BOTS/<perfil>/best_genome.json.

Persistência de geração/indivíduo (não reseta ao reabrir)
- Cada perfil mantém um contador global em BOTS/<perfil>/progress.json
  - next_generation: próxima geração global (G)
  - next_individual: offset do próximo indivíduo global (N)
- A numeração usada no console é:
  - G = geração global (incrementa a cada round)
  - N = next_individual + (worker_id+1)
  - Após um round com W workers, next_individual += W

Arquivos principais (tecnologias)
- Godot 4.x (GDScript): simulação do jogo e cálculo de rewards
- Python 3.x: treinamento genético + orquestração

Código/arquivos principais:
- tools/training_genetic_ga.py: trainer genético (GA)
- tools/island_orchestrator.py: orquestrador de rounds/workers
- treino.py: runner de perfil (gera artefatos e chama o orquestrador)
- scripts/modules/training_manager.gd + reward_shaper_default.gd: cálculo de reward e bridge
- scripts/modules/bot_policy_genetic.gd: execução do genoma no jogo

Como rodar treino por perfil (comando simples)
1) Criar/editar um perfil
Exemplo: BOTS/agressivo.json

Fonte da verdade (importante)
- O arquivo BOTS/<perfil>.json é a “fonte da verdade” do comportamento de treino do bot.
- Os arquivos dentro de BOTS/<perfil>/ (rewards.json, bot_p1.json, bot_p2.json, islands.json) são gerados automaticamente.
- Comportamento padrão: sempre que você inicia um treino pelo runner, ele regera esses arquivos a partir do perfil.
- Se quiser mudar pesos/parametros, edite sempre o BOTS/<perfil>.json.

2) Rodar treino
Treinar o perfil "agressivo":
python treino.py --agressivo

Isso:
- garante/gera os arquivos em BOTS/agressivo/
- roda o treino com workers e atualiza BOTS/agressivo/best_genome.json automaticamente

Config manual de rewards durante experimento
Existem 2 formas:

Forma A (recomendado): editar o perfil BOTS/<perfil>.json
- Ajuste rewards.base e (opcional) islands.*
- Rode novamente:
  python treino.py --<perfil>

Forma B: editar diretamente BOTS/<perfil>/rewards.json
- Se você quer manter a edição manual sem o runner sobrescrever, use:
  python treino.py --<perfil> --no-sync

Obs: o menu interativo (python treino.py sem argumentos) sempre sincroniza do perfil.

Regras globais de partida (match rules)
- Regras como `max_kills`, `max_seconds` e `max_steps` são globais e ficam em `BOTS/IA/config/match_rules.json`.
- Os perfis de bot (`BOTS/<bot>.json`) devem focar em comportamento/reward (ex.: punição por ficar sem matar), não em duração da partida.
- Dica: você pode desabilitar limites colocando 0 (ex.: `max_seconds: 0.0`, `max_steps: 0`).
  Se fizer isso, garanta que exista sempre uma condição de término no gameplay (ex.: limite de kills ou mecânica que força fim), para evitar lutas infinitas.

Console do treino (campos)
- `Score` = `match_score` do P1 no último episódio (pontuação total calculada pelo jogo).
- `Opp` = `match_score` do P2 no último episódio.
- `K=a-b` = kills do último episódio (P1-P2).
- `W` pode aparecer como `?` quando o episódio termina empatado (kills e score iguais).

Observação importante:
- O reward novo só é aplicado para workers/headless iniciados depois. Se você mudar no meio do round, reinicie o treino (Ctrl+C e rode de novo).

Como escolher IA no menu inicial (sem modo Dev)
No CharacterSelect:
- Ative o checkbox "Bot" para P1 e/ou P2.
- Escolha o perfil na lista (IA Default, IA Agressivo, ...).

O jogo vai carregar automaticamente:
P1 → res://BOTS/<perfil_p1>/best_genome.json
P2 → res://BOTS/<perfil_p2>/best_genome.json

Convenções de nomes e estrutura
- Perfis (declaração): BOTS/<perfil>.json
- Dados gerados do perfil: BOTS/<perfil>/...
- Recomenda-se usar nomes em minúsculo: default, agressivo, defensivo, etc.

Checklist de criação de um novo bot do zero
1) Crie BOTS/novo_bot.json (copie de BOTS/default.json)
2) Ajuste rewards e islands conforme objetivo
3) Rode:
   python treino.py --novo_bot
4) Observe:
   - BOTS/novo_bot/current_bot.json (metadados do melhor)
   - BOTS/novo_bot/best_genome.json (melhor genoma)
5) Use no menu inicial selecionando "IA Novo_bot" (o runner lista automaticamente arquivos .json em BOTS/)

Troubleshooting
- Console mostra best N/A por um tempo: ainda não chegou nenhum result.json válido.
- FPS baixo durante treino: muitos headless em paralelo consomem CPU. Reduza concurrency no perfil (islands.concurrency).
- Scores negativos no começo: normal com penalidade de tempo e mortes; foque na tendência de melhoria.

Mudanças no jogo (mapas, mecânicas, balanceamento)
- O modo de treino executa o próprio jogo em Godot headless carregando `res://engine/scenes/Main.tscn`.
  Então, qualquer mudança de código/arena usada pelo `Main.tscn` é automaticamente usada no treino.
- Hoje o mapa/arena do treino vem da propriedade `arena_definition` dentro do `Main.tscn`.
  Se você trocar a arena padrão (ou editar `default_arena.tres`), o treino passa a usar isso.
- Se você adicionar mapas novos e quiser treinar em mapas diferentes (ou randomizar), precisa adicionar uma seleção de arena
  (ex.: arg `--arena=res://data/arenas/novo.tres`) ou trocar o `Main.tscn`/cena usada no headless.
- Mudanças que alteram a interface do bot (dimensão das observações/ações, regras de reward, eventos) podem invalidar genomas antigos.
  Nesses casos é normal precisar retreinar e/ou regenerar seeds.
