class_name LevelCatalog
extends RefCounted
## Read-only level definitions. Invalid content fails visibly instead of
## quietly falling back to a different campaign.

const PATH := "res://data/levels/chapter_one.json"

var levels: Array[Dictionary] = []


func load_levels(path: String = PATH) -> bool:
	levels.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version") != 1:
		return false
	var entries: Variant = data.get("levels")
	if not entries is Array or entries.is_empty():
		return false
	for entry in entries:
		if not _valid_entry(entry, levels.size() + 1):
			levels.clear()
			return false
		levels.append(entry.duplicate(true))
	return true


func get_level(id: int) -> Dictionary:
	if id < 1 or id > levels.size():
		return {}
	return levels[id - 1].duplicate(true)


static func whole_number(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value >= low and value <= high and value == floor(value)


func _valid_entry(entry: Variant, expected_id: int) -> bool:
	if not entry is Dictionary:
		return false
	return whole_number(entry.get("id"), expected_id, expected_id) \
		and whole_number(entry.get("moves"), 1, 100) \
		and whole_number(entry.get("clear_goal"), 1, int(entry.get("moves", 0))) \
		and whole_number(entry.get("seed"), 0, 2147483647) \
		and entry.get("title") is String and not entry["title"].is_empty() \
		and entry.get("hint") is String
