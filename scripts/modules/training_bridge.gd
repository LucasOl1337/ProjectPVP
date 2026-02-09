extends RefCounted
class_name TrainingBridge

const DEFAULT_PORT := 9009

var server: TCPServer = TCPServer.new()
var peer: StreamPeerTCP = null
var port := DEFAULT_PORT
var is_listening := false
var buffer := ""
var messages: Array[Dictionary] = []
var last_error := OK
var pending_hello := false
var accept_count := 0
var last_peer_status := -1

func start(listen_port: int = DEFAULT_PORT) -> void:
	stop()
	port = listen_port
	var err: int = server.listen(port, "127.0.0.1")
	last_error = err
	is_listening = server.is_listening()
	if err != OK or not is_listening:
		push_error("[TrainingBridge] Falha ao escutar porta %d (err=%d listening=%s)" % [port, err, str(is_listening)])
	buffer = ""
	messages.clear()

func stop() -> void:
	if server.is_listening():
		server.stop()
	peer = null
	is_listening = false
	buffer = ""
	messages.clear()

func poll() -> void:
	if not is_listening:
		return
	while true:
		var candidate = server.take_connection()
		if not candidate:
			break
		peer = candidate
		peer.set_no_delay(true)
		pending_hello = true
		accept_count += 1
		buffer = ""
		messages.clear()
	if peer == null:
		return
	peer.poll()
	var status := peer.get_status()
	last_peer_status = status
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		peer = null
		buffer = ""
		pending_hello = false
		return
	if pending_hello:
		send({"type": "hello", "protocol": 1})
		pending_hello = false
	var available: int = peer.get_available_bytes()
	if available <= 0:
		return
	var res: Array = peer.get_data(available)
	if res.size() >= 2 and int(res[0]) == OK:
		var bytes: PackedByteArray = res[1]
		buffer += bytes.get_string_from_utf8()
	while true:
		var newline_index: int = buffer.find("\n")
		if newline_index == -1:
			break
		var line: String = buffer.substr(0, newline_index).strip_edges()
		buffer = buffer.substr(newline_index + 1)
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			messages.append(parsed)

func is_bridge_connected() -> bool:
	if peer == null:
		return false
	peer.poll()
	var status := peer.get_status()
	last_peer_status = status
	return status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING

func get_debug_state() -> Dictionary:
	return {
		"accept_count": accept_count,
		"peer_status": last_peer_status,
		"pending_hello": pending_hello
	}

func pop_messages() -> Array[Dictionary]:
	var output: Array[Dictionary] = messages.duplicate()
	messages.clear()
	return output

func send(payload: Dictionary) -> void:
	if peer == null:
		return
	peer.poll()
	var status := peer.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		return
	var safe_payload: Variant = _to_json_safe(payload)
	var text: String = JSON.stringify(safe_payload)
	var bytes := (text + "\n").to_utf8_buffer()
	peer.put_data(bytes)


func _to_json_safe(value: Variant) -> Variant:
	if value == null:
		return null
	if value is bool or value is int or value is float or value is String:
		return value
	if value is Vector2:
		var v := value as Vector2
		return {"x": float(v.x), "y": float(v.y)}
	if value is Vector3:
		var v3 := value as Vector3
		return {"x": float(v3.x), "y": float(v3.y), "z": float(v3.z)}
	if value is Array:
		var arr_in := value as Array
		var arr_out: Array = []
		arr_out.resize(arr_in.size())
		for i in range(arr_in.size()):
			arr_out[i] = _to_json_safe(arr_in[i])
		return arr_out
	if value is Dictionary:
		var dict_in := value as Dictionary
		var dict_out: Dictionary = {}
		for k in dict_in.keys():
			dict_out[k] = _to_json_safe(dict_in[k])
		return dict_out
	return str(value)
