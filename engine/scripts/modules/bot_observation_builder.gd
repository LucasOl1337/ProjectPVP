extends RefCounted
class_name BotObservationBuilder

const OBS_VERSION := 2

const CollisionLayers = preload("res://engine/scripts/modules/collision_layers.gd")

var config_path := ""
var config_signature := ""
var sensors_cfg := {
	"enabled": true,
	"mask": CollisionLayers.WORLD,
	"front_wall_distance": 34.0,
	"front_wall_y_offsets": [-34.0, -18.0],
	"ground_distance": 220.0,
	"ceiling_distance": 120.0,
	"ledge_probe_x": 28.0,
	"ledge_probe_down": 260.0,
	"reload_interval_ms": 500
}

var _last_reload_ms := 0

func configure(config: Dictionary) -> void:
	var path_value: Variant = config.get("config_path")
	if path_value is String:
		config_path = String(path_value)

func build(main_node: Node, player: Node, opponent: Node, frame_number: int = 0, delta: float = 0.0) -> Dictionary:
	_reload_if_needed(false)
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
	var facing := _read_int(state, "facing", 1)
	var sensors_snapshot := _build_sensors_snapshot(node, position, facing)
	return {
		"position": position,
		"velocity": _read_vector(state, "velocity", Vector2.ZERO),
		"facing": facing,
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
		"sensors": sensors_snapshot,
		"on_floor": _read_bool_method(node, "is_on_floor", false),
		"on_wall": _read_bool_method(node, "is_on_wall", false)
	}

func _build_sensors_snapshot(node: Node, position: Vector2, facing: int) -> Dictionary:
	if not bool(sensors_cfg.get("enabled", true)):
		return {}
	if node == null:
		return {}
	if not (node is CanvasItem):
		return {}
	var world: World2D = (node as CanvasItem).get_world_2d()
	if world == null:
		return {}
	var space_state: PhysicsDirectSpaceState2D = world.direct_space_state
	var mask := int(sensors_cfg.get("mask", CollisionLayers.WORLD))
	var exclude: Array[RID] = []
	if node is CollisionObject2D:
		exclude.append((node as CollisionObject2D).get_rid())

	var front_wall_distance := float(sensors_cfg.get("front_wall_distance", 34.0))
	var front_wall_y_offsets_value: Variant = sensors_cfg.get("front_wall_y_offsets", [-34.0, -18.0])
	var front_wall_y_offsets: Array = front_wall_y_offsets_value as Array if front_wall_y_offsets_value is Array else [-34.0, -18.0]
	var best_wall_dist := INF
	for y_off_value in front_wall_y_offsets:
		var y_off := float(y_off_value)
		var from := position + Vector2(0.0, y_off)
		var to := from + Vector2(float(facing) * front_wall_distance, 0.0)
		var hit := _ray(space_state, from, to, mask, exclude)
		if not hit.is_empty():
			var d := float(hit.get("distance", INF))
			best_wall_dist = minf(best_wall_dist, d)
	var wall_ahead := best_wall_dist < INF

	var ground_distance := float(sensors_cfg.get("ground_distance", 220.0))
	var ground_from := position
	var ground_to := position + Vector2(0.0, ground_distance)
	var ground_hit := _ray(space_state, ground_from, ground_to, mask, exclude)
	var ground_dist := float(ground_hit.get("distance", INF))

	var ceiling_distance := float(sensors_cfg.get("ceiling_distance", 120.0))
	var ceiling_from := position + Vector2(0.0, -18.0)
	var ceiling_to := ceiling_from + Vector2(0.0, -ceiling_distance)
	var ceiling_hit := _ray(space_state, ceiling_from, ceiling_to, mask, exclude)
	var ceiling_dist := float(ceiling_hit.get("distance", INF))

	var ledge_probe_x := float(sensors_cfg.get("ledge_probe_x", 28.0))
	var ledge_probe_down := float(sensors_cfg.get("ledge_probe_down", 260.0))
	var ledge_from := position + Vector2(float(facing) * ledge_probe_x, -8.0)
	var ledge_to := ledge_from + Vector2(0.0, ledge_probe_down)
	var ledge_hit := _ray(space_state, ledge_from, ledge_to, mask, exclude)
	var ledge_has_ground := not ledge_hit.is_empty()
	var ledge_ahead := not ledge_has_ground
	var ledge_ground_dist := float(ledge_hit.get("distance", INF))

	return {
		"wall_ahead": wall_ahead,
		"front_wall_distance": best_wall_dist,
		"ground_distance": ground_dist,
		"ceiling_distance": ceiling_dist,
		"ledge_ahead": ledge_ahead,
		"ledge_ground_distance": ledge_ground_dist
	}

func _ray(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, mask: int, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, mask)
	query.exclude = exclude
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var pos_value: Variant = hit.get("position")
	var dist := INF
	if pos_value is Vector2:
		dist = (pos_value as Vector2).distance_to(from)
	var out := hit.duplicate(true)
	out["distance"] = dist
	return out

func _build_nearest_arrow_snapshot(node: Node, position: Vector2) -> Dictionary:
	var tree = node.get_tree() if node != null else null
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
		var arrow_pos: Vector2 = pos_value as Vector2
		var dist := arrow_pos.distance_to(position)
		if dist < best_dist:
			best_dist = dist
			best_arrow = arrow
	if best_arrow == null:
		return {}
	var arrow_pos_value: Variant = best_arrow.get("global_position")
	var arrow_pos: Vector2 = arrow_pos_value as Vector2
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

func _reload_if_needed(force: bool) -> void:
	if config_path == "":
		return
	var now_ms := int(Time.get_ticks_msec())
	var reload_interval_ms := int(sensors_cfg.get("reload_interval_ms", 500))
	if not force and now_ms - _last_reload_ms < reload_interval_ms:
		return
	_last_reload_ms = now_ms
	var signature := _file_signature(config_path)
	if signature == "":
		return
	if not force and signature == config_signature:
		return
	config_signature = signature
	var loaded := _load_json(config_path)
	if loaded.is_empty():
		return
	if loaded.has("sensors") and loaded["sensors"] is Dictionary:
		sensors_cfg = _deep_merge_dict(sensors_cfg.duplicate(true), loaded["sensors"] as Dictionary)

func _file_signature(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return "%d" % FileAccess.get_modified_time(path)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

func _deep_merge_dict(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in overlay.keys():
		var v: Variant = overlay[k]
		if out.has(k) and out[k] is Dictionary and v is Dictionary:
			out[k] = _deep_merge_dict(out[k] as Dictionary, v as Dictionary)
		else:
			out[k] = v
	return out
