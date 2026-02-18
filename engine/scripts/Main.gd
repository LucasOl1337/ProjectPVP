extends Node2D



const InputMapConfig = preload("res://engine/scripts/modules/input_map_config.gd")

const ArenaManager = preload("res://engine/scripts/modules/arena_manager.gd")

const ArenaDefinition = preload("res://engine/scripts/modules/arena_definition.gd")

const CollisionLayersScript = preload("res://engine/scripts/modules/collision_layers.gd")
const NetMatchDriver = preload("res://engine/scripts/modules/net_match_driver.gd")

const BotDriver = preload("res://engine/scripts/modules/bot_driver.gd")

const TrainingManagerScript = preload("res://engine/scripts/modules/training_manager.gd")

const SuddenDeathController = preload("res://engine/scripts/modules/sudden_death_controller.gd")

const MAX_WINS := 5

const MAX_STATE_FRAMES := 240

const IA_CONFIG_DIR := "res://BOTS/IA/config"
const IA_ROUNDS_PATH := IA_CONFIG_DIR + "/rounds.json"

const IA_GA_PATH := IA_CONFIG_DIR + "/ga.json"

const IA_TRAINER_PATH := IA_CONFIG_DIR + "/trainer.json"



const BOTS_DIR := "res://BOTS/profiles"
const DEFAULT_PROFILE := "default"

const DEFAULT_REWARDS_PATH := BOTS_DIR + "/" + DEFAULT_PROFILE + "/rewards.json"

const DEFAULT_BOT_P1_PATH := BOTS_DIR + "/" + DEFAULT_PROFILE + "/bot_p1.json"

const DEFAULT_BOT_P2_PATH := BOTS_DIR + "/" + DEFAULT_PROFILE + "/bot_p2.json"

const DEFAULT_GENOME := BOTS_DIR + "/" + DEFAULT_PROFILE + "/best_genome.json"

const DEFAULT_CURRENT_BOT := BOTS_DIR + "/" + DEFAULT_PROFILE + "/current_bot.json"



@onready var player_one := $Player1

@onready var player_two := $Player2

@onready var score_label := get_node_or_null("HUD/ScoreLabel")

@onready var winner_label := get_node_or_null("HUD/WinnerLabel")

@onready var dev_hud := get_node_or_null("DevHUD")



@export var debug_hitboxes := true

@export var wrap_enabled := true

@export var wrap_padding := Vector2(40.0, 40.0)

@export var arena_definition: ArenaDefinition

@export var net_driver_enabled := true

@export var bot_player_one_enabled := false

@export var bot_player_two_enabled := false

@export var bot_player_one_policy := "simple"

@export var bot_player_two_policy := "simple"

@export var bot_disable_net_driver := true

@export var training_enabled := false

@export var training_port := 9009

@export var training_watch_mode := false

@export var training_time_scale := 1.0

@export var sudden_death_enabled := true

@export var sudden_death_start_seconds := 20.0

@export var sudden_death_phase_interval_seconds := 5.0

@export var sudden_death_phase1_close_percent := 0.20

@export var sudden_death_phase2_close_percent := 0.25

@export var sudden_death_draw_walls := true



var genetic_genome_path_p1 := DEFAULT_GENOME

var genetic_genome_path_p2 := DEFAULT_GENOME



var input_config := InputMapConfig.new()

var arena_manager := ArenaManager.new()

var round_index := 0

var wins := {1: 0, 2: 0}

var match_over := false

var round_active := false

var dev_mode_enabled := false

var wrap_bounds := Rect2(Vector2(-1200.0, -700.0), Vector2(2400.0, 1400.0))

var record_states := false

var state_frame_index := 0

var state_history: Array = []

var net_driver := NetMatchDriver.new()

var local_player_ids: Array = [1, 2]

var bot_driver_one := BotDriver.new()

var bot_driver_two := BotDriver.new()

var training_manager: TrainingManager = TrainingManager.new()

var training_prev_config := {}

var training_match_reset := false

var training_match_mode := false

var trainer_config := {}

var trainer_process_id := 0

var trainer_running := false

var trainer_status_text := "Trainer: parado"

var trainer_manual_stop := false



var training_record_path := ""



var bot_profile_p1 := DEFAULT_PROFILE

var bot_profile_p2 := DEFAULT_PROFILE



var headless_quit_idle_seconds := 0.0

var headless_started_at := 0.0

var headless_last_connected_at := 0.0

var headless_ever_connected := false



var headless_round_max_steps := -1

var headless_round_max_seconds := -1.0

var headless_round_max_kills := -1



var headless_rewards_path := ""

var headless_bot_config_p1_path := ""

var headless_bot_config_p2_path := ""

var headless_super_reward_path := ""



var auto_apply_best_genome := true

var best_genome_poll_accum := 0.0

var best_genome_last_signature := ""



var current_bot_poll_accum := 0.0

var current_bot_last_signature_p1 := ""

var current_bot_last_signature_p2 := ""

var current_bot_meta_p1: Dictionary = {}

var current_bot_meta_p2: Dictionary = {}



var observation_poll_accum := 0.0



var obs_action_ema := {

	"p1": {"shoot": 0.0, "melee": 0.0, "jump": 0.0, "dash": 0.0},

	"p2": {"shoot": 0.0, "melee": 0.0, "jump": 0.0, "dash": 0.0},

}

var obs_action_ema_alpha := 0.15

var sudden_death := SuddenDeathController.new()

var sudden_death_crush_draw_resolving := false



func _is_headless_runtime() -> bool:

	if DisplayServer.get_name() == "headless" or OS.has_feature("headless"):

		return true

	if OS.has_method("get_cmdline_user_args") and OS.get_cmdline_user_args().has("--training"):

		return true

	return false



func _ready() -> void:

	_apply_headless_user_args()

	if not _is_headless_runtime():

		Engine.max_fps = 60

		Engine.physics_ticks_per_second = 60

		if DisplayServer.has_method("window_set_vsync_mode"):

			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

	else:

		Engine.physics_ticks_per_second = 60

	if not training_enabled and not bot_player_one_enabled and not bot_player_two_enabled:
		net_driver_enabled = false
	input_config.apply()

	trainer_config = _load_trainer_config()

	if CharacterSelectionState:

		debug_hitboxes = CharacterSelectionState.get_debug_hitboxes_enabled()

		dev_mode_enabled = CharacterSelectionState.is_dev_mode_enabled()

		bot_player_one_enabled = CharacterSelectionState.is_bot_enabled(1)

		bot_player_two_enabled = CharacterSelectionState.is_bot_enabled(2)

		bot_player_one_policy = CharacterSelectionState.get_bot_policy(1)

		bot_player_two_policy = CharacterSelectionState.get_bot_policy(2)

		bot_profile_p1 = CharacterSelectionState.get_bot_profile(1)

		bot_profile_p2 = CharacterSelectionState.get_bot_profile(2)

		training_enabled = CharacterSelectionState.is_training_enabled()

		training_watch_mode = CharacterSelectionState.is_training_watch_mode()

		training_port = CharacterSelectionState.get_training_port()

		genetic_genome_path_p1 = CharacterSelectionState.get_genetic_genome_path(1)

		genetic_genome_path_p2 = CharacterSelectionState.get_genetic_genome_path(2)

		if OS.has_method("get_cmdline_user_args") and OS.get_cmdline_user_args().has("--training"):

			print("[HeadlessState] training=%s port=%d watch=%s time_scale=%s" % [str(training_enabled), int(training_port), str(training_watch_mode), str(CharacterSelectionState.get_training_time_scale())])

	training_time_scale = CharacterSelectionState.get_training_time_scale() if CharacterSelectionState else 1.0

	if training_enabled:

		dev_mode_enabled = true

		bot_player_one_enabled = true

		bot_player_two_enabled = true

		if _is_headless_runtime():

			bot_player_one_policy = "external"

			bot_player_two_policy = "external"

		else:

			if bot_player_one_policy == "external" or bot_player_one_policy == "":

				bot_player_one_policy = "objective"

			if bot_player_two_policy == "external" or bot_player_two_policy == "":

				bot_player_two_policy = "objective"

		training_match_reset = true

	_apply_debug_hitboxes()

	_configure_dev_mode(dev_mode_enabled)

	_sync_trainer_ui()

	sudden_death.configure(

		sudden_death_enabled,

		sudden_death_start_seconds,

		sudden_death_phase_interval_seconds,

		sudden_death_phase1_close_percent,

		sudden_death_phase2_close_percent,

		sudden_death_draw_walls

	)

	_configure_arena_definition()

	_configure_net_driver()

	_configure_bot_drivers()

	_configure_training()

	player_one.connect("died", Callable(self, "_on_player_died"))

	player_two.connect("died", Callable(self, "_on_player_died"))

	_update_score_ui()

	if winner_label:

		winner_label.visible = false

	_normalize_segment_colliders()

	_configure_wrap_bounds()

	_configure_collision_masks()

	_start_round()

	if headless_quit_idle_seconds > 0.0:

		headless_started_at = float(Time.get_ticks_msec()) / 1000.0

		headless_last_connected_at = headless_started_at

		set_process(true)



