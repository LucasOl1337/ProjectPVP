extends RefCounted
class_name InputMapConfig

func apply() -> void:
	_reset_action("p1_left")
	_reset_action("p1_right")
	_reset_action("p1_up")
	_reset_action("p1_down")
	_reset_action("p1_jump")
	_reset_action("p1_shoot")
	_reset_action("p1_melee")
	_reset_action("p1_ult")
	_reset_action("p1_triangle")
	_reset_action("p2_left")
	_reset_action("p2_right")
	_reset_action("p2_up")
	_reset_action("p2_down")
	_reset_action("p2_jump")
	_reset_action("p2_shoot")
	_reset_action("p2_melee")
	_reset_action("p2_ult")
	_reset_action("p2_triangle")
	_reset_action("p1_dash_l1")
	_reset_action("p1_dash_l2")
	_reset_action("p1_dash_r1")
	_reset_action("p1_dash_r2")
	_reset_action("p2_dash_l1")
	_reset_action("p2_dash_l2")
	_reset_action("p2_dash_r1")
	_reset_action("p2_dash_r2")

	_add_key_action("p1_left", "A")
	_add_key_action("p1_right", "D")
	_add_key_action("p1_up", "W")
	_add_key_action("p1_down", "S")
	_add_key_action("p1_jump", "Space")
	_add_key_action("p1_shoot", "Q")
	_add_key_action("p1_melee", "E")
	_add_key_action("p1_ult", "R")
	_add_key_action("p1_triangle", "E")

	_add_key_action("p2_left", "Left")
	_add_key_action("p2_right", "Right")
	_add_key_action("p2_up", "Up")
	_add_key_action("p2_down", "Down")
	_add_key_action("p2_jump", "Enter")
	_add_key_action("p2_shoot", "Ctrl")
	_add_key_action("p2_melee", "Shift")
	_add_key_action("p2_ult", "Enter")
	_add_key_action("p2_triangle", "Shift")

	_add_joypad_axis("p1_left", 0, -1.0, 0)
	_add_joypad_axis("p1_right", 0, 1.0, 0)
	_add_joypad_axis("p1_up", 1, -1.0, 0)
	_add_joypad_axis("p1_down", 1, 1.0, 0)
	_add_joypad_button("p1_left", 13, 0)
	_add_joypad_button("p1_right", 14, 0)
	_add_joypad_button("p1_up", 11, 0)
	_add_joypad_button("p1_down", 12, 0)
	_add_joypad_button("p1_jump", 0, 0)
	_add_joypad_button("p1_shoot", 2, 0)
	_add_joypad_button("p1_melee", 3, 0)
	_add_joypad_button("p1_ult", 1, 0)
	_add_joypad_button("p1_triangle", 3, 0)
	_add_joypad_button("p1_jump", 11, 0)
	_add_joypad_button("p1_dash_l1", 9, 0)
	_add_joypad_button("p1_dash_r1", 10, 0)
	_add_joypad_axis("p1_dash_l2", 4, 1.0, 0)
	_add_joypad_axis("p1_dash_r2", 5, 1.0, 0)

	_add_joypad_axis("p2_left", 0, -1.0, 1)
	_add_joypad_axis("p2_right", 0, 1.0, 1)
	_add_joypad_axis("p2_up", 1, -1.0, 1)
	_add_joypad_axis("p2_down", 1, 1.0, 1)
	_add_joypad_button("p2_left", 13, 1)
	_add_joypad_button("p2_right", 14, 1)
	_add_joypad_button("p2_up", 11, 1)
	_add_joypad_button("p2_down", 12, 1)
	_add_joypad_button("p2_jump", 0, 1)
	_add_joypad_button("p2_shoot", 2, 1)
	_add_joypad_button("p2_melee", 3, 1)
	_add_joypad_button("p2_ult", 1, 1)
	_add_joypad_button("p2_triangle", 3, 1)
	_add_joypad_button("p2_jump", 11, 1)
	_add_joypad_button("p2_dash_l1", 9, 1)
	_add_joypad_button("p2_dash_r1", 10, 1)
	_add_joypad_axis("p2_dash_l2", 4, 1.0, 1)
	_add_joypad_axis("p2_dash_r2", 5, 1.0, 1)

func _reset_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)

func _add_key_action(action: String, key_name: String) -> void:
	var keycode := OS.find_keycode_from_string(key_name)
	if keycode == 0:
		return
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _add_joypad_button(action: String, button_index: int, device: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button_index
	ev.device = device
	InputMap.action_add_event(action, ev)

func _add_joypad_axis(action: String, axis: int, axis_value: float, device: int) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = axis_value
	ev.device = device
	InputMap.action_add_event(action, ev)
