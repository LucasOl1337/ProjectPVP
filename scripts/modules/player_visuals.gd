extends RefCounted
class_name PlayerVisuals

func _is_headless_runtime() -> bool:
	if DisplayServer.get_name() == "headless" or OS.has_feature("headless"):
		return true
	if OS.has_method("get_cmdline_user_args"):
		var args: Array = OS.get_cmdline_user_args()
		return args.has("--training") or args.has("--no-visuals")
	return false

const CharacterBaseProfile = preload("res://scripts/characters/character_base_profile.gd")
const SpriteDebugOverlay = preload("res://scripts/modules/sprite_debug_overlay.gd")

const HURTBOX_SCALE := Vector2(0.86, 0.9)
const CROUCH_HEIGHT_SCALE := 0.6
const AIM_INACTIVE_ALPHA := 0.18
const AIM_ACTIVE_SCALE := 1.3
const AIM_RADIUS_DEFAULT := 72.0
const AIM_RADIUS_MULT := 0.7
const AIM_SEGMENT_COUNT := 3
const AIM_SEGMENT_SIZE := Vector2(6.0, 6.0)
const AIM_SEGMENT_ALPHA := 0.55
const AIM_ARROW_TEXTURE_PATH := "res://assets/ui/aim_indicator/aim_arrow.png"
const AIM_SEGMENT_TEXTURE_PATH := "res://assets/ui/aim_indicator/aim_segment.png"
const AIM_SEGMENT_SCALE := 0.5
const DEFAULT_BODY_WIDTH := 34.0
const DEFAULT_BODY_HEIGHT := 68.0
const ACTION_PRIORITIES := {
	"death": 120,
	"ult": 100,
	"melee": 90,
	"dash": 80,
	"shoot": 70,
	"aim": 60,
	"jump_start": 55,
	"jump_air": 50,
	"running": 40,
	"walk": 30,
	"crouch": 25,
	"idle": 10
}
const PRIORITY_NEGATIVE_INFINITY := -99999
const ACTION_DEFAULT_DURATIONS := {
	"idle": 1.0,
	"walk": 0.8,
	"running": 0.75,
	"dash": 0.45,
	"jump_start": 0.35,
	"jump_air": 0.8,
	"aim": 0.6,
	"shoot": 0.55,
	"melee": 0.45,
	"hurt": 0.5,
	"death": 1.0,
	"ult": 0.8
}
const ACTION_DEFAULT_SPEEDS := {
	"walk": 10.0,
	"running": 12.0,
	"dash": 8.0,
	"jump_start": 10.0,
	"jump_air": 10.0,
	"shoot": 12.0,
	"ult": 12.0,
	"aim": 12.0,
	"melee": 12.0,
	"hurt": 10.0,
	"death": 8.0,
	"crouch": 6.0
}

const TEAM_RECOLOR_SHADER = preload("res://assets/shaders/team_recolor.gdshader")

# SECTION: STATE

var owner: CharacterBody2D = null
var player_id := 1
var character_id := ""
var character_data: CharacterData = null

var aim_indicator: Node2D = null
var character_sprite: AnimatedSprite2D = null
var body_shape: CollisionShape2D = null
var hurtbox: Area2D = null
var body_poly: Node2D = null
var legs_poly: Node2D = null
var head_poly: Node2D = null
var bow_poly: Node2D = null
var debug_overlay: Node2D = null
var debug_overlay_enabled := false

var ghost_timer := 0.0
var ghost_interval := 0.05
var parry_anim_timer := 0.0
var base_scale := Vector2.ONE
var base_sprite_scale := Vector2.ONE
var base_modulate := Color(1, 1, 1, 1)
var _team_recolor_material: ShaderMaterial = null
var base_sprite_position := Vector2.ZERO
var dash_anim_hold_timer := 0.0
var shoot_anim_timer := 0.0
var melee_anim_timer := 0.0
var jump_start_timer := 0.0
var ult_anim_timer := 0.0
var is_crouching := false
var base_body_size := Vector2.ZERO
var base_body_position := Vector2.ZERO
var animation_frame_offsets: Dictionary = {}
var base_animation_name := ""
var base_animation_offset := Vector2.ZERO
var current_collider_action := ""
var _last_collider_size := Vector2.ZERO
var aim_arrow: Node2D = null
var aim_segments: Array[Node2D] = []
var bow_node: Node2D = null
var base_bow_position := Vector2.ZERO
var base_bow_rotation := 0.0
var _default_profile: CharacterBaseProfile = null
var _cached_assets_base_path := ""
var _cached_has_assets := false
var has_running_animation := false
var current_override_action := ""
var current_override_priority := PRIORITY_NEGATIVE_INFINITY
var current_override_lock := 0.0
var pending_override_action := ""
var pending_override_priority := PRIORITY_NEGATIVE_INFINITY
var pending_override_lock := 0.0
var action_lock_timers: Dictionary = {}

# SECTION: SETUP

func configure(
	owner_node: CharacterBody2D,
	player_id_value: int,
	character_id_value: String,
	character_data_value: CharacterData,
	aim_indicator_node: Node2D,
	character_sprite_node: AnimatedSprite2D,
	body_shape_node: CollisionShape2D,
	hurtbox_node: Area2D,
	body_poly_node: Node2D,
	legs_poly_node: Node2D,
	head_poly_node: Node2D,
	bow_poly_node: Node2D
) -> void:
	owner = owner_node
	player_id = player_id_value
	character_id = character_id_value
	character_data = character_data_value
	aim_indicator = aim_indicator_node
	character_sprite = character_sprite_node
	body_shape = body_shape_node
	hurtbox = hurtbox_node
	body_poly = body_poly_node
	legs_poly = legs_poly_node
	head_poly = head_poly_node
	bow_poly = bow_poly_node
	if owner != null:
		base_scale = owner.scale
		base_modulate = owner.modulate

func set_character_data(data: CharacterData) -> void:
	character_data = data
	_cached_assets_base_path = ""
	_cached_has_assets = false

func configure_debug_overlay(enabled: bool) -> void:
	if _is_headless_runtime():
		return
	debug_overlay_enabled = enabled
	if not enabled:
		if debug_overlay != null:
			debug_overlay.set_enabled(false)
		return
	if owner == null:
		return
	if debug_overlay == null:
		debug_overlay = SpriteDebugOverlay.new()
		debug_overlay.name = "SpriteDebugOverlay"
		owner.add_child(debug_overlay)
	debug_overlay.configure(character_sprite, body_shape)
	debug_overlay.set_enabled(true)
	_update_debug_overlay(character_sprite.animation if character_sprite != null else "")

func request_action_override(action: String, priority: int, lock_duration: float = 0.0) -> void:
	if action == "":
		return
	if current_override_action == action:
		current_override_priority = priority
		current_override_lock = max(current_override_lock, lock_duration)
		if pending_override_action == action:
			pending_override_action = ""
		return
	if _can_apply_override(priority):
		_apply_override_action(action, priority, lock_duration)
		return
	if pending_override_action == "" or priority >= pending_override_priority:
		pending_override_action = action
		pending_override_priority = priority
		pending_override_lock = lock_duration

