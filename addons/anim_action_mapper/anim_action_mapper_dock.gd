@tool
extends VBoxContainer


const CharacterData = preload("res://engine/scripts/characters/character_data.gd")

const DEFAULT_ACTIONS: Array[String] = [
	"idle",
	"walk",
	"running",
	"dash",
	"jump_start",
	"jump_air",
	"crouch",
	"aim",
	"shoot",
	"melee",
	"ult",
	"hurt",
	"death",
]

const DIRECTION_KEYS: Array[String] = [
	"right",
	"left",
	"up",
	"down",
	"up_right",
	"up_left",
	"down_right",
	"down_left",
]


var _editor: EditorInterface

var _data: CharacterData
var _dirty := false

var _data_path_edit: LineEdit
var _status_label: Label
var _actions_root: VBoxContainer
var _save_button: Button
var _apply_button: Button
var _reload_button: Button
var _mcp_char_id_edit: LineEdit
var _mcp_uuid_edit: LineEdit
var _mcp_import_button: Button
var _mcp_thread: Thread
var _data_dialog: EditorFileDialog
var _dir_dialog: EditorFileDialog
var _gif_dialog: EditorFileDialog
var _sfx_dialog: EditorFileDialog
var _texture_dialog: EditorFileDialog

var _pending_dir_pick := {}
var _pending_gif_pick := {}
var _pending_sfx_pick := {}
var _pending_texture_pick := {}


func _init(editor: EditorInterface) -> void:
	_editor = editor


func _ready() -> void:
	_build_ui()
	_set_status("Selecione um CharacterData (.tres/.res) para editar.")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var header := HBoxContainer.new()
	add_child(header)

	var pick_button := Button.new()
	pick_button.text = "Selecionar CharacterData"
	pick_button.pressed.connect(_open_character_data_dialog)
	header.add_child(pick_button)

	_reload_button = Button.new()
	_reload_button.text = "Recarregar"
	_reload_button.disabled = true
	_reload_button.pressed.connect(_reload_resource)
	header.add_child(_reload_button)

	_save_button = Button.new()
	_save_button.text = "Salvar"
	_save_button.disabled = true
	_save_button.pressed.connect(_save_resource)
	header.add_child(_save_button)

	_apply_button = Button.new()
	_apply_button.text = "Aplicar"
	_apply_button.disabled = true
	_apply_button.pressed.connect(_apply_changes)
	header.add_child(_apply_button)

	_data_path_edit = LineEdit.new()
	_data_path_edit.editable = false
	_data_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_data_path_edit)

	var mcp_panel := PanelContainer.new()
	add_child(mcp_panel)
	var mcp_root := VBoxContainer.new()
	mcp_panel.add_child(mcp_root)

	var mcp_title := Label.new()
	mcp_title.text = "Import MCP (PixelLab)"
	mcp_root.add_child(mcp_title)

	var mcp_row := HBoxContainer.new()
	mcp_root.add_child(mcp_row)

	_mcp_char_id_edit = LineEdit.new()
	_mcp_char_id_edit.placeholder_text = "char_id (ex: storm_dragon)"
	_mcp_char_id_edit.custom_minimum_size = Vector2(220, 0)
	mcp_row.add_child(_mcp_char_id_edit)

	_mcp_uuid_edit = LineEdit.new()
	_mcp_uuid_edit.placeholder_text = "uuid PixelLab (opcional)"
	_mcp_uuid_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mcp_row.add_child(_mcp_uuid_edit)

	_mcp_import_button = Button.new()
	_mcp_import_button.text = "Importar + Organizar"
	_mcp_import_button.pressed.connect(_start_mcp_import)
	mcp_row.add_child(_mcp_import_button)

	var projectile_panel := PanelContainer.new()
	add_child(projectile_panel)
	var projectile_root := VBoxContainer.new()
	projectile_panel.add_child(projectile_root)

	var projectile_title := Label.new()
	projectile_title.text = "Projétil (Flecha)"
	projectile_root.add_child(projectile_title)

	var tex_row := HBoxContainer.new()
	projectile_root.add_child(tex_row)

	var tex_label := Label.new()
	tex_label.text = "Texture"
	tex_label.custom_minimum_size = Vector2(70, 0)
	tex_row.add_child(tex_label)

	var tex_edit := LineEdit.new()
	tex_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tex_edit.text = _get_projectile_texture_path()
	tex_edit.text_submitted.connect(func(_t: String): _set_projectile_texture_from_path(tex_edit.text))
	tex_edit.focus_exited.connect(func(): _set_projectile_texture_from_path(tex_edit.text))
	tex_row.add_child(tex_edit)

	var tex_browse := Button.new()
	tex_browse.text = "…"
	tex_browse.pressed.connect(func():
		_pending_texture_pick = {"edit": tex_edit}
		_texture_dialog.popup_centered_ratio(0.7)
	)
	tex_row.add_child(tex_browse)

	var tex_clear := Button.new()
	tex_clear.text = "X"
	tex_clear.pressed.connect(func():
		_set_projectile_texture(null)
		tex_edit.text = ""
	)
	tex_row.add_child(tex_clear)

	var off_row := HBoxContainer.new()
	projectile_root.add_child(off_row)

	var fwd_label := Label.new()
	fwd_label.text = "Forward"
	fwd_label.custom_minimum_size = Vector2(70, 0)
	off_row.add_child(fwd_label)

	var fwd := SpinBox.new()
	fwd.min_value = -500.0
	fwd.max_value = 500.0
	fwd.step = 1.0
	fwd.custom_minimum_size = Vector2(110, 0)
	fwd.value = float(_data.projectile_forward) if _data != null else 0.0
	fwd.value_changed.connect(func(v: float):
		if _data == null:
			return
		_data.projectile_forward = float(v)
		_mark_dirty()
	)
	off_row.add_child(fwd)

	var vlabel := Label.new()
	vlabel.text = "Y"
	vlabel.custom_minimum_size = Vector2(20, 0)
	off_row.add_child(vlabel)

	var voff := SpinBox.new()
	voff.min_value = -500.0
	voff.max_value = 500.0
	voff.step = 1.0
	voff.custom_minimum_size = Vector2(110, 0)
	voff.value = float(_data.projectile_vertical_offset) if _data != null else 0.0
	voff.value_changed.connect(func(v: float):
		if _data == null:
			return
		_data.projectile_vertical_offset = float(v)
		_mark_dirty()
	)
	off_row.add_child(voff)

	var hint := Label.new()
	hint.text = "SFX do tiro: configure na ação SHOOT (campo SFX)"
	projectile_root.add_child(hint)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_actions_root = VBoxContainer.new()
	_actions_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_actions_root)

	_data_dialog = EditorFileDialog.new()
	_data_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_data_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_data_dialog.add_filter("*.tres ; Resource")
	_data_dialog.add_filter("*.res ; Resource")
	_data_dialog.file_selected.connect(_on_character_data_selected)
	add_child(_data_dialog)

	_dir_dialog = EditorFileDialog.new()
	_dir_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_dir_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_dir_dialog)

	_gif_dialog = EditorFileDialog.new()
	_gif_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_gif_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_gif_dialog.add_filter("*.gif ; GIF")
	_gif_dialog.file_selected.connect(_on_gif_selected)
	add_child(_gif_dialog)

	_sfx_dialog = EditorFileDialog.new()
	_sfx_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_sfx_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_sfx_dialog.add_filter("*.ogg ; OGG")
	_sfx_dialog.add_filter("*.wav ; WAV")
	_sfx_dialog.add_filter("*.mp3 ; MP3")
	_sfx_dialog.file_selected.connect(_on_sfx_selected)
	add_child(_sfx_dialog)

	_texture_dialog = EditorFileDialog.new()
	_texture_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_texture_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_texture_dialog.add_filter("*.png ; PNG")
	_texture_dialog.add_filter("*.webp ; WEBP")
	_texture_dialog.add_filter("*.tres ; Resource")
	_texture_dialog.add_filter("*.res ; Resource")
	_texture_dialog.file_selected.connect(_on_texture_selected)
	add_child(_texture_dialog)


