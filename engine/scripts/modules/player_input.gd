extends RefCounted
class_name PlayerInput

const MAX_BUFFER_FRAMES := 120

var player_id := 1
var p2_left_key := 0
var p2_right_key := 0
var p2_up_key := 0
var p2_down_key := 0
var p2_jump_key := 0
var p2_shoot_key := 0
var p1_jump_key := 0
var p1_up_key := 0
var p1_left_key := 0
var p1_right_key := 0
var p1_down_key := 0
var _frame_index := 0
var _frames: Array = []
var _current_frame: Dictionary = {}
var _has_frame := false
var use_external_frames := false

static func normalize_frame(frame: Dictionary, fallback_frame: int = 0) -> Dictionary:
	if frame.is_empty():
		return {}
	var normalized := frame.duplicate(true)
	if normalized.has("actions") and normalized["actions"] is Dictionary:
		normalized["actions"] = (normalized["actions"] as Dictionary).duplicate(true)
	if not normalized.has("frame"):
		normalized["frame"] = fallback_frame
	if not normalized.has("axis"):
		normalized["axis"] = 0.0
	if not normalized.has("aim"):
		normalized["aim"] = Vector2.ZERO
	if not normalized.has("jump_pressed"):
		normalized["jump_pressed"] = false
	if not normalized.has("shoot_pressed"):
		normalized["shoot_pressed"] = false
	if not normalized.has("shoot_is_pressed"):
		normalized["shoot_is_pressed"] = false
	if not normalized.has("dash_pressed"):
		normalized["dash_pressed"] = []
	if not normalized.has("melee_pressed"):
		normalized["melee_pressed"] = false
	if not normalized.has("ult_pressed"):
		normalized["ult_pressed"] = false
	if not normalized.has("actions") or not (normalized["actions"] is Dictionary):
		normalized["actions"] = {}
	var actions: Dictionary = normalized["actions"]
	for action_name in ["left", "right", "up", "down"]:
		if not actions.has(action_name):
			actions[action_name] = false
	normalized["actions"] = actions
	return normalized

static func build_empty_frame(frame_number: int) -> Dictionary:
	return {
		"frame": frame_number,
		"axis": 0.0,
		"aim": Vector2.ZERO,
		"jump_pressed": false,
		"shoot_pressed": false,
		"shoot_is_pressed": false,
		"dash_pressed": [],
		"melee_pressed": false,
		"ult_pressed": false,
		"actions": {
			"left": false,
			"right": false,
			"up": false,
			"down": false
		}
	}

func configure(id: int) -> void:
	player_id = id
	_set_p1_keycodes()
	_set_p2_keycodes()
	_reset_buffer()
	use_external_frames = false

func capture() -> void:
	if use_external_frames:
		return
	var frame := {
		"frame": _frame_index,
		"axis": _read_axis(),
		"aim": _read_aim_input(),
		"jump_pressed": _read_jump_pressed_raw(),
		"shoot_pressed": _read_shoot_pressed(),
		"shoot_is_pressed": _read_shoot_is_pressed(),
		"dash_pressed": _read_dash_pressed(),
		"melee_pressed": _read_melee_pressed(),
		"ult_pressed": _read_ult_pressed(),
		"actions": {
			"left": _read_action_pressed("left"),
			"right": _read_action_pressed("right"),
			"up": _read_action_pressed("up"),
			"down": _read_action_pressed("down")
		}
	}
	_current_frame = frame
	_has_frame = true
	_frames.append(frame)
	if _frames.size() > MAX_BUFFER_FRAMES:
		_frames.pop_front()
	_frame_index += 1

func build_local_frame(frame_number: int) -> Dictionary:
	return {
		"frame": frame_number,
		"axis": _read_axis(),
		"aim": _read_aim_input(),
		"jump_pressed": _read_jump_pressed_raw(),
		"shoot_pressed": _read_shoot_pressed(),
		"shoot_is_pressed": _read_shoot_is_pressed(),
		"dash_pressed": _read_dash_pressed(),
		"melee_pressed": _read_melee_pressed(),
		"ult_pressed": _read_ult_pressed(),
		"actions": {
			"left": _read_action_pressed("left"),
			"right": _read_action_pressed("right"),
			"up": _read_action_pressed("up"),
			"down": _read_action_pressed("down")
		}
	}

func get_frame(frame_offset: int = 0) -> Dictionary:
	if not _has_frame:
		return {}
	if frame_offset <= 0:
		return (_current_frame as Dictionary).duplicate(true)
	var index := _frames.size() - 1 - frame_offset
	if index < 0 or index >= _frames.size():
		return {}
	return (_frames[index] as Dictionary).duplicate(true)

