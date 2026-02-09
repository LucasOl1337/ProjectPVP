extends Area2D

const ProjectileConfig = preload("res://scripts/modules/projectile_config.gd")
const CollisionLayers = preload("res://scripts/modules/collision_layers.gd")
const ARROW_COLLISION_SIZE := Vector2(96, 12)

@export var profile_name := "default"
@export var arrow_texture: Texture2D
var texture_override: Texture2D = null

var config = ProjectileConfig.new()
var direction := Vector2.RIGHT
var velocity := Vector2.ZERO
var distance_travelled := 0.0
var lifetime := 0.0
var forward_dir := Vector2.RIGHT
var forward_speed := 0.0
var source: Node = null
var is_stuck := false
var is_collectable := true
var pending_direction := Vector2.RIGHT
@onready var sprite := get_node_or_null("Sprite")
@onready var animation_player := get_node_or_null("AnimationPlayer")
@onready var collision_shape := get_node_or_null("CollisionShape2D")

func setup(owner: Node, dir: Vector2) -> void:
	source = owner
	config.apply_profile(profile_name)
	if dir == Vector2.ZERO:
		direction = Vector2.RIGHT
	else:
		direction = dir.normalized()
	forward_dir = direction
	pending_direction = direction
	forward_speed = config.base_speed
	velocity = forward_dir * forward_speed
	lifetime = config.max_lifetime
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var rect := collision_shape.shape as RectangleShape2D
		rect.size = ARROW_COLLISION_SIZE

func _ready() -> void:
	add_to_group("arrows")
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("area_entered", Callable(self, "_on_area_entered"))
	collision_layer = CollisionLayers.PROJECTILE
	collision_mask = CollisionLayers.WORLD | CollisionLayers.HURTBOX
	_setup_sprite_frames()
	_apply_texture_override()

func _physics_process(delta: float) -> void:
	if is_stuck:
		return
	var prev_pos := global_position
	if forward_speed > config.min_speed:
		var decay_rate = config.speed_decay
		if forward_dir.y < 0.0:
			decay_rate *= config.upward_speed_decay_multiplier
		forward_speed = max(forward_speed - decay_rate * delta, config.min_speed)
	var forward_component = forward_dir * forward_speed
	var side_component = velocity - forward_dir * velocity.dot(forward_dir)
	velocity = forward_component + side_component
	if distance_travelled >= config.max_range() * config.gravity_delay_ratio:
		var gravity_scale = ProjectSettings.get_setting("gameplay/global_gravity_scale", 1.0)
		var progress = min(distance_travelled / config.max_range(), 1.0)
		var ramp = 1.0
		if config.gravity_ramp_ratio > 0.0:
			ramp = clamp(progress / config.gravity_ramp_ratio, 0.0, 1.0)
		var gravity_factor = lerp(config.gravity_min_scale, config.gravity_max_scale, ramp)
		var gravity_strength = config.gravity * gravity_factor * gravity_scale
		if velocity.y < 0.0:
			gravity_strength *= config.upward_gravity_multiplier
		velocity.y += gravity_strength * delta
	global_position += velocity * delta
	if velocity.length() > 0.01:
		_update_sprite_direction(velocity)
		
	distance_travelled += prev_pos.distance_to(global_position)
	lifetime -= delta
	if distance_travelled >= config.max_range() or lifetime <= 0.0:
		_stick(true)

func _on_body_entered(body: Node) -> void:
	if is_stuck:
		if is_collectable and body.has_method("add_arrows"):
			body.add_arrows(1)
			queue_free()
		return
	if body == source:
		return
	if body.has_method("receive_arrow"):
		body.receive_arrow(self)
		return
	if body.has_method("hit"):
		body.hit()
	_stick(true)

func _on_area_entered(area: Area2D) -> void:
	if is_stuck:
		var collect_target := _resolve_hit_target(area)
		if is_collectable and collect_target and collect_target.has_method("add_arrows"):
			collect_target.add_arrows(1)
			queue_free()
			return
		return
	if area == null:
		return
	if area == source:
		return
	var target := _resolve_hit_target(area)
	if target == null or target == source:
		return
	if target.has_method("receive_arrow"):
		target.receive_arrow(self)
		return
	if target.has_method("hit"):
		target.hit()
	_stick(true)

func _resolve_hit_target(node: Node) -> Node:
	if node == null:
		return null
	if node is Area2D:
		var parent := node.get_parent()
		if parent != null:
			return parent
	return node


func _stick(collectable: bool, attach_to: Node = null) -> void:
	if is_stuck:
		return
	is_stuck = true
	is_collectable = collectable
	velocity = Vector2.ZERO
	forward_speed = 0.0
	set_physics_process(false)
	if attach_to != null:
		var current_pos = global_position
		call_deferred("_deferred_attach_to_target", attach_to, current_pos)
		set_deferred("monitoring", false)
	else:
		set_deferred("monitoring", true)

func _deferred_attach_to_target(target: Node, current_pos: Vector2) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not is_inside_tree():
		return
	reparent(target)
	global_position = current_pos

func freeze_for_parry() -> void:
	if is_stuck:
		return
	velocity = Vector2.ZERO
	set_physics_process(false)


func _setup_sprite_frames() -> void:
	if sprite == null:
		return
	var final_texture := texture_override if texture_override else arrow_texture
	if final_texture == null:
		return
	var frames := SpriteFrames.new()
	frames.add_animation("east")
	frames.add_frame("east", final_texture)
	sprite.sprite_frames = frames
	sprite.play("east")
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	if animation_player and animation_player is AnimationPlayer:
		var player := animation_player as AnimationPlayer
		if player.has_animation("flight"):
			player.play("flight")
	_update_sprite_direction(pending_direction)

func set_texture_override(tex: Texture2D) -> void:
	texture_override = tex
	_apply_texture_override()

func _apply_texture_override() -> void:
	if sprite == null:
		return
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null:
		return
	var final_texture := texture_override if texture_override else arrow_texture
	if final_texture == null:
		return
	if frames.has_animation("east"):
		frames.clear("east")
	frames.add_frame("east", final_texture)
	sprite.play("east")
func _update_sprite_direction(dir: Vector2) -> void:
	if sprite == null:
		return
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	rotation = dir.angle() + PI
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("east") and sprite.animation != "east":
		sprite.play("east")

func attach_to_target(target: Node) -> void:
	if target == null:
		return
	var current_pos = global_position
	call_deferred("_deferred_attach_to_target", target, current_pos)
	set_deferred("monitoring", false)