func _open_character_data_dialog() -> void:
	_data_dialog.popup_centered_ratio(0.7)


func _on_character_data_selected(path: String) -> void:
	var res := load(path)
	if res == null:
		_set_status("Falha ao carregar: %s" % path)
		return
	if not (res is CharacterData):
		_set_status("O recurso selecionado não é CharacterData: %s" % path)
		return
	_set_character_data(res)


func _set_character_data(data: CharacterData) -> void:
	_data = data
	_dirty = false
	_data_path_edit.text = _data.resource_path
	_reload_button.disabled = _data.resource_path == ""
	_save_button.disabled = _data.resource_path == ""
	_apply_button.disabled = _data.resource_path == ""
	_rebuild_actions_ui()
	_set_status("Editando: %s" % (_data.resource_path if _data.resource_path != "" else "(sem path; salve como .tres)") )


func _rebuild_actions_ui() -> void:
	for child in _actions_root.get_children():
		child.queue_free()

	var actions := _collect_actions()
	for action in actions:
		_actions_root.add_child(_create_action_panel(action))


func _collect_actions() -> Array[String]:
	var actions: Array[String] = DEFAULT_ACTIONS.duplicate()
	if _data != null:
		for k in _data.action_animation_paths.keys():
			var s := str(k)
			if s != "" and not actions.has(s):
				actions.append(s)
		actions.sort()
	return actions


func _create_action_panel(action: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(details)

	var title := Label.new()
	title.text = action.to_upper()
	title.custom_minimum_size = Vector2(120, 0)
	title.add_theme_font_size_override("font_size", 16)
	top.add_child(title)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = _action_should_expand(action)
	toggle.text = "▼" if toggle.button_pressed else "▶"
	toggle.toggled.connect(func(pressed: bool):
		details.visible = pressed
		toggle.text = "▼" if pressed else "▶"
	)
	top.add_child(toggle)

	details.visible = toggle.button_pressed

	var controls := HBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(controls)

	var mode := OptionButton.new()
	mode.add_item("Shared", 0)
	mode.add_item("Direções (custom)", 1)
	mode.selected = 1 if _action_has_custom_dirs(action) else 0
	mode.item_selected.connect(func(_idx: int):
		_set_action_mode(action, mode.selected)
		_rebuild_actions_ui()
	)
	controls.add_child(mode)

	var auto_button := Button.new()
	auto_button.text = "Auto"
	auto_button.pressed.connect(func(): _auto_set_default_path(action))
	controls.add_child(auto_button)

	if mode.selected == 0:
		var mirror_left := Button.new()
		mirror_left.text = "Gerar esquerda"
		mirror_left.pressed.connect(func(): _mirror_direction(action, -1))
		controls.add_child(mirror_left)

		var mirror_right := Button.new()
		mirror_right.text = "Gerar direita"
		mirror_right.pressed.connect(func(): _mirror_direction(action, 1))
		controls.add_child(mirror_right)

	var validate_button := Button.new()
	validate_button.text = "Validar"
	validate_button.pressed.connect(func(): _validate_action_paths(action))
	controls.add_child(validate_button)

	var import_gif_button := Button.new()
	import_gif_button.text = "Importar GIF"
	import_gif_button.pressed.connect(Callable(self, "_open_gif_dialog").bind(action, ""))
	controls.add_child(import_gif_button)

	var sep := HSeparator.new()
	details.add_child(sep)

	var paths_box := VBoxContainer.new()
	paths_box.name = "Paths"
	details.add_child(paths_box)

	if mode.selected == 0:
		var add_path := Button.new()
		add_path.text = "+ path"
		add_path.pressed.connect(func():
			var config := _get_action_config(action)
			var paths := config.get("shared", [])
			paths.append("")
			config["shared"] = paths
			_set_action_config(action, config)
			_rebuild_actions_ui()
		)
		root.add_child(add_path)

		var config := _get_action_config(action)
		var paths: Array = config.get("shared", [])
		if paths.is_empty():
			paths = [""]
		for i in range(paths.size()):
			paths_box.add_child(_create_path_row(action, i, str(paths[i])))
	else:
		paths_box.add_child(_create_dir_grid(action))

	var params := HBoxContainer.new()
	details.add_child(params)

	params.add_child(_create_duration_control(action))
	params.add_child(_create_speed_control(action))
	params.add_child(_create_anchor_control(action))
	params.add_child(_create_action_scale_control(action))
	params.add_child(_create_action_offset_control(action))
	params.add_child(_create_action_sfx_control(action))

	return panel


func _action_should_expand(action: String) -> bool:
	if _data == null:
		return true
	var config := _get_action_config(action)
	var shared: Array = config.get("shared", [])
	for p in shared:
		if str(p).strip_edges() != "":
			return true
	if _action_has_custom_dirs(action):
		return true
	var s := _get_action_float(_get_dict_prop("action_sprite_scale"), action, 1.0)
	if not is_equal_approx(s, 1.0):
		return true
	var off := _get_action_vec2(_get_dict_prop("action_sprite_offset"), action, Vector2.ZERO)
	if off != Vector2.ZERO:
		return true
	return false


func _create_path_row(action: String, index: int, value: String) -> Control:
	var row := HBoxContainer.new()

	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(_t: String): _commit_path_edit(action, index, edit.text))
	edit.focus_exited.connect(func(): _commit_path_edit(action, index, edit.text))
	row.add_child(edit)

	var browse := Button.new()
	browse.text = "…"
	browse.pressed.connect(func():
		_pending_dir_pick = {"action": action, "index": index, "edit": edit}
		_dir_dialog.popup_centered_ratio(0.7)
	)
	row.add_child(browse)

	var remove := Button.new()
	remove.text = "-"
	remove.disabled = false
	remove.pressed.connect(func():
		var config := _get_action_config(action)
		var paths: Array = config.get("shared", [])
		if index >= 0 and index < paths.size():
			paths.remove_at(index)
			config["shared"] = paths
			_set_action_config(action, config)
			_rebuild_actions_ui()
	)
	row.add_child(remove)

	return row


