extends RefCounted

class_name TrainingManager



const RewardShaperDefault = preload("res://engine/scripts/modules/reward_shaper_default.gd")

const RewardShaperTunable = preload("res://engine/scripts/modules/reward_shaper_tunable.gd")

const TrainingRecorder = preload("res://engine/scripts/modules/training_recorder.gd")



const BASE_TICK_RATE := 60.0



const TrainingBridge = preload("res://engine/scripts/modules/training_bridge.gd")

const BotObservationBuilder = preload("res://engine/scripts/modules/bot_observation_builder.gd")



var bridge = TrainingBridge.new()

var observation_builder = BotObservationBuilder.new()



var main_node: Node = null

var player_one: Node = null

var player_two: Node = null

var bot_driver_one = null

var bot_driver_two = null



var enabled := false

var watch_mode := false

var time_scale := 1.0

var reward_time_without_kill := -0.001

var reward_kill := 1.0

var reward_death := -1.0

var reward_time_alive := 0.0

var round_max_steps := 0

var round_max_seconds := 0.0

var round_max_kills := 5

var round_steps := 0

var round_elapsed := 0.0

var round_kills := {1: 0, 2: 0}

var round_deaths := {1: 0, 2: 0}

var round_alive_time := {1: 0.0, 2: 0.0}

var round_score := {1: 0.0, 2: 0.0}

var match_round_scores := {1: [], 2: []}

var match_score := {1: 0.0, 2: 0.0}

var last_match_score := {1: 0.0, 2: 0.0}

var last_kill_total := 0

var round_segment_steps := 0

var last_round_stats: Dictionary = {}

var round_history: Array = []

var round_history_max := 5

var round_log_path := "res://BOTS/IA/logs/round_stats.csv"
var evolution_stats: Dictionary = {}

var evolution_log_path := "res://BOTS/IA/logs/evolution.csv"
var logging_enabled := false

var log_path := "user://training_metrics.csv"

var ga_state: Dictionary = {}

var pending_save_models: Array[Dictionary] = []



var bot_configs := {}

var bot_names := {1: "Agressivo", 2: "Estrategista"}



var frame_number := 0

var last_alive := {1: true, 2: true}

var connected_sent := false

var episode_index := 0

var episode_steps := 0

var episode_elapsed := 0.0

var total_steps := 0

var episode_reward := {"1": 0.0, "2": 0.0}

var last_episode_reward := {"1": 0.0, "2": 0.0}

var last_reward := {"1": 0.0, "2": 0.0}

var last_episode_steps := 0

var wins_count := {1: 0, 2: 0}

var last_winner := 0

var last_done := false

var reward_shaper = null



var super_reward_cfg_path := ""

var super_reward_cfg_signature := ""

var super_reward_cfg: Dictionary = {}

var super_reward_last_components: Dictionary = {1: {}, 2: {}}

var recorder = null

var recording_enabled := false

var recording_path := ""



var force_external_policies := false

var external_policies_applied := false

var external_control_players := {
	1: true,
	2: true
}

func set_external_control_players(player_ids: Array) -> void:
	var out := {1: false, 2: false}
	for v in player_ids:
		var id := int(v)
		if id == 1 or id == 2:
			out[id] = true
	external_control_players = out



func _get_dev_debug() -> Node:

	var main_loop: MainLoop = Engine.get_main_loop()

	if main_loop is SceneTree:

		var tree: SceneTree = main_loop as SceneTree

		if tree.root:

			return tree.root.get_node_or_null("DevDebug")

	return null



func configure(main_node_value: Node, p1: Node, p2: Node, bot_one, bot_two) -> void:

	main_node = main_node_value

	player_one = p1

	player_two = p2

	bot_driver_one = bot_one

	bot_driver_two = bot_two

	_ensure_reward_shaper()

	_ensure_recorder()

	_reset_tracking()

	_apply_recording_state()



func set_recording(enabled_value: bool, path: String = "") -> void:

	recording_enabled = enabled_value

	recording_path = _normalize_path(path) if path != "" else ""

	_apply_recording_state()



func _ensure_recorder() -> void:

	if recorder == null:

		recorder = TrainingRecorder.new()



func _apply_recording_state() -> void:

	_ensure_recorder()

	if recorder == null:

		return

	if not recording_enabled or recording_path == "":

		recorder.stop()

		return

	recorder.start(recording_path)



func start(port: int) -> void:

	enabled = true

	_ensure_reward_shaper()

	_ensure_recorder()

	_bridge_start(port)

	connected_sent = false

	_apply_time_scale()

	external_policies_applied = false

	if force_external_policies:

		_ensure_external_policies()

		external_policies_applied = true



