extends SceneTree

func _init() -> void:
	var policy := BotPolicyGAParams.new()
	var result := policy.load_genome("res://BOTS/profiles/agressivo/best_genome.json")
	print("load:", result)
	var obs := {
		"delta": 0.016,
		"delta_position": Vector2(300, 0),
		"self": {
			"is_dead": false,
			"facing": 1,
			"arrows": 3,
			"sensors": {
				"wall_ahead": false,
				"ledge_ahead": false,
				"front_wall_distance": 999.0,
				"ground_distance": 0.0,
				"ceiling_distance": 999.0,
				"ledge_ground_distance": 0.0
			}
		},
		"match": {"round_active": true}
	}
	for i in range(10):
		var action := policy.select_action(obs)
		print("action:", action)
	obs["delta_position"] = Vector2(40, 0)
	for i in range(10):
		var action2 := policy.select_action(obs)
		print("action_close:", action2)
	quit(0)

