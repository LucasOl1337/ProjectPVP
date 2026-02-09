extends RefCounted
class_name ArenaManager

const ArenaDefinition = preload("res://scripts/modules/arena_definition.gd")

var arena_definition: ArenaDefinition = ArenaDefinition.new()

func set_definition(definition: ArenaDefinition) -> void:
	if definition == null:
		return
	arena_definition = definition

func get_spawn_points(swapped: bool = false) -> Array:
	return arena_definition.get_spawn_points(swapped)

func apply_spawn(players, swapped: bool = false) -> void:
	var points = get_spawn_points(swapped)
	var count = min(players.size(), points.size())
	for i in range(count):
		var player = players[i]
		if player is Node2D:
			player.global_position = points[i]

func has_wrap_bounds() -> bool:
	return arena_definition.has_wrap_bounds()

func get_wrap_bounds() -> Rect2:
	return arena_definition.get_wrap_bounds()

func get_wrap_padding() -> Vector2:
	return arena_definition.get_wrap_padding()
