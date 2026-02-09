extends Node

signal selection_changed(selections: Dictionary)

const DEFAULT_SELECTION := {
	1: "storm_dragon",
	2: "storm_dragon"
}

var selections := DEFAULT_SELECTION.duplicate()
var debug_hitboxes_enabled := false
var dev_mode_enabled := false
var bot_enabled := {
	1: false,
	2: false
}
var bot_policy := {
	1: "simple",
	2: "simple"
}
var training_enabled := false
var training_watch_mode := true
var training_time_scale := 1.0
var training_port := 9009
var bot_profile := {
	1: "default",
	2: "default"
}
var genetic_genome_path := {
	1: "res://BOTS/default/best_genome.json",
	2: "res://BOTS/default/best_genome.json"
}

func set_character(player_id: int, character_id: String) -> void:
	selections[player_id] = character_id
	emit_signal("selection_changed", selections)

func get_character(player_id: int) -> String:
	return selections.get(player_id, DEFAULT_SELECTION.get(player_id, "guts"))

func reset() -> void:
	selections = DEFAULT_SELECTION.duplicate()
	debug_hitboxes_enabled = false
	dev_mode_enabled = false
	bot_enabled = {
		1: false,
		2: false
	}
	bot_policy = {
		1: "simple",
		2: "simple"
	}
	training_enabled = false
	training_watch_mode = true
	training_time_scale = 1.0
	training_port = 9009
	bot_profile = {
		1: "default",
		2: "default"
	}
	genetic_genome_path = {
		1: "res://BOTS/default/best_genome.json",
		2: "res://BOTS/default/best_genome.json"
	}
	emit_signal("selection_changed", selections)

func get_all() -> Dictionary:
	return selections.duplicate()

func set_debug_hitboxes_enabled(enabled: bool) -> void:
	debug_hitboxes_enabled = enabled

func get_debug_hitboxes_enabled() -> bool:
	return debug_hitboxes_enabled

func set_dev_mode_enabled(enabled: bool) -> void:
	dev_mode_enabled = enabled

func is_dev_mode_enabled() -> bool:
	return dev_mode_enabled

func set_bot_enabled(player_id: int, enabled: bool) -> void:
	bot_enabled[player_id] = enabled

func is_bot_enabled(player_id: int) -> bool:
	return bool(bot_enabled.get(player_id, false))

func set_bot_policy(player_id: int, policy_id: String) -> void:
	if policy_id == "":
		policy_id = "simple"
	bot_policy[player_id] = policy_id

func get_bot_policy(player_id: int) -> String:
	return String(bot_policy.get(player_id, "simple"))

func set_training_enabled(enabled: bool) -> void:
	training_enabled = enabled

func is_training_enabled() -> bool:
	return training_enabled

func set_training_watch_mode(enabled: bool) -> void:
	training_watch_mode = enabled

func is_training_watch_mode() -> bool:
	return training_watch_mode

func set_training_time_scale(value: float) -> void:
	training_time_scale = max(value, 0.1)

func get_training_time_scale() -> float:
	return training_time_scale

func set_training_port(value: int) -> void:
	training_port = max(value, 1)

func get_training_port() -> int:
	return training_port

func set_bot_profile(player_id: int, profile_id: String) -> void:
	var profile := profile_id.strip_edges().to_lower()
	if profile == "":
		profile = "default"
	bot_profile[player_id] = profile
	genetic_genome_path[player_id] = "res://BOTS/%s/best_genome.json" % profile

func get_bot_profile(player_id: int) -> String:
	return String(bot_profile.get(player_id, "default"))

func set_genetic_genome_path(player_id: int, path: String) -> void:
	if path == "":
		return
	genetic_genome_path[player_id] = path

func get_genetic_genome_path(player_id: int) -> String:
	return String(genetic_genome_path.get(player_id, "res://BOTS/default/best_genome.json"))
