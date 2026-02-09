extends "res://scripts/modules/reward_shaper.gd"
class_name RewardShaperTunable

var config_path := ""
var reload_interval_sec := 0.5

var _cfg_mtime := 0
var _cfg_last_reload_at := 0.0
var _cfg: Dictionary = {}

var _last_alive := {1: true, 2: true}
var _time_since_shot := {1: 0.0, 2: 0.0}
var _prev_arrows := {1: 0, 2: 0}
var _prev_shoot_timer := {1: 0.0, 2: 0.0}
var _pending_shot_age := {1: -1.0, 2: -1.0}


func configure(path: String, interval_sec: float = 0.5) -> void:
	config_path = path
	reload_interval_sec = maxf(0.05, float(interval_sec))
	_cfg_mtime = 0
	_cfg_last_reload_at = 0.0
	_cfg = {}


func reset(manager) -> void:
	_last_alive = {1: true, 2: true}
	_time_since_shot = {1: 0.0, 2: 0.0}
	_prev_arrows = {1: 0, 2: 0}
	_prev_shoot_timer = {1: 0.0, 2: 0.0}
	_pending_shot_age = {1: -1.0, 2: -1.0}
	_reload_if_needed(manager, true)
	if manager != null:
		manager.super_reward_last_components = {1: {}, 2: {}}


func compute(manager, obs_p1: Dictionary, obs_p2: Dictionary, step_delta: float) -> Dictionary:
	_reload_if_needed(manager, false)
	if manager == null:
		return {"1": 0.0, "2": 0.0}

	var alive_p1: bool = manager._is_alive(obs_p1)
	var alive_p2: bool = manager._is_alive(obs_p2)
	var r1 := 0.0
	var r2 := 0.0
	var comp1: Dictionary = {}
	var comp2: Dictionary = {}

	var base1 := 0.0
	var base2 := 0.0
	base1 += manager._get_bot_reward(1, "time_without_kill", manager.reward_time_without_kill, "step") * step_delta
	base2 += manager._get_bot_reward(2, "time_without_kill", manager.reward_time_without_kill, "step") * step_delta
	if alive_p1:
		base1 += manager._get_bot_reward(1, "time_alive", manager.reward_time_alive, "alive") * step_delta
	if alive_p2:
		base2 += manager._get_bot_reward(2, "time_alive", manager.reward_time_alive, "alive") * step_delta

	var death1 := 0.0
	var death2 := 0.0
	var kill1 := 0.0
	var kill2 := 0.0
	if bool(_last_alive.get(1, true)) and not alive_p1:
		death1 += manager._get_bot_reward(1, "death", manager.reward_death)
		kill2 += manager._get_bot_reward(2, "kill", manager.reward_kill)
		manager.round_deaths[1] = int(manager.round_deaths.get(1, 0)) + 1
		manager.round_kills[2] = int(manager.round_kills.get(2, 0)) + 1
	if bool(_last_alive.get(2, true)) and not alive_p2:
		death2 += manager._get_bot_reward(2, "death", manager.reward_death)
		kill1 += manager._get_bot_reward(1, "kill", manager.reward_kill)
		manager.round_deaths[2] = int(manager.round_deaths.get(2, 0)) + 1
		manager.round_kills[1] = int(manager.round_kills.get(1, 0)) + 1
	_last_alive[1] = alive_p1
	_last_alive[2] = alive_p2

	r1 += base1 + kill1 + death1
	r2 += base2 + kill2 + death2
	comp1["base"] = base1
	comp2["base"] = base2
	comp1["kill"] = kill1
	comp2["kill"] = kill2
	comp1["death"] = death1
	comp2["death"] = death2

	var input_cfg: Dictionary = _cfg.get("inputs", {}) if _cfg.has("inputs") and _cfg["inputs"] is Dictionary else {}
	var dist_cfg: Dictionary = _cfg.get("distance", {}) if _cfg.has("distance") and _cfg["distance"] is Dictionary else {}
	var events_cfg: Dictionary = _cfg.get("events", {}) if _cfg.has("events") and _cfg["events"] is Dictionary else {}
	var shoot_cfg: Dictionary = _cfg.get("shoot", {}) if _cfg.has("shoot") and _cfg["shoot"] is Dictionary else {}

	var in1 := _score_inputs(manager, 1, obs_p1, input_cfg, step_delta)
	var in2 := _score_inputs(manager, 2, obs_p2, input_cfg, step_delta)
	r1 += in1
	r2 += in2
	comp1["inputs"] = in1
	comp2["inputs"] = in2

	var d1 := _score_distance(obs_p1, dist_cfg)
	var d2 := _score_distance(obs_p2, dist_cfg)
	r1 += d1
	r2 += d2
	comp1["distance"] = d1
	comp2["distance"] = d2

	var ev := _score_events(events_cfg, alive_p1, alive_p2)
	r1 += float(ev.get(1, 0.0))
	r2 += float(ev.get(2, 0.0))
	comp1["events"] = float(ev.get(1, 0.0))
	comp2["events"] = float(ev.get(2, 0.0))

	var s_out := _score_shooting(manager, obs_p1, obs_p2, shoot_cfg, step_delta)
	r1 += float(s_out.get(1, 0.0))
	r2 += float(s_out.get(2, 0.0))
	comp1["shoot"] = float(s_out.get(1, 0.0))
	comp2["shoot"] = float(s_out.get(2, 0.0))
	comp1["time_since_shot"] = float(_time_since_shot.get(1, 0.0))
	comp2["time_since_shot"] = float(_time_since_shot.get(2, 0.0))

	manager.super_reward_last_components = {1: comp1, 2: comp2}
	return {"1": r1, "2": r2}


