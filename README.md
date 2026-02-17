# Project PVP

Jogo 2D PvP estilo TowerFall, com foco em movimentação precisa e hitboxes consistentes.

## Objetivo do MVP
- Combate PvP local 2–4 players.
- Movimentação responsiva (dash, salto, wall‑jump).
- Hitbox/hurtbox claras e determinísticas.

## Stack
- Engine: **Godot 4.x**
- Linguagem: **GDScript**
- Plataforma inicial: **PC (Steam)**

## Como abrir
1. Instale o Godot 4.x.
2. Abra o arquivo `project.godot`.

## Estrutura
- `scenes/` – cenas principais
- `scripts/` – scripts do jogo
- `assets/` – arte e áudio
- `docs/` – planejamento e especificações

## Pipeline de assets (PixelLab)
Para importar exports do PixelLab no formato esperado pelo jogo, use o script:

```bash
python engine/tools/pixellab_import.py <zip_path> --name <nome_personagem>
```

Ou para importar varios ZIPs de uma pasta:

```bash
python engine/tools/pixellab_import.py <pasta_com_zips>
```

Ele extrai para `assets/characters/<nome_personagem>/pixellab/` e mantém a estrutura
`rotations/`, `animations/` e `metadata.json`. O script tambem gera
`pixellab_manifest.json` com lista de animacoes/direcoes e contagem de frames.

## Teste de determinismo
Para garantir que o loop principal continua determinístico (pré-requisito do modo online/rollback), rode:

```bash
godot4 --headless --fixed-fps 60 --script res://engine/tools/determinism_tester.gd --frames=720 --runs=3 --seed=1337
```

O tester instancia `Main.tscn`, injeta inputs pseudo-aleatórios via `PlayerInput.push_frame` e compara o hash final de cada execução. Se algum hash divergir, o comando retorna código 1. Ajuste `--frames`, `--runs` ou `--seed` conforme necessário.

## Status
Projeto em fase de esqueleto e planejamento inicial.
