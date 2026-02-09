extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")

var port := 9009
var watch_mode := false
var time_scale := 6.0
var quit_idle_seconds := 10.0

var _last_connected_time := 0.0
var _started_time := 0.0

func _initialize() -> void:
	_parse_cli_args()
	_started_time = Time.get_unix_time_from_system()
	_last_connected_time = _started_time

	if CharacterSelectionState:
		CharacterSelectionState.set_training_enabled(true)
		CharacterSelectionState.set_training_port(port)
		CharacterSelectionState.set_training_watch_mode(watch_mode)
		CharacterSelectionState.set_training_time_scale(time_scale)
		CharacterSelectionState.set_bot_enabled(1, true)
		CharacterSelectionState.set_bot_enabled(2, true)
		CharacterSelectionState.set_bot_policy(1, "external")
		CharacterSelectionState.set_bot_policy(2, "external")
		CharacterSelectionState.set_dev_mode_enabled(false)
		CharacterSelectionState.set_debug_hitboxes_enabled(false)

	var scene: Node = MAIN_SCENE.instantiate()
	get_root().add_child(scene)
	process_frame()

	while true:
		process_frame()
		var now := Time.get_unix_time_from_system()
		var connected := false
		if scene != null and scene.has_variable("training_manager") and scene.training_manager != null:
			var metrics: Dictionary = scene.training_manager.get_metrics()
			connected = bool(metrics.get("connected", false))
		if connected:
			_last_connected_time = now
			continue
		if quit_idle_seconds > 0.0 and (now - _last_connected_time) >= quit_idle_seconds and (now - _started_time) >= 1.0:
			break

	quit()

func _parse_cli_args() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--port="):
			port = max(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--time-scale="):
			time_scale = max(0.1, float(arg.get_slice("=", 1)))
		elif arg == "--watch":
			watch_mode = true
		elif arg == "--no-watch":
			watch_mode = false
		elif arg.begins_with("--quit-idle="):
			quit_idle_seconds = max(0.0, float(arg.get_slice("=", 1)))
