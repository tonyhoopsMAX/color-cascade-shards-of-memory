extends SceneTree
## Headless unit tests for the pure puzzle logic (no rendering required).
##
## Run from the repository root:
##   godot --headless --path . --script res://tests/test_puzzle_logic.gd
## Exits with code 0 when every check passes, 1 otherwise.

var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("== Color Cascade: puzzle logic tests ==")
	_test_board_state_basics()
	_test_gravity_preserves_order_and_never_overlaps()
	_test_orthogonal_matches_are_found()
	_test_diagonal_tiles_do_not_match()
	_test_two_tiles_are_not_a_match()
	_test_l_shape_and_mixed_colours()
	_test_cascade_chain_reaction()
	_test_cascade_without_matches_is_noop()
	_test_tile_queue_is_deterministic_with_seed()
	_test_load_from_strings_round_trip()

	print("\n%d checks, %d failures" % [_checks, _failures])
	if _failures == 0:
		print("ALL LOGIC TESTS PASSED")
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


func _board(pattern: PackedStringArray, columns: int = 7, rows: int = 8) -> BoardState:
	var board := BoardState.new(columns, rows)
	board.load_from_strings(pattern)
	return board


func _column_has_no_gaps_below_tiles(board: BoardState, column: int) -> bool:
	var seen_tile := false
	for row in range(board.rows):
		var empty := board.is_empty(column, row)
		if seen_tile and empty:
			return false
		if not empty:
			seen_tile = true
	return true


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_board_state_basics() -> void:
	print("\n[BoardState basics]")
	var board := BoardState.new(7, 8)
	_check(board.columns == 7 and board.rows == 8, "board is 7 columns x 8 rows")
	_check(board.count_tiles() == 0 and board.count_empty() == 56, "new board is empty (56 cells)")
	board.set_cell(3, 7, 2)
	_check(board.get_cell(3, 7) == 2, "set/get cell round trip")
	_check(board.get_cell(-1, 0) == BoardState.EMPTY and board.get_cell(7, 0) == BoardState.EMPTY, "out-of-bounds reads are EMPTY")
	_check(not board.is_inside(0, 8) and board.is_inside(6, 7), "is_inside respects bounds")
	board.clear()
	_check(board.count_tiles() == 0, "clear() empties the board")


func _test_gravity_preserves_order_and_never_overlaps() -> void:
	print("\n[Gravity]")
	var board := _board([
		"0......",
		".......",
		"1......",
		".......",
		".2.....",
		"3......",
		".......",
		".......",
	])
	var moves := board.apply_gravity()
	_check(board.get_cell(0, 7) == 3 and board.get_cell(0, 6) == 1 and board.get_cell(0, 5) == 0, "column 0 stacks bottom-up in original order (3,1,0)")
	_check(board.get_cell(1, 7) == 2, "column 1 tile falls to the bottom row")
	_check(board.count_tiles() == 4, "gravity never loses or duplicates tiles")
	var ok := true
	for column in range(board.columns):
		ok = ok and _column_has_no_gaps_below_tiles(board, column)
	_check(ok, "no empty cell remains below a tile in any column")
	_check(moves.size() == 4, "each moved tile is reported exactly once (%d moves)" % moves.size())
	var second := board.apply_gravity()
	_check(second.is_empty(), "gravity on a settled board reports no moves")


func _test_orthogonal_matches_are_found() -> void:
	print("\n[Orthogonal matches]")
	var detector := MatchDetector.new(3)
	var horizontal := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"..111..",
	])
	var groups := detector.find_matches(horizontal)
	_check(groups.size() == 1 and groups[0].size() == 3, "horizontal run of 3 is one group of 3")

	var vertical := _board([
		".......",
		".......",
		".......",
		".......",
		"4......",
		"4......",
		"4......",
		"4......",
	])
	groups = detector.find_matches(vertical)
	_check(groups.size() == 1 and groups[0].size() == 4, "vertical run of 4 is one group of 4")


func _test_diagonal_tiles_do_not_match() -> void:
	print("\n[Diagonals must NOT count]")
	var detector := MatchDetector.new(3)
	var diagonal := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		"2......",
		".2.....",
		"..2....",
	])
	_check(detector.find_matches(diagonal).is_empty(), "three same-colour tiles on a diagonal form no match")
	_check(detector.get_group_at(diagonal, Vector2i(0, 5)).size() == 1, "diagonal neighbour is not part of the group")

	var checker := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"0.0.0..",
		".0.0...",
	])
	_check(detector.find_matches(checker).is_empty(), "checkerboard of 5 same-colour tiles (corner contact only) has no match")

	var corner_plus_pair := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"..3....",
		"33.....",
	])
	_check(detector.find_matches(corner_plus_pair).is_empty(), "a pair plus a diagonal third tile is not a group of 3")


