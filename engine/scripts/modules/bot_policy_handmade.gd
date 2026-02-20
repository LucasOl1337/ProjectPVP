extends BotPolicyBase
class_name BotPolicyHandmade

var config_path := ""
var config_signature := ""

var tuning := {
	"keep_distance": 220.0,
	"shoot_range": 640.0,
	"min_shoot_distance": 20.0,
	"dash_range": 640.0,
	"dash_probability": 0.9,
	"melee_range": 85.0,
	"shoot_hold": 0.14,
	"decision_interval_ms": 50,
	"reaction_time_ms": 0,
	"aim_noise_degrees": 0.0,
	"shoot_y_tolerance": 140.0,
	"shoot_dx_min": 30.0
}

var metrics_cfg := {
	"enabled": false,
	"path": "user://handmade_metrics.jsonl",
	"flush_seconds": 1.0,
	"sample_every_steps": 10,
	"include_observation": false
}

var objectives_cfg := {
	"enabled": true,
	"pick_interval_ms": 80,
	"collect_arrow": {
		"enabled": true,
		"min_self_arrows": 1,
		"max_arrow_distance": 520.0,
		"prefer_when_opponent_distance_gt": 160.0
	},
	"recover_height": {
		"enabled": true,
		"dy_gt": 220.0
	},
	"safety": {
		"avoid_ledges": true,
		"avoid_walls": true
	}
}

var rules: Array = []

var _shoot_hold_remaining := 0.0
var _shoot_just_started := false
var _decision_accum_ms := 0
var _reaction_remaining_ms := 0
var _cached_action: Dictionary = {}
var _last_rule_id := ""
var _rule_next_allowed_ms: Dictionary = {}

var _objective_accum_ms := 0
var _cached_objective_id := ""

var _rng := RandomNumberGenerator.new()
var _metrics: Dictionary = {}
var _metrics_file: FileAccess = null
var _metrics_next_flush_ms := 0

func _init() -> void:
	policy_id = "handmade"
	_rng.randomize()
	_reset_metrics()

func configure(config: Dictionary) -> void:
	var profile := String(config.get("profile", "default")).strip_edges().to_lower()
	if profile == "":
		profile = "default"
	config_path = String(config.get("config_path", "res://BOTS/profiles/%s/handmade.json" % profile))
	_reload_if_needed(true)

func reset() -> void:
	_shoot_hold_remaining = 0.0
	_shoot_just_started = false
	_decision_accum_ms = 0
	_reaction_remaining_ms = 0
	_cached_action = {}
	_last_rule_id = ""
	_rule_next_allowed_ms.clear()
	_objective_accum_ms = 0
	_cached_objective_id = ""
	_reset_metrics()
	_close_metrics_file()

func select_action(observation: Dictionary) -> Dictionary:
	_reload_if_needed(false)
	var dt := float(observation.get("delta", 0.0))
	if _shoot_hold_remaining > 0.0:
		_shoot_hold_remaining = max(_shoot_hold_remaining - dt, 0.0)
	_shoot_just_started = false

	var dt_ms := int(round(dt * 1000.0))
	_decision_accum_ms += maxi(dt_ms, 0)
	if _reaction_remaining_ms > 0:
		_reaction_remaining_ms = maxi(_reaction_remaining_ms - maxi(dt_ms, 0), 0)
		_record_step(observation, _cached_action, _last_rule_id)
		return _cached_action.duplicate(true)

	if _decision_accum_ms < int(tuning.get("decision_interval_ms", 60)) and not _cached_action.is_empty():
		_record_step(observation, _cached_action, _last_rule_id)
		return _cached_action.duplicate(true)
	_decision_accum_ms = 0

	var decision := _compute_action(observation)
	_cached_action = decision.action.duplicate(true)
	_last_rule_id = String(decision.get("rule_id", ""))
	var reaction_ms := int(tuning.get("reaction_time_ms", 0))
	if reaction_ms > 0:
		_reaction_remaining_ms = reaction_ms
	_record_step(observation, _cached_action, _last_rule_id)
	return _cached_action.duplicate(true)

