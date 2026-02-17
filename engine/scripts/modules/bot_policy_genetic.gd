extends BotPolicyBase
class_name BotPolicyGenetic

const POS_SCALE := 1000.0
const VEL_SCALE := 1000.0
const AXIS_OPTIONS := [-1.0, 0.0, 1.0]

const SHOOT_HOLD_SECONDS := 0.08
const SHOOT_COOLDOWN_SECONDS := 0.18
const MELEE_COOLDOWN_SECONDS := 0.30
const JUMP_COOLDOWN_SECONDS := 0.18

var genome_path := ""
var load_error := ""
var loaded := false

var w1: Array = []
var b1: Array = []
var w2: Array = []
var b2: Array = []
var w3: Array = []
var b3: Array = []

var _shoot_hold_remaining := 0.0
var _shoot_cooldown_remaining := 0.0
var _shoot_release_frame := false

var _melee_cooldown_remaining := 0.0
var _last_melee_intent := false

var _jump_cooldown_remaining := 0.0
var _last_jump_intent := false

func _init() -> void:
	policy_id = "genetic"

func configure(config: Dictionary) -> void:
	if config.has("genome_path"):
		var path := String(config.get("genome_path", ""))
		if path != genome_path:
			load_genome(path)

func load_genome(path: String) -> Dictionary:
	genome_path = path
	var ok := _load_genome(path)
	return {"ok": ok, "error": load_error, "path": genome_path}

func get_load_error() -> String:
	return load_error

func is_loaded() -> bool:
	return loaded

func select_action(observation: Dictionary) -> Dictionary:
	if not loaded:
		return {}
	var delta_time := float(observation.get("delta", 0.0))
	var self_state := _read_dict(observation.get("self", {}))
	var match_state := _read_dict(observation.get("match", {}))
	if bool(self_state.get("is_dead", false)) or (match_state.has("round_active") and not bool(match_state.get("round_active"))):
		_shoot_hold_remaining = 0.0
		_shoot_cooldown_remaining = 0.0
		_shoot_release_frame = false
		_melee_cooldown_remaining = 0.0
		_last_melee_intent = false
		return {
			"axis": 0.0,
			"aim": Vector2(1, 0),
			"jump_pressed": false,
			"shoot_pressed": false,
			"shoot_is_pressed": false,
			"melee_pressed": false,
			"ult_pressed": false,
			"dash_pressed": [],
			"actions": {"left": false, "right": false, "up": false, "down": false}
		}
	_shoot_cooldown_remaining = maxf(_shoot_cooldown_remaining - delta_time, 0.0)
	_melee_cooldown_remaining = maxf(_melee_cooldown_remaining - delta_time, 0.0)
	_jump_cooldown_remaining = maxf(_jump_cooldown_remaining - delta_time, 0.0)
	var features := _obs_to_features(observation)
	if features.is_empty():
		return {}
	var output := _forward(features)
	if output.size() < 7:
		return {}
	var axis_idx := _argmax(output, 0, 3)
	var axis_value: float = float(AXIS_OPTIONS[axis_idx])
	var shoot_intent: bool = float(output[3]) > 0.0
	var jump_intent: bool = float(output[4]) > 0.0
	var dash: bool = float(output[5]) > 0.0
	var melee_intent: bool = float(output[6]) > 0.0

	var shoot_pressed := false
	var shoot_is_pressed := false
	if _shoot_release_frame:
		_shoot_release_frame = false
		shoot_pressed = false
		shoot_is_pressed = false
	elif _shoot_hold_remaining > 0.0:
		_shoot_hold_remaining = maxf(_shoot_hold_remaining - delta_time, 0.0)
		shoot_pressed = false
		shoot_is_pressed = true
		if _shoot_hold_remaining <= 0.0:
			_shoot_release_frame = true
			_shoot_cooldown_remaining = SHOOT_COOLDOWN_SECONDS
	elif shoot_intent and _shoot_cooldown_remaining <= 0.0:
		_shoot_hold_remaining = SHOOT_HOLD_SECONDS
		shoot_pressed = true
		shoot_is_pressed = true

	var melee_pressed := false
	if melee_intent and not _last_melee_intent and _melee_cooldown_remaining <= 0.0:
		melee_pressed = true
		_melee_cooldown_remaining = MELEE_COOLDOWN_SECONDS
	_last_melee_intent = melee_intent

	var jump_pressed := false
	if jump_intent and not _last_jump_intent and _jump_cooldown_remaining <= 0.0:
		jump_pressed = true
		_jump_cooldown_remaining = JUMP_COOLDOWN_SECONDS
	_last_jump_intent = jump_intent

	var delta := _read_vec2(observation.get("delta_position", Vector2.ZERO))
	var aim := Vector2(1, 0)
	if delta.length() > 0.0:
		aim = delta.normalized()

	return {
		"axis": axis_value,
		"aim": aim,
		"jump_pressed": jump_pressed,
		"shoot_pressed": shoot_pressed,
		"shoot_is_pressed": shoot_is_pressed,
		"melee_pressed": melee_pressed,
		"ult_pressed": false,
		"dash_pressed": ["r1"] if dash else [],
		"actions": {
			"left": axis_value < 0.0,
			"right": axis_value > 0.0,
			"up": false,
			"down": false
		}
	}