func release_action_override(action: String) -> void:
	if action == "":
		return
	if action == current_override_action:
		current_override_action = ""
		current_override_priority = PRIORITY_NEGATIVE_INFINITY
		current_override_lock = 0.0
		_stop_action_timer(action)
		_apply_pending_override()
		return
	if action == pending_override_action:
		pending_override_action = ""
		pending_override_priority = PRIORITY_NEGATIVE_INFINITY
		pending_override_lock = 0.0
		_stop_action_timer(action)
		return

func update_action_override_state(delta: float) -> void:
	if current_override_lock > 0.0:
		current_override_lock = max(current_override_lock - delta, 0.0)
	if pending_override_action != "" and _can_apply_override(pending_override_priority):
		_apply_pending_override()
	elif current_override_action == "" and pending_override_action != "":
		_apply_pending_override()

func get_action_priority(action: String, default_priority: int = 0) -> int:
	return ACTION_PRIORITIES.get(action, default_priority)

func _can_apply_override(priority: int) -> bool:
	if current_override_action == "":
		return true
	if priority > current_override_priority:
		return true
	if priority == current_override_priority and current_override_lock <= 0.0:
		return true
	return false

func _apply_override_action(action: String, priority: int, lock_duration: float) -> void:
	current_override_action = action
	current_override_priority = priority
	current_override_lock = max(lock_duration, 0.0)
	if action == pending_override_action:
		pending_override_action = ""
		pending_override_priority = PRIORITY_NEGATIVE_INFINITY
		pending_override_lock = 0.0

func _apply_pending_override() -> void:
	if pending_override_action == "":
		return
	_apply_override_action(pending_override_action, pending_override_priority, pending_override_lock)

func _stop_action_timer(action: String) -> void:
	match action:
		"dash":
			dash_anim_hold_timer = 0.0
		"shoot":
			shoot_anim_timer = 0.0
		"melee":
			melee_anim_timer = 0.0
		"jump_start":
			jump_start_timer = 0.0
		"ult":
			ult_anim_timer = 0.0
		"aim":
			shoot_anim_timer = 0.0
		"running", "walk", "idle", "crouch":
			pass
		_:
			pass

# SECTION: METHODS

func is_crouching_active() -> bool:
	return is_crouching

func reset_state() -> void:
	parry_anim_timer = 0.0
	dash_anim_hold_timer = 0.0
	shoot_anim_timer = 0.0
	melee_anim_timer = 0.0
	jump_start_timer = 0.0
	ult_anim_timer = 0.0
	_apply_crouch(false)
	_set_crouch_visuals(false)
	current_override_action = ""
	current_override_priority = PRIORITY_NEGATIVE_INFINITY
	current_override_lock = 0.0
	pending_override_action = ""
	pending_override_priority = PRIORITY_NEGATIVE_INFINITY
	pending_override_lock = 0.0
	action_lock_timers.clear()

func hold_dash_animation(duration: float) -> void:
	dash_anim_hold_timer = max(duration, 0.0)
	_lock_action_for_duration("dash", duration, min(duration, 0.12))

func trigger_shoot_animation(duration: float) -> void:
	shoot_anim_timer = max(duration, 0.0)
	_lock_action_for_duration("shoot", duration, min(duration, 0.05))

func trigger_melee_animation(duration: float) -> void:
	melee_anim_timer = max(duration, 0.0)
	_lock_action_for_duration("melee", duration, min(duration, 0.08))

func trigger_jump_start(duration: float) -> void:
	jump_start_timer = max(duration, 0.0)
	_lock_action_for_duration("jump_start", duration, min(duration, 0.05))

func trigger_ult_animation(duration: float) -> void:
	ult_anim_timer = max(duration, 0.0)
	_lock_action_for_duration("ult", duration, min(duration, 0.2))

func trigger_parry(duration: float) -> void:
	parry_anim_timer = max(duration, 0.0)

func has_action_animation(action: String) -> bool:
	if character_sprite == null or character_sprite.sprite_frames == null:
		return false
	var frames: SpriteFrames = character_sprite.sprite_frames
	if frames.has_animation(action):
		return true
	var directions := ["right", "left", "up", "down", "up_right", "up_left", "down_right", "down_left"]
	for dir in directions:
		var anim_name := "%s_%s" % [action, dir]
		if frames.has_animation(anim_name):
			return true
	return false


func _candidate_action_keys(action: String) -> Array[String]:
	var keys: Array[String] = [action]
	if action in ["jump_start", "jump_air"]:
		keys.append("jump")
	return keys

func get_action_animation_duration(action: String, default_duration: float = 0.8) -> float:
	if character_data != null:
		for lookup_action in _candidate_action_keys(action):
			if character_data.action_animation_durations.has(lookup_action):
				var value: Variant = character_data.action_animation_durations[lookup_action]
				if value is float or value is int:
					return float(value)
	if ACTION_DEFAULT_DURATIONS.has(action):
		return float(ACTION_DEFAULT_DURATIONS[action])
	return default_duration

func get_action_animation_speed(action: String, default_speed: float = 10.0) -> float:
	if character_data != null:
		for lookup_action in _candidate_action_keys(action):
			if character_data.action_animation_speeds.has(lookup_action):
				var value: Variant = character_data.action_animation_speeds[lookup_action]
				if value is float or value is int:
					return max(0.1, float(value))
	if ACTION_DEFAULT_SPEEDS.has(action):
		return float(ACTION_DEFAULT_SPEEDS[action])
	return default_speed

func is_dash_anim_active(dash_active: bool) -> bool:
	return dash_active or dash_anim_hold_timer > 0.0

func update_animation_timers(delta: float) -> void:
	if shoot_anim_timer > 0.0:
		shoot_anim_timer = max(shoot_anim_timer - delta, 0.0)
	if melee_anim_timer > 0.0:
		melee_anim_timer = max(melee_anim_timer - delta, 0.0)
	if jump_start_timer > 0.0:
		jump_start_timer = max(jump_start_timer - delta, 0.0)
	if ult_anim_timer > 0.0:
		ult_anim_timer = max(ult_anim_timer - delta, 0.0)
	if dash_anim_hold_timer > 0.0:
		dash_anim_hold_timer = max(dash_anim_hold_timer - delta, 0.0)
	_update_action_lock_timers(delta)

func update_visuals(delta: float, dash_active: bool, facing: int) -> void:
	if _is_headless_runtime():
		return
	if owner == null:
		return
	if parry_anim_timer > 0.0:
		parry_anim_timer = max(parry_anim_timer - delta, 0.0)
		owner.modulate = Color(1.0, 0.95, 0.6, 1)
		owner.scale = Vector2(1.08, 0.92)
		owner.rotation = 0.0
		return
	owner.modulate = base_modulate
	if dash_active:
		owner.scale = Vector2(1.05, 0.95)
		owner.rotation = deg_to_rad(6.0 * facing)
		ghost_timer -= delta
		if ghost_timer <= 0.0:
			ghost_timer = ghost_interval
			_spawn_dash_ghost()
		return
	owner.scale = base_scale
	owner.rotation = 0.0

