extends Control

@onready var normal_button := get_node_or_null("Content/Layout/HeroCard/Hero/CTAWrapper/NormalButton")
@onready var dev_button := get_node_or_null("Content/Layout/HeroCard/Hero/CTAWrapper/DevButton")
@onready var subtitle_label := get_node_or_null("Content/Layout/HeroCard/Hero/SubtitleLabel")
@onready var hitbox_toggle := get_node_or_null("Content/Layout/SideCard/SideVBox/HitboxToggle")
@onready var dev_toggle := get_node_or_null("Content/Layout/SideCard/SideVBox/DevToggle")

func _ready() -> void:
	if normal_button:
		normal_button.pressed.connect(_on_normal_button_pressed)
	else:
		push_error("NormalButton não encontrado em MainMenu")
	if dev_button:
		dev_button.pressed.connect(_on_dev_button_pressed)
	else:
		push_error("DevButton não encontrado em MainMenu")
	if subtitle_label:
		subtitle_label.text = "Arena PvP precisa • Local e Online P2P"
	else:
		push_error("SubtitleLabel não encontrado em MainMenu")
	_configure_hitbox_toggle()
	_configure_dev_toggle()

func _on_normal_button_pressed() -> void:
	if CharacterSelectionState:
		CharacterSelectionState.set_training_enabled(false)
		CharacterSelectionState.set_dev_mode_enabled(false)
	_go_to_character_select()

func _on_dev_button_pressed() -> void:
	if CharacterSelectionState:
		CharacterSelectionState.set_training_enabled(false)
		CharacterSelectionState.set_training_watch_mode(false)
		CharacterSelectionState.set_training_time_scale(1.0)
		CharacterSelectionState.set_dev_mode_enabled(true)
		CharacterSelectionState.set_bot_enabled(1, true)
		CharacterSelectionState.set_bot_enabled(2, true)
		CharacterSelectionState.set_bot_policy(1, "genetic")
		CharacterSelectionState.set_bot_policy(2, "genetic")
		CharacterSelectionState.set_bot_profile(1, "default")
		CharacterSelectionState.set_bot_profile(2, "default")
	_go_to_main()

func _go_to_character_select() -> void:
	var packed := load("res://scenes/CharacterSelect.tscn")
	if packed == null:
		push_error("Falha ao carregar CharacterSelect.tscn (load retornou null)")
		return
	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		push_error("Falha ao trocar para CharacterSelect.tscn: %s" % err)

func _go_to_main() -> void:
	var packed := load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Falha ao carregar Main.tscn (load retornou null)")
		return
	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		push_error("Falha ao trocar para Main.tscn: %s" % err)

func _configure_hitbox_toggle() -> void:
	if hitbox_toggle == null:
		push_warning("HitboxToggle não encontrado em MainMenu")
		return
	var enabled := true
	if CharacterSelectionState:
		enabled = CharacterSelectionState.get_debug_hitboxes_enabled()
	else:
		push_warning("CharacterSelectionState indisponível; usando hitboxes visíveis por padrão")
	hitbox_toggle.button_pressed = enabled
	hitbox_toggle.toggled.connect(_on_hitbox_toggle_toggled)

func _on_hitbox_toggle_toggled(pressed: bool) -> void:
	if CharacterSelectionState:
		CharacterSelectionState.set_debug_hitboxes_enabled(pressed)
	else:
		push_warning("CharacterSelectionState não disponível para salvar preferência de hitbox")

func _configure_dev_toggle() -> void:
	if dev_toggle == null:
		push_warning("DevToggle não encontrado em MainMenu")
		return
	var enabled := false
	if CharacterSelectionState:
		enabled = CharacterSelectionState.is_dev_mode_enabled()
	else:
		push_warning("CharacterSelectionState indisponível; modo dev desligado por padrão")
	dev_toggle.button_pressed = enabled
	dev_toggle.toggled.connect(_on_dev_toggle_toggled)

func _on_dev_toggle_toggled(pressed: bool) -> void:
	if CharacterSelectionState:
		CharacterSelectionState.set_dev_mode_enabled(pressed)
	else:
		push_warning("CharacterSelectionState não disponível para salvar modo dev")
