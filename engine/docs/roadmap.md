# Roadmap (alto nível)

## Fase 0 — Pré‑produção
- Definir escopo do MVP local
- Esqueleto do projeto
- Prototipar movimento e hitbox

## Fase 1 — Core local
- Movimento completo (salto, dash, wall‑jump)
- Hitbox/hurtbox + colisões
- Loop básico de combate
- Suporte 2–4 players local

## Fase 2 — Conteúdo mínimo
- 2 arenas
- 2 personagens
- HUD básico

## Fase 3 — Online (rollback)
- Simulação determinística
- Input delay configurável
- Replays/telemetria

## Fase 4 — Online detalhado
1. **Lockstep LAN**
   - Menu Host/Join com `ENetMultiplayerPeer`
   - Sync de inputs por frame (sem previsão)
   - Determinism tester rodando em CI
2. **Rollback local peer-to-peer**
   - Buffer de estados + re-simulação com `PlayerInput.push_frame`
   - Replays baseados em input log
   - Telemetria de desync (hash por frame)
3. **Infra online básica**
   - Relay simples (Node/Go) para matchmaking/NAT punch
   - Armazenar configs (delay, rollback window) por partida
   - Upload de replays/crash dumps
