extends Node2D

@onready var tutorial_mask: TutorialMask = $TutorialMask

func _ready() -> void:
	tutorial_mask.click_use_area.connect(
		func():
			print("already click!")
			_set_area_random()
	)

func _set_area_random():
	var can_test_area = tutorial_mask.screen_size - tutorial_mask.target_size
	var target_pos = Vector2(randf()*can_test_area.x, randf()*can_test_area.y)
	tutorial_mask.set_target_pos(target_pos)