func _process(delta: float) -> void:

	if headless_quit_idle_seconds <= 0.0:

		return

	var now := float(Time.get_ticks_msec()) / 1000.0

	if headless_started_at <= 0.0:

		headless_started_at = now

		headless_last_connected_at = now

		return

	if now - headless_started_at < 1.0:

		return

	var connected := false

	if training_manager:

		var metrics: Dictionary = training_manager.get_metrics()

		connected = bool(metrics.get("connected", false))

	if connected:

		headless_ever_connected = true

		headless_last_connected_at = now

		return

	if headless_ever_connected:

		get_tree().quit()

		return

	if now - headless_last_connected_at >= headless_quit_idle_seconds:

		get_tree().quit()



func _apply_headless_user_args() -> void:

	var args: Array = []

	if OS.has_method("get_cmdline_user_args"):

		args = OS.get_cmdline_user_args()

	if not args.is_empty():

		print("[HeadlessArgs] %s" % var_to_str(args))

	var overrides := {

		"training": false,

		"auto_trainer": false,

		"match_mode": false,

		"record_path": null,

		"max_steps": null,

		"max_seconds": null,

		"max_kills": null,

		"port": null,

		"time_scale": null,

		"watch": null,

		"quit_idle": null

		,

		"rewards_path": null,

		"super_reward_path": null,

		"bot_config_p1": null,

		"bot_config_p2": null

	}

	for raw in args:

		var arg := String(raw)

		if arg == "--training":

			overrides["training"] = true

		elif arg == "--auto-trainer":

			overrides["auto_trainer"] = true

		elif arg == "--match-mode" or arg == "--training-match-mode":

			overrides["match_mode"] = true

		elif arg.begins_with("--port="):

			overrides["port"] = int(arg.get_slice("=", 1))

		elif arg.begins_with("--time-scale="):

			overrides["time_scale"] = float(arg.get_slice("=", 1))

		elif arg == "--watch":

			overrides["watch"] = true

		elif arg == "--no-watch":

			overrides["watch"] = false

		elif arg.begins_with("--quit-idle="):

			overrides["quit_idle"] = float(arg.get_slice("=", 1))

		elif arg.begins_with("--record-path="):

			overrides["record_path"] = arg.get_slice("=", 1)

		elif arg.begins_with("--max-steps="):

			overrides["max_steps"] = int(arg.get_slice("=", 1))

		elif arg.begins_with("--max-seconds="):

			overrides["max_seconds"] = float(arg.get_slice("=", 1))

		elif arg.begins_with("--max-kills="):

			overrides["max_kills"] = int(arg.get_slice("=", 1))

		elif arg.begins_with("--rewards-path="):

			overrides["rewards_path"] = arg.get_slice("=", 1)

		elif arg.begins_with("--super-reward-path="):

			overrides["super_reward_path"] = arg.get_slice("=", 1)

		elif arg.begins_with("--bot-config-p1="):

			overrides["bot_config_p1"] = arg.get_slice("=", 1)

		elif arg.begins_with("--bot-config-p2="):

			overrides["bot_config_p2"] = arg.get_slice("=", 1)



	if CharacterSelectionState:

		if bool(overrides["training"]):

			CharacterSelectionState.set_training_enabled(true)

			if not bool(overrides["auto_trainer"]):

				trainer_manual_stop = true

		if overrides["port"] != null:

			CharacterSelectionState.set_training_port(int(overrides["port"]))

		if overrides["watch"] != null:

			CharacterSelectionState.set_training_watch_mode(bool(overrides["watch"]))

		if overrides["time_scale"] != null:

			CharacterSelectionState.set_training_time_scale(float(overrides["time_scale"]))

		if bool(overrides["match_mode"]):

			training_match_mode = true

	if overrides["quit_idle"] != null:

		headless_quit_idle_seconds = max(0.0, float(overrides["quit_idle"]))

	if overrides["record_path"] != null:

		training_record_path = String(overrides["record_path"])

	if overrides["max_steps"] != null:

		headless_round_max_steps = int(overrides["max_steps"])

	if overrides["max_seconds"] != null:

		headless_round_max_seconds = float(overrides["max_seconds"])

	if overrides["max_kills"] != null:

		headless_round_max_kills = int(overrides["max_kills"])

	if overrides["rewards_path"] != null:

		headless_rewards_path = String(overrides["rewards_path"])

	if overrides["super_reward_path"] != null:

		headless_super_reward_path = String(overrides["super_reward_path"])

	if overrides["bot_config_p1"] != null:

		headless_bot_config_p1_path = String(overrides["bot_config_p1"])

	if overrides["bot_config_p2"] != null:

		headless_bot_config_p2_path = String(overrides["bot_config_p2"])



func _configure_net_driver() -> void:

	if _is_headless_runtime() and not ProjectSettings.get_setting("network/enable_net_driver_headless", false):

		net_driver_enabled = false

	if not net_driver_enabled:

		return

	var players: Array = []

	if player_one:

		players.append(player_one)

	if player_two:

		players.append(player_two)

	net_driver.configure(players)

	net_driver.set_local_player_ids(local_player_ids)



func set_net_driver_enabled(enabled: bool) -> void:

	net_driver_enabled = enabled

	if net_driver_enabled:

		_configure_net_driver()

		return

	for player_id in [1, 2]:

		var player := player_one if player_id == 1 else player_two

		if player == null:

			continue

		var reader: Variant = player.get("input_reader") if player.has_method("get") else null

		if reader and reader.has_method("set_use_external_frames"):

			var driver := bot_driver_one if player_id == 1 else bot_driver_two

			var use_external := driver != null and driver.enabled

			reader.set_use_external_frames(use_external)



func receive_remote_input(player_id: int, frame_number: int, frame: Dictionary) -> void:

	if not net_driver_enabled:

		return

	net_driver.receive_remote_input(player_id, frame_number, frame)



func _configure_dev_mode(enabled: bool) -> void:

	dev_mode_enabled = enabled

	if DevDebug:

		DevDebug.configure(enabled)

	if dev_hud:

		dev_hud.configure(enabled)

		if enabled:

			dev_hud.configure_training(training_enabled, training_watch_mode, training_time_scale, training_port)

			dev_hud.update_training_metrics(training_manager.get_metrics())

			_sync_trainer_ui()

		if enabled and not dev_hud.reload_requested.is_connected(_on_dev_reload_requested):

			dev_hud.reload_requested.connect(_on_dev_reload_requested)

		elif not enabled and dev_hud.reload_requested.is_connected(_on_dev_reload_requested):

			dev_hud.reload_requested.disconnect(_on_dev_reload_requested)

		if enabled and not dev_hud.training_toggle_requested.is_connected(_on_training_toggle_requested):

			dev_hud.training_toggle_requested.connect(_on_training_toggle_requested)

		elif not enabled and dev_hud.training_toggle_requested.is_connected(_on_training_toggle_requested):

			dev_hud.training_toggle_requested.disconnect(_on_training_toggle_requested)

		if enabled and not dev_hud.training_watch_toggled.is_connected(_on_training_watch_toggled):

			dev_hud.training_watch_toggled.connect(_on_training_watch_toggled)

		elif not enabled and dev_hud.training_watch_toggled.is_connected(_on_training_watch_toggled):

			dev_hud.training_watch_toggled.disconnect(_on_training_watch_toggled)

		if enabled and not dev_hud.training_reset_requested.is_connected(_on_training_reset_requested):

			dev_hud.training_reset_requested.connect(_on_training_reset_requested)

		elif not enabled and dev_hud.training_reset_requested.is_connected(_on_training_reset_requested):

			dev_hud.training_reset_requested.disconnect(_on_training_reset_requested)

		if enabled and not dev_hud.training_logging_toggled.is_connected(_on_training_logging_toggled):

			dev_hud.training_logging_toggled.connect(_on_training_logging_toggled)

		elif not enabled and dev_hud.training_logging_toggled.is_connected(_on_training_logging_toggled):

			dev_hud.training_logging_toggled.disconnect(_on_training_logging_toggled)

		if enabled and not dev_hud.genome_load_requested.is_connected(_on_genome_load_requested):

			dev_hud.genome_load_requested.connect(_on_genome_load_requested)

		elif not enabled and dev_hud.genome_load_requested.is_connected(_on_genome_load_requested):

			dev_hud.genome_load_requested.disconnect(_on_genome_load_requested)

		if enabled and not dev_hud.round_limits_requested.is_connected(_on_round_limits_requested):

			dev_hud.round_limits_requested.connect(_on_round_limits_requested)

		elif not enabled and dev_hud.round_limits_requested.is_connected(_on_round_limits_requested):

			dev_hud.round_limits_requested.disconnect(_on_round_limits_requested)

		if enabled and not dev_hud.rewards_requested.is_connected(_on_rewards_requested):

			dev_hud.rewards_requested.connect(_on_rewards_requested)

		elif not enabled and dev_hud.rewards_requested.is_connected(_on_rewards_requested):

			dev_hud.rewards_requested.disconnect(_on_rewards_requested)

		if enabled and not dev_hud.ga_config_requested.is_connected(_on_ga_config_requested):

			dev_hud.ga_config_requested.connect(_on_ga_config_requested)

		elif not enabled and dev_hud.ga_config_requested.is_connected(_on_ga_config_requested):

			dev_hud.ga_config_requested.disconnect(_on_ga_config_requested)

		if enabled and not dev_hud.bot_config_requested.is_connected(_on_bot_config_requested):

			dev_hud.bot_config_requested.connect(_on_bot_config_requested)

		elif not enabled and dev_hud.bot_config_requested.is_connected(_on_bot_config_requested):

			dev_hud.bot_config_requested.disconnect(_on_bot_config_requested)

		if enabled and not dev_hud.trainer_start_requested.is_connected(_on_trainer_start_requested):

			dev_hud.trainer_start_requested.connect(_on_trainer_start_requested)

		elif not enabled and dev_hud.trainer_start_requested.is_connected(_on_trainer_start_requested):

			dev_hud.trainer_start_requested.disconnect(_on_trainer_start_requested)

		if enabled and not dev_hud.trainer_stop_requested.is_connected(_on_trainer_stop_requested):

			dev_hud.trainer_stop_requested.connect(_on_trainer_stop_requested)

		elif not enabled and dev_hud.trainer_stop_requested.is_connected(_on_trainer_stop_requested):

			dev_hud.trainer_stop_requested.disconnect(_on_trainer_stop_requested)

		if enabled and dev_hud.has_signal("live_train_start_requested") and not dev_hud.live_train_start_requested.is_connected(_on_live_train_start_requested):

			dev_hud.live_train_start_requested.connect(_on_live_train_start_requested)

		elif (not enabled) and dev_hud.has_signal("live_train_start_requested") and dev_hud.live_train_start_requested.is_connected(_on_live_train_start_requested):

			dev_hud.live_train_start_requested.disconnect(_on_live_train_start_requested)

		if enabled and dev_hud.has_signal("live_train_stop_requested") and not dev_hud.live_train_stop_requested.is_connected(_on_live_train_stop_requested):

			dev_hud.live_train_stop_requested.connect(_on_live_train_stop_requested)

		elif (not enabled) and dev_hud.has_signal("live_train_stop_requested") and dev_hud.live_train_stop_requested.is_connected(_on_live_train_stop_requested):

			dev_hud.live_train_stop_requested.disconnect(_on_live_train_stop_requested)

		if enabled and dev_hud.has_signal("live_train_save_requested") and not dev_hud.live_train_save_requested.is_connected(_on_live_train_save_requested):

			dev_hud.live_train_save_requested.connect(_on_live_train_save_requested)

		elif (not enabled) and dev_hud.has_signal("live_train_save_requested") and dev_hud.live_train_save_requested.is_connected(_on_live_train_save_requested):

			dev_hud.live_train_save_requested.disconnect(_on_live_train_save_requested)

		if enabled and not dev_hud.ga_model_save_requested.is_connected(_on_ga_model_save_requested):

			dev_hud.ga_model_save_requested.connect(_on_ga_model_save_requested)

		elif not enabled and dev_hud.ga_model_save_requested.is_connected(_on_ga_model_save_requested):

			dev_hud.ga_model_save_requested.disconnect(_on_ga_model_save_requested)

		if enabled:

			_refresh_genome_status()

			_refresh_round_limits_ui()

			_refresh_rewards_ui()

			_refresh_ga_config_ui()

			_ensure_trainer_running()