func request_reset() -> void:

	_request_reset()



func stop() -> void:

	enabled = false

	_bridge_stop()

	if recorder != null and recorder.has_method("stop"):

		recorder.stop()

	Engine.time_scale = 1.0



func set_logging_enabled(enabled_value: bool, path: String = "") -> void:

	logging_enabled = enabled_value

	if path != "":

		log_path = path

	if logging_enabled:

		_ensure_log_header()



func is_logging_enabled() -> bool:

	return logging_enabled



func get_log_path() -> String:

	return log_path



func _bridge_call(method_name: String, args: Array = []) -> Variant:

	if bridge == null:

		return null

	if not bridge.has_method(method_name):

		return null

	return bridge.callv(method_name, args)



func _bridge_start(port: int) -> void:

	_bridge_call("start", [port])



func _bridge_stop() -> void:

	_bridge_call("stop")



func _bridge_poll() -> void:

	_bridge_call("poll")



func _bridge_send(payload: Dictionary) -> void:

	_bridge_call("send", [payload])



func _bridge_pop_messages() -> Array[Dictionary]:

	var value: Variant = _bridge_call("pop_messages")

	if value is Array:

		return value

	return []



func _bridge_is_connected() -> bool:

	var result: Variant = _bridge_call("is_bridge_connected")

	if result is bool:

		return result

	return false



func set_watch_mode(enabled_value: bool, speed: float) -> void:

	watch_mode = enabled_value

	time_scale = float(speed)

	_apply_time_scale()



func set_rewards(time_without_kill_reward: float, kill_reward: float, death_reward: float, time_alive_reward: float) -> void:

	reward_time_without_kill = time_without_kill_reward

	reward_kill = kill_reward

	reward_death = death_reward

	reward_time_alive = time_alive_reward



func load_rewards(path: String) -> void:

	var data := _load_json(path)

	if data.is_empty():

		return

	if data.has("time_without_kill"):

		reward_time_without_kill = float(data["time_without_kill"])

	elif data.has("step"):

		reward_time_without_kill = float(data["step"])

	if data.has("kill"):

		reward_kill = float(data["kill"])

	if data.has("death"):

		reward_death = float(data["death"])

	if data.has("time_alive"):

		reward_time_alive = float(data["time_alive"])

	elif data.has("alive"):

		reward_time_alive = float(data["alive"])



func set_round_limits(max_steps: int, max_seconds: float, max_kills: int = -1) -> void:

	round_max_steps = max(max_steps, 0)

	round_max_seconds = max(max_seconds, 0.0)

	if max_kills >= 0:

		round_max_kills = max(max_kills, 0)



func load_round_limits(path: String) -> void:

	var data := _load_json(path)

	if data.is_empty():

		return

	if data.has("max_steps"):

		round_max_steps = max(int(data["max_steps"]), 0)

	if data.has("max_seconds"):

		round_max_seconds = max(float(data["max_seconds"]), 0.0)

	if data.has("max_kills"):

		round_max_kills = max(int(data["max_kills"]), 0)

	if data.has("history_max"):

		round_history_max = max(int(data["history_max"]), 0)

	if data.has("log_path"):

		round_log_path = _normalize_path(String(data["log_path"]))

	if data.has("evolution_log_path"):

		evolution_log_path = _normalize_path(String(data["evolution_log_path"]))



func load_bot_config(player_id: int, path: String) -> void:

	var data := _load_json(path)

	if data.is_empty():

		return

	bot_configs[player_id] = data

	if data.has("name"):

		bot_names[player_id] = String(data["name"])



func set_bot_reward_config(player_id: int, reward_config: Dictionary) -> void:

	var config: Dictionary = bot_configs.get(player_id, {})

	config["reward"] = reward_config.duplicate(true)

	bot_configs[player_id] = config



func step(delta: float) -> void:

	if not enabled:

		return

	if delta <= 0.0:

		return

	_bridge_poll()

	if _bridge_is_connected():

		var needs_external := not external_policies_applied

		if bool(external_control_players.get(1, true)) and bot_driver_one and bot_driver_one.has_method("get_policy_id"):

			needs_external = needs_external or String(bot_driver_one.get_policy_id()) != "external"

		if bool(external_control_players.get(2, true)) and bot_driver_two and bot_driver_two.has_method("get_policy_id"):

			needs_external = needs_external or String(bot_driver_two.get_policy_id()) != "external"

		if needs_external:

			_ensure_external_policies()

			external_policies_applied = true

	if _bridge_is_connected() and not connected_sent:

		_bridge_send({"type": "hello", "protocol": 1})

		connected_sent = true

	var messages: Array[Dictionary] = _bridge_pop_messages()

	for message in messages:

		_handle_message(message)

	if not _bridge_is_connected():

		return

	_tick_training(delta)



