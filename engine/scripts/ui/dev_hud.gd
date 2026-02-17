extends CanvasLayer



signal reload_requested

signal training_toggle_requested(enabled: bool)

signal training_watch_toggled(enabled: bool)

signal training_reset_requested

signal training_logging_toggled(enabled: bool)

signal genome_load_requested(path: String)

signal round_limits_requested(max_steps: int, max_seconds: float, max_kills: int)

signal rewards_requested(time_without_kill: float, kill_reward: float, death_reward: float, time_alive: float)

signal ga_config_requested(generation_per_round: bool, generations: int)

signal bot_config_requested(player_id: int, reward_config: Dictionary)

signal ga_model_save_requested(player_id: int, model_name: String)

signal trainer_start_requested(python_path: String, script_path: String, extra_args: String)

signal trainer_stop_requested()



signal live_train_start_requested

signal live_train_stop_requested

signal live_train_save_requested(player_id: int)



@onready var panel := get_node_or_null("Panel")

@onready var label := get_node_or_null("Panel/Margin/VBox/EntriesLabel")

@onready var status_label := get_node_or_null("Panel/Margin/VBox/HeaderRow/StatusLabel")

@onready var reload_button := get_node_or_null("Panel/Margin/VBox/HeaderRow/ReloadButton")



@onready var training_group := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainingGroup")

@onready var rewards_group := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RewardsGroup")

@onready var round_group := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RoundGroup")

@onready var ga_group := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GaGroup")

@onready var genome_group := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup")

@onready var metrics_box := get_node_or_null("Panel/Margin/VBox/ContentRow/MetricsBox")

@onready var training_title := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainingGroup/TrainingTitle")

@onready var training_toggle := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainingGroup/TrainingToggle")

@onready var watch_toggle := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainingGroup/WatchToggle")

@onready var reset_episode_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainingGroup/ResetEpisodeButton")

@onready var training_metrics_label := get_node_or_null("Panel/Margin/VBox/ContentRow/MetricsBox/TrainingMetricsLabel")

@onready var bot_metrics_tabs := get_node_or_null("Panel/Margin/VBox/ContentRow/MetricsBox/BotMetricsTabs")

@onready var global_metrics_label := get_node_or_null("Panel/Margin/VBox/ContentRow/MetricsBox/BotMetricsTabs/Geral/GlobalMetrics")

@onready var bot_metrics_labels := {

	1: get_node_or_null("Panel/Margin/VBox/ContentRow/MetricsBox/BotMetricsTabs/P1/BotP1Metrics"),

	2: get_node_or_null("Panel/Margin/VBox/ContentRow/MetricsBox/BotMetricsTabs/P2/BotP2Metrics")

}

@onready var ga_overlay := get_node_or_null("GaOverlay")

@onready var ga_overlay_labels := {

	1: get_node_or_null("GaOverlay/Margin/VBox/BotP1Card/Margin/VBox/BotP1GaLabel"),

	2: get_node_or_null("GaOverlay/Margin/VBox/BotP2Card/Margin/VBox/BotP2GaLabel")

}

@onready var ga_overlay_name_edits := {

	1: get_node_or_null("GaOverlay/Margin/VBox/BotP1Card/Margin/VBox/BotP1GaSaveRow/BotP1GaName"),

	2: get_node_or_null("GaOverlay/Margin/VBox/BotP2Card/Margin/VBox/BotP2GaSaveRow/BotP2GaName")

}

@onready var ga_overlay_save_buttons := {

	1: get_node_or_null("GaOverlay/Margin/VBox/BotP1Card/Margin/VBox/BotP1GaSaveRow/BotP1GaSaveButton"),

	2: get_node_or_null("GaOverlay/Margin/VBox/BotP2Card/Margin/VBox/BotP2GaSaveRow/BotP2GaSaveButton")

}

@onready var logging_toggle := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainingGroup/LoggingToggle")

@onready var log_path_label := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainingGroup/LogPathLabel")

@onready var reward_time_without_kill_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RewardsGroup/RewardStepRow/RewardStepSpin")

@onready var reward_kill_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RewardsGroup/RewardKillRow/RewardKillSpin")

@onready var reward_death_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RewardsGroup/RewardDeathRow/RewardDeathSpin")

@onready var reward_time_alive_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RewardsGroup/RewardAliveRow/RewardAliveSpin")

@onready var rewards_apply_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RewardsGroup/RewardsApplyButton")

@onready var bots_group := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup")

@onready var bot_p1_title := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP1Card/BotP1Title")

@onready var trainer_group := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainerGroup")

@onready var trainer_python_path := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainerGroup/TrainerPythonRow/TrainerPythonPath")

@onready var trainer_script_path := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainerGroup/TrainerScriptRow/TrainerScriptPath")

@onready var trainer_args_line := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainerGroup/TrainerArgsRow/TrainerArgs")

@onready var trainer_start_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainerGroup/TrainerButtonsRow/TrainerStartButton")

@onready var trainer_stop_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainerGroup/TrainerButtonsRow/TrainerStopButton")

@onready var trainer_status_label := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/TrainerGroup/TrainerStatusLabel")

@onready var bot_p1_preset := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP1Card/BotP1PresetRow/BotP1Preset")

@onready var bot_p1_time_without_kill_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP1Card/BotP1StepRow/BotP1StepSpin")

@onready var bot_p1_kill_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP1Card/BotP1KillRow/BotP1KillSpin")

@onready var bot_p1_death_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP1Card/BotP1DeathRow/BotP1DeathSpin")

@onready var bot_p1_time_alive_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP1Card/BotP1AliveRow/BotP1AliveSpin")

@onready var bot_p1_apply_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP1Card/BotP1ApplyButton")

@onready var bot_p2_title := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP2Card/BotP2Title")

@onready var bot_p2_preset := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP2Card/BotP2PresetRow/BotP2Preset")

@onready var bot_p2_time_without_kill_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP2Card/BotP2StepRow/BotP2StepSpin")

@onready var bot_p2_kill_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP2Card/BotP2KillRow/BotP2KillSpin")

@onready var bot_p2_death_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP2Card/BotP2DeathRow/BotP2DeathSpin")

@onready var bot_p2_time_alive_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP2Card/BotP2AliveRow/BotP2AliveSpin")

@onready var bot_p2_apply_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/BotsGroup/BotCards/BotP2Card/BotP2ApplyButton")

@onready var round_limits_title := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RoundGroup/RoundLimitsTitle")

@onready var round_steps_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RoundGroup/RoundStepsRow/RoundStepsSpin")

@onready var round_seconds_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RoundGroup/RoundSecondsRow/RoundSecondsSpin")

@onready var round_kills_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RoundGroup/RoundKillsRow/RoundKillsSpin")

@onready var round_apply_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/RoundGroup/RoundApplyButton")

@onready var ga_generation_toggle := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GaGroup/GaGenerationToggle")

@onready var ga_generations_spin := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GaGroup/GaGenerationsRow/GaGenerationsSpin")

@onready var ga_apply_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GaGroup/GaApplyButton")

@onready var genome_label := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/GenomeLabel")

@onready var load_genome_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/LoadGenomeButton")



@onready var live_train_start_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/LiveTrainButtons/LiveTrainStartButton")

@onready var live_train_stop_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/LiveTrainButtons/LiveTrainStopButton")

@onready var live_train_save_p1_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/LiveTrainButtons/LiveTrainSaveP1Button")

@onready var live_train_save_p2_button := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/LiveTrainButtons/LiveTrainSaveP2Button")

