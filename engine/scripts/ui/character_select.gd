extends Control



const BOT_PROFILE_DIR := "res://BOTS/profiles"


@onready var p1_option: OptionButton = $Content/Layout/PlayersRow/Player1Card/Player1VBox/Player1Option

@onready var p2_option: OptionButton = $Content/Layout/PlayersRow/Player2Card/Player2VBox/Player2Option

@onready var start_button: Button = $Content/Layout/ActionBar/StartButton

@onready var back_button: Button = $Content/Layout/ActionBar/BackButton

@onready var subtitle_label: Label = $Content/Layout/HeaderRow/TitleBlock/SubtitleLabel

@onready var toolbar_hitbox_toggle: CheckButton = $Content/Layout/HeaderRow/OptionsCard/OptionsVBox/HitboxToggle

@onready var toolbar_dev_toggle: CheckButton = $Content/Layout/HeaderRow/OptionsCard/OptionsVBox/DevToggle

@onready var p1_bot_toggle: CheckButton = $Content/Layout/PlayersRow/Player1Card/Player1VBox/Player1BotToggle

@onready var p2_bot_toggle: CheckButton = $Content/Layout/PlayersRow/Player2Card/Player2VBox/Player2BotToggle

@onready var p1_bot_policy: OptionButton = $Content/Layout/PlayersRow/Player1Card/Player1VBox/Player1BotPolicy

@onready var p2_bot_policy: OptionButton = $Content/Layout/PlayersRow/Player2Card/Player2VBox/Player2BotPolicy



func _ready() -> void:

	if not CharacterSelectionState:

		push_error("CharacterSelectionState autoload não encontrado")

	if start_button:

		start_button.pressed.connect(_on_start_button_pressed)

	else:

		push_error("StartButton não encontrado em CharacterSelect")

	if back_button:

		back_button.pressed.connect(_on_back_button_pressed)

	else:

		push_warning("BackButton não encontrado em CharacterSelect")

	if subtitle_label:

		_update_subtitle_text()

	else:

		push_error("SubtitleLabel não encontrado em CharacterSelect")

	_populate_options()

	_configure_hitbox_toggle()

	_configure_dev_toggle()

	_configure_bot_options()



func _populate_options() -> void:

	if not p1_option or not p2_option:

		push_error("OptionButtons não encontrados em CharacterSelect")

		return

	var characters := CharacterRegistry.list_characters()

	print("CharacterSelect: carregando %s personagens" % characters.size())

	p1_option.clear()

	p2_option.clear()

	if characters.is_empty():

		var ids := CharacterRegistry.list_character_ids()

		for character_id in ids:

			var data := CharacterRegistry.get_character(character_id)

			var label := character_id.capitalize()

			if data and data.display_name != "":

				label = data.display_name

			var idx1 := p1_option.get_item_count()

			p1_option.add_item(label)

			p1_option.set_item_metadata(idx1, character_id)

			var idx2 := p2_option.get_item_count()

			p2_option.add_item(label)

			p2_option.set_item_metadata(idx2, character_id)

	else:

		for character_data in characters:

			var label := character_data.display_name

			if label == "":

				label = character_data.id.capitalize()

			var idx1 := p1_option.get_item_count()

			p1_option.add_item(label)

			p1_option.set_item_metadata(idx1, character_data.id)

			var idx2 := p2_option.get_item_count()

			p2_option.add_item(label)

			p2_option.set_item_metadata(idx2, character_data.id)

	if CharacterSelectionState:

		_select_defaults()



func _select_defaults() -> void:

	if not CharacterSelectionState:

		return

	var p1_default := CharacterSelectionState.get_character(1)

	var p2_default := CharacterSelectionState.get_character(2)

	_select_option_by_id(p1_option, p1_default)

	_select_option_by_id(p2_option, p2_default)



func _select_option_by_id(option_button: OptionButton, character_id: String) -> void:

	for i in range(option_button.get_item_count()):

		if option_button.get_item_metadata(i) == character_id:

			option_button.select(i)

			return

	if option_button.get_item_count() > 0:

		option_button.select(0)