func _commit_path_edit(action: String, index: int, text: String) -> void:
	var config := _get_action_config(action)
	var paths: Array = config.get("shared", [])
	while paths.size() <= index:
		paths.append("")
	paths[index] = text.strip_edges()
	config["shared"] = paths
	_set_action_config(action, config)


func _on_dir_selected(dir_path: String) -> void:
	if _pending_dir_pick.is_empty():
		return
	var edit: LineEdit = _pending_dir_pick.get("edit")
	if edit != null:
		edit.text = dir_path
	var action := str(_pending_dir_pick.get("action"))
	if _pending_dir_pick.has("dir"):
		_commit_dir_path_edit(action, str(_pending_dir_pick.get("dir")), dir_path)
	else:
		_commit_path_edit(action, int(_pending_dir_pick.get("index")), dir_path)
	_pending_dir_pick = {}


func _open_gif_dialog(action: String, dir_key: String = "") -> void:
	_pending_gif_pick = {"action": action, "dir": dir_key}
	_gif_dialog.popup_centered_ratio(0.7)


func _open_gif_dialog_compat(action: String) -> void:
	_open_gif_dialog(action, "")


func _on_gif_selected(file_path: String) -> void:
	var action := str(_pending_gif_pick.get("action", ""))
	var dir_key := str(_pending_gif_pick.get("dir", ""))
	_pending_gif_pick = {}
	if action == "":
		return
	if _data == null:
		return
	var ok := _import_gif_to_action(file_path, action, dir_key)
	if ok:
		_rebuild_actions_ui()


func _open_sfx_dialog(action: String) -> void:
	_pending_sfx_pick = {"action": action}
	_sfx_dialog.popup_centered_ratio(0.7)


func _on_sfx_selected(path: String) -> void:
	var action := str(_pending_sfx_pick.get("action", ""))
	_pending_sfx_pick = {}
	if action == "" or _data == null:
		return
	_set_action_sfx_path(action, path)
	_rebuild_actions_ui()


func _on_texture_selected(path: String) -> void:
	var edit: LineEdit = _pending_texture_pick.get("edit")
	_pending_texture_pick = {}
	_set_projectile_texture_from_path(path)
	if edit != null:
		edit.text = _get_projectile_texture_path()
	_rebuild_actions_ui()


func _get_projectile_texture_path() -> String:
	if _data == null:
		return ""
	if _data.projectile_texture == null:
		return ""
	return String(_data.projectile_texture.resource_path)


func _set_projectile_texture_from_path(path: String) -> void:
	if _data == null:
		return
	var p := path.strip_edges()
	if p == "":
		_set_projectile_texture(null)
		return
	var tex := load(p)
	if tex is Texture2D:
		_set_projectile_texture(tex)
	else:
		_set_status("Texture inválida: %s" % p)


func _set_projectile_texture(tex: Texture2D) -> void:
	if _data == null:
		return
	_data.projectile_texture = tex
	_mark_dirty()


func _get_action_sfx_path(action: String) -> String:
	if _data == null:
		return ""
	if _data.action_sfx_paths == null:
		return ""
	if not _data.action_sfx_paths.has(action):
		return ""
	return str(_data.action_sfx_paths[action])


func _set_action_sfx_path(action: String, path: String) -> void:
	if _data == null:
		return
	var p := path.strip_edges()
	if p == "":
		if _data.action_sfx_paths.has(action):
			_data.action_sfx_paths.erase(action)
			_mark_dirty()
		return
	_data.action_sfx_paths[action] = p
	_mark_dirty()


func _import_gif_to_action(file_path: String, action: String, dir_key: String) -> bool:
	var config := _get_action_config(action)
	var out_res_dir := ""
	if dir_key == "":
		var shared: Array = config.get("shared", [])
		if shared.size() > 0 and str(shared[0]).strip_edges() != "":
			out_res_dir = str(shared[0]).strip_edges()
		else:
			var char_id := str(_data.id)
			if char_id == "":
				char_id = "character"
			out_res_dir = "res://visuals/imported_gifs/%s/%s/" % [char_id, action]
			config["shared"] = [out_res_dir]
			_set_action_config(action, config)
	else:
		var dirs: Dictionary = config.get("dirs", {})
		var entry: Variant = dirs.get(dir_key, [])
		var arr: Array = entry if entry is Array else []
		if arr.size() > 0 and str(arr[0]).strip_edges() != "":
			out_res_dir = str(arr[0]).strip_edges()
		else:
			var char_id2 := str(_data.id)
			if char_id2 == "":
				char_id2 = "character"
			out_res_dir = "res://visuals/imported_gifs/%s/%s/%s/" % [char_id2, action, dir_key]
			dirs[dir_key] = [out_res_dir]
			config["dirs"] = dirs
			_set_action_config(action, config)

	var out_global := _globalize_path(out_res_dir)
	DirAccess.make_dir_recursive_absolute(out_global)
	var pattern := out_global.path_join("frame_%03d.png")
	var input_path := file_path
	if input_path.begins_with("res://"):
		input_path = ProjectSettings.globalize_path(input_path)

	var output: Array = []
	var args := PackedStringArray(["convert", input_path, "-coalesce", pattern])
	var magick := _resolve_magick_command()
	var exit_code := OS.execute(magick, args, output, true)
	if exit_code != 0:
		var output_text := "\n".join(output)
		if exit_code == -1:
			magick = _find_magick_exe_windows()
			if magick == "":
				_set_status("Falha ao importar GIF: ImageMagick não encontrado (comando 'magick').\nInstale o ImageMagick e reinicie o editor.\n" + output_text)
				return false
			exit_code = OS.execute(magick, args, output, true)
			if exit_code == 0:
				_rescan_filesystem()
				_set_status("GIF importado para: %s" % out_res_dir)
				return true
		var output2: Array = []
		var exit_code2 := OS.execute(magick, PackedStringArray([input_path, "-coalesce", pattern]), output2, true)
		if exit_code2 != 0:
			var hint := "Para importar GIF, instale o ImageMagick (comando 'magick') ou converta manualmente para PNG sequence/spritesheet."
			var output_text2 := "\n".join(output2)
			_set_status("Falha ao importar GIF (exit=%s/%s). %s\n%s\n%s" % [str(exit_code), str(exit_code2), hint, output_text, output_text2])
			return false

	_rescan_filesystem()
	_set_status("GIF importado para: %s" % out_res_dir)
	return true