func push_frame(frame: Dictionary) -> void:
	var normalized := _normalize_frame(frame)
	if normalized.is_empty():
		return
	_current_frame = normalized.duplicate(true)
	_has_frame = true
	_frames.append(_current_frame.duplicate(true))
	if _frames.size() > MAX_BUFFER_FRAMES:
		_frames.pop_front()
	var frame_number := int(_current_frame.get("frame", _frame_index))
	_frame_index = maxi(frame_number + 1, _frame_index + 1)

func _reset_buffer() -> void:
	_frames.clear()
	_current_frame = {}
	_frame_index = 0
	_has_frame = false

func _is_valid_frame(frame: Dictionary) -> bool:
	if frame.is_empty():
		return false
	return frame.has("axis") and frame.has("aim") and frame.has("actions")

func _clone_frame(frame: Dictionary) -> Dictionary:
	var cloned := frame.duplicate(true)
	if cloned.has("actions") and cloned["actions"] is Dictionary:
		cloned["actions"] = (cloned["actions"] as Dictionary).duplicate(true)
	return cloned

func _normalize_frame(frame: Dictionary) -> Dictionary:
	return normalize_frame(frame, _frame_index)

func set_use_external_frames(enabled: bool) -> void:
	use_external_frames = enabled
	if not enabled:
		_current_frame = {}
		_has_frame = false

func action(name: String) -> String:
	return "p%d_%s" % [player_id, name]

func dash_action(name: String) -> String:
	return "p%d_dash_%s" % [player_id, name]

func _has_action(name: String) -> bool:
	return InputMap.has_action(name)

func _is_action_pressed_safe(name: String) -> bool:
	if not _has_action(name):
		return false
	return Input.is_action_pressed(name)

func _is_action_just_pressed_safe(name: String) -> bool:
	if not _has_action(name):
		return false
	return Input.is_action_just_pressed(name)

func _get_axis_safe(negative: String, positive: String) -> float:
	if not _has_action(negative) or not _has_action(positive):
		return 0.0
	return Input.get_axis(negative, positive)

func is_action_pressed(name: String) -> bool:
	if _has_frame and _current_frame.has("actions"):
		var actions: Dictionary = _current_frame["actions"]
		if actions.has(name):
			return bool(actions[name])
	return _is_action_pressed_safe(action(name))

func get_axis() -> float:
	if _has_frame and _current_frame.has("axis"):
		return float(_current_frame["axis"])
	return _read_axis()

func jump_pressed(is_crouching: bool) -> bool:
	if is_crouching:
		return false
	if _has_frame and _current_frame.has("jump_pressed"):
		return bool(_current_frame["jump_pressed"])
	return _read_jump_pressed_raw()

func shoot_pressed() -> bool:
	if _has_frame and _current_frame.has("shoot_pressed"):
		return bool(_current_frame["shoot_pressed"])
	return _read_shoot_pressed()

func shoot_is_pressed() -> bool:
	if _has_frame and _current_frame.has("shoot_is_pressed"):
		return bool(_current_frame["shoot_is_pressed"])
	return _read_shoot_is_pressed()

func aim_input() -> Vector2:
	if _has_frame and _current_frame.has("aim"):
		return _current_frame["aim"]
	return _read_aim_input()

func aim_direction(aim_input_value: Vector2, facing: int) -> Vector2:
	if aim_input_value == Vector2.ZERO:
		return Vector2(facing, 0)
	return aim_input_value.normalized()

func dash_pressed() -> Array:
	if _has_frame and _current_frame.has("dash_pressed"):
		return (_current_frame["dash_pressed"] as Array).duplicate()
	return _read_dash_pressed()

func melee_pressed() -> bool:
	if _has_frame and _current_frame.has("melee_pressed"):
		return bool(_current_frame["melee_pressed"])
	return _read_melee_pressed()

func ult_pressed() -> bool:
	if _has_frame and _current_frame.has("ult_pressed"):
		return bool(_current_frame["ult_pressed"])
	return _read_ult_pressed()

func _read_axis() -> float:
	if player_id == 2:
		var axis := 0.0
		if p2_left_key != 0 and Input.is_key_pressed(p2_left_key):
			axis -= 1.0
		if p2_right_key != 0 and Input.is_key_pressed(p2_right_key):
			axis += 1.0
		if axis != 0.0:
			return axis
		return _get_axis_safe(action("left"), action("right"))
	if player_id == 1:
		var axis := 0.0
		if p1_left_key != 0 and Input.is_key_pressed(p1_left_key):
			axis -= 1.0
		if p1_right_key != 0 and Input.is_key_pressed(p1_right_key):
			axis += 1.0
		if axis != 0.0:
			return axis
	return _get_axis_safe(action("left"), action("right"))