@onready var live_train_status_label := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/LiveTrainStatusLabel")

@onready var live_train_p1_label := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/LiveTrainP1Label")

@onready var live_train_p2_label := get_node_or_null("Panel/Margin/VBox/ContentRow/ControlsBox/GenomeGroup/LiveTrainP2Label")



var dev_enabled := false

var observation_mode := true

var training_enabled := false

var training_watch_mode := false

var training_time_scale := 1.0

var training_port := 0

var training_metrics: Dictionary = {}

var training_logging_enabled := false

var training_log_path := "user://training_metrics.csv"

var genome_path := ""

var genome_status := "Não carregado"

var current_bot: Dictionary = {}

var observation_stats: Dictionary = {}

var live_train_status := "Live: parado"

var round_max_steps := 0

var round_max_seconds := 0.0

var round_max_kills := 5

var reward_time_without_kill := -0.001

var reward_kill := 1.0

var reward_death := -1.0

var reward_time_alive := 0.0

var generation_per_round := true

var max_generations := 0

var bot_rewards := {1: {}, 2: {}}

var bot_card_names := {1: "P1", 2: "P2"}

var bot_points := {1: 0.0, 2: 0.0}

var current_generation := 1

var trainer_python := "python"

var trainer_script := "engine/tools/training_genetic_ga.py"

var trainer_args := ""

var trainer_is_running := false

var trainer_status := "Trainer: parado"



const BOT_PRESET_ORDER := ["custom", "agressivo", "estrategista", "balanceado", "defensivo"]

const BOT_PRESETS := {

	"custom": {"label": "Personalizado", "values": {}},

	"agressivo": {

		"label": "Agressivo",

		"values": {

			"time_without_kill": -0.001,

			"kill": 1.3,

			"death": -0.9,

			"time_alive": 0.003

		}

	},

	"estrategista": {

		"label": "Estrategista",

		"values": {

			"time_without_kill": -0.001,

			"kill": 1.0,

			"death": -1.2,

			"time_alive": 0.004

		}

	},

	"balanceado": {

		"label": "Balanceado",

		"values": {

			"time_without_kill": -0.001,

			"kill": 1.05,

			"death": -1.0,

			"time_alive": 0.003

		}

	},

	"defensivo": {

		"label": "Defensivo",

		"values": {

			"time_without_kill": -0.001,

			"kill": 0.9,

			"death": -1.4,

			"time_alive": 0.005

		}

	}

}



func _ready() -> void:

	visible = false

	if DevDebug:

		DevDebug.entries_changed.connect(_on_entries_changed)

	_update_labels([])

	_update_training_metrics_label()

	_update_bot_metrics_tabs()

	_update_ga_overlay()



func configure(enabled: bool) -> void:

	dev_enabled = enabled

	visible = enabled

	if status_label:

		status_label.text = "Modo Dev %s (Ctrl+R ou Alt+1 recarrega)" % ("ativado" if enabled else "desativado")

	if reload_button:

		reload_button.visible = enabled

		if enabled and not reload_button.pressed.is_connected(_on_reload_pressed):

			reload_button.pressed.connect(_on_reload_pressed)

		elif not enabled and reload_button.pressed.is_connected(_on_reload_pressed):

			reload_button.pressed.disconnect(_on_reload_pressed)

	_configure_training_controls(enabled)

	_configure_trainer_controls(enabled)

	_configure_genome_controls(enabled)

	_configure_ga_overlay_controls(enabled)

	if enabled and DevDebug:

		_update_labels(DevDebug.get_entries())

	_update_training_metrics_label()

	_update_genome_label()

	_update_trainer_controls()

	set_observation_mode(true)

	_update_ga_overlay()

	_configure_live_train_controls(enabled)

	_update_live_train_labels()



func _configure_live_train_controls(enabled: bool) -> void:

	if live_train_start_button:

		live_train_start_button.visible = enabled

		if enabled and not live_train_start_button.pressed.is_connected(_on_live_train_start_pressed):

			live_train_start_button.pressed.connect(_on_live_train_start_pressed)

		elif not enabled and live_train_start_button.pressed.is_connected(_on_live_train_start_pressed):

			live_train_start_button.pressed.disconnect(_on_live_train_start_pressed)

	if live_train_stop_button:

		live_train_stop_button.visible = enabled

		if enabled and not live_train_stop_button.pressed.is_connected(_on_live_train_stop_pressed):

			live_train_stop_button.pressed.connect(_on_live_train_stop_pressed)

		elif not enabled and live_train_stop_button.pressed.is_connected(_on_live_train_stop_pressed):

			live_train_stop_button.pressed.disconnect(_on_live_train_stop_pressed)

	if live_train_save_p1_button:

		live_train_save_p1_button.visible = enabled

		if enabled and not live_train_save_p1_button.pressed.is_connected(_on_live_train_save_pressed.bind(1)):

			live_train_save_p1_button.pressed.connect(_on_live_train_save_pressed.bind(1))

		elif not enabled and live_train_save_p1_button.pressed.is_connected(_on_live_train_save_pressed.bind(1)):

			live_train_save_p1_button.pressed.disconnect(_on_live_train_save_pressed.bind(1))

	if live_train_save_p2_button:

		live_train_save_p2_button.visible = enabled

		if enabled and not live_train_save_p2_button.pressed.is_connected(_on_live_train_save_pressed.bind(2)):

			live_train_save_p2_button.pressed.connect(_on_live_train_save_pressed.bind(2))

		elif not enabled and live_train_save_p2_button.pressed.is_connected(_on_live_train_save_pressed.bind(2)):

			live_train_save_p2_button.pressed.disconnect(_on_live_train_save_pressed.bind(2))



func _on_live_train_start_pressed() -> void:

	emit_signal("live_train_start_requested")



func _on_live_train_stop_pressed() -> void:

	emit_signal("live_train_stop_requested")



func _on_live_train_save_pressed(player_id: int) -> void:

	emit_signal("live_train_save_requested", int(player_id))



func toggle_observation_mode() -> void:

	set_observation_mode(not observation_mode)



func set_observation_mode(enabled: bool) -> void:

	observation_mode = enabled

	if label:

		label.visible = dev_enabled and not observation_mode

	if training_group:

		training_group.visible = dev_enabled

	if training_title:

		training_title.visible = dev_enabled and not observation_mode

	if training_toggle:

		training_toggle.visible = dev_enabled and not observation_mode

	if watch_toggle:

		watch_toggle.visible = dev_enabled and not observation_mode

	if logging_toggle:

		logging_toggle.visible = dev_enabled and not observation_mode

	if log_path_label:

		log_path_label.visible = dev_enabled and not observation_mode

	if trainer_group:

		trainer_group.visible = dev_enabled and not observation_mode

	if rewards_group:

		rewards_group.visible = dev_enabled and not observation_mode

	if bots_group:

		bots_group.visible = dev_enabled and not observation_mode

	if round_group:

		round_group.visible = dev_enabled and not observation_mode

	if ga_group:

		ga_group.visible = dev_enabled and not observation_mode

	if genome_group:

		genome_group.visible = dev_enabled

	if metrics_box:

		metrics_box.visible = dev_enabled and not observation_mode

	_update_ga_overlay()



func _configure_ga_overlay_controls(enabled: bool) -> void:

	for player_id in [1, 2]:

		var button = ga_overlay_save_buttons.get(player_id)

		if button == null:

			continue

		if enabled and not button.pressed.is_connected(_on_ga_overlay_save_pressed.bind(player_id)):

			button.pressed.connect(_on_ga_overlay_save_pressed.bind(player_id))

		elif not enabled and button.pressed.is_connected(_on_ga_overlay_save_pressed.bind(player_id)):

			button.pressed.disconnect(_on_ga_overlay_save_pressed.bind(player_id))



