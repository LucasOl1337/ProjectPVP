extends RefCounted
class_name TrainingRecorder

var file: FileAccess = null
var path := ""

func start(output_path: String) -> bool:
	stop()
	path = output_path
	if path == "":
		return false
	var f := FileAccess.open(path, FileAccess.WRITE_READ)
	if f == null:
		return false
	file = f
	file.seek_end()
	return true

func stop() -> void:
	if file != null:
		file.flush()
		file.close()
	file = null
	path = ""

func record_line(payload: Dictionary) -> void:
	if file == null:
		return
	file.store_line(JSON.stringify(payload))