func _apply_debug_hitboxes() -> void:

	var tree := get_tree()

	if tree:

		tree.debug_collisions_hint = debug_hitboxes

	if player_one and player_one.has_method("set_debug_visuals_enabled"):

		player_one.set_debug_visuals_enabled(debug_hitboxes)

	if player_two and player_two.has_method("set_debug_visuals_enabled"):

		player_two.set_debug_visuals_enabled(debug_hitboxes)



func _unhandled_input(event: InputEvent) -> void:

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:

		debug_hitboxes = not debug_hitboxes

		_apply_debug_hitboxes()

	if dev_mode_enabled and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:

		if dev_hud and dev_hud.has_method("toggle_observation_mode"):

			dev_hud.toggle_observation_mode()

		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()

		return

	if dev_mode_enabled and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and event.ctrl_pressed:

		_reload_current_scene()

		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()

		return

	if dev_mode_enabled and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		_dev_hot_reload_mechanics()
		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()
		return

	if dev_mode_enabled and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		_reload_current_scene()
		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()
		return

	if dev_mode_enabled and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_1 and event.alt_pressed:

		_dev_hot_reload_mechanics()

		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()

		return



func _on_dev_reload_requested() -> void:

	_reload_current_scene()


func _dev_hot_reload_mechanics() -> void:
	_dev_reload_script("res://engine/mecanicas/walk.gd")
	_dev_reload_script("res://engine/mecanicas/jump.gd")
	_dev_reload_script("res://engine/mecanicas/dash.gd")
	_dev_reload_script("res://engine/mecanicas/shoot.gd")
	_dev_reload_script("res://engine/mecanicas/aiming.gd")

	for player in [player_one, player_two]:
		if player != null and player.has_method("dev_hot_reload_mechanics"):
			player.dev_hot_reload_mechanics()

	if DevDebug:
		DevDebug.log_event("hot_reload", "Main dev mechanics reload")


func _dev_reload_script(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var script_res: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if script_res and script_res.has_method("reload"):
		script_res.call("reload", false)
	if DevDebug and path == "res://engine/mecanicas/dash.gd":
		var mtime := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
		DevDebug.log_event("hot_reload", "dash.gd mtime=%d" % int(mtime))



func _reload_current_scene() -> void:

	if DevDebug:

		DevDebug.log_event("dev_hud", "Reload solicitado")

	if dev_mode_enabled:
		_dev_reload_script("res://engine/mecanicas/walk.gd")
		_dev_reload_script("res://engine/mecanicas/jump.gd")
		_dev_reload_script("res://engine/mecanicas/dash.gd")
		_dev_reload_script("res://engine/mecanicas/shoot.gd")
		_dev_reload_script("res://engine/mecanicas/aiming.gd")

	if CharacterRegistry:

		CharacterRegistry.reload_cache()

	var tree := get_tree()

	if tree == null:

		push_warning("SceneTree indisponível para reload")

		return

	var status := tree.reload_current_scene()

	if status != OK:

		push_error("Falha ao recarregar cena: %s" % status)



func _physics_process(delta: float) -> void:

	if net_driver_enabled and not training_enabled and not bot_player_one_enabled and not bot_player_two_enabled:
		set_net_driver_enabled(false)
	if training_enabled:

		training_manager.step(delta)

		if OS.has_method("get_cmdline_user_args") and OS.get_cmdline_user_args().has("--debug-bridge"):

			if int(Time.get_ticks_msec()) % 1000 < 17:

				print("[TrainingDebug] %s" % [str(training_manager.get_metrics().get("bridge_debug", {}))])

		if dev_hud and dev_mode_enabled:

			dev_hud.update_training_metrics(training_manager.get_metrics())

	_poll_best_genome(delta)

	_poll_current_bot(delta)

	_poll_observation_stats(delta)

	_update_trainer_process_watchdog()

	if net_driver_enabled:

		net_driver.step_frame()

	else:

		_step_bot_drivers(delta)

	var sudden := sudden_death.tick(delta, match_over, round_active, player_one, player_two, wrap_bounds, Callable(self, "_get_player_half_width"))

	if bool(sudden.get("redraw", false)):

		queue_redraw()

	if bool(sudden.get("restart_round", false)):

		if match_over or not round_active:

			return

		sudden_death_crush_draw_resolving = true

		if player_one and not bool(player_one.get("is_dead")) and player_one.has_method("die"):

			player_one.call("die")

		if player_two and not bool(player_two.get("is_dead")) and player_two.has_method("die"):

			player_two.call("die")

		sudden_death_crush_draw_resolving = false

		round_active = false

		_clear_arrows()

		call_deferred("_start_round")

		return

	_record_state()

	if not wrap_enabled:

		return

	_apply_wrap(player_one)

	_apply_wrap(player_two)







func _get_player_half_width(player: Node) -> float:

	if player == null:

		return 0.0

	var shape_node := player.get_node_or_null("CollisionShape2D")

	if shape_node == null or not (shape_node is CollisionShape2D):

		return 0.0

	var collider: CollisionShape2D = shape_node as CollisionShape2D

	if collider.shape == null:

		return 0.0

	var scale_abs := collider.global_scale.abs()

	var shape := collider.shape

	if shape is RectangleShape2D:

		return (shape as RectangleShape2D).size.x * scale_abs.x * 0.5

	if shape is CircleShape2D:

		var radius := (shape as CircleShape2D).radius

		return radius * maxf(scale_abs.x, scale_abs.y)

	return 0.0

func _draw() -> void:

	if sudden_death == null or not sudden_death.draw_walls:

		return

	if sudden_death.phase != 1 and sudden_death.phase != 2:

		return

	if wrap_bounds.size == Vector2.ZERO:

		return

	var world_left := wrap_bounds.position.x

	var world_right := wrap_bounds.position.x + wrap_bounds.size.x

	var world_top := wrap_bounds.position.y

	var world_bottom := wrap_bounds.position.y + wrap_bounds.size.y

	var local_top_left := to_local(Vector2(world_left, world_top))

	var local_top_right := to_local(Vector2(world_right, world_top))

	var local_bottom_left := to_local(Vector2(world_left, world_bottom))

	var local_width := local_top_right.x - local_top_left.x

	var local_height := local_bottom_left.y - local_top_left.y

	var wall_width := local_width * sudden_death.close_percent

	if wall_width <= 0.0:

		return

	var left_rect := Rect2(local_top_left, Vector2(wall_width, local_height))

	var right_rect := Rect2(Vector2(local_top_left.x + local_width - wall_width, local_top_left.y), Vector2(wall_width, local_height))

	var fill := Color(0.85, 0.12, 0.12, 0.32)

	draw_rect(left_rect, fill, true)

	draw_rect(right_rect, fill, true)



func _poll_best_genome(delta: float) -> void:

	if not auto_apply_best_genome:

		return

	if not dev_mode_enabled:

		return

	if trainer_running:

		return

	if training_enabled:

		var metrics := training_manager.get_metrics()

		if bool(metrics.get("connected", false)):

			return

	best_genome_poll_accum += delta

	if best_genome_poll_accum < 1.0:

		return

	best_genome_poll_accum = 0.0

	var path := DEFAULT_GENOME

	var signature := _file_signature(path)

	if signature == "" or signature == best_genome_last_signature:

		return

	best_genome_last_signature = signature

	_on_genome_load_requested(path)

	if DevDebug:

		DevDebug.log_event("trainer", "Auto-aplicou best_genome.json")



func _poll_current_bot(delta: float) -> void:

	if training_enabled:

		return

	if not bot_player_one_enabled and not bot_player_two_enabled:

		return

	current_bot_poll_accum += delta

	if current_bot_poll_accum < 1.0:

		return

	current_bot_poll_accum = 0.0

	_poll_current_bot_for_player(1)

	_poll_current_bot_for_player(2)

	_apply_bot_display_names()



func _poll_current_bot_for_player(player_id: int) -> void:

	var enabled := bot_player_one_enabled if player_id == 1 else bot_player_two_enabled

	if not enabled:

		return

	var policy := bot_player_one_policy if player_id == 1 else bot_player_two_policy

	if policy != "genetic":

		return

	var profile := bot_profile_p1 if player_id == 1 else bot_profile_p2

	if profile == "":

		profile = DEFAULT_PROFILE

	var path := "%s/%s/current_bot.json" % [BOTS_DIR, profile]

	var signature := _file_signature(path)

	if signature == "":

		return

	if player_id == 1:

		if signature == current_bot_last_signature_p1:

			return

		current_bot_last_signature_p1 = signature

	else:

		if signature == current_bot_last_signature_p2:

			return

		current_bot_last_signature_p2 = signature

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:

		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())

	if parsed is Dictionary:

		if player_id == 1:

			current_bot_meta_p1 = parsed as Dictionary

		else:

			current_bot_meta_p2 = parsed as Dictionary

		if dev_hud and dev_hud.has_method("update_current_bot"):

			dev_hud.update_current_bot(parsed as Dictionary)



