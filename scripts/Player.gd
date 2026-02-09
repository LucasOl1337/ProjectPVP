extends CharacterBody2D

signal died(player)

const PlayerMovement = preload("res://scripts/modules/player_movement.gd")
const PlayerDash = preload("res://scripts/modules/player_dash.gd")
const PlayerShoot = preload("res://scripts/modules/player_shoot.gd")
const PlayerHitbox = preload("res://scripts/modules/player_hitbox.gd")
const PlayerInput = preload("res://scripts/modules/player_input.gd")
const PlayerCombat = preload("res://scripts/modules/player_combat.gd")
const PlayerVisuals = preload("res://scripts/modules/player_visuals.gd")
const CollisionLayers = preload("res://scripts/modules/collision_layers.gd")
const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const StatsComponent = preload("res://scripts/modules/stats_component.gd")
const DEFAULT_PROJECTILE_TEXTURE := preload("res://assets/characters/arrow/custom/crystal_arrow.png")

@export var player_id := 1
@export var character_id := ""
@export var move_speed := 240.0
@export var acceleration := 1600.0
@export var friction := 2000.0
@export var jump_velocity := 360.0
@export var gravity := 1200.0
@export var shoot_cooldown := 0.001
@export var arrow_scene: PackedScene
@export var max_arrows := 5
@export var dash_multiplier := 1.8
@export var dash_duration := 0.1		
@export var dash_cooldown := 0.45
@export var melee_cooldown := 0.45
@export var melee_duration := 0.12

var facing := 1
var movement := PlayerMovement.new()
var dash := PlayerDash.new()
var shooter := PlayerShoot.new()
var hitbox := PlayerHitbox.new()
var input_reader := PlayerInput.new()
var combat := PlayerCombat.new()
var stats := StatsComponent.new()
var visuals := PlayerVisuals.new()
var last_dash_velocity := Vector2.ZERO
var arrows := 0
var is_dead := false
var character_data: CharacterData = null
var dash_parry_timer := 0.0
var dash_press_timer := 0.0
var aim_hold_active := false
var aim_hold_dir := Vector2.ZERO
var shoot_was_pressed := false
var projectile_texture: Texture2D = null
var dash_jump_used := false

@onready var aim_indicator := get_node_or_null("AimIndicator")
@onready var ammo_label := get_node_or_null("AmmoLabel")
@onready var name_label := get_node_or_null("NameLabel")
@onready var shoot_sfx := get_node_or_null("ShootSfx")
@onready var pickup_sfx := get_node_or_null("PickupSfx")
@onready var parry_sfx := get_node_or_null("ParrySfx")
@onready var body_poly := get_node_or_null("Body")
@onready var legs_poly := get_node_or_null("Legs")
@onready var head_poly := get_node_or_null("Head")
@onready var bow_poly := get_node_or_null("Bow")
@onready var melee_area := get_node_or_null("MeleeArea")
@onready var hurtbox := get_node_or_null("Hurtbox")
var melee_shape: CollisionShape2D = null
var melee_visual: Node2D = null
@onready var body_shape := $CollisionShape2D
@onready var character_sprite := get_node_or_null("CharacterSprite")
var shoot_stream: AudioStreamGenerator
var pickup_stream: AudioStreamGenerator
var parry_stream: AudioStreamGenerator
var action_sfx_players: Dictionary = {}
var action_sfx_stop_timers: Dictionary = {}

func _ready() -> void:
	add_to_group("players")
	hitbox.setup(self)
	_configure_collision_layers()
	input_reader.configure(player_id)
	_load_character_data()
	_apply_character_stats_override()
	_setup_skills()
	_setup_stats()
	visuals.configure(
		self,
		player_id,
		character_id,
		character_data,
		aim_indicator,
		character_sprite,
		body_shape,
		hurtbox,
		body_poly,
		legs_poly,
		head_poly,
		bow_poly
	)
	visuals.apply_player_color()
	_apply_stat_values()
	arrows = max_arrows
	_update_ammo_ui()
	_setup_sfx()
	_setup_action_sfx()
	visuals.configure_character_visuals()
	visuals.setup_character_sprite()
	set_display_name("P%d" % player_id, _get_label_color())
	_make_collision_shapes_unique()
	visuals.align_hitbox_to_sprite()
	visuals.cache_animation_offsets()
	visuals.setup_aim_indicator()
	visuals.setup_base_profile()
	visuals.cache_body_shape_defaults()
	visuals.sync_hurtbox_to_body()
	var debug_enabled := true
	if CharacterSelectionState:
		debug_enabled = CharacterSelectionState.get_debug_hitboxes_enabled()
	visuals.configure_debug_overlay(debug_enabled)
	if melee_area:
		melee_shape = melee_area.get_node_or_null("CollisionShape2D")
		melee_visual = melee_area.get_node_or_null("Dagger")
		melee_area.monitoring = false
		melee_area.monitorable = false
		if melee_shape:
			melee_shape.disabled = true
		melee_area.connect("body_entered", Callable(self, "_on_melee_body_entered"))
		melee_area.connect("area_entered", Callable(self, "_on_melee_area_entered"))
	if hurtbox:
		hurtbox.monitoring = true
		hurtbox.monitorable = true

