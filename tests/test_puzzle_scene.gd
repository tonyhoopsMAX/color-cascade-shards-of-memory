extends SceneTree
## Headless integration test: instantiates the real puzzle scene, simulates taps
## and verifies the full loop (place -> move consumed -> queue advances ->
## clear -> gravity -> cascade -> input lock -> restart).
##
## Run from the repository root:
##   godot --headless --path . --script res://tests/test_puzzle_scene.gd
## Exits with code 0 when every check passes, 1 otherwise.

const SCENE_PATH := "res://scenes/puzzle/puzzle_scene.tscn"
const VIEWPORT_SIZE := Vector2i(1080, 1920)

var _failures := 0
var _checks := 0
var _scene: PuzzleController
var _board: BoardManager


func _initialize() -> void:
	print("== Color Cascade: puzzle scene tests ==")
	_run()


func _run() -> void:
	# The root window only enters the tree after _initialize(); wait a frame so
	# the headless window exists before sizing it and adding the scene.
	await process_frame
	root.size = VIEWPORT_SIZE
	root.content_scale_size = VIEWPORT_SIZE

	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		printerr("  FAIL  could not load %s" % SCENE_PATH)
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	_board = _scene.board
	if _board == null:
		printerr("  FAIL  scene has no board (was _ready() called?)")
		quit(1)
		return
	# Make animations fast but keep them non-zero so the "busy" lock is testable.
	_board.place_duration = 0.02
	_board.clear_duration = 0.02
	_board.fall_duration = 0.02
	_board.step_pause = 0.0
	await process_frame
	await process_frame

	await _test_layout_fits_viewport()
	await _test_place_consumes_move_and_advances_queue()
	await _test_occupied_cell_is_rejected()
	await _test_input_locked_while_resolving()
	await _test_clear_gravity_and_cascade_through_scene()
	await _test_restart_resets_everything()
	await _test_out_of_moves_locks_input()
	await _test_restart_during_cascade_is_safe()

	print("\n%d checks, %d failures" % [_checks, _failures])
	if _failures == 0:
		print("ALL SCENE TESTS PASSED")
	quit(0 if _failures == 0 else 1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures += 1
		printerr("  FAIL  %s" % message)


## Sends a press+release touch at the centre of a board cell through the real
## input pipeline (Viewport -> Control._gui_input), exactly like a finger tap.
func _tap_cell(cell: Vector2i) -> void:
	var global_pos := _board.get_global_transform() * _board.get_cell_center(cell)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = global_pos
	root.push_input(press, true)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = global_pos
	root.push_input(release, true)


func _click_restart() -> void:
	var button := _scene.restart_button
	var global_pos := button.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = global_pos
	press.global_position = global_pos
	root.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = global_pos
	release.global_position = global_pos
	root.push_input(release, true)


func _wait_until_idle(max_frames: int = 600) -> void:
	var frames := 0
	while _board.is_resolving and frames < max_frames:
		await process_frame
		frames += 1


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(0.5).encloses(inner)


## Directly seeds the logical board and tile nodes so a specific scenario can
## be tested without relying on the random queue. Uses the board's public API.
func _force_board(pattern: PackedStringArray) -> void:
	_board.reset_board()
	var state := _board.board_state
	var template := BoardState.new(state.columns, state.rows)
	template.load_from_strings(pattern)
	# Place tiles bottom-up without triggering resolution by writing the state
	# and spawning visuals through place_tile on an inert resolver? No - keep it
	# honest: use place_tile only for cells that do not create matches yet.
	for row in range(template.rows - 1, -1, -1):
		for column in range(template.columns):
			var tile_type := template.get_cell(column, row)
			if tile_type == BoardState.EMPTY:
				continue
			_board.board_state.set_cell(column, row, tile_type)
			_board._spawn_tile(Vector2i(column, row), tile_type)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_layout_fits_viewport() -> void:
	print("\n[Layout @ 1080x1920]")
	var screen := Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE))
	_check(_rect_inside(_board.get_global_rect(), screen), "board is inside the screen")
	_check(_rect_inside(_scene.restart_button.get_global_rect(), screen), "restart button is inside the screen")
	_check(_rect_inside(_scene.moves_value_label.get_global_rect(), screen), "moves label is inside the screen")
	_check(_rect_inside(_scene.status_label.get_global_rect(), screen), "status label is inside the screen")

	var board_rect := _board.get_global_rect()
	var button_rect := _scene.restart_button.get_global_rect()
	var header_rect := _scene.moves_value_label.get_global_rect()
	_check(not board_rect.intersects(button_rect), "board does not overlap the restart button")
	_check(not board_rect.intersects(header_rect), "board does not overlap the HUD header")
	_check(not _scene.status_label.get_global_rect().intersects(button_rect), "status label does not overlap the restart button")

	var cell_px := _board.get_cell_rect(Vector2i.ZERO).size.x
	_check(cell_px >= 100.0, "cells are clearly visible (%.0f px at 1080 wide)" % cell_px)
	_check(is_equal_approx(board_rect.size.x / board_rect.size.y, 7.0 / 8.0) or absf(board_rect.size.x / board_rect.size.y - 0.875) < 0.02, "board keeps the 7:8 aspect ratio")

	var last_cell := _board.get_global_transform() * _board.get_cell_rect(Vector2i(6, 7)).end
	_check(_rect_inside(Rect2(last_cell - Vector2.ONE, Vector2.ONE), screen), "bottom-right cell is on screen")

	# Simulate a narrower / taller phone and make sure nothing leaves the screen.
	for test_size in [Vector2i(1080, 2400), Vector2i(1080, 1620), Vector2i(720, 1280)]:
		root.size = test_size
		root.content_scale_size = test_size
		_scene.size = Vector2(test_size)
		await process_frame
		await process_frame
		var test_rect := Rect2(Vector2.ZERO, Vector2(test_size))
		var fits := _rect_inside(_board.get_global_rect(), test_rect) \
			and _rect_inside(_scene.restart_button.get_global_rect(), test_rect) \
			and _rect_inside(_scene.moves_value_label.get_global_rect(), test_rect) \
			and _rect_inside(_scene.status_label.get_global_rect(), test_rect)
		var no_overlap := not _board.get_global_rect().intersects(_scene.restart_button.get_global_rect()) \
			and not _board.get_global_rect().intersects(_scene.moves_value_label.get_global_rect()) \
			and not _board.get_global_rect().intersects(_scene.status_label.get_global_rect())
		_check(fits and no_overlap, "layout fits without overlap at %dx%d" % [test_size.x, test_size.y])
	root.size = VIEWPORT_SIZE
	root.content_scale_size = VIEWPORT_SIZE
	_scene.size = Vector2(VIEWPORT_SIZE)
	await process_frame
	await process_frame