func _resolve_magick_command() -> String:
	if OS.has_feature("windows"):
		var exe := _find_magick_exe_windows()
		if exe != "":
			return exe
	return "magick"


func _find_magick_exe_windows() -> String:
	for root: String in ["C:/Program Files", "C:/Program Files (x86)"]:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and entry.begins_with("ImageMagick"):
				var candidate: String = root.path_join(entry).path_join("magick.exe")
				if FileAccess.file_exists(candidate):
					dir.list_dir_end()
					return candidate
			entry = dir.get_next()
		dir.list_dir_end()
	return ""


func _action_has_custom_dirs(action: String) -> bool:
	if _data == null:
		return false
	var raw: Variant = _data.action_animation_paths.get(action, null)
	if raw is Dictionary:
		if (raw as Dictionary).get("__mode", "") == "dirs":
			return true
		for k in (raw as Dictionary).keys():
			var ks := str(k)
			if ks != "" and ks != "shared":
				return true
	return false


func _set_action_mode(action: String, mode: int) -> void:
	if _data == null:
		return
	var config := _get_action_config(action)
	if mode == 0:
		config["dirs"] = {}
		if config.has("__mode"):
			config.erase("__mode")
	else:
		if not config.has("dirs"):
			config["dirs"] = {}
		config["__mode"] = "dirs"
	_set_action_config(action, config)


func _get_action_config(action: String) -> Dictionary:
	var shared: Array[String] = []
	var dirs: Dictionary = {}
	if _data == null:
		return {"shared": shared, "dirs": dirs}
	var raw: Variant = _data.action_animation_paths.get(action, null)
	if raw is Dictionary:
		if (raw as Dictionary).has("__mode"):
			dirs["__mode"] = (raw as Dictionary)["__mode"]
		for k in (raw as Dictionary).keys():
			var key := str(k)
			var v: Variant = (raw as Dictionary)[k]
			if key == "__mode":
				continue
			if key == "" or key == "shared":
				shared = _coerce_paths_array(v)
			else:
				dirs[key] = _coerce_paths_array(v)
	elif raw != null:
		shared = _coerce_paths_array(raw)
	var out_dirs := dirs
	var mode_value := ""
	if out_dirs.has("__mode"):
		mode_value = str(out_dirs["__mode"])
		out_dirs.erase("__mode")
	var out := {"shared": shared, "dirs": out_dirs}
	if mode_value != "":
		out["__mode"] = mode_value
	return out


func _set_action_config(action: String, config: Dictionary) -> void:
	if _data == null:
		return
	var shared: Array[String] = []
	var dirs: Dictionary = {}
	var force_mode := str(config.get("__mode", ""))
	if config.has("shared") and config["shared"] is Array:
		shared = _clean_paths(config["shared"])
	if config.has("dirs") and config["dirs"] is Dictionary:
		for k in (config["dirs"] as Dictionary).keys():
			var key := str(k).strip_edges()
			if key == "" or key == "shared":
				continue
			var arr := _clean_paths(_coerce_paths_array((config["dirs"] as Dictionary)[k]))
			if not arr.is_empty():
				dirs[key] = arr

	var force_dict := force_mode == "dirs"
	if dirs.is_empty() and not force_dict:
		if shared.is_empty():
			if _data.action_animation_paths.has(action):
				_data.action_animation_paths.erase(action)
				_mark_dirty()
			return
		_data.action_animation_paths[action] = shared
		_mark_dirty()
		return

	var out := {}
	if force_dict:
		out["__mode"] = "dirs"
	if not shared.is_empty():
		out["shared"] = shared
	for k in dirs.keys():
		out[k] = dirs[k]
	_data.action_animation_paths[action] = out
	_mark_dirty()


func _coerce_paths_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for p in raw:
			out.append(str(p))
		return out
	if raw is PackedStringArray:
		for p in raw:
			out.append(str(p))
		return out
	if raw != null and str(raw) != "":
		out.append(str(raw))
	return out


func _clean_paths(paths: Array) -> Array[String]:
	var cleaned: Array[String] = []
	for p in paths:
		var s := str(p).strip_edges()
		if s != "":
			cleaned.append(s)
	return cleaned


func _create_dir_grid(action: String) -> Control:
	var box := VBoxContainer.new()
	var config := _get_action_config(action)
	var dirs: Dictionary = config.get("dirs", {})
	var shared: Array = config.get("shared", [])

	var shared_row := HBoxContainer.new()
	var shared_label := Label.new()
	shared_label.text = "shared"
	shared_label.custom_minimum_size = Vector2(90, 0)
	shared_row.add_child(shared_label)

	var shared_edit := LineEdit.new()
	shared_edit.text = str(shared[0]) if shared.size() > 0 else ""
	shared_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shared_edit.text_submitted.connect(func(_t: String): _commit_path_edit(action, 0, shared_edit.text))
	shared_edit.focus_exited.connect(func(): _commit_path_edit(action, 0, shared_edit.text))
	shared_row.add_child(shared_edit)

	var shared_browse := Button.new()
	shared_browse.text = "…"
	shared_browse.pressed.connect(func():
		_pending_dir_pick = {"action": action, "index": 0, "edit": shared_edit}
		_dir_dialog.popup_centered_ratio(0.7)
	)
	shared_row.add_child(shared_browse)

	var shared_gif := Button.new()
	shared_gif.text = "GIF"
	shared_gif.pressed.connect(Callable(self, "_open_gif_dialog").bind(action, ""))
	shared_row.add_child(shared_gif)

	box.add_child(shared_row)

	for dir_key in DIRECTION_KEYS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = dir_key
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)

		var edit := LineEdit.new()
		var entry: Variant = dirs.get(dir_key, [])
		var arr: Array = entry if entry is Array else []
		edit.text = str(arr[0]) if arr.size() > 0 else ""
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_submitted.connect(func(_t: String): _commit_dir_path_edit(action, dir_key, edit.text))
		edit.focus_exited.connect(func(): _commit_dir_path_edit(action, dir_key, edit.text))
		row.add_child(edit)

		var browse := Button.new()
		browse.text = "…"
		browse.pressed.connect(func():
			_pending_dir_pick = {"action": action, "dir": dir_key, "edit": edit}
			_dir_dialog.popup_centered_ratio(0.7)
		)
		row.add_child(browse)

		var gif := Button.new()
		gif.text = "GIF"
		gif.pressed.connect(Callable(self, "_open_gif_dialog").bind(action, dir_key))
		row.add_child(gif)

		if dir_key == "left":
			var mir := Button.new()
			mir.text = "Espelhar do right"
			mir.pressed.connect(func(): _mirror_dir(action, "right", "left"))
			row.add_child(mir)
		elif dir_key == "right":
			var mir2 := Button.new()
			mir2.text = "Espelhar do left"
			mir2.pressed.connect(func(): _mirror_dir(action, "left", "right"))
			row.add_child(mir2)

		box.add_child(row)

	return box