func _on_ga_overlay_save_pressed(player_id: int) -> void:

	var name_edit = ga_overlay_name_edits.get(player_id)

	var name_value := ""

	if name_edit != null:

		name_value = String(name_edit.text).strip_edges()

	if name_value == "":

		var ga_state: Dictionary = {}

		if training_metrics.has("ga_state") and training_metrics["ga_state"] is Dictionary:

			ga_state = training_metrics["ga_state"] as Dictionary

		var state: Dictionary = {}

		if ga_state.has(player_id) and ga_state[player_id] is Dictionary:

			state = ga_state[player_id] as Dictionary

		else:

			var key := str(player_id)

			if ga_state.has(key) and ga_state[key] is Dictionary:

				state = ga_state[key] as Dictionary

		var gen := int(state.get("generation", 0))

		var ind := int(state.get("individual", 0))

		name_value = "P%d_gen%d_ind%d" % [player_id, gen, ind]

	if DevDebug:

		DevDebug.log_event("ga", "Salvar modelo P%d: %s" % [player_id, name_value])

	emit_signal("ga_model_save_requested", player_id, name_value)



func configure_training(enabled: bool, watch_mode: bool, time_scale: float, port: int) -> void:

	training_enabled = enabled

	training_watch_mode = watch_mode

	training_time_scale = time_scale

	training_port = port

	if training_toggle:

		training_toggle.button_pressed = enabled

	if watch_toggle:

		watch_toggle.button_pressed = watch_mode

	_update_training_controls_state()

	_update_training_metrics_label()

	_update_log_path_label()

	_update_genome_label()

	_update_trainer_controls()

	_update_round_limits_controls()

	_update_rewards_controls()

	_update_ga_overlay()



func _configure_trainer_controls(enabled: bool) -> void:

	if trainer_group:

		trainer_group.visible = enabled

	if trainer_start_button:

		trainer_start_button.visible = enabled

		if enabled and not trainer_start_button.pressed.is_connected(_on_trainer_start_pressed):

			trainer_start_button.pressed.connect(_on_trainer_start_pressed)

		elif not enabled and trainer_start_button.pressed.is_connected(_on_trainer_start_pressed):

			trainer_start_button.pressed.disconnect(_on_trainer_start_pressed)

	if trainer_stop_button:

		trainer_stop_button.visible = enabled

		if enabled and not trainer_stop_button.pressed.is_connected(_on_trainer_stop_pressed):

			trainer_stop_button.pressed.connect(_on_trainer_stop_pressed)

		elif not enabled and trainer_stop_button.pressed.is_connected(_on_trainer_stop_pressed):

			trainer_stop_button.pressed.disconnect(_on_trainer_stop_pressed)

	_update_trainer_controls()

	_update_bot_controls()

	_update_ga_controls()



func _configure_ga_controls(enabled: bool) -> void:

	if ga_generation_toggle:

		ga_generation_toggle.visible = enabled

	if ga_generations_spin:

		ga_generations_spin.visible = enabled

	if ga_apply_button:

		ga_apply_button.visible = enabled

		if enabled and not ga_apply_button.pressed.is_connected(_on_ga_apply_pressed):

			ga_apply_button.pressed.connect(_on_ga_apply_pressed)

		elif not enabled and ga_apply_button.pressed.is_connected(_on_ga_apply_pressed):

			ga_apply_button.pressed.disconnect(_on_ga_apply_pressed)

	_update_ga_controls()



func configure_round_limits(max_steps: int, max_seconds: float, max_kills: int) -> void:

	round_max_steps = max(max_steps, 0)

	round_max_seconds = max(max_seconds, 0.0)

	round_max_kills = max(max_kills, 0)

	_update_round_limits_controls()



func configure_rewards(time_without_kill: float, kill_reward: float, death_reward: float, time_alive: float) -> void:

	reward_time_without_kill = time_without_kill

	reward_kill = kill_reward

	reward_death = death_reward

	reward_time_alive = time_alive

	_update_rewards_controls()



func configure_ga_config(generation_round: bool, generations: int) -> void:

	generation_per_round = generation_round

	max_generations = max(generations, 0)

	_update_ga_controls()



func configure_genome(path: String, status: String = "") -> void:

	genome_path = path

	if status != "":

		genome_status = status

	_update_genome_label()



func update_current_bot(meta: Dictionary) -> void:

	current_bot = meta.duplicate(true)

	_update_genome_label()



func update_observation_stats(stats: Dictionary) -> void:

	observation_stats = stats.duplicate(true)

	_update_genome_label()



func configure_trainer(python_path: String, script_path: String, extra_args: String, is_running: bool, status_text: String) -> void:

	trainer_python = python_path

	trainer_script = script_path

	trainer_args = extra_args

	trainer_is_running = is_running

	trainer_status = status_text

	_update_trainer_controls()



func update_training_metrics(metrics: Dictionary) -> void:

	training_metrics = metrics.duplicate(true)

	if metrics.has("bot_points") and metrics["bot_points"] is Dictionary:

		bot_points = (metrics["bot_points"] as Dictionary).duplicate(true)

	if metrics.has("generation"):

		current_generation = int(metrics.get("generation", current_generation))

	if metrics.has("logging_enabled"):

		training_logging_enabled = bool(metrics.get("logging_enabled", false))

	if metrics.has("log_path"):

		training_log_path = String(metrics.get("log_path", training_log_path))

	if metrics.has("reward_time_without_kill"):

		reward_time_without_kill = float(metrics.get("reward_time_without_kill", reward_time_without_kill))

	if metrics.has("reward_kill"):

		reward_kill = float(metrics.get("reward_kill", reward_kill))

	if metrics.has("reward_death"):

		reward_death = float(metrics.get("reward_death", reward_death))

	if metrics.has("reward_time_alive"):

		reward_time_alive = float(metrics.get("reward_time_alive", reward_time_alive))

	if metrics.has("round_max_steps"):

		round_max_steps = int(metrics.get("round_max_steps", round_max_steps))

	if metrics.has("round_max_seconds"):

		round_max_seconds = float(metrics.get("round_max_seconds", round_max_seconds))

	if metrics.has("round_max_kills"):

		round_max_kills = int(metrics.get("round_max_kills", round_max_kills))

	if metrics.has("bot_rewards") and metrics["bot_rewards"] is Dictionary:

		bot_rewards = (metrics["bot_rewards"] as Dictionary).duplicate(true)

	if metrics.has("bot_names") and metrics["bot_names"] is Dictionary:

		bot_card_names = (metrics["bot_names"] as Dictionary).duplicate(true)

	if logging_toggle:

		logging_toggle.button_pressed = training_logging_enabled

	_update_training_metrics_label()

	_update_log_path_label()

	_update_rewards_controls()

	_update_bot_controls()

	_update_ga_controls()

	_update_round_limits_controls()

	_update_ga_overlay()

	_update_live_train_labels()



func set_live_train_status(text: String) -> void:

	live_train_status = text

	if live_train_status_label:

		live_train_status_label.text = text



