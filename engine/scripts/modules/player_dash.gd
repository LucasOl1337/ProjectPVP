extends RefCounted
class_name PlayerDash

# PlayerDash
#
# Versão “de módulo” do dash (mantida por compatibilidade).
# O Player atualmente usa `engine/mecanicas/dash.gd` (DashMechanic).
#
# Unidades:
# - `dash_duration`: segundos
# - `dash_distance`: pixels (distância total desejada durante `dash_duration`)
# - `dash_multiplier`: fator sobre `move_speed` (fallback quando `dash_distance == 0`)

var dash_multiplier := 4.0
var dash_duration := 0.2
var dash_cooldown := 0.45
var dash_distance := 0.0
var upward_multiplier := 0.5
var combo_window := 0.05

var dash_time_left := 0.0
var dash_velocity := Vector2.ZERO
var needs_ground_reset := false
var combo_timer := 0.0
var pending_keys = []
var dash_cooldowns := {
	"l1": 0.0,
	"l2": 0.0,
	"r1": 0.0,
	"r2": 0.0
}

func configure(mult: float, duration: float, cooldown: float, distance: float = 0.0) -> void:
	dash_multiplier = mult
	var d := float(duration)
	if d > 5.0:
		d = d / 1000.0
	dash_duration = d
	dash_cooldown = cooldown
	dash_distance = max(distance, 0.0)

func update_cooldowns(delta: float) -> void:
	for key in dash_cooldowns.keys():
		var time_left := float(dash_cooldowns[key]) - delta
		dash_cooldowns[key] = max(time_left, 0.0)
	if combo_timer > 0.0:
		combo_timer = max(combo_timer - delta, 0.0)

func update_and_get_velocity(delta: float) -> Vector2:
	if dash_time_left <= 0.0:
		return Vector2.ZERO
	dash_time_left -= delta
	return dash_velocity

func update_grounded(is_on_floor: bool) -> void:
	if is_on_floor:
		needs_ground_reset = false

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

func try_trigger(dash_keys: Array, dash_dir: Vector2, move_speed: float) -> bool:
	# Mesma regra do DashMechanic:
	# - Se `dash_distance > 0`, calcula a velocidade como distância/duração.
	# - Em combos, soma distância proporcional ao número de teclas usadas.
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
		if not dash_cooldowns.has(dash_key):
			continue
		if dash_cooldowns[dash_key] > 0.0:
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
		dash_cooldowns = (state["dash_cooldowns"] as Dictionary).duplicate(true)
