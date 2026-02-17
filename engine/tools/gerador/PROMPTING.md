# Prompting (tag-based) — padrão recomendado

## Por que o prompt anterior gerava “corpo oval genérico”

O gerador tende a colapsar para um template humano padrão quando:
- o prompt está longo e abstrato;
- existem contradições;
- faltam âncoras de silhueta e proporção;
- “regras” competem com “identidade” (ex.: muitas instruções vs poucas tags fortes).

## Estrutura mínima (boa)

Base (curta):

```
pixel art character sprite, full-body, iconic silhouette, readable at 128px, 8-direction side view,
archer hero, silhouette-first, weapon held in hands, bowstring drawn, arrow nocked,
distinct quiver, clear emblem,
crisp pixel clusters, 1-2px outline, strong 3-tone shading
```

Depois acrescentar:
- `--shape`: define `BODY/PROPORTIONS/SILHOUETTE`.
- `--style`: define `theme/head/weapon/palette/motif`.
- auto traits: 4-6 detalhes pequenos.

## “Negação” que funciona (concreta)

Evitar frases como “não genérico”.

Preferir:
- `no plain tshirt`
- `no plain pants`
- `no modern jeans`
- `no melee weapons`

## Regras de consistência

1) Um `BODY:` por variante.
2) Um `PROPORTIONS:` por variante.
3) Um `weapon:` principal por variante.
4) `head` precisa ser uma forma simples (coroa, visor, máscara, capacete).
5) `emblem` precisa aparecer como marca no peito/cinto/capa.

## Como aumentar variação (sem virar ruído)

Checklist:
- Aumentar count (10 -> 20) e depois filtrar.
- Rotacionar `--styles` e `--shapes`.
- Travar o que funcionou e variar apenas 1 categoria por vez.

Exemplo de iteração:
1) Pack A: variar apenas `--shape`, fixar style.
2) Pack B: variar apenas `--style`, fixar shape.
3) Pack C: usar os 2 melhores (shape/style) e gerar 20.