func _tick_training(step_delta: float) -> void:

	var dt := step_delta
	var ts := Engine.time_scale
	if ts > 0.0:
		dt = step_delta / ts

	round_elapsed += dt

	round_steps += 1

	episode_elapsed += dt

	var obs_p1: Dictionary = observation_builder.build(main_node, player_one, player_two, frame_number, dt)

	var obs_p2: Dictionary = observation_builder.build(main_node, player_two, player_one, frame_number, dt)

	var rewards: Dictionary = _compute_rewards(obs_p1, obs_p2, dt)

	var done: bool = _is_done()

	var alive_p1: bool = _is_alive(obs_p1)

	var alive_p2: bool = _is_alive(obs_p2)

	_accumulate_round_stats(obs_p1, obs_p2, alive_p1, alive_p2, dt)

	_update_episode_metrics(rewards, done, alive_p1, alive_p2)

	var debug_bridge := OS.has_method("get_cmdline_user_args") and OS.get_cmdline_user_args().has("--debug-bridge")

	var obs_out_p1 := obs_p1

	var obs_out_p2 := obs_p2

	if not debug_bridge:

		obs_out_p1 = obs_p1.duplicate(false)

		obs_out_p2 = obs_p2.duplicate(false)

		obs_out_p1.erase("raw")

		obs_out_p2.erase("raw")

	var payload := {

		"type": "step",

		"frame": frame_number,

		"obs": {"1": obs_out_p1, "2": obs_out_p2},

		"reward": rewards,

		"done": done,

		"info": _build_info(),

		"metrics": get_metrics()

	}

	if debug_bridge:

		payload["actions_frame"] = {"1": _get_player_frame(player_one), "2": _get_player_frame(player_two)}

		payload["bot_policy"] = {

			"1": bot_driver_one.get_policy_id() if bot_driver_one and bot_driver_one.has_method("get_policy_id") else "",

			"2": bot_driver_two.get_policy_id() if bot_driver_two and bot_driver_two.has_method("get_policy_id") else ""

		}

	_record_step(payload)

	_bridge_send(payload)

	for request in pending_save_models:

		_bridge_send({"type": "save_model", "player_id": int(request.get("player_id", 0)), "name": String(request.get("name", ""))})

	pending_save_models.clear()

	frame_number += 1



func _record_step(step_payload: Dictionary) -> void:

	if not recording_enabled or recorder == null:

		return

	var obs_value: Variant = step_payload.get("obs")

	if not (obs_value is Dictionary):

		return

	var obs_map: Dictionary = obs_value as Dictionary

	var obs1: Dictionary = (obs_map.get("1", {}) as Dictionary).duplicate(true)

	var obs2: Dictionary = (obs_map.get("2", {}) as Dictionary).duplicate(true)

	obs1.erase("raw")

	obs2.erase("raw")

	var record := {

		"t_ms": int(Time.get_ticks_msec()),

		"frame": int(step_payload.get("frame", 0)),

		"obs": {"1": obs1, "2": obs2},

		"reward": step_payload.get("reward", {}),

		"done": bool(step_payload.get("done", false)),

		"info": step_payload.get("info", {}),

		"actions_frame": {"1": _get_player_frame(player_one), "2": _get_player_frame(player_two)}

	}

	recorder.record_line(record)



func _get_player_frame(player: Node) -> Dictionary:

	if player == null or not player.has_method("get"):

		return {}

	var reader: Variant = player.get("input_reader")

	if reader == null or not reader.has_method("get_frame"):

		return {}

	var frame: Variant = reader.get_frame()

	if frame is Dictionary:

		return (frame as Dictionary).duplicate(true)

	return {}



func reset_episode() -> void:

	_reset_tracking()

	_reset_episode_metrics()

	if reward_shaper != null and reward_shaper.has_method("reset"):

		reward_shaper.reset(self)

	if _bridge_is_connected():

		_bridge_send({"type": "episode_start"})



func _ensure_reward_shaper() -> void:

	if reward_shaper == null:

		if super_reward_cfg_path != "":

			reward_shaper = RewardShaperTunable.new()

			reward_shaper.configure(super_reward_cfg_path)

		else:

			reward_shaper = RewardShaperDefault.new()