func _commit_dir_path_edit(action: String, dir_key: String, text: String) -> void:
	var config := _get_action_config(action)
	var dirs: Dictionary = config.get("dirs", {})
	var cleaned := text.strip_edges()
	if cleaned == "":
		if dirs.has(dir_key):
			dirs.erase(dir_key)
	else:
		dirs[dir_key] = [cleaned]
	config["dirs"] = dirs
	_set_action_config(action, config)


func _mirror_dir(action: String, source_dir: String, target_dir: String) -> void:
	var config := _get_action_config(action)
	var dirs: Dictionary = config.get("dirs", {})
	var src_arr: Variant = dirs.get(source_dir, [])
	var dst_arr: Variant = dirs.get(target_dir, [])
	var src_list: Array = src_arr if src_arr is Array else []
	var dst_list: Array = dst_arr if dst_arr is Array else []
	if src_list.is_empty() or str(src_list[0]).strip_edges() == "":
		_set_status("[%s] defina path da direção '%s' primeiro." % [action, source_dir])
		return
	if dst_list.is_empty() or str(dst_list[0]).strip_edges() == "":
		var shared: Array = config.get("shared", [])
		var base_res := str(shared[0]).strip_edges() if shared.size() > 0 else ""
		var dst_res := ""
		if base_res != "":
			if not base_res.ends_with("/"):
				base_res += "/"
			dst_res = base_res + target_dir + "/"
		else:
			var src_res := str(src_list[0]).strip_edges()
			if src_res.ends_with("/"):
				src_res = src_res.substr(0, src_res.length() - 1)
			var parent := src_res.get_base_dir()
			dst_res = parent + "/" + target_dir + "/"
		dirs[target_dir] = [dst_res]
		config["dirs"] = dirs
		_set_action_config(action, config)
		dst_list = [dst_res]
	var src_global := _globalize_path(str(src_list[0]))
	var dst_global := _globalize_path(str(dst_list[0]))
	DirAccess.make_dir_recursive_absolute(dst_global)
	var result := _mirror_pngs(src_global, dst_global)
	_rescan_filesystem()
	_rebuild_actions_ui()
	_set_status("[%s] %s" % [action, result])


func _get_action_paths(action: String) -> Array[String]:
	var config := _get_action_config(action)
	var shared: Array = config.get("shared", [])
	var out: Array[String] = []
	for p in shared:
		out.append(str(p))
	return out


func _set_action_paths(action: String, paths: Array[String]) -> void:
	var config := _get_action_config(action)
	config["shared"] = paths
	_set_action_config(action, config)


func _create_duration_control(action: String) -> Control:
	var wrap := HBoxContainer.new()
	var label := Label.new()
	label.text = "Dur"
	wrap.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 10.0
	spin.step = 0.01
	spin.custom_minimum_size = Vector2(90, 0)
	spin.value = _get_action_float(_data.action_animation_durations if _data != null else {}, action, 0.0)
	spin.value_changed.connect(func(v: float):
		_set_action_float(_data.action_animation_durations, action, v)
	)
	wrap.add_child(spin)
	return wrap


func _create_speed_control(action: String) -> Control:
	var wrap := HBoxContainer.new()
	var label := Label.new()
	label.text = "Spd"
	wrap.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 60.0
	spin.step = 0.1
	spin.custom_minimum_size = Vector2(90, 0)
	spin.value = _get_action_float(_data.action_animation_speeds if _data != null else {}, action, 0.0)
	spin.value_changed.connect(func(v: float):
		_set_action_float(_data.action_animation_speeds, action, v)
	)
	wrap.add_child(spin)
	return wrap


func _create_action_scale_control(action: String) -> Control:
	var wrap := HBoxContainer.new()
	var label := Label.new()
	label.text = "Escala"
	wrap.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0.1
	spin.max_value = 3.0
	spin.step = 0.01
	spin.custom_minimum_size = Vector2(110, 0)
	spin.value = _get_action_float(_get_dict_prop("action_sprite_scale"), action, 1.0)
	spin.value_changed.connect(func(v: float):
		_set_dict_prop_float("action_sprite_scale", action, v, 1.0)
	)
	wrap.add_child(spin)
	return wrap


func _create_action_offset_control(action: String) -> Control:
	var wrap := HBoxContainer.new()
	var label := Label.new()
	label.text = "Off"
	wrap.add_child(label)

	var v := _get_action_vec2(_get_dict_prop("action_sprite_offset"), action, Vector2.ZERO)

	var spin_x := SpinBox.new()
	spin_x.min_value = -400.0
	spin_x.max_value = 400.0
	spin_x.step = 0.5
	spin_x.custom_minimum_size = Vector2(90, 0)
	spin_x.value = v.x
	wrap.add_child(spin_x)

	var spin_y := SpinBox.new()
	spin_y.min_value = -400.0
	spin_y.max_value = 400.0
	spin_y.step = 0.5
	spin_y.custom_minimum_size = Vector2(90, 0)
	spin_y.value = v.y
	wrap.add_child(spin_y)

	var apply := func():
		_set_dict_prop_vec2("action_sprite_offset", action, Vector2(float(spin_x.value), float(spin_y.value)), Vector2.ZERO)

	spin_x.value_changed.connect(func(_vx: float): apply.call())
	spin_y.value_changed.connect(func(_vy: float): apply.call())

	return wrap


func _create_action_sfx_control(action: String) -> Control:
	var wrap := HBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = "SFX"
	label.custom_minimum_size = Vector2(40, 0)
	wrap.add_child(label)

	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = _get_action_sfx_path(action)
	edit.text_submitted.connect(func(_t: String): _set_action_sfx_path(action, edit.text))
	edit.focus_exited.connect(func(): _set_action_sfx_path(action, edit.text))
	wrap.add_child(edit)

	var browse := Button.new()
	browse.text = "…"
	browse.pressed.connect(func(): _open_sfx_dialog(action))
	wrap.add_child(browse)

	var clear := Button.new()
	clear.text = "X"
	clear.pressed.connect(func():
		_set_action_sfx_path(action, "")
		_rebuild_actions_ui()
	)
	wrap.add_child(clear)

	var dur_label := Label.new()
	dur_label.text = "Dur"
	wrap.add_child(dur_label)
	var dur := SpinBox.new()
	dur.min_value = 0.0
	dur.max_value = 10.0
	dur.step = 0.01
	dur.custom_minimum_size = Vector2(90, 0)
	dur.value = _get_action_float(_data.action_sfx_durations if _data != null else {}, action, 0.0)
	dur.value_changed.connect(func(v: float):
		_set_action_float(_data.action_sfx_durations, action, v)
	)
	wrap.add_child(dur)

	var spd_label := Label.new()
	spd_label.text = "Pitch"
	wrap.add_child(spd_label)
	var spd := SpinBox.new()
	spd.min_value = 0.1
	spd.max_value = 4.0
	spd.step = 0.05
	spd.custom_minimum_size = Vector2(90, 0)
	spd.value = _get_action_float(_data.action_sfx_speeds if _data != null else {}, action, 1.0)
	spd.value_changed.connect(func(v: float):
		_set_action_float(_data.action_sfx_speeds, action, v)
	)
	wrap.add_child(spd)

	var vol_label := Label.new()
	vol_label.text = "Vol(dB)"
	wrap.add_child(vol_label)
	var vol := SpinBox.new()
	vol.min_value = -60.0
	vol.max_value = 6.0
	vol.step = 0.5
	vol.custom_minimum_size = Vector2(100, 0)
	vol.value = _get_action_float(_data.action_sfx_volumes_db if _data != null else {}, action, -2.0)
	vol.value_changed.connect(func(v: float):
		_set_action_float_with_default(_data.action_sfx_volumes_db, action, v, -2.0)
	)
	wrap.add_child(vol)

	return wrap