func _test_place_consumes_move_and_advances_queue() -> void:
	print("\n[Placement]")
	_scene.restart()
	await process_frame
	var moves_before := _scene.moves_left
	var current := _scene.tile_queue.get_current()
	var next := _scene.tile_queue.get_next()
	var cell := Vector2i(3, 7)

	_tap_cell(cell)
	await _wait_until_idle()

	_check(_board.board_state.get_cell(cell.x, cell.y) == current, "tapped cell now holds the current tile type")
	_check(_board.get_tile_node(cell) != null, "a Tile node exists at the tapped cell")
	_check(_scene.moves_left == moves_before - 1, "one move consumed (%d -> %d)" % [moves_before, _scene.moves_left])
	_check(_scene.moves_value_label.text == str(_scene.moves_left), "moves label shows the remaining moves")
	_check(_scene.tile_queue.get_current() == next, "queue advanced: previous 'next' is now 'current'")
	_check(_scene._current_preview_tile.tile_type == _scene.tile_queue.get_current(), "current preview matches the queue")
	_check(_scene._next_preview_tile.tile_type == _scene.tile_queue.get_next(), "next preview matches the queue")


func _test_occupied_cell_is_rejected() -> void:
	print("\n[Occupied cell]")
	var cell := Vector2i(3, 7)
	var moves_before := _scene.moves_left
	var tile_before := _board.board_state.get_cell(cell.x, cell.y)
	var rejected := []
	var handler := func(c: Vector2i, reason: String) -> void: rejected.append([c, reason])
	_board.tap_rejected.connect(handler)
	_tap_cell(cell)
	await _wait_until_idle()
	_board.tap_rejected.disconnect(handler)
	_check(_scene.moves_left == moves_before, "tapping an occupied cell does not consume a move")
	_check(_board.board_state.get_cell(cell.x, cell.y) == tile_before, "occupied cell keeps its tile")
	_check(rejected.size() == 1 and rejected[0][1] == BoardManager.REJECT_OCCUPIED, "tap_rejected(occupied) was emitted")


