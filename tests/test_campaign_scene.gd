extends SceneTree
## Real campaign scene, isolated from player saves. Includes zero-animation
## placement, final-move wins, restart, navigation, layout and persistent unlocks.

var checks := 0
var failures := 0
var scene: CampaignController
var test_path: String


func _initialize() -> void:
	test_path = "user://campaign_scene_test_%d.json" % OS.get_process_id()
	_run()


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		printerr("FAIL ", message)


func _run() -> void:
	await process_frame
	root.size = Vector2i(1080, 1920)
	root.content_scale_size = root.size
	var packed: PackedScene = load("res://scenes/campaign/campaign_scene.tscn")
	scene = packed.instantiate()
	scene.progress_path = test_path
	root.add_child(scene)
	scene.board.place_duration = 0
	scene.board.clear_duration = 0
	scene.board.fall_duration = 0
	scene.board.step_pause = 0
	await process_frame
	await process_frame
	check(scene.level_id == 1 and scene.moves_left == 20, "new player starts level one")
	check(scene.attempt.clear_goal == 6 and scene.attempt.score == 0, "goal and score initialized")
	check(scene.next_button.disabled, "Next disabled before a win")
	check(not scene.start_level(2), "controller rejects a locked level")

	var first := scene.tile_queue.get_current()
	scene._on_board_cell_tapped(Vector2i(0, 7))
	check(scene.board.is_resolving and scene.moves_left == 19, "zero-animation placement charges move before completion")
	await _idle()
	check(not scene.is_over and scene.attempt.score == 0, "no-match placement does not score or end early")
	scene.restart()
	check(scene.tile_queue.get_current() == first, "retry repeats the tile sequence")
	scene._set_moves(1)
	scene._on_board_cell_tapped(Vector2i(0, 7))
	await _idle()
	check(scene.is_over and scene.moves_left == 0, "last non-matching move ends attempt with animations off")
	check(scene.progress.unlocked_level == 1, "loss does not unlock levels")

	scene.restart()
	# Stage a legal final placement: two same-color neighbors below CURRENT.
	# The remaining goal is three, after a previous three-tile clear.
	scene.attempt.record_resolution(3, 1)
	var color := scene.tile_queue.get_current()
	for row in [6, 7]:
		scene.board.board_state.set_cell(0, row, color)
		scene.board._spawn_tile(Vector2i(0, row), color)
	scene._set_moves(1)
	var results: Array[String] = []
	scene.puzzle_over.connect(func(reason: String) -> void: results.append(reason))
	scene._on_board_cell_tapped(Vector2i(0, 5))
	await _idle()
	check(results == [CampaignController.OVER_WIN], "last-move goal produces exactly one win, not a loss")
	check(scene.is_over and not scene.board.accepting_input, "winning locks board input")
	check(scene.attempt.score == 60 and scene.progress.best_scores["1"] == 60, "win records actual score")
	check(scene.progress.unlocked_level == 2 and not scene.next_button.disabled, "winning unlocks Next")
	check(scene.last_save_error == OK, "winning saves progress")
	var stored := ProgressStore.new(6, test_path)
	check(stored.load_progress() and stored.unlocked_level == 2, "unlock survives a fresh save-store instance")
	scene.advance_level()
	check(scene.level_id == 2 and scene.moves_left == 22 and not scene.is_over, "Next starts level two with its own move budget")
	check(scene.attempt.score == 0 and scene.board.board_state.count_tiles() == 0, "Next resets score and board")
	scene.open_levels()
	check(scene.level_overlay.visible and not scene.board.accepting_input, "level menu blocks board input")
	check(scene.level_list.get_child_count() == 6, "level menu includes all six levels")
	check((scene.level_list.get_child(2) as Button).disabled, "locked level is disabled in menu")
	scene.close_levels()
	check(not scene.level_overlay.visible and scene.board.accepting_input, "Back resumes current attempt")
	check(scene.start_level(1), "completed level can be replayed")
	check(scene.progress.unlocked_level == 2, "replay preserves unlocks")

	# Restart during the mandatory pre-resolution yield must cancel the turn.
	scene._on_board_cell_tapped(Vector2i(0, 7))
	scene.restart()
	await process_frame
	await process_frame
	check(scene.moves_left == 20 and scene.attempt.score == 0 and scene.board.board_state.count_tiles() == 0, "restart cancels a pending zero-animation turn")

	await _test_layout()
	# Verify replaying the final unlocked level cannot advance past the catalog.
	for id in range(1, 7):
		scene.progress.record_win(id, 300)
	check(scene.start_level(6), "final level can be started once unlocked")
	scene._on_board_resolution_finished(24, 1)
	check(scene.is_over and scene.next_button.disabled, "chapter completion disables Next")
	scene.advance_level()
	check(scene.level_id == 6, "cannot advance to a nonexistent level seven")
	check(scene.status_label.text.begins_with("Chapter complete"), "chapter completion message is visible")
	scene.free()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(test_path + suffix):
			DirAccess.remove_absolute(test_path + suffix)
	print("CAMPAIGN SCENE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _idle() -> void:
	var frames := 0
	while scene.board.is_resolving and frames < 600:
		await process_frame
		frames += 1
	check(not scene.board.is_resolving, "resolution completed within timeout")


func _test_layout() -> void:
	for dimensions in [Vector2i(1080, 1920), Vector2i(1080, 2400), Vector2i(1080, 1620), Vector2i(720, 1280)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		scene.size = Vector2(dimensions)
		await process_frame
		await process_frame
		var screen := Rect2(Vector2.ZERO, Vector2(dimensions)).grow(0.5)
		var fits := true
		for control in [scene.board, scene.level_label, scene.goal_label, scene.goal_bar, scene.restart_button, scene.next_button, scene.levels_button, scene.status_label]:
			fits = fits and screen.encloses(control.get_global_rect())
		var board_rect := scene.board.get_global_rect()
		var no_overlap := not board_rect.intersects(scene.goal_label.get_global_rect()) \
			and not board_rect.intersects(scene.status_label.get_global_rect()) \
			and not board_rect.intersects(scene.restart_button.get_global_rect())
		check(fits and no_overlap, "campaign fits without overlap at %dx%d" % [dimensions.x, dimensions.y])
