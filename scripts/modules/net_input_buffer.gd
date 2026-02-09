extends RefCounted
class_name NetInputBuffer

const PlayerInput = preload("res://scripts/modules/player_input.gd")
const DEFAULT_MAX_FRAMES := 300

var max_frames := DEFAULT_MAX_FRAMES
var _frames_by_player: Dictionary = {}
var _last_frame_by_player: Dictionary = {}
var _last_frame_number: Dictionary = {}

func set_max_frames(value: int) -> void:
	max_frames = max(value, 1)

func clear() -> void:
	_frames_by_player.clear()
	_last_frame_by_player.clear()
	_last_frame_number.clear()

func push_input(player_id: int, frame_number: int, frame: Dictionary) -> void:
	var normalized := PlayerInput.normalize_frame(frame, frame_number)
	if normalized.is_empty():
		return
	var player_frames: Dictionary = _frames_by_player.get(player_id, {})
	player_frames[frame_number] = normalized
	_frames_by_player[player_id] = player_frames
	_last_frame_by_player[player_id] = normalized
	_last_frame_number[player_id] = frame_number
	_trim_old_frames(player_id, frame_number)

func has_frame(player_id: int, frame_number: int) -> bool:
	var player_frames: Dictionary = _frames_by_player.get(player_id, {})
	return player_frames.has(frame_number)

func get_frame(player_id: int, frame_number: int) -> Dictionary:
	var player_frames: Dictionary = _frames_by_player.get(player_id, {})
	if player_frames.has(frame_number):
		return player_frames[frame_number]
	return {}

func get_or_predict_frame(player_id: int, frame_number: int) -> Dictionary:
	var frame := get_frame(player_id, frame_number)
	if not frame.is_empty():
		return frame
	var predicted := _predict_frame(player_id, frame_number)
	if predicted.is_empty():
		return PlayerInput.build_empty_frame(frame_number)
	return predicted

func _predict_frame(player_id: int, frame_number: int) -> Dictionary:
	if not _last_frame_by_player.has(player_id):
		return {}
	var predicted := (_last_frame_by_player[player_id] as Dictionary).duplicate(true)
	predicted["frame"] = frame_number
	predicted["jump_pressed"] = false
	predicted["shoot_pressed"] = false
	predicted["dash_pressed"] = []
	predicted["melee_pressed"] = false
	predicted["ult_pressed"] = false
	if not predicted.has("shoot_is_pressed"):
		predicted["shoot_is_pressed"] = false
	if not predicted.has("axis"):
		predicted["axis"] = 0.0
	if not predicted.has("aim"):
		predicted["aim"] = Vector2.ZERO
	if not predicted.has("actions") or not (predicted["actions"] is Dictionary):
		predicted["actions"] = {"left": false, "right": false, "up": false, "down": false}
	return predicted

func _trim_old_frames(player_id: int, newest_frame: int) -> void:
	var player_frames: Dictionary = _frames_by_player.get(player_id, {})
	if player_frames.is_empty():
		return
	var min_frame := newest_frame - max_frames
	var to_remove: Array = []
	for frame_number in player_frames.keys():
		if int(frame_number) < min_frame:
			to_remove.append(frame_number)
	for frame_number in to_remove:
		player_frames.erase(frame_number)
	_frames_by_player[player_id] = player_frames