func _poll_observation_stats(delta: float) -> void:

	if not dev_mode_enabled:

		return

	if dev_hud == null or not dev_hud.has_method("update_observation_stats"):

		return

	observation_poll_accum += delta

	if observation_poll_accum < 0.25:

		return

	observation_poll_accum = 0.0

	var fps := 0.0

	if Performance.has_method("get_monitor"):

		fps = float(Performance.get_monitor(Performance.TIME_FPS))

	var p1_action := bot_driver_one.get_last_action() if bot_driver_one else {}

	var p2_action := bot_driver_two.get_last_action() if bot_driver_two else {}

	_update_action_ema("p1", p1_action)

	_update_action_ema("p2", p2_action)

	var p1_policy := bot_driver_one.get_policy_id() if bot_driver_one else ""

	var p2_policy := bot_driver_two.get_policy_id() if bot_driver_two else ""

	var p1_arrows := int(player_one.get("arrows")) if player_one else 0

	var p2_arrows := int(player_two.get("arrows")) if player_two else 0

	dev_hud.update_observation_stats({

		"fps": fps,

		"round_index": int(round_index),

		"wins": wins.duplicate(true),

		"p1": {"policy": p1_policy, "arrows": p1_arrows, "action": p1_action, "ema": obs_action_ema["p1"]},

		"p2": {"policy": p2_policy, "arrows": p2_arrows, "action": p2_action, "ema": obs_action_ema["p2"]},

	})



func _update_action_ema(key: String, action: Dictionary) -> void:

	if not obs_action_ema.has(key):

		return

	var ema: Dictionary = obs_action_ema[key]

	var shoot := 1.0 if bool(action.get("shoot_is_pressed", false)) else 0.0

	var melee := 1.0 if bool(action.get("melee_pressed", false)) else 0.0

	var jump := 1.0 if bool(action.get("jump_pressed", false)) else 0.0

	var dash_any := false

	var dash = action.get("dash_pressed", [])

	if dash is Array:

		dash_any = (dash as Array).size() > 0

	var dash_f := 1.0 if dash_any else 0.0

	ema["shoot"] = lerpf(float(ema.get("shoot", 0.0)), shoot, obs_action_ema_alpha)

	ema["melee"] = lerpf(float(ema.get("melee", 0.0)), melee, obs_action_ema_alpha)

	ema["jump"] = lerpf(float(ema.get("jump", 0.0)), jump, obs_action_ema_alpha)

	ema["dash"] = lerpf(float(ema.get("dash", 0.0)), dash_f, obs_action_ema_alpha)



func _file_signature(path: String) -> String:

	if not FileAccess.file_exists(path):

		return ""

	var modified: int = int(FileAccess.get_modified_time(path))

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)

	if file == null:

		return ""

	var length: int = int(file.get_length())

	var head_len: int = mini(length, 256)

	var head_bytes: PackedByteArray = file.get_buffer(head_len)

	var head := head_bytes.get_string_from_utf8()

	var tail := ""

	if length > 256:

		file.seek(maxi(length - 256, 0))

		var tail_bytes: PackedByteArray = file.get_buffer(mini(256, length))

		tail = tail_bytes.get_string_from_utf8()

	return "%d:%d:%s:%s" % [modified, length, head, tail]



func _start_round() -> void:

	if match_over:

		return

	round_active = true

	sudden_death.reset_round()

	if sudden_death.draw_walls:

		queue_redraw()

	round_index += 1

	var swapped := round_index % 2 == 0

	var spawn_points = arena_manager.get_spawn_points(swapped)

	if spawn_points.size() >= 2:

		if training_enabled:

			var rng := RandomNumberGenerator.new()

			rng.randomize()

			var offset_options := [-140.0, 0.0, 140.0]

			var offset := float(offset_options[rng.randi_range(0, offset_options.size() - 1)])

			spawn_points[0].x += offset

			spawn_points[1].x -= offset

		elif dev_mode_enabled:

			var rng := RandomNumberGenerator.new()

			rng.randomize()

			var offset_options := [-140.0, 0.0, 140.0]

			var offset := float(offset_options[rng.randi_range(0, offset_options.size() - 1)])

			spawn_points[0].x += offset

			spawn_points[1].x -= offset

		player_one.reset_for_round(spawn_points[0])

		player_two.reset_for_round(spawn_points[1])

		_reset_bot_drivers()

	else:

		push_warning("ArenaDefinition does not provide at least two spawn points. Keeping previous player positions.")

		_reset_bot_drivers()

	if training_enabled:

		if training_match_reset:

			training_match_reset = false

			training_manager.reset_episode()



func _configure_bot_drivers() -> void:

	var bots_enabled := bot_player_one_enabled or bot_player_two_enabled

	if bots_enabled and bot_disable_net_driver and net_driver_enabled:

		set_net_driver_enabled(false)

	if player_one and player_two:

		var config_p1 := _build_bot_config(1, bot_player_one_policy)

		bot_driver_one.configure(self, player_one, player_two, bot_player_one_policy, config_p1)

		bot_driver_one.set_enabled(bot_player_one_enabled)

		var config_p2 := _build_bot_config(2, bot_player_two_policy)

		bot_driver_two.configure(self, player_two, player_one, bot_player_two_policy, config_p2)

		bot_driver_two.set_enabled(bot_player_two_enabled)

	_refresh_genome_status()





func _build_bot_config(player_id: int, policy_id: String) -> Dictionary:

	var profile := bot_profile_p1 if player_id == 1 else bot_profile_p2

	if profile == "":

		profile = DEFAULT_PROFILE

	var config: Dictionary = {

		"profile": profile,

		"config_path": "%s/%s/handmade.json" % [BOTS_DIR, profile]

	}

	if policy_id == "genetic":

		var path := genetic_genome_path_p1 if player_id == 1 else genetic_genome_path_p2

		if path != "":

			config["genome_path"] = path

	return config



func _format_genome_result(label: String, result: Dictionary) -> String:

	var ok := bool(result.get("ok", false))

	if ok:

		return "%s OK" % label

	var error := String(result.get("error", "erro"))

	return "%s erro: %s" % [label, error]



func _load_genome_for_bots(path: String) -> String:

	var status_parts: Array[String] = []

	if bot_driver_one and bot_driver_one.get_policy_id() == "genetic":

		var result_one: Dictionary = bot_driver_one.load_genome(path)

		status_parts.append(_format_genome_result("P1", result_one))

	if bot_driver_two and bot_driver_two.get_policy_id() == "genetic":

		var result_two: Dictionary = bot_driver_two.load_genome(path)

		status_parts.append(_format_genome_result("P2", result_two))

	if status_parts.is_empty():

		return "Sem bot genetico"

	return " | ".join(status_parts)



func _update_genome_ui(status: String) -> void:

	if dev_hud and dev_mode_enabled:

		var path_text := genetic_genome_path_p1

		if genetic_genome_path_p1 != genetic_genome_path_p2 and genetic_genome_path_p2 != "":

			path_text = "P1: %s\nP2: %s" % [genetic_genome_path_p1, genetic_genome_path_p2]

		dev_hud.configure_genome(path_text, status)



