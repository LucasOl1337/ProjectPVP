extends RefCounted
class_name DashMechanic

# DashMechanic
#
# Mecânica responsável por gerar uma “velocidade de dash” por um curto período.
# O Player chama `try_trigger(...)` quando detecta inputs de dash, e a cada frame
# aplica `update_and_get_velocity(delta)` para obter a velocidade a ser somada no movimento.0.
# Unidades (importante):
# - `dash_duration`: segundos
# - `dash_distance`: pixels (distância total desejada durante `dash_duration`)
# - `dash_multiplier`: fator sobre `move_speed` (fallback quando `dash_distance == 0`)
#
# Conveniência (pra evitar confusão): se `dash_duration` vier muito alto (> 5),
# assumimos que o valor foi passado em milissegundos e convertemos para segundos.
#
# Regra de distância:
# - Se `dash_distance > 0`, a velocidade do dash vira: `dash_distance / dash_duration`.
# - Em combos (ex.: 2 dashes no mesmo trigger), a distância soma: `dash_distance * used_count`.

var dash_multiplier := 1.8
var dash_duration := 0.12
var dash_cooldown := 0.45
var dash_distance := 100
var upward_multiplier := 0.5
var combo_window := 0.05

var dash_time_left := 0.0
var dash_velocity := Vector2.ZERO
var needs_ground_reset := false
var combo_timer := 0.0
var pending_keys: Array = []
var dash_cooldowns := {
	"r1": 0.0,
	"r2": 0.0
}

func dev_apply_config_from_source(path: String = "res://engine/mecanicas/dash.gd") -> Dictionary:
	var result := {
		"ok": false,
		"path": path,
		"global_path": ProjectSettings.globalize_path(path),
		"applied": {},
		"error": ""
	}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["error"] = "Não foi possível abrir arquivo"
		return result
	var text := file.get_as_text()
	file.close()

	var rx := RegEx.new()
	var err := rx.compile("^\\s*var\\s+(dash_multiplier|dash_duration|dash_cooldown|dash_distance|upward_multiplier|combo_window)\\s*:?=\\s*([+-]?(?:\\d+\\.?\\d*|\\d*\\.?\\d+))\\s*$")
	if err != OK:
		result["error"] = "Falha ao compilar regex"
		return result

	var applied: Dictionary = {}
	for line in text.split("\n"):
		var m := rx.search(line)
		if m == null:
			continue
		var key := String(m.get_string(1))
		var value := float(m.get_string(2))
		applied[key] = value

	if applied.is_empty():
		result["error"] = "Nenhuma chave encontrada no arquivo"
		return result

	if applied.has("dash_multiplier"):
		dash_multiplier = float(applied["dash_multiplier"])
	if applied.has("dash_duration"):
		dash_duration = float(applied["dash_duration"])
	if applied.has("dash_cooldown"):
		dash_cooldown = float(applied["dash_cooldown"])
	if applied.has("dash_distance"):
		dash_distance = float(applied["dash_distance"])
	if applied.has("upward_multiplier"):
		upward_multiplier = float(applied["upward_multiplier"])
	if applied.has("combo_window"):
		combo_window = float(applied["combo_window"])
	_normalize_config()

	result["ok"] = true
	result["applied"] = applied.duplicate(true)
	return result

func configure(mult: float, duration: float, cooldown: float, distance: float = -1.0) -> void:
	# Método opcional para configurar em runtime.
	# Por padrão, o jogo usa a config global definida neste arquivo.
	dash_multiplier = mult
	dash_duration = duration
	dash_cooldown = cooldown
	if distance >= 0.0:
		dash_distance = distance
	_normalize_config()


func _normalize_config() -> void:
	# Se vier muito alto, assume milissegundos (ex.: 50 => 0.05s)
	if dash_duration > 5.0:
		dash_duration = dash_duration / 1000.0
	dash_duration = max(dash_duration, 0.01)
	dash_cooldown = max(dash_cooldown, 0.0)
	dash_multiplier = max(dash_multiplier, 0.0)
	dash_distance = max(dash_distance, 0.0)
	combo_window = max(combo_window, 0.0)