func get_metrics() -> Dictionary:
	return _metrics.duplicate(true)

func _compute_action(observation: Dictionary) -> Dictionary:
	var delta: Vector2 = observation.get("delta_position", Vector2.ZERO)
	if not (delta is Vector2):
		delta = Vector2.ZERO
	var distance := float(observation.get("distance", delta.length()))
	var self_state: Dictionary = observation.get("self", {}) if observation.get("self") is Dictionary else {}
	var facing := int(self_state.get("facing", 1))
	var arrows := int(self_state.get("arrows", 0))
	var dx := float(delta.x)
	var dy := float(delta.y)
	var abs_dx := absf(dx)

	var axis := 0.0
	var keep_distance := float(tuning.get("keep_distance", 120.0))
	if arrows <= 0:
		keep_distance = minf(keep_distance, 80.0)
	var backoff_threshold := keep_distance * 0.6
	if abs_dx > keep_distance:
		axis = sign(dx)
	elif abs_dx < backoff_threshold:
		if abs_dx < 8.0:
			axis = -float(facing)
		else:
			axis = -sign(dx)

	var aim := Vector2(facing, 0)
	if distance > 0.0:
		aim = delta.normalized()
	aim = _apply_aim_noise(aim)

	var min_shoot_distance := float(tuning.get("min_shoot_distance", 40.0))
	var shoot_range := float(tuning.get("shoot_range", 520.0))
	var melee_range := float(tuning.get("melee_range", 85.0))
	var dash_range := float(tuning.get("dash_range", 640.0))
	var dash_probability := float(tuning.get("dash_probability", 0.9))
	var want_shoot := arrows > 0 and distance > min_shoot_distance and distance < shoot_range
	var melee := distance < melee_range
	var jump := dy < -120.0 and abs_dx > 80.0
	var dash_pressed: Array = []
	if distance > dash_range and _rng.randf() < clampf(dash_probability, 0.0, 1.0):
		dash_pressed = ["r1"]
	var shoot_y_tolerance := float(tuning.get("shoot_y_tolerance", 140.0))
	var shoot_dx_min := float(tuning.get("shoot_dx_min", 30.0))
	if want_shoot and abs_dx > shoot_dx_min and absf(dy) < shoot_y_tolerance:
		axis = 0.0
		melee = false
		jump = false
		dash_pressed = []

	var chosen_rule := ""
	var overrides: Dictionary = {}
	var objective_id := _select_objective(observation)
	var now_ms := int(Time.get_ticks_msec())
	for rule_value in rules:
		if not (rule_value is Dictionary):
			continue
		var rule: Dictionary = rule_value
		var rule_id := String(rule.get("id", ""))
		if rule_id != "":
			var next_ok := int(_rule_next_allowed_ms.get(rule_id, 0))
			if now_ms < next_ok:
				continue
		var when_value: Variant = rule.get("when", {})
		var when: Dictionary = when_value as Dictionary if when_value is Dictionary else {}
		if not _match_when(when, observation, objective_id):
			continue
		overrides = rule.get("do", {}) if rule.get("do", {}) is Dictionary else {}
		chosen_rule = rule_id
		var cooldown_ms := int(rule.get("cooldown_ms", 0))
		if rule_id != "" and cooldown_ms > 0:
			_rule_next_allowed_ms[rule_id] = now_ms + cooldown_ms
		break

	var applied_objective := _apply_objective(objective_id, observation, axis, aim, want_shoot, melee, jump, dash_pressed, delta, distance, facing)
	axis = applied_objective.axis
	aim = applied_objective.aim
	want_shoot = applied_objective.want_shoot
	melee = applied_objective.melee
	jump = applied_objective.jump
	dash_pressed = applied_objective.dash_pressed

	if not overrides.is_empty():
		var applied := _apply_overrides(overrides, axis, aim, want_shoot, melee, jump, dash_pressed, delta, distance, facing)
		axis = applied.axis
		aim = applied.aim
		want_shoot = applied.want_shoot
		melee = applied.melee
		jump = applied.jump
		dash_pressed = applied.dash_pressed

	var shoot_hold_seconds: float = maxf(0.01, float(tuning.get("shoot_hold", 0.09)))
	if want_shoot and _shoot_hold_remaining <= 0.0:
		_shoot_hold_remaining = shoot_hold_seconds
		_shoot_just_started = true
	var shoot_is_pressed := _shoot_hold_remaining > 0.0
	var shoot_pressed := _shoot_just_started

	var actions := {
		"left": axis < 0.0,
		"right": axis > 0.0,
		"up": false,
		"down": false
	}

	var action := {
		"axis": axis,
		"aim": aim,
		"jump_pressed": jump,
		"shoot_pressed": shoot_pressed,
		"shoot_is_pressed": shoot_is_pressed,
		"melee_pressed": melee,
		"ult_pressed": false,
		"dash_pressed": dash_pressed,
		"actions": actions,
		"debug_objective": objective_id,
		"debug_rule": chosen_rule,
		"debug_distance": distance
	}

	return {"action": action, "rule_id": chosen_rule}

