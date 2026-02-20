extends Area2D

# Arrow (mecânica do projétil)
#
# Este script concentra o comportamento do projétil (flecha):
# - movimento (velocidade inicial, decay, gravidade, lifetime, alcance)
# - hitbox (CollisionShape2D)
# - visual (sprite, escala e rotação conforme a velocidade)
# - colisões (mundo e hurtboxes)
#
# Importante sobre “config”:
# - `ProjectileConfig` guarda perfis (default/heavy/fast) com valores base.
# - `profile_name` escolhe qual perfil aplicar.
# - Os campos `override_*` permitem sobrescrever valores do perfil direto na cena.


const ProjectileConfig = preload("res://engine/scripts/modules/projectile_config.gd")
const CollisionLayersScript = preload("res://engine/scripts/modules/collision_layers.gd")


@export_group("Arrow")
@export var profile_name := "default"
@export var arrow_texture: Texture2D
@export var collision_size := Vector2(96.0, 12.0)
@export var sprite_scale := Vector2(1.5, 1.2)
@export var rotate_with_velocity := true
@export var collectable_when_stuck := true
@export var inherit_owner_velocity_factor := 1.0

# Se algum personagem quiser trocar o visual da flecha sem duplicar a cena,
# o código pode chamar `set_texture_override(...)`.


@export_group("Movement Overrides")
# Se um override ficar em -1, usamos o valor do perfil dentro de `ProjectileConfig`.
@export var override_base_speed := -1.0
@export var override_min_speed := -1.0
@export var override_speed_decay := -1.0
@export var override_gravity := -1.0
@export var override_max_lifetime := -1.0
@export var override_range_ratio := -1.0


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
	# Chamado pelo Player no momento do disparo.
	# Define o dono (pra não colidir com quem atirou), direção inicial e aplica o perfil.
	source = owner
	config.apply_profile(profile_name)
	_apply_movement_overrides()
	if dir == Vector2.ZERO:
		direction = Vector2.RIGHT
	else:
		direction = dir.normalized()
	forward_dir = direction
	pending_direction = direction
	forward_speed = float(config.base_speed)
	var inherited := _get_owner_velocity(owner) * float(_resolve_inherit_factor(owner))
	var inherited_along := maxf(0.0, inherited.dot(forward_dir))
	forward_speed = maxf(float(config.min_speed), forward_speed + inherited_along)
	velocity = forward_dir * forward_speed
	lifetime = config.max_lifetime
	_apply_collision_size()
	_apply_sprite_scale()


func _resolve_inherit_factor(owner: Node) -> float:
	if owner != null and owner.has_method("get_projectile_inherit_velocity_factor"):
		var v: Variant = owner.call("get_projectile_inherit_velocity_factor")
		if v is float or v is int:
			return float(v)
	return inherit_owner_velocity_factor


func _get_owner_velocity(owner: Node) -> Vector2:
	if owner == null:
		return Vector2.ZERO
	if owner.has_method("get_projectile_inherited_velocity"):
		var v: Variant = owner.call("get_projectile_inherited_velocity")
		if v is Vector2:
			return v
	var raw: Variant = owner.get("velocity")
	if raw is Vector2:
		return raw
	return Vector2.ZERO


func _ready() -> void:
	# Configura colisão e visual inicial.
	add_to_group("arrows")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	collision_layer = CollisionLayersScript.PROJECTILE
	collision_mask = CollisionLayersScript.WORLD | CollisionLayersScript.HURTBOX
	_setup_sprite_frames()
	_apply_texture_override()
	_apply_collision_size()
	_apply_sprite_scale()