func update_cooldowns(delta: float) -> void:
	for key in dash_cooldowns.keys():
		var time_left := float(dash_cooldowns[key]) - delta
		dash_cooldowns[key] = max(time_left, 0.0)
	if combo_timer > 0.0:
		combo_timer = max(combo_timer - delta, 0.0)


func collect_combo_inputs(pressed: Array) -> Array:
	if combo_timer <= 0.0:
		if pending_keys.is_empty():
			if pressed.is_empty():
				return []
			combo_timer = combo_window
			pending_keys = pressed.duplicate()
			return []
		var output = pending_keys.duplicate()
		pending_keys.clear()
		return output
	for key in pressed:
		if not pending_keys.has(key):
			pending_keys.append(key)
	return []

func update_and_get_velocity(delta: float) -> Vector2:
	# Enquanto estiver dashing, retorna a velocidade do dash.
	# Quando acaba o tempo, retorna Vector2.ZERO.
	if dash_time_left <= 0.0:
		return Vector2.ZERO
	dash_time_left -= delta
	return dash_velocity

func update_grounded(is_on_floor: bool) -> void:
	# Evita “dash infinito”: depois de um dash, exige tocar o chão para liberar novamente.
	if is_on_floor:
		needs_ground_reset = false

func try_trigger(dash_keys: Array, dash_dir: Vector2, move_speed: float) -> bool:
	# Tenta iniciar um dash.
	# - `dash_keys`: lista de teclas/slots acionados no combo (ex.: ["l1","r1"]).
	# - `dash_dir`: direção desejada (normalizada pelo Player).
	# - `move_speed`: velocidade base do personagem (usada no fallback por multiplicador).
	if needs_ground_reset:
		return false
	if dash_time_left > 0.0:
		return false
	if dash_keys.is_empty():
		return false
	var dir := dash_dir
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	var total_boost := 0.0
	var used_count := 0
	for dash_key in dash_keys:
		if dash_key != "r1" and dash_key != "r2":
			continue
		if not dash_cooldowns.has(dash_key):
			continue
		if float(dash_cooldowns[dash_key]) > 0.0:
			continue
		total_boost += move_speed * dash_multiplier
		dash_cooldowns[dash_key] = dash_cooldown
		used_count += 1
	if used_count <= 0:
		return false
	if dash_distance > 0.0 and dash_duration > 0.0:
		total_boost = (dash_distance * float(used_count)) / dash_duration
	if dir.y < 0.0:
		total_boost *= upward_multiplier
	dash_time_left = dash_duration
	dash_velocity = dir * total_boost
	needs_ground_reset = true
	return true

func is_dashing() -> bool:
	return dash_time_left > 0.0

func get_state() -> Dictionary:
	return {
		"dash_time_left": dash_time_left,
		"dash_velocity": dash_velocity,
		"needs_ground_reset": needs_ground_reset,
		"combo_timer": combo_timer,
		"pending_keys": pending_keys.duplicate(),
		"dash_cooldowns": dash_cooldowns.duplicate(true)
	}

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("dash_time_left"):
		dash_time_left = float(state["dash_time_left"])
	if state.has("dash_velocity"):
		dash_velocity = state["dash_velocity"]
	if state.has("needs_ground_reset"):
		needs_ground_reset = bool(state["needs_ground_reset"])
	if state.has("combo_timer"):
		combo_timer = float(state["combo_timer"])
	if state.has("pending_keys") and state["pending_keys"] is Array:
		pending_keys = (state["pending_keys"] as Array).duplicate()
	if state.has("dash_cooldowns") and state["dash_cooldowns"] is Dictionary:
		var incoming: Dictionary = state["dash_cooldowns"] as Dictionary
		for k in dash_cooldowns.keys():
			if incoming.has(k):
				dash_cooldowns[k] = float(incoming[k])
	elif state.has("dash_cooldown_left"):
		var cd := float(state["dash_cooldown_left"])
		for k in dash_cooldowns.keys():
			dash_cooldowns[k] = cd
