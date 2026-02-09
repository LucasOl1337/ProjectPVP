extends Resource
class_name ArenaDefinition

@export var spawn_points: Array[Vector2] = [
	Vector2(-520, 360),
	Vector2(520, 360)
]
@export var wrap_bounds := Rect2(Vector2(-1200.0, -700.0), Vector2(2400.0, 1400.0))
@export var wrap_padding := Vector2(40.0, 40.0)

func has_spawn_points() -> bool:
	return not spawn_points.is_empty()

func get_spawn_points(swapped: bool = false) -> Array[Vector2]:
	if spawn_points.is_empty():
		return []
	var points := spawn_points.duplicate()
	if swapped:
		points.reverse()
	return points

func has_wrap_bounds() -> bool:
	return wrap_bounds.size != Vector2.ZERO

func get_wrap_bounds() -> Rect2:
	return wrap_bounds

func get_wrap_padding() -> Vector2:
	return wrap_padding