func apply_player_color() -> void:
	base_modulate = Color(1, 1, 1, 1)
	if owner:
		owner.modulate = base_modulate

	if character_sprite != null:
		if player_id == 2:
			if _team_recolor_material == null:
				_team_recolor_material = ShaderMaterial.new()
				_team_recolor_material.shader = TEAM_RECOLOR_SHADER
			_team_recolor_material.set_shader_parameter("active", true)
			_team_recolor_material.set_shader_parameter("target_color", Color(1.0, 0.15, 0.15, 1.0))
			_team_recolor_material.set_shader_parameter("hue_min", 0.45)
			_team_recolor_material.set_shader_parameter("hue_max", 0.75)
			_team_recolor_material.set_shader_parameter("feather", 0.07)
			_team_recolor_material.set_shader_parameter("sat_min", 0.18)
			_team_recolor_material.set_shader_parameter("val_min", 0.12)
			_team_recolor_material.set_shader_parameter("intensity", 1.0)
			character_sprite.use_parent_material = true
			character_sprite.material = null
			if owner:
				owner.material = _team_recolor_material
		else:
			character_sprite.use_parent_material = false
			character_sprite.material = null
			if owner:
				owner.material = null

	if body_poly is Polygon2D:
		if player_id == 1:
			body_poly.color = Color(0.95, 0.95, 0.95)
		else:
			body_poly.color = Color(0.9, 0.35, 0.35)

func configure_character_visuals() -> void:
	if _is_headless_runtime():
		return
	if character_sprite == null:
		return
	var use_sprite := _has_cached_character_assets()
	character_sprite.visible = use_sprite
	for node in [body_poly, legs_poly, head_poly, bow_poly]:
		if node is CanvasItem:
			node.visible = not use_sprite

func setup_character_sprite() -> void:
	if _is_headless_runtime():
		return
	has_running_animation = false
	if character_sprite == null:
		return
	var base_path := _character_base_path()
	if not _has_cached_character_assets():
		return
	var frames := SpriteFrames.new()
	var rotations_path := base_path + "rotations/"
	_load_directional_rotations(frames, rotations_path)
	var resolved_id := character_id
	if character_data != null and character_data.id != "":
		resolved_id = character_data.id
	print("[ANIM] === Loading animations for character: %s ===" % resolved_id)
	_load_action_variants(frames, "walk", get_action_animation_speed("walk", 10.0), _animation_paths("walk", [
		base_path + "animations/walk/"
	], base_path))
	_load_action_variants(
		frames,
		"running",
		get_action_animation_speed("running", get_action_animation_speed("walk", 10.0)),
		_animation_paths("running", [
			base_path + "animations/running/",
			base_path + "animations/run/"
		], base_path)
	)
	_load_action_variants(frames, "dash", get_action_animation_speed("dash", 8.0), _animation_paths("dash", [
		base_path + "animations/dash_magic/",
		base_path + "animations/running-6-frames/",
		base_path + "animations/running-8-frames/",
		base_path + "animations/running-4-frames/"
	], base_path))
	_load_action_variants(frames, "jump_start", get_action_animation_speed("jump_start", 10.0), _animation_paths("jump_start", [
		base_path + "animations/jumping-1/"
	], base_path))
	_load_action_variants(frames, "jump_air", get_action_animation_speed("jump_air", 10.0), _animation_paths("jump_air", [
		base_path + "animations/jumping-2/"
	], base_path))
	_load_action_variants(frames, "shoot", get_action_animation_speed("shoot", 12.0), _animation_paths("shoot", [
		base_path + "animations/throw-object/",
		base_path + "animations/custom-Bow and arrow aiming/"
	], base_path))
	_load_action_variants(frames, "ult", get_action_animation_speed("ult", 12.0), _animation_paths("ult", [
		base_path + "animations/roundhouse-kick/"
	], base_path))
	_load_action_variants(frames, "aim", get_action_animation_speed("aim", 12.0), _animation_paths("aim", [
		base_path + "animations/custom-Bow and arrow aiming/",
		base_path + "animations/throw-object/",
		base_path + "animations/aiming/"
	], base_path))
	_load_action_variants(frames, "melee", get_action_animation_speed("melee", 12.0), _animation_paths("melee", [
		base_path + "animations/lead-jab/",
		base_path + "animations/cross-punch/",
		base_path + "animations/high-kick/"
	], base_path))
	_load_action_variants(frames, "hurt", get_action_animation_speed("hurt", 10.0), _animation_paths("hurt", [
		base_path + "animations/taking-punch/"
	], base_path))
	_load_action_variants(frames, "death", get_action_animation_speed("death", 8.0), _animation_paths("death", [
		base_path + "animations/falling-back-death/"
	], base_path))
	var crouch_paths := _animation_paths("crouch", [
		base_path + "animations/crouching/"
	], base_path)
	_load_action_variants(frames, "crouch", get_action_animation_speed("crouch", 6.0), crouch_paths)
	var crouch_speed := get_action_animation_speed("crouch", 6.0)
	if crouch_paths.size() > 0:
		_load_single_animation(frames, crouch_paths[0], "crouch", crouch_speed)
	character_sprite.sprite_frames = frames
	has_running_animation = has_action_animation("running")
	if frames.has_animation("right"):
		character_sprite.play("right")
	elif frames.has_animation("left"):
		character_sprite.play("left")
	elif frames.has_animation("up"):
		character_sprite.play("up")
	character_sprite.centered = true
	character_sprite.offset = Vector2.ZERO
	character_sprite.scale = _character_sprite_scale()
	character_sprite.flip_h = false
	base_sprite_scale = character_sprite.scale
	base_sprite_position = character_sprite.position

func align_hitbox_to_sprite() -> void:
	if _is_headless_runtime():
		return
	if body_shape == null:
		return
	if not (body_shape.shape is RectangleShape2D):
		return
	var rect := body_shape.shape as RectangleShape2D
	var target_size := _resolve_reference_collider_size()
	var has_reference := base_body_size != Vector2.ZERO
	if not has_reference and character_data:
		has_reference = character_data.collider_size != Vector2.ZERO
	if not has_reference and character_sprite != null and character_sprite.sprite_frames != null:
		if character_sprite.sprite_frames.has_animation(character_sprite.animation):
			var ref_texture: Texture2D = character_sprite.sprite_frames.get_frame_texture(character_sprite.animation, 0)
			var ref_used := _texture_used_rect(ref_texture)
			if ref_texture != null and ref_used.size != Vector2i.ZERO:
				var ref_size: Vector2 = Vector2(ref_used.size) * character_sprite.scale
				var padding := Vector2(4.0, 2.0)
				target_size = Vector2(
					max(ref_size.x + padding.x, target_size.x),
					max(ref_size.y + padding.y, target_size.y)
				)
	rect.size = target_size
	var collider_offset := Vector2(0, -rect.size.y * 0.5)
	if character_data and character_data.collider_offset != Vector2.ZERO:
		collider_offset = character_data.collider_offset
	body_shape.position = collider_offset
	sync_hurtbox_to_body()
	cache_body_shape_defaults()
	_apply_crouch(false)
	if character_sprite == null or character_sprite.sprite_frames == null:
		_update_debug_overlay(character_sprite.animation if character_sprite != null else "")
		return
	if not character_sprite.sprite_frames.has_animation(character_sprite.animation):
		_update_debug_overlay(character_sprite.animation)
		return
	var texture: Texture2D = character_sprite.sprite_frames.get_frame_texture(character_sprite.animation, 0)
	var used := _texture_used_rect(texture)
	if texture == null or used.size == Vector2i.ZERO:
		_update_debug_overlay(character_sprite.animation)
		return
	var texture_size: Vector2 = texture.get_size()
	var used_center_x: float = (used.position.x + used.size.x * 0.5 - texture_size.x * 0.5) * character_sprite.scale.x
	var action := _resolve_action_from_anim(character_sprite.animation)
	var anchor_ratio := _resolve_ground_anchor_ratio(action)
	var used_anchor: float = (used.position.y + used.size.y * anchor_ratio - texture_size.y * 0.5) * character_sprite.scale.y
	character_sprite.position = Vector2(-used_center_x, -used_anchor) + _resolve_sprite_anchor_offset()
	base_sprite_position = character_sprite.position
	_update_debug_overlay(character_sprite.animation)

