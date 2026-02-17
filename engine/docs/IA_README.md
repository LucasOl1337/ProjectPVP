# IA_README — Guia rápido para IA/colaboradores



Este arquivo existe para que uma IA consiga entender rapidamente o projeto, navegar no código e aplicar mudanças com segurança.



## Visão geral

- **Projeto:** Project PVP (Godot 4.x)

- **Gênero:** Arena PvP 2D estilo TowerFall

- **Linguagem:** GDScript

- **Cena principal:** `res://engine/scenes/MainMenu.tscn`



## Estrutura de pastas

- `scenes/` — cenas principais (menu, gameplay, player)

- `scripts/` — scripts do jogo (Player, módulos, personagens)

- `data/` — recursos `.tres` (personagens, arenas, configs)

- `assets/` — arte/áudio (sprites, animações)

- `docs/` — visão, arquitetura, roadmap e métricas

- `engine/tools/` — utilitários (ex.: importador PixelLab)


## Fluxo de gameplay (alto nível)

- `Main.gd` orquestra rounds, respawns, score e fluxo de partida.

- `Player.gd` é o controlador principal do personagem e delega para módulos de **input**, **combate** e **visuais**.



## Sistema de personagens (modular)

### CharacterData (Resource)

Arquivo: `scripts/characters/character_data.gd`

- Define stats base e overrides

- Define assets e escala de sprite

- Define skills e slots

- **Aponta para um `CharacterBaseProfile`** (mapeamento ação → animação)



Os recursos ficam em `data/characters/*.tres` e são carregados dinamicamente pelo `CharacterRegistry`.



### CharacterRegistry

Arquivo: `scripts/characters/character_registry.gd`

- Carrega automaticamente todos os `.tres` em `data/characters/`

- Expõe `get_character`, `list_character_ids`, `list_characters`



### CharacterBaseProfile (Resource)

Arquivo: `scripts/characters/character_base_profile.gd`

- Define nomes de ações (idle, walk, dash, jump, crouch, aim, shoot, melee, hurt, death)

- Configura mira 8 direções

- Configura **Bow** (node path, offset, rotação)



> O Player resolve animações com base neste perfil, então o nome da pasta/anim deve bater com os nomes definidos no profile.



## Player (módulos principais)

Arquivo: `scripts/Player.gd`

- Integra módulos:

  - `scripts/modules/player_input.gd`

  - `scripts/modules/player_combat.gd`

  - `scripts/modules/player_visuals.gd`

  - `scripts/modules/player_movement.gd`

  - `scripts/modules/player_dash.gd`

  - `scripts/modules/player_shoot.gd`

  - `scripts/modules/player_melee.gd`

  - `scripts/modules/player_hitbox.gd`

- Usa `StatsComponent` e `SkillController`

- Resolve animações via `CharacterBaseProfile`

- Mira 8 direções + arco acompanha direção



### PlayerVisuals (novo)

Arquivo: `scripts/modules/player_visuals.gd`

- Centraliza **animação, sprites, offsets, mira, crouch, bow** e efeitos visuais (dash ghost).

- Carrega animações via `asset_base_path` + `action_animation_paths` (CharacterData).

- Evita hardcode de paths no `Player.gd`.



## Sistema de skills

### SkillBase

Arquivo: `scripts/characters/skills/skill_base.gd`

- Base de skills como `Resource`

- Métodos: `update`, `can_activate`, `try_activate`, `activate`, `reset`



### SkillRuntime

Arquivo: `scripts/characters/skills/skill_runtime.gd`

- Instância runtime de uma `SkillBase`

- Guarda owner, slot e cooldown



### SkillController

Arquivo: `scripts/characters/skills/skill_controller.gd`

- Gerencia skills configuradas no `CharacterData`

- Slots customizados + slots reservados (`melee`, `ult`)



## Stats e modificadores

Arquivo: `scripts/modules/stats_component.gd`

- Base stats + modificadores

- Suporta modificadores flat e multiplicativos



## Input

Arquivo: `scripts/modules/input_map_config.gd`

- Configura ações de input (teclado/controle)

- Ações prefixadas por player (`p1_`, `p2_`, ...)



## Assets e pipeline PixelLab

Utilitário: `engine/tools/pixellab_import.py`
- Importa ZIPs do PixelLab

- Exporta para `assets/characters/<nome>/pixellab/`

- Gera `pixellab_manifest.json`



## Como adicionar um novo personagem

1. **Importar assets**

   ```bash

   python engine/tools/pixellab_import.py <zip_path> --name <nome_personagem>

   ```

2. **Criar um CharacterBaseProfile** (opcional se existir um padrão)

3. **Criar um CharacterData** em `data/characters/`:

   - `id`, `display_name`

   - `asset_base_path` (ex.: `res://visuals/assets/characters/<nome>/pixellab`)

   - `sprite_scale`

   - `base_profile`

   - `skills` e `skill_slots` se necessário

4. O `CharacterRegistry` carrega automaticamente o novo personagem.



> Para mudar personagem default, edite `CharacterSelectionState`.



## Atualizações recentes (refatoração)

- `Player.gd` foi modularizado: **PlayerInput**, **PlayerCombat**, **PlayerVisuals**.

- Animações e paths de assets agora vêm do `CharacterData` (`asset_base_path`, `sprite_scale`, `action_animation_paths`).

- Mira, crouch, bow e seleção de animação ficaram isolados no `PlayerVisuals`.



## Pendências / bugs conhecidos

- **Lee skill (E / triangle / Y) não dispara** como planejado.

  - `lee.tres` usa `GroundSlamSkill` em `ult_skill`.

  - Input atual: `p1_melee = E`, `p1_ult = R` (ver `InputMapConfig`).

  - O esperado parece ser acionar a skill no botão de melee (E/triangle/Y). Verificar se deve:

    - mover `GroundSlamSkill` para `melee_skill`, **ou**

    - trocar o binding do `ult` para E/triangle/Y.

- Textura da flecha ainda está hardcoded em `scripts/Arrow.gd`.



## Convenções e métricas

Ver `docs/metrics.md` para unidades e escalas de gameplay (px/s, px/s², etc.).



## Arquivos de referência

- `docs/architecture.md` — princípios de arquitetura

- `docs/vision.md` — visão do projeto

- `docs/roadmap.md` — roadmap de alto nível



## Observações importantes

- Evitar hardcode de personagens: use `CharacterRegistry`

- Animações dependem do **nome definido no BaseProfile**

- Mira 8-dir usa fallback quando direção não existir

- Mantenha consistência de unidades (px)

