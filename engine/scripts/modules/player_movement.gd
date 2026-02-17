extends RefCounted
class_name PlayerMovement

var move_speed := 240.0
var acceleration := 1600.0
var friction := 2000.0
var gravity := 1200.0
var jump_velocity := 360.0
var wall_jump_horizontal_force := 450.0
var wall_jump_vertical_force := 420.0
var wall_slide_speed := 60.0
var wall_gravity_scale := 0.2

func configure(speed: float, accel: float, fric: float, grav: float, jump: float) -> void:
	move_speed = speed
	acceleration = accel
	friction = fric
	gravity = grav
	jump_velocity = jump

func update(player: CharacterBody2D, input_axis: float, jump_pressed: bool, delta: float) -> void:
	var is_on_wall := player.is_on_wall()
	var wall_normal := player.get_wall_normal()
	var gravity_setting: Variant = ProjectSettings.get_setting("gameplay/global_gravity_scale")
	var gravity_scale := 1.0
	if gravity_setting is float or gravity_setting is int:
		gravity_scale = float(gravity_setting)
	
	# Handle wall jump
	if jump_pressed and is_on_wall and not player.is_on_floor():
		player.velocity.y = -wall_jump_vertical_force
		player.velocity.x = wall_normal.x * wall_jump_horizontal_force
	elif jump_pressed and player.is_on_floor():
		player.velocity.y = -jump_velocity
	
	# Handle gravity and wall slide
	if not player.is_on_floor():
		if is_on_wall and input_axis != 0.0 and sign(input_axis) == sign(wall_normal.x):
			# Wall slide when holding into wall
			if player.velocity.y > 0:  # Only slide when falling
				player.velocity.y = min(player.velocity.y, wall_slide_speed)
			player.velocity.y += gravity * wall_gravity_scale * gravity_scale * delta
		else:
			# Normal gravity
			player.velocity.y += gravity * gravity_scale * delta
	
	# Handle horizontal movement
	if input_axis != 0.0:
		var target_speed := input_axis * move_speed
		player.velocity.x = move_toward(player.velocity.x, target_speed, acceleration * delta)
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, friction * delta)
