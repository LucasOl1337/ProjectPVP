extends RefCounted
class_name BotActionFrame

const PlayerInput = preload("res://scripts/modules/player_input.gd")

static func build(frame_number: int, action: Dictionary) -> Dictionary:
	var actions := _normalize_actions(action.get("actions"))
	var axis := 0.0
	if action.has("axis"):
		axis = float(action["axis"])
	else:
		axis = float(actions.get("right", false)) - float(actions.get("left", false))
	var aim_value: Variant = action.get("aim", Vector2.ZERO)
	var aim: Vector2 = _normalize_aim(aim_value)
	var shoot_pressed := bool(action.get("shoot_pressed", false))
	var shoot_is_pressed := bool(action.get("shoot_is_pressed", shoot_pressed))
	var frame := {
		"frame": frame_number,
		"axis": axis,
		"aim": aim,
		"jump_pressed": bool(action.get("jump_pressed", false)),
		"shoot_pressed": shoot_pressed,
		"shoot_is_pressed": shoot_is_pressed,
		"dash_pressed": _normalize_dash(action.get("dash_pressed")),
		"melee_pressed": bool(action.get("melee_pressed", false)),
		"ult_pressed": bool(action.get("ult_pressed", false)),
		"actions": actions
	}
	return PlayerInput.normalize_frame(frame, frame_number)

static func _normalize_actions(value: Variant) -> Dictionary:
	var actions: Dictionary = {}
	if value is Dictionary:
		actions = (value as Dictionary).duplicate(true)
	var output: Dictionary = actions.duplicate(true)
	for name in ["left", "right", "up", "down"]:
		if not output.has(name):
			output[name] = false
		else:
			output[name] = bool(output[name])
	return output

static func _normalize_dash(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate()
	return []

static func _normalize_aim(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array:
		var array_value := value as Array
		if array_value.size() >= 2:
			return Vector2(float(array_value[0]), float(array_value[1]))
	if value is Dictionary:
		var dict_value := value as Dictionary
		if dict_value.has("x") and dict_value.has("y"):
			return Vector2(float(dict_value["x"]), float(dict_value["y"]))
	return Vector2.ZERO