func cache_animation_offsets() -> void:
	if _is_headless_runtime():
		return
	animation_frame_offsets.clear()
	base_animation_name = character_sprite.animation if character_sprite != null else ""
	base_animation_offset = character_sprite.position if character_sprite != null else Vector2.ZERO
	if character_sprite == null or character_sprite.sprite_frames == null:
		return
	var anchor_offset := _resolve_sprite_anchor_offset()
	var frames: SpriteFrames = character_sprite.sprite_frames
	for anim_name in frames.get_animation_names():
		var frame_count := frames.get_frame_count(anim_name)
		if frame_count == 0:
			continue
		var action := _resolve_action_from_anim(anim_name)
		var anchor_ratio := _resolve_ground_anchor_ratio(action)
		var offsets: Array[Vector2] = []
		offsets.resize(frame_count)
		for frame_idx in range(frame_count):
			var texture := frames.get_frame_texture(anim_name, frame_idx)
			var used := _texture_used_rect(texture)
			if used.size == Vector2i.ZERO:
				offsets[frame_idx] = base_animation_offset
				continue
			var texture_size: Vector2 = texture.get_size()
			var offset_x: float = (used.position.x + used.size.x * 0.5 - texture_size.x * 0.5) * base_sprite_scale.x
			var offset_y: float = (used.position.y + used.size.y * anchor_ratio - texture_size.y * 0.5) * base_sprite_scale.y
			offsets[frame_idx] = Vector2(-offset_x, -offset_y) + anchor_offset
		animation_frame_offsets[anim_name] = offsets
	if base_animation_name != "" and animation_frame_offsets.has(base_animation_name):
		var base_offsets: Array = animation_frame_offsets[base_animation_name]
		if base_offsets.size() > 0 and base_offsets[0] is Vector2:
			base_animation_offset = base_offsets[0]

func setup_aim_indicator() -> void:
	if _is_headless_runtime():
		return
	if aim_indicator == null:
		return
	var trail_root := aim_indicator.get_node_or_null("AimTrail") as Node2D
	if trail_root == null:
		trail_root = Node2D.new()
		trail_root.name = "AimTrail"
		aim_indicator.add_child(trail_root)
	trail_root.visible = true
	var base_arrow: Node2D = null
	var arrow_texture := load(AIM_ARROW_TEXTURE_PATH)
	if arrow_texture is Texture2D:
		base_arrow = aim_indicator.get_node_or_null("AimArrowSprite") as Sprite2D
		if base_arrow == null:
			var sprite := Sprite2D.new()
			sprite.name = "AimArrowSprite"
			sprite.texture = arrow_texture
			sprite.centered = true
			base_arrow = sprite
			aim_indicator.add_child(base_arrow)
	else:
		var polygon_arrow := aim_indicator.get_node_or_null("AimArrow") as Polygon2D
		if polygon_arrow == null:
			polygon_arrow = aim_indicator.get_node_or_null("AimUp") as Polygon2D
		if polygon_arrow == null:
			polygon_arrow = Polygon2D.new()
			polygon_arrow.name = "AimArrow"
			polygon_arrow.polygon = PackedVector2Array([Vector2(0, -10), Vector2(6, 2), Vector2(-6, 2)])
			polygon_arrow.color = Color(1, 0.9, 0.4, 1)
			aim_indicator.add_child(polygon_arrow)
		base_arrow = polygon_arrow
	aim_arrow = base_arrow
	aim_arrow.visible = false
	aim_arrow.position = Vector2.ZERO
	aim_arrow.rotation = 0.0
	aim_arrow.z_index = 1
	aim_segments.clear()
	var segment_texture := load(AIM_SEGMENT_TEXTURE_PATH)
	for i in range(AIM_SEGMENT_COUNT):
		var seg_name := "AimSegment%d" % i
		var segment_node: Node2D = null
		if segment_texture is Texture2D:
			segment_node = trail_root.get_node_or_null(seg_name) as Sprite2D
			if segment_node == null:
				var seg_sprite := Sprite2D.new()
				seg_sprite.name = seg_name
				seg_sprite.texture = segment_texture
				seg_sprite.centered = true
				seg_sprite.scale = Vector2(AIM_SEGMENT_SCALE, AIM_SEGMENT_SCALE)
				segment_node = seg_sprite
				trail_root.add_child(segment_node)
		else:
			segment_node = trail_root.get_node_or_null(seg_name) as Polygon2D
			if segment_node == null:
				var segment := Polygon2D.new()
				segment.name = seg_name
				var half := AIM_SEGMENT_SIZE * 0.5
				segment.polygon = PackedVector2Array([
					Vector2(-half.x, -half.y),
					Vector2(half.x, -half.y),
					Vector2(half.x, half.y),
					Vector2(-half.x, half.y),
				])
				segment.color = Color(1, 0.88, 0.35, AIM_SEGMENT_ALPHA)
				segment_node = segment
				trail_root.add_child(segment_node)
		segment_node.visible = false
		if segment_node is CanvasItem:
			segment_node.self_modulate = Color(1, 0.88, 0.35, AIM_SEGMENT_ALPHA)
		aim_segments.append(segment_node)
	for child in aim_indicator.get_children():
		if child != aim_arrow and child != trail_root and child is CanvasItem:
			child.visible = false
	for child in trail_root.get_children():
		if child is CanvasItem:
			child.visible = false

func setup_base_profile() -> void:
	if _is_headless_runtime():
		return
	var profile := _get_base_profile()
	bow_node = null
	if profile != null and profile.bow_node_path != NodePath("") and owner != null and owner.has_node(profile.bow_node_path):
		bow_node = owner.get_node_or_null(profile.bow_node_path) as Node2D
	if bow_node == null:
		bow_node = bow_poly
	if bow_node != null:
		base_bow_position = bow_node.position
		base_bow_rotation = bow_node.rotation