func _create_anchor_control(action: String) -> Control:
	var wrap := HBoxContainer.new()
	var cb := CheckBox.new()
	cb.text = "Anchor"
	cb.button_pressed = _data != null and _data.action_ground_anchor_ratio.has(action)
	wrap.add_child(cb)

	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 1.0
	spin.step = 0.01
	spin.custom_minimum_size = Vector2(110, 0)
	spin.value = _get_action_float(_data.action_ground_anchor_ratio if _data != null else {}, action, 1.0)
	spin.editable = cb.button_pressed
	wrap.add_child(spin)

	cb.toggled.connect(func(enabled: bool):
		spin.editable = enabled
		if _data == null:
			return
		if not enabled:
			if _data.action_ground_anchor_ratio.has(action):
				_data.action_ground_anchor_ratio.erase(action)
				_mark_dirty()
		else:
			_data.action_ground_anchor_ratio[action] = float(spin.value)
			_mark_dirty()
	)
	spin.value_changed.connect(func(v: float):
		if _data == null:
			return
		if cb.button_pressed:
			_data.action_ground_anchor_ratio[action] = float(v)
			_mark_dirty()
	)

	return wrap


func _get_action_float(dict: Dictionary, key: String, fallback: float) -> float:
	if dict == null:
		return fallback
	if not dict.has(key):
		return fallback
	var v: Variant = dict[key]
	if v is int or v is float:
		return float(v)
	return fallback


func _set_action_float(dict: Dictionary, key: String, value: float) -> void:
	if _data == null:
		return
	if value <= 0.0:
		if dict.has(key):
			dict.erase(key)
			_mark_dirty()
		return
	dict[key] = float(value)
	_mark_dirty()


func _set_action_float_with_default(dict: Dictionary, key: String, value: float, default_value: float) -> void:
	if _data == null:
		return
	var v := float(value)
	if is_equal_approx(v, default_value):
		if dict.has(key):
			dict.erase(key)
			_mark_dirty()
		return
	dict[key] = v
	_mark_dirty()


func _get_dict_prop(prop: String) -> Dictionary:
	if _data == null:
		return {}
	var v: Variant = _data.get(prop)
	if v is Dictionary:
		return v
	return {}


func _set_dict_prop_float(prop: String, key: String, value: float, default_value: float) -> void:
	if _data == null:
		return
	var d := _get_dict_prop(prop).duplicate(true)
	var v := float(value)
	if is_equal_approx(v, default_value):
		if d.has(key):
			d.erase(key)
	else:
		d[key] = v
	_data.set(prop, d)
	_mark_dirty()


func _set_dict_prop_vec2(prop: String, key: String, value: Vector2, default_value: Vector2) -> void:
	if _data == null:
		return
	var d := _get_dict_prop(prop).duplicate(true)
	if value == default_value:
		if d.has(key):
			d.erase(key)
	else:
		d[key] = value
	_data.set(prop, d)
	_mark_dirty()


func _get_action_vec2(dict: Dictionary, key: String, fallback: Vector2) -> Vector2:
	if dict == null:
		return fallback
	if not dict.has(key):
		return fallback
	var v: Variant = dict[key]
	if v is Vector2:
		return v
	return fallback


func _set_action_vec2(dict: Dictionary, key: String, value: Vector2, fallback: Vector2) -> void:
	if _data == null:
		return
	if value == fallback:
		if dict.has(key):
			dict.erase(key)
			_mark_dirty()
		return
	dict[key] = value
	_mark_dirty()


func _auto_set_default_path(action: String) -> void:
	if _data == null:
		return
	var base := str(_data.asset_base_path)
	if base == "":
		_set_status("asset_base_path está vazio no CharacterData.")
		return
	if not base.ends_with("/"):
		base += "/"
	var candidate := base + "animations/%s/" % action
	var config := _get_action_config(action)
	var shared: Array = config.get("shared", [])
	if shared.is_empty():
		shared = [candidate]
	else:
		shared[0] = candidate
	config["shared"] = shared
	if _action_has_custom_dirs(action):
		var dirs: Dictionary = config.get("dirs", {})
		var base_dir := candidate
		if not base_dir.ends_with("/"):
			base_dir += "/"
		for dir_key in DIRECTION_KEYS:
			if not dirs.has(dir_key):
				dirs[dir_key] = [base_dir + dir_key + "/"]
		config["dirs"] = dirs
	_set_action_config(action, config)
	_rebuild_actions_ui()


func _validate_action_paths(action: String) -> void:
	if _data == null:
		return
	var config := _get_action_config(action)
	var shared: Array = config.get("shared", [])
	var dirs: Dictionary = config.get("dirs", {})

	var missing: Array[String] = []
	var ok_count := 0

	for p in shared:
		if str(p).strip_edges() == "":
			continue
		if _dir_exists(str(p)):
			ok_count += 1
		else:
			missing.append(str(p))

	for k in dirs.keys():
		var entry: Variant = dirs[k]
		var arr: Array = entry if entry is Array else []
		for p2 in arr:
			if str(p2).strip_edges() == "":
				continue
			if _dir_exists(str(p2)):
				ok_count += 1
			else:
				missing.append("%s=%s" % [str(k), str(p2)])

	if ok_count == 0 and missing.is_empty():
		_set_status("[%s] sem paths configurados." % action)
		return
	if missing.is_empty():
		_set_status("[%s] OK (%d paths)." % [action, ok_count])
	else:
		_set_status("[%s] faltando (%d): %s" % [action, missing.size(), ", ".join(missing)])


