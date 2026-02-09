extends Node2D
class_name SpriteDebugOverlay

const COLOR_USED_RECT := Color(0.25, 1.0, 0.35, 0.85)
const COLOR_HITBOX := Color(1.0, 0.25, 0.25, 0.9)
const COLOR_GROUND := Color(1.0, 0.9, 0.2, 0.85)
const COLOR_TARGET := Color(0.45, 0.7, 1.0, 0.75)

var character_sprite: AnimatedSprite2D = null
var body_shape: CollisionShape2D = null
var current_anim := ""
var anchor_ratio := 1.0
var target_height := 0.0
var enabled := false

func configure(sprite: AnimatedSprite2D, body: CollisionShape2D) -> void:
	character_sprite = sprite
	body_shape = body
	z_index = 100

func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if enabled:
		queue_redraw()

func update_state(anim_name: String, action: String, anchor_ratio_value: float, target_height_value: float) -> void:
	current_anim = anim_name
	anchor_ratio = clamp(anchor_ratio_value, 0.0, 1.0)
	target_height = max(target_height_value, 0.0)
	if enabled:
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	_draw_hitbox()
	_draw_sprite_used_rect()
	_draw_ground_line()
	_draw_target_height()

func _draw_hitbox() -> void:
	if body_shape == null:
		return
	if not (body_shape.shape is RectangleShape2D):
		return
	var rect := body_shape.shape as RectangleShape2D
	var size := rect.size
	if size == Vector2.ZERO:
		return
	var top_left := body_shape.position - size * 0.5
	draw_rect(Rect2(top_left, size), COLOR_HITBOX, false, 1.5)

func _draw_sprite_used_rect() -> void:
	if character_sprite == null or character_sprite.sprite_frames == null:
		return
	var frames := character_sprite.sprite_frames
	var anim := current_anim
	if anim == "" or not frames.has_animation(anim):
		anim = character_sprite.animation
	if anim == "" or not frames.has_animation(anim):
		return
	if frames.get_frame_count(anim) == 0:
		return
	var texture := frames.get_frame_texture(anim, 0)
	if texture == null:
		return
	var image := texture.get_image()
	if image == null:
		return
	var used := image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return
	var texture_size := texture.get_size()
	var scale := character_sprite.scale
	var offset := character_sprite.position
	var top_left := Vector2(
		(used.position.x - texture_size.x * 0.5) * scale.x,
		(used.position.y - texture_size.y * 0.5) * scale.y
	) + offset
	var used_size := Vector2(used.size) * scale
	draw_rect(Rect2(top_left, used_size), COLOR_USED_RECT, false, 1.5)
	var anchor_y := (used.position.y + used.size.y * anchor_ratio - texture_size.y * 0.5) * scale.y + offset.y
	draw_line(Vector2(top_left.x, anchor_y), Vector2(top_left.x + used_size.x, anchor_y), COLOR_GROUND, 1.0)
	draw_circle(Vector2(offset.x, anchor_y), 2.5, COLOR_GROUND)

func _draw_ground_line() -> void:
	draw_line(Vector2(-80, 0), Vector2(80, 0), COLOR_GROUND, 1.0)

func _draw_target_height() -> void:
	if target_height <= 0.0:
		return
	var top_y := -target_height * anchor_ratio
	var bottom_y := target_height * (1.0 - anchor_ratio)
	draw_line(Vector2(-20, top_y), Vector2(20, top_y), COLOR_TARGET, 1.0)
	if abs(bottom_y) > 0.5:
		draw_line(Vector2(-20, bottom_y), Vector2(20, bottom_y), COLOR_TARGET, 1.0)
