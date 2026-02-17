extends RefCounted
class_name PlayerShoot

var shoot_cooldown := 0.35
var shoot_timer := 0.0

func configure(cooldown: float) -> void:
	shoot_cooldown = cooldown

func update(delta: float) -> void:
	if shoot_timer > 0.0:
		shoot_timer -= delta

func try_shoot(player: Node, arrow_scene: PackedScene, aim_dir: Vector2, override_texture: Texture2D = null) -> bool:
	if shoot_timer > 0.0 or arrow_scene == null:
		return false
	var direction := aim_dir
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	var arrow := arrow_scene.instantiate()
	var spawn_offset := Vector2.ZERO
	if player.has_method("get_projectile_spawn_offset"):
		spawn_offset = player.get_projectile_spawn_offset(direction)
	arrow.global_position = player.global_position + spawn_offset
	if arrow.has_method("set_texture_override") and override_texture != null:
		arrow.set_texture_override(override_texture)
	if arrow.has_method("setup"):
		arrow.setup(player, direction)
	player.get_tree().current_scene.add_child(arrow)
	shoot_timer = shoot_cooldown
	return true

func get_state() -> Dictionary:
	return {
		"shoot_timer": shoot_timer
	}

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("shoot_timer"):
		shoot_timer = float(state["shoot_timer"])
