extends Area2D
class_name SkillHitboxArea

@export var radius := 120.0
@export var duration := 0.12
@export var knockback_force := 0.0
@export var max_height_difference := 0.0
@export var hit_once := true

var owner_node: Node = null
var elapsed := 0.0
var hit_targets: Dictionary = {}
var collision_shape: CollisionShape2D = null

func configure(owner_ref: Node, world_position: Vector2) -> void:
	owner_node = owner_ref
	global_position = world_position

func _ready() -> void:
	collision_layer = CollisionLayers.HITBOX
	collision_mask = CollisionLayers.HURTBOX
	collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape == null:
		collision_shape = CollisionShape2D.new()
		add_child(collision_shape)
	if collision_shape.shape == null:
		_apply_shape()
	monitoring = true
	monitorable = true
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("area_entered", Callable(self, "_on_area_entered"))
	call_deferred("_apply_overlaps")

func _physics_process(delta: float) -> void:
	if duration <= 0.0:
		queue_free()
		return
	elapsed += delta
	if elapsed >= duration:
		queue_free()

func _apply_shape() -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision_shape.shape = circle

func _apply_overlaps() -> void:
	for body in get_overlapping_bodies():
		_process_hit(body)
	for area in get_overlapping_areas():
		_process_hit(area)

func _on_body_entered(body: Node) -> void:
	_process_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_process_hit(area)

func _process_hit(node: Node) -> void:
	var target := _resolve_hit_target(node)
	if target == null or target == owner_node:
		return
	if max_height_difference > 0.0 and target is Node2D:
		var delta_y: float = abs((target as Node2D).global_position.y - global_position.y)
		if delta_y > max_height_difference:
			return
	var id := target.get_instance_id()
	if hit_once and hit_targets.has(id):
		return
	hit_targets[id] = true
	if target.has_method("hit"):
		target.hit()
	if knockback_force != 0.0 and target is CharacterBody2D:
		var direction := ((target as CharacterBody2D).global_position - global_position).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT
		(target as CharacterBody2D).velocity += direction * knockback_force

func _resolve_hit_target(node: Node) -> Node:
	if node == null:
		return null
	if node is Area2D:
		var parent := node.get_parent()
		if parent != null:
			return parent
	return node
