extends RefCounted
class_name StatsComponent

var base: Dictionary = {}
var modifiers: Dictionary = {}
var dirty := true

func set_base(stat: String, value: float) -> void:
	base[stat] = value
	dirty = true

func set_bases(values: Dictionary) -> void:
	for key in values.keys():
		base[key] = values[key]
	dirty = true

func get_base(stat: String, default_value: float = 0.0) -> float:
	return float(base.get(stat, default_value))

func add_modifier(stat: String, modifier_id: String, flat: float = 0.0, mult: float = 1.0) -> void:
	if modifier_id == "":
		return
	if not modifiers.has(stat):
		modifiers[stat] = {}
	var stat_mods: Dictionary = modifiers[stat]
	stat_mods[modifier_id] = {
		"flat": flat,
		"mult": mult,
	}
	dirty = true

func remove_modifier(stat: String, modifier_id: String) -> void:
	if not modifiers.has(stat):
		return
	var stat_mods: Dictionary = modifiers[stat]
	stat_mods.erase(modifier_id)
	dirty = true

func clear_modifiers(stat: String = "") -> void:
	if stat == "":
		modifiers.clear()
		dirty = true
		return
	modifiers.erase(stat)
	dirty = true

func is_dirty() -> bool:
	return dirty

func clear_dirty() -> void:
	dirty = false

func get_state() -> Dictionary:
	return {
		"base": base.duplicate(true),
		"modifiers": modifiers.duplicate(true),
		"dirty": dirty
	}

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("base") and state["base"] is Dictionary:
		base = (state["base"] as Dictionary).duplicate(true)
	if state.has("modifiers") and state["modifiers"] is Dictionary:
		modifiers = (state["modifiers"] as Dictionary).duplicate(true)
	if state.has("dirty"):
		dirty = bool(state["dirty"])

func get_value(stat: String, default_value: float = 0.0) -> float:
	var base_value := float(base.get(stat, default_value))
	if not modifiers.has(stat):
		return base_value
	var stat_mods: Dictionary = modifiers[stat]
	var flat_total := 0.0
	var mult_total := 1.0
	for mod in stat_mods.values():
		flat_total += float(mod.get("flat", 0.0))
		mult_total *= float(mod.get("mult", 1.0))
	return (base_value + flat_total) * mult_total