func cache_body_shape_defaults() -> void:
	if _is_headless_runtime():
		return
	if body_shape == null:
		return
	if not (body_shape.shape is RectangleShape2D):
		return
	var rect := body_shape.shape as RectangleShape2D
	base_body_size = rect.size
	base_body_position = body_shape.position

func sync_hurtbox_to_body() -> void:
	if _is_headless_runtime():
		return
	if hurtbox == null or body_shape == null:
		return
	var hurt_shape := hurtbox.get_node_or_null("CollisionShape2D")
	if hurt_shape == null:
		return
	if not (body_shape.shape is RectangleShape2D) or not (hurt_shape.shape is RectangleShape2D):
		return
	var body_rect := body_shape.shape as RectangleShape2D
	var hurt_rect := hurt_shape.shape as RectangleShape2D
	hurt_rect.size = body_rect.size * HURTBOX_SCALE
	hurt_shape.position = body_shape.position
	hurtbox.position = Vector2.ZERO

func update_aim_indicator(aim_input: Vector2, active: bool) -> void:
	if aim_indicator == null or aim_arrow == null:
		return
	var origin := Vector2.ZERO
	var radius := AIM_RADIUS_DEFAULT
	if body_shape != null and body_shape.shape is RectangleShape2D:
		var rect := body_shape.shape as RectangleShape2D
		radius = max(rect.size.x, rect.size.y) * AIM_RADIUS_MULT
		origin = body_shape.position
	aim_indicator.position = origin
	if not active or aim_input == Vector2.ZERO:
		aim_arrow.visible = false
		for segment in aim_segments:
			if segment is CanvasItem:
				segment.visible = false
		return
	var dir := aim_input.normalized()
	var angle := dir.angle()
	aim_arrow.position = dir * radius
	aim_arrow.rotation = angle + PI * 0.5
	aim_arrow.visible = true
	if aim_arrow is CanvasItem:
		aim_arrow.self_modulate = Color(1, 0.88, 0.35, 1)
	aim_arrow.scale = Vector2(AIM_ACTIVE_SCALE, AIM_ACTIVE_SCALE)
	var count := aim_segments.size()
	for i in range(count):
		var segment := aim_segments[i]
		if not (segment is CanvasItem):
			continue
		var t := float(i + 1) / float(count + 1)
		segment.position = dir * (radius * t)
		segment.rotation = angle
		segment.visible = true

func update_bow_aim(aim_input: Vector2, active: bool) -> void:
	if bow_node == null:
		return
	var profile := _get_base_profile()
	if profile == null:
		return
	var position_offset := profile.bow_offset
	var aim_offset := profile.bow_offset_aim if active and aim_input != Vector2.ZERO else Vector2.ZERO
	bow_node.position = base_bow_position + position_offset + aim_offset
	if profile.bow_rotate:
		if active and aim_input != Vector2.ZERO:
			bow_node.rotation = aim_input.normalized().angle()
		else:
			bow_node.rotation = base_bow_rotation
	else:
		bow_node.rotation = base_bow_rotation

func update_crouch_state(input_reader, on_floor: bool) -> bool:
	if input_reader == null:
		return is_crouching
	var crouch_pressed: bool = input_reader.is_action_pressed("down") and on_floor
	if crouch_pressed != is_crouching:
		_apply_crouch(crouch_pressed)
		_set_crouch_visuals(crouch_pressed)
	return is_crouching

func update_character_sprite(aim_input: Vector2, dash_active: bool, facing: int, is_dead: bool, on_floor: bool, velocity_x: float, aim_hold_active: bool) -> void:
	var action_key := _resolve_action_key(dash_active, on_floor, velocity_x, aim_hold_active)
	_apply_collider_override(action_key)
	if character_sprite == null or not _has_cached_character_assets():
		return
	if is_dead:
		return
	var action := _resolve_action_name(action_key)
	var profile := _get_base_profile()
	var use_8_dir := profile != null and profile.use_8_dir_aim and action_key == "aim"
	var direction := _resolve_direction(aim_input, use_8_dir, facing)
	var selection: Dictionary = _pick_animation_with_flip(action, direction, facing)
	var anim := ""
	if selection.has("name"):
		anim = String(selection["name"])
	var flip_h := bool(selection.get("flip", false))
	var frames: SpriteFrames = character_sprite.sprite_frames
	if anim != "" and frames and frames.has_animation(anim):
		character_sprite.flip_h = flip_h
		if character_sprite.animation != anim:
			_apply_animation_offset(anim)
			if action == "dash":
				print("[ANIM] Playing dash animation: '%s' (frames: %d)" % [anim, frames.get_frame_count(anim)])
			character_sprite.play(anim)
		_apply_animation_offset(anim)

func get_projectile_spawn_offset(direction: Vector2, facing: int) -> Vector2:
	var dir := direction
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	var base_origin := _body_chest_position(facing)
	if bow_node != null and bow_node.is_inside_tree() and owner != null:
		base_origin = owner.to_local(bow_node.global_position)
	var forward := character_data.projectile_forward if character_data else 80.0
	var vertical := character_data.projectile_vertical_offset if character_data else 0.0
	return base_origin + dir * forward + Vector2(0, vertical)

func play_death_animation(facing: int) -> void:
	if character_sprite == null or character_sprite.sprite_frames == null:
		return
	var direction = "east" if facing >= 0 else "west"
	var anim := _pick_animation("death", direction, facing)
	if anim != "" and character_sprite.sprite_frames.has_animation(anim):
		character_sprite.play(anim)

func _body_chest_position(facing: int) -> Vector2:
	if body_shape != null and body_shape.shape is RectangleShape2D:
		var rect := body_shape.shape as RectangleShape2D
		var center: Vector2 = body_shape.position
		return Vector2(
			center.x + rect.size.x * 0.15 * facing,
			center.y - rect.size.y * 0.35
		)
	return Vector2(18.0 * facing, -48.0)

func _get_base_profile() -> CharacterBaseProfile:
	if character_data != null and character_data.base_profile != null:
		return character_data.base_profile
	if _default_profile == null:
		_default_profile = CharacterBaseProfile.new()
	return _default_profile

func _character_base_path() -> String:
	if character_data != null and character_data.asset_base_path != "":
		var base_path := character_data.asset_base_path
		if not base_path.ends_with("/"):
			base_path += "/"
		return base_path
	return ""

func _character_sprite_scale() -> Vector2:
	if character_data != null and character_data.sprite_scale != Vector2.ZERO:
		return character_data.sprite_scale
	return Vector2(3.6, 3.6)

func _has_character_assets(base_path: String) -> bool:
	if base_path == "":
		return false
	var dir := DirAccess.open(base_path + "rotations/")
	if dir == null:
		return false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "png":
			dir.list_dir_end()
			return true
		file_name = dir.get_next()
	dir.list_dir_end()
	return false

func _has_cached_character_assets() -> bool:
	var base_path := _character_base_path()
	if base_path == "":
		_cached_assets_base_path = ""
		_cached_has_assets = false
		return false
	if base_path != _cached_assets_base_path:
		_cached_assets_base_path = base_path
		_cached_has_assets = _has_character_assets(base_path)
	return _cached_has_assets

