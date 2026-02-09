extends RefCounted
class_name ProjectileConfig

var map_width = 1600.0
var range_ratio = 0.9
var gravity_delay_ratio = 0.0

var base_speed = 1500.0
var min_speed = 720.0
var speed_decay = 360.0
var gravity = 750.0
var upward_gravity_multiplier = 3.2
var upward_speed_decay_multiplier = 2.2
var gravity_ramp_ratio = 0.6
var gravity_min_scale = 0.45
var gravity_max_scale = 1.2
var max_lifetime = 2.5

var profiles = {
	"default": {
		"base_speed": 1500.0,
		"min_speed": 720.0,
		"speed_decay": 360.0,
		"gravity": 750.0,
		"upward_gravity_multiplier": 3.2,
		"upward_speed_decay_multiplier": 2.2,
		"gravity_ramp_ratio": 0.6,
		"gravity_min_scale": 0.45,
		"gravity_max_scale": 1.2,
		"map_width": 1600.0,
		"range_ratio": 0.9,
		"gravity_delay_ratio": 0.0,
		"max_lifetime": 2.5
	},
	"heavy": {
		"base_speed": 1350.0,
		"min_speed": 640.0,
		"speed_decay": 420.0,
		"gravity": 900.0,
		"upward_gravity_multiplier": 3.4,
		"upward_speed_decay_multiplier": 2.3,
		"gravity_ramp_ratio": 0.6,
		"gravity_min_scale": 0.5,
		"gravity_max_scale": 1.25,
		"map_width": 2560.0,
		"range_ratio": 0.82,
		"gravity_delay_ratio": 0.0,
		"max_lifetime": 2.3
	},
	"fast": {
		"base_speed": 1650.0,
		"min_speed": 800.0,
		"speed_decay": 320.0,
		"gravity": 680.0,
		"upward_gravity_multiplier": 3.0,
		"upward_speed_decay_multiplier": 2.0,
		"gravity_ramp_ratio": 0.55,
		"gravity_min_scale": 0.4,
		"gravity_max_scale": 1.15,
		"map_width": 2560.0,
		"range_ratio": 0.95,
		"gravity_delay_ratio": 0.0,
		"max_lifetime": 2.3
	}
}

func max_range() -> float:
	return map_width * range_ratio

func apply_profile(profile_name: String) -> void:
	if not profiles.has(profile_name):
		return
	var data = profiles[profile_name]
	if data.has("base_speed"):
		base_speed = data["base_speed"]
	if data.has("min_speed"):
		min_speed = data["min_speed"]
	if data.has("speed_decay"):
		speed_decay = data["speed_decay"]
	if data.has("gravity"):
		gravity = data["gravity"]
	if data.has("upward_gravity_multiplier"):
		upward_gravity_multiplier = data["upward_gravity_multiplier"]
	if data.has("upward_speed_decay_multiplier"):
		upward_speed_decay_multiplier = data["upward_speed_decay_multiplier"]
	if data.has("gravity_ramp_ratio"):
		gravity_ramp_ratio = data["gravity_ramp_ratio"]
	if data.has("gravity_min_scale"):
		gravity_min_scale = data["gravity_min_scale"]
	if data.has("gravity_max_scale"):
		gravity_max_scale = data["gravity_max_scale"]
	if data.has("map_width"):
		map_width = data["map_width"]
	if data.has("range_ratio"):
		range_ratio = data["range_ratio"]
	if data.has("gravity_delay_ratio"):
		gravity_delay_ratio = data["gravity_delay_ratio"]
	if data.has("max_lifetime"):
		max_lifetime = data["max_lifetime"]
