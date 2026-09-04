class_name BoardState
extends RefCounted
## Pure data model of the puzzle grid.
##
## Stores one integer per cell (a TileTypes.Kind value or EMPTY). Contains no nodes, no rendering and no timing so it can be
## unit-tested and reasoned about independently of the scene.
##
## Coordinates: column 0 is the left edge, row 0 is the TOP of the board.
## Gravity therefore pulls tiles towards higher row indices.

const EMPTY := -1

var columns: int
var rows: int

## Flat array, index = row * columns + column.
var _cells: Array[int] = []


func _init(p_columns: int = 7, p_rows: int = 8) -> void:
	columns = maxi(1, p_columns)
	rows = maxi(1, p_rows)
	clear()


## Resets every cell to EMPTY.
func clear() -> void:
	_cells.clear()
	_cells.resize(columns * rows)
	_cells.fill(EMPTY)


func is_inside(column: int, row: int) -> bool:
	return column >= 0 and column < columns and row >= 0 and row < rows


func get_cell(column: int, row: int) -> int:
	if not is_inside(column, row):
		return EMPTY
	return _cells[row * columns + column]


func set_cell(column: int, row: int, tile_type: int) -> void:
	if not is_inside(column, row):
		push_warning("BoardState.set_cell out of bounds: (%d, %d)" % [column, row])
		return
	_cells[row * columns + column] = tile_type


func is_empty(column: int, row: int) -> bool:
	return get_cell(column, row) == EMPTY


func clear_cell(column: int, row: int) -> void:
	set_cell(column, row, EMPTY)


## Number of cells currently holding a tile.
func count_tiles() -> int:
	var count := 0
	for value in _cells:
		if value != EMPTY:
			count += 1
	return count


func count_empty() -> int:
	return columns * rows - count_tiles()


func is_full() -> bool:
	return count_empty() == 0


## Returns a deep copy of this board (useful for tests and previews).
func duplicate_state() -> BoardState:
	var copy := BoardState.new(columns, rows)
	copy._cells = _cells.duplicate()
	return copy


## Applies gravity to every column so tiles sit at the bottom with all empty
## cells above them. Tile order inside a column is preserved.
##
## Returns an Array of Dictionaries describing each tile that moved:
##   {"column": int, "from_row": int, "to_row": int, "tile_type": int}
## The list is empty when nothing moved.
func apply_gravity() -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for column in range(columns):
		# Scan bottom-up; write_row is the lowest row still available to fill.
		var write_row := rows - 1
		for read_row in range(rows - 1, -1, -1):
			var tile_type := get_cell(column, read_row)
			if tile_type == EMPTY:
				continue
			if read_row != write_row:
				set_cell(column, write_row, tile_type)
				clear_cell(column, read_row)
				moves.append({
					"column": column,
					"from_row": read_row,
					"to_row": write_row,
					"tile_type": tile_type,
				})
			write_row -= 1
	return moves


## Human-readable dump for debugging and tests (top row first).
func to_debug_string() -> String:
	var lines: PackedStringArray = []
	for row in range(rows):
		var line := ""
		for column in range(columns):
			var value := get_cell(column, row)
			line += "." if value == EMPTY else str(value)
		lines.append(line)
	return "\n".join(lines)


## Fills the board from a list of strings (top row first). Each character is a
## digit for a tile type or "." for empty. Handy for tests and future level data.
func load_from_strings(pattern: PackedStringArray) -> void:
	clear()
	for row in range(mini(rows, pattern.size())):
		var line := pattern[row]
		for column in range(mini(columns, line.length())):
			var ch := line[column]
			if ch == ".":
				continue
			if ch.is_valid_int():
				set_cell(column, row, ch.to_int())
