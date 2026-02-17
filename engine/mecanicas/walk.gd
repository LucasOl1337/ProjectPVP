extends RefCounted
class_name WalkMechanic

var move_speed := 240.0
var acceleration := 1600.0
var friction := 2000.0

func configure(speed: float, accel: float, fric: float) -> void:
	move_speed = speed
	acceleration = accel
	friction = fric

func update(player: CharacterBody2D, input_axis: float, delta: float) -> void:
	if input_axis != 0.0:
		var target_speed := input_axis * move_speed
		player.velocity.x = move_toward(player.velocity.x, target_speed, acceleration * delta)
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, friction * delta)

