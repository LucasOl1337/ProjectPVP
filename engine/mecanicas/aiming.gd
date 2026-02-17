extends RefCounted
class_name AimingMechanic

var hold_requires_ammo := true

var aim_hold_active := false
var aim_hold_dir := Vector2.ZERO
var shoot_was_pressed := false

func _resolve_aim_direction(input_reader: Object, aim_input: Vector2, facing: int) -> Vector2:
	if input_reader != null and input_reader.has_method("aim_direction"):
		var value: Variant = input_reader.call("aim_direction", aim_input, facing)
		if value is Vector2:
			return value
	if aim_input != Vector2.ZERO:
		return aim_input.normalized()
	return Vector2.RIGHT * float(facing)

func reset() -> void:
	aim_hold_active = false
	aim_hold_dir = Vector2.ZERO
	shoot_was_pressed = false

func update(input_reader: Object, aim_input: Vector2, facing: int, shoot_pressed: bool, has_ammo: bool) -> Dictionary:
	var shoot_just_pressed := shoot_pressed and not shoot_was_pressed
	var shoot_just_released := (not shoot_pressed) and shoot_was_pressed
	shoot_was_pressed = shoot_pressed
	if shoot_just_pressed:
		if (not hold_requires_ammo) or has_ammo:
			aim_hold_active = true
			aim_hold_dir = _resolve_aim_direction(input_reader, aim_input, facing)
	if aim_hold_active:
		var hold_dir: Vector2 = _resolve_aim_direction(input_reader, aim_input, facing)
		if hold_dir != Vector2.ZERO:
			aim_hold_dir = hold_dir
	if aim_hold_active and shoot_just_released:
		aim_hold_active = false
	return {
		"shoot_just_pressed": shoot_just_pressed,
		"shoot_just_released": shoot_just_released,
		"aim_hold_active": aim_hold_active,
		"aim_hold_dir": aim_hold_dir,
		"shoot_pressed": shoot_pressed
	}

func get_state() -> Dictionary:
	return {
		"aim_hold_active": aim_hold_active,
		"aim_hold_dir": aim_hold_dir,
		"shoot_was_pressed": shoot_was_pressed
	}

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("aim_hold_active"):
		aim_hold_active = bool(state["aim_hold_active"])
	if state.has("aim_hold_dir"):
		aim_hold_dir = state["aim_hold_dir"]
	if state.has("shoot_was_pressed"):
		shoot_was_pressed = bool(state["shoot_was_pressed"])