func _physics_process(delta: float) -> void:
	# Movimento do projétil:
	# - mantém um componente “forward” com decay
	# - aplica gravidade depois de um atraso proporcional ao alcance
	# - trava (“stick”) quando passa do alcance/lifetime
	if is_stuck:
		return
	var prev_pos: Vector2 = global_position
	var min_speed: float = float(config.min_speed)
	if absf(forward_speed) > min_speed:
		var decay_rate: float = float(config.speed_decay)
		if velocity.y < 0.0:
			decay_rate *= float(config.upward_speed_decay_multiplier)
		forward_speed = signf(forward_speed) * maxf(absf(forward_speed) - decay_rate * delta, min_speed)
	var forward_component := forward_dir * forward_speed
	var current_along := velocity.dot(forward_dir)
	var side_component := velocity - forward_dir * current_along
	velocity = forward_component + side_component
	if distance_travelled >= config.max_range() * config.gravity_delay_ratio:
		var gravity_scale: float = float(ProjectSettings.get_setting("gameplay/global_gravity_scale", 1.0))
		var progress: float = minf(distance_travelled / config.max_range(), 1.0)
		var ramp: float = 1.0
		if config.gravity_ramp_ratio > 0.0:
			ramp = clampf(progress / float(config.gravity_ramp_ratio), 0.0, 1.0)
		var gravity_factor: float = lerpf(float(config.gravity_min_scale), float(config.gravity_max_scale), ramp)
		var gravity_strength: float = float(config.gravity) * gravity_factor * gravity_scale
		if velocity.y < 0.0:
			gravity_strength *= float(config.upward_gravity_multiplier)
		var gravity_vec := Vector2(0.0, gravity_strength)
		var gravity_along := gravity_vec.dot(forward_dir)
		var gravity_parallel := forward_dir * gravity_along
		var gravity_perp := gravity_vec - gravity_parallel
		forward_speed += gravity_along * delta
		velocity += gravity_perp * delta
	global_position += velocity * delta
	if rotate_with_velocity and velocity.length() > 0.01:
		_update_sprite_direction(velocity)
	distance_travelled += prev_pos.distance_to(global_position)
	lifetime -= delta
	if distance_travelled >= config.max_range() or lifetime <= 0.0:
		_stick(collectable_when_stuck)


func _on_body_entered(body: Node) -> void:
	# Colisão com corpos (mundo/player). Quando a flecha está stuck, ela pode ser coletada.
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
	_stick(collectable_when_stuck)


func _on_area_entered(area: Area2D) -> void:
	# Colisão com áreas (hurtboxes). Resolve o alvo real (muitas vezes é o pai da Area2D).
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
	_stick(collectable_when_stuck)


func _resolve_hit_target(node: Node) -> Node:
	if node == null:
		return null
	if node is Area2D:
		var parent := node.get_parent()
		if parent != null:
			return parent
	return node


func _stick(collectable: bool, attach_to: Node = null) -> void:
	# “Stick”: para o projétil e desliga movimento. Pode deixar coletável.
	if is_stuck:
		return
	is_stuck = true
	is_collectable = collectable
	velocity = Vector2.ZERO
	forward_speed = 0.0
	set_physics_process(false)
	if attach_to != null:
		var current_pos := global_position
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
	# Usado por mecânicas de parry: congela a flecha no ar.
	if is_stuck:
		return
	velocity = Vector2.ZERO
	set_physics_process(false)


func set_texture_override(tex: Texture2D) -> void:
	# Troca o visual em runtime sem precisar alterar a cena.
	texture_override = tex
	_apply_texture_override()


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
		var player: AnimationPlayer = animation_player as AnimationPlayer
		if player.has_animation("flight"):
			player.play("flight")
	_update_sprite_direction(pending_direction)


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
	var current_pos := global_position
	call_deferred("_deferred_attach_to_target", target, current_pos)
	set_deferred("monitoring", false)


func _apply_collision_size() -> void:
	# Centraliza o ajuste do tamanho de hitbox.
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var rect := collision_shape.shape as RectangleShape2D
		rect.size = collision_size


func _apply_sprite_scale() -> void:
	# Centraliza o ajuste de escala do visual.
	if sprite:
		sprite.scale = sprite_scale


func _apply_movement_overrides() -> void:
	# Sobrescreve valores do ProjectileConfig quando os overrides estão ativos.
	if override_base_speed > 0.0:
		config.base_speed = override_base_speed
	if override_min_speed > 0.0:
		config.min_speed = override_min_speed
	if override_speed_decay > 0.0:
		config.speed_decay = override_speed_decay
	if override_gravity >= 0.0:
		config.gravity = override_gravity
	if override_max_lifetime > 0.0:
		config.max_lifetime = override_max_lifetime
	if override_range_ratio > 0.0:
		config.range_ratio = override_range_ratio