func _update_live_train_labels() -> void:

	if live_train_status_label:

		live_train_status_label.text = live_train_status

	var ga_state: Dictionary = {}

	if training_metrics.has("ga_state") and training_metrics["ga_state"] is Dictionary:

		ga_state = training_metrics["ga_state"] as Dictionary

	var p1: Dictionary = {}

	if ga_state.has(1) and ga_state[1] is Dictionary:

		p1 = ga_state[1] as Dictionary

	elif ga_state.has("1") and ga_state["1"] is Dictionary:

		p1 = ga_state["1"] as Dictionary

	var p2: Dictionary = {}

	if ga_state.has(2) and ga_state[2] is Dictionary:

		p2 = ga_state[2] as Dictionary

	elif ga_state.has("2") and ga_state["2"] is Dictionary:

		p2 = ga_state["2"] as Dictionary

	if live_train_p1_label:

		var gen := int(p1.get("generation", 0))

		var ind := int(p1.get("individual", 0))

		var epi := int(p1.get("episode_in_individual", 0))

		var epi_max := int(p1.get("episodes_per_genome", 0))

		if epi_max <= 0:

			live_train_p1_label.text = "P1: gen %d | ind %d" % [gen, ind]

		else:

			live_train_p1_label.text = "P1: gen %d | ind %d | treinos %d/%d" % [gen, ind, epi, epi_max]

	if live_train_p2_label:

		var mode := String(p2.get("mode", ""))

		if mode == "":

			mode = "?"

		var gen2 := int(p2.get("generation", 0))

		var ind2 := int(p2.get("individual", 0))

		var epi2 := int(p2.get("episode_in_individual", 0))

		var epi2_max := int(p2.get("episodes_per_genome", 0))

		var steps2 := int(p2.get("mutation_steps", 0))

		var parts: Array[String] = []

		parts.append("%s" % mode)

		parts.append("gen %d" % gen2)

		if ind2 > 0:

			parts.append("ind %d" % ind2)

		if epi2_max > 0:

			parts.append("treinos %d/%d" % [epi2, epi2_max])

		parts.append("mut %d" % steps2)

		live_train_p2_label.text = "P2: %s" % " | ".join(parts)



func _update_ga_overlay() -> void:

	if ga_overlay == null:

		return

	ga_overlay.visible = dev_enabled and not observation_mode

	if not ga_overlay.visible:

		return



	var connected := bool(training_metrics.get("connected", false))

	var bot_names: Dictionary = {}

	if training_metrics.has("bot_names") and training_metrics["bot_names"] is Dictionary:

		bot_names = training_metrics["bot_names"] as Dictionary



	if not training_enabled:

		for player_id in [1, 2]:

			var label_node = ga_overlay_labels.get(player_id)

			if label_node == null:

				continue

			var header := "[b]%s (P%d)[/b]" % [String(bot_names.get(player_id, "P%d" % player_id)), player_id]

			label_node.text = "%s\nTreino: inativo" % header

		return



	if not connected:

		for player_id in [1, 2]:

			var label_node = ga_overlay_labels.get(player_id)

			if label_node == null:

				continue

			var header := "[b]%s (P%d)[/b]" % [String(bot_names.get(player_id, "P%d" % player_id)), player_id]

			label_node.text = "%s\nConexão: aguardando" % header

		return



	var ga_state: Dictionary = {}

	if training_metrics.has("ga_state") and training_metrics["ga_state"] is Dictionary:

		ga_state = training_metrics["ga_state"] as Dictionary



	for player_id in [1, 2]:

		var label_node = ga_overlay_labels.get(player_id)

		if label_node == null:

			continue

		var header := "[b]%s (P%d)[/b]" % [String(bot_names.get(player_id, "P%d" % player_id)), player_id]



		var state: Dictionary = {}

		if ga_state.has(player_id) and ga_state[player_id] is Dictionary:

			state = ga_state[player_id] as Dictionary

		else:

			var key := str(player_id)

			if ga_state.has(key) and ga_state[key] is Dictionary:

				state = ga_state[key] as Dictionary



		if state.is_empty():

			label_node.text = "%s\nGA: aguardando dados" % header

			continue



		var mode := String(state.get("mode", ""))

		var generation := int(state.get("generation", 0))

		var individual := int(state.get("individual", 0))

		var population := int(state.get("population", 0))

		var mutation_steps := int(state.get("mutation_steps", 0))

		var mutation_rate := float(state.get("mutation_rate", 0.0))

		var mutation_std := float(state.get("mutation_std", 0.0))



		var lines: Array[String] = []

		if mode != "":

			lines.append("Modo: %s" % mode)

		lines.append("Geração: %d" % generation)

		if population > 0:

			lines.append("Indivíduo atual: %d/%d" % [individual, population])

		else:

			lines.append("Indivíduo atual: %d" % individual)

		lines.append("Mutações: %d" % mutation_steps)

		if mutation_rate != 0.0 or mutation_std != 0.0:

			lines.append("Aleatoriedade: taxa %0.3f | std %0.3f" % [mutation_rate, mutation_std])

		else:

			lines.append("Aleatoriedade: -")



		label_node.text = "%s\n%s" % [header, "\n".join(lines)]



func _on_entries_changed(entries: Array) -> void:

	if not dev_enabled:

		return

	_update_labels(entries)



func _update_labels(entries: Array) -> void:

	if label == null:

		return

	if entries.is_empty():

		label.text = "Sem eventos registrados."

		return

	var lines: Array[String] = []

	for entry in entries:

		var type := str(entry.get("type", "?"))

		var text := str(entry.get("text", ""))

		lines.append("[%s] %s" % [type, text])

	label.text = "\n".join(lines)



func _configure_training_controls(enabled: bool) -> void:

	if training_toggle:

		training_toggle.visible = enabled

		if enabled and not training_toggle.toggled.is_connected(_on_training_toggle):

			training_toggle.toggled.connect(_on_training_toggle)

		elif not enabled and training_toggle.toggled.is_connected(_on_training_toggle):

			training_toggle.toggled.disconnect(_on_training_toggle)

	if watch_toggle:

		watch_toggle.visible = enabled

		if enabled and not watch_toggle.toggled.is_connected(_on_watch_toggle):

			watch_toggle.toggled.connect(_on_watch_toggle)

		elif not enabled and watch_toggle.toggled.is_connected(_on_watch_toggle):

			watch_toggle.toggled.disconnect(_on_watch_toggle)

	if reset_episode_button:

		reset_episode_button.visible = enabled

		if enabled and not reset_episode_button.pressed.is_connected(_on_reset_episode_pressed):

			reset_episode_button.pressed.connect(_on_reset_episode_pressed)

		elif not enabled and reset_episode_button.pressed.is_connected(_on_reset_episode_pressed):

			reset_episode_button.pressed.disconnect(_on_reset_episode_pressed)

	if logging_toggle:

		logging_toggle.visible = enabled

		if enabled and not logging_toggle.toggled.is_connected(_on_logging_toggle):

			logging_toggle.toggled.connect(_on_logging_toggle)

		elif not enabled and logging_toggle.toggled.is_connected(_on_logging_toggle):

			logging_toggle.toggled.disconnect(_on_logging_toggle)

	_configure_rewards_controls(enabled)

	_configure_bot_controls(enabled)

	_configure_trainer_controls(enabled)

	_configure_round_controls(enabled)

	_configure_ga_controls(enabled)

	_update_training_controls_state()

	_update_bot_controls()

	_configure_genome_controls(enabled)