func _apply_crouch(active: bool) -> void:
	if body_shape == null or not (body_shape.shape is RectangleShape2D):
		is_crouching = false
		return
	if base_body_size == Vector2.ZERO:
		cache_body_shape_defaults()
	var rect := body_shape.shape as RectangleShape2D
	var target_size := base_body_size
	if active:
		target_size = Vector2(base_body_size.x, base_body_size.y * CROUCH_HEIGHT_SCALE)
	rect.size = target_size
	var target_position := base_body_position
	if active:
		target_position = Vector2(0, -target_size.y * 0.5)
	body_shape.position = target_position
	is_crouching = active
	sync_hurtbox_to_body()

func _set_crouch_visuals(active: bool) -> void:
	var has_character_sprite := character_sprite != null and _has_cached_character_assets()
	if character_sprite:
		if not has_character_sprite:
			var target_scale: Vector2 = base_sprite_scale * (Vector2.ONE if not active else Vector2(1.0, 0.9))
			character_sprite.scale = target_scale
			character_sprite.position = base_sprite_position + (Vector2.ZERO if not active else Vector2(0, 6))
	for poly in [body_poly, legs_poly, head_poly, bow_poly]:
		if poly is CanvasItem:
			poly.self_modulate = Color(0.9, 0.9, 0.9, 1) if active else Color(1, 1, 1, 1)
	_update_debug_overlay(character_sprite.animation if character_sprite != null else "")

func _crouch_sprite_offset() -> Vector2:
	if base_sprite_scale == Vector2.ZERO or base_body_size == Vector2.ZERO:
		return Vector2.ZERO
	var profile := _get_base_profile()
	if profile != null:
		return profile.crouch_sprite_offset
	var target_height: float = base_body_size.y * CROUCH_HEIGHT_SCALE
	var drop: float = max(base_body_size.y - target_height, 0.0) * 0.5
	return Vector2(0, drop)

func _apply_animation_offset(anim_name: String) -> void:
	if character_sprite == null:
		return
	var offsets: Array = animation_frame_offsets.get(anim_name, [])
	var frame_idx := 0
	if character_sprite.frame > 0:
		frame_idx = character_sprite.frame
	if offsets.size() > 0:
		frame_idx = clamp(frame_idx, 0, offsets.size() - 1)
	var target := base_animation_offset
	if offsets.size() > 0 and offsets[frame_idx] is Vector2:
		target = offsets[frame_idx]
	character_sprite.position = target
	character_sprite.scale = base_sprite_scale
	_update_debug_overlay(anim_name)

func _resolve_action(dash_active: bool, on_floor: bool, velocity_x: float, aim_hold_active: bool) -> String:
	return _resolve_action_name(_resolve_action_key(dash_active, on_floor, velocity_x, aim_hold_active))

func _resolve_action_key(dash_active: bool, on_floor: bool, velocity_x: float, aim_hold_active: bool) -> String:
	if current_override_action != "":
		return current_override_action
	if is_crouching:
		return "crouch"
	if dash_active:
		return "dash"
	if aim_hold_active and shoot_anim_timer <= 0.0:
		return "aim"
	if shoot_anim_timer > 0.0:
		return "shoot"
	if ult_anim_timer > 0.0:
		return "ult"
	if melee_anim_timer > 0.0:
		return "melee"
	if jump_start_timer > 0.0:
		return "jump_start"
	if !on_floor:
		return "jump_air"
	if abs(velocity_x) > 10.0:
		return _ground_movement_action()
	return "idle"

func _ground_movement_action() -> String:
	if has_running_animation:
		return "running"
	return "walk"

func _resolve_action_name(action_key: String) -> String:
	var profile := _get_base_profile()
	if profile == null:
		return action_key
	return profile.action_prefix(action_key)

func _fallback_direction(direction: String, facing: int) -> String:
	match direction:
		"up", "down":
			return "left" if facing < 0 else "right"
		"up_left", "down_left":
			return "left"
		"up_right", "down_right":
			return "right"
		_:
			return direction

func _resolve_action_from_anim(anim_name: String) -> String:
	if anim_name == "":
		return ""
	var profile := _get_base_profile()
	if profile == null:
		return anim_name
	var action_map := {
		"idle": profile.action_idle,
		"walk": profile.action_walk,
		"running": profile.action_running,
		"dash": profile.action_dash,
		"jump_start": profile.action_jump_start,
		"jump_air": profile.action_jump_air,
		"crouch": profile.action_crouch,
		"aim": profile.action_aim,
		"shoot": profile.action_shoot,
		"melee": profile.action_melee,
		"hurt": profile.action_hurt,
		"death": profile.action_death
	}
	for action_key in action_map.keys():
		var prefix: String = str(action_map[action_key])
		if prefix == "":
			continue
		if anim_name == prefix or anim_name.begins_with(prefix + "_"):
			return action_key
	return anim_name

func _lock_action_for_duration(action: String, duration: float, lock_duration: float) -> void:
	if action == "":
		return
	if duration > 0.0:
		action_lock_timers[action] = duration
	request_action_override(action, get_action_priority(action, 0), lock_duration)

func _update_action_lock_timers(delta: float) -> void:
	var to_release: Array[String] = []
	for action in action_lock_timers.keys():
		var remaining := float(action_lock_timers[action]) - delta
		if remaining <= 0.0:
			to_release.append(action)
		else:
			action_lock_timers[action] = remaining
	for action in to_release:
		action_lock_timers.erase(action)
		release_action_override(action)

func _resolve_target_visual_height(action: String, fallback_height: float) -> float:
	var target := 0.0
	if character_data != null:
		if character_data.action_target_visual_height.has(action):
			var value: Variant = character_data.action_target_visual_height[action]
			if value is float or value is int:
				target = float(value)
		if target <= 0.0 and character_data.target_visual_height > 0.0:
			target = character_data.target_visual_height
	if target <= 0.0:
		target = fallback_height
	return target

func _resolve_ground_anchor_ratio(action: String) -> float:
	var ratio := 1.0
	if character_data != null:
		if action != "" and character_data.action_ground_anchor_ratio.has(action):
			var value: Variant = character_data.action_ground_anchor_ratio[action]
			if value is float or value is int:
				ratio = float(value)
		elif character_data.ground_anchor_ratio > 0.0:
			ratio = character_data.ground_anchor_ratio
	return clamp(ratio, 0.0, 1.0)

func _resolve_reference_collider_size() -> Vector2:
	var width := 0.0
	var height := 0.0
	if base_body_size != Vector2.ZERO:
		width = base_body_size.x
		height = base_body_size.y
	if character_data != null:
		if width <= 0.0:
			if character_data.collider_size.x > 0.0:
				width = character_data.collider_size.x
		if height <= 0.0:
			if character_data.collider_size.y > 0.0:
				height = character_data.collider_size.y
	if width <= 0.0:
		width = DEFAULT_BODY_WIDTH
	if height <= 0.0:
		height = DEFAULT_BODY_HEIGHT
	return Vector2(width, height)