func _on_start_button_pressed() -> void:

	print("CharacterSelect: botão Iniciar clicado")

	if not p1_option or not p2_option:

		push_error("OptionButtons não disponíveis ao iniciar partida")

		return

	var p1_id := _selected_id(p1_option)

	var p2_id := _selected_id(p2_option)

	print("CharacterSelect: P1=%s, P2=%s" % [p1_id, p2_id])

	if CharacterSelectionState:

		CharacterSelectionState.set_character(1, p1_id)

		CharacterSelectionState.set_character(2, p2_id)

		var p1_bot := p1_bot_toggle.button_pressed if p1_bot_toggle else false

		var p2_bot := p2_bot_toggle.button_pressed if p2_bot_toggle else false

		CharacterSelectionState.set_bot_enabled(1, p1_bot)

		CharacterSelectionState.set_bot_enabled(2, p2_bot)

		CharacterSelectionState.set_bot_profile(1, _selected_profile(p1_bot_policy))

		CharacterSelectionState.set_bot_profile(2, _selected_profile(p2_bot_policy))

	else:

		push_error("CharacterSelectionState não disponível; usando fallback padrão")

	var err := get_tree().change_scene_to_file("res://engine/scenes/Main.tscn")

	if err != OK:

		push_error("Falha ao carregar Main.tscn: %s" % err)

	else:

		print("CharacterSelect: carregando Main.tscn")



func _on_back_button_pressed() -> void:

	var err := get_tree().change_scene_to_file("res://engine/scenes/MainMenu.tscn")

	if err != OK:

		push_error("Falha ao voltar para MainMenu.tscn: %s" % err)



func _selected_id(option_button: OptionButton) -> String:

	if option_button == null:

		return _fallback_character_id()

	var selected_index := option_button.get_selected()

	if selected_index < 0 and option_button.get_item_count() > 0:

		selected_index = 0

	elif option_button.get_item_count() == 0:

		return _fallback_character_id()

	var metadata = option_button.get_item_metadata(selected_index)

	if metadata == null:

		return _fallback_character_id(selected_index)

	return metadata



func _fallback_character_id(preferred_index: int = 0) -> String:

	var ids := CharacterRegistry.list_character_ids()

	if ids.is_empty():

		return "storm_dragon"

	var clamped_index: int = clampi(preferred_index, 0, ids.size() - 1)

	return ids[clamped_index]



func _configure_hitbox_toggle() -> void:

	if toolbar_hitbox_toggle == null:

		push_warning("Toolbar/HitboxToggle não encontrado em CharacterSelect")

		return

	var enabled := true

	if CharacterSelectionState:

		enabled = CharacterSelectionState.get_debug_hitboxes_enabled()

	else:

		push_warning("CharacterSelectionState indisponível; usando hitboxes visíveis por padrão")

	toolbar_hitbox_toggle.button_pressed = enabled

	toolbar_hitbox_toggle.toggled.connect(_on_hitbox_toggle_toggled)



func _on_hitbox_toggle_toggled(pressed: bool) -> void:

	if CharacterSelectionState:

		CharacterSelectionState.set_debug_hitboxes_enabled(pressed)

		_update_subtitle_text()

	else:

		push_warning("CharacterSelectionState não disponível para salvar preferência de hitbox")



func _configure_dev_toggle() -> void:

	if toolbar_dev_toggle == null:

		push_warning("Toolbar/DevToggle não encontrado em CharacterSelect")

		return

	var enabled := false

	if CharacterSelectionState:

		enabled = CharacterSelectionState.is_dev_mode_enabled()

	else:

		push_warning("CharacterSelectionState indisponível; modo dev desligado por padrão")

	toolbar_dev_toggle.button_pressed = enabled

	toolbar_dev_toggle.toggled.connect(_on_dev_toggle_toggled)



