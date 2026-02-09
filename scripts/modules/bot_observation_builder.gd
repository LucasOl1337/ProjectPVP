extends RefCounted
class_name BotObservationBuilder

const OBS_VERSION := 2

func build(main_node: Node, player: Node, opponent: Node, frame_number: int = 0, delta: float = 0.0) -> Dictionary:
	var self_state := _read_state(player)
	var opponent_state := _read_state(opponent)
	var self_position := _read_vector(self_state, "global_position", _read_node_position(player))
	var opponent_position := _read_vector(opponent_state, "global_position", _read_node_position(opponent))
	var delta_position := opponent_position - self_position
	return {
		"schema": {"obs_version": OBS_VERSION},
		"frame": frame_number,
		"delta": delta,
		"self": _build_actor_snapshot(player, self_state, self_position),
		"opponent": _build_actor_snapshot(opponent, opponent_state, opponent_position),
		"delta_position": delta_position,
		"distance": delta_position.length(),
		"match": _build_match_snapshot(main_node),
		"raw": {
			"self_state": self_state,
			"opponent_state": opponent_state
		}
	}

func _read_state(node: Node) -> Dictionary:
	if node != null and node.has_method("get_state"):
		var state: Dictionary = node.get_state()
		return state.duplicate(true)
	return {}

func _build_actor_snapshot(node: Node, state: Dictionary, position: Vector2) -> Dictionary:
	var aim_hold_dir := _read_vector(state, "aim_hold_dir", Vector2.ZERO)
	var last_dash_velocity := _read_vector(state, "last_dash_velocity", Vector2.ZERO)
	var arrow_snapshot := _build_nearest_arrow_snapshot(node, position)
	return {
		"position": position,
		"velocity": _read_vector(state, "velocity", Vector2.ZERO),
		"facing": _read_int(state, "facing", 1),
		"is_dead": _read_bool(state, "is_dead", false),
		"arrows": _read_int(state, "arrows", 0),
		"dash_parry_timer": float(state.get("dash_parry_timer", 0.0)),
		"dash_press_timer": float(state.get("dash_press_timer", 0.0)),
		"aim_hold_active": bool(state.get("aim_hold_active", false)),
		"aim_hold_dir": aim_hold_dir,
		"shoot_was_pressed": bool(state.get("shoot_was_pressed", false)),
		"last_dash_velocity": last_dash_velocity,
		"dash_jump_used": bool(state.get("dash_jump_used", false)),
		"nearest_arrow": arrow_snapshot,
		"on_floor": _read_bool_method(node, "is_on_floor", false),
		"on_wall": _read_bool_method(node, "is_on_wall", false)
	}

func _build_nearest_arrow_snapshot(node: Node, position: Vector2) -> Dictionary:
	var tree := node.get_tree() if node != null else null
	if tree == null:
		return {}
	var arrows := tree.get_nodes_in_group("arrows")
	if arrows.is_empty():
		return {}
	var best_dist := INF
	var best_arrow: Node = null
	for arrow in arrows:
		if arrow == null or not (arrow is Node):
			continue
		if not arrow.has_method("get"):
			continue
		var pos_value: Variant = arrow.get("global_position")
		if not (pos_value is Vector2):
			continue
		var arrow_pos := pos_value as Vector2
		var dist := arrow_pos.distance_to(position)
		if dist < best_dist:
			best_dist = dist
			best_arrow = arrow
	if best_arrow == null:
		return {}
	var arrow_pos_value: Variant = best_arrow.get("global_position")
	var arrow_pos := arrow_pos_value as Vector2
	var delta := arrow_pos - position
	var vel := Vector2.ZERO
	var vel_value: Variant = best_arrow.get("velocity")
	if vel_value is Vector2:
		vel = vel_value
	return {
		"delta_position": delta,
		"distance": best_dist,
		"velocity": vel,
		"is_stuck": bool(best_arrow.get("is_stuck"))
	}

func _build_match_snapshot(main_node: Node) -> Dictionary:
	if main_node == null:
		return {}
	var wins_value: Variant = _safe_get(main_node, "wins")
	return {
		"round_active": bool(_safe_get(main_node, "round_active")),
		"match_over": bool(_safe_get(main_node, "match_over")),
		"wins": (wins_value as Dictionary).duplicate(true) if wins_value is Dictionary else {}
	}

func _safe_get(node: Node, property_name: String) -> Variant:
	if node == null:
		return null
	if node.has_method("get"):
		return node.get(property_name)
	return null

func _read_vector(state: Dictionary, key: String, fallback: Vector2) -> Vector2:
	if state.has(key) and state[key] is Vector2:
		return state[key]
	return fallback

func _read_int(state: Dictionary, key: String, fallback: int) -> int:
	if state.has(key):
		return int(state[key])
	return fallback

func _read_bool(state: Dictionary, key: String, fallback: bool) -> bool:
	if state.has(key):
		return bool(state[key])
	return fallback

func _read_bool_method(node: Node, method_name: String, fallback: bool) -> bool:
	if node != null and node.has_method(method_name):
		return bool(node.call(method_name))
	return fallback

func _read_node_position(node: Node) -> Vector2:
	if node != null and node.has_method("get"):
		var position_value: Variant = node.get("global_position")
		if position_value is Vector2:
			return position_value
	return Vector2.ZERO