func _mirror_direction(action: String, target_facing: int) -> void:
	if _data == null:
		return
	var paths := _get_action_paths(action)
	if paths.is_empty():
		_set_status("[%s] defina um path antes de gerar direção." % action)
		return
	var base_res := paths[0]
	if base_res == "":
		_set_status("[%s] path vazio." % action)
		return
	var base_global := _globalize_path(base_res)
	var style := _detect_dir_style(base_global)
	if style == "":
		_set_status("[%s] não detectei pastas direcionais (east/right)." % action)
		return
	var source_dir := ""
	var target_dir := ""
	if style == "east":
		source_dir = "east" if target_facing < 0 else "west"
		target_dir = "west" if target_facing < 0 else "east"
	else:
		source_dir = "right" if target_facing < 0 else "left"
		target_dir = "left" if target_facing < 0 else "right"
	var source := base_global.path_join(source_dir)
	if not DirAccess.dir_exists_absolute(source):
		_set_status("[%s] pasta fonte não existe: %s" % [action, source])
		return
	var target := base_global.path_join(target_dir)
	DirAccess.make_dir_recursive_absolute(target)
	var result := _mirror_pngs(source, target)
	_rescan_filesystem()
	_set_status("[%s] %s" % [action, result])


func _mirror_pngs(source_dir: String, target_dir: String) -> String:
	var dir := DirAccess.open(source_dir)
	if dir == null:
		return "falha ao abrir: %s" % source_dir
	dir.list_dir_begin()
	var name := dir.get_next()
	var written := 0
	var overwritten := 0
	var failed := 0
	while name != "":
		if not dir.current_is_dir() and name.get_extension().to_lower() == "png":
			var src := source_dir.path_join(name)
			var dst := target_dir.path_join(name)
			var existed := FileAccess.file_exists(dst)
			var img := Image.new()
			var err := img.load(src)
			if err == OK:
				img.flip_x()
				var save_err := img.save_png(dst)
				if save_err == OK:
					if existed:
						overwritten += 1
					else:
						written += 1
				else:
					failed += 1
			else:
				failed += 1
		name = dir.get_next()
	dir.list_dir_end()
	return "gerados=%d, sobrescritos=%d, falhas=%d" % [written, overwritten, failed]


func _detect_dir_style(base_global: String) -> String:
	if DirAccess.dir_exists_absolute(base_global.path_join("east")) or DirAccess.dir_exists_absolute(base_global.path_join("west")):
		return "east"
	if DirAccess.dir_exists_absolute(base_global.path_join("right")) or DirAccess.dir_exists_absolute(base_global.path_join("left")):
		return "right"
	return ""


func _dir_exists(path: String) -> bool:
	var g := _globalize_path(path)
	return DirAccess.dir_exists_absolute(g)


func _globalize_path(path: String) -> String:
	var p := path.strip_edges()
	if p.begins_with("res://"):
		return ProjectSettings.globalize_path(p)
	return p


func _rescan_filesystem() -> void:
	if _editor == null:
		return
	var fs := _editor.get_resource_filesystem()
	if fs != null and fs.has_method("scan"):
		fs.call("scan")
	elif fs != null and fs.has_method("scan_sources"):
		fs.call("scan_sources")


func _mark_dirty() -> void:
	_dirty = true
	_save_button.disabled = _data == null or _data.resource_path == ""
	_apply_button.disabled = _data == null or _data.resource_path == ""
	if _data != null and _data.resource_path != "":
		_data_path_edit.text = _data.resource_path + " *"