func set_super_reward_config(path: String) -> void:

	super_reward_cfg_path = path

	super_reward_cfg_signature = ""

	super_reward_cfg = {}

	super_reward_last_components = {1: {}, 2: {}}

	reward_shaper = null

	_ensure_reward_shaper()

	if enabled and reward_shaper != null and reward_shaper.has_method("reset"):

		reward_shaper.reset(self)



func get_metrics() -> Dictionary:

	return {

		"enabled": enabled,

		"connected": _bridge_is_connected(),

		"bridge_listening": bridge.is_listening,

		"bridge_port": bridge.port,

		"bridge_last_error": bridge.last_error,

		"bridge_debug": bridge.get_debug_state() if bridge and bridge.has_method("get_debug_state") else {},

		"logging_enabled": logging_enabled,

		"log_path": log_path,

		"generation": max(episode_index, 1),

		"round_steps": round_steps,

		"round_elapsed": round_elapsed,

		"round_max_steps": round_max_steps,

		"round_max_seconds": round_max_seconds,

		"round_max_kills": round_max_kills,

		"round_kills": round_kills.duplicate(true),

		"round_deaths": round_deaths.duplicate(true),

		"round_log_path": round_log_path,

		"round_history": round_history.duplicate(true),

		"reward_time_without_kill": reward_time_without_kill,

		"reward_kill": reward_kill,

		"reward_death": reward_death,

		"reward_time_alive": reward_time_alive,

		"round_score": round_score.duplicate(true),

		"match_score": match_score.duplicate(true),

		"last_match_score": last_match_score.duplicate(true),

		"evolution": evolution_stats.duplicate(true),

		"bot_rewards": _get_bot_reward_metrics(),

		"bot_names": bot_names.duplicate(true),

		"last_round": last_round_stats.duplicate(true),

		"episode": episode_index,

		"episode_steps": episode_steps,

		"last_episode_steps": last_episode_steps,

		"reward": episode_reward.duplicate(true),

		"bot_points": match_score.duplicate(true),

		"last_episode_reward": last_episode_reward.duplicate(true),

		"last_reward": last_reward.duplicate(true),

		"wins": wins_count.duplicate(true),

		"last_winner": last_winner,

		"total_steps": total_steps,

		"watch_mode": watch_mode,

		"time_scale": Engine.time_scale,

		"super_reward": {

			"path": super_reward_cfg_path,

			"signature": super_reward_cfg_signature,

			"last_components": super_reward_last_components.duplicate(true),

		},

		"ga_state": ga_state.duplicate(true)

	}



func _get_bot_reward_metrics() -> Dictionary:

	var result: Dictionary = {}

	for player_id in bot_configs.keys():

		var config: Dictionary = bot_configs[player_id]

		if config.has("reward") and config["reward"] is Dictionary:

			result[player_id] = (config["reward"] as Dictionary).duplicate(true)

		else:

			result[player_id] = {}

	return result



func _handle_message(message: Dictionary) -> void:

	var msg_type := String(message.get("type", ""))

	if msg_type == "action":

		_apply_actions(message.get("actions"))

		return

	if msg_type == "config":

		_apply_config(message)

		return

	if msg_type == "reset":

		_request_reset()

		return

	if msg_type == "get_metrics":

		_bridge_send({"type": "metrics", "metrics": get_metrics()})

		return

	if msg_type == "ping":

		_bridge_send({"type": "pong", "t": int(Time.get_ticks_msec())})

		return

	if msg_type == "event":

		var dev_debug := _get_dev_debug()

		if dev_debug != null and dev_debug.has_method("log_event"):

			dev_debug.log_event("trainer", String(message.get("text", "")))

		return



func _apply_actions(actions_value: Variant) -> void:

	if not (actions_value is Dictionary):

		return

	var actions: Dictionary = actions_value as Dictionary

	var action_p1 := _extract_action(actions, 1)

	var action_p2 := _extract_action(actions, 2)

	if bot_driver_one and bot_driver_one.has_method("set_external_action"):

		bot_driver_one.set_external_action(action_p1)

	if bot_driver_two and bot_driver_two.has_method("set_external_action"):

		bot_driver_two.set_external_action(action_p2)



func _extract_action(actions: Dictionary, player_id: int) -> Dictionary:

	var key_str := str(player_id)

	if actions.has(player_id):

		var value: Variant = actions[player_id]

		if value is Dictionary:

			return value.duplicate(true)

		return {}

	if actions.has(key_str):

		var value: Variant = actions[key_str]

		if value is Dictionary:

			return value.duplicate(true)

		return {}

	return {}



