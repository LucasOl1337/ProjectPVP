extends Resource
class_name CharacterBaseProfile

@export var action_idle := "idle"
@export var action_walk := "walk"
@export var action_running := "running"
@export var action_dash := "dash"
@export var action_jump_start := "jump_start"
@export var action_jump_air := "jump_air"
@export var action_crouch := "crouch"
@export var action_aim := "aim"
@export var action_shoot := "shoot"
@export var action_melee := "melee"
@export var action_hurt := "hurt"
@export var action_death := "death"
@export var action_ult := "ult"

@export var use_8_dir_aim := true
@export var bow_node_path: NodePath = NodePath("Bow")
@export var bow_offset := Vector2.ZERO
@export var bow_offset_aim := Vector2.ZERO
@export var bow_rotate := true
@export var crouch_sprite_offset := Vector2.ZERO

func action_prefix(action: String) -> String:
	match action:
		"idle":
			return action_idle
		"walk":
			return action_walk
		"running":
			return action_running
		"dash":
			return action_dash
		"jump_start":
			return action_jump_start
		"jump_air":
			return action_jump_air
		"crouch":
			return action_crouch
		"aim":
			return action_aim
		"shoot":
			return action_shoot
		"melee":
			return action_melee
		"hurt":
			return action_hurt
		"death":
			return action_death
		"ult":
			return action_ult
		_:
			return action
