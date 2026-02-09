extends RefCounted
class_name BotDriver

const BotActionFrame = preload("res://scripts/modules/bot_action_frame.gd")
const BotObservationBuilder = preload("res://scripts/modules/bot_observation_builder.gd")
const BotPolicyExternal = preload("res://scripts/modules/bot_policy_external.gd")
const BotPolicySimple = preload("res://scripts/modules/bot_policy_simple.gd")
const BotPolicyGenetic = preload("res://scripts/modules/bot_policy_genetic.gd")
const BotPolicyObjective = preload("res://scripts/modules/bot_policy_objective.gd")
const BotPolicyHandmade = preload("res://scripts/modules/bot_policy_handmade.gd")

var player: Node = null
var opponent: Node = null
var main_node: Node = null
var policy = null
var observation_builder := BotObservationBuilder.new()
var frame_number := 0
var enabled := false
var manage_external_frames := true
var last_observation: Dictionary = {}
var last_action: Dictionary = {}
var _policy_id := "simple"
var _policy_config: Dictionary = {}

func configure(main_node_value: Node, player_node: Node, opponent_node: Node, policy_id: String = "simple", config: Dictionary = {}) -> void:
	main_node = main_node_value
	player = player_node
	opponent = opponent_node
	_policy_config = config.duplicate(true) if config is Dictionary else {}
	set_policy(policy_id)
	_reset_frames()
	_set_external_frames(true)

func set_policy(policy_id: String) -> void:
	_policy_id = policy_id
	if policy_id == "external":
		policy = BotPolicyExternal.new()
	elif policy_id == "handmade":
		policy = BotPolicyHandmade.new()
	elif policy_id == "objective":
		policy = BotPolicyObjective.new()
	elif policy_id == "genetic":
		policy = BotPolicyGenetic.new()
	else:
		policy = BotPolicySimple.new()
	if policy:
		policy.configure(_policy_config)

func get_policy_metrics() -> Dictionary:
	if policy and policy.has_method("get_metrics"):
		var m: Variant = policy.get_metrics()
		if m is Dictionary:
			return (m as Dictionary).duplicate(true)
	return {}

func set_policy_config(config: Dictionary) -> void:
	_policy_config = config.duplicate(true) if config is Dictionary else {}
	if policy:
		policy.configure(_policy_config)

func set_enabled(value: bool) -> void:
	enabled = value
	_set_external_frames(value)

func reset() -> void:
	_reset_frames()
	if policy:
		policy.reset()

func step(delta: float) -> void:
	if not enabled:
		return
	var reader = _get_input_reader()
	if reader == null:
		return
	var observation := observation_builder.build(main_node, player, opponent, frame_number, delta)
	last_observation = observation.duplicate(true)
	var action: Dictionary = {}
	if policy:
		action = policy.select_action(observation)
	last_action = action.duplicate(true) if action is Dictionary else {}
	var frame := BotActionFrame.build(frame_number, action)
	if reader.has_method("push_frame"):
		reader.push_frame(frame)
	frame_number += 1

func set_external_action(action: Dictionary) -> void:
	if policy and policy.has_method("set_action"):
		policy.set_action(action)

func load_genome(path: String) -> Dictionary:
	if path == "":
		return {"ok": false, "error": "Caminho vazio", "path": path}
	_policy_config["genome_path"] = path
	if policy and policy.has_method("configure"):
		policy.configure(_policy_config)
	if policy and policy.has_method("load_genome"):
		return policy.load_genome(path)
	return {"ok": false, "error": "Policy não suporta genoma", "path": path}

func get_last_observation() -> Dictionary:
	return last_observation.duplicate(true)

func get_last_action() -> Dictionary:
	return last_action.duplicate(true)

func get_policy_id() -> String:
	return _policy_id

func _reset_frames() -> void:
	frame_number = 0
	last_observation = {}
	last_action = {}

func _get_input_reader() -> Variant:
	if player == null:
		return null
	if player.has_method("get"):
		return player.get("input_reader")
	return null

func _set_external_frames(enabled_value: bool) -> void:
	if not manage_external_frames:
		return
	var reader = _get_input_reader()
	if reader and reader.has_method("set_use_external_frames"):
		reader.set_use_external_frames(enabled_value)
