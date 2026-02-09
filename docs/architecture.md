# Arquitetura Inicial

## Princípios
- **Simulação determinística** por input
- **Fixed timestep** (60 FPS)
- Separar **input**, **simulação**, **render**

## Camadas
1. **Input**: captura local e buffer de comandos
2. **Simulação**: estado autoritativo (players, projéteis)
3. **Render**: sprites e efeitos

## Arena
- Definição via `ArenaDefinition` (`data/arenas/*.tres`)
- Configura spawn points, limites de wrap e padding
- `Main.gd` injeta o recurso no `ArenaManager`, evitando valores hardcoded

## Hitbox
- Uso de shapes simples (capsule/retângulo)
- Colisões explicitamente controladas
- Visualização de debug para ajuste fino

## Personagens
- `CharacterData` permite overrides opcionais de stats (movimento, dash, projétil)
- `Player.gd` aplica os overrides antes de configurar módulos
