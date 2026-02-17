extends RefCounted

var cooldown := 0.35
var duration := 0.15
var cooldown_timer := 0.0
var active_timer := 0.0

func configure(cooldown_value: float, duration_value: float) -> void:
	cooldown = cooldown_value
	duration = duration_value

func try_attack() -> bool:
	if cooldown_timer > 0.0 or active_timer > 0.0:
		return false
	cooldown_timer = cooldown
	active_timer = duration
	return true

func update(delta: float) -> bool:
	var finished := false
	if cooldown_timer > 0.0:
		cooldown_timer = max(cooldown_timer - delta, 0.0)
	if active_timer > 0.0:
		active_timer = max(active_timer - delta, 0.0)
		if active_timer == 0.0:
			finished = true
	return finished

func is_active() -> bool:
	return active_timer > 0.0

func get_state() -> Dictionary:
	return {
		"cooldown_timer": cooldown_timer,
		"active_timer": active_timer
	}

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("cooldown_timer"):
		cooldown_timer = float(state["cooldown_timer"])
	if state.has("active_timer"):
		active_timer = float(state["active_timer"])