func _refresh_genome_status() -> void:

	if not dev_hud or not dev_mode_enabled:

		return

	var status_parts: Array[String] = []

	if bot_driver_one and bot_driver_one.get_policy_id() == "genetic":

		if genetic_genome_path_p1 == "":

			status_parts.append("P1 caminho vazio")

		else:

			status_parts.append(_format_genome_result("P1", bot_driver_one.load_genome(genetic_genome_path_p1)))

	if bot_driver_two and bot_driver_two.get_policy_id() == "genetic":

		if genetic_genome_path_p2 == "":

			status_parts.append("P2 caminho vazio")

		else:

			status_parts.append(_format_genome_result("P2", bot_driver_two.load_genome(genetic_genome_path_p2)))

	if status_parts.is_empty():

		_update_genome_ui("Sem bot genetico")

		return

	_update_genome_ui(" | ".join(status_parts))



func _on_round_limits_requested(max_steps: int, max_seconds: float, max_kills: int) -> void:

	training_manager.set_round_limits(max_steps, max_seconds, max_kills)

	_save_round_limits_config(max_steps, max_seconds, max_kills)

	_refresh_round_limits_ui()

	if dev_hud and dev_mode_enabled:

		dev_hud.update_training_metrics(training_manager.get_metrics())



func _on_rewards_requested(time_without_kill: float, kill_reward: float, death_reward: float, time_alive: float) -> void:

	training_manager.set_rewards(time_without_kill, kill_reward, death_reward, time_alive)

	_save_rewards_config(time_without_kill, kill_reward, death_reward, time_alive)

	_refresh_rewards_ui()

	if dev_hud and dev_mode_enabled:

		dev_hud.update_training_metrics(training_manager.get_metrics())



func _on_ga_config_requested(generation_round: bool, generations: int) -> void:

	_save_ga_config(generation_round, generations)

	_refresh_ga_config_ui()



func _on_bot_config_requested(player_id: int, reward_config: Dictionary) -> void:

	training_manager.set_bot_reward_config(player_id, reward_config)

	if player_id == 1:

		_save_bot_config(DEFAULT_BOT_P1_PATH, "P1", reward_config)

	elif player_id == 2:

		_save_bot_config(DEFAULT_BOT_P2_PATH, "P2", reward_config)

	if dev_hud and dev_mode_enabled:

		dev_hud.update_training_metrics(training_manager.get_metrics())



func _on_trainer_start_requested(python_path: String, script_path: String, extra_args: String) -> void:

	_start_trainer_process(python_path, script_path, extra_args, false)



func _on_trainer_stop_requested() -> void:

	if trainer_process_id != 0 and OS.is_process_running(trainer_process_id):

		OS.kill(trainer_process_id)

	trainer_process_id = 0

	trainer_running = false

	trainer_manual_stop = true

	_set_trainer_status("Trainer: parado")

	_sync_trainer_ui()



func _on_ga_model_save_requested(player_id: int, model_name: String) -> void:

	training_manager.request_save_model(player_id, model_name)



func _on_live_train_start_requested() -> void:

	_start_live_training()



func _on_live_train_stop_requested() -> void:

	_stop_live_training()



func _on_live_train_save_requested(player_id: int) -> void:

	var name := _build_live_save_name(player_id)

	training_manager.request_save_model(player_id, name)

	if dev_hud and dev_mode_enabled and dev_hud.has_method("set_live_train_status"):

		dev_hud.set_live_train_status("Live: salvou %s" % name)



func _build_live_save_name(player_id: int) -> String:

	var metrics := training_manager.get_metrics()

	var ga: Dictionary = metrics.get("ga_state", {}) if metrics.get("ga_state", {}) is Dictionary else {}

	var state: Dictionary = {}

	if ga.has(player_id) and ga[player_id] is Dictionary:

		state = ga[player_id] as Dictionary

	else:

		var key := str(player_id)

		if ga.has(key) and ga[key] is Dictionary:

			state = ga[key] as Dictionary

	var gen := int(state.get("generation", 0))

	var ind := int(state.get("individual", 0))

	var epi := int(state.get("episode_in_individual", 0))

	return "live_p%d_gen%d_ind%d_ep%d" % [int(player_id), gen, ind, epi]



func _start_live_training() -> void:

	training_watch_mode = true

	training_time_scale = 1.0

	training_port = 9009

	training_enabled = true

	bot_player_one_enabled = true

	bot_player_two_enabled = true

	bot_player_one_policy = "external"

	bot_player_two_policy = "external"

	_configure_bot_drivers()

	set_net_driver_enabled(false)

	training_manager.force_external_policies = true

	training_manager.set_watch_mode(training_watch_mode, training_time_scale)

	training_manager.start(training_port)

	if dev_hud and dev_mode_enabled:

		dev_hud.configure_training(training_enabled, training_watch_mode, training_time_scale, training_port)

		dev_hud.update_training_metrics(training_manager.get_metrics())

		if dev_hud.has_method("set_live_train_status"):

			dev_hud.set_live_train_status("Live: rodando")



	var args := "--population 1 --elite 1 --episodes-per-genome 2 --generations 0 --opponent baseline --learn-aim --aim-bins 9 --watch --time-scale 1.0"

	_start_trainer_process("python", "engine/tools/training_genetic_ga.py", args, true)



func _stop_live_training() -> void:

	_on_trainer_stop_requested()

	training_enabled = false

	training_manager.stop()

	training_manager.force_external_policies = false

	bot_player_one_policy = "genetic"

	bot_player_two_policy = "genetic"

	_configure_bot_drivers()

	_refresh_genome_status()

	if dev_hud and dev_mode_enabled and dev_hud.has_method("set_live_train_status"):

		dev_hud.set_live_train_status("Live: parado")



func _refresh_round_limits_ui() -> void:

	if not dev_hud or not dev_mode_enabled:

		return

	var metrics := training_manager.get_metrics()

	dev_hud.configure_round_limits(

		int(metrics.get("round_max_steps", 0)),

		float(metrics.get("round_max_seconds", 0.0)),

		int(metrics.get("round_max_kills", 5))

	)



func _refresh_rewards_ui() -> void:

	if not dev_hud or not dev_mode_enabled:

		return

	var metrics := training_manager.get_metrics()

	dev_hud.configure_rewards(

		float(metrics.get("reward_time_without_kill", -0.001)),

		float(metrics.get("reward_kill", 1.0)),

		float(metrics.get("reward_death", -1.0)),

		float(metrics.get("reward_time_alive", 0.0))

	)



func _refresh_ga_config_ui() -> void:

	if not dev_hud or not dev_mode_enabled:

		return

	var config := _load_ga_config()

	var generation_round := bool(config.get("generation_per_round", true))

	var generations := int(config.get("generations", 0))

	dev_hud.configure_ga_config(generation_round, generations)



func _save_round_limits_config(max_steps: int, max_seconds: float, max_kills: int) -> void:

	var payload := _load_round_limits_config()

	payload["max_steps"] = max_steps

	payload["max_seconds"] = max_seconds

	payload["max_kills"] = max_kills

	var file := FileAccess.open(IA_ROUNDS_PATH, FileAccess.WRITE)

	if file == null:

		return

	file.store_string(JSON.stringify(payload, "  "))



func _load_trainer_config() -> Dictionary:

	var defaults := {

		"python_path": "python",

		"script_path": "engine/tools/training_genetic_ga.py",

		"script_args": "--host 127.0.0.1"

	}

	if not FileAccess.file_exists(IA_TRAINER_PATH):

		return defaults

	var file := FileAccess.open(IA_TRAINER_PATH, FileAccess.READ)

	if file == null:

		return defaults

	var parsed: Variant = JSON.parse_string(file.get_as_text())

	if parsed is Dictionary:

		return defaults.merged(parsed as Dictionary, true)

	return defaults



func _save_trainer_config(payload: Dictionary) -> void:

	var file := FileAccess.open(IA_TRAINER_PATH, FileAccess.WRITE)

	if file == null:

		return

	file.store_string(JSON.stringify(payload, "  "))



func _sync_trainer_ui() -> void:

	if not dev_hud or not dev_mode_enabled:

		return

	var python_path := String(trainer_config.get("python_path", "python"))

	var script_path := String(trainer_config.get("script_path", "engine/tools/training_genetic_ga.py"))

	var extra_args := String(trainer_config.get("script_args", ""))

	var running := trainer_running and trainer_process_id != 0 and OS.is_process_running(trainer_process_id)

	if trainer_running and not running:

		trainer_running = false

		trainer_process_id = 0

		_set_trainer_status("Trainer: finalizado")

		running = false

	dev_hud.configure_trainer(python_path, script_path, extra_args, running, trainer_status_text)



func _update_trainer_process_watchdog() -> void:

	if trainer_process_id == 0:

		return

	if not OS.is_process_running(trainer_process_id):

		trainer_process_id = 0

		trainer_running = false

		_set_trainer_status("Trainer: finalizado")

		_sync_trainer_ui()

		if training_enabled and not trainer_manual_stop:

			_ensure_trainer_running()