func _configure_rewards_controls(enabled: bool) -> void:

	if reward_time_without_kill_spin:

		reward_time_without_kill_spin.visible = enabled

	if reward_kill_spin:

		reward_kill_spin.visible = enabled

	if reward_death_spin:

		reward_death_spin.visible = enabled

	if reward_time_alive_spin:

		reward_time_alive_spin.visible = enabled

	if rewards_apply_button:

		rewards_apply_button.visible = enabled

		if enabled and not rewards_apply_button.pressed.is_connected(_on_rewards_apply_pressed):

			rewards_apply_button.pressed.connect(_on_rewards_apply_pressed)

		elif not enabled and rewards_apply_button.pressed.is_connected(_on_rewards_apply_pressed):

			rewards_apply_button.pressed.disconnect(_on_rewards_apply_pressed)

	_update_rewards_controls()



func _configure_bot_controls(enabled: bool) -> void:

	if bots_group:

		bots_group.visible = enabled

	if bot_p1_preset:

		bot_p1_preset.visible = enabled

		_ensure_bot_preset_options(bot_p1_preset)

		if enabled and not bot_p1_preset.item_selected.is_connected(_on_bot_p1_preset_selected):

			bot_p1_preset.item_selected.connect(_on_bot_p1_preset_selected)

		elif not enabled and bot_p1_preset.item_selected.is_connected(_on_bot_p1_preset_selected):

			bot_p1_preset.item_selected.disconnect(_on_bot_p1_preset_selected)

	if bot_p2_preset:

		bot_p2_preset.visible = enabled

		_ensure_bot_preset_options(bot_p2_preset)

		if enabled and not bot_p2_preset.item_selected.is_connected(_on_bot_p2_preset_selected):

			bot_p2_preset.item_selected.connect(_on_bot_p2_preset_selected)

		elif not enabled and bot_p2_preset.item_selected.is_connected(_on_bot_p2_preset_selected):

			bot_p2_preset.item_selected.disconnect(_on_bot_p2_preset_selected)

	if bot_p1_apply_button:

		bot_p1_apply_button.visible = enabled

		if enabled and not bot_p1_apply_button.pressed.is_connected(_on_bot_p1_apply_pressed):

			bot_p1_apply_button.pressed.connect(_on_bot_p1_apply_pressed)

		elif not enabled and bot_p1_apply_button.pressed.is_connected(_on_bot_p1_apply_pressed):

			bot_p1_apply_button.pressed.disconnect(_on_bot_p1_apply_pressed)

	if bot_p2_apply_button:

		bot_p2_apply_button.visible = enabled

		if enabled and not bot_p2_apply_button.pressed.is_connected(_on_bot_p2_apply_pressed):

			bot_p2_apply_button.pressed.connect(_on_bot_p2_apply_pressed)

		elif not enabled and bot_p2_apply_button.pressed.is_connected(_on_bot_p2_apply_pressed):

			bot_p2_apply_button.pressed.disconnect(_on_bot_p2_apply_pressed)



func _configure_round_controls(enabled: bool) -> void:

	if round_limits_title:

		round_limits_title.visible = enabled

	if round_steps_spin:

		round_steps_spin.visible = enabled

	if round_seconds_spin:

		round_seconds_spin.visible = enabled

	if round_kills_spin:

		round_kills_spin.visible = enabled

	if round_apply_button:

		round_apply_button.visible = enabled

		if enabled and not round_apply_button.pressed.is_connected(_on_round_apply_pressed):

			round_apply_button.pressed.connect(_on_round_apply_pressed)

		elif not enabled and round_apply_button.pressed.is_connected(_on_round_apply_pressed):

			round_apply_button.pressed.disconnect(_on_round_apply_pressed)

	_update_round_limits_controls()



func _configure_genome_controls(enabled: bool) -> void:

	if genome_label:

		genome_label.visible = enabled

	if load_genome_button:

		load_genome_button.visible = enabled

		if enabled and not load_genome_button.pressed.is_connected(_on_load_genome_pressed):

			load_genome_button.pressed.connect(_on_load_genome_pressed)

		elif not enabled and load_genome_button.pressed.is_connected(_on_load_genome_pressed):

			load_genome_button.pressed.disconnect(_on_load_genome_pressed)



func _update_training_controls_state() -> void:

	if training_title:

		training_title.visible = dev_enabled

	var disabled := not training_enabled

	if watch_toggle:

		watch_toggle.disabled = disabled

	if reset_episode_button:

		reset_episode_button.disabled = disabled

	if logging_toggle:

		logging_toggle.disabled = disabled



func _update_log_path_label() -> void:

	if log_path_label == null:

		return

	var status := "ON" if training_logging_enabled else "OFF"

	log_path_label.text = "CSV %s: %s" % [status, training_log_path]



func _update_genome_label() -> void:

	if genome_label == null:

		return

	var status_text := "" if genome_status == "" else " (%s)" % genome_status

	var lines: Array[String] = []

	lines.append("Genoma: %s%s" % [genome_path, status_text])

	if not current_bot.is_empty():

		var r := int(current_bot.get("round", 0))

		var gen := int(current_bot.get("generation", -1))

		var worker_id := int(current_bot.get("worker_id", -1))

		var best := float(current_bot.get("best", 0.0))

		var parts: Array[String] = []

		parts.append("round %d" % r)

		if gen >= 0:

			parts.append("gen %d" % gen)

		if worker_id >= 0:

			parts.append("worker %d" % worker_id)

		parts.append("best %.3f" % best)

		lines.append("Treino: %s" % " | ".join(parts))

	if not observation_stats.is_empty():

		var fps := float(observation_stats.get("fps", 0.0))

		var round_index := int(observation_stats.get("round_index", 0))

		var wins_dict: Dictionary = observation_stats.get("wins", {}) if observation_stats.get("wins", {}) is Dictionary else {}

		lines.append("Jogo: round %d | FPS %.0f | placar %d x %d" % [round_index, fps, int(wins_dict.get(1, 0)), int(wins_dict.get(2, 0))])

		if fps > 0.0 and fps < 55.0:

			lines.append("Dica: se o treino (islands) estiver rodando junto, reduza concurrency pra evitar lag")

		var p1: Dictionary = observation_stats.get("p1", {}) if observation_stats.get("p1", {}) is Dictionary else {}

		var p2: Dictionary = observation_stats.get("p2", {}) if observation_stats.get("p2", {}) is Dictionary else {}

		lines.append(_format_bot_row("P1", p1))

		lines.append(_format_bot_row("P2", p2))

	genome_label.text = "\n".join(lines)



func _format_bot_row(label_name: String, bot: Dictionary) -> String:

	var policy := String(bot.get("policy", ""))

	var arrows := int(bot.get("arrows", 0))

	var action: Dictionary = bot.get("action", {}) if bot.get("action", {}) is Dictionary else {}

	var axis := float(action.get("axis", 0.0))

	var rule := String(action.get("debug_rule", ""))

	var dist := float(action.get("debug_distance", -1.0))

	var shoot := bool(action.get("shoot_is_pressed", false))

	var melee := bool(action.get("melee_pressed", false))

	var jump := bool(action.get("jump_pressed", false))

	var dash = action.get("dash_pressed", [])

	var dash_any := false

	if dash is Array:

		dash_any = (dash as Array).size() > 0

	var ema: Dictionary = bot.get("ema", {}) if bot.get("ema", {}) is Dictionary else {}

	var shoot_r := float(ema.get("shoot", 0.0))

	var melee_r := float(ema.get("melee", 0.0))

	var jump_r := float(ema.get("jump", 0.0))

	var dash_r := float(ema.get("dash", 0.0))

	var extra := ""

	if rule != "":

		extra = " rule=%s" % rule

		if dist >= 0.0:

			extra += " d=%.0f" % dist

	return "%s [%s] arrows=%d axis=%.0f%s shoot=%s melee=%s jump=%s dash=%s | rates s%.0f m%.0f j%.0f d%.0f" % [

		label_name,

		policy,

		arrows,

		axis,

		extra,

		"1" if shoot else "0",

		"1" if melee else "0",

		"1" if jump else "0",

		"1" if dash_any else "0",

		shoot_r * 100.0,

		melee_r * 100.0,

		jump_r * 100.0,

		dash_r * 100.0

	]