func _apply_overrides(overrides: Dictionary, axis: float, aim: Vector2, want_shoot: bool, melee: bool, jump: bool, dash_pressed: Array, delta: Vector2, distance: float, facing: int) -> Dictionary:
	var axis_out := axis
	if overrides.has("axis"):
		var v: Variant = overrides["axis"]
		if v is String:
			var s := String(v)
			if s == "toward":
				axis_out = sign(delta.x)
			elif s == "away":
				axis_out = -sign(delta.x)
			elif s == "stop":
				axis_out = 0.0
		elif v is int or v is float:
			axis_out = clampf(float(v), -1.0, 1.0)

	var aim_out := aim
	if overrides.has("aim"):
		var a: Variant = overrides["aim"]
		if a is String:
			var s2 := String(a)
			if s2 == "toward":
				if distance > 0.0:
					aim_out = delta.normalized()
				else:
					aim_out = Vector2(facing, 0)
			elif s2 == "facing":
				aim_out = Vector2(facing, 0)
		elif a is Array:
			var arr: Array = a as Array
			if arr.size() >= 2:
				aim_out = Vector2(float(arr[0]), float(arr[1]))
		elif a is Dictionary:
			var d: Dictionary = a as Dictionary
			if d.has("x") and d.has("y"):
				aim_out = Vector2(float(d["x"]), float(d["y"]))
	if aim_out.length() > 0.0:
		aim_out = aim_out.normalized()
	aim_out = _apply_aim_noise(aim_out)

	var want_shoot_out := want_shoot
	if overrides.has("shoot"):
		var s3: Variant = overrides["shoot"]
		if s3 is bool:
			want_shoot_out = bool(s3)
		elif s3 is String:
			want_shoot_out = String(s3) != "off"

	var melee_out := melee
	if overrides.has("melee"):
		melee_out = bool(overrides["melee"])
	var jump_out := jump
	if overrides.has("jump"):
		jump_out = bool(overrides["jump"])

	var dash_out := dash_pressed.duplicate()
	if overrides.has("dash"):
		var dash_v: Variant = overrides["dash"]
		if dash_v is bool:
			dash_out = ["r1"] if bool(dash_v) else []
		elif dash_v is String:
			var dash_s := String(dash_v)
			if dash_s == "toward":
				dash_out = ["r1"]
				if not overrides.has("aim"):
					if distance > 0.0:
						aim_out = delta.normalized()
					else:
						aim_out = Vector2(facing, 0)
			elif dash_s == "away":
				dash_out = ["r1"]
				if not overrides.has("aim"):
					if distance > 0.0:
						aim_out = (-delta).normalized()
					else:
						aim_out = Vector2(-facing, 0)
			else:
				dash_out = [dash_s]
		elif dash_v is Array:
			dash_out = (dash_v as Array).duplicate()

	return {
		"axis": axis_out,
		"aim": aim_out,
		"want_shoot": want_shoot_out,
		"melee": melee_out,
		"jump": jump_out,
		"dash_pressed": dash_out
	}

