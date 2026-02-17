# Gerador (Pixellab/MCP)

Esta pasta reúne um planejamento robusto + arquivos utilitários para gerar sprites/rotações/animações via Pixellab (MCP) e importar os assets para `assets/characters/...`.

**Entradas principais do repositório**
- [pixellab_pipeline.py](file:///c:/Users/user/Desktop/ProjectPVP/engine/tools/pixellab_pipeline.py): pipeline principal (submit/import/batch, styles, shapes).
- [pixellab_import.py](file:///c:/Users/user/Desktop/ProjectPVP/engine/tools/pixellab_import.py): import do ZIP para estrutura do projeto.
- [pixellab_add_animations.py](file:///c:/Users/user/Desktop/ProjectPVP/engine/tools/pixellab_add_animations.py): exemplo simples de enfileirar animações.

**Conteúdo aqui dentro**
- `PLANEJAMENTO.md`: plano detalhado de como evoluir prompts, estilos, shapes, QA e seleção.
- `PLAYBOOK_FUTURAS_IAS.md`: instruções objetivas para futuras IAs trabalharem no mesmo padrão.
- `PROMPTING.md`: modelo de prompt robusto (literal, com tags) e regras anti-genérico.
- `mcp_client.py`: cliente MCP (JSON-RPC sobre HTTP) reutilizável.
- `queue_animations.py`: enfileira animações via MCP usando um preset JSON.
- `generate_pack.py`: cria lote (submit-batch) e importa (import-batch).
- `rank_pack.py`: ranqueia variantes por `qa_score` a partir de `engine/tools/_cache/pixellab_jobs/pixellab/jobs`.
- `presets/`: presets JSON (animações, packs de exemplo).

## Pré-requisitos

1) Ter o servidor `pixellab` configurado no Trae em `%APPDATA%/Trae/User/mcp.json`.
2) Ter Python instalado.

O pipeline lê `url` e `Authorization` automaticamente do `mcp.json` do Trae.

## Uso rápido (linha de comando)

Listas disponíveis:
```bash
python engine/tools/pixellab_pipeline.py list-styles
python engine/tools/pixellab_pipeline.py list-shapes
```

Gerar 10 variações e importar:
```bash
python engine/tools/pixellab_pipeline.py submit-batch --id meu_pack --name Meu+Pack --description archer+hero,+silhouette-first --preset pvp_archer_side_128 --styles "style_desert_nomad,style_samurai_archer" --shapes "lanky,bulky,compact" --count 10 --no-animations
python engine/tools/pixellab_pipeline.py import-batch --id meu_pack --count 10 --timeout 7200 --interval 25
```

Ranquear:
```bash
python gerador/rank_pack.py --id meu_pack --top 5
```

## Uso rápido (animações)

Enfileirar animações para um `character_id`:
```bash
python gerador/queue_animations.py --character-id <UUID> --preset gerador/presets/animations_archer.json
```
