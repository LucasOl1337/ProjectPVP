# AnimActionMapper

Ferramenta de editor (dock) para mapear **ações** do personagem para **pastas de animação** (frames em PNG) e ajustar parâmetros por ação.

## Como usar

1. Ative em `Project > Project Settings > Plugins` o plugin **AnimActionMapper**.
2. Abra o dock **AnimActionMapper**.
3. Clique **Selecionar CharacterData** e escolha o `.tres/.res` do personagem.
4. Para cada ação, edite `path`(s) (pastas) e clique **Salvar**.

## Ajuste visual por ação

Em cada ação você pode ajustar:

- `Scale`: multiplicador de escala (ex.: `0.9` para reduzir 10%).
- `Off`: offset (X/Y) para corrigir alinhamento daquela ação.

Dica: depois de mudar valores, clique **Salvar** e depois **Aplicar** (no topo). Se o jogo estiver rodando pelo editor, ele deve atualizar sozinho em alguns instantes.

## SFX por ação

Cada ação pode ter:

- `SFX`: caminho do áudio (`.ogg/.wav/.mp3` em `res://`).
- `Dur`: duração (em segundos) antes do plugin parar o som automaticamente.
- `Spd`: velocidade de playback.

## Projétil (flecha)

No `CharacterData`, o projétil do tiro usa:

- `projectile_texture`: textura da flecha.
- `projectile_forward`: distância para frente no spawn.
- `projectile_vertical_offset`: offset vertical no spawn.

No dock isso aparece na seção **Projétil (Flecha)**.

## Import MCP (PixelLab)

No dock existe a seção **Import MCP (PixelLab)**:

- `char_id`: id interno do personagem no projeto (ex.: `storm_dragon`).
- `uuid PixelLab` (opcional): se você já tem o UUID do personagem no PixelLab.

Botão **Importar + Organizar**:

- baixa/importa via scripts do projeto;
- copia para `res://visuals/assets/characters/<char_id>/pixellab/`;
- tenta organizar sugestões em `animations/<ação>/...` (walk/running/dash/aim/shoot...);
- cria/atualiza `res://engine/data/characters/<char_id>.tres` e preenche `action_animation_paths`.

### Formato recomendado (sem direção)

- Crie **uma pasta por ação** contendo uma sequência de PNGs:
  - `.../animations/walk/` (com `frame_000.png`, `frame_001.png`, ...)
  - `.../animations/shoot/` etc.
- Convenção: frames desenhados **virados para a direita**. O jogo espelha automaticamente quando o personagem está virado para a esquerda.

### Direções (custom)

Algumas ações podem manter direções customizadas (ex.: `up/down/right/left` ou até diagonais).

- No dock, troque o modo da ação para **Direções (custom)**.
- Defina um path por direção (cada um aponta para uma pasta com sequência de PNGs).
- Você pode misturar: usar `shared` para fallback e sobrescrever só algumas direções.

## GIF

Godot normalmente não usa GIF animado como `SpriteFrames` diretamente.

Opções:
- Preferido: exportar/converter GIF para **sequência de PNGs** na pasta da ação.
- Se você tiver o **ImageMagick** instalado (`magick`), use o botão **Importar GIF** no dock para extrair frames automaticamente.

No modo **Direções (custom)**, o botão **GIF** da direção importa o GIF direto para a pasta daquela direção.

