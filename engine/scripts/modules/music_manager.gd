extends Node

var _player: AudioStreamPlayer
var _loop_enabled := true
var _current_path := ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BgmPlayer"
	add_child(_player)
	_player.finished.connect(_on_finished)


func play_bgm(path: String, volume_db: float = 0.0, loop: bool = true) -> void:
	_loop_enabled = loop
	_player.volume_db = volume_db
	var p := path.strip_edges()
	if p == "":
		stop()
		return
	if p == _current_path and _player.playing:
		return
	if not ResourceLoader.exists(p):
		stop()
		return
	var stream: Variant = load(p)
	if not (stream is AudioStream):
		stop()
		return
	_current_path = p
	_player.stream = stream
	if stream.has_property("loop"):
		stream.set("loop", loop)
	_player.play()


func stop() -> void:
	_current_path = ""
	if _player:
		_player.stop()
		_player.stream = null


func _on_finished() -> void:
	if _loop_enabled and _player != null and _player.stream != null:
		_player.play()
