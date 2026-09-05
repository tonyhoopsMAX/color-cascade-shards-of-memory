extends SceneTree
## Deterministic coverage of level content, scoring, solvability and saves.

var checks := 0
var failures := 0
var test_path: String


func _initialize() -> void:
	test_path = "user://campaign_logic_test_%d.json" % OS.get_process_id()
	var catalog := LevelCatalog.new()
	check(catalog.load_levels(), "level catalog loads")
	check(catalog.levels.size() == 6, "six introductory levels")
	check(catalog.get_level(0).is_empty() and catalog.get_level(7).is_empty(), "invalid level IDs rejected")
	var copy := catalog.get_level(1)
	copy["moves"] = 1
	check(int(catalog.get_level(1)["moves"]) == 20, "definitions cannot be mutated by callers")
	check(not LevelCatalog.whole_number("2", 1, 6), "numeric strings rejected")
	check(not LevelCatalog.whole_number(2.5, 1, 6), "fractional IDs rejected")
	check(not LevelCatalog.whole_number(INF, 1, 6), "infinity rejected")

	var attempt := PuzzleAttempt.new(9)
	attempt.record_resolution(0, 0)
	check(attempt.score == 0, "no score for a placement without a clear")
	attempt.record_resolution(3, 1)
	check(attempt.score == 30 and not attempt.is_won(), "ten points per cleared tile")
	attempt.record_resolution(7, 2)
	check(attempt.score == 150 and attempt.is_won(), "cascade bonus and goal overshoot")
	check(attempt.best_cascade == 2, "largest cascade recorded")

	for definition in catalog.levels:
		_test_solvable(definition)
	_test_saves()
	_cleanup()
	print("CAMPAIGN LOGIC: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		printerr("FAIL ", message)


func _test_solvable(level: Dictionary) -> void:
	var board := BoardState.new(7, 8)
	var queue := TileQueue.new(TileTypes.all(), int(level["seed"]))
	var resolver := CascadeResolver.new(MatchDetector.new(3))
	var attempt := PuzzleAttempt.new(int(level["clear_goal"]))
	# One lane per color gives a concrete legal solution, not just an estimate.
	for move in range(int(level["moves"])):
		var color := queue.pop_current()
		var row := 7
		while row >= 0 and not board.is_empty(color, row):
			row -= 1
		if row < 0:
			break
		board.set_cell(color, row, color)
		var cleared := 0
		var waves := 0
		for step in resolver.resolve(board):
			if step["type"] == CascadeResolver.STEP_CLEAR:
				cleared += step["cells"].size()
				waves += 1
		attempt.record_resolution(cleared, waves)
		if attempt.is_won():
			break
	check(attempt.is_won(), "level %d has a legal solution within its move budget" % int(level["id"]))


func _test_saves() -> void:
	var progress := ProgressStore.new(6, test_path)
	check(not progress.load_progress() and progress.unlocked_level == 1, "missing save starts fresh")
	check(not progress.select_level(2), "locked level cannot be selected")
	check(not progress.record_win(2, 500), "locked level cannot unlock successors")
	check(progress.record_win(1, 120), "winning level accepted")
	check(progress.unlocked_level == 2, "only the next level unlocks")
	progress.record_win(1, 60)
	check(progress.best_scores["1"] == 120, "replay cannot lower a best score")
	check(progress.select_level(2), "unlocked level can be selected")
	check(progress.save_progress() == OK, "save succeeds")
	var loaded := ProgressStore.new(6, test_path)
	check(loaded.load_progress(), "save reloads")
	check(loaded.selected_level == 2 and loaded.best_scores["1"] == 120, "selection and score survive reload")
	loaded.record_win(2, 180)
	check(loaded.save_progress() == OK, "second save keeps a backup")
	_write(test_path, "{broken json")
	var recovered := ProgressStore.new(6, test_path)
	check(recovered.load_progress() and recovered.recovered_backup, "corrupt main save recovers backup")
	check(recovered.unlocked_level == 2, "backup contains the last valid state")
	check(recovered.save_progress() == OK, "recovered state can be saved")
	var reloaded := ProgressStore.new(6, test_path)
	check(reloaded.load_progress() and not reloaded.recovered_backup, "recovery repairs the main save")
	_cleanup()
	_write(test_path, JSON.stringify({"version": 1, "unlocked_level": 99, "selected_level": 1, "best_scores": {}}))
	check(not reloaded.load_progress() and reloaded.unlocked_level == 1, "out-of-range save is rejected")
	_write(test_path, JSON.stringify({"version": 1, "unlocked_level": 1, "selected_level": 1, "best_scores": {"1": "bad"}}))
	check(not reloaded.load_progress(), "invalid score type is rejected")
	_write(test_path, JSON.stringify({"version": 99, "unlocked_level": 1, "selected_level": 1, "best_scores": {}}))
	check(not reloaded.load_progress(), "unsupported save schema rejected")
	var invalid_path := ProgressStore.new(6, "user://missing_campaign_test_%d/progress.json" % OS.get_process_id())
	check(invalid_path.save_progress() != OK, "write failures are surfaced")
	var final_progress := ProgressStore.new(6, test_path)
	for id in range(1, 7):
		final_progress.record_win(id, 300)
	check(final_progress.unlocked_level == 6 and final_progress.best_scores.size() == 6, "final win does not create a seventh level")


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(test_path + suffix):
			DirAccess.remove_absolute(test_path + suffix)
