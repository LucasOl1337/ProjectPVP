# PixelLab MCP (Automação)



Este projeto já possui um pipeline 100% automatizado para gerar/importar personagens e animações via PixelLab MCP.



## Como funciona



- `submit`: cria o job no PixelLab e salva um arquivo de job em `engine/tools/_cache/pixellab_jobs/pixellab/jobs/<id>.json`.
- `import`: tenta baixar o ZIP do job e importar para `assets/characters/<id>/pixellab/`.

- Ao importar, também cria automaticamente `data/characters/<id>.tres` (CharacterData) se não existir.

- `import-pending`: tenta importar todos os jobs pendentes.

- `generate`: cria múltiplas variações e publica a melhor em `assets/characters/<id>/pixellab/`.



## Comandos



Listar presets:



`python engine/tools/pixellab_pipeline.py list-presets`



Listar lore packs (inspirados em regiões no estilo Runeterra):



`python engine/tools/pixellab_pipeline.py list-lore`



Criar job (não espera terminar):



`python engine/tools/pixellab_pipeline.py submit --id wizard_arcano --name Wizard+Arcano --description wizard+purple+hat,+crescent+moon+pin,+glowing+staff --preset iconic_side_128 --no-animations`



Criar job com lore pack:



`python engine/tools/pixellab_pipeline.py submit --id wizard_arcano --name Wizard+Arcano --description wizard+purple+hat,+crescent+moon+pin,+glowing+staff --preset iconic_side_128 --lore targon --no-animations`



Importar quando estiver pronto:



`python engine/tools/pixellab_pipeline.py import --id wizard_arcano`



Importar todos os jobs pendentes:



`python engine/tools/pixellab_pipeline.py import-pending`



Gerar 2 variações e publicar a melhor:



`python engine/tools/pixellab_pipeline.py generate --id wizard_arcano --name Wizard+Arcano --description wizard+purple+hat,+crescent+moon+pin,+glowing+staff --preset iconic_side_128 --tries 2 --timeout 2400 --interval 20 --no-animations`



Gerar 3 variações usando lore pack e publicar a melhor:



`python engine/tools/pixellab_pipeline.py generate --id wizard_arcano --name Wizard+Arcano --description wizard+purple+hat,+crescent+moon+pin,+glowing+staff --preset iconic_side_128 --lore targon --tries 3 --timeout 2400 --interval 20 --no-animations`



## Notas de qualidade



- `size` máximo do MCP é 128; use `iconic_side_128` para mais detalhe.

- Para evitar aparência genérica, descreva itens icônicos: 1 prop assinatura, 1 emblema, 1 assimetria, e materiais.

- O pipeline salva um `qa_score` no job após importar (heurística automática de densidade/contraste/ocupação).



## Prompts prontos (Runeterra-inspirados)



Veja `docs/runeterra_inspired_prompts.md`.