func _configure_collision_layers() -> void:
	collision_layer = CollisionLayers.PLAYER_BODY
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER_BODY
	if hurtbox:
		hurtbox.collision_layer = CollisionLayers.HURTBOX
		hurtbox.collision_mask = CollisionLayers.PROJECTILE | CollisionLayers.HITBOX
	if melee_area:
		melee_area.collision_layer = CollisionLayers.HITBOX
		melee_area.collision_mask = CollisionLayers.HURTBOX

func _load_character_data() -> void:
	var resolved_id := character_id
	if resolved_id == "":
		if not Engine.is_editor_hint() and CharacterSelectionState != null:
			resolved_id = CharacterSelectionState.get_character(player_id)
		else:
			if player_id == 2:
				var ids := CharacterRegistry.list_character_ids()
				resolved_id = ids[1] if ids.size() > 1 else CharacterRegistry.get_default_id()
			else:
				resolved_id = CharacterRegistry.get_default_id()
	character_id = resolved_id
	character_data = CharacterRegistry.get_character(resolved_id)
	if DevDebug:
		DevDebug.log_event("player%d" % player_id, "carregou %s" % resolved_id)
	visuals.character_id = resolved_id
	visuals.set_character_data(character_data)
	projectile_texture = _resolve_projectile_texture()

func _setup_skills() -> void:
	combat.configure(self, character_data, melee_cooldown, melee_duration)

func _setup_stats() -> void:
	stats.set_bases({
		"move_speed": move_speed,
		"acceleration": acceleration,
		"friction": friction,
		"gravity": gravity,
		"jump_velocity": jump_velocity,
		"shoot_cooldown": shoot_cooldown,
		"max_arrows": float(max_arrows),
		"dash_multiplier": dash_multiplier,
		"dash_duration": dash_duration,
		"dash_cooldown": dash_cooldown,
		"melee_cooldown": melee_cooldown,
		"melee_duration": melee_duration,
	})

func _apply_stat_values() -> void:
	var previous_max_arrows := max_arrows
	move_speed = stats.get_value("move_speed", move_speed)
	acceleration = stats.get_value("acceleration", acceleration)
	friction = stats.get_value("friction", friction)
	gravity = stats.get_value("gravity", gravity)
	jump_velocity = stats.get_value("jump_velocity", jump_velocity)
	shoot_cooldown = stats.get_value("shoot_cooldown", shoot_cooldown)
	max_arrows = int(round(stats.get_value("max_arrows", max_arrows)))
	dash_multiplier = stats.get_value("dash_multiplier", dash_multiplier)
	dash_duration = stats.get_value("dash_duration", dash_duration)
	dash_cooldown = stats.get_value("dash_cooldown", dash_cooldown)
	melee_cooldown = stats.get_value("melee_cooldown", melee_cooldown)
	melee_duration = stats.get_value("melee_duration", melee_duration)
	movement.configure(move_speed, acceleration, friction, gravity, jump_velocity)
	dash.configure(dash_multiplier, dash_duration, dash_cooldown)
	shooter.configure(shoot_cooldown)
	combat.configure_melee(melee_cooldown, melee_duration)
	if arrows > max_arrows:
		arrows = max_arrows
		_update_ammo_ui()
	elif previous_max_arrows != max_arrows:
		_update_ammo_ui()
	stats.clear_dirty()