func _select_objective(observation: Dictionary) -> String:
	if not bool(objectives_cfg.get("enabled", true)):
		_cached_objective_id = ""
		_objective_accum_ms = 0
		return ""
	var dt := float(observation.get("delta", 0.0))
	var dt_ms := int(round(dt * 1000.0))
	_objective_accum_ms += maxi(dt_ms, 0)
	var pick_interval_ms := int(objectives_cfg.get("pick_interval_ms", 80))
	if _cached_objective_id != "" and _objective_accum_ms < pick_interval_ms:
		return _cached_objective_id
	_objective_accum_ms = 0
	_cached_objective_id = _compute_objective_now(observation)
	return _cached_objective_id

func _compute_objective_now(observation: Dictionary) -> String:
	var delta: Vector2 = observation.get("delta_position", Vector2.ZERO)
	if not (delta is Vector2):
		delta = Vector2.ZERO
	var distance := float(observation.get("distance", delta.length()))
	var self_state: Dictionary = observation.get("self", {}) if observation.get("self") is Dictionary else {}
	var arrows := int(self_state.get("arrows", 0))
	var collect_cfg_base: Variant = objectives_cfg.get("collect_arrow", {})
	var collect_cfg_base_dict: Dictionary = collect_cfg_base as Dictionary if collect_cfg_base is Dictionary else {}
	var opp_far_threshold := float(collect_cfg_base_dict.get("prefer_when_opponent_distance_gt", 160.0))

	var recover_cfg: Dictionary = objectives_cfg.get("recover_height", {}) if objectives_cfg.get("recover_height") is Dictionary else {}
	if bool(recover_cfg.get("enabled", true)):
		var dy_mag := float(recover_cfg.get("dy_gt", 220.0))
		if delta.y < -dy_mag:
			return "recover_height"

	var collect_cfg: Dictionary = objectives_cfg.get("collect_arrow", {}) if objectives_cfg.get("collect_arrow") is Dictionary else {}
	if bool(collect_cfg.get("enabled", true)):
		var min_self_arrows := int(collect_cfg.get("min_self_arrows", 1))
		var max_arrow_distance := float(collect_cfg.get("max_arrow_distance", 520.0))
		if arrows < min_self_arrows:
			var arrow: Dictionary = self_state.get("nearest_arrow", {}) if self_state.get("nearest_arrow") is Dictionary else {}
			if not arrow.is_empty():
				var arrow_dist := float(arrow.get("distance", INF))
				var is_stuck := bool(arrow.get("is_stuck", true))
				var prefer_when_arrow_distance_lt := float(collect_cfg.get("prefer_when_arrow_distance_lt", 180.0))
				if is_stuck and arrow_dist < max_arrow_distance and (distance > opp_far_threshold or arrow_dist < prefer_when_arrow_distance_lt):
					return "collect_arrow"

	return "fight"