func _set_trainer_status(text: String) -> void:

	trainer_status_text = text

	if dev_hud and dev_mode_enabled:

		dev_hud.configure_trainer(

			String(trainer_config.get("python_path", "python")),

			String(trainer_config.get("script_path", "engine/tools/training_genetic_ga.py")),

			String(trainer_config.get("script_args", "")),

			trainer_running and trainer_process_id != 0 and OS.is_process_running(trainer_process_id),

			trainer_status_text

		)



func _ensure_trainer_running() -> void:

	if not training_enabled:

		return

	if trainer_manual_stop:

		return

	if trainer_running and trainer_process_id != 0 and OS.is_process_running(trainer_process_id):

		return

	var python_path := String(trainer_config.get("python_path", "python"))

	var script_path := String(trainer_config.get("script_path", "engine/tools/training_genetic_ga.py"))

	var extra_args := String(trainer_config.get("script_args", ""))

	_start_trainer_process(python_path, script_path, extra_args, true)



func _start_trainer_process(python_path: String, script_path: String, extra_args: String, auto_started: bool) -> void:

	var executable := python_path.strip_edges()

	if executable == "":

		executable = "python"

	if trainer_running and trainer_process_id != 0 and OS.is_process_running(trainer_process_id):

		if not auto_started:

			_set_trainer_status("Trainer: já em execução (PID %d)" % trainer_process_id)

		return

	var resolved_script := _resolve_trainer_script_path(script_path)

	if resolved_script == "":

		_set_trainer_status("Trainer: script inválido")

		trainer_running = false

		trainer_process_id = 0

		trainer_manual_stop = true

		_sync_trainer_ui()

		return

	trainer_manual_stop = false

	if auto_started:

		_set_trainer_status("Trainer: iniciando automaticamente...")

	else:

		_set_trainer_status("Trainer: iniciando...")

	var parsed_args := _parse_trainer_args(extra_args)

	parsed_args = _append_default_trainer_args(parsed_args)

	var args := PackedStringArray()

	args.append(resolved_script)

	args.append_array(parsed_args)

	var pid := OS.create_process(executable, args)

	if pid <= 0:

		_set_trainer_status("Trainer: falha ao iniciar %s" % executable)

		trainer_running = false

		trainer_process_id = 0

		trainer_manual_stop = true

		return

	trainer_process_id = pid

	trainer_running = true

	_set_trainer_status("Trainer: rodando (PID %d)" % pid)

	if not auto_started:

		trainer_config = {

			"python_path": executable,

			"script_path": script_path,

			"script_args": extra_args

		}

		_save_trainer_config(trainer_config)

	_sync_trainer_ui()



func _append_default_trainer_args(args: PackedStringArray) -> PackedStringArray:

	var result := args.duplicate()

	if not _args_contain_flag(result, "--host"):

		result.append("--host")

		result.append("127.0.0.1")

	if not _args_contain_flag(result, "--port"):

		result.append("--port")

		result.append(str(training_port))

	if not _args_contain_flag(result, "--time-scale"):

		result.append("--time-scale")

		result.append(str(training_time_scale))

	if not _args_contain_flag(result, "--save-path"):

		result.append("--save-path")

		result.append("BOTS/%s/best_genome.json" % DEFAULT_PROFILE)

	if not _args_contain_flag(result, "--log-path"):

		result.append("--log-path")

		result.append("BOTS/%s/logs/genetic_log.csv" % DEFAULT_PROFILE)

	if not _args_contain_flag(result, "--result-path"):

		result.append("--result-path")

		result.append("BOTS/%s/_last_trainer_result.json" % DEFAULT_PROFILE)

	if not _args_contain_flag(result, "--load-path"):

		var default_seed := "res://BOTS/profiles/%s/best_genome.json" % DEFAULT_PROFILE
		if FileAccess.file_exists(default_seed):

			result.append("--load-path")

			result.append("BOTS/%s/best_genome.json" % DEFAULT_PROFILE)

	if training_watch_mode and not _args_contain_flag(result, "--watch"):

		result.append("--watch")

	elif not training_watch_mode and not _args_contain_flag(result, "--no-watch") and _args_contain_flag(result, "--watch") == false:

		result.append("--no-watch")

	return result



func _args_contain_flag(args: PackedStringArray, flag: String) -> bool:

	for value in args:

		if value == flag:

			return true

	return false



func _resolve_trainer_script_path(path: String) -> String:

	var trimmed := path.strip_edges()

	if trimmed == "":

		return ""

	if trimmed.begins_with("res://") or trimmed.begins_with("user://"):

		if FileAccess.file_exists(trimmed):

			return ProjectSettings.globalize_path(trimmed)

		return ""

	if _is_absolute_path(trimmed):

		return trimmed if FileAccess.file_exists(trimmed) else ""

	var resource_path := "res://" + trimmed

	if FileAccess.file_exists(resource_path):

		return ProjectSettings.globalize_path(resource_path)

	return ""



func _is_absolute_path(path: String) -> bool:

	if path.begins_with("/"):

		return true

	if path.length() > 1 and path[1] == ":":

		return true

	return false



func _parse_trainer_args(args_text: String) -> PackedStringArray:

	var result := PackedStringArray()

	var trimmed := args_text.strip_edges()

	if trimmed == "":

		return result

	var regex := RegEx.new()

	if regex.compile("\"([^\"]*)\"|'([^']*)'|\\S+") != OK:

		return PackedStringArray(trimmed.split(" ", false))

	var matches := regex.search_all(trimmed)

	for match in matches:

		if match.get_string(1) != "":

			result.append(match.get_string(1))

		elif match.get_string(2) != "":

			result.append(match.get_string(2))

		else:

			result.append(match.get_string(0))

	return result



func _load_round_limits_config() -> Dictionary:

	if not FileAccess.file_exists(IA_ROUNDS_PATH):

		return {}

	var file := FileAccess.open(IA_ROUNDS_PATH, FileAccess.READ)

	if file == null:

		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())

	if parsed is Dictionary:

		return parsed as Dictionary

	return {}



func _save_rewards_config(time_without_kill: float, kill_reward: float, death_reward: float, time_alive: float) -> void:

	var payload := {

		"time_without_kill": time_without_kill,

		"kill": kill_reward,

		"death": death_reward,

		"time_alive": time_alive

	}

	var file := FileAccess.open(DEFAULT_REWARDS_PATH, FileAccess.WRITE)

	if file == null:

		return

	file.store_string(JSON.stringify(payload, "  "))



func _save_ga_config(generation_round: bool, generations: int) -> void:

	var payload := _load_ga_config()

	payload["generation_per_round"] = generation_round

	payload["generations"] = generations

	var file := FileAccess.open(IA_GA_PATH, FileAccess.WRITE)

	if file == null:

		return

	file.store_string(JSON.stringify(payload, "  "))



func _save_bot_config(path: String, name: String, reward_config: Dictionary) -> void:

	var payload := {

		"name": name,

		"reward": reward_config

	}

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:

		return

	file.store_string(JSON.stringify(payload, "  "))



func _load_ga_config() -> Dictionary:

	if not FileAccess.file_exists(IA_GA_PATH):

		return {}

	var file := FileAccess.open(IA_GA_PATH, FileAccess.READ)

	if file == null:

		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())

	if parsed is Dictionary:

		return parsed as Dictionary

	return {}



func _configure_training() -> void:

	var rewards_path := DEFAULT_REWARDS_PATH

	if _is_headless_runtime() and headless_rewards_path != "":

		rewards_path = headless_rewards_path

	training_manager.load_rewards(rewards_path)

	if headless_super_reward_path != "":

		training_manager.set_super_reward_config(headless_super_reward_path)

	training_manager.load_round_limits(IA_ROUNDS_PATH)

	if headless_round_max_steps >= 0 or headless_round_max_seconds >= 0.0 or headless_round_max_kills >= 0:

		training_manager.set_round_limits(

			headless_round_max_steps if headless_round_max_steps >= 0 else int(training_manager.round_max_steps),

			headless_round_max_seconds if headless_round_max_seconds >= 0.0 else float(training_manager.round_max_seconds),

			headless_round_max_kills if headless_round_max_kills >= 0 else int(training_manager.round_max_kills)

		)

	var bot_p1_path := DEFAULT_BOT_P1_PATH

	var bot_p2_path := DEFAULT_BOT_P2_PATH

	if _is_headless_runtime() and headless_bot_config_p1_path != "":

		bot_p1_path = headless_bot_config_p1_path

	if _is_headless_runtime() and headless_bot_config_p2_path != "":

		bot_p2_path = headless_bot_config_p2_path

	training_manager.load_bot_config(1, bot_p1_path)

	training_manager.load_bot_config(2, bot_p2_path)

	_apply_bot_display_names()

	training_manager.configure(self, player_one, player_two, bot_driver_one, bot_driver_two)

	training_manager.force_external_policies = _is_headless_runtime()

	if training_record_path != "":

		training_manager.set_recording(true, training_record_path)

	_refresh_round_limits_ui()

	_refresh_rewards_ui()

	_refresh_ga_config_ui()

	if not training_enabled:

		training_manager.stop()

		return

	set_net_driver_enabled(false)

	training_manager.set_watch_mode(training_watch_mode, training_time_scale)

	training_manager.start(training_port)

	if OS.has_method("get_cmdline_user_args") and OS.get_cmdline_user_args().has("--training"):

		print("[TrainingBridgeState] listening=%s port=%d err=%d" % [str(training_manager.bridge.is_listening), int(training_manager.bridge.port), int(training_manager.bridge.last_error)])

	if dev_hud and dev_mode_enabled:

		dev_hud.configure_training(training_enabled, training_watch_mode, training_time_scale, training_port)

		dev_hud.update_training_metrics(training_manager.get_metrics())

		_sync_trainer_ui()



