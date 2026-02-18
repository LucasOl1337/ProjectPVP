@tool
extends EditorPlugin


var _dock: Control


func _enter_tree() -> void:
	var dock_script: Script = preload("res://addons/anim_action_mapper/anim_action_mapper_dock.gd")
	_dock = dock_script.new(get_editor_interface())
	_dock.name = "AnimActionMapper"
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _dock)


func _exit_tree() -> void:
	if _dock == null:
		return
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
