extends Resource
class_name CharacterData

@export var id := ""
@export var display_name := ""
@export var melee_skill: Resource
@export var ult_skill: Resource
@export var skill_slots: Array[String] = []
@export var skills: Array[Resource] = []
@export var asset_base_path := ""
@export var sprite_scale := Vector2(3.6, 3.6)
@export var sprite_anchor_offset := Vector2.ZERO
@export var animation_scale_max := 1.0
@export var animation_scale_min := 0.0
@export var visual_reference_width := 0.0
@export var visual_reference_height := 0.0
@export var target_visual_height := 0.0
@export_range(0.0, 1.0, 0.01) var ground_anchor_ratio := 1.0
@export var aim_skip_left := false
@export var action_skip_left: Dictionary = {}
@export var action_target_visual_height: Dictionary = {}
@export var action_ground_anchor_ratio: Dictionary = {}
@export var action_collider_overrides: Dictionary = {}
@export var action_animation_durations: Dictionary = {}
@export var action_animation_speeds: Dictionary = {}
@export var action_sfx_paths: Dictionary = {}
@export var action_sfx_durations: Dictionary = {}
@export var action_sfx_speeds: Dictionary = {}
@export var action_sfx_volumes_db: Dictionary = {}
@export var base_profile: Resource
@export var action_animation_paths: Dictionary = {}
@export var action_sprite_scale: Dictionary = {}
@export var action_sprite_offset: Dictionary = {}
@export var overrides_stats := false
@export var move_speed := 240.0
@export var acceleration := 1600.0
@export var friction := 2000.0
@export var jump_velocity := 360.0
@export var gravity := 1200.0
@export var max_fall_speed := 2000.0
@export var shoot_cooldown := 0.001
@export var max_arrows := 5
@export var melee_cooldown := 0.45
@export var melee_duration := 0.12
@export var collider_size := Vector2.ZERO
@export var collider_offset := Vector2.ZERO
@export var projectile_forward := 80.0
@export var projectile_vertical_offset := 0.0
@export var projectile_inherit_velocity_factor := 1.0
@export var projectile_scale := 1.0
@export var projectile_texture: Texture2D
