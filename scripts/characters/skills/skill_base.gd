extends Resource
class_name SkillBase

@export var cooldown := 0.0
var cooldown_timer := 0.0

func update(_player: Node, delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer = max(cooldown_timer - delta, 0.0)

func reset() -> void:
	cooldown_timer = 0.0

func can_activate(_player: Node) -> bool:
	return cooldown_timer <= 0.0

func try_activate(player: Node) -> bool:
	if not can_activate(player):
		return false
	cooldown_timer = cooldown
	return true

func activate(_player: Node) -> void:
	return

func get_state() -> Dictionary:
	return {
		"cooldown_timer": cooldown_timer
	}

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("cooldown_timer"):
		cooldown_timer = float(state["cooldown_timer"])