func _load_genome(path: String) -> bool:
	load_error = ""
	loaded = false
	w1 = []
	b1 = []
	w2 = []
	b2 = []
	w3 = []
	b3 = []
	if path == "":
		load_error = "Caminho vazio"
		return false
	if not FileAccess.file_exists(path):
		load_error = "Arquivo não encontrado"
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_error = "Falha ao abrir arquivo"
		return false
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		load_error = "JSON inválido"
		return false
	var payload: Dictionary = parsed as Dictionary
	var weights_value: Variant = payload.get("weights", [])
	if not (weights_value is Array):
		load_error = "Formato inválido de pesos"
		return false
	var weights: Array = weights_value as Array
	if weights.size() < 6:
		load_error = "Pesos incompletos"
		return false
	w1 = _to_matrix(weights[0])
	b1 = _to_vector(weights[1])
	w2 = _to_matrix(weights[2])
	b2 = _to_vector(weights[3])
	w3 = _to_matrix(weights[4])
	b3 = _to_vector(weights[5])
	if w1.is_empty() or w2.is_empty() or w3.is_empty():
		load_error = "Pesos inválidos"
		return false
	loaded = true
	return true

func _obs_to_features(obs: Dictionary) -> Array:
	if obs.is_empty():
		return []
	var delta := _read_vec2(obs.get("delta_position", Vector2.ZERO))
	var distance := delta.length()

	var self_state := _read_dict(obs.get("self", {}))
	var opp_state := _read_dict(obs.get("opponent", {}))
	var match_state := _read_dict(obs.get("match", {}))
	var wins := _read_dict(match_state.get("wins", {}))

	var self_pos := _read_vec2(self_state.get("position", Vector2.ZERO))
	var opp_pos := _read_vec2(opp_state.get("position", Vector2.ZERO))
	var self_vel := _read_vec2(self_state.get("velocity", Vector2.ZERO))
	var opp_vel := _read_vec2(opp_state.get("velocity", Vector2.ZERO))

	return [
		delta.x / POS_SCALE,
		delta.y / POS_SCALE,
		distance / POS_SCALE,
		self_pos.x / POS_SCALE,
		self_pos.y / POS_SCALE,
		self_vel.x / VEL_SCALE,
		self_vel.y / VEL_SCALE,
		float(self_state.get("facing", 1)),
		_bool_to_float(self_state.get("on_floor", false)),
		_bool_to_float(self_state.get("on_wall", false)),
		float(self_state.get("arrows", 0)),
		_bool_to_float(self_state.get("is_dead", false)),
		opp_pos.x / POS_SCALE,
		opp_pos.y / POS_SCALE,
		opp_vel.x / VEL_SCALE,
		opp_vel.y / VEL_SCALE,
		float(opp_state.get("facing", 1)),
		_bool_to_float(opp_state.get("on_floor", false)),
		_bool_to_float(opp_state.get("on_wall", false)),
		float(opp_state.get("arrows", 0)),
		_bool_to_float(opp_state.get("is_dead", false)),
		_bool_to_float(match_state.get("round_active", false)),
		_bool_to_float(match_state.get("match_over", false)),
		float(_read_win(wins, 1)),
		float(_read_win(wins, 2))
	]

func _read_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array:
		var array_value: Array = value as Array
		if array_value.size() >= 2:
			return Vector2(float(array_value[0]), float(array_value[1]))
	if value is Dictionary:
		var dict_value: Dictionary = value as Dictionary
		if dict_value.has("x") and dict_value.has("y"):
			return Vector2(float(dict_value["x"]), float(dict_value["y"]))
	return Vector2.ZERO

func _read_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}

func _read_win(wins: Dictionary, player_id: int) -> int:
	if wins.has(player_id):
		return int(wins[player_id])
	var key := str(player_id)
	if wins.has(key):
		return int(wins[key])
	return 0

func _bool_to_float(value: Variant) -> float:
	return 1.0 if bool(value) else 0.0

func _to_matrix(value: Variant) -> Array:
	var matrix: Array = []
	if value is Array:
		for row_value in value:
			if row_value is Array:
				var row: Array = []
				for cell in row_value:
					row.append(float(cell))
				matrix.append(row)
	return matrix

func _to_vector(value: Variant) -> Array:
	var output: Array = []
	if value is Array:
		for cell in value:
			output.append(float(cell))
	return output

func _forward(features: Array) -> Array:
	var x := _tanh_vec(_add_vec(_matmul_vec(features, w1), b1))
	x = _tanh_vec(_add_vec(_matmul_vec(x, w2), b2))
	return _add_vec(_matmul_vec(x, w3), b3)

func _matmul_vec(vec: Array, matrix: Array) -> Array:
	if matrix.is_empty():
		return []
	var out_size := 0
	if matrix[0] is Array:
		out_size = (matrix[0] as Array).size()
	var result: Array = []
	result.resize(out_size)
	for j in range(out_size):
		var sum := 0.0
		for i in range(vec.size()):
			if i >= matrix.size():
				break
			var row: Array = matrix[i] as Array
			if j < row.size():
				sum += float(vec[i]) * float(row[j])
		result[j] = sum
	return result

func _add_vec(a: Array, b: Array) -> Array:
	var result: Array = []
	var size: int = min(a.size(), b.size())
	result.resize(size)
	for i in range(size):
		result[i] = float(a[i]) + float(b[i])
	return result

func _tanh_vec(vec: Array) -> Array:
	var result: Array = []
	result.resize(vec.size())
	for i in range(vec.size()):
		result[i] = tanh(float(vec[i]))
	return result

func _argmax(vec: Array, start: int, count: int) -> int:
	var best_idx := 0
	var best_value := -INF
	for i in range(count):
		var idx := start + i
		if idx >= vec.size():
			break
		var value := float(vec[idx])
		if value > best_value:
			best_value = value
			best_idx = i
	return best_idx