func _update_round_limits_controls() -> void:

	if round_steps_spin:

		if not round_steps_spin.has_focus():

			round_steps_spin.value = round_max_steps

	if round_seconds_spin:

		if not round_seconds_spin.has_focus():

			round_seconds_spin.value = round_max_seconds

	if round_kills_spin:

		if not round_kills_spin.has_focus():

			round_kills_spin.value = round_max_kills



func _update_rewards_controls() -> void:

	if reward_time_without_kill_spin:

		if not reward_time_without_kill_spin.has_focus():

			reward_time_without_kill_spin.value = reward_time_without_kill

	if reward_kill_spin:

		if not reward_kill_spin.has_focus():

			reward_kill_spin.value = reward_kill

	if reward_death_spin:

		if not reward_death_spin.has_focus():

			reward_death_spin.value = reward_death

	if reward_time_alive_spin:

		if not reward_time_alive_spin.has_focus():

			reward_time_alive_spin.value = reward_time_alive



func _update_bot_controls() -> void:

	if bot_p1_title:

		bot_p1_title.text = "%s (P1)" % String(bot_card_names.get(1, "P1"))

	if bot_p2_title:

		bot_p2_title.text = "%s (P2)" % String(bot_card_names.get(2, "P2"))

	if bot_p1_time_without_kill_spin:

		if not bot_p1_time_without_kill_spin.has_focus():

			bot_p1_time_without_kill_spin.value = _get_bot_reward_value(1, "time_without_kill", float(bot_p1_time_without_kill_spin.value), "step")

	if bot_p1_kill_spin:

		if not bot_p1_kill_spin.has_focus():

			bot_p1_kill_spin.value = _get_bot_reward_value(1, "kill", float(bot_p1_kill_spin.value))

	if bot_p1_death_spin:

		if not bot_p1_death_spin.has_focus():

			bot_p1_death_spin.value = _get_bot_reward_value(1, "death", float(bot_p1_death_spin.value))

	if bot_p1_time_alive_spin:

		if not bot_p1_time_alive_spin.has_focus():

			bot_p1_time_alive_spin.value = _get_bot_reward_value(1, "time_alive", float(bot_p1_time_alive_spin.value), "alive")

	if bot_p2_time_without_kill_spin:

		if not bot_p2_time_without_kill_spin.has_focus():

			bot_p2_time_without_kill_spin.value = _get_bot_reward_value(2, "time_without_kill", float(bot_p2_time_without_kill_spin.value), "step")

	if bot_p2_kill_spin:

		if not bot_p2_kill_spin.has_focus():

			bot_p2_kill_spin.value = _get_bot_reward_value(2, "kill", float(bot_p2_kill_spin.value))

	if bot_p2_death_spin:

		if not bot_p2_death_spin.has_focus():

			bot_p2_death_spin.value = _get_bot_reward_value(2, "death", float(bot_p2_death_spin.value))

	if bot_p2_time_alive_spin:

		if not bot_p2_time_alive_spin.has_focus():

			bot_p2_time_alive_spin.value = _get_bot_reward_value(2, "time_alive", float(bot_p2_time_alive_spin.value), "alive")



func _get_bot_reward_value(player_id: int, key: String, fallback: float, legacy_key: String = "") -> float:

	var config: Dictionary = bot_rewards.get(player_id, {}) if bot_rewards.has(player_id) else {}

	if config.has(key):

		return float(config[key])

	if legacy_key != "" and config.has(legacy_key):

		return float(config[legacy_key])

	return fallback



func _update_trainer_controls() -> void:

	if not dev_enabled:

		return

	if trainer_python_path and trainer_python_path.text != trainer_python:

		trainer_python_path.text = trainer_python

	elif trainer_python_path and trainer_python_path.text == "" and trainer_python != "":

		trainer_python_path.text = trainer_python

	if trainer_script_path and trainer_script_path.text != trainer_script:

		trainer_script_path.text = trainer_script

	if trainer_args_line and trainer_args_line.text != trainer_args:

		trainer_args_line.text = trainer_args

	if trainer_start_button:

		trainer_start_button.disabled = trainer_is_running

	if trainer_stop_button:

		trainer_stop_button.disabled = not trainer_is_running

	if trainer_status_label:

		trainer_status_label.text = trainer_status



func _ensure_bot_preset_options(button: OptionButton) -> void:

	if button == null:

		return

	if button.item_count > 0:

		return

	for preset_key in BOT_PRESET_ORDER:

		var preset: Dictionary = BOT_PRESETS.get(preset_key, {})

		button.add_item(String(preset.get("label", preset_key)))

	button.select(0)



func _on_bot_p1_preset_selected(index: int) -> void:

	_apply_bot_preset(1, _get_preset_key(index))



func _on_bot_p2_preset_selected(index: int) -> void:

	_apply_bot_preset(2, _get_preset_key(index))



func _get_preset_key(index: int) -> String:

	if index < 0 or index >= BOT_PRESET_ORDER.size():

		return "custom"

	return BOT_PRESET_ORDER[index]



func _apply_bot_preset(player_id: int, preset_key: String) -> void:

	var preset: Dictionary = BOT_PRESETS.get(preset_key, {})

	if preset.is_empty() or not preset.has("values"):

		return

	var values: Dictionary = preset["values"]

	if values.is_empty():

		return

	_set_bot_spin_values(player_id, values)



func _set_bot_spin_values(player_id: int, values: Dictionary) -> void:

	if player_id == 1:

		if bot_p1_time_without_kill_spin and values.has("time_without_kill"):

			bot_p1_time_without_kill_spin.value = float(values["time_without_kill"])

		if bot_p1_kill_spin and values.has("kill"):

			bot_p1_kill_spin.value = float(values["kill"])

		if bot_p1_death_spin and values.has("death"):

			bot_p1_death_spin.value = float(values["death"])

		if bot_p1_time_alive_spin and values.has("time_alive"):

			bot_p1_time_alive_spin.value = float(values["time_alive"])

		return

	if bot_p2_time_without_kill_spin and values.has("time_without_kill"):

		bot_p2_time_without_kill_spin.value = float(values["time_without_kill"])

	if bot_p2_kill_spin and values.has("kill"):

		bot_p2_kill_spin.value = float(values["kill"])

	if bot_p2_death_spin and values.has("death"):

		bot_p2_death_spin.value = float(values["death"])

	if bot_p2_time_alive_spin and values.has("time_alive"):

		bot_p2_time_alive_spin.value = float(values["time_alive"])



func _update_ga_controls() -> void:

	if ga_generation_toggle:

		ga_generation_toggle.button_pressed = generation_per_round

	if ga_generations_spin:

		ga_generations_spin.value = max_generations



