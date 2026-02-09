extends SkillBase
class_name GroundSlamSkill

const SkillHitboxArea = preload("res://scripts/skills/skill_hitbox_area.gd")

@export var skill_name := "Ground Slam"
@export var damage := 50.0
@export var area_radius := 120.0
@export var knockback_force := 400.0
@export var ground_offset := Vector2(0, 20)
@export var max_height_difference := 80.0
@export var hitbox_duration := 0.12
@export var hit_once := true
@export var hitbox_scene: PackedScene

func activate(player: Node) -> void:
	if not (player is Node2D):
		_log_event("activate_fail", "Player inválido")
		return
	var player_node := player as Node2D
	var origin := player_node.global_position + ground_offset
	var hitbox := _create_hitbox_instance()
	if hitbox == null:
		_log_event("activate_fail", "Cena de hitbox inválida")
		return
	hitbox.radius = area_radius
	hitbox.duration = hitbox_duration
	hitbox.knockback_force = knockback_force
	hitbox.max_height_difference = max_height_difference
	hitbox.hit_once = hit_once
	hitbox.configure(player, origin)
	var scene := player_node.get_tree().current_scene
	if scene == null:
		player_node.add_child(hitbox)
	else:
		scene.add_child(hitbox)
	_log_event("activate", "Hitbox criado em %s" % origin)

func _log_event(event: String, message: String) -> void:
	if not DevDebug:
		return
	DevDebug.log_event("ground_slam", "%s -> %s" % [event, message])

func _create_hitbox_instance() -> SkillHitboxArea:
	if hitbox_scene != null:
		var instance := hitbox_scene.instantiate()
		if instance is SkillHitboxArea:
			return instance as SkillHitboxArea
		_log_event("activate_fail", "Cena de hitbox não usa SkillHitboxArea")
		return null
	return SkillHitboxArea.new()