func _apply_objective(objective_id: String, observation: Dictionary, axis: float, aim: Vector2, want_shoot: bool, melee: bool, jump: bool, dash_pressed: Array, delta: Vector2, distance: float, facing: int) -> Dictionary:
	var axis_out := axis
	var aim_out := aim
	var want_shoot_out := want_shoot
	var melee_out := melee
	var jump_out := jump
	var dash_out := dash_pressed.duplicate()
	var self_state: Dictionary = observation.get("self", {}) if observation.get("self") is Dictionary else {}
	var self_sensors: Dictionary = self_state.get("sensors", {}) if self_state.get("sensors") is Dictionary else {}

	if objective_id == "collect_arrow":
		var arrow: Dictionary = self_state.get("nearest_arrow", {}) if self_state.get("nearest_arrow") is Dictionary else {}
		if not arrow.is_empty():
			var arrow_delta: Variant = arrow.get("delta_position", Vector2.ZERO)
			if arrow_delta is Vector2:
				axis_out = sign((arrow_delta as Vector2).x)
				want_shoot_out = false
				melee_out = false

	elif objective_id == "recover_height":
		want_shoot_out = false
		melee_out = false
		var recover_base: Variant = objectives_cfg.get("recover_height", {})
		var recover_dict: Dictionary = recover_base as Dictionary if recover_base is Dictionary else {}
		if delta.y < -float(recover_dict.get("dy_gt", 220.0)):
			jump_out = true
			axis_out = sign(delta.x)

	var safety_cfg: Dictionary = objectives_cfg.get("safety", {}) if objectives_cfg.get("safety") is Dictionary else {}
	var avoid_ledges := bool(safety_cfg.get("avoid_ledges", true))
	var avoid_walls := bool(safety_cfg.get("avoid_walls", true))
	if axis_out != 0.0:
		var moving_dir := int(sign(axis_out))
		if moving_dir == facing:
			if avoid_ledges and bool(self_sensors.get("ledge_ahead", false)):
				axis_out = 0.0
			if avoid_walls and bool(self_sensors.get("wall_ahead", false)):
				axis_out = 0.0

	if aim_out.length() > 0.0:
		aim_out = aim_out.normalized()
	aim_out = _apply_aim_noise(aim_out)

	return {
		"axis": axis_out,
		"aim": aim_out,
		"want_shoot": want_shoot_out,
		"melee": melee_out,
		"jump": jump_out,
		"dash_pressed": dash_out
	}

func _match_when(when: Dictionary, observation: Dictionary, objective_id: String) -> bool:
	if when.is_empty():
		return true
	var delta: Vector2 = observation.get("delta_position", Vector2.ZERO)
	if not (delta is Vector2):
		delta = Vector2.ZERO
	var distance := float(observation.get("distance", delta.length()))
	var self_state: Dictionary = observation.get("self", {}) if observation.get("self", {}) is Dictionary else {}
	var opp_state: Dictionary = observation.get("opponent", {}) if observation.get("opponent", {}) is Dictionary else {}
	var self_sensors: Dictionary = self_state.get("sensors", {}) if self_state.get("sensors", {}) is Dictionary else {}
	for key in when.keys():
		var value: Variant = when[key]
		match String(key):
			"objective_is":
				if value is String:
					if objective_id != String(value):
						return false
				elif value is Array:
					var ok := false
					for v in (value as Array):
						if objective_id == String(v):
							ok = true
							break
					if not ok:
						return false
				else:
					return false
			"distance_lt":
				if not (distance < float(value)):
					return false
			"distance_gt":
				if not (distance > float(value)):
					return false
			"dx_lt":
				if not (delta.x < float(value)):
					return false
			"dx_gt":
				if not (delta.x > float(value)):
					return false
			"dy_lt":
				if not (delta.y < float(value)):
					return false
			"dy_gt":
				if not (delta.y > float(value)):
					return false
			"self_on_floor":
				if bool(self_state.get("on_floor", false)) != bool(value):
					return false
			"opponent_on_floor":
				if bool(opp_state.get("on_floor", false)) != bool(value):
					return false
			"self_arrows_gt":
				if not (int(self_state.get("arrows", 0)) > int(value)):
					return false
			"self_arrows_lt":
				if not (int(self_state.get("arrows", 0)) < int(value)):
					return false
			"opponent_arrows_gt":
				if not (int(opp_state.get("arrows", 0)) > int(value)):
					return false
			"opponent_arrows_lt":
				if not (int(opp_state.get("arrows", 0)) < int(value)):
					return false
			"nearest_arrow_distance_lt":
				var arrow: Dictionary = self_state.get("nearest_arrow", {}) if self_state.get("nearest_arrow", {}) is Dictionary else {}
				if arrow.is_empty():
					return false
				if not (float(arrow.get("distance", INF)) < float(value)):
					return false
			"nearest_arrow_distance_gt":
				var arrow2: Dictionary = self_state.get("nearest_arrow", {}) if self_state.get("nearest_arrow", {}) is Dictionary else {}
				if arrow2.is_empty():
					return false
				if not (float(arrow2.get("distance", 0.0)) > float(value)):
					return false
			"self_sensor_wall_ahead":
				if bool(self_sensors.get("wall_ahead", false)) != bool(value):
					return false
			"self_sensor_ledge_ahead":
				if bool(self_sensors.get("ledge_ahead", false)) != bool(value):
					return false
			"self_sensor_ground_distance_lt":
				if not (float(self_sensors.get("ground_distance", INF)) < float(value)):
					return false
			"self_sensor_ground_distance_gt":
				if not (float(self_sensors.get("ground_distance", 0.0)) > float(value)):
					return false
			"self_sensor_front_wall_distance_lt":
				if not (float(self_sensors.get("front_wall_distance", INF)) < float(value)):
					return false
			"self_sensor_front_wall_distance_gt":
				if not (float(self_sensors.get("front_wall_distance", 0.0)) > float(value)):
					return false
			"self_sensor_ceiling_distance_lt":
				if not (float(self_sensors.get("ceiling_distance", INF)) < float(value)):
					return false
			"self_sensor_ceiling_distance_gt":
				if not (float(self_sensors.get("ceiling_distance", 0.0)) > float(value)):
					return false
			"self_sensor_ledge_ground_distance_lt":
				if not (float(self_sensors.get("ledge_ground_distance", INF)) < float(value)):
					return false
			"self_sensor_ledge_ground_distance_gt":
				if not (float(self_sensors.get("ledge_ground_distance", 0.0)) > float(value)):
					return false
			_:
				return false
	return true