func _on_dev_toggle_toggled(pressed: bool) -> void:

	if CharacterSelectionState:

		CharacterSelectionState.set_dev_mode_enabled(pressed)

		_update_subtitle_text()

	else:

		push_warning("CharacterSelectionState não disponível para salvar modo dev")



func _configure_bot_options() -> void:

	_populate_bot_profile_options(p1_bot_policy)

	_populate_bot_profile_options(p2_bot_policy)

	var p1_enabled := false

	var p2_enabled := false

	var p1_profile := "default"

	var p2_profile := "default"

	if CharacterSelectionState:

		p1_enabled = CharacterSelectionState.is_bot_enabled(1)

		p2_enabled = CharacterSelectionState.is_bot_enabled(2)

		p1_profile = CharacterSelectionState.get_bot_profile(1)

		p2_profile = CharacterSelectionState.get_bot_profile(2)

	if p1_bot_toggle:

		p1_bot_toggle.button_pressed = p1_enabled

		if not p1_bot_toggle.toggled.is_connected(_on_p1_bot_toggled):

			p1_bot_toggle.toggled.connect(_on_p1_bot_toggled)

	if p2_bot_toggle:

		p2_bot_toggle.button_pressed = p2_enabled

		if not p2_bot_toggle.toggled.is_connected(_on_p2_bot_toggled):

			p2_bot_toggle.toggled.connect(_on_p2_bot_toggled)

	if p1_bot_policy:

		_select_option_by_id(p1_bot_policy, p1_profile)

		p1_bot_policy.disabled = not p1_enabled

		if not p1_bot_policy.item_selected.is_connected(_on_p1_bot_policy_selected):

			p1_bot_policy.item_selected.connect(_on_p1_bot_policy_selected)

	if p2_bot_policy:

		_select_option_by_id(p2_bot_policy, p2_profile)

		p2_bot_policy.disabled = not p2_enabled

		if not p2_bot_policy.item_selected.is_connected(_on_p2_bot_policy_selected):

			p2_bot_policy.item_selected.connect(_on_p2_bot_policy_selected)





func _populate_bot_profile_options(option_button: OptionButton) -> void:

	if option_button == null:

		return

	option_button.clear()

	for profile_dict in _list_bot_profiles():

		var idx: int = option_button.get_item_count()

		var label: String = String(profile_dict.get("label", ""))

		var profile_id: String = String(profile_dict.get("id", "default"))

		option_button.add_item(label)

		option_button.set_item_metadata(idx, profile_id)



func _list_bot_profiles() -> Array[Dictionary]:

	var default_policy := _detect_bot_policy("default")
	var default_suffix := _read_promoted_suffix("default") if default_policy == "ga_params" else ""
	var default_label := ("IA Treinada (Default)%s" % default_suffix) if default_policy == "ga_params" else "IA Handmade (Default)"
	var result: Array[Dictionary] = [{"id": "default", "label": default_label}]

	var dir := DirAccess.open(BOT_PROFILE_DIR)

	if dir == null:

		return result

	dir.list_dir_begin()

	var entry := dir.get_next()

	while entry != "":

		if dir.current_is_dir() and not entry.begins_with("."):

			var profile_id := entry

			var cfg_path := "%s/%s/handmade.json" % [BOT_PROFILE_DIR, entry]
			var genome_path := "%s/%s/best_genome.json" % [BOT_PROFILE_DIR, entry]

			var has_handmade := FileAccess.file_exists(cfg_path)
			var has_genome := FileAccess.file_exists(genome_path)
			if has_handmade or has_genome:

				if profile_id != "default":
					var policy := _detect_bot_policy(profile_id)
					var suffix := _read_promoted_suffix(profile_id) if policy == "ga_params" else ""
					var label := (("IA Treinada %s%s" if policy == "ga_params" else "IA Handmade %s") % [profile_id.capitalize(), suffix]) if policy == "ga_params" else ("IA Handmade %s" % profile_id.capitalize())
					result.append({"id": profile_id, "label": label})

		entry = dir.get_next()

	dir.list_dir_end()

	var sorted_tail: Array[Dictionary] = []
	for i in range(1, result.size()):
		sorted_tail.append(result[i])
	sorted_tail.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:

		return String(a.get("id", "")) < String(b.get("id", ""))

	)
	var out: Array[Dictionary] = []
	out.append(result[0])
	out.append_array(sorted_tail)
	return out



