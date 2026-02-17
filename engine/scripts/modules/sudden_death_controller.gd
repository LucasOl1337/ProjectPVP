extends RefCounted
class_name SuddenDeathController


var enabled := true
var start_seconds := 20.0
var phase_interval_seconds := 5.0
var phase1_close_percent := 0.20
var phase2_close_percent := 0.25
var draw_walls := true

var phase := 0
var elapsed_seconds := 0.0
var close_percent := 0.0
var needs_redraw := false


func configure(
	enabled_value: bool,
	start_seconds_value: float,
	phase_interval_seconds_value: float,
	phase1_close_percent_value: float,
	phase2_close_percent_value: float,
	draw_walls_value: bool
) -> void:
	enabled = enabled_value
	start_seconds = max(start_seconds_value, 0.0)
	phase_interval_seconds = max(phase_interval_seconds_value, 0.0)
	phase1_close_percent = clamp(phase1_close_percent_value, 0.0, 0.95)
	phase2_close_percent = clamp(phase2_close_percent_value, 0.0, 0.95)
	draw_walls = draw_walls_value


func reset_round() -> void:
	phase = 0
	elapsed_seconds = 0.0
	close_percent = 0.0
	needs_redraw = draw_walls


func tick(
	delta: float,
	match_over: bool,
	round_active: bool,
	player_one: Node2D,
	player_two: Node2D,
	wrap_bounds: Rect2,
	get_half_width: Callable
) -> Dictionary:
	needs_redraw = false
	if not enabled:
		return {"restart_round": false, "redraw": false}
	if match_over or not round_active:
		return {"restart_round": false, "redraw": false}
	elapsed_seconds += delta
	var both_alive := _is_alive(player_one) and _is_alive(player_two)
	if phase == 0:
		if elapsed_seconds >= start_seconds and both_alive:
			phase = 1
			close_percent = phase1_close_percent
			needs_redraw = draw_walls
	elif phase == 1:
		if elapsed_seconds >= start_seconds + phase_interval_seconds and both_alive:
			phase = 2
			close_percent = phase2_close_percent
			needs_redraw = draw_walls
	elif phase == 2:
		if elapsed_seconds >= start_seconds + phase_interval_seconds * 2.0 and both_alive:
			phase = 3
			close_percent = 0.5
			needs_redraw = draw_walls
			return {"restart_round": true, "redraw": needs_redraw}
	if phase == 1 or phase == 2:
		_apply_walls(player_one, wrap_bounds, get_half_width)
		_apply_walls(player_two, wrap_bounds, get_half_width)
	return {"restart_round": false, "redraw": needs_redraw}


func _is_alive(player: Node) -> bool:
	if player == null:
		return false
	return not bool(player.get("is_dead"))


func _try_die(player: Node) -> void:
	if player == null:
		return
	if player.has_method("die"):
		player.call("die")


func _apply_walls(player: Node2D, wrap_bounds: Rect2, get_half_width: Callable) -> void:
	if player == null:
		return
	if not _is_alive(player):
		return
	var left := wrap_bounds.position.x
	var right := wrap_bounds.position.x + wrap_bounds.size.x
	var width := wrap_bounds.size.x
	var half_width := 0.0
	if get_half_width.is_valid():
		half_width = float(get_half_width.call(player))
	var safe_left := left + width * close_percent + half_width
	var safe_right := right - width * close_percent - half_width
	var x := player.global_position.x
	if x <= safe_left or x >= safe_right:
		_try_die(player)


func get_state() -> Dictionary:
	return {
		"enabled": enabled,
		"start_seconds": start_seconds,
		"phase_interval_seconds": phase_interval_seconds,
		"phase1_close_percent": phase1_close_percent,
		"phase2_close_percent": phase2_close_percent,
		"draw_walls": draw_walls,
		"phase": phase,
		"elapsed_seconds": elapsed_seconds,
		"close_percent": close_percent
	}


func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("enabled"):
		enabled = bool(state["enabled"])
	if state.has("start_seconds"):
		start_seconds = float(state["start_seconds"])
	if state.has("phase_interval_seconds"):
		phase_interval_seconds = float(state["phase_interval_seconds"])
	if state.has("phase1_close_percent"):
		phase1_close_percent = float(state["phase1_close_percent"])
	if state.has("phase2_close_percent"):
		phase2_close_percent = float(state["phase2_close_percent"])
	if state.has("draw_walls"):
		draw_walls = bool(state["draw_walls"])
	if state.has("phase"):
		phase = int(state["phase"])
	if state.has("elapsed_seconds"):
		elapsed_seconds = float(state["elapsed_seconds"])
	if state.has("close_percent"):
		close_percent = float(state["close_percent"])
	needs_redraw = draw_walls