func _get_bot_reward(player_id: int, key: String, fallback: float, legacy_key: String = "") -> float:

	var config: Dictionary = bot_configs.get(player_id, {})

	if config.has("reward") and config["reward"] is Dictionary:

		var reward_cfg: Dictionary = config["reward"]

		if reward_cfg.has(key):

			return float(reward_cfg[key])

		if legacy_key != "" and reward_cfg.has(legacy_key):

			return float(reward_cfg[legacy_key])

	return fallback



func _accumulate_round_stats(obs_p1: Dictionary, obs_p2: Dictionary, alive_p1: bool, alive_p2: bool, delta: float) -> void:

	if alive_p1:

		round_alive_time[1] = float(round_alive_time.get(1, 0.0)) + delta

	if alive_p2:

		round_alive_time[2] = float(round_alive_time.get(2, 0.0)) + delta



func _build_round_stats(winner_id: int) -> Dictionary:

	var steps: int = max(round_steps, 1)

	var round_index_value: Variant = _safe_get(main_node, "round_index")

	var wins_value: Variant = _safe_get(main_node, "wins")

	var match_over_value: Variant = _safe_get(main_node, "match_over")

	var wins_dict: Dictionary = (wins_value as Dictionary) if wins_value is Dictionary else {}

	var is_match_over := match_over_value != null and bool(match_over_value)

	var w1 := int(wins_dict.get(1, wins_dict.get("1", 0)))

	var w2 := int(wins_dict.get(2, wins_dict.get("2", 0)))

	var steps_out := round_steps

	var time_out := round_elapsed

	var kills_out: Dictionary = round_kills.duplicate(true)

	var deaths_out: Dictionary = round_deaths.duplicate(true)

	if is_match_over:

		steps_out = episode_steps

		time_out = episode_elapsed

		kills_out = round_kills.duplicate(true)

		deaths_out = round_deaths.duplicate(true)

	return {

		"round_index": int(round_index_value) if round_index_value != null else 0,

		"winner": winner_id,

		"steps": steps_out,

		"time": time_out,

		"kills": kills_out,

		"deaths": deaths_out,

		"alive_time": round_alive_time.duplicate(true),

		"wins": wins_dict.duplicate(true),

		"match_score": match_score.duplicate(true),

		"round_scores": match_round_scores.duplicate(true)

	}



func _reset_round_stats() -> void:

	round_kills = {1: 0, 2: 0}

	round_deaths = {1: 0, 2: 0}

	round_alive_time = {1: 0.0, 2: 0.0}

	round_score = {1: 0.0, 2: 0.0}

	match_round_scores = {1: [], 2: []}

	match_score = {1: 0.0, 2: 0.0}

	last_kill_total = 0

	round_segment_steps = 0



func _append_round_history(stats: Dictionary) -> void:

	if round_history_max <= 0:

		return

	round_history.append(stats.duplicate(true))

	while round_history.size() > round_history_max:

		round_history.pop_front()



func _update_evolution_stats() -> void:

	var total_rounds := round_history.size()

	if total_rounds <= 0:

		evolution_stats = {}

		return

	var wins := {1: 0, 2: 0}

	var kills := {1: 0.0, 2: 0.0}

	var alive := {1: 0.0, 2: 0.0}

	var score := {1: 0.0, 2: 0.0}

	for round_entry in round_history:

		if not (round_entry is Dictionary):

			continue

		var round_dict: Dictionary = round_entry as Dictionary

		var winner_id := int(round_dict.get("winner", 0))

		if winner_id > 0 and wins.has(winner_id):

			wins[winner_id] += 1

		var round_kills: Dictionary = round_dict.get("kills", {}) if round_dict.has("kills") else {}

		var round_alive: Dictionary = round_dict.get("alive_time", {}) if round_dict.has("alive_time") else {}

		var round_score: Dictionary = round_dict.get("match_score", {}) if round_dict.has("match_score") else {}

		kills[1] += float(round_kills.get(1, 0.0))

		kills[2] += float(round_kills.get(2, 0.0))

		alive[1] += float(round_alive.get(1, 0.0))

		alive[2] += float(round_alive.get(2, 0.0))

		score[1] += float(round_score.get(1, 0.0))

		score[2] += float(round_score.get(2, 0.0))

	var rounds_float := float(total_rounds)

	evolution_stats = {

		"rounds": total_rounds,

		"window": round_history_max,

		"wins": wins.duplicate(true),

		"winrate": {

			1: float(wins.get(1, 0)) / rounds_float,

			2: float(wins.get(2, 0)) / rounds_float

		},

		"avg_kills": {

			1: float(kills.get(1, 0.0)) / rounds_float,

			2: float(kills.get(2, 0.0)) / rounds_float

		},

		"avg_alive": {

			1: float(alive.get(1, 0.0)) / rounds_float,

			2: float(alive.get(2, 0.0)) / rounds_float

		},

		"avg_score": {

			1: float(score.get(1, 0.0)) / rounds_float,

			2: float(score.get(2, 0.0)) / rounds_float

		}

	}



