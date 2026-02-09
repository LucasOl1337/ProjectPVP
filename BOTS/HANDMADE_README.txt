COMO CONFIGURAR O BOT HANDMADE (MANUAL)
========================================

Este bot funciona com base em uma lista de REGRAS ("rules") avaliadas em ordem.
A primeira regra cujas condições ("when") forem atendidas será executada ("do").

Arquivo de configuração: BOTS/<nome_do_perfil>/handmade.json
Exemplo padrão: BOTS/default/handmade.json

ESTRUTURA DO ARQUIVO
--------------------
{
  "tuning": { ... },    // Ajustes finos globais
  "metrics": { ... },   // Configuração de logs de debug
  "rules": [ ... ]      // Lista de regras (prioridade: topo -> baixo)
}

CAMPOS DE "tuning"
------------------
- keep_distance: Distância ideal para manter (usado se nenhuma regra definir movimento).
- decision_interval_ms: Intervalo entre decisões (ex: 60ms = ~16fps). Aumente para deixar o bot mais "lento" mentalmente.
- reaction_time_ms: Tempo de atraso simulado (ex: 150ms de reflexo humano).
- aim_noise_degrees: Erro aleatório na mira em graus (ex: 5.0).

CAMPOS DE "rules" (Regra)
-------------------------
Cada regra pode ter:
- "id": Nome único para debug (aparece no HUD).
- "description": Texto explicativo (opcional).
- "cooldown_ms": Tempo em milissegundos antes dessa regra poder ser usada novamente.
- "when": Dicionário de condições. TODAS devem ser verdadeiras para a regra ativar.
- "do": Ações a tomar se a regra ativar.

CONDICOES ("when") DISPONIVEIS
------------------------------
- distance_lt / distance_gt: Distância total menor/maior que X.
- dx_lt / dx_gt: Distância horizontal (delta X) menor/maior que X.
- dy_lt / dy_gt: Distância vertical (delta Y) menor/maior que X (positivo = oponente abaixo).
- self_arrows_gt / self_arrows_lt: Minhas flechas disponíveis.
- opponent_arrows_gt / opponent_arrows_lt: Flechas do oponente.
- self_on_floor: true/false (estou no chão?).
- opponent_on_floor: true/false (oponente no chão?).
- nearest_arrow_distance_lt: Distância até a flecha mais próxima no chão (útil para coletar).

ACOES ("do") DISPONIVEIS
------------------------
- axis: Movimento horizontal.
    - "toward": Ir em direção ao oponente.
    - "away": Fugir do oponente.
    - "stop": Parar.
    - numero (-1.0 a 1.0): Valor fixo.
- aim: Mira.
    - "toward": Mirar no oponente.
    - "facing": Mirar para onde estou olhando.
    - [x, y]: Vetor fixo (ex: [0, -1] para cima).
- shoot: true/false/"off". Atirar (segura o botão pelo tempo configurado em tuning.shoot_hold).
- melee: true/false. Ataque corpo-a-corpo.
- jump: true/false. Pular.
- dash: Dash/Esquiva.
    - "toward": Dash na direção do movimento/oponente.
    - "away": Dash para longe.
    - true: Dash simples.

DICA DE DEBUG
-------------
No jogo, ative o "Modo Dev" (F1 ou botão na tela de seleção).
No HUD de debug, a linha do bot mostrará "rule=<id_da_regra>" indicando qual regra está ativa no momento.