func _apply_character_stats_override() -> void:
	if character_data == null:
		return
	if not character_data.overrides_stats:
		return
	move_speed = character_data.move_speed
	acceleration = character_data.acceleration
	friction = character_data.friction
	jump_velocity = character_data.jump_velocity
	gravity = character_data.gravity
	shoot_cooldown = character_data.shoot_cooldown
	max_arrows = character_data.max_arrows
	dash_multiplier = character_data.dash_multiplier
	dash_duration = character_data.dash_duration
	dash_cooldown = character_data.dash_cooldown
	melee_cooldown = character_data.melee_cooldown
	melee_duration = character_data.melee_duration

func set_debug_visuals_enabled(enabled: bool) -> void:
	visuals.configure_debug_overlay(enabled)

func set_display_name(display_name: String, color: Color = Color.WHITE) -> void:
	if name_label == null:
		return
	name_label.text = display_name
	name_label.visible = display_name != ""
	name_label.self_modulate = color

func _get_label_color() -> Color:
	if player_id == 1:
		return Color(0.95, 0.95, 0.95)
	return Color(0.9, 0.35, 0.35)

func _make_collision_shapes_unique() -> void:
	if body_shape and body_shape.shape:
		body_shape.shape = body_shape.shape.duplicate()
	if hurtbox:
		var hurt_shape := hurtbox.get_node_or_null("CollisionShape2D")
		if hurt_shape and hurt_shape.shape:
			hurt_shape.shape = hurt_shape.shape.duplicate()

func _physics_process(delta: float) -> void:
	input_reader.capture()
	if stats.is_dirty():
		_apply_stat_values()
	var input_axis := input_reader.get_axis()
	if input_axis != 0.0:
		facing = int(sign(input_axis))
	_update_melee_orientation()
	var aim_input := input_reader.aim_input()
	var shoot_pressed := input_reader.shoot_is_pressed()
	var shoot_just_pressed := shoot_pressed and not shoot_was_pressed
	var shoot_just_released := (not shoot_pressed) and shoot_was_pressed
	if shoot_just_pressed and arrows > 0:
		aim_hold_active = true
		aim_hold_dir = input_reader.aim_direction(aim_input, facing)
	if aim_hold_active:
		var hold_dir := input_reader.aim_direction(aim_input, facing)
		if hold_dir != Vector2.ZERO:
			aim_hold_dir = hold_dir
	visuals.update_aim_indicator(aim_hold_dir, aim_hold_active)
	visuals.update_bow_aim(aim_hold_dir, aim_hold_active)
	var is_crouching := visuals.update_crouch_state(input_reader, is_on_floor())
	var jump_pressed := input_reader.jump_pressed(is_crouching)

	dash.update_cooldowns(delta)
	dash.update_grounded(is_on_floor())
	var dash_press_list := input_reader.dash_pressed()
	var dash_inputs := dash.collect_combo_inputs(dash_press_list)
	var previous_dash_velocity := last_dash_velocity
	velocity -= previous_dash_velocity

	movement.update(self, input_axis, jump_pressed, delta)

	var dash_dir := input_reader.aim_direction(aim_input, facing).normalized()
	if dash_press_list.size() > 0:
		dash_press_timer = 0.2
	var dash_triggered := dash.try_trigger(dash_inputs, dash_dir, move_speed)
	if dash_triggered:
		dash_parry_timer = 0.2
		var dash_anim_duration := visuals.get_action_animation_duration("dash", 0.3)
		visuals.hold_dash_animation(dash_anim_duration)
	var dash_velocity := dash.update_and_get_velocity(delta)
	if previous_dash_velocity != Vector2.ZERO and dash_velocity == Vector2.ZERO:
		velocity += previous_dash_velocity
		last_dash_velocity = Vector2.ZERO
	else:
		velocity += dash_velocity
		last_dash_velocity = dash_velocity
	if dash.is_dashing() and jump_pressed and not dash_jump_used:
		velocity.y = min(velocity.y, -jump_velocity)
		dash_jump_used = true
	elif is_on_floor():
		dash_jump_used = false

	_update_parry_timers(delta)
	combat.update(delta)
	_handle_melee(delta)
	_handle_ult()
	shooter.update(delta)
	if aim_hold_active and shoot_just_released:
		aim_hold_active = false
		if arrows > 0:
			if shooter.try_shoot(self, arrow_scene, aim_hold_dir, projectile_texture):
				arrows = max(arrows - 1, 0)
				_update_ammo_ui()
				_play_shoot_sfx()
				visuals.trigger_shoot_animation(0.6)

	visuals.update_animation_timers(delta)
	var dash_anim_active := visuals.is_dash_anim_active(dash.is_dashing())
	visuals.update_character_sprite(
		aim_input,
		dash_anim_active,
		facing,
		is_dead,
		is_on_floor(),
		velocity.x,
		aim_hold_active
	)
	visuals.update_visuals(delta, dash.is_dashing(), facing)

	move_and_slide()
	_check_head_stomp()
	shoot_was_pressed = shoot_pressed