func _score_events(cfg: Dictionary, alive_p1: bool, alive_p2: bool) -> Dictionary:
	var out := {1: 0.0, 2: 0.0}
	if cfg.is_empty():
		return out
	var kill_bonus := float(cfg.get("kill", 0.0))
	if kill_bonus == 0.0:
		return out
	var killed_p2 := bool(_last_alive.get(2, true)) and not alive_p2
	var killed_p1 := bool(_last_alive.get(1, true)) and not alive_p1
	if killed_p2:
		out[1] = float(out.get(1, 0.0)) + kill_bonus
	if killed_p1:
		out[2] = float(out.get(2, 0.0)) + kill_bonus
	return out


func _score_inputs(manager, player_id: int, obs: Dictionary, cfg: Dictionary, step_delta: float) -> float:
	if manager == null or cfg.is_empty():
		return 0.0
	var p = manager.player_one if player_id == 1 else manager.player_two
	if p == null:
		return 0.0
	var frame: Dictionary = manager._get_player_frame(p)
	if frame.is_empty():
		return 0.0
	var total := 0.0
	var axis_cfg: Dictionary = cfg.get("axis", {}) if cfg.has("axis") and cfg["axis"] is Dictionary else {}
	if axis_cfg:
		var axis := float(frame.get("axis", 0.0))
		if axis < -0.1:
			total += float(axis_cfg.get("-1", axis_cfg.get("left", 0.0)))
		elif axis > 0.1:
			total += float(axis_cfg.get("1", axis_cfg.get("right", 0.0)))
		else:
			total += float(axis_cfg.get("0", axis_cfg.get("idle", 0.0)))

	for key in ["jump_pressed", "shoot_pressed", "shoot_is_pressed", "melee_pressed", "ult_pressed"]:
		if bool(frame.get(key, false)):
			total += float(cfg.get(key, 0.0))

	if frame.has("dash_pressed") and frame["dash_pressed"] is Array:
		var dash_arr: Array = frame["dash_pressed"]
		if dash_arr.size() > 0:
			total += float(cfg.get("dash_pressed", 0.0))

	var per_second := float(cfg.get("per_second", 0.0))
	if per_second != 0.0:
		total += per_second * step_delta
	return total


func _score_distance(obs: Dictionary, cfg: Dictionary) -> float:
	if cfg.is_empty():
		return 0.0
	var dist := float(obs.get("distance", 0.0))
	var target := float(cfg.get("target", 360.0))
	var tol := float(cfg.get("tolerance", 120.0))
	var weight := float(cfg.get("weight", 0.0))
	if weight == 0.0:
		return 0.0
	var diff := absf(dist - target)
	var scaled := diff / maxf(1.0, tol)
	var v := -scaled
	var too_close := float(cfg.get("too_close", 0.0))
	var close_pen := float(cfg.get("close_penalty", 0.0))
	if too_close > 0.0 and dist < too_close:
		v += close_pen * ((too_close - dist) / maxf(1.0, too_close))
	var too_far := float(cfg.get("too_far", 0.0))
	var far_pen := float(cfg.get("far_penalty", 0.0))
	if too_far > 0.0 and dist > too_far:
		v += far_pen * ((dist - too_far) / maxf(1.0, too_far))
	return weight * v


