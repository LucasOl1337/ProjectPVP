extends RefCounted
class_name SkillController

const SkillRuntime = preload("res://scripts/characters/skills/skill_runtime.gd")

var runtimes: Dictionary = {}

func configure(character_data: CharacterData, owner: Node) -> void:
	runtimes.clear()
	if character_data == null:
		_dev_log_event("skills", "Character data ausente")
		return
	var slot_names: Array[String] = character_data.skill_slots
	var skills: Array[SkillBase] = character_data.skills
	if slot_names.size() == skills.size() and slot_names.size() > 0:
		for i in range(slot_names.size()):
			var slot := slot_names[i]
			var skill := skills[i]
			if slot == "" or skill == null:
				continue
			runtimes[slot] = SkillRuntime.new(skill, slot, owner)
			_dev_log_event("skills", "Slot %s configurado" % slot)
	if character_data.melee_skill != null and not runtimes.has("melee"):
		runtimes["melee"] = SkillRuntime.new(character_data.melee_skill, "melee", owner)
		_dev_log_event("skills", "Slot melee configurado")
	if character_data.ult_skill != null and not runtimes.has("ult"):
		runtimes["ult"] = SkillRuntime.new(character_data.ult_skill, "ult", owner)
		_dev_log_event("skills", "Slot ult configurado")

func update_all(delta: float) -> void:
	for runtime in runtimes.values():
		runtime.update(delta)

func has_skill(slot: String) -> bool:
	return runtimes.has(slot)

func try_activate(slot: String) -> bool:
	var runtime: SkillRuntime = runtimes.get(slot)
	if runtime == null:
		_dev_log_event("skills", "Slot %s sem runtime" % slot)
		return false
	return runtime.try_activate()

func activate(slot: String) -> void:
	var runtime: SkillRuntime = runtimes.get(slot)
	if runtime == null:
		_dev_log_event("skills", "Slot %s sem runtime para activate" % slot)
		return
	runtime.activate()

func reset_all() -> void:
	for runtime in runtimes.values():
		runtime.reset()

func get_state() -> Dictionary:
	var state := {}
	for slot in runtimes.keys():
		var runtime: SkillRuntime = runtimes.get(slot)
		if runtime != null:
			state[slot] = runtime.get_state()
	return state

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	for slot in state.keys():
		var runtime: SkillRuntime = runtimes.get(slot)
		if runtime == null:
			continue
		var runtime_state: Variant = state.get(slot)
		if runtime_state is Dictionary:
			runtime.apply_state(runtime_state)

func _dev_log_event(category: String, message: String) -> void:
	if not DevDebug:
		return
	DevDebug.log_event(category, message)
