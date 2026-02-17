extends RefCounted

class_name CharacterRegistry



const CHARACTER_DIR := "res://engine/data/characters"



static var _cache: Dictionary = {}

static var _loaded := false



static func _load_all() -> void:

	if _loaded:

		return

	_cache.clear()

	var dir := DirAccess.open(CHARACTER_DIR)

	if dir == null:

		push_error("CharacterRegistry: não foi possível abrir %s" % CHARACTER_DIR)

		_loaded = true

		return

	dir.list_dir_begin()

	var file_name := dir.get_next()

	while file_name != "":

		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "tres":

			var path := "%s/%s" % [CHARACTER_DIR, file_name]

			var res := load(path)

			if res is CharacterData:
				var data: CharacterData = res as CharacterData
				var resolved_id := data.id

				if resolved_id == "":

					resolved_id = file_name.get_basename()

				_cache[resolved_id] = data

			else:

				push_warning("CharacterRegistry: recurso inválido em %s" % path)

		file_name = dir.get_next()

	dir.list_dir_end()

	_loaded = true



static func get_character(id: String) -> CharacterData:

	_load_all()

	if _cache.has(id):

		return _cache[id]

	var fallback_id := get_default_id()

	if fallback_id != "" and _cache.has(fallback_id):

		return _cache[fallback_id]

	return null



static func list_character_ids() -> Array[String]:

	_load_all()

	var ids: Array[String] = []

	for key in _cache.keys():

		ids.append(key)

	ids.sort()

	return ids



static func reload_cache() -> void:

	_cache.clear()

	_loaded = false



static func get_default_id() -> String:

	var ids := list_character_ids()

	if ids.is_empty():

		return ""

	return ids[0]



static func list_characters() -> Array[CharacterData]:

	var characters: Array[CharacterData] = []

	for id in list_character_ids():

		var data := get_character(id)

		if data == null:

			push_error("CharacterRegistry: recurso de personagem '%s' não pôde ser carregado" % id)

			continue

		characters.append(data)

	return characters