func _apply_collider_override(action_key: String) -> void:
	if body_shape == null or not (body_shape.shape is RectangleShape2D):
		return
	if is_crouching:
		current_collider_action = "crouch"
		return
	if action_key == current_collider_action:
		return
	if base_body_size == Vector2.ZERO:
		cache_body_shape_defaults()
	var rect := body_shape.shape as RectangleShape2D
	var target_size := base_body_size
	var target_position := base_body_position
	if character_data != null and character_data.action_collider_overrides.has(action_key):
		var override_value: Variant = character_data.action_collider_overrides[action_key]
		if override_value is Dictionary:
			var override_dict := override_value as Dictionary
			if override_dict.has("size") and override_dict["size"] is Vector2:
				target_size = override_dict["size"]
			if override_dict.has("offset") and override_dict["offset"] is Vector2:
				target_position = override_dict["offset"]
			elif override_dict.has("position") and override_dict["position"] is Vector2:
				target_position = override_dict["position"]
	if rect.size != target_size:
		rect.size = target_size
		_last_collider_size = target_size
	body_shape.position = target_position
	sync_hurtbox_to_body()
	current_collider_action = action_key

func _resolve_sprite_anchor_offset() -> Vector2:
	if character_data != null and character_data.sprite_anchor_offset != Vector2.ZERO:
		return character_data.sprite_anchor_offset
	return Vector2.ZERO

func _update_debug_overlay(anim_name: String) -> void:
	if not debug_overlay_enabled or debug_overlay == null:
		return
	var action := _resolve_action_from_anim(anim_name)
	var reference_size := _resolve_reference_collider_size()
	var anchor_ratio := _resolve_ground_anchor_ratio(action)
	debug_overlay.update_state(anim_name, action, anchor_ratio, reference_size.y)

func _pick_animation_with_flip(action: String, direction: String, facing: int) -> Dictionary:
	var result := {"name": "", "flip": false}
	if character_sprite == null or character_sprite.sprite_frames == null:
		return result
	var frames: SpriteFrames = character_sprite.sprite_frames
	var candidates: Array = []
	var canonical_direction := direction
	candidates.append({"name": "%s_%s" % [action, canonical_direction], "flip": false})
	if canonical_direction == "left":
		candidates.append({"name": "%s_right" % action, "flip": true})
	elif canonical_direction == "right":
		candidates.append({"name": "%s_left" % action, "flip": true})
	var fallback_dir := _fallback_direction(canonical_direction, facing)
	if fallback_dir != canonical_direction:
		candidates.append({"name": "%s_%s" % [action, fallback_dir], "flip": false})
	candidates.append({"name": action, "flip": false})
	var direction_priority := [canonical_direction, "right", "left", "up", "down", "up_right", "up_left", "down_right", "down_left"]
	for dir_name in direction_priority:
		candidates.append({"name": "%s_%s" % [action, dir_name], "flip": dir_name == "right" and canonical_direction == "left"})
	candidates.append({"name": canonical_direction, "flip": false})
	candidates.append({"name": "right", "flip": canonical_direction == "left"})
	candidates.append({"name": "left", "flip": false})
	for candidate in candidates:
		var anim_name: String = candidate.get("name", "")
		if anim_name == "":
			continue
		if frames.has_animation(anim_name):
			return candidate
	return result

func _pick_animation(action: String, direction: String, facing: int) -> String:
	var selection := _pick_animation_with_flip(action, direction, facing)
	if selection.has("name"):
		return String(selection["name"])
	return ""

func _resolve_direction(aim_input: Vector2, use_8_dir: bool, facing: int) -> String:
	if aim_input == Vector2.ZERO:
		return "right" if facing >= 0 else "left"
	if use_8_dir:
		var x := int(sign(aim_input.x))
		var y := int(sign(aim_input.y))
		if x == 0 and y < 0:
			return "up"
		if x == 0 and y > 0:
			return "down"
		if y == 0 and x > 0:
			return "right"
		if y == 0 and x < 0:
			return "left"
		if x > 0 and y < 0:
			return "up_right"
		if x < 0 and y < 0:
			return "up_left"
		if x > 0 and y > 0:
			return "down_right"
		if x < 0 and y > 0:
			return "down_left"
	var dir := aim_input.normalized()
	var abs_x := absf(dir.x)
	var abs_y := absf(dir.y)
	if dir.y < -0.35 and abs_y >= abs_x:
		return "up"
	if abs_x >= 0.2:
		return "right" if dir.x >= 0.0 else "left"
	return "right" if facing >= 0 else "left"

func _animation_paths(action: String, defaults: Array[String], base_path: String) -> Array[String]:
	var resolved: Array[String] = []
	print("[ANIM] _animation_paths called for action '%s'" % action)
	if character_data != null:
		for lookup_action in _candidate_action_keys(action):
			if not character_data.action_animation_paths.has(lookup_action):
				continue
			var custom: Variant = character_data.action_animation_paths[lookup_action]
			if custom is Array:
				for path in custom:
					if path is String:
						var converted := _resolve_animation_path(path, base_path)
						if converted != "":
							resolved.append(converted)
			elif custom is String:
				var converted := _resolve_animation_path(custom, base_path)
				if converted != "":
					resolved.append(converted)
	if not resolved.is_empty():
		print("[ANIM] Using custom paths for '%s': %s" % [action, resolved])
		return resolved
	print("[ANIM] Using default paths for '%s': %s" % [action, defaults])
	return defaults

func _resolve_animation_path(path: String, base_path: String) -> String:
	if path == "":
		return ""
	var resolved := path
	if path.begins_with("res://"):
		resolved = path
	elif path.begins_with("/"):
		resolved = path
	else:
		resolved = base_path + path.trim_prefix("./")
	if not resolved.ends_with("/"):
		resolved += "/"
	return resolved

func _load_directional_rotations(frames: SpriteFrames, rotations_path: String) -> void:
	print("[ANIM] Loading rotations from: %s" % rotations_path)
	var direction_files := {
		"right": ["right.png", "east.png"],
		"left": ["left.png", "west.png"],
		"up": ["up.png", "north.png"],
		"down": ["down.png", "south.png"]
	}
	for dir_name in direction_files.keys():
		var loaded := false
		for file_name in direction_files[dir_name]:
			var full_path: String = rotations_path + file_name
			var texture := load(full_path)
			if texture:
				frames.add_animation(dir_name)
				frames.add_frame(dir_name, texture)
				frames.set_animation_speed(dir_name, 1.0)
				print("[ANIM] Loaded rotation '%s' from '%s'" % [dir_name, full_path])
				loaded = true
				break
		if not loaded:
			print("[ANIM] WARNING: Failed to load rotation '%s'" % dir_name)

func _load_single_animation(frames: SpriteFrames, folder_path: String, animation_name: String, speed: float) -> void:
	if _load_frames_from_folder(frames, animation_name, folder_path):
		frames.set_animation_speed(animation_name, speed)

