# Playbook — futuras IAs trabalhando neste repositório

## Missão

Gerar sprites e animações com identidade e silhueta distinta, usando o pipeline existente.

O Pixellab/MCP não é “inteligente” no sentido humano: ele responde melhor quando você **constrói um sistema** (packs + tags) do que quando você pede “seja criativo”.

## Primeiro passo (sempre)

1) Ler os comandos disponíveis:
   - `python engine/tools/pixellab_pipeline.py --help`
2) Listar opções de variação:
   - `python engine/tools/pixellab_pipeline.py list-styles`
   - `python engine/tools/pixellab_pipeline.py list-shapes`

## Regras de ouro (não negociar)

1) Não usar frases abstratas:
   - proibido: “não genérico”, “mais criativo”, “faça bonito”.
   - permitido: tags literais de forma/proporção/arma/cabeça/paleta.

2) Evitar contradições:
   - se `--shape` já define `PROPORTIONS`, não adicionar outra `PROPORTIONS`.
   - se `--style` define `weapon`, não adicionar outra arma.

3) Variedade vem do espaço de busca:
   - Quando 80% sai ruim, aumente `count` e melhore o filtro.

4) Nunca confiar só no `qa_score`:
   - Use `qa_score` para eliminar sprites lavados.
   - A seleção final é humana (silhueta/identidade/arma/cabeça).

## Procedimento padrão para criar um pack

1) Definir objetivo explícito
   - Ex.: “arqueiros com shapes extremos, 2 estilos vencedores, 20 variantes”.

2) Construir prompt base curto
   - `pixel art character sprite...` + 3-6 constraints concretas.

3) Escolher variações
   - `--styles`: 2 a 6 estilos.
   - `--shapes`: 3 a 5 shapes.

4) Gerar e importar
   - `submit-batch` -> `import-batch`.

5) Ranquear e selecionar
   - usar `gerador/rank_pack.py`.
   - abrir `rotations/south.png` dos top-N.

6) Refinar
   - Travar 1-2 combinações (style+shape) vencedoras.
   - Gerar 20 variantes só nessas combinações.

## Procedimento padrão para animações

1) Escolher um sprite base (aprovado).
2) Enfileirar animações com `queue_animations.py`.
3) Importar ZIP e validar:
   - arte não “derreteu”
   - arma continua legível
   - loop está limpo

## Diagnóstico rápido

Se “todos saem com corpo oval igual”:
- aumentar força do `--shape` (usar `lanky/bulky/compact/hunched`).
- reduzir ruído no prompt base.
- não misturar duas armas.

Se “arma some ou fica nas costas”:
- reforçar: `weapon held in hands`, `weapon dominates the silhouette`.

Se “cabeça não tem identidade”:
- exigir 1 `head:` simples (máscara, visor, capacete, coroa).