func _normalize_path(path: String) -> String:

	if path == "":

		return ""

	if path.begins_with("res://") or path.begins_with("user://"):

		return path

	if path.begins_with("/"):

		return path

	return "res://" + path



func _ensure_round_log_header() -> void:

	if round_log_path == "":

		return

	if FileAccess.file_exists(round_log_path):

		return

	var file := FileAccess.open(round_log_path, FileAccess.WRITE)

	if file == null and not round_log_path.begins_with("user://"):

		round_log_path = "user://round_stats.csv"

		file = FileAccess.open(round_log_path, FileAccess.WRITE)

	if file == null:

		return

	file.store_line("timestamp,episode,round_index,winner,kills_p1,kills_p2,deaths_p1,deaths_p2,alive_p1,alive_p2,score_p1,score_p2")



func _log_round_stats(stats: Dictionary) -> void:

	if round_log_path == "":

		return

	_ensure_round_log_header()

	var file := FileAccess.open(round_log_path, FileAccess.READ_WRITE)

	if file == null:

		return

	file.seek_end()

	var timestamp := int(Time.get_unix_time_from_system())

	var kills: Dictionary = stats.get("kills", {}) if stats.has("kills") else {}

	var deaths: Dictionary = stats.get("deaths", {}) if stats.has("deaths") else {}

	var alive: Dictionary = stats.get("alive_time", {}) if stats.has("alive_time") else {}

	var scores: Dictionary = stats.get("match_score", {}) if stats.has("match_score") else {}

	var line := "%d,%d,%d,%d,%d,%d,%d,%d,%.3f,%.3f,%.3f,%.3f" % [

		timestamp,

		int(episode_index),

		int(stats.get("round_index", 0)),

		int(stats.get("winner", 0)),

		int(kills.get(1, 0)),

		int(kills.get(2, 0)),

		int(deaths.get(1, 0)),

		int(deaths.get(2, 0)),

		float(alive.get(1, 0.0)),

		float(alive.get(2, 0.0)),

		float(scores.get(1, 0.0)),

		float(scores.get(2, 0.0))

	]

	file.store_line(line)



func _ensure_evolution_log_header() -> void:

	if evolution_log_path == "":

		return

	if FileAccess.file_exists(evolution_log_path):

		return

	var file := FileAccess.open(evolution_log_path, FileAccess.WRITE)

	if file == null and not evolution_log_path.begins_with("user://"):

		evolution_log_path = "user://evolution.csv"

		file = FileAccess.open(evolution_log_path, FileAccess.WRITE)

	if file == null:

		return

	file.store_line("timestamp,episode,rounds,winrate_p1,winrate_p2,avg_kills_p1,avg_kills_p2,avg_alive_p1,avg_alive_p2,avg_score_p1,avg_score_p2")



func _log_evolution_stats() -> void:

	if evolution_log_path == "":

		return

	if evolution_stats.is_empty():

		return

	_ensure_evolution_log_header()

	var file := FileAccess.open(evolution_log_path, FileAccess.READ_WRITE)

	if file == null:

		return

	file.seek_end()

	var timestamp := int(Time.get_unix_time_from_system())

	var winrate: Dictionary = evolution_stats.get("winrate", {}) if evolution_stats.has("winrate") else {}

	var avg_kills: Dictionary = evolution_stats.get("avg_kills", {}) if evolution_stats.has("avg_kills") else {}

	var avg_alive: Dictionary = evolution_stats.get("avg_alive", {}) if evolution_stats.has("avg_alive") else {}

	var avg_score: Dictionary = evolution_stats.get("avg_score", {}) if evolution_stats.has("avg_score") else {}

	var line := "%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [

		timestamp,

		int(episode_index),

		int(evolution_stats.get("rounds", 0)),

		float(winrate.get(1, 0.0)),

		float(winrate.get(2, 0.0)),

		float(avg_kills.get(1, 0.0)),

		float(avg_kills.get(2, 0.0)),

		float(avg_alive.get(1, 0.0)),

		float(avg_alive.get(2, 0.0)),

		float(avg_score.get(1, 0.0)),

		float(avg_score.get(2, 0.0))

	]

	file.store_line(line)