func _read_jump_pressed_raw() -> bool:
	if player_id == 2:
		if p2_jump_key != 0 and Input.is_key_pressed(p2_jump_key):
			return true
		if p2_up_key != 0 and Input.is_key_pressed(p2_up_key):
			return false
		return _is_action_just_pressed_safe(action("jump"))
	if p1_jump_key != 0 and Input.is_key_pressed(p1_jump_key):
		return true
	if p1_up_key != 0 and Input.is_key_pressed(p1_up_key):
		return false
	return _is_action_just_pressed_safe(action("jump"))

func _read_shoot_pressed() -> bool:
	if player_id == 2:
		if p2_shoot_key != 0 and Input.is_key_pressed(p2_shoot_key):
			return true
		return _is_action_just_pressed_safe(action("shoot"))
	return _is_action_just_pressed_safe(action("shoot"))

func _read_shoot_is_pressed() -> bool:
	if player_id == 2:
		if p2_shoot_key != 0 and Input.is_key_pressed(p2_shoot_key):
			return true
		return _is_action_pressed_safe(action("shoot"))
	return _is_action_pressed_safe(action("shoot"))

func _read_aim_input() -> Vector2:
	var x := _get_axis_safe(action("left"), action("right"))
	var y := _get_axis_safe(action("up"), action("down"))
	if player_id == 2:
		var axis_x := 0.0
		if p2_left_key != 0 and Input.is_key_pressed(p2_left_key):
			axis_x -= 1.0
		if p2_right_key != 0 and Input.is_key_pressed(p2_right_key):
			axis_x += 1.0
		if axis_x != 0.0:
			x = axis_x
		var axis_y := 0.0
		if p2_up_key != 0 and Input.is_key_pressed(p2_up_key):
			axis_y -= 1.0
		if p2_down_key != 0 and Input.is_key_pressed(p2_down_key):
			axis_y += 1.0
		if axis_y != 0.0:
			y = axis_y
	if player_id == 1:
		var axis_x := 0.0
		if p1_left_key != 0 and Input.is_key_pressed(p1_left_key):
			axis_x -= 1.0
		if p1_right_key != 0 and Input.is_key_pressed(p1_right_key):
			axis_x += 1.0
		if axis_x != 0.0:
			x = axis_x
		var axis_y := 0.0
		if p1_up_key != 0 and Input.is_key_pressed(p1_up_key):
			axis_y -= 1.0
		if p1_down_key != 0 and Input.is_key_pressed(p1_down_key):
			axis_y += 1.0
		if axis_y != 0.0:
			y = axis_y
	return Vector2(x, y)

func _read_dash_pressed() -> Array:
	var pressed := []
	if _is_action_just_pressed_safe(dash_action("l1")):
		pressed.append("l1")
	if _is_action_just_pressed_safe(dash_action("l2")):
		pressed.append("l2")
	if _is_action_just_pressed_safe(dash_action("r1")):
		pressed.append("r1")
	if _is_action_just_pressed_safe(dash_action("r2")):
		pressed.append("r2")
	return pressed

func _read_melee_pressed() -> bool:
	var pressed := _is_action_just_pressed_safe(action("melee"))
	if pressed:
		_log_input("melee", "just_pressed")
	return pressed

func _read_ult_pressed() -> bool:
	var pressed := _is_action_just_pressed_safe(action("ult"))
	if pressed:
		_log_input("ult", "action:ult")
	return pressed

func _read_action_pressed(name: String) -> bool:
	return _is_action_pressed_safe(action(name))

func _set_p2_keycodes() -> void:
	if player_id != 2:
		return
	p2_left_key = OS.find_keycode_from_string("Left")
	p2_right_key = OS.find_keycode_from_string("Right")
	p2_up_key = OS.find_keycode_from_string("Up")
	p2_down_key = OS.find_keycode_from_string("Down")
	p2_jump_key = OS.find_keycode_from_string("Enter")
	p2_shoot_key = OS.find_keycode_from_string("Ctrl")

func _set_p1_keycodes() -> void:
	if player_id != 1:
		return
	p1_jump_key = OS.find_keycode_from_string("Space")
	p1_up_key = OS.find_keycode_from_string("W")
	p1_left_key = OS.find_keycode_from_string("A")
	p1_right_key = OS.find_keycode_from_string("D")
	p1_down_key = OS.find_keycode_from_string("S")

func _log_input(action_name: String, detail: String = "") -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return
	var tree: SceneTree = main_loop as SceneTree
	if tree.root == null:
		return
	var dev_debug := tree.root.get_node_or_null("DevDebug")
	if dev_debug == null or not dev_debug.has_method("log_input"):
		return
	dev_debug.log_input(player_id, action_name, detail)