func _set_training_enabled(enabled: bool) -> void:

	if enabled == training_enabled and enabled:

		training_manager.set_watch_mode(training_watch_mode, training_time_scale)

		return

	if enabled:

		training_manager.load_rewards(DEFAULT_REWARDS_PATH)

		training_manager.load_round_limits(IA_ROUNDS_PATH)

		training_manager.load_bot_config(1, DEFAULT_BOT_P1_PATH)

		training_manager.load_bot_config(2, DEFAULT_BOT_P2_PATH)

		_refresh_round_limits_ui()

		_refresh_rewards_ui()

		_refresh_ga_config_ui()

		training_match_reset = true

		training_prev_config = {

			"bot_p1_enabled": bot_player_one_enabled,

			"bot_p2_enabled": bot_player_two_enabled,

			"bot_p1_policy": bot_player_one_policy,

			"bot_p2_policy": bot_player_two_policy,

			"net_driver_enabled": net_driver_enabled

		}

		training_enabled = true

		bot_player_one_enabled = true

		bot_player_two_enabled = true

		if _is_headless_runtime():

			bot_player_one_policy = "external"

			bot_player_two_policy = "external"

		else:

			if bot_player_one_policy == "external" or bot_player_one_policy == "":

				bot_player_one_policy = "objective"

			if bot_player_two_policy == "external" or bot_player_two_policy == "":

				bot_player_two_policy = "objective"

		trainer_manual_stop = true

		_configure_bot_drivers()

		set_net_driver_enabled(false)

		training_manager.set_watch_mode(training_watch_mode, training_time_scale)

		training_manager.start(training_port)

		_apply_bot_display_names()

	else:

		training_enabled = false

		training_manager.stop()

		if not training_prev_config.is_empty():

			bot_player_one_enabled = bool(training_prev_config.get("bot_p1_enabled", false))

			bot_player_two_enabled = bool(training_prev_config.get("bot_p2_enabled", false))

			bot_player_one_policy = String(training_prev_config.get("bot_p1_policy", "simple"))

			bot_player_two_policy = String(training_prev_config.get("bot_p2_policy", "simple"))

			var prev_net_enabled := bool(training_prev_config.get("net_driver_enabled", false))

			set_net_driver_enabled(prev_net_enabled)

		training_prev_config = {}

		_configure_bot_drivers()

		_apply_bot_display_names()

	if dev_hud and dev_mode_enabled:

		dev_hud.configure_training(training_enabled, training_watch_mode, training_time_scale, training_port)

		dev_hud.update_training_metrics(training_manager.get_metrics())



func _on_training_toggle_requested(enabled: bool) -> void:

	_set_training_enabled(enabled)



func _on_training_watch_toggled(enabled: bool) -> void:

	training_watch_mode = enabled

	training_manager.set_watch_mode(training_watch_mode, training_time_scale)

	if dev_hud and dev_mode_enabled:

		dev_hud.configure_training(training_enabled, training_watch_mode, training_time_scale, training_port)



func _on_training_reset_requested() -> void:

	training_manager.request_reset()

	if dev_hud and dev_mode_enabled:

		dev_hud.update_training_metrics(training_manager.get_metrics())



func _on_training_logging_toggled(enabled: bool) -> void:

	training_manager.set_logging_enabled(enabled)

	if dev_hud and dev_mode_enabled:

		dev_hud.update_training_metrics(training_manager.get_metrics())



func _on_genome_load_requested(path: String) -> void:

	if trainer_process_id != 0 and OS.is_process_running(trainer_process_id):

		_on_trainer_stop_requested()

	var final_path := path

	if final_path == "":

		final_path = genetic_genome_path_p1

	if final_path == "":

		_update_genome_ui("Caminho vazio")

		return

	genetic_genome_path_p1 = final_path

	genetic_genome_path_p2 = final_path

	if CharacterSelectionState:

		CharacterSelectionState.set_genetic_genome_path(1, final_path)

		CharacterSelectionState.set_genetic_genome_path(2, final_path)

	var ensure_genetic := true

	if bot_driver_one and bot_driver_one.get_policy_id() == "genetic":

		ensure_genetic = false

	if bot_driver_two and bot_driver_two.get_policy_id() == "genetic":

		ensure_genetic = false

	if ensure_genetic:

		if bot_player_one_enabled:

			bot_player_one_policy = "genetic"

			if CharacterSelectionState:

				CharacterSelectionState.set_bot_policy(1, bot_player_one_policy)

		if bot_player_two_enabled:

			bot_player_two_policy = "genetic"

			if CharacterSelectionState:

				CharacterSelectionState.set_bot_policy(2, bot_player_two_policy)

		_configure_bot_drivers()

	_refresh_genome_status()



func _reset_bot_drivers() -> void:

	if bot_driver_one:

		bot_driver_one.reset()

	if bot_driver_two:

		bot_driver_two.reset()



func _step_bot_drivers(delta: float) -> void:

	if bot_driver_one and bot_driver_one.enabled:

		bot_driver_one.step(delta)

	if bot_driver_two and bot_driver_two.enabled:

		bot_driver_two.step(delta)



func _on_player_died(player: Node) -> void:

	if match_over or not round_active:

		return

	if sudden_death_crush_draw_resolving:

		return

	round_active = false

	if sudden_death and sudden_death.draw_walls:

		queue_redraw()

	if player == player_one:

		wins[2] += 1

	else:

		wins[1] += 1

	_update_score_ui()

	_clear_arrows()

	var winner_id := _check_match_winner()

	if winner_id > 0:

		_end_match(winner_id)

	else:

		call_deferred("_start_round")



func _check_match_winner() -> int:

	for id in wins.keys():

		if wins[id] >= MAX_WINS:

			return int(id)

	return 0



func _end_match(winner_id: int) -> void:

	match_over = true

	round_active = false

	if training_enabled:

		if training_match_mode:

			if winner_label:

				winner_label.visible = false

			return

		wins = {1: 0, 2: 0}

		match_over = false

		if winner_label:

			winner_label.visible = false

		call_deferred("_start_round")

		return

	if player_one:

		player_one.set_physics_process(false)

	if player_two:

		player_two.set_physics_process(false)

	if winner_label:

		winner_label.text = "%s venceu!" % _get_bot_display_name(winner_id)

		winner_label.visible = true

	await get_tree().create_timer(2.5).timeout

	get_tree().change_scene_to_file("res://engine/scenes/MainMenu.tscn")





func reset_training_match() -> void:

	if not training_enabled:

		return

	wins = {1: 0, 2: 0}

	match_over = false

	round_active = false

	call_deferred("_start_round")



func _update_score_ui() -> void:

	if score_label:

		var name_p1 := _get_bot_display_name(1)

		var name_p2 := _get_bot_display_name(2)

		score_label.text = "%s %d  x  %d %s" % [name_p1, wins[1], wins[2], name_p2]



func get_state() -> Dictionary:

	return {

		"wins": wins.duplicate(true),

		"round_index": round_index,

		"match_over": match_over,

		"round_active": round_active,

		"sudden_death": sudden_death.get_state() if sudden_death else {},

		"wrap_bounds": wrap_bounds,

		"wrap_padding": wrap_padding,

		"player_one": player_one.get_state() if player_one else {},

		"player_two": player_two.get_state() if player_two else {}

	}



func apply_state(state: Dictionary) -> void:

	if state.is_empty():

		return

	if state.has("wins") and state["wins"] is Dictionary:

		wins = (state["wins"] as Dictionary).duplicate(true)

	if state.has("round_index"):

		round_index = int(state["round_index"])

	if state.has("match_over"):

		match_over = bool(state["match_over"])

	if state.has("round_active"):

		round_active = bool(state["round_active"])

	if state.has("sudden_death") and state["sudden_death"] is Dictionary and sudden_death:

		sudden_death.apply_state(state["sudden_death"])

	if state.has("wrap_bounds"):

		wrap_bounds = state["wrap_bounds"]

	if state.has("wrap_padding"):

		wrap_padding = state["wrap_padding"]

	if state.has("player_one") and player_one and state["player_one"] is Dictionary:

		player_one.apply_state(state["player_one"])

	if state.has("player_two") and player_two and state["player_two"] is Dictionary:

		player_two.apply_state(state["player_two"])

	_update_score_ui()

	if sudden_death and sudden_death.draw_walls:

		queue_redraw()

	if winner_label:

		var winner_id := _check_match_winner() if match_over else 0

		if winner_id > 0:

			winner_label.text = "%s venceu!" % _get_bot_display_name(winner_id)

			winner_label.visible = true

		else:

			winner_label.visible = false

	if match_over:

		if player_one:

			player_one.set_physics_process(false)

		if player_two:

			player_two.set_physics_process(false)



func _apply_bot_display_names() -> void:

	if player_one and player_one.has_method("set_display_name"):

		player_one.set_display_name(_get_bot_display_name(1), _get_bot_label_color(1))

	if player_two and player_two.has_method("set_display_name"):

		player_two.set_display_name(_get_bot_display_name(2), _get_bot_label_color(2))

	_update_score_ui()



