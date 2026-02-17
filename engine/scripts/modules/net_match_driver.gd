extends RefCounted

class_name NetMatchDriver



const NetInputBuffer = preload("res://engine/scripts/modules/net_input_buffer.gd")



var input_buffer := NetInputBuffer.new()

var player_nodes_by_id: Dictionary = {}

var local_player_ids: Array[int] = []

var frame_number := 0

var last_applied_frame := -1



func configure(players: Array) -> void:

	player_nodes_by_id.clear()

	for player in players:

		if player == null:

			continue

		var player_id_variant = player.get("player_id")

		if not (player_id_variant is int):

			continue

		var resolved_id: int = int(player_id_variant)

		player_nodes_by_id[resolved_id] = player

		var reader = player.get("input_reader")

		if reader and reader.has_method("set_use_external_frames"):

			reader.set_use_external_frames(true)

	frame_number = 0

	last_applied_frame = -1

	input_buffer.clear()



func set_local_player_ids(ids: Array) -> void:

	local_player_ids.clear()

	for value in ids:

		if value is int:

			local_player_ids.append(value)

		elif value is float:

			local_player_ids.append(int(value))



func step_frame() -> void:

	_capture_local_inputs(frame_number)

	_apply_inputs(frame_number)

	last_applied_frame = frame_number

	frame_number += 1



func get_last_applied_frame() -> int:

	return last_applied_frame



func receive_remote_input(player_id: int, frame_number: int, frame: Dictionary) -> void:

	input_buffer.push_input(player_id, frame_number, frame)



func _capture_local_inputs(frame_number: int) -> void:

	for player_id in local_player_ids:

		var player = player_nodes_by_id.get(player_id)

		if player == null:

			continue

		var reader = player.get("input_reader")

		if reader == null:

			continue

		if not reader.has_method("build_local_frame"):

			continue

		var frame: Dictionary = reader.build_local_frame(frame_number)

		input_buffer.push_input(player_id, frame_number, frame)



func _apply_inputs(frame_number: int) -> void:

	for player_id in player_nodes_by_id.keys():

		var player = player_nodes_by_id[player_id]

		if player == null:

			continue

		var reader = player.get("input_reader")

		if reader == null or not reader.has_method("push_frame"):

			continue

		var frame := input_buffer.get_or_predict_frame(player_id, frame_number)

		reader.push_frame(frame)