func hit() -> void:
	die()

func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	visuals.play_death_animation(facing)
	emit_signal("died", self)

func can_parry() -> bool:
	return dash_parry_timer > 0.0

func receive_arrow(arrow: Node) -> void:
	if is_dead:
		return
	if dash_parry_timer > 0.0 or dash_press_timer > 0.0:
		add_arrows(1)
		on_parry()
		dash_press_timer = 0.0
		dash_parry_timer = 0.0
		if arrow != null and is_instance_valid(arrow):
			arrow.queue_free()
		return
	if arrow != null and is_instance_valid(arrow):
		if arrow.has_method("attach_to_target"):
			arrow.attach_to_target(self)
		else:
			arrow.queue_free()
	die()

func on_parry() -> void:
	visuals.trigger_parry(0.3)
	_play_parry_sfx()

func reset_for_round(new_position: Vector2) -> void:
	is_dead = false
	global_position = new_position
	velocity = Vector2.ZERO
	set_physics_process(true)
	arrows = max_arrows
	_update_ammo_ui()
	dash_parry_timer = 0.0
	dash_press_timer = 0.0
	visuals.reset_state()
	_set_melee_active(false)
	combat.reset()

func add_arrows(amount: int) -> void:
	arrows = clamp(arrows + amount, 0, max_arrows)
	_update_ammo_ui()
	_play_pickup_sfx()

func add_stat_modifier(stat: String, modifier_id: String, flat: float = 0.0, mult: float = 1.0) -> void:
	stats.add_modifier(stat, modifier_id, flat, mult)

func remove_stat_modifier(stat: String, modifier_id: String) -> void:
	stats.remove_modifier(stat, modifier_id)

func get_stat_value(stat: String, default_value: float = 0.0) -> float:
	return stats.get_value(stat, default_value)

func get_state() -> Dictionary:
	return {
		"global_position": global_position,
		"velocity": velocity,
		"facing": facing,
		"is_dead": is_dead,
		"arrows": arrows,
		"dash_parry_timer": dash_parry_timer,
		"dash_press_timer": dash_press_timer,
		"aim_hold_active": aim_hold_active,
		"aim_hold_dir": aim_hold_dir,
		"shoot_was_pressed": shoot_was_pressed,
		"last_dash_velocity": last_dash_velocity,
		"dash_jump_used": dash_jump_used,
		"stats": stats.get_state(),
		"dash": dash.get_state(),
		"shooter": shooter.get_state(),
		"combat": combat.get_state(),
		"projectile_texture_path": _projectile_texture_path()
	}

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("global_position"):
		global_position = state["global_position"]
	if state.has("velocity"):
		velocity = state["velocity"]
	if state.has("facing"):
		facing = int(state["facing"])
	if state.has("is_dead"):
		is_dead = bool(state["is_dead"])
		set_physics_process(not is_dead)
	if state.has("arrows"):
		arrows = int(state["arrows"])
		_update_ammo_ui()
	if state.has("dash_parry_timer"):
		dash_parry_timer = float(state["dash_parry_timer"])
	if state.has("dash_press_timer"):
		dash_press_timer = float(state["dash_press_timer"])
	if state.has("aim_hold_active"):
		aim_hold_active = bool(state["aim_hold_active"])
	if state.has("aim_hold_dir"):
		aim_hold_dir = state["aim_hold_dir"]
	if state.has("shoot_was_pressed"):
		shoot_was_pressed = bool(state["shoot_was_pressed"])
	if state.has("last_dash_velocity"):
		last_dash_velocity = state["last_dash_velocity"]
	if state.has("dash_jump_used"):
		dash_jump_used = bool(state["dash_jump_used"])
	if state.has("stats") and state["stats"] is Dictionary:
		stats.apply_state(state["stats"])
		if stats.is_dirty():
			_apply_stat_values()
	if state.has("dash") and state["dash"] is Dictionary:
		dash.apply_state(state["dash"])
	if state.has("shooter") and state["shooter"] is Dictionary:
		shooter.apply_state(state["shooter"])
	if state.has("combat") and state["combat"] is Dictionary:
		combat.apply_state(state["combat"])
	if state.has("projectile_texture_path"):
		_set_projectile_texture_from_path(state["projectile_texture_path"])
	_set_melee_active(combat.is_melee_active())
	_update_melee_orientation()