func _apply_changes() -> void:
	if _data == null:
		return
	if _data.resource_path == "":
		_set_status("O CharacterData não tem resource_path; salve como .tres primeiro.")
		return
	if _dirty:
		_save_resource()
	var reloaded: Variant = ResourceLoader.load(_data.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if reloaded is CharacterData:
		_set_character_data(reloaded)
		_set_status("Aplicado. Se o jogo estiver rodando no editor, deve atualizar em ~0.5s.")
	else:
		_set_status("Aplicado. (Aviso: não consegui recarregar o resource do cache)")


func _save_resource() -> void:
	if _data == null:
		return
	if _data.resource_path == "":
		_set_status("O CharacterData não tem resource_path; salve como .tres primeiro.")
		return
	var err := ResourceSaver.save(_data, _data.resource_path)
	if err == OK:
		_dirty = false
		_data_path_edit.text = _data.resource_path
		_set_status("Salvo: %s" % _data.resource_path)
	else:
		_set_status("Falha ao salvar (%s): %s" % [str(err), _data.resource_path])


func _reload_resource() -> void:
	if _data == null:
		return
	if _data.resource_path == "":
		return
	var res := load(_data.resource_path)
	if res != null and res is CharacterData:
		_set_character_data(res)
		_set_status("Recarregado: %s" % _data.resource_path)
	else:
		_set_status("Falha ao recarregar: %s" % _data.resource_path)


func _set_status(text: String) -> void:
	_status_label.text = text


func _start_mcp_import() -> void:
	var char_id := _mcp_char_id_edit.text.strip_edges()
	if char_id == "":
		_set_status("Informe um char_id (ex: storm_dragon).")
		return
	if _mcp_thread != null and _mcp_thread.is_started():
		_set_status("Import já está rodando…")
		return
	_mcp_import_button.disabled = true
	_set_status("Importando via MCP… (isso pode demorar)")
	_mcp_thread = Thread.new()
	_mcp_thread.start(_thread_mcp_import.bind({"char_id": char_id, "uuid": _mcp_uuid_edit.text.strip_edges()}))


func _thread_mcp_import(params: Dictionary) -> void:
	var char_id := str(params.get("char_id", "")).strip_edges()
	var uuid := str(params.get("uuid", "")).strip_edges()
	var output: Array = []
	var exit_code := 0

	var project_root := ProjectSettings.globalize_path("res://")
	var python := "python"
	if uuid != "":
		var code := "import os,runpy,sys; os.chdir(r'%s'); sys.argv=['pixellab_manual_download.py','--uuid','%s','--name','%s']; runpy.run_path('engine/tools/pixellab_manual_download.py', run_name='__main__')" % [project_root.replace("'", "\\'"), uuid.replace("'", "\\'"), char_id.replace("'", "\\'")]
		exit_code = OS.execute(python, PackedStringArray(["-c", code]), output, true)
	else:
		var code2 := "import os,runpy,sys; os.chdir(r'%s'); sys.argv=['pixellab_pipeline.py','import','--id','%s']; runpy.run_path('engine/tools/pixellab_pipeline.py', run_name='__main__')" % [project_root.replace("'", "\\'"), char_id.replace("'", "\\'")]
		exit_code = OS.execute(python, PackedStringArray(["-c", code2]), output, true)

	var step_log := ""
	if output.size() > 0:
		step_log = "\n" + "\n".join(output)

	var ok := exit_code == 0
	if ok:
		var copy_ok := _sync_pixellab_assets(char_id, project_root)
		if not copy_ok:
			ok = false
			step_log += "\nFalha ao copiar para visuals/assets."

	var mapping := {}
	if ok:
		mapping = _organize_pixellab_actions(char_id, project_root)

	call_deferred("_finish_mcp_import", char_id, ok, exit_code, step_log, mapping)


func _finish_mcp_import(char_id: String, ok: bool, exit_code: int, log_text: String, mapping: Dictionary) -> void:
	_mcp_import_button.disabled = false
	if _mcp_thread != null:
		_mcp_thread.wait_to_finish()
		_mcp_thread = null

	if not ok:
		_set_status("Falha no Import MCP (exit=%s).%s" % [str(exit_code), log_text])
		return

	_apply_or_create_character_data(char_id, mapping)
	_rescan_filesystem()
	_set_status("MCP importado e organizado para '%s'." % char_id)


func _sync_pixellab_assets(char_id: String, project_root: String) -> bool:
	var src := project_root.path_join("assets/characters/%s/pixellab" % char_id)
	var dst := project_root.path_join("visuals/assets/characters/%s/pixellab" % char_id)
	if not DirAccess.dir_exists_absolute(src):
		return false
	if DirAccess.dir_exists_absolute(dst):
		_remove_dir_recursive(dst)
	DirAccess.make_dir_recursive_absolute(dst)
	_copy_dir_recursive(src, dst)
	return true


func _organize_pixellab_actions(char_id: String, project_root: String) -> Dictionary:
	var base := project_root.path_join("visuals/assets/characters/%s/pixellab" % char_id)
	var anim_root := base.path_join("animations")
	if not DirAccess.dir_exists_absolute(anim_root):
		return {}

	var candidates := _list_subdirs(anim_root)
	var mapping: Dictionary = {}
	for action in DEFAULT_ACTIONS:
		if action == "idle":
			continue
		var best := _pick_best_animation_for_action(action, candidates)
		if best == "":
			continue
		var src_anim := anim_root.path_join(best)
		var dst_anim := anim_root.path_join(action)
		if not DirAccess.dir_exists_absolute(dst_anim):
			DirAccess.make_dir_recursive_absolute(dst_anim)
			_copy_animation_folder_normalized(src_anim, dst_anim)
		var action_config := _build_action_config_from_folder(dst_anim, char_id, action)
		if not action_config.is_empty():
			mapping[action] = action_config
	return mapping


func _apply_or_create_character_data(char_id: String, mapping: Dictionary) -> void:
	var data: CharacterData = _data
	var should_save_to := ""
	if data == null or str(data.id) != char_id:
		var target_res := "res://engine/data/characters/%s.tres" % char_id
		var existing := load(target_res)
		if existing is CharacterData:
			data = existing
			should_save_to = target_res
		else:
			data = CharacterData.new()
			data.id = char_id
			data.display_name = char_id
			should_save_to = target_res

	data.asset_base_path = "res://visuals/assets/characters/%s/pixellab/" % char_id
	for k in mapping.keys():
		data.action_animation_paths[str(k)] = mapping[k]

	if should_save_to != "":
		var err := ResourceSaver.save(data, should_save_to)
		if err == OK:
			_set_character_data(load(should_save_to))
		else:
			_set_status("Falha ao salvar CharacterData (%s): %s" % [str(err), should_save_to])
	else:
		_set_character_data(data)
		_mark_dirty()


func _pick_best_animation_for_action(action: String, candidates: Array[String]) -> String:
	var keywords := _keywords_for_action(action)
	var best := ""
	var best_score := -999
	for name in candidates:
		var score := 0
		var n := name.to_lower()
		for kw in keywords:
			if n.find(kw) != -1:
				score += 10
		if action == "dash" and n.find("run") != -1:
			score -= 2
		if action == "running" and n.find("walk") != -1:
			score -= 2
		if score > best_score:
			best_score = score
			best = name
	return best if best_score > 0 else ""


func _keywords_for_action(action: String) -> Array[String]:
	match action:
		"walk":
			return ["walk", "walking"]
		"running":
			return ["run", "running"]
		"dash":
			return ["dash"]
		"aim":
			return ["aim"]
		"shoot":
			return ["shoot", "throw", "arrow", "bow"]
		"melee":
			return ["punch", "kick", "jab", "slam", "melee"]
		"ult":
			return ["ult", "roundhouse", "super"]
		"jump_start", "jump_air":
			return ["jump", "jumping"]
		"hurt":
			return ["hurt", "hit", "damage", "taking"]
		"death":
			return ["death", "die", "fall"]
		"crouch":
			return ["crouch"]
		_:
			return [action]


func _build_action_config_from_folder(dst_anim_global: String, char_id: String, action: String) -> Dictionary:
	var base_res := "res://visuals/assets/characters/%s/pixellab/animations/%s/" % [char_id, action]
	var dirs := _list_subdirs(dst_anim_global)
	if dirs.is_empty():
		return {"shared": [base_res]}

	var out := {"__mode": "dirs", "shared": [base_res]}
	for d in dirs:
		var normalized := _normalize_dir_name(d)
		if normalized == "":
			continue
		out[normalized] = [base_res + normalized + "/"]
	return out


func _copy_animation_folder_normalized(src_anim: String, dst_anim: String) -> void:
	var dirs := _list_subdirs(src_anim)
	if dirs.is_empty():
		_copy_dir_recursive(src_anim, dst_anim)
		return
	for d in dirs:
		var normalized := _normalize_dir_name(d)
		if normalized == "":
			continue
		var src_dir := src_anim.path_join(d)
		var dst_dir := dst_anim.path_join(normalized)
		DirAccess.make_dir_recursive_absolute(dst_dir)
		_copy_dir_recursive(src_dir, dst_dir)


func _normalize_dir_name(name: String) -> String:
	var n := name.strip_edges().to_lower().replace("-", "_")
	match n:
		"east":
			return "right"
		"west":
			return "left"
		"north":
			return "up"
		"south":
			return "down"
		"north_east", "northeast":
			return "up_right"
		"north_west", "northwest":
			return "up_left"
		"south_east", "southeast":
			return "down_right"
		"south_west", "southwest":
			return "down_left"
		"right", "left", "up", "down", "up_right", "up_left", "down_right", "down_left":
			return n
		_:
			return ""


func _list_subdirs(abs_dir: String) -> Array[String]:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return []
	dir.list_dir_begin()
	var out: Array[String] = []
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			out.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _copy_dir_recursive(src: String, dst: String) -> void:
	var dir := DirAccess.open(src)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var src_path := src.path_join(entry)
		var dst_path := dst.path_join(entry)
		if dir.current_is_dir():
			DirAccess.make_dir_recursive_absolute(dst_path)
			_copy_dir_recursive(src_path, dst_path)
		else:
			_copy_file(src_path, dst_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _copy_file(src: String, dst: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.flush()


func _remove_dir_recursive(abs_dir: String) -> void:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var path := abs_dir.path_join(entry)
		if dir.current_is_dir():
			_remove_dir_recursive(path)
		else:
			DirAccess.remove_absolute(path)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_dir)