func _on_p1_bot_toggled(pressed: bool) -> void:

	if CharacterSelectionState:

		CharacterSelectionState.set_bot_enabled(1, pressed)

		var profile_id := _selected_profile(p1_bot_policy)
		CharacterSelectionState.set_bot_policy(1, _detect_bot_policy(profile_id) if pressed else "simple")

	if p1_bot_policy:

		p1_bot_policy.disabled = not pressed



func _on_p2_bot_toggled(pressed: bool) -> void:

	if CharacterSelectionState:

		CharacterSelectionState.set_bot_enabled(2, pressed)

		var profile_id := _selected_profile(p2_bot_policy)
		CharacterSelectionState.set_bot_policy(2, _detect_bot_policy(profile_id) if pressed else "simple")

	if p2_bot_policy:

		p2_bot_policy.disabled = not pressed



func _on_p1_bot_policy_selected(index: int) -> void:

	_save_bot_profile(1, p1_bot_policy, index)



func _on_p2_bot_policy_selected(index: int) -> void:

	_save_bot_profile(2, p2_bot_policy, index)



func _save_bot_profile(player_id: int, option_button: OptionButton, index: int) -> void:

	if option_button == null:

		return

	var metadata: Variant = option_button.get_item_metadata(index)

	var profile_id: String = "default"

	if metadata != null:

		profile_id = String(metadata)

	if CharacterSelectionState:

		CharacterSelectionState.set_bot_policy(player_id, _detect_bot_policy(profile_id))

		CharacterSelectionState.set_bot_profile(player_id, profile_id)



func _selected_profile(option_button: OptionButton) -> String:

	if option_button == null:

		return "default"

	var selected_index := option_button.get_selected()

	if selected_index < 0 and option_button.get_item_count() > 0:

		selected_index = 0

	if selected_index < 0:

		return "default"

	var metadata: Variant = option_button.get_item_metadata(selected_index)

	if metadata == null:

		return "default"

	return String(metadata)


func _detect_bot_policy(profile_id: String) -> String:
	var base := "%s/%s" % [BOT_PROFILE_DIR, profile_id]
	var genome_path := "%s/best_genome.json" % base
	if FileAccess.file_exists(genome_path):
		var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(genome_path))
		if payload is Dictionary and String((payload as Dictionary).get("schema_id", "")) == "ga_params_v1":
			return "ga_params"
	return "handmade"


func _read_promoted_suffix(profile_id: String) -> String:
	var meta_path := "%s/%s/current_bot.json" % [BOT_PROFILE_DIR, profile_id]
	if not FileAccess.file_exists(meta_path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not (parsed is Dictionary):
		return ""
	var meta := parsed as Dictionary
	if meta.has("individual"):
		var g := int(meta.get("generation_global", meta.get("islands_round", meta.get("round", 0))))
		var n := int(meta.get("individual", 0))
		if n > 0:
			return " (G%d_N%d)" % [g, n] if g > 0 else " (N%d)" % n
	return ""



func _update_subtitle_text() -> void:

	if subtitle_label == null:

		return

	var hints: Array[String] = []

	var hitbox_hint := "Hitboxes visíveis"

	if CharacterSelectionState:

		if not CharacterSelectionState.get_debug_hitboxes_enabled():

			hitbox_hint = "Hitboxes escondidas"

		if CharacterSelectionState.is_dev_mode_enabled():

			hints.append("Modo Dev ON")

		else:

			hints.append("Modo Dev OFF")

	else:

		hints.append("Modo Dev OFF")

	hints.append(hitbox_hint)

	subtitle_label.text = "Escolha o personagem para cada jogador (%s)" % ", ".join(hints)