func _reload_if_needed(force: bool) -> void:
	if config_path == "":
		return
	var signature := _file_signature(config_path)
	if signature == "":
		return
	if not force and signature == config_signature:
		return
	config_signature = signature
	var loaded := _load_json(config_path)
	if loaded.is_empty():
		return
	var new_tuning := tuning.duplicate(true)
	if loaded.has("tuning") and loaded["tuning"] is Dictionary:
		new_tuning = _deep_merge_dict(new_tuning, loaded["tuning"] as Dictionary)
	tuning = new_tuning
	var new_metrics := metrics_cfg.duplicate(true)
	if loaded.has("metrics") and loaded["metrics"] is Dictionary:
		new_metrics = _deep_merge_dict(new_metrics, loaded["metrics"] as Dictionary)
	metrics_cfg = new_metrics
	var new_objectives := objectives_cfg.duplicate(true)
	if loaded.has("objectives") and loaded["objectives"] is Dictionary:
		new_objectives = _deep_merge_dict(new_objectives, loaded["objectives"] as Dictionary)
	objectives_cfg = new_objectives
	if loaded.has("rules") and loaded["rules"] is Array:
		rules = (loaded["rules"] as Array).duplicate(true)
	else:
		rules = []
	_reset_metrics()
	_close_metrics_file()

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

