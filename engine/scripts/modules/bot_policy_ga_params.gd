extends BotPolicyBase
class_name BotPolicyGAParams

const INF := 1.0e20

var genome_path := ""
var load_error := ""
var loaded := false

var genes: Dictionary = {}

var shoot_hold_remaining := 0.0
var shoot_cooldown_remaining := 0.0
var shoot_release_frame := false

var dash_cooldown_remaining := 0.0
var jump_cooldown_remaining := 0.0
var melee_cooldown_remaining := 0.0
var last_jump_intent := false
var last_melee_intent := false

var rng := RandomNumberGenerator.new()

static func _defaults_v1() -> Dictionary:
	return {
		"movement.keep_distance": 220.0,
		"movement.backoff_ratio": 0.6,
		"movement.approach_deadzone_x": 10.0,
		"shoot.min_distance": 20.0,
		"shoot.max_distance": 640.0,
		"shoot.y_tolerance": 140.0,
		"shoot.hold_seconds": 0.14,
		"shoot.intent_cooldown": 0.18,
		"shoot.dx_min": 30.0,
		"dash.use": true,
		"dash.range": 650.0,
		"dash.probability": 0.25,
		"dash.intent_cooldown": 0.35,
		"jump.chase_dy": 140.0,
		"jump.intent_cooldown": 0.25,
		"melee.range": 85.0,
		"melee.intent_cooldown": 0.30,
		"safety.avoid_ledges": true,
		"safety.avoid_walls": true,
		"safety.wall_stop_distance": 14.0,
		"safety.max_safe_drop_distance": 85.0,
		"safety.ceiling_block_distance": 18.0,
		"safety.air_ground_distance": 55.0,
		"objective.collect_arrow_weight": 0.7,
		"objective.fight_weight": 1.0,
		"objective.pick_interval": 0.08
	}

static func _spec_v1() -> Dictionary:
	return {
		"movement.keep_distance": {"type": "float", "min": 60.0, "max": 420.0},
		"movement.backoff_ratio": {"type": "float", "min": 0.15, "max": 0.95},
		"movement.approach_deadzone_x": {"type": "float", "min": 0.0, "max": 40.0},
		"shoot.min_distance": {"type": "float", "min": 0.0, "max": 120.0},
		"shoot.max_distance": {"type": "float", "min": 120.0, "max": 900.0},
		"shoot.y_tolerance": {"type": "float", "min": 30.0, "max": 420.0},
		"shoot.hold_seconds": {"type": "float", "min": 0.05, "max": 0.30},
		"shoot.intent_cooldown": {"type": "float", "min": 0.0, "max": 0.8},
		"shoot.dx_min": {"type": "float", "min": 0.0, "max": 160.0},
		"dash.use": {"type": "bool"},
		"dash.range": {"type": "float", "min": 100.0, "max": 1200.0},
		"dash.probability": {"type": "float", "min": 0.0, "max": 1.0},
		"dash.intent_cooldown": {"type": "float", "min": 0.0, "max": 1.0},
		"jump.chase_dy": {"type": "float", "min": 40.0, "max": 520.0},
		"jump.intent_cooldown": {"type": "float", "min": 0.0, "max": 1.0},
		"melee.range": {"type": "float", "min": 30.0, "max": 180.0},
		"melee.intent_cooldown": {"type": "float", "min": 0.0, "max": 1.0},
		"safety.avoid_ledges": {"type": "bool"},
		"safety.avoid_walls": {"type": "bool"},
		"safety.wall_stop_distance": {"type": "float", "min": 0.0, "max": 90.0},
		"safety.max_safe_drop_distance": {"type": "float", "min": 0.0, "max": 420.0},
		"safety.ceiling_block_distance": {"type": "float", "min": 0.0, "max": 160.0},
		"safety.air_ground_distance": {"type": "float", "min": 0.0, "max": 260.0},
		"objective.collect_arrow_weight": {"type": "float", "min": 0.0, "max": 2.0},
		"objective.fight_weight": {"type": "float", "min": 0.0, "max": 2.0},
		"objective.pick_interval": {"type": "float", "min": 0.02, "max": 0.40}
	}

