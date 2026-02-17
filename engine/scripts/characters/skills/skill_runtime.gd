extends RefCounted
class_name SkillRuntime

var skill: Resource = null
var slot := ""
var owner: Node = null

func _init(base_skill: Resource = null, slot_name: String = "", owner_node: Node = null) -> void:
	owner = owner_node
	slot = slot_name
	if base_skill == null:
		return
	skill = base_skill.duplicate()

func is_valid() -> bool:
	return skill != null

func update(delta: float) -> void:
	if skill == null:
		return
	if skill.has_method("update"):
		skill.call("update", owner, delta)

func reset() -> void:
	if skill == null:
		return
	if skill.has_method("reset"):
		skill.call("reset")

func try_activate() -> bool:
	if skill == null:
		_log_result("try_activate", false, "Skill ausente")
		return false
	if not skill.has_method("try_activate"):
		_log_result("try_activate", false, "Skill sem try_activate")
		return false
	var ok: bool = bool(skill.call("try_activate", owner))
	_log_result("try_activate", ok, "Skill %s" % slot)
	return ok

func activate() -> void:
	if skill == null:
		_log_result("activate", false, "Skill ausente")
		return
	if skill.has_method("activate"):
		skill.call("activate", owner)
	_log_result("activate", true, "Skill %s" % slot)

func get_state() -> Dictionary:
	if skill == null:
		return {}
	if not skill.has_method("get_state"):
		return {}
	var state: Variant = skill.call("get_state")
	return state if state is Dictionary else {}

func apply_state(state: Dictionary) -> void:
	if skill == null:
		return
	if skill.has_method("apply_state"):
		skill.call("apply_state", state)

func _log_result(action: String, success: bool, message: String) -> void:
	if not DevDebug:
		return
	DevDebug.log_result("skill_runtime_%s" % slot, success, message)