func _deep_merge_dict(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in overlay.keys():
		var v: Variant = overlay[key]
		if out.has(key) and out[key] is Dictionary and v is Dictionary:
			out[key] = _deep_merge_dict(out[key] as Dictionary, v as Dictionary)
		else:
			out[key] = v
	return out

func _file_signature(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var modified: int = int(FileAccess.get_modified_time(path))
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var length: int = int(file.get_length())
	return "%d:%d" % [modified, length]

func _apply_aim_noise(aim: Vector2) -> Vector2:
	var degrees := float(tuning.get("aim_noise_degrees", 0.0))
	if degrees <= 0.0:
		return aim
	var radians := deg_to_rad(_rng.randf_range(-degrees, degrees))
	return aim.rotated(radians)

func _reset_metrics() -> void:
	_metrics = {
		"policy": "handmade",
		"config_path": config_path,
		"steps": 0,
		"last_rule": "",
		"rule_hits": {},
		"avg_distance": 0.0
	}

func _record_step(observation: Dictionary, action: Dictionary, rule_id: String) -> void:
	_metrics["steps"] = int(_metrics.get("steps", 0)) + 1
	_metrics["last_rule"] = rule_id
	var distance := float(observation.get("distance", 0.0))
	var steps := int(_metrics.get("steps", 1))
	var prev_avg := float(_metrics.get("avg_distance", 0.0))
	_metrics["avg_distance"] = prev_avg + (distance - prev_avg) / float(maxi(steps, 1))
	if rule_id != "":
		var hits: Dictionary = _metrics.get("rule_hits", {}) if _metrics.get("rule_hits", {}) is Dictionary else {}
		hits[rule_id] = int(hits.get(rule_id, 0)) + 1
		_metrics["rule_hits"] = hits

	if not bool(metrics_cfg.get("enabled", false)):
		return
	var sample_every := int(metrics_cfg.get("sample_every_steps", 10))
	if sample_every <= 0:
		sample_every = 1
	if (steps % sample_every) != 0:
		return
	_maybe_open_metrics_file()
	if _metrics_file == null:
		return
	var payload := {
		"t_ms": int(Time.get_ticks_msec()),
		"frame": int(observation.get("frame", 0)),
		"rule": rule_id,
		"distance": distance,
		"axis": float(action.get("axis", 0.0)),
		"shoot": bool(action.get("shoot_is_pressed", false)),
		"melee": bool(action.get("melee_pressed", false)),
		"jump": bool(action.get("jump_pressed", false)),
		"dash": (action.get("dash_pressed", []) as Array).size() > 0 if action.get("dash_pressed", []) is Array else false
	}
	if bool(metrics_cfg.get("include_observation", false)):
		payload["obs"] = _encode_observation_small(observation)
	_metrics_file.store_line(JSON.stringify(payload))
	_maybe_flush_metrics()

func _encode_observation_small(observation: Dictionary) -> Dictionary:
	var delta: Vector2 = observation.get("delta_position", Vector2.ZERO)
	if not (delta is Vector2):
		delta = Vector2.ZERO
	var self_state: Dictionary = observation.get("self", {}) if observation.get("self", {}) is Dictionary else {}
	var opp_state: Dictionary = observation.get("opponent", {}) if observation.get("opponent", {}) is Dictionary else {}
	return {
		"distance": float(observation.get("distance", 0.0)),
		"delta": [delta.x, delta.y],
		"self": {"arrows": int(self_state.get("arrows", 0)), "on_floor": bool(self_state.get("on_floor", false))},
		"opponent": {"arrows": int(opp_state.get("arrows", 0)), "on_floor": bool(opp_state.get("on_floor", false))}
	}

func _maybe_open_metrics_file() -> void:
	if _metrics_file != null:
		return
	var path := String(metrics_cfg.get("path", "user://handmade_metrics.jsonl"))
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE_READ)
	if f == null:
		return
	_metrics_file = f
	_metrics_file.seek_end()
	_metrics_next_flush_ms = int(Time.get_ticks_msec()) + int(float(metrics_cfg.get("flush_seconds", 1.0)) * 1000.0)

func _maybe_flush_metrics() -> void:
	if _metrics_file == null:
		return
	var now := int(Time.get_ticks_msec())
	if now < _metrics_next_flush_ms:
		return
	_metrics_file.flush()
	_metrics_next_flush_ms = now + int(float(metrics_cfg.get("flush_seconds", 1.0)) * 1000.0)

func _close_metrics_file() -> void:
	if _metrics_file == null:
		return
	_metrics_file.flush()
	_metrics_file.close()
	_metrics_file = null
	_metrics_next_flush_ms = 0
