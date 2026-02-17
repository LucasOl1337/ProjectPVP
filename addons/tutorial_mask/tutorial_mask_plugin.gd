@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type("TutorialMaskInstantiator","CanvasLayer",preload("tutorial_mask_instantiator.gd"),preload("icon.svg"))
	pass


func _exit_tree() -> void:
	remove_custom_type("TutorialMask")
	pass