func _update_training_metrics_label() -> void:

	if training_metrics_label == null:

		return

	if not training_enabled:

		training_metrics_label.text = "Treino: inativo"

		return

	var connected := bool(training_metrics.get("connected", false))

	var episode := int(training_metrics.get("episode", 0))

	var episode_steps := int(training_metrics.get("episode_steps", 0))

	var last_episode_steps := int(training_metrics.get("last_episode_steps", 0))

	var total_steps := int(training_metrics.get("total_steps", 0))

	var match_score: Dictionary = {}

	if training_metrics.has("match_score") and training_metrics["match_score"] is Dictionary:

		match_score = training_metrics["match_score"]

	var last_match_score: Dictionary = {}

	if training_metrics.has("last_match_score") and training_metrics["last_match_score"] is Dictionary:

		last_match_score = training_metrics["last_match_score"]

	var wins: Dictionary = {}

	if training_metrics.has("wins") and training_metrics["wins"] is Dictionary:

		wins = training_metrics["wins"]

	var bot_names: Dictionary = {}

	if training_metrics.has("bot_names") and training_metrics["bot_names"] is Dictionary:

		bot_names = training_metrics["bot_names"]

	var name_p1 := String(bot_names.get(1, "P1"))

	var name_p2 := String(bot_names.get(2, "P2"))

	var last_winner := int(training_metrics.get("last_winner", 0))

	var winner_text := "Empate"

	if last_winner == 1:

		winner_text = name_p1

	elif last_winner == 2:

		winner_text = name_p2

	var round_steps := int(training_metrics.get("round_steps", 0))

	var round_elapsed := float(training_metrics.get("round_elapsed", 0.0))

	var round_max_steps_metric := int(training_metrics.get("round_max_steps", 0))

	var round_max_seconds_metric := float(training_metrics.get("round_max_seconds", 0.0))

	var round_kills: Dictionary = {}

	if training_metrics.has("round_kills") and training_metrics["round_kills"] is Dictionary:

		round_kills = training_metrics["round_kills"]

	var kills_p1 := int(round_kills.get(1, 0))

	var kills_p2 := int(round_kills.get(2, 0))

	var last_round: Dictionary = {}

	if training_metrics.has("last_round") and training_metrics["last_round"] is Dictionary:

		last_round = training_metrics["last_round"]

	var last_round_line := "Última rodada: -"

	if not last_round.is_empty():

		var winner_id := int(last_round.get("winner", 0))

		var winner_name := "Empate"

		if winner_id == 1:

			winner_name = name_p1

		elif winner_id == 2:

			winner_name = name_p2

		var last_kills: Dictionary = {}

		if last_round.has("kills") and last_round["kills"] is Dictionary:

			last_kills = last_round["kills"]

		last_round_line = "Última rodada: vencedor %s | K %d/%d" % [

			winner_name,

			int(last_kills.get(1, 0)),

			int(last_kills.get(2, 0))

		]

	var alive_line := ""

	if not last_round.is_empty() and last_round.has("alive_time") and last_round["alive_time"] is Dictionary:

		var alive_dict: Dictionary = last_round["alive_time"] as Dictionary

		alive_line = "Vivo: %s %0.1fs | %s %0.1fs" % [

			name_p1,

			float(alive_dict.get(1, 0.0)),

			name_p2,

			float(alive_dict.get(2, 0.0))

		]

	var evolution: Dictionary = {}

	if training_metrics.has("evolution") and training_metrics["evolution"] is Dictionary:

		evolution = training_metrics["evolution"] as Dictionary

	var evolution_line := ""

	var evolution_detail := ""

	if not evolution.is_empty():

		var rounds := int(evolution.get("rounds", 0))

		var winrate: Dictionary = evolution.get("winrate", {}) if evolution.has("winrate") else {}

		var avg_kills: Dictionary = evolution.get("avg_kills", {}) if evolution.has("avg_kills") else {}

		var avg_alive: Dictionary = evolution.get("avg_alive", {}) if evolution.has("avg_alive") else {}

		var avg_score: Dictionary = evolution.get("avg_score", {}) if evolution.has("avg_score") else {}

		evolution_line = "Evolução (%d): win %s %0.0f%% | %s %0.0f%%" % [

			rounds,

			name_p1,

			float(winrate.get(1, 0.0)) * 100.0,

			name_p2,

			float(winrate.get(2, 0.0)) * 100.0

		]

		evolution_detail = "Médias: K %0.1f/%0.1f | Alive %0.1f/%0.1f | Score %0.2f/%0.2f" % [

			float(avg_kills.get(1, 0.0)),

			float(avg_kills.get(2, 0.0)),

			float(avg_alive.get(1, 0.0)),

			float(avg_alive.get(2, 0.0)),

			float(avg_score.get(1, 0.0)),

			float(avg_score.get(2, 0.0))

		]

	var steps_text := str(round_steps)

	if round_max_steps_metric > 0:

		steps_text = "%d/%d" % [round_steps, round_max_steps_metric]

	var time_text := "%0.1f" % round_elapsed

	if round_max_seconds_metric > 0.0:

		time_text = "%0.1f/%0.1f" % [round_elapsed, round_max_seconds_metric]

	var round_kills_target := int(training_metrics.get("round_max_kills", round_max_kills))

	var speed_value := float(training_metrics.get("time_scale", training_time_scale))

	var metrics_lines: Array[String] = [

		"Treino: %s (porta %d)" % ["ON" if training_enabled else "OFF", training_port],

		"Conectado: %s | Watch: %s | Speed: %0.2fx" % ["sim" if connected else "não", "sim" if training_watch_mode else "não", speed_value],

		"Logging: %s" % ["ON" if training_logging_enabled else "OFF"],

		"Bots: P1 %s | P2 %s" % [name_p1, name_p2],

		"Rodada: steps %s | tempo %s | kills %d/%d (max %d)" % [steps_text, time_text, kills_p1, kills_p2, round_kills_target],

		"Episódio: %d | Steps: %d | Último: %d" % [episode, episode_steps, last_episode_steps],

		"Score atual: P1 %0.3f | P2 %0.3f" % [float(match_score.get(1, 0.0)), float(match_score.get(2, 0.0))],

		"Último match: P1 %0.3f | P2 %0.3f" % [float(last_match_score.get(1, 0.0)), float(last_match_score.get(2, 0.0))],

		"Wins: %s %d | %s %d | Último: %s" % [name_p1, int(wins.get(1, 0)), name_p2, int(wins.get(2, 0)), winner_text],

		last_round_line,

		alive_line

	]

	if evolution_line != "":

		metrics_lines.append(evolution_line)

	if evolution_detail != "":

		metrics_lines.append(evolution_detail)

	metrics_lines.append("Total steps: %d" % total_steps)

	training_metrics_label.text = "\n".join(metrics_lines)



