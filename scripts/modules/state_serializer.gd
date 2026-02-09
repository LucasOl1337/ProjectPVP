extends RefCounted
class_name StateSerializer


static func to_canonical(value: Variant) -> Variant:
	if value == null:
		return null
	if value is bool:
		return bool(value)
	if value is int:
		return int(value)
	if value is float:
		var f := float(value)
		if is_nan(f) or is_inf(f):
			return 0.0
		return f
	if value is String:
		return String(value)
	if value is Vector2:
		var v2 := value as Vector2
		return [float(v2.x), float(v2.y)]
	if value is Vector3:
		var v3 := value as Vector3
		return [float(v3.x), float(v3.y), float(v3.z)]
	if value is Color:
		var c := value as Color
		return [float(c.r), float(c.g), float(c.b), float(c.a)]
	if value is Rect2:
		var r := value as Rect2
		return {
			"position": to_canonical(r.position),
			"size": to_canonical(r.size)
		}
	if value is PackedByteArray:
		return (value as PackedByteArray).hex_encode()
	if value is PackedStringArray:
		return Array(value)
	if value is PackedInt32Array:
		return Array(value)
	if value is PackedInt64Array:
		return Array(value)
	if value is PackedFloat32Array:
		return Array(value)
	if value is PackedFloat64Array:
		return Array(value)
	if value is Array:
		var arr_in := value as Array
		var arr_out: Array = []
		arr_out.resize(arr_in.size())
		for i in range(arr_in.size()):
			arr_out[i] = to_canonical(arr_in[i])
		return arr_out
	if value is Dictionary:
		var dict_in := value as Dictionary
		var keys := dict_in.keys()
		keys.sort_custom(func(a, b):
			return String(a) < String(b)
		)
		var out: Dictionary = {}
		for k in keys:
			out[String(k)] = to_canonical(dict_in[k])
		return out
	return String(value)


static func to_canonical_json(value: Variant) -> String:
	return JSON.stringify(to_canonical(value))


static func hash_state(value: Variant) -> String:
	var text := to_canonical_json(value)
	return text.to_utf8_buffer().sha256_text()