func _projectile_texture_path() -> String:
	if projectile_texture and projectile_texture.resource_path != "":
		return projectile_texture.resource_path
	return ""

func _set_projectile_texture_from_path(path_variant: Variant) -> void:
	if path_variant is String and path_variant != "":
		var loaded := load(path_variant)
		if loaded is Texture2D:
			projectile_texture = loaded
			return
	projectile_texture = _resolve_projectile_texture()

func _resolve_projectile_texture() -> Texture2D:
	if character_data and character_data.projectile_texture:
		return character_data.projectile_texture
	return DEFAULT_PROJECTILE_TEXTURE

func _update_ammo_ui() -> void:
	if ammo_label == null:
		return
	ammo_label.text = str(arrows)

func _play_shoot_sfx() -> void:
	_play_tone(shoot_sfx, shoot_stream, 780.0, 0.12)

func _play_pickup_sfx() -> void:
	_play_tone(pickup_sfx, pickup_stream, 1200.0, 0.08)

func _play_parry_sfx() -> void:
	_play_tone(parry_sfx, parry_stream, 1500.0, 0.14)

func _play_action_sfx(action: String) -> void:
	var key := String(action)
	if not action_sfx_players.has(key):
		if DevDebug:
			DevDebug.log_event("audio", "action_sfx ausente: %s" % key)
		return
	var player = action_sfx_players[key]
	if not (player is AudioStreamPlayer):
		if DevDebug:
			DevDebug.log_event("audio", "player inválido p/ %s" % key)
		return
	var audio_player := player as AudioStreamPlayer
	var playback_speed := _resolve_action_sfx_speed(key)
	var playback_duration := _resolve_action_sfx_duration(key)
	if playback_speed > 0.0:
		audio_player.pitch_scale = playback_speed
	else:
		audio_player.pitch_scale = 1.0
	audio_player.stop()
	audio_player.play()
	if playback_duration > 0.0:
		audio_player.seek(0.0)
		_call_action_sfx_stop_timer(key, playback_duration)
	if DevDebug:
		DevDebug.log_event("audio", "play %s" % key)

func _setup_sfx() -> void:
	shoot_stream = _ensure_generator(shoot_sfx, -4.0)
	pickup_stream = _ensure_generator(pickup_sfx, -6.0)
	parry_stream = _ensure_generator(parry_sfx, -4.0)

func _setup_action_sfx() -> void:
	for player in action_sfx_players.values():
		if player is Node:
			var node := player as Node
			if is_instance_valid(node) and node.is_inside_tree():
				node.queue_free()
	action_sfx_players.clear()
	if character_data == null:
		return
	var mapping: Dictionary = character_data.action_sfx_paths if character_data.action_sfx_paths != null else {}
	var existing_keys := mapping.keys() if mapping is Dictionary else []
	var base_path := character_data.asset_base_path if character_data.asset_base_path is String else ""
	if DevDebug:
		DevDebug.log_event("audio", "setup_action_sfx char=%s id=%s map_size=%d" % [character_data.display_name, character_id, mapping.size()])
	var fallback_actions := [
		"idle",
		"walk",
		"running",
		"dash",
		"jump_start",
		"jump_air",
		"aim",
		"shoot",
		"melee",
		"ult",
		"hurt",
		"death"
	]
	for fallback in fallback_actions:
		var key := String(fallback)
		if key in existing_keys:
			continue
		var auto_path := _find_default_action_sfx_path(key)
		if auto_path == "":
			continue
		mapping[key] = auto_path
		if DevDebug:
			DevDebug.log_event("audio", "fallback action_sfx:%s -> %s" % [key, auto_path])
	for action in mapping.keys():
		var key := String(action)
		var path := _resolve_action_sfx_path(mapping[action], base_path)
		if path == "":
			if DevDebug:
				DevDebug.log_event("audio", "action_sfx:%s path vazio" % key)
			continue
		var stream := load(path)
		if not (stream is AudioStream):
			push_warning("Action SFX '%s' não é AudioStream válido: %s" % [key, path])
			continue
		var player := AudioStreamPlayer.new()
		player.name = "%sSfx" % key.capitalize()
		player.stream = stream
		player.bus = "Master"
		player.volume_db = -2.0
		add_child(player)
		action_sfx_players[key] = player
		if DevDebug:
			DevDebug.log_event("audio", "action_sfx:%s pronto %s" % [key, path])
	if DevDebug and action_sfx_players.is_empty():
		DevDebug.log_event("audio", "sem action_sfx configurados")
	action_sfx_stop_timers.clear()