func _get_bot_display_name(player_id: int) -> String:

	var default_name := "P%d" % player_id

	if training_enabled and training_manager:

		var bot_names: Dictionary = training_manager.bot_names

		if bot_names.has(player_id):

			return String(bot_names[player_id])

	var enabled := bot_player_one_enabled if player_id == 1 else bot_player_two_enabled

	if enabled:

		var policy := bot_player_one_policy if player_id == 1 else bot_player_two_policy

		if policy == "genetic":

			var profile := bot_profile_p1 if player_id == 1 else bot_profile_p2

			if profile == "":

				profile = DEFAULT_PROFILE

			var meta := current_bot_meta_p1 if player_id == 1 else current_bot_meta_p2

			var suffix := ""

			var gn := _extract_bot_gn(meta)

			if gn != "":

				suffix = " (%s)" % gn

			return "%s%s" % [profile.capitalize(), suffix]

	return default_name



func _extract_bot_gn(meta: Dictionary) -> String:

	if meta.is_empty():

		return ""

	if meta.has("individual"):

		var g := int(meta.get("generation_global", meta.get("islands_round", 0)))

		var n := int(meta.get("individual", 0))

		if g > 0 and n > 0:

			return "G%d_N%d" % [g, n]

	var source := String(meta.get("source_rel", meta.get("source", "")))

	if source == "":

		return ""

	var g_idx := source.find("_G")

	var n_idx := source.find("_N")

	if g_idx < 0 or n_idx < 0:

		return ""

	var after_g := source.substr(g_idx + 2)

	var g_str := after_g.get_slice("_", 0)

	var after_n := source.substr(n_idx + 2)

	var n_str := after_n.get_slice("_", 0)

	var g_val := int(g_str)

	var n_val := int(n_str)

	if g_val <= 0 or n_val <= 0:

		return ""

	return "G%d_N%d" % [g_val, n_val]



func _get_bot_label_color(player_id: int) -> Color:

	if player_id == 1:

		return Color(0.95, 0.95, 0.95)

	return Color(0.9, 0.35, 0.35)



func enable_state_recording(enabled: bool) -> void:

	record_states = enabled

	if not record_states:

		clear_state_history()



func clear_state_history() -> void:

	state_history.clear()

	state_frame_index = 0



func _record_state() -> void:

	if not record_states:

		return

	state_history.append({

		"frame": state_frame_index,

		"state": get_state()

	})

	if state_history.size() > MAX_STATE_FRAMES:

		state_history.pop_front()

	state_frame_index += 1



func get_recorded_state(frame_offset: int = 0) -> Dictionary:

	if state_history.is_empty():

		return {}

	if frame_offset <= 0:

		return state_history[state_history.size() - 1]

	var index := state_history.size() - 1 - frame_offset

	if index < 0 or index >= state_history.size():

		return {}

	return state_history[index]



func apply_recorded_state(frame_offset: int = 0) -> void:

	var snapshot := get_recorded_state(frame_offset)

	if snapshot.is_empty():

		return

	if snapshot.has("state") and snapshot["state"] is Dictionary:

		apply_state(snapshot["state"])



func _clear_arrows() -> void:

	for arrow in get_tree().get_nodes_in_group("arrows"):

		arrow.queue_free()



func _configure_wrap_bounds() -> void:

	if arena_manager.has_wrap_bounds():

		wrap_bounds = arena_manager.get_wrap_bounds()

		wrap_padding = arena_manager.get_wrap_padding()

	else:

		wrap_bounds = _calculate_wrap_bounds()



func _calculate_wrap_bounds() -> Rect2:

	var colliders := _collect_static_colliders()

	var has_bounds := false

	var bounds := Rect2()

	for collider in colliders:

		var rect := _collider_rect(collider)

		if rect.size == Vector2.ZERO:

			continue

		if not has_bounds:

			bounds = rect

			has_bounds = true

		else:

			bounds = bounds.merge(rect)

	if not has_bounds:

		return Rect2(Vector2(-1200.0, -700.0), Vector2(2400.0, 1400.0))

	return bounds



func _collect_static_colliders() -> Array:

	var colliders: Array = []

	var shape_nodes := find_children("*", "CollisionShape2D", true, false)

	var polygon_nodes := find_children("*", "CollisionPolygon2D", true, false)

	for collider in shape_nodes + polygon_nodes:

		if collider is Node and _has_static_parent(collider):

			colliders.append(collider)

	return colliders



func _has_static_parent(node: Node) -> bool:

	var current: Node = node

	while current != null:

		if current is StaticBody2D:

			return true

		if current is CharacterBody2D or current is RigidBody2D:

			return false

		current = current.get_parent()

	return false



func _get_static_parent(node: Node) -> StaticBody2D:

	var current: Node = node

	while current != null:

		if current is StaticBody2D:

			return current as StaticBody2D

		if current is CharacterBody2D or current is RigidBody2D:

			return null

		current = current.get_parent()

	return null



func _configure_collision_masks() -> void:

	var colliders := _collect_static_colliders()

	var mask := 0

	for collider in colliders:

		var static_body := _get_static_parent(collider)

		if static_body:

			mask |= static_body.collision_layer

		if collider is CollisionShape2D:

			collider.disabled = false

			collider.one_way_collision = false

		elif collider is CollisionPolygon2D:

			collider.disabled = false

			collider.one_way_collision = false

	if mask == 0:

		mask = 1

		for collider in colliders:

			var static_body := _get_static_parent(collider)

			if static_body:

				static_body.collision_layer = 1

	mask |= CollisionLayersScript.PLAYER_BODY
	if player_one:

		player_one.collision_mask = mask

	if player_two:

		player_two.collision_mask = mask

	if not arena_manager.has_wrap_bounds():

		wrap_padding = Vector2(40.0, 40.0)



func _configure_arena_definition() -> void:

	if arena_definition:

		arena_manager.set_definition(arena_definition)

		if arena_definition.has_wrap_bounds():

			wrap_bounds = arena_definition.get_wrap_bounds()

			wrap_padding = arena_definition.get_wrap_padding()



func _normalize_segment_colliders() -> void:

	var colliders := _collect_static_colliders()

	for collider in colliders:

		if collider is CollisionShape2D:

			var shape: Shape2D = collider.shape

			if shape is SegmentShape2D:

				var static_body := _get_static_parent(collider)

				if static_body == null:

					continue

				if _has_auto_barrier(static_body, collider):

					continue

				var scale_abs: Vector2 = collider.scale.abs()

				if scale_abs.x < 0.5 and scale_abs.y < 0.5:

					continue

				var rect := RectangleShape2D.new()

				rect.size = Vector2(2.0, 2.0)

				var barrier := CollisionShape2D.new()

				barrier.name = "%s_Barrier" % collider.name

				barrier.shape = rect

				barrier.position = collider.position

				barrier.rotation = collider.rotation

				barrier.scale = scale_abs

				barrier.disabled = false

				barrier.one_way_collision = false

				barrier.set_meta("auto_segment_source", collider.get_path())

				static_body.add_child(barrier)

				barrier.owner = static_body.owner



func _has_auto_barrier(static_body: StaticBody2D, source: CollisionShape2D) -> bool:

	for child in static_body.get_children():

		if child is CollisionShape2D and child.has_meta("auto_segment_source"):

			if child.get_meta("auto_segment_source") == source.get_path():

				return true

	return false



func _collider_rect(collider: Node) -> Rect2:

	if collider is CollisionShape2D:

		var shape: Shape2D = collider.shape

		if shape is RectangleShape2D:

			var rect_shape: RectangleShape2D = shape as RectangleShape2D

			var size: Vector2 = rect_shape.size * collider.scale.abs()

			var origin: Vector2 = collider.global_position - size * 0.5

			return Rect2(origin, size)

		elif shape is CircleShape2D:

			var circle: CircleShape2D = shape as CircleShape2D

			var radius: float = circle.radius * maxf(collider.scale.abs().x, collider.scale.abs().y)

			var size: Vector2 = Vector2(radius * 2.0, radius * 2.0)

			var origin: Vector2 = collider.global_position - size * 0.5

			return Rect2(origin, size)

	elif collider is CollisionPolygon2D:

		var polygon: PackedVector2Array = collider.polygon

		if polygon.is_empty():

			return Rect2()

		var min_v: Vector2 = Vector2(INF, INF)

		var max_v: Vector2 = Vector2(-INF, -INF)

		for point in polygon:

			var world_point: Vector2 = collider.to_global(point)

			min_v.x = minf(min_v.x, world_point.x)

			min_v.y = minf(min_v.y, world_point.y)

			max_v.x = maxf(max_v.x, world_point.x)

			max_v.y = maxf(max_v.y, world_point.y)

		return Rect2(min_v, max_v - min_v)

	return Rect2()



func _apply_wrap(player: Node2D) -> void:

	if player == null:

		return

	var pos := player.global_position

	var left := wrap_bounds.position.x

	var right := wrap_bounds.position.x + wrap_bounds.size.x

	var top := wrap_bounds.position.y

	var bottom := wrap_bounds.position.y + wrap_bounds.size.y

	if pos.x < left - wrap_padding.x:

		pos.x = right + wrap_padding.x

	elif pos.x > right + wrap_padding.x:

		pos.x = left - wrap_padding.x

	if pos.y < top - wrap_padding.y:

		pos.y = bottom + wrap_padding.y

	elif pos.y > bottom + wrap_padding.y:

		pos.y = top - wrap_padding.y

	if pos != player.global_position:

		player.global_position = pos
