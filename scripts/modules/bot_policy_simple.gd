extends BotPolicyBase
class_name BotPolicySimple

var shoot_range := 520.0
var keep_distance := 90.0
var dash_range := 620.0

var shoot_hold_seconds := 0.09
var _shoot_hold_remaining := 0.0
var _shoot_just_started := false

func _init() -> void:
	policy_id = "simple"

func configure(config: Dictionary) -> void:
	if config.has("shoot_range"):
		shoot_range = float(config["shoot_range"])
	if config.has("keep_distance"):
		keep_distance = float(config["keep_distance"])
	if config.has("dash_range"):
		dash_range = float(config["dash_range"])
	if config.has("shoot_hold"):
		shoot_hold_seconds = max(0.01, float(config["shoot_hold"]))

func reset() -> void:
	_shoot_hold_remaining = 0.0
	_shoot_just_started = false

func select_action(observation: Dictionary) -> Dictionary:
	_shoot_just_started = false
	var dt := float(observation.get("delta", 0.0))
	if _shoot_hold_remaining > 0.0:
		_shoot_hold_remaining = max(_shoot_hold_remaining - dt, 0.0)
	var delta: Vector2 = observation.get("delta_position", Vector2.ZERO)
	if not (delta is Vector2):
		delta = Vector2.ZERO
	var distance: float = delta.length()
	var axis := 0.0
	if abs(delta.x) > keep_distance:
		axis = sign(delta.x)
	var actions := {
		"left": axis < 0.0,
		"right": axis > 0.0,
		"up": false,
		"down": false
	}
	var facing := 1
	if observation.has("self") and observation["self"] is Dictionary:
		facing = int((observation["self"] as Dictionary).get("facing", 1))
	var aim := Vector2(facing, 0)
	if distance > 0.0:
		aim = delta.normalized()
	var want_shoot := distance > 40.0 and distance < shoot_range
	if want_shoot and _shoot_hold_remaining <= 0.0:
		_shoot_hold_remaining = shoot_hold_seconds
		_shoot_just_started = true
	var shoot_is_pressed := _shoot_hold_remaining > 0.0
	var shoot_pressed := _shoot_just_started
	var melee := distance < 80.0
	var jump := delta.y < -120.0
	var dash_pressed: Array = []
	if distance > dash_range:
		dash_pressed = ["r1"]
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
