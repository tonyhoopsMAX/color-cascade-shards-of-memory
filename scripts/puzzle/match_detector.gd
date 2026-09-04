class_name MatchDetector
extends RefCounted
## Finds groups of same-coloured tiles that are connected ORTHOGONALLY only.
##
## Connectivity uses the four von Neumann neighbours (up, down, left, right).
## Diagonal adjacency is deliberately NOT considered a connection, so two tiles
## touching only at a corner never join the same group.

## Orthogonal neighbour offsets. No diagonals on purpose.
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var min_match_size: int


func _init(p_min_match_size: int = 3) -> void:
	min_match_size = maxi(1, p_min_match_size)


## Returns every clearable group on the board.
## Each group is an Array[Vector2i] of (column, row) cells sharing one colour
## and connected orthogonally, with size >= min_match_size.
func find_matches(board: BoardState) -> Array:
	var groups: Array = []
	var visited := {}
	for row in range(board.rows):
		for column in range(board.columns):
			var start := Vector2i(column, row)
			if visited.has(start):
				continue
			var tile_type := board.get_cell(column, row)
			if tile_type == BoardState.EMPTY:
				continue
			var group := _flood_fill(board, start, tile_type, visited)
			if group.size() >= min_match_size:
				groups.append(group)
	return groups


## Returns the connected same-colour group containing the given cell
## (regardless of size), or an empty array if the cell is empty.
func get_group_at(board: BoardState, cell: Vector2i) -> Array[Vector2i]:
	var tile_type := board.get_cell(cell.x, cell.y)
	if tile_type == BoardState.EMPTY:
		return []
	return _flood_fill(board, cell, tile_type, {})


## Convenience: does the board contain at least one clearable group?
func has_matches(board: BoardState) -> bool:
	return not find_matches(board).is_empty()


## Flattens find_matches() into a unique list of cells to clear.
func collect_matched_cells(board: BoardState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var seen := {}
	for group in find_matches(board):
		for cell in group:
			if not seen.has(cell):
				seen[cell] = true
				cells.append(cell)
	return cells


## Iterative breadth-first flood fill over orthogonal neighbours.
func _flood_fill(board: BoardState, start: Vector2i, tile_type: int, visited: Dictionary) -> Array[Vector2i]:
	var group: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		group.append(current)
		for offset in NEIGHBOUR_OFFSETS:
			var next := current + offset
			if visited.has(next):
				continue
			if not board.is_inside(next.x, next.y):
				continue
			if board.get_cell(next.x, next.y) != tile_type:
				continue
			visited[next] = true
			queue.append(next)
	return group
