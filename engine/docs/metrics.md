# Métricas do Jogo (Unidades)

## Unidade base
- **1 unidade = 1 pixel (px)**.
- Todos os cálculos de movimento usam **px, px/s, px/s²**.

## Movimento
- `move_speed`: **px/s**
- `acceleration`: **px/s²**
- `friction`: **px/s²**
- `jump_velocity`: **px/s**
- `gravity`: **px/s²**

## Dash
- `dash_duration`: **segundos (s)**
- `dash_multiplier`: multiplica o `move_speed` (resultado em **px/s**)
- `dash_cooldown`: **segundos (s)**

## Projéteis
- `base_speed`: **px/s** (velocidade inicial)
- `min_speed`: **px/s** (velocidade mínima)
- `speed_decay`: **px/s²** (queda de velocidade)
- `gravity`: **px/s²**
- `upward_gravity_multiplier`: multiplicador de gravidade quando a flecha sobe
- `upward_speed_decay_multiplier`: multiplica a queda de velocidade quando sobe
- `gravity_ramp_ratio`: fração do percurso para chegar na gravidade máxima
- `gravity_min_scale`: escala mínima da gravidade no início do voo
- `gravity_max_scale`: escala máxima da gravidade ao final do voo
- `map_width`: **px**
- `range_ratio`: fração de `map_width`
- `gravity_delay_ratio`: fração do percurso antes da gravidade atuar

## Gravidade global
- `gameplay/global_gravity_scale`: multiplicador aplicado à gravidade do player e projéteis

## Arena
- Largura atual (paredes): **~1600 px**
- Altura útil (piso ao teto): **~840 px**

> Ajuste `map_width` em `projectile_config.gd` se o cenário mudar.
