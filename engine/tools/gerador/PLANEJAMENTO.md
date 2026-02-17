# Planejamento (robusto) — Gerador de sprites e animações

## Objetivo

Construir um sistema previsível e iterável para:
- Gerar sprites com variação real de silhueta/identidade (evitar “corpo oval genérico”).
- Importar assets para o projeto com estrutura consistente.
- Gerar animações (walk/run/dash/aim/etc.) por template e importar.
- Permitir que humanas e futuras IAs colaborem com o mesmo padrão de qualidade.

O Pixellab/MCP não é uma IA “que entende intenção”; ele responde melhor a **tags literais**, sem abstrações (“faça ficar bom”, “não genérico”).

## Princípios

1) **Prompt literal e tag-based**
   - Prefira: `BODY: ...`, `PROPORTIONS: ...`, `SILHOUETTE: ...`, `weapon: ...`, `head: ...`, `emblem: ...`, `palette: ...`.
   - Evite: “não genérico”, “criativo”, “faça melhor”, “parecido com X” (depende muito do modelo).

2) **Pouca entropia + âncoras fortes**
   - O modelo colapsa para um template se as âncoras forem fracas.
   - Uma boa âncora por categoria é melhor que 10 frases vagas.

3) **Sem contradições**
   - Não misturar dois `BODY:` diferentes.
   - Não misturar `weapon: wrist crossbow` com `weapon: longbow` ao mesmo tempo.
   - Se `--style/--shape` definem `weapon/head/palette`, remova do resto.

4) **Varie o seed de forma controlada**
   - Seed estável por variante = reprodutibilidade.
   - “Criatividade” aqui significa variar escolhas discretas (packs) e proporções.

## Arquitetura do prompt

### Camadas

1) **Base** (mínimo necessário)
   - Tipo: `pixel art character sprite`
   - View/tamanho: `readable at 128px, 8-direction side view`
   - Função: `archer hero`
   - Regras de render: `crisp pixel clusters, 1-2px outline, strong 3-tone shading`

2) **Shape pack** (`--shape` / `--shapes`)
   - Objetivo: forçar massa e proporções.
   - Exemplos: `lanky`, `bulky`, `compact`, `longcoat`, `hunched`.
   - Deve gerar 1-2 linhas no máximo (âncora forte, sem ruído).

3) **Style pack** (`--style` / `--styles`)
   - Objetivo: criar identidade visual consistente (head/weapon/palette/motif).
   - Deve ser pequeno e “tag-like”.

4) **Traits automáticos** (auto_traits)
   - Objetivo: adicionar 3-6 detalhes não contraditórios.
   - Deve respeitar “lock”: se estilo já define `weapon/head/palette`, não re-sorteia esses campos.

5) **Constraints** (anti-queda no genérico)
   - Evitar frases abstratas.
   - Usar negações concretas quando necessário: `no plain tshirt`, `no plain pants`, `no melee weapons`.

## Controle de “criatividade”

Como o modelo não tem um knob explícito de criatividade, o controle deve ser feito por:
- Aumentar o espaço de busca (mais variantes).
- Variações discretas: `--styles` e `--shapes` com rotação.
- Ajustar `ai_freedom` no preset (se disponível no preset usado) com valores moderados.
- Ajustar proporções (custom proportions) para não colapsar no mesmo “boneco”.

Recomendação de iteração:
1) Gerar 10 variantes com `--styles` + `--shapes`.
2) Ranquear por `qa_score`.
3) Selecionar manualmente top 2-3 (porque `qa_score` mede contraste/ocupação, não “beleza”).
4) Regerar 20 variantes a partir das 2-3 combinações vencedoras.

## QA e seleção

### Métricas automáticas

O pipeline calcula `qa_score` com base em:
- fração de área opaca,
- bounding box,
- variedade de cores,
- contraste.

Isso ajuda a evitar sprites “lavados”/pouco contrastados, mas não garante boa direção de arte.

### Critérios humanos (rápidos)

Checklist de 10s por sprite:
- Silhueta diferente do resto?
- `head` é reconhecível a 64px?
- `weapon` domina a leitura e está coerente?
- `palette` tem 2 cores + 1 acento?
- O corpo não virou “oval padrão”?

## Animações

### Filosofia

Animações tendem a degradar identidade. O segredo é:
- manter o corpo simples e consistente;
- usar `template_animation_id` adequado;
- manter `action_description` curto e literal.

### Pipeline sugerido

1) Gerar/importar rotações.
2) Selecionar 1 candidato.
3) Enfileirar animações principais (walk/run/aim/dash).
4) Importar ZIP de animações quando pronto.

## “Como uma futura IA deve trabalhar”

Regras operacionais:
- Sempre consultar `list-styles` e `list-shapes` antes de criar um pack.
- Nunca colocar “não genérico” no texto; trocar por 2-3 âncoras concretas.
- Se a maioria está ruim, aumentar o espaço de busca + travar os campos que funcionaram.
- Registrar no job JSON quais foram `style` e `shape` usados.

