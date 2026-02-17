extends RefCounted
class_name BotPolicyBase

var policy_id := "base"

func configure(config: Dictionary) -> void:
	pass

func reset() -> void:
	pass

func select_action(observation: Dictionary) -> Dictionary:
	return {}
