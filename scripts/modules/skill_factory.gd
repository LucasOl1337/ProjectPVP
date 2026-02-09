extends RefCounted

const SKILL_BASE_PATH := "res://data/skills/"

var _cache: Dictionary = {}

static func get_skill_resource(skill_id: String) -> Resource:
	if skill_id == "":
		return null
	var path := get_skill_path(skill_id)
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		push_warning("SkillFactory: recurso não encontrado para '%s' (%s)" % [skill_id, path])
		return null
	var res := ResourceLoader.load(path)
	if res == null:
		push_warning("SkillFactory: falha ao carregar '%s'" % path)
		return null
	_cache[path] = res
	return res

static func get_skill_path(skill_id: String) -> String:
	if skill_id == "":
		return ""
	return "%s%s.tres" % [SKILL_BASE_PATH, skill_id]

static func list_available_skills() -> PackedStringArray:
	var dir := DirAccess.open(SKILL_BASE_PATH)
	if dir == null:
		push_warning("SkillFactory: diretório %s não acessível" % SKILL_BASE_PATH)
		return PackedStringArray()
	dir.list_dir_begin()
	var names: PackedStringArray = []
	while true:
		var file := dir.get_next()
		if file == "":
			break
		if dir.current_is_dir():
			continue
		if file.ends_with(".tres"):
			var id := file.replace(".tres", "")
			names.append(id)
	dir.list_dir_end()
	names.sort()
	return names