static func _clamp_genes_v1(input_genes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var defaults := _defaults_v1()
	var spec := _spec_v1()
	for key in spec.keys():
		var s: Dictionary = spec[key]
		if not input_genes.has(key):
			out[key] = defaults.get(key)
			continue
		if String(s.get("type", "float")) == "bool":
			out[key] = bool(input_genes.get(key, defaults.get(key, false)))
			continue
		var v := float(input_genes.get(key, defaults.get(key, 0.0)))
		if s.has("min"):
			v = maxf(float(s["min"]), v)
		if s.has("max"):
			v = minf(float(s["max"]), v)
		out[key] = v
	return out

func _init() -> void:
	policy_id = "ga_params"
	rng.randomize()

func configure(config: Dictionary) -> void:
	if config.has("genome_path"):
		var path := String(config.get("genome_path", ""))
		if path != genome_path:
			load_genome(path)

func load_genome(path: String) -> Dictionary:
	genome_path = path
	var ok := _load_genome(path)
	return {"ok": ok, "error": load_error, "path": genome_path}

func _load_genome(path: String) -> bool:
	loaded = false
	load_error = ""
	genes = {}
	if path.strip_edges() == "":
		load_error = "Caminho vazio"
		return false
	if not FileAccess.file_exists(path):
		load_error = "Arquivo não existe"
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		load_error = "JSON inválido"
		return false
	var payload := parsed as Dictionary
	if String(payload.get("schema_id", "")) != "ga_params_v1":
		load_error = "Schema incompatível"
		return false
	var g: Variant = payload.get("genes", {})
	if not (g is Dictionary):
		load_error = "Genes inválidos"
		return false
	genes = _clamp_genes_v1(g as Dictionary)
	_reset_controls()
	loaded = true
	return true

func _reset_controls() -> void:
	shoot_hold_remaining = 0.0
	shoot_cooldown_remaining = 0.0
	shoot_release_frame = false
	dash_cooldown_remaining = 0.0
	jump_cooldown_remaining = 0.0
	melee_cooldown_remaining = 0.0
	last_jump_intent = false
	last_melee_intent = false

static func _aim_from_obs(observation: Dictionary) -> Vector2:
	var delta: Variant = observation.get("delta_position", Vector2(1, 0))
	if delta is Vector2:
		var v: Vector2 = delta
		if v.length() > 0.0:
			return v.normalized()
		return Vector2(1, 0)
	if delta is Array:
		var arr: Array = delta
		if arr.size() >= 2:
			var v2 := Vector2(float(arr[0]), float(arr[1]))
			if v2.length() > 0.0:
				return v2.normalized()
	return Vector2(1, 0)

func select_action(observation: Dictionary) -> Dictionary:
	if not loaded:
		return {}

	var delta_time := float(observation.get("delta", 0.0))
	var self_state: Dictionary = {}
	var self_state_obj: Variant = observation.get("self")
	if self_state_obj is Dictionary:
		self_state = self_state_obj
	var match_state: Dictionary = {}
	var match_state_obj: Variant = observation.get("match")
	if match_state_obj is Dictionary:
		match_state = match_state_obj
	if bool(self_state.get("is_dead", false)) or (match_state.has("round_active") and not bool(match_state.get("round_active"))):
		_reset_controls()
		var aim0 := _aim_from_obs(observation)
		return {
			"axis": 0.0,
			"aim": aim0,
			"jump_pressed": false,
			"shoot_pressed": false,
			"shoot_is_pressed": false,
			"melee_pressed": false,
			"ult_pressed": false,
			"dash_pressed": [],
			"actions": {"left": false, "right": false, "up": false, "down": false}
		}

	shoot_cooldown_remaining = maxf(0.0, shoot_cooldown_remaining - delta_time)
	dash_cooldown_remaining = maxf(0.0, dash_cooldown_remaining - delta_time)
	jump_cooldown_remaining = maxf(0.0, jump_cooldown_remaining - delta_time)
	melee_cooldown_remaining = maxf(0.0, melee_cooldown_remaining - delta_time)

	var delta_pos: Variant = observation.get("delta_position", Vector2.ZERO)
	var dx := 0.0
	var dy := 0.0
	if delta_pos is Vector2:
		var dp: Vector2 = delta_pos
		dx = dp.x
		dy = dp.y
	elif delta_pos is Array:
		var arr2: Array = delta_pos
		if arr2.size() >= 2:
			dx = float(arr2[0])
			dy = float(arr2[1])

	var abs_dx := absf(dx)
	var abs_dy := absf(dy)
	var distance_v := sqrt(dx * dx + dy * dy)

	var facing := int(self_state.get("facing", 1))
	if facing == 0:
		facing = 1
	var arrows := int(self_state.get("arrows", 0))
	var sensors: Dictionary = {}
	var sensors_obj: Variant = self_state.get("sensors")
	if sensors_obj is Dictionary:
		sensors = sensors_obj
	var sensor_wall_ahead := bool(sensors.get("wall_ahead", false))
	var sensor_ledge_ahead := bool(sensors.get("ledge_ahead", false))
	var sensor_front_wall_distance := float(sensors.get("front_wall_distance", INF))
	var sensor_ground_distance := float(sensors.get("ground_distance", INF))
	var sensor_ceiling_distance := float(sensors.get("ceiling_distance", INF))
	var sensor_ledge_ground_distance := float(sensors.get("ledge_ground_distance", INF))

	var nearest_arrow: Dictionary = {}
	var nearest_arrow_obj: Variant = self_state.get("nearest_arrow")
	if nearest_arrow_obj is Dictionary:
		nearest_arrow = nearest_arrow_obj
	var arrow_delta := Vector2.ZERO
	var arrow_delta_obj: Variant = nearest_arrow.get("delta_position")
	if arrow_delta_obj is Vector2:
		arrow_delta = arrow_delta_obj as Vector2
	var arrow_distance := float(nearest_arrow.get("distance", INF))

	var keep_distance := float(genes.get("movement.keep_distance", 220.0))
	var backoff_ratio := float(genes.get("movement.backoff_ratio", 0.6))
	var deadzone_x := float(genes.get("movement.approach_deadzone_x", 10.0))
	var backoff_threshold := keep_distance * backoff_ratio

	var axis := 0.0
	var collecting_arrow := false
	if arrows <= 0 and arrow_distance < INF and arrow_delta.length() > 0.0:
		collecting_arrow = true
		if absf(arrow_delta.x) > 12.0:
			axis = 1.0 if arrow_delta.x > 0.0 else -1.0
		else:
			axis = 0.0
	elif abs_dx > maxf(deadzone_x, keep_distance):
		axis = 1.0 if dx > 0.0 else -1.0
	elif abs_dx < backoff_threshold:
		if abs_dx < maxf(2.0, deadzone_x):
			axis = -float(facing)
		else:
			axis = -1.0 if dx > 0.0 else 1.0

	var avoid_ledges := bool(genes.get("safety.avoid_ledges", true))
	var avoid_walls := bool(genes.get("safety.avoid_walls", true))
	var wall_stop_distance := float(genes.get("safety.wall_stop_distance", 14.0))
	var max_safe_drop_distance := float(genes.get("safety.max_safe_drop_distance", 85.0))
	var ceiling_block_distance := float(genes.get("safety.ceiling_block_distance", 18.0))
	var air_ground_distance := float(genes.get("safety.air_ground_distance", 55.0))
	var is_airborne_by_sensor := sensor_ground_distance > air_ground_distance

	var blocked_by_safety := false
	if axis != 0.0:
		var moving_dir := 1 if axis > 0.0 else -1
		if moving_dir == facing:
			if avoid_ledges and sensor_ledge_ahead:
				axis = 0.0
				blocked_by_safety = true
			if avoid_ledges and (not sensor_ledge_ahead) and sensor_ledge_ground_distance > max_safe_drop_distance:
				axis = 0.0
				blocked_by_safety = true
			if avoid_walls and sensor_wall_ahead:
				axis = 0.0
				blocked_by_safety = true
			if avoid_walls and sensor_front_wall_distance < wall_stop_distance:
				axis = 0.0
				blocked_by_safety = true

	if blocked_by_safety and not collecting_arrow and abs_dx > maxf(deadzone_x, keep_distance):
		axis = -float(facing)

	var aim := _aim_from_obs(observation)
	if collecting_arrow and arrow_delta.length() > 0.0:
		aim = arrow_delta.normalized()

	var shoot_min := float(genes.get("shoot.min_distance", 20.0))
	var shoot_max := float(genes.get("shoot.max_distance", 640.0))
	var shoot_y_tol := float(genes.get("shoot.y_tolerance", 140.0))
	var shoot_dx_min := float(genes.get("shoot.dx_min", 30.0))
	var want_shoot_window := (arrows > 0) and (distance_v > shoot_min) and (distance_v < shoot_max) and (abs_dx > shoot_dx_min) and (abs_dy < shoot_y_tol)

	var melee_range := float(genes.get("melee.range", 85.0))
	var melee_intent_cd := float(genes.get("melee.intent_cooldown", 0.30))
	var melee_intent := (distance_v < melee_range) and melee_cooldown_remaining <= 0.0

	var jump_dy := float(genes.get("jump.chase_dy", 140.0))
	var jump_intent_cd := float(genes.get("jump.intent_cooldown", 0.25))
	var jump_intent := (dy < -jump_dy) and (abs_dx > 80.0) and jump_cooldown_remaining <= 0.0
	if sensor_ceiling_distance < ceiling_block_distance:
		jump_intent = false
	if is_airborne_by_sensor:
		jump_intent = false

	var dash_use := bool(genes.get("dash.use", true))
	var dash_range := float(genes.get("dash.range", 650.0))
	var dash_prob := float(genes.get("dash.probability", 0.25))
	var dash_cd := float(genes.get("dash.intent_cooldown", 0.35))
	var dash_intent := dash_use and (distance_v > dash_range) and dash_cooldown_remaining <= 0.0 and (rng.randf() < dash_prob)
	if is_airborne_by_sensor:
		dash_intent = false

	if collecting_arrow:
		want_shoot_window = false
		melee_intent = false
		jump_intent = false
		dash_intent = false
	elif want_shoot_window:
		axis = 0.0
		melee_intent = false
		jump_intent = false
		dash_intent = false

	var shoot_pressed := false
	var shoot_is_pressed := false
	var hold_seconds := float(genes.get("shoot.hold_seconds", 0.14))
	var shoot_intent_cd := float(genes.get("shoot.intent_cooldown", 0.18))
	if shoot_release_frame:
		shoot_release_frame = false
		shoot_pressed = false
		shoot_is_pressed = false
	elif shoot_hold_remaining > 0.0:
		shoot_hold_remaining = maxf(0.0, shoot_hold_remaining - delta_time)
		shoot_is_pressed = true
		if shoot_hold_remaining <= 0.0:
			shoot_release_frame = true
			shoot_cooldown_remaining = maxf(shoot_cooldown_remaining, shoot_intent_cd)
	elif want_shoot_window and shoot_cooldown_remaining <= 0.0:
		shoot_hold_remaining = maxf(0.01, hold_seconds)
		shoot_pressed = true
		shoot_is_pressed = true

	var melee_pressed := false
	if melee_intent and not last_melee_intent:
		melee_pressed = true
		melee_cooldown_remaining = maxf(melee_cooldown_remaining, melee_intent_cd)
	last_melee_intent = melee_intent

	var jump_pressed := false
	if jump_intent and not last_jump_intent:
		jump_pressed = true
		jump_cooldown_remaining = maxf(jump_cooldown_remaining, jump_intent_cd)
	last_jump_intent = jump_intent

	var dash_pressed: Array = ["r1"] if dash_intent else []
	if dash_intent:
		dash_cooldown_remaining = maxf(dash_cooldown_remaining, dash_cd)

	return {
		"axis": float(axis),
		"aim": aim,
		"jump_pressed": bool(jump_pressed),
		"shoot_pressed": bool(shoot_pressed),
		"shoot_is_pressed": bool(shoot_is_pressed),
		"melee_pressed": bool(melee_pressed),
		"ult_pressed": false,
		"dash_pressed": dash_pressed,
		"actions": {"left": axis < 0.0, "right": axis > 0.0, "up": false, "down": false}
	}
