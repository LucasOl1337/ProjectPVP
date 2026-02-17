extends Node

signal entries_changed(entries: Array)

var enabled := false
var max_entries := 20
var entries: Array = []

func configure(enabled_value: bool) -> void:
	enabled = enabled_value
	clear()

func is_enabled() -> bool:
	return enabled

func clear() -> void:
	entries.clear()
	emit_signal("entries_changed", entries.duplicate())

func log_input(player_id: int, action: String, detail: String = "") -> void:
	if not enabled:
		return
	var message := "P%d %s" % [player_id, action]
	if detail != "":
		message += " (%s)" % detail
	_add_entry("INPUT", message)

func log_event(category: String, message: String) -> void:
	if not enabled:
		return
	_add_entry(category, message)

func log_result(action: String, success: bool, message: String = "") -> void:
	if not enabled:
		return
	var status := "OK" if success else "FAIL"
	var full := "%s -> %s" % [action, status]
	if message != "":
		full += ": %s" % message
	_add_entry("RESULT", full)

func get_entries() -> Array:
	return entries.duplicate()

func _add_entry(kind: String, message: String) -> void:
	var entry := {
		"type": kind,
		"text": message,
		"time": Time.get_ticks_msec()
	}
	entries.append(entry)
	if entries.size() > max_entries:
		entries.pop_front()
	emit_signal("entries_changed", entries.duplicate())
