extends BotPolicyBase
class_name BotPolicyExternal

var _pending_action: Dictionary = {}

func _init() -> void:
	policy_id = "external"

func configure(config: Dictionary) -> void:
	pass

func reset() -> void:
	_pending_action = {}

func set_action(action: Dictionary) -> void:
	if action == null:
		_pending_action = {}
		return
	_pending_action = action.duplicate(true) if action is Dictionary else {}

func select_action(observation: Dictionary) -> Dictionary:
	return _pending_action.duplicate(true)
