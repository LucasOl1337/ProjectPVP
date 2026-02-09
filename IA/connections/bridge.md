# Training Bridge (TCP/JSON)

Conexão entre o jogo e o agente externo de treinamento.

## Mensagens enviadas pelo jogo

- `{"type":"hello","protocol":1}`
- `{"type":"step","frame":int,"obs":{...},"reward":{...},"done":bool}`

## Mensagens enviadas pelo agente

- `{"type":"config","watch_mode":bool,"time_scale":float}`
- `{"type":"action","actions":{ "1":{...}, "2":{...} }}`
- `{"type":"reset"}`

## Observações
- Todas as mensagens são JSON por linha (newline-delimited).
- O jogo sempre espera `action` após cada `step`.
- `obs.delta` é o `delta` do `_physics_process` (afetado por `Engine.time_scale`).
- Por padrão, o jogo não envia `obs.raw` no payload do bridge (reduz overhead). Use `--debug-bridge` para incluir campos de debug.

## Testes rápidos

### 1) Smoke test do bridge

1. Suba o jogo em modo treino (headless):

```powershell
$godot="C:/.../Godot_v4.5.1-stable_win64_console.exe"
& $godot --headless --path "$PWD" --scene res://scenes/Main.tscn -- --training --port=20001 --no-watch --time-scale=8.0
```

2. Em outro terminal, rode:

```powershell
python tools\bridge_smoke_test.py --host 127.0.0.1 --port 20001 --duration 8 --reply-actions
```

Para validar que `obs.delta` acompanha `--time-scale`:

```powershell
python tools\bridge_smoke_test.py --host 127.0.0.1 --port 20001 --duration 8 --reply-actions --time-scale 8 --assert-delta
```

Se estiver ok, você vê linhas com `type` e no final `OK: recebeu 'step' do jogo`.

### 2) Teste com o trainer (GA)

```powershell
python tools\training_genetic_ga.py --host 127.0.0.1 --port 20001 --no-watch --time-scale 8.0 --population 4 --elite 1 --episodes-per-genome 1 --generations 3 --opponent best
```

Para habilitar mira aprendível:

```powershell
python tools\training_genetic_ga.py --host 127.0.0.1 --port 20001 --no-watch --time-scale 8.0 --learn-aim --aim-bins 9
```

## Teste no editor (Godot)

1. Abra o projeto e rode a cena `Main.tscn`.
2. Ative `Dev Mode`/HUD (se estiver disponível no menu) e habilite `Training`.
3. Rode o trainer em paralelo apontando para a porta configurada no HUD.

## Nota (auto-start do trainer)

Em headless com `--training`, o jogo não inicia automaticamente um processo Python por padrão (evita dois trainers competindo pela mesma porta).
Se quiser forçar auto-start, use `--auto-trainer`.

## Gravação (treino com humano)

Para gravar um dataset JSONL (1 linha por step):

```powershell
& $godot --headless --path "$PWD" --scene res://scenes/Main.tscn -- --training --port=20001 --record-path=user://datasets/sessao_01.jsonl
```

`user://` aponta para a pasta de dados do Godot (no editor dá pra abrir via "Project > Open User Data Folder").
