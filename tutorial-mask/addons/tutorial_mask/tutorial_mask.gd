extends CanvasLayer
class_name TutorialMask

signal click_use_area

var shader_material: ShaderMaterial = preload("shader/tutorial_mask_material.tres")
var shader : Shader = preload("shader/tutorial_mask.gdshader")
var color_rect: ColorRect

var screen_size
@export var target_pos: Vector2 = Vector2(100, 100)
@export var target_size: Vector2 = Vector2(100, 100)
@export var mask_color: Color = Color(0, 0, 0, 1)




func _ready() -> void:
	screen_size = get_viewport().get_visible_rect().size
	color_rect = ColorRect.new()
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.material = shader_material
	shader_material.shader = shader
	color_rect.color = mask_color
	color_rect.gui_input.connect(_on_color_rect_gui_input)
	add_child(color_rect)
	set_screen_size(screen_size)
	set_target_pos(target_pos)
	set_target_size(target_size)


func _on_color_rect_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		## 获取全局坐标判断是否在区域内
		# 1. 获取鼠标点击的**全局屏幕坐标**（和 Shader 中的 target_pos 坐标系一致）
		var mouse_global_pos = color_rect.get_global_mouse_position()
		# 2. 构建目标区域的矩形范围（起点 + 尺寸）
		var target_rect = Rect2(target_pos, target_size)
		# 3. 判断鼠标是否在目标区域内
		if target_rect.has_point(mouse_global_pos):
			# print("点击了")
			click_use_area.emit()
		else:
			pass

func set_screen_size(new_screen_size: Vector2):
	screen_size = new_screen_size
	shader_material.set_shader_parameter("screen_size",screen_size)


func set_target_pos(new_target_pos: Vector2):
	target_pos = new_target_pos
	shader_material.set_shader_parameter("target_pos",target_pos)


func set_target_size(new_target_size: Vector2):
	target_size = new_target_size
	shader_material.set_shader_parameter("target_size",target_size)