func _test_input_locked_while_resolving() -> void:
	print("\n[Input lock during resolution]")
	_scene.restart()
	await process_frame
	_board.place_duration = 0.3  # long enough to tap again mid-animation
	var first := Vector2i(0, 7)
	var second := Vector2i(1, 7)
	_tap_cell(first)
	await process_frame
	_check(_board.is_resolving, "board reports is_resolving right after a placement")
	var moves_after_first := _scene.moves_left
	_tap_cell(second)
	await process_frame
	_check(_board.board_state.is_empty(second.x, second.y), "second tap during resolution places nothing")
	_check(_scene.moves_left == moves_after_first, "second tap during resolution consumes no move")
	await _wait_until_idle()
	_check(not _board.is_resolving, "board unlocks once resolution finishes")
	_board.place_duration = 0.02
	_tap_cell(second)
	await _wait_until_idle()
	_check(not _board.board_state.is_empty(second.x, second.y), "tap after unlock places normally")


func _test_clear_gravity_and_cascade_through_scene() -> void:
	print("\n[Clear + gravity + cascade in the scene]")
	_scene.restart()
	await process_frame
	# Column 1 holds two 0s above a 1; row 7 holds 0 . 1 1 -> placing a 1 at
	# (1,7) clears four 1s, drops the 0s beside the 0 at (0,7) -> cascade.
	_force_board([
		".......",
		".......",
		".......",
		".......",
		".0.....",
		".0.....",
		".1.....",
		"0.11...",
	])
	await process_frame
	var target := Vector2i(1, 7)
	var results := []
	var handler := func(cleared: int, cascades: int) -> void: results.append([cleared, cascades])
	_board.resolution_finished.connect(handler)
	_check(_board.place_tile(target, 1), "place_tile accepted on the empty cell")
	await _wait_until_idle()
	_board.resolution_finished.disconnect(handler)

	_check(results.size() == 1, "resolution_finished emitted exactly once")
	if results.size() == 1:
		_check(results[0][0] == 7 and results[0][1] == 2, "7 tiles cleared over 2 cascade waves (got %d / %d)" % [results[0][0], results[0][1]])
	_check(_board.board_state.count_tiles() == 0, "logical board is empty after the cascade")
	_check(_board.get_tile_node_count() == 0, "all Tile nodes were removed")
	_check(not _board.is_resolving, "board is idle after the cascade")

	# Gravity with a survivor: visual position must match the logical cell.
	_force_board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"2......",
		".33....",
	])
	await process_frame
	_check(_board.place_tile(Vector2i(0, 7), 3), "place_tile accepted for the gravity scenario")
	await _wait_until_idle()
	var survivor_cell := Vector2i(0, 7)
	var survivor := _board.get_tile_node(survivor_cell)
	_check(_board.board_state.get_cell(0, 7) == 2 and _board.board_state.count_tiles() == 1, "survivor tile fell to the bottom row logically")
	_check(survivor != null and survivor.position.is_equal_approx(_board.get_slot_rect(survivor_cell).position), "survivor Tile node sits exactly on its new cell")
	_check(_board.get_tile_node_count() == 1, "exactly one Tile node remains (no overlap / leftovers)")


