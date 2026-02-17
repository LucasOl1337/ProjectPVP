extends RefCounted

class_name PlayerCombat



const SkillController = preload("res://engine/scripts/characters/skills/skill_controller.gd")

const PlayerMelee = preload("res://engine/scripts/modules/player_melee.gd")



var owner: Node = null

var skill_controller := SkillController.new()

var melee := PlayerMelee.new()



func configure(owner_node: Node, character_data, melee_cooldown: float, melee_duration: float) -> void:

	owner = owner_node

	skill_controller.configure(character_data, owner_node)

	melee.configure(melee_cooldown, melee_duration)



func configure_melee(cooldown_value: float, duration_value: float) -> void:

	melee.configure(cooldown_value, duration_value)



func update(delta: float) -> void:

	skill_controller.update_all(delta)



func reset() -> void:

	skill_controller.reset_all()

	melee.cooldown_timer = 0.0

	melee.active_timer = 0.0



func get_state() -> Dictionary:

	return {

		"skills": skill_controller.get_state(),

		"melee": melee.get_state()

	}



func apply_state(state: Dictionary) -> void:

	if state.is_empty():

		return

	if state.has("skills") and state["skills"] is Dictionary:

		skill_controller.apply_state(state["skills"])

	if state.has("melee") and state["melee"] is Dictionary:

		melee.apply_state(state["melee"])



func is_melee_active() -> bool:

	return melee.is_active()



func get_melee_duration() -> float:

	return melee.duration



func _dev_log_result(action: String, success: bool, message: String) -> void:

	if not DevDebug:

		return

	DevDebug.log_result(action, success, message)



func handle_melee(delta: float, pressed: bool) -> Dictionary:

	var result := {

		"uses_skill": false,

		"start": false,

		"stop": false

	}

	if skill_controller.has_skill("melee"):

		result.uses_skill = true

		if pressed and skill_controller.try_activate("melee"):

			skill_controller.activate("melee")

			result.start = true

		return result

	melee.update(delta)

	if not melee.is_active():

		result.stop = true

	if pressed and melee.try_attack():

		result.start = true

	return result



func handle_ult(pressed: bool) -> bool:

	if not skill_controller.has_skill("ult"):

		if pressed:

			_dev_log_result("ult", false, "Slot ult não configurado")

		return false

	if pressed and skill_controller.try_activate("ult"):

		skill_controller.activate("ult")

		_dev_log_result("ult", true, "Skill ativada")

		return true

	if pressed:

		_dev_log_result("ult", false, "try_activate falhou")

	return false



func process_melee_hit(node: Node) -> void:

	if not melee.is_active():

		return

	var target := _resolve_hit_target(node)

	if target == null or target == owner:

		return

	if target.has_method("die"):

		target.die()



func _resolve_hit_target(node: Node) -> Node:

	if node == null:

		return null

	if node is Area2D:

		var parent := node.get_parent()

		if parent != null:

			return parent

	return node