func _resolve_action_sfx_path(path_variant: Variant, base_path: String) -> String:
	if not (path_variant is String):
		return ""
	var path := String(path_variant).strip_edges()
	if path == "":
		return ""
	if path.begins_with("res://"):
		return path
	if base_path != "":
		var resolved := base_path
		if not resolved.ends_with("/"):
			resolved += "/"
		resolved += path.trim_prefix("./")
		return resolved
	return path

func _find_default_action_sfx_path(action: String) -> String:
	if character_id == "":
		return ""
	var base_dir := "res://assets/characters/%s/sfx" % character_id
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return ""
	var target_prefix := action.to_lower()
	var allowed_exts := [".mp3", ".wav", ".ogg"]
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var entry_lower := entry.to_lower()
			for ext in allowed_exts:
				if entry_lower == "%s%s" % [target_prefix, ext]:
					dir.list_dir_end()
					return "%s/%s" % [base_dir, entry]
		entry = dir.get_next()
	dir.list_dir_end()
	return ""

func _ensure_generator(player: Node, volume_db: float) -> AudioStreamGenerator:
	if not (player is AudioStreamPlayer):
		return null
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100
	generator.buffer_length = 0.2
	player.stream = generator
	player.volume_db = volume_db
	return generator

func _play_tone(player: Node, generator: AudioStreamGenerator, freq: float, duration: float) -> void:
	if not (player is AudioStreamPlayer) or generator == null:
		return
	if not player.playing:
		player.play()
	var playback = player.get_stream_playback()
	if playback == null:
		return
	var sample_rate = generator.mix_rate
	var total = int(duration * sample_rate)
	for i in range(total):
		var t = float(i) / sample_rate
		var sample = sin(TAU * freq * t) * 0.2
		playback.push_frame(Vector2(sample, sample))

func _resolve_action_sfx_speed(action: String) -> float:
	if character_data != null and character_data.action_sfx_speeds.has(action):
		var value: Variant = character_data.action_sfx_speeds[action]
		if value is float or value is int:
			return max(0.05, float(value))
	return 1.0

func _resolve_action_sfx_duration(action: String) -> float:
	if character_data != null and character_data.action_sfx_durations.has(action):
		var value: Variant = character_data.action_sfx_durations[action]
		if value is float or value is int:
			return max(0.0, float(value))
	return 0.0

func _call_action_sfx_stop_timer(action: String, duration: float) -> void:
	if duration <= 0.0:
		return
	if action_sfx_stop_timers.has(action):
		var existing: Dictionary = action_sfx_stop_timers[action]
		var timer: SceneTreeTimer = existing.get("timer") if existing.has("timer") else null
		var callable: Callable = existing.get("callable") if existing.has("callable") else Callable()
		if timer is SceneTreeTimer and is_instance_valid(timer):
			if callable is Callable and callable.is_valid() and timer.is_connected("timeout", callable):
				timer.disconnect("timeout", callable)
		action_sfx_stop_timers.erase(action)
	var timer := get_tree().create_timer(duration)
	var callable := Callable(self, "_on_action_sfx_timeout").bind(action)
	timer.connect("timeout", callable)
	action_sfx_stop_timers[action] = {"timer": timer, "callable": callable}

func _on_action_sfx_timeout(action: String) -> void:
	action_sfx_stop_timers.erase(action)
	if not action_sfx_players.has(action):
		return
	var player = action_sfx_players[action]
	if player is AudioStreamPlayer and is_instance_valid(player):
		(player as AudioStreamPlayer).stop()

func _update_parry_timers(delta: float) -> void:
	if dash_parry_timer > 0.0:
		dash_parry_timer = max(dash_parry_timer - delta, 0.0)
	if dash_press_timer > 0.0:
		dash_press_timer = max(dash_press_timer - delta, 0.0)

