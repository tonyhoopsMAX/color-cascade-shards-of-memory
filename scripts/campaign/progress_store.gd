class_name ProgressStore
extends RefCounted
## Versioned, validated local progress. Never stores personal data. A previous
## valid save remains as .bak, and failed writes are reported to the caller.

const DEFAULT_PATH := "user://campaign_progress.json"
const MAX_BYTES := 65536

var save_path: String
var level_count: int
var unlocked_level := 1
var selected_level := 1
var best_scores: Dictionary = {}
var recovered_backup := false


func _init(count: int, path: String = DEFAULT_PATH) -> void:
	level_count = maxi(1, count)
	save_path = path


func load_progress() -> bool:
	unlocked_level = 1
	selected_level = 1
	best_scores.clear()
	recovered_backup = false
	if _read_valid(save_path):
		return true
	if _read_valid(save_path + ".bak"):
		recovered_backup = true
		return true
	return false


func select_level(id: int) -> bool:
	if id < 1 or id > unlocked_level:
		return false
	selected_level = id
	return true


func record_win(id: int, score: int) -> bool:
	if id < 1 or id > unlocked_level or score < 0:
		return false
	var key := str(id)
	best_scores[key] = maxi(int(best_scores.get(key, 0)), score)
	unlocked_level = maxi(unlocked_level, mini(id + 1, level_count))
	return true


func save_progress() -> Error:
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"version": 1, "unlocked_level": unlocked_level,
		"selected_level": selected_level, "best_scores": best_scores,
	}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	# Only replace the backup with a verified main save. A corrupt main file
	# must never overwrite the backup from which we just recovered.
	var previous := ProgressStore.new(level_count, save_path)
	if previous._read_valid(save_path):
		error = DirAccess.copy_absolute(save_path, save_path + ".bak")
		if error != OK:
			return error
	return DirAccess.rename_absolute(temp_path, save_path)


func _read_valid(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return false
	var data: Variant = parser.data
	if not data is Dictionary or data.get("version") != 1:
		return false
	if not LevelCatalog.whole_number(data.get("unlocked_level"), 1, level_count):
		return false
	var unlocked := int(data["unlocked_level"])
	if not LevelCatalog.whole_number(data.get("selected_level"), 1, unlocked):
		return false
	var scores: Variant = data.get("best_scores")
	if not scores is Dictionary or scores.size() > level_count:
		return false
	for key in scores:
		if not key is String or not key.is_valid_int():
			return false
		var id := int(key)
		if str(id) != key or id < 1 or id > unlocked:
			return false
		if not LevelCatalog.whole_number(scores[key], 0, 1000000000):
			return false
	unlocked_level = unlocked
	selected_level = int(data["selected_level"])
	best_scores = scores.duplicate(true)
	return true
