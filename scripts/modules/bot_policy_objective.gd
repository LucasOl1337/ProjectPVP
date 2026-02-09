extends BotPolicyBase
class_name BotPolicyObjective

var shoot_range := 820.0
var keep_distance := 80.0
var retreat_distance := 40.0
var dash_range := 640.0
var jump_threshold := -280.0

var shoot_cooldown_seconds := 0.16
var melee_cooldown_seconds := 0.35
var dash_cooldown_seconds := 0.6
var shoot_hold_seconds := 0.07
var _time_since_shot := 999.0
var _time_since_melee := 999.0
var _time_since_dash := 999.0
var _shoot_hold_remaining := 0.0
var _shoot_just_started := false

func _init() -> void:
	policy_id = "objective"

func configure(config: Dictionary) -> void:
	if config.has("shoot_range"):
		shoot_range = float(config["shoot_range"])
	if config.has("keep_distance"):
		keep_distance = float(config["keep_distance"])
	if config.has("retreat_distance"):
		retreat_distance = float(config["retreat_distance"])
	if config.has("dash_range"):
		dash_range = float(config["dash_range"])
	if config.has("jump_threshold"):
		jump_threshold = float(config["jump_threshold"])
	if config.has("shoot_cooldown"):
		shoot_cooldown_seconds = max(0.0, float(config["shoot_cooldown"]))
	if config.has("shoot_hold"):
		shoot_hold_seconds = max(0.01, float(config["shoot_hold"]))
	if config.has("melee_cooldown"):
		melee_cooldown_seconds = max(0.0, float(config["melee_cooldown"]))
	if config.has("dash_cooldown"):
		dash_cooldown_seconds = max(0.0, float(config["dash_cooldown"]))

func reset() -> void:
	_time_since_shot = 999.0
	_time_since_melee = 999.0
	_time_since_dash = 999.0
	_shoot_hold_remaining = 0.0
	_shoot_just_started = false

func select_action(observation: Dictionary) -> Dictionary:
	var dt := float(observation.get("delta", 0.0))
	_time_since_shot += dt
	_time_since_melee += dt
	_time_since_dash += dt
	_shoot_just_started = false
	if _shoot_hold_remaining > 0.0:
		_shoot_hold_remaining = max(_shoot_hold_remaining - dt, 0.0)

	var delta: Vector2 = observation.get("delta_position", Vector2.ZERO)
	if not (delta is Vector2):
		delta = Vector2.ZERO
	var distance: float = delta.length()

	var axis := 0.0
	if abs(delta.x) > keep_distance:
		axis = sign(delta.x)
	elif abs(delta.x) < retreat_distance and abs(delta.x) > 1.0:
		axis = -sign(delta.x)

	var facing := 1
	var self_snapshot: Dictionary = observation.get("self", {}) if observation.get("self") is Dictionary else {}
	if self_snapshot.has("facing"):
		facing = int(self_snapshot.get("facing", 1))

	var aim := Vector2(facing, 0)
	if distance > 0.001:
		aim = delta.normalized()

	var jump := delta.y < jump_threshold
	var dash_pressed: Array = []
	if distance > dash_range and _time_since_dash >= dash_cooldown_seconds:
		dash_pressed = ["r1"]
		_time_since_dash = 0.0

	var melee := false
	if distance < 85.0 and _time_since_melee >= melee_cooldown_seconds:
		melee = true
		_time_since_melee = 0.0

	var want_shoot := distance > 60.0 and distance < shoot_range and _time_since_shot >= shoot_cooldown_seconds
	if want_shoot and _shoot_hold_remaining <= 0.0:
		_shoot_hold_remaining = shoot_hold_seconds
		_shoot_just_started = true
		_time_since_shot = 0.0
	var shoot_is_pressed := _shoot_hold_remaining > 0.0
	var shoot_pressed := _shoot_just_started

	var actions := {
		"left": axis < 0.0,
		"right": axis > 0.0,
		"up": false,
		"down": false
	}

	return {
		"axis": axis,
		"aim": aim,
		"jump_pressed": jump,
		"shoot_pressed": shoot_pressed,
		"shoot_is_pressed": shoot_is_pressed,
		"melee_pressed": melee,
		"ult_pressed": false,
		"dash_pressed": dash_pressed,
		"actions": actions
	}

