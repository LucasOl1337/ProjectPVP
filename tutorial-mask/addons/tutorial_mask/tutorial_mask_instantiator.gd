@tool
extends Node

var scene

func _enter_tree() -> void:
	scene = preload("tutorial_mask_scene.tscn").instantiate()
	add_child(scene)
	
func _exit_tree() -> void:
	scene.free()