func _update_bot_metrics_tabs() -> void:

	if bot_metrics_tabs == null:

		return

	bot_metrics_tabs.visible = dev_enabled

	if global_metrics_label:

		if not training_enabled:

			global_metrics_label.text = "[b]Geral[/b]\nTreino: inativo"

		else:

			var evolution: Dictionary = {}

			if training_metrics.has("evolution") and training_metrics["evolution"] is Dictionary:

				evolution = training_metrics["evolution"] as Dictionary

			var rounds := int(evolution.get("rounds", 0))

			var winrate: Dictionary = evolution.get("winrate", {}) if evolution.has("winrate") else {}

			var avg_kills: Dictionary = evolution.get("avg_kills", {}) if evolution.has("avg_kills") else {}

			var avg_alive: Dictionary = evolution.get("avg_alive", {}) if evolution.has("avg_alive") else {}

			var avg_score: Dictionary = evolution.get("avg_score", {}) if evolution.has("avg_score") else {}

			var last_match_score_tab: Dictionary = {}

			if training_metrics.has("last_match_score") and training_metrics["last_match_score"] is Dictionary:

				last_match_score_tab = training_metrics["last_match_score"]

			var trait_line := "Traços: win %0.0f%%/%0.0f%% | K %0.1f/%0.1f | Alive %0.1f/%0.1f | Score %0.2f/%0.2f" % [

				float(winrate.get(1, 0.0)) * 100.0,

				float(winrate.get(2, 0.0)) * 100.0,

				float(avg_kills.get(1, 0.0)),

				float(avg_kills.get(2, 0.0)),

				float(avg_alive.get(1, 0.0)),

				float(avg_alive.get(2, 0.0)),

				float(avg_score.get(1, 0.0)),

				float(avg_score.get(2, 0.0))

			]

			var global_lines: Array[String] = [

				"[b]Geral[/b]",

				"Geração atual: %d" % max(current_generation, 1),

				"Rodadas analisadas: %d" % rounds,

				trait_line,

				"Último match: P1 %0.3f | P2 %0.3f" % [

					float(last_match_score_tab.get(1, 0.0)),

					float(last_match_score_tab.get(2, 0.0))

				]

			]

			global_metrics_label.text = "\n".join(global_lines)

	for player_id in bot_metrics_labels.keys():

		var label_node: RichTextLabel = bot_metrics_labels.get(player_id, null)

		if label_node == null:

			continue

		if not training_enabled:

			label_node.text = "[b]P%d[/b]\nTreino: inativo" % player_id

			continue

		var name := String(bot_card_names.get(player_id, "P%d" % player_id))

		var match_score_tab := {}

		if training_metrics.has("match_score") and training_metrics["match_score"] is Dictionary:

			match_score_tab = training_metrics["match_score"]

		var last_match_score_tab := {}

		if training_metrics.has("last_match_score") and training_metrics["last_match_score"] is Dictionary:

			last_match_score_tab = training_metrics["last_match_score"]

		var wins: Dictionary = {}

		if training_metrics.has("wins") and training_metrics["wins"] is Dictionary:

			wins = training_metrics["wins"]

		var total_points := float(bot_points.get(str(player_id), bot_points.get(player_id, 0.0)))

		var generation_text := "Geração %d" % max(current_generation, 1)

		var info_lines: Array[String] = [

			"[b]%s[/b]" % name,

			generation_text,

			"Pontos: %0.3f" % total_points,

			"Score atual: %0.3f | Último: %0.3f" % [

				float(match_score_tab.get(str(player_id), match_score_tab.get(player_id, 0.0))),

				float(last_match_score_tab.get(str(player_id), last_match_score_tab.get(player_id, 0.0)))

			],

			"Wins: %d" % int(wins.get(player_id, 0))

		]

		label_node.text = "\n".join(info_lines)



func _on_reload_pressed() -> void:

	DevDebug.log_event("dev_hud", "Solicitou reload de cena")

	emit_signal("reload_requested")



func _on_training_toggle(pressed: bool) -> void:

	training_enabled = pressed

	_update_training_controls_state()

	_update_training_metrics_label()

	_update_ga_overlay()

	emit_signal("training_toggle_requested", pressed)



func _on_watch_toggle(pressed: bool) -> void:

	training_watch_mode = pressed

	_update_ga_overlay()

	emit_signal("training_watch_toggled", pressed)



func _on_reset_episode_pressed() -> void:

	emit_signal("training_reset_requested")



func _on_logging_toggle(pressed: bool) -> void:

	training_logging_enabled = pressed

	_update_log_path_label()

	emit_signal("training_logging_toggled", pressed)



func _on_load_genome_pressed() -> void:

	emit_signal("genome_load_requested", genome_path)



func _on_round_apply_pressed() -> void:

	var steps := round_max_steps

	if round_steps_spin:

		steps = int(round_steps_spin.value)

	var seconds := round_max_seconds

	if round_seconds_spin:

		seconds = float(round_seconds_spin.value)

	var kills := round_max_kills

	if round_kills_spin:

		kills = int(round_kills_spin.value)

	round_max_steps = steps

	round_max_seconds = seconds

	round_max_kills = kills

	emit_signal("round_limits_requested", steps, seconds, kills)



func _on_rewards_apply_pressed() -> void:

	var time_without_kill_value := reward_time_without_kill

	if reward_time_without_kill_spin:

		time_without_kill_value = float(reward_time_without_kill_spin.value)

	var kill_value := reward_kill

	if reward_kill_spin:

		kill_value = float(reward_kill_spin.value)

	var death_value := reward_death

	if reward_death_spin:

		death_value = float(reward_death_spin.value)

	var time_alive_value := reward_time_alive

	if reward_time_alive_spin:

		time_alive_value = float(reward_time_alive_spin.value)

	reward_time_without_kill = time_without_kill_value

	reward_kill = kill_value

	reward_death = death_value

	reward_time_alive = time_alive_value

	emit_signal("rewards_requested", time_without_kill_value, kill_value, death_value, time_alive_value)



func _on_bot_p1_apply_pressed() -> void:

	var payload := _build_bot_reward_payload(1)

	bot_rewards[1] = payload

	emit_signal("bot_config_requested", 1, payload)



func _on_bot_p2_apply_pressed() -> void:

	var payload := _build_bot_reward_payload(2)

	bot_rewards[2] = payload

	emit_signal("bot_config_requested", 2, payload)



func _build_bot_reward_payload(player_id: int) -> Dictionary:

	var payload := {}

	if player_id == 1:

		payload["time_without_kill"] = float(bot_p1_time_without_kill_spin.value) if bot_p1_time_without_kill_spin else 0.0

		payload["kill"] = float(bot_p1_kill_spin.value) if bot_p1_kill_spin else 0.0

		payload["death"] = float(bot_p1_death_spin.value) if bot_p1_death_spin else 0.0

		payload["time_alive"] = float(bot_p1_time_alive_spin.value) if bot_p1_time_alive_spin else 0.0

		return payload

	payload["time_without_kill"] = float(bot_p2_time_without_kill_spin.value) if bot_p2_time_without_kill_spin else 0.0

	payload["kill"] = float(bot_p2_kill_spin.value) if bot_p2_kill_spin else 0.0

	payload["death"] = float(bot_p2_death_spin.value) if bot_p2_death_spin else 0.0

	payload["time_alive"] = float(bot_p2_time_alive_spin.value) if bot_p2_time_alive_spin else 0.0

	return payload



func _on_ga_apply_pressed() -> void:

	var enabled := generation_per_round

	if ga_generation_toggle:

		enabled = ga_generation_toggle.button_pressed

	var generations := max_generations

	if ga_generations_spin:

		generations = int(ga_generations_spin.value)

	generation_per_round = enabled

	max_generations = generations

	emit_signal("ga_config_requested", enabled, generations)



func _on_trainer_start_pressed() -> void:

	var python_path := trainer_python

	if trainer_python_path:

		python_path = trainer_python_path.text.strip_edges()

		trainer_python_path.text = python_path

	var script_path := trainer_script

	if trainer_script_path:

		script_path = trainer_script_path.text.strip_edges()

		trainer_script_path.text = script_path

	var extra_args := trainer_args

	if trainer_args_line:

		extra_args = trainer_args_line.text.strip_edges()

		trainer_args_line.text = extra_args

	trainer_python = python_path if python_path != "" else "python"

	trainer_script = script_path

	trainer_args = extra_args

	trainer_status = "Trainer: iniciando..."

	trainer_is_running = true

	_update_trainer_controls()

	emit_signal("trainer_start_requested", trainer_python, trainer_script, trainer_args)



func _on_trainer_stop_pressed() -> void:

	trainer_status = "Trainer: parando..."

	_update_trainer_controls()

	emit_signal("trainer_stop_requested")