func _apply_config(message: Dictionary) -> void:

	if message.has("watch_mode"):

		watch_mode = bool(message["watch_mode"])

	if message.has("time_scale"):

		time_scale = float(message["time_scale"])

	if message.has("ga_state") and message["ga_state"] is Dictionary:

		ga_state = (message["ga_state"] as Dictionary).duplicate(true)

	_apply_time_scale()



func request_save_model(player_id: int, model_name: String) -> void:

	pending_save_models.append({"player_id": player_id, "name": model_name})



func _request_reset() -> void:

	if main_node == null:

		return

	reset_episode()

	if main_node.has_method("reset_training_match"):

		main_node.call("reset_training_match")

		return

	if main_node.has_method("_start_round"):

		main_node.call("_start_round")



func _compute_rewards(obs_p1: Dictionary, obs_p2: Dictionary, step_delta: float) -> Dictionary:

	_ensure_reward_shaper()

	if reward_shaper != null and reward_shaper.has_method("compute"):

		var rewards: Variant = reward_shaper.compute(self, obs_p1, obs_p2, step_delta)

		if rewards is Dictionary:

			return rewards

	return {"1": 0.0, "2": 0.0}



func _average_scores(values: Array) -> float:

	if values.is_empty():

		return 0.0

	var total := 0.0

	for value in values:

		total += float(value)

	return total / float(values.size())



func _finalize_round_scores() -> void:

	if round_segment_steps <= 0:

		return

	match_round_scores[1].append(float(round_score.get(1, 0.0)))

	match_round_scores[2].append(float(round_score.get(2, 0.0)))

	match_score[1] = _average_scores(match_round_scores.get(1, []))

	match_score[2] = _average_scores(match_round_scores.get(2, []))

	round_score[1] = 0.0

	round_score[2] = 0.0

	round_segment_steps = 0



func _update_episode_metrics(rewards: Dictionary, done: bool, alive_p1: bool, alive_p2: bool) -> void:

	var reward_p1: float = float(rewards.get("1", 0.0))

	var reward_p2: float = float(rewards.get("2", 0.0))

	last_reward = {"1": reward_p1, "2": reward_p2}

	episode_reward["1"] = float(episode_reward.get("1", 0.0)) + reward_p1

	episode_reward["2"] = float(episode_reward.get("2", 0.0)) + reward_p2

	round_score[1] = float(round_score.get(1, 0.0)) + reward_p1

	round_score[2] = float(round_score.get(2, 0.0)) + reward_p2

	round_segment_steps += 1

	episode_steps += 1

	total_steps += 1

	var total_kills := int(round_kills.get(1, 0)) + int(round_kills.get(2, 0))

	if total_kills > last_kill_total:

		_finalize_round_scores()

		last_kill_total = total_kills

	if done and not last_done:

		if round_segment_steps > 0:

			_finalize_round_scores()

		last_match_score = match_score.duplicate(true)

		last_episode_reward = episode_reward.duplicate(true)

		last_episode_steps = episode_steps

		episode_index += 1

		var match_over_value: Variant = _safe_get(main_node, "match_over")

		if match_over_value != null and bool(match_over_value):

			last_winner = _determine_match_winner()

		else:

			last_winner = _determine_round_winner(alive_p1, alive_p2)

		last_round_stats = _build_round_stats(last_winner)

		_append_round_history(last_round_stats)

		_log_round_stats(last_round_stats)

		_update_evolution_stats()

		_log_evolution_stats()

		if last_winner > 0 and wins_count.has(last_winner):

			wins_count[last_winner] += 1

		_log_episode()

		last_done = true

	elif not done:

		last_done = false



func _determine_winner(alive_p1: bool, alive_p2: bool) -> int:

	if alive_p1 and not alive_p2:

		return 1

	if alive_p2 and not alive_p1:

		return 2

	return 0





func _determine_match_winner() -> int:

	var wins_value: Variant = _safe_get(main_node, "wins")

	if not (wins_value is Dictionary):

		return 0

	var wins: Dictionary = wins_value as Dictionary

	var w1 := int(wins.get(1, wins.get("1", 0)))

	var w2 := int(wins.get(2, wins.get("2", 0)))

	if w1 > w2:

		return 1

	if w2 > w1:

		return 2

	return 0



func _determine_round_winner(alive_p1: bool, alive_p2: bool) -> int:

	if round_max_kills > 0:

		var kills_p1 := int(round_kills.get(1, 0))

		var kills_p2 := int(round_kills.get(2, 0))

		if kills_p1 > kills_p2:

			return 1

		if kills_p2 > kills_p1:

			return 2

		var s1 := float(match_score.get(1, 0.0))

		var s2 := float(match_score.get(2, 0.0))

		if s1 > s2:

			return 1

		if s2 > s1:

			return 2

		return 0

	return _determine_winner(alive_p1, alive_p2)



