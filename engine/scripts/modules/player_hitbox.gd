extends RefCounted
class_name PlayerHitbox

var spawn_position := Vector2.ZERO

func setup(player: Node2D) -> void:
	spawn_position = player.global_position

func respawn(player: CharacterBody2D) -> void:
	player.global_position = spawn_position
	player.velocity = Vector2.ZERO
