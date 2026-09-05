class_name CampaignController
extends PuzzleController
## Extends the original prototype without changing its rules or test scene.

const OVER_WIN := "win"

@export var progress_path: String = ProgressStore.DEFAULT_PATH

var catalog := LevelCatalog.new()
var progress: ProgressStore
var attempt: PuzzleAttempt
var level_id := 1
var level: Dictionary
var last_save_error: Error = OK

var level_label: Label
var goal_label: Label
var save_label: Label
var goal_bar: ProgressBar
var next_button: Button
var levels_button: Button
var level_overlay: ColorRect
var level_list: VBoxContainer


func _ready() -> void:
	if not catalog.load_levels():
		board.accepting_input = false
		status_label.text = "Level data could not be loaded. Please reinstall the game."
		restart_button.disabled = true
		return
	progress = ProgressStore.new(catalog.levels.size(), progress_path)
	var loaded := progress.load_progress()
	level_id = progress.selected_level
	_build_campaign_ui()
	super._ready()
	board.resolution_started.connect(_update_navigation)
	board.resolution_finished.connect(func(_cleared: int, _waves: int) -> void: _update_navigation())
	if progress.recovered_backup:
		save_label.text = "Recovered the previous progress save."
	elif not loaded and FileAccess.file_exists(progress_path):
		save_label.text = "Save unreadable. Starting at level 1."
	_update_navigation()


func restart() -> void:
	level = catalog.get_level(level_id)
	starting_moves = int(level["moves"])
	queue_seed = int(level["seed"])
	attempt = PuzzleAttempt.new(int(level["clear_goal"]))
	super.restart()
	restart_button.text = "Retry"
	_set_status(level["hint"])
	_refresh_hud()
	_update_navigation()


func _on_board_resolution_finished(cleared_tiles: int, cascade_count: int) -> void:
	if is_over:
		return
	attempt.record_resolution(cleared_tiles, cascade_count)
	_refresh_hud()
	# Check the goal before the move budget: a last-move clear is still a win.
	if attempt.is_won():
		_finish(OVER_WIN)
	else:
		super._on_board_resolution_finished(cleared_tiles, cascade_count)
	_update_navigation()


func _finish(reason: String) -> void:
	if is_over:
		return
	# Publish the complete result only after saving and updating the visible HUD.
	is_over = true
	board.accepting_input = false
	if reason == OVER_WIN:
		progress.record_win(level_id, attempt.score)
		_save_progress()
		if level_id == catalog.levels.size():
			_set_status("Chapter complete! Replay any level to improve your score.")
		else:
			_set_status("Level complete! %d points. The next level is unlocked." % attempt.score)
	elif reason == OVER_NO_MOVES:
		_set_status("Out of moves! Cleared %d of %d. Retry uses the same tile sequence." % [attempt.cleared_tiles, attempt.clear_goal])
	else:
		_set_status("The board is full. Tap Retry to try again.")
	_refresh_hud()
	_update_navigation()
	puzzle_over.emit(reason)


func start_level(id: int) -> bool:
	if board.is_resolving or not progress.select_level(id):
		return false
	level_id = id
	level_overlay.hide()
	_save_progress()
	restart()
	return true


func advance_level() -> void:
	if is_over and attempt.is_won() and level_id < catalog.levels.size():
		start_level(level_id + 1)


func open_levels() -> void:
	if board.is_resolving:
		return
	for child in level_list.get_children():
		level_list.remove_child(child)
		child.queue_free()
	for definition in catalog.levels:
		var id := int(definition["id"])
		var unlocked := id <= progress.unlocked_level
		var suffix := ""
		if not unlocked:
			suffix = "  /  Locked"
		elif progress.best_scores.has(str(id)):
			suffix = "  /  Best %d" % int(progress.best_scores[str(id)])
		var button := _button("%d. %s%s" % [id, definition["title"], suffix])
		button.disabled = not unlocked
		button.pressed.connect(start_level.bind(id))
		level_list.add_child(button)
	level_overlay.show()
	board.accepting_input = false


func close_levels() -> void:
	level_overlay.hide()
	board.accepting_input = not is_over


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(level_overlay):
		if level_overlay.visible:
			close_levels()
		else:
			open_levels()


func _save_progress() -> void:
	last_save_error = progress.save_progress()
	save_label.text = "" if last_save_error == OK else "Progress not saved. Keep the app open and try again."


func _refresh_hud() -> void:
	level_label.text = "CHAPTER 1  /  %d OF %d  /  %s" % [level_id, catalog.levels.size(), level["title"]]
	goal_label.text = "Clear %d / %d    Score %d    Best %d" % [mini(attempt.cleared_tiles, attempt.clear_goal), attempt.clear_goal, attempt.score, int(progress.best_scores.get(str(level_id), 0))]
	goal_bar.max_value = attempt.clear_goal
	goal_bar.value = mini(attempt.cleared_tiles, attempt.clear_goal)


func _update_navigation() -> void:
	if not is_instance_valid(next_button):
		return
	levels_button.disabled = board.is_resolving
	next_button.disabled = not is_over or not attempt.is_won() or level_id >= catalog.levels.size()
	# Retry remains usable during a cascade, as in the original prototype.


func _build_campaign_ui() -> void:
	var layout: VBoxContainer = $SafeArea/Layout
	layout.add_theme_constant_override("separation", 16)
	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 6)
	layout.add_child(summary)
	layout.move_child(summary, 0)
	level_label = _label(26)
	goal_label = _label(30)
	goal_bar = ProgressBar.new()
	goal_bar.custom_minimum_size.y = 14
	goal_bar.show_percentage = false
	goal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_label = _label(22)
	save_label.modulate = Color(1.0, 0.76, 0.45)
	summary.add_child(level_label)
	summary.add_child(goal_label)
	summary.add_child(goal_bar)
	summary.add_child(save_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	var footer := restart_button.get_parent()
	footer.add_child(actions)
	restart_button.reparent(actions)
	restart_button.custom_minimum_size = Vector2(0, 84)
	restart_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart_button.add_theme_font_size_override("font_size", 30)
	levels_button = _button("Levels")
	next_button = _button("Next")
	actions.add_child(levels_button)
	actions.add_child(next_button)
	levels_button.pressed.connect(open_levels)
	next_button.pressed.connect(advance_level)
	_build_level_menu()


func _build_level_menu() -> void:
	level_overlay = ColorRect.new()
	level_overlay.color = Color(0.02, 0.025, 0.05, 0.97)
	add_child(level_overlay)
	level_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	level_overlay.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)
	var title := _label(38)
	title.text = "COLOR CASCADE / CHAPTER 1"
	content.add_child(title)
	var hint := _label(26)
	hint.text = "Choosing a level starts a new attempt. Unlocked levels and best scores are saved."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	level_list = VBoxContainer.new()
	level_list.add_theme_constant_override("separation", 14)
	content.add_child(level_list)
	var resume := _button("Back to puzzle")
	resume.pressed.connect(close_levels)
	content.add_child(resume)
	level_overlay.hide()


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 84)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 30)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return button