func _is_alive(obs: Dictionary) -> bool:

	if obs.has("self") and obs["self"] is Dictionary:

		var self_dict := obs["self"] as Dictionary

		if self_dict.has("is_dead"):

			return not bool(self_dict["is_dead"])

	return true



func _is_done() -> bool:

	if round_max_steps > 0 and round_steps >= round_max_steps:

		return true

	if round_max_seconds > 0.0 and round_elapsed >= round_max_seconds:

		return true

	var match_over_value: Variant = _safe_get(main_node, "match_over")

	if match_over_value != null and bool(match_over_value):

		return true

	if round_max_kills > 0:

		if int(round_kills.get(1, 0)) >= round_max_kills:

			return true

		if int(round_kills.get(2, 0)) >= round_max_kills:

			return true

	var round_active_value: Variant = _safe_get(main_node, "round_active")

	if round_active_value != null:

		if not bool(round_active_value) and round_max_kills <= 0:

			return match_over_value != null and bool(match_over_value)

		return false

	return false



func _build_info() -> Dictionary:

	var round_index_value: Variant = _safe_get(main_node, "round_index")

	var match_over_value: Variant = _safe_get(main_node, "match_over")

	return {

		"round_index": int(round_index_value) if round_index_value != null else 0,

		"match_over": bool(match_over_value) if match_over_value != null else false

	}



func _safe_get(node: Node, property_name: String) -> Variant:

	if node == null:

		return null

	if node.has_method("get"):

		return node.get(property_name)

	return null



func _reset_tracking() -> void:

	frame_number = 0

	last_alive = {1: true, 2: true}

	round_steps = 0

	round_elapsed = 0.0

	_reset_round_stats()



func _reset_episode_metrics() -> void:

	episode_steps = 0

	episode_elapsed = 0.0

	episode_reward = {"1": 0.0, "2": 0.0}

	last_reward = {"1": 0.0, "2": 0.0}

	last_done = false

	round_steps = 0

	round_elapsed = 0.0

	_reset_round_stats()



func _load_json(path: String) -> Dictionary:

	if path == "":

		return {}

	if not FileAccess.file_exists(path):

		return {}

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:

		return {}

	var text := file.get_as_text()

	var parsed: Variant = JSON.parse_string(text)

	if parsed is Dictionary:

		return parsed as Dictionary

	return {}



func _ensure_log_header() -> void:

	if log_path == "":

		return

	if FileAccess.file_exists(log_path):

		return

	var file := FileAccess.open(log_path, FileAccess.WRITE)

	if file == null:

		return

	file.store_line("timestamp,episode,steps,match_score_p1,match_score_p2,winner,wins_p1,wins_p2,total_steps,watch_mode,time_scale")



func _log_episode() -> void:

	if not logging_enabled:

		return

	if log_path == "":

		return

	_ensure_log_header()

	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)

	if file == null:

		return

	file.seek_end()

	var reward_p1 := float(last_match_score.get(1, 0.0))

	var reward_p2 := float(last_match_score.get(2, 0.0))

	var wins_p1 := int(wins_count.get(1, 0))

	var wins_p2 := int(wins_count.get(2, 0))

	var timestamp := int(Time.get_unix_time_from_system())

	var line := "%d,%d,%d,%.4f,%.4f,%d,%d,%d,%d,%d,%.2f" % [

		timestamp,

		episode_index,

		last_episode_steps,

		reward_p1,

		reward_p2,

		last_winner,

		wins_p1,

		wins_p2,

		total_steps,

		int(watch_mode),

		float(Engine.time_scale)

	]

	file.store_line(line)



func _apply_time_scale() -> void:

	var target := time_scale

	var is_training_runtime := OS.has_method("get_cmdline_user_args") and OS.get_cmdline_user_args().has("--training")

	var is_headless_runtime := DisplayServer.get_name() == "headless" or OS.has_feature("headless")

	if watch_mode or not (is_headless_runtime or is_training_runtime):

		target = min(time_scale, 1.0)

	Engine.time_scale = clamp(target, 0.01, 20.0)



func _ensure_external_policies() -> void:

	if bool(external_control_players.get(1, true)) and bot_driver_one and bot_driver_one.has_method("set_policy"):

		bot_driver_one.set_policy("external")

		bot_driver_one.set_enabled(true)

	if bool(external_control_players.get(2, true)) and bot_driver_two and bot_driver_two.has_method("set_policy"):

		bot_driver_two.set_policy("external")

		bot_driver_two.set_enabled(true)