func _test_restart_resets_everything() -> void:
	print("\n[Restart]")
	_scene.restart()
	await process_frame
	_tap_cell(Vector2i(2, 7))
	await _wait_until_idle()
	_tap_cell(Vector2i(4, 7))
	await _wait_until_idle()
	_check(_scene.moves_left == PuzzleRules.STARTING_MOVES - 2, "two moves spent before restart")

	_click_restart()
	await process_frame
	await process_frame
	_check(_scene.moves_left == PuzzleRules.STARTING_MOVES, "restart restores %d moves" % PuzzleRules.STARTING_MOVES)
	_check(_scene.moves_value_label.text == str(PuzzleRules.STARTING_MOVES), "moves label reset")
	_check(_board.board_state.count_tiles() == 0, "board state cleared by restart")
	_check(_board.get_tile_node_count() == 0, "tile nodes removed by restart")
	_check(not _board.is_resolving and _board.accepting_input and not _scene.is_over, "restart clears lock / game-over state")
	_check(_scene._current_preview_tile.tile_type == _scene.tile_queue.get_current(), "queue preview refreshed after restart")


func _test_out_of_moves_locks_input() -> void:
	print("\n[Move counter reaches zero]")
	_scene.restart()
	await process_frame
	_scene._set_moves(1)
	_tap_cell(Vector2i(6, 0))  # top-right corner: never part of a match on an empty board
	await _wait_until_idle()
	await process_frame
	_check(_scene.moves_left == 0, "last move consumed")
	_check(_scene.is_over, "puzzle is flagged as over at 0 moves")
	var tiles_before := _board.board_state.count_tiles()
	_tap_cell(Vector2i(5, 0))
	await _wait_until_idle()
	_check(_board.board_state.count_tiles() == tiles_before, "no tile can be placed after moves run out")
	_check(_scene.status_label.text.begins_with("Out of moves"), "status explains the puzzle is over")
	_scene.restart()
	await process_frame
	_check(_scene.moves_left == PuzzleRules.STARTING_MOVES and not _scene.is_over, "restart recovers from the out-of-moves state")


func _test_restart_during_cascade_is_safe() -> void:
	print("\n[Restart mid-cascade]")
	_scene.restart()
	await process_frame
	_board.clear_duration = 0.4
	_force_board([
		".......",
		".......",
		".......",
		".......",
		".0.....",
		".0.....",
		".1.....",
		"0.11...",
	])
	await process_frame
	_board.place_tile(Vector2i(1, 7), 1)
	await process_frame
	await process_frame
	_check(_board.is_resolving, "cascade is in progress")
	_scene.restart()
	await process_frame
	_check(not _board.is_resolving, "restart during a cascade clears the resolving flag")
	_check(_board.board_state.count_tiles() == 0 and _board.get_tile_node_count() == 0, "restart during a cascade leaves an empty board")
	# Let any abandoned coroutine wake up; it must not resurrect state.
	for i in range(40):
		await process_frame
	_check(_board.board_state.count_tiles() == 0 and _board.get_tile_node_count() == 0 and not _board.is_resolving, "abandoned cascade does not modify the fresh board")
	_check(_scene.moves_left == PuzzleRules.STARTING_MOVES, "moves stay at the restarted value")
	_board.clear_duration = 0.02
	_tap_cell(Vector2i(3, 3))
	await _wait_until_idle()
	_check(_board.board_state.count_tiles() == 1, "board is playable again after a mid-cascade restart")