func _handle_melee(delta: float) -> void:
	var pressed := input_reader.melee_pressed()
	var result := combat.handle_melee(delta, pressed)
	if result.get("uses_skill", false):
		_set_melee_active(false)
		if result.get("start", false):
			var duration := visuals.get_action_animation_duration("melee", combat.get_melee_duration())
			visuals.trigger_melee_animation(duration)
			_play_action_sfx("melee")
		return
	if result.get("stop", false):
		_set_melee_active(false)
	if result.get("start", false):
		var duration := visuals.get_action_animation_duration("melee", combat.get_melee_duration())
		visuals.trigger_melee_animation(duration)
		_play_action_sfx("melee")
		_set_melee_active(true)

func _handle_ult() -> void:
	var pressed := input_reader.ult_pressed()
	var activated := combat.handle_ult(pressed)
	if activated:
		_play_action_sfx("ult")
		if visuals.has_action_animation("ult"):
			var duration := visuals.get_action_animation_duration("ult", 0.8)
			visuals.trigger_ult_animation(duration)

func _set_melee_active(active: bool) -> void:
	if melee_area == null:
		return
	melee_area.monitoring = active
	melee_area.monitorable = active
	if melee_shape:
		melee_shape.disabled = not active
	if melee_visual:
		melee_visual.visible = active
	if active:
		_update_melee_orientation()

func _update_melee_orientation() -> void:
	if melee_area == null:
		return
	melee_area.position = _melee_anchor_offset()
	if melee_visual:
		melee_visual.scale.x = facing

func _body_chest_position() -> Vector2:
	if body_shape != null and body_shape.shape is RectangleShape2D:
		var rect := body_shape.shape as RectangleShape2D
		var center: Vector2 = body_shape.position
		return Vector2(
			center.x + rect.size.x * 0.15 * facing,
			center.y - rect.size.y * 0.35
		)
	return Vector2(18.0 * facing, -48.0)

func _melee_anchor_offset() -> Vector2:
	var anchor := _body_chest_position()
	if body_shape != null and body_shape.shape is RectangleShape2D:
		var rect := body_shape.shape as RectangleShape2D
		anchor.x += (rect.size.x * 0.5 + 12.0) * facing
	else:
		anchor.x += 32.0 * facing
	return anchor

func _on_melee_body_entered(body: Node) -> void:
	_process_melee_hit(body)

func _on_melee_area_entered(area: Area2D) -> void:
	_process_melee_hit(area)

func _process_melee_hit(node: Node) -> void:
	combat.process_melee_hit(node)

func _check_head_stomp() -> void:
	if is_dead:
		return
	if velocity.y <= 0.0:
		return
	for other in get_tree().get_nodes_in_group("players"):
		if other == self or other == null:
			continue
		if not other.is_inside_tree() or !other.has_method("die"):
			continue
		if other.is_dead:
			continue
		var self_rect := _get_body_rect(self)
		var other_rect := _get_body_rect(other)
		if self_rect.size == Vector2.ZERO or other_rect.size == Vector2.ZERO:
			var horizontal_gap: float = abs(global_position.x - other.global_position.x)
			if horizontal_gap > 40:
				continue
			var vertical_gap: float = other.global_position.y - global_position.y
			if vertical_gap < 20 or vertical_gap > 120:
				continue
		else:
			var head_height: float = max(12.0, other_rect.size.y * 0.25)
			var head_rect := Rect2(other_rect.position, Vector2(other_rect.size.x, head_height))
			var foot_height: float = max(10.0, self_rect.size.y * 0.2)
			var foot_pos := Vector2(self_rect.position.x, self_rect.position.y + self_rect.size.y - foot_height)
			var foot_rect := Rect2(foot_pos, Vector2(self_rect.size.x, foot_height))
			if not foot_rect.intersects(head_rect):
				continue
		other.die()
		velocity.y = -jump_velocity * 0.8
		break

func _get_body_rect(player: Node) -> Rect2:
	if player == null:
		return Rect2()
	var shape_node := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return Rect2()
	if shape_node.shape is RectangleShape2D:
		var rect_shape := shape_node.shape as RectangleShape2D
		var size: Vector2 = rect_shape.size * shape_node.scale.abs()
		if player == self and visuals._last_collider_size != Vector2.ZERO:
			size = visuals._last_collider_size
		var origin: Vector2 = shape_node.global_position - size * 0.5
		return Rect2(origin, size)
	return Rect2()

func get_projectile_spawn_offset(direction: Vector2) -> Vector2:
	return visuals.get_projectile_spawn_offset(direction, facing)
