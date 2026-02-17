extends RefCounted
class_name JumpMechanic

var gravity := 1200.0
var jump_velocity := 360.0

var wall_jump_horizontal_force := 450.0
var wall_jump_vertical_force := 420.0
var wall_slide_speed := 60.0
var wall_gravity_scale := 0.2

func configure(grav: float, jump: float) -> void:
	gravity = grav
	jump_velocity = jump

func update(player: CharacterBody2D, input_axis: float, jump_pressed: bool, delta: float) -> void:
	var is_on_wall := player.is_on_wall()
	var wall_normal := player.get_wall_normal()
	var gravity_setting: Variant = ProjectSettings.get_setting("gameplay/global_gravity_scale")
	var gravity_scale := 1.0
	if gravity_setting is float or gravity_setting is int:
		gravity_scale = float(gravity_setting)

	if jump_pressed and is_on_wall and not player.is_on_floor():
		player.velocity.y = -wall_jump_vertical_force
		player.velocity.x = wall_normal.x * wall_jump_horizontal_force
	elif jump_pressed and player.is_on_floor():
		player.velocity.y = -jump_velocity

	if player.is_on_floor():
		return

	if is_on_wall and input_axis != 0.0 and sign(input_axis) == sign(wall_normal.x):
		if player.velocity.y > 0.0:
			player.velocity.y = min(player.velocity.y, wall_slide_speed)
		player.velocity.y += gravity * wall_gravity_scale * gravity_scale * delta
		return

	player.velocity.y += gravity * gravity_scale * delta