func _score_shooting(manager, obs_p1: Dictionary, obs_p2: Dictionary, cfg: Dictionary, step_delta: float) -> Dictionary:
	var out := {1: 0.0, 2: 0.0}
	if cfg.is_empty() or manager == null:
		return out
	var miss_window := float(cfg.get("miss_window_sec", 1.25))
	var hit_window := float(cfg.get("hit_window_sec", 0.8))
	var fire_reward := float(cfg.get("shot_fired", 0.0))
	var miss_pen := float(cfg.get("shot_missed", 0.0))
	var hit_reward := float(cfg.get("shot_hit", 0.0))
	var no_shoot_pen_per_sec := float(cfg.get("no_shoot_per_sec", 0.0))
	var no_shoot_grace := float(cfg.get("no_shoot_grace_sec", 0.0))

	for pid in [1, 2]:
		_time_since_shot[pid] = float(_time_since_shot.get(pid, 0.0)) + step_delta
		var obs := obs_p1 if pid == 1 else obs_p2
		var raw: Dictionary = obs.get("raw", {}) if obs.has("raw") and obs["raw"] is Dictionary else {}
		var self_state: Dictionary = raw.get("self_state", {}) if raw.has("self_state") and raw["self_state"] is Dictionary else {}
		var shooter: Dictionary = self_state.get("shooter", {}) if self_state.has("shooter") and self_state["shooter"] is Dictionary else {}
		var shoot_timer := float(shooter.get("shoot_timer", 0.0))
		var prev_timer := float(_prev_shoot_timer.get(pid, 0.0))
		_prev_shoot_timer[pid] = shoot_timer

		var arrows := 0
		var self_snap: Dictionary = obs.get("self", {}) if obs.has("self") and obs["self"] is Dictionary else {}
		arrows = int(self_snap.get("arrows", 0))
		var prev_ar := int(_prev_arrows.get(pid, arrows))
		_prev_arrows[pid] = arrows
		var fired := (prev_timer <= 0.0001 and shoot_timer > 0.0001) or (arrows < prev_ar)
		if fired:
			_time_since_shot[pid] = 0.0
			_pending_shot_age[pid] = 0.0
			out[pid] = float(out.get(pid, 0.0)) + fire_reward

		var age := float(_pending_shot_age.get(pid, -1.0))
		if age >= 0.0:
			age += step_delta
			_pending_shot_age[pid] = age
			var opp_obs := obs_p2 if pid == 1 else obs_p1
			var opp_alive: bool = bool(manager._is_alive(opp_obs))
			if not opp_alive and age <= hit_window:
				_pending_shot_age[pid] = -1.0
				out[pid] = float(out.get(pid, 0.0)) + hit_reward
			elif age >= miss_window:
				_pending_shot_age[pid] = -1.0
				out[pid] = float(out.get(pid, 0.0)) + miss_pen

		if no_shoot_pen_per_sec != 0.0:
			var t := maxf(0.0, float(_time_since_shot.get(pid, 0.0)) - no_shoot_grace)
			out[pid] = float(out.get(pid, 0.0)) + (no_shoot_pen_per_sec * t * step_delta)

	return out


func _reload_if_needed(manager, force: bool) -> void:
	if config_path == "":
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if not force and (now - _cfg_last_reload_at) < reload_interval_sec:
		return
	_cfg_last_reload_at = now
	if not FileAccess.file_exists(config_path):
		return
	var mtime := int(FileAccess.get_modified_time(config_path))
	if not force and mtime == _cfg_mtime:
		return
	_cfg_mtime = mtime
	if manager != null and manager.has_method("_load_json"):
		_cfg = manager._load_json(config_path)
	else:
		_cfg = {}
	if _cfg.has("reload_interval_sec"):
		reload_interval_sec = maxf(0.05, float(_cfg.get("reload_interval_sec", reload_interval_sec)))
	if manager != null:
		manager.super_reward_cfg_path = config_path
		manager.super_reward_cfg_signature = str(mtime)
		manager.super_reward_cfg = _cfg.duplicate(true) if _cfg is Dictionary else {}
