extends RefCounted
class_name SkillRuntime

var skill: SkillBase = null
var slot := ""
var owner: Node = null

func _init(base_skill: Resource = null, slot_name: String = "", owner_node: Node = null) -> void:
	owner = owner_node
	slot = slot_name
	if base_skill == null:
		return
	if base_skill is SkillBase:
		skill = (base_skill as SkillBase).duplicate() as SkillBase
		return
	if base_skill is Script:
		var instance = (base_skill as Script).new()
		if instance is SkillBase:
			skill = instance

func is_valid() -> bool:
	return skill != null

func update(delta: float) -> void:
	if skill == null:
		return
	skill.update(owner, delta)

func reset() -> void:
	if skill == null:
		return
	skill.reset()

func try_activate() -> bool:
	if skill == null:
		_log_result("try_activate", false, "Skill ausente")
		return false
	var ok := skill.try_activate(owner)
	_log_result("try_activate", ok, "Skill %s" % slot)
	return ok

func activate() -> void:
	if skill == null:
		_log_result("activate", false, "Skill ausente")
		return
	skill.activate(owner)
	_log_result("activate", true, "Skill %s" % slot)

func get_state() -> Dictionary:
	if skill == null:
		return {}
	return skill.get_state()

func apply_state(state: Dictionary) -> void:
	if skill == null:
		return
	skill.apply_state(state)

func _log_result(action: String, success: bool, message: String) -> void:
	if not DevDebug:
		return
	DevDebug.log_result("skill_runtime_%s" % slot, success, message)
