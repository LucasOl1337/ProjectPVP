extends SceneTree





const MAIN_SCENE := preload("res://engine/scenes/Main.tscn")

const StateSerializer = preload("res://engine/scripts/modules/state_serializer.gd")



const DEFAULT_SIM_FRAMES := 720

const DEFAULT_RUNS := 2

const DEFAULT_SEED := 1337

const DASH_KEYS := ["l1", "l2", "r1", "r2"]



var sim_frames := DEFAULT_SIM_FRAMES

var runs := DEFAULT_RUNS

var base_seed := DEFAULT_SEED

var dump_every := 60

var hold_states: Dictionary = {}





func _initialize() -> void:

	_parse_cli_args()

	var signatures: Array[String] = []

	for i in range(runs):

		signatures.append(_run_simulation(base_seed + i))

	var reference := signatures[0]

	var consistent := true

	for sig in signatures:

		if sig != reference:

			consistent = false

			break

	if consistent:

		print("[FrameChecksumRunner] PASS frames=%d runs=%d signature=%s" % [sim_frames, runs, reference])

		quit()

	else:

		push_error("[FrameChecksumRunner] FAIL signatures=%s" % var_to_str(signatures))

		quit(1)





func _parse_cli_args() -> void:

	for arg in OS.get_cmdline_args():

		if arg.begins_with("--frames="):

			sim_frames = int(arg.get_slice("=", 1))

		elif arg.begins_with("--runs="):

			runs = max(2, int(arg.get_slice("=", 1)))

		elif arg.begins_with("--seed="):

			base_seed = int(arg.get_slice("=", 1))

		elif arg.begins_with("--dump-every="):

			dump_every = max(0, int(arg.get_slice("=", 1)))





func _run_simulation(seed: int) -> String:

	hold_states.clear()

	var rng := RandomNumberGenerator.new()

	rng.seed = seed

	var scene: Node = MAIN_SCENE.instantiate()

	get_root().add_child(scene)

	process_frame()

	_configure_external_input(scene)

	var per_frame_hashes: PackedStringArray = []

	per_frame_hashes.resize(sim_frames)

	for frame in range(sim_frames):

		_inject_inputs(scene, rng, frame)

		process_frame()

		var state: Dictionary = scene.get_state() if scene.has_method("get_state") else {}

		var h := StateSerializer.hash_state(state)

		per_frame_hashes[frame] = h

		if dump_every > 0 and (frame % dump_every) == 0:

			print("[FrameChecksum] seed=%d frame=%d hash=%s" % [seed, frame, h])

	var joined := "\n".join(per_frame_hashes)

	var signature := joined.to_utf8_buffer().sha256_text()

	scene.queue_free()

	process_frame()

	return signature





func _configure_external_input(scene: Node) -> void:

	for player in _players(scene):

		if player == null:

			continue

		if not player.has_variable("input_reader"):

			continue

		var reader := player.input_reader

		if reader and reader.has_method("set_use_external_frames"):

			reader.set_use_external_frames(true)





func _inject_inputs(scene: Node, rng: RandomNumberGenerator, frame_number: int) -> void:

	for player in _players(scene):

		if player == null:

			continue

		var reader := player.input_reader if player.has_variable("input_reader") else null

		if reader == null:

			continue

		var frame := _build_frame_dict(rng, player.player_id, frame_number)

		reader.push_frame(frame)





func _players(scene: Node) -> Array:

	var list: Array = []

	if scene.has_variable("player_one"):

		list.append(scene.player_one)

	if scene.has_variable("player_two"):

		list.append(scene.player_two)

	return list





func _build_frame_dict(rng: RandomNumberGenerator, player_id: int, frame_number: int) -> Dictionary:

	var axis_value := rng.randi_range(-1, 1)

	var aim := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))

	if aim.length_squared() < 0.01:

		aim = Vector2.RIGHT

	var dash_pressed: Array = []

	if rng.randf() < 0.2:

		dash_pressed.append(DASH_KEYS[rng.randi_range(0, DASH_KEYS.size() - 1)])

		if rng.randf() < 0.35:

			var extra := DASH_KEYS[rng.randi_range(0, DASH_KEYS.size() - 1)]

			if extra != dash_pressed[0]:

				dash_pressed.append(extra)

	var hold_state := hold_states.get(player_id, {"shoot_hold": false})

	var shoot_hold := bool(hold_state.get("shoot_hold", false))

	var shoot_pressed := false

	if shoot_hold:

		if rng.randf() < 0.2:

			shoot_hold = false

	else:

		if rng.randf() < 0.12:

			shoot_hold = true

			shoot_pressed = true

	hold_state["shoot_hold"] = shoot_hold

	hold_states[player_id] = hold_state

	return {

		"frame": frame_number,

		"axis": float(axis_value),

		"aim": aim,

		"jump_pressed": rng.randf() < 0.08,

		"shoot_pressed": shoot_pressed,

		"shoot_is_pressed": shoot_hold,

		"dash_pressed": dash_pressed,

		"melee_pressed": rng.randf() < 0.1,

		"ult_pressed": rng.randf() < 0.05,

		"actions": {

			"left": axis_value < 0,

			"right": axis_value > 0,

			"up": rng.randf() < 0.2,

			"down": rng.randf() < 0.2,

		}

	}



