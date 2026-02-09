# Networking (planejamento)

## Estratégia
- **Local primeiro** com arquitetura determinística.
- Migração futura para **rollback netcode**.

## Pré‑requisitos
- Estado serializável
- RNG com seed fixa
- Input aplicado por frame

## Fases
1. Offline/local
2. Matchmaking simples
3. Rollback + reconciliação