func _load_action_variants(frames: SpriteFrames, action: String, speed: float, base_paths: Array[String]) -> void:
	print("[ANIM] _load_action_variants for '%s' with %d paths" % [action, base_paths.size()])
	var loaded_any := false
	for base_path in base_paths:
		print("[ANIM] Trying to load '%s' from: %s" % [action, base_path])
		if _load_animation_set(frames, base_path, action, speed):
			loaded_any = true
	if not loaded_any:
		print("[ANIM] WARNING: failed to load any variations for '%s'" % action)


func _load_animation_set(frames: SpriteFrames, base_path: String, action: String, speed: float) -> bool:
	var direction_variants := {
		"right": ["right", "east"],
		"left": ["left", "west"],
		"up": ["up", "north"],
		"down": ["down", "south"],
		"up_right": ["up-right", "upright", "north-east", "northeast"],
		"up_left": ["up-left", "upleft", "north-west", "northwest"],
		"down_right": ["down-right", "downright", "south-east", "southeast"],
		"down_left": ["down-left", "downleft", "south-west", "southwest"],
	}
	var loaded := false
	if _has_direction_subfolders(base_path):
		var loaded_dirs: Array[String] = []
		for dir_name in direction_variants.keys():
			var variants: Array = direction_variants[dir_name]
			var resolved_dir := _find_existing_direction_folder(base_path, variants)
			if resolved_dir == "":
				continue
			var animation_name := "%s_%s" % [action, dir_name]
			var folder_path := base_path
			if not folder_path.ends_with("/"):
				folder_path += "/"
			folder_path += resolved_dir + "/"
			if frames.has_animation(animation_name) and frames.get_frame_count(animation_name) > 0:
				continue
			if _load_frames_from_folder(frames, animation_name, folder_path):
				frames.set_animation_speed(animation_name, speed)
				loaded = true
				loaded_dirs.append(animation_name)
			else:
				print("[ANIM] Failed to load '%s' from '%s'" % [animation_name, folder_path])
		if loaded:
			return true

	var shared_animation := "%s_shared" % action
	if _load_frames_from_folder(frames, shared_animation, base_path):
		frames.set_animation_speed(shared_animation, speed)
		if not frames.has_animation(action) or frames.get_frame_count(action) == 0:
			_copy_animation(frames, shared_animation, action)
		for dir_name in direction_variants.keys():
			var animation_name := "%s_%s" % [action, dir_name]
			if frames.has_animation(animation_name) and frames.get_frame_count(animation_name) > 0:
				continue
			_copy_animation(frames, shared_animation, animation_name)
		return true

	print("[ANIM] No directional folders or frames found for '%s' at '%s'" % [action, base_path])
	return false

func _has_direction_subfolders(base_path: String) -> bool:
	var dir := DirAccess.open(base_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			dir.list_dir_end()
			return true
		entry = dir.get_next()
	dir.list_dir_end()
	return false

func _find_existing_direction_folder(base_path: String, variants: Array) -> String:
	if variants.is_empty():
		return ""
	var dir := DirAccess.open(base_path)
	if dir == null:
		return ""
	var normalized_variants: Array[String] = []
	for variant in variants:
		if variant is String:
			normalized_variants.append(variant.to_lower())
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			var entry_normalized := entry.to_lower()
			if entry_normalized in normalized_variants:
				dir.list_dir_end()
				return entry
		entry = dir.get_next()
	dir.list_dir_end()
	return ""

func _copy_animation(frames: SpriteFrames, source_anim: String, target_anim: String) -> void:
	if not frames.has_animation(source_anim):
		return
	var frame_count := frames.get_frame_count(source_anim)
	if frame_count == 0:
		return
	if frames.has_animation(target_anim):
		frames.remove_animation(target_anim)
	frames.add_animation(target_anim)
	var source_speed := frames.get_animation_speed(source_anim)
	for i in frame_count:
		var tex := frames.get_frame_texture(source_anim, i)
		if tex:
			frames.add_frame(target_anim, tex)
	frames.set_animation_speed(target_anim, source_speed)


const SUPPORTED_FRAME_EXTENSIONS := ["png", "gif"]

func _load_frames_from_folder(frames: SpriteFrames, animation_name: String, folder_path: String) -> bool:
	var dir := DirAccess.open(folder_path)
	if dir == null:
		return false
	var files := _list_frame_files(dir)
	if files.is_empty():
		return false
	if not frames.has_animation(animation_name):
		frames.add_animation(animation_name)
	for file_name in files:
		var texture := load(folder_path + file_name)
		if texture:
			frames.add_frame(animation_name, texture)
	return true

func _load_frames_from_pattern(frames: SpriteFrames, animation_name: String, base_path: String, dir_name: String) -> bool:
	var dir := DirAccess.open(base_path)
	if dir == null:
		return false
	var files := []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_direction_frame(file_name, dir_name):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	if files.is_empty():
		return false
	if not frames.has_animation(animation_name):
		frames.add_animation(animation_name)
	for file in files:
		var texture := load(base_path + file)
		if texture:
			frames.add_frame(animation_name, texture)
	return true

func _list_frame_files(dir: DirAccess) -> Array:
	var files := []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			if ext in SUPPORTED_FRAME_EXTENSIONS:
				files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files

func _is_direction_frame(file_name: String, dir_name: String) -> bool:
	if file_name.get_extension().to_lower() not in SUPPORTED_FRAME_EXTENSIONS:
		return false
	return file_name.begins_with(dir_name + "_") or file_name.begins_with(dir_name + "-")

func _load_idle_from_rotations(frames: SpriteFrames, rotations_path: String) -> void:
	var directions := {
		"south": "south.png",
		"south_east": "south-east.png",
		"east": "east.png",
		"north_east": "north-east.png",
		"north": "north.png",
		"north_west": "north-west.png",
		"west": "west.png",
		"south_west": "south-west.png"
	}
	for dir_name in directions.keys():
		var texture := load(rotations_path + directions[dir_name])
		if texture:
			var animation_name := "idle_%s" % dir_name
			frames.add_animation(animation_name)
			frames.add_frame(animation_name, texture)
			frames.set_animation_speed(animation_name, 1.0)

func _texture_used_rect(texture: Texture2D) -> Rect2i:
	if texture == null:
		return Rect2i()
	var image := texture.get_image()
	if image == null:
		return Rect2i()
	return image.get_used_rect()

func _theme_color() -> Color:
	if player_id == 1:
		return Color(0.9, 0.95, 1.0, 1)
	return Color(0.95, 0.35, 0.35, 1)

func _spawn_dash_ghost() -> void:
	if owner == null:
		return
	var ghost := Node2D.new()
	ghost.global_position = owner.global_position
	ghost.rotation = owner.rotation
	ghost.scale = owner.scale
	ghost.z_index = -1
	var ghost_color = _theme_color()
	ghost_color.a = 0.5
	for poly in [body_poly, legs_poly, head_poly, bow_poly]:
		if poly is Polygon2D:
			var clone = poly.duplicate()
			clone.color = ghost_color
			ghost.add_child(clone)
	owner.get_tree().current_scene.add_child(ghost)
	var tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate", Color(ghost.modulate.r, ghost.modulate.g, ghost.modulate.b, 0.0), 0.25)
	tween.tween_callback(Callable(ghost, "queue_free"))