func _test_two_tiles_are_not_a_match() -> void:
	print("\n[Minimum group size]")
	var detector := MatchDetector.new(3)
	var pair := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"11.1...",
	])
	_check(detector.find_matches(pair).is_empty(), "two adjacent tiles plus a separated one do not match")
	pair.set_cell(2, 7, 1)
	_check(detector.find_matches(pair).size() == 1 and detector.find_matches(pair)[0].size() == 4, "filling the gap creates one group of 4")


func _test_l_shape_and_mixed_colours() -> void:
	print("\n[Shapes and colours]")
	var detector := MatchDetector.new(3)
	var l_shape := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		"0......",
		"0......",
		"00.....",
	])
	var groups := detector.find_matches(l_shape)
	_check(groups.size() == 1 and groups[0].size() == 4, "L-shape of 4 is a single orthogonal group")

	var mixed := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"010....",
	])
	_check(detector.find_matches(mixed).is_empty(), "different colours in a row never match")

	var two_groups := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"222.444",
		"1.1.1.1",
	])
	groups = detector.find_matches(two_groups)
	_check(groups.size() == 2, "two separate groups are both reported")
	_check(detector.collect_matched_cells(two_groups).size() == 6, "collect_matched_cells flattens to 6 unique cells")


func _test_cascade_chain_reaction() -> void:
	print("\n[Cascades]")
	var resolver := CascadeResolver.new(MatchDetector.new(3))
	# Clearing the T of four 1s drops the two 0s in column 1 next to the 0 in
	# column 0 -> a second clear of three 0s (a genuine chain reaction).
	var board := _board([
		".......",
		".......",
		".......",
		".......",
		".0.....",
		".0.....",
		".1.....",
		"0111...",
	])
	var steps := resolver.resolve(board)
	_check(CascadeResolver.count_clears(steps) == 2, "two clear waves happen (1s, then the 0s after falling)")
	_check(CascadeResolver.count_cleared_tiles(steps) == 7, "seven tiles cleared in total (4 + 3)")
	_check(board.count_tiles() == 0, "board ends empty and stable")
	_check(resolver.match_detector.find_matches(board).is_empty(), "no matches remain after resolve()")

	# A cascade that leaves survivors: the 2 must land on the floor afterwards.
	var survivor := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"2......",
		"333....",
	])
	steps = resolver.resolve(survivor)
	_check(CascadeResolver.count_clears(steps) == 1, "single clear wave for the 3s")
	_check(survivor.get_cell(0, 7) == 2 and survivor.count_tiles() == 1, "survivor falls onto the bottom row after the clear")
	var has_gravity_step := false
	for step in steps:
		if step["type"] == CascadeResolver.STEP_GRAVITY:
			has_gravity_step = true
	_check(has_gravity_step, "a gravity step is reported for the falling survivor")


func _test_cascade_without_matches_is_noop() -> void:
	print("\n[Cascade no-op]")
	var resolver := CascadeResolver.new()
	var board := _board([
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		".......",
		"0101010",
	])
	var before := board.to_debug_string()
	var steps := resolver.resolve(board)
	_check(steps.is_empty(), "resolve() returns no steps when nothing matches")
	_check(board.to_debug_string() == before, "board is untouched when nothing matches")


func _test_tile_queue_is_deterministic_with_seed() -> void:
	print("\n[Tile queue]")
	var types: Array[int] = [0, 1, 2, 3, 4]
	var a := TileQueue.new(types, 1234)
	var b := TileQueue.new(types, 1234)
	var same := true
	var all_valid := true
	for i in range(50):
		if a.get_current() != b.get_current() or a.get_next() != b.get_next():
			same = false
		if not types.has(a.get_current()):
			all_valid = false
		a.pop_current()
		b.pop_current()
	_check(same, "same seed yields the same 50-tile sequence")
	_check(all_valid, "queue only produces known tile types")
	var first_next := a.get_next()
	a.pop_current()
	_check(a.get_current() == first_next, "pop_current() promotes next -> current")


func _test_load_from_strings_round_trip() -> void:
	print("\n[Debug serialisation]")
	var pattern: PackedStringArray = [
		".......",
		".......",
		".......",
		".......",
		".......",
		"..4....",
		".33....",
		"01210..",
	]
	var board := _board(pattern)
	_check(board.to_debug_string() == "\n".join(pattern), "load_from_strings / to_debug_string round trip")
