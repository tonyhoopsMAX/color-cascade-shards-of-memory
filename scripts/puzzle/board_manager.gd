class_name BoardManager
extends Control
## Scene-side owner of the puzzle grid.
##
## Responsibilities:
##   * draws the grid slots (placeholder visuals),
##   * converts taps into grid cells and validates them,
##   * spawns / moves / removes Tile nodes so the visuals mirror BoardState,
##   * plays back CascadeResolver steps with short animations,
##   * locks input while a placement or cascade is resolving.
##
## The rules live in MatchDetector / CascadeResolver and the data in BoardState;
## this node never decides what a match is, it only shows the results.

signal cell_tapped(cell: Vector2i)
signal tap_rejected(cell: Vector2i, reason: String)
signal tile_placed(cell: Vector2i, tile_type: int)
signal resolution_started()
signal resolution_finished(cleared_tiles: int, cascade_count: int)
signal board_reset()

const INVALID_CELL := Vector2i(-1, -1)
const REJECT_BUSY := "busy"
const REJECT_LOCKED := "locked"
const REJECT_OCCUPIED := "occupied"

@export var columns: int = PuzzleRules.BOARD_COLUMNS
@export var rows: int = PuzzleRules.BOARD_ROWS
@export var min_match_size: int = PuzzleRules.MIN_MATCH_SIZE
## Fraction of a cell used as spacing between slots.
@export_range(0.0, 0.3, 0.01) var cell_gap_ratio := 0.08
## When true a freshly placed tile drops immediately. When false (prototype
## default, as specified) tiles stay where they are placed until a clear
## triggers gravity for the whole board.
@export var gravity_after_placement := false

@export_group("Animation")
@export_range(0.0, 1.0, 0.01) var place_duration := 0.14
@export_range(0.0, 1.0, 0.01) var clear_duration := 0.24
@export_range(0.0, 1.0, 0.01) var fall_duration := 0.20
@export_range(0.0, 1.0, 0.01) var step_pause := 0.04

var board_state: BoardState
var match_detector: MatchDetector
var cascade_resolver: CascadeResolver

## True while a placement / cascade is animating. Taps are ignored meanwhile.
var is_resolving := false
## Controller-level gate (e.g. out of moves). Taps are ignored when false.
var accepting_input := true

var _tiles: Dictionary = {}  # Vector2i (column, row) -> Tile
var _tile_layer: Control
var _cell_size := 0.0
var _grid_origin := Vector2.ZERO
var _generation := 0
var _active_tweens: Array[Tween] = []
var _pressed_cell := INVALID_CELL
var _board_style := StyleBoxFlat.new()
var _slot_style := StyleBoxFlat.new()


func _ready() -> void:
	board_state = BoardState.new(columns, rows)
	match_detector = MatchDetector.new(min_match_size)
	cascade_resolver = CascadeResolver.new(match_detector)

	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

	_tile_layer = Control.new()
	_tile_layer.name = "TileLayer"
	_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tile_layer)

	_board_style.bg_color = Color(0.07, 0.08, 0.13, 0.95)
	_slot_style.bg_color = Color(0.19, 0.21, 0.31, 1.0)

	resized.connect(_on_resized)
	_on_resized()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Places a tile on an empty cell and starts resolving matches/cascades.
## Returns false (and does nothing) if the board is busy or the cell is invalid.
func place_tile(cell: Vector2i, tile_type: int) -> bool:
	if is_resolving:
		return false
	if not board_state.is_inside(cell.x, cell.y) or not board_state.is_empty(cell.x, cell.y):
		return false

	board_state.set_cell(cell.x, cell.y, tile_type)
	var tile := _spawn_tile(cell, tile_type)
	tile_placed.emit(cell, tile_type)
	_run_resolution(tile)
	return true


## Fully resets the board: stops any running animation, removes every tile
## and clears the grid. Safe to call in the middle of a cascade.
func reset_board() -> void:
	_generation += 1
	_kill_active_tweens()
	for tile in _tiles.values():
		if is_instance_valid(tile):
			tile.queue_free()
	_tiles.clear()
	if _tile_layer != null:
		for child in _tile_layer.get_children():
			child.queue_free()
	board_state.clear()
	is_resolving = false
	_pressed_cell = INVALID_CELL
	board_reset.emit()


func get_tile_node(cell: Vector2i) -> Tile:
	return _tiles.get(cell) as Tile


func get_tile_node_count() -> int:
	return _tiles.size()


## Converts a position in this control's local space into a grid cell,
## or INVALID_CELL when outside the grid.
func cell_from_position(local_position: Vector2) -> Vector2i:
	if _cell_size <= 0.0:
		return INVALID_CELL
	var local := local_position - _grid_origin
	if local.x < 0.0 or local.y < 0.0:
		return INVALID_CELL
	var column := int(local.x / _cell_size)
	var row := int(local.y / _cell_size)
	if column >= columns or row >= rows:
		return INVALID_CELL
	return Vector2i(column, row)


## Local-space rectangle covering a full cell (including its gap).
func get_cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_grid_origin + Vector2(cell) * _cell_size, Vector2(_cell_size, _cell_size))


## Local-space centre of a cell (handy for tests and effects).
func get_cell_center(cell: Vector2i) -> Vector2:
	return get_cell_rect(cell).get_center()


## Local-space rectangle a tile occupies inside its cell.
func get_slot_rect(cell: Vector2i) -> Rect2:
	return get_cell_rect(cell).grow(-_gap() * 0.5)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# Real touches on mobile and real mouse clicks on desktop are handled.
	# Emulated copies (touch->mouse or mouse->touch) are ignored so a tap is
	# never processed twice.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return

	var pressed := false
	var position := Vector2.ZERO
	if event is InputEventScreenTouch:
		if event.index != 0:
			return
		pressed = event.pressed
		position = event.position
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		pressed = event.pressed
		position = event.position
	else:
		return

	accept_event()
	var cell := cell_from_position(position)
	if pressed:
		_pressed_cell = cell
		return

	# Release: only count it as a tap when it ends on the cell it started on.
	var start_cell := _pressed_cell
	_pressed_cell = INVALID_CELL
	if cell == INVALID_CELL or cell != start_cell:
		return
	_handle_tap(cell)


func _handle_tap(cell: Vector2i) -> void:
	if is_resolving:
		tap_rejected.emit(cell, REJECT_BUSY)
		return
	if not accepting_input:
		tap_rejected.emit(cell, REJECT_LOCKED)
		return
	if not board_state.is_empty(cell.x, cell.y):
		_bump_tile(cell)
		tap_rejected.emit(cell, REJECT_OCCUPIED)
		return
	cell_tapped.emit(cell)


# ---------------------------------------------------------------------------
# Resolution playback
# ---------------------------------------------------------------------------

func _run_resolution(placed_tile: Tile) -> void:
	is_resolving = true
	_generation += 1
	var generation := _generation
	resolution_started.emit()
	# Always yield once, including when animations are disabled. The controller
	# must finish charging the move and advancing the queue before completion.
	await get_tree().process_frame
	if not _is_current(generation):
		return

	# Pop-in for the placed tile.
	if is_instance_valid(placed_tile) and place_duration > 0.0:
		placed_tile.scale = Vector2(0.4, 0.4)
		var pop := _make_tween()
		pop.tween_property(placed_tile, "scale", Vector2.ONE, place_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await pop.finished
		if not _is_current(generation):
			return

	if gravity_after_placement:
		var initial_moves := board_state.apply_gravity()
		if not initial_moves.is_empty():
			await _animate_gravity(initial_moves)
			if not _is_current(generation):
				return

	# Compute the whole cascade up front (BoardState is now in its final,
	# stable state) and play the steps back one after another.
	var steps := cascade_resolver.resolve(board_state)
	var cleared_tiles := 0
	var cascade_count := 0
	for step in steps:
		match step["type"]:
			CascadeResolver.STEP_CLEAR:
				cascade_count += 1
				cleared_tiles += (step["cells"] as Array).size()
				await _animate_clear(step["cells"])
			CascadeResolver.STEP_GRAVITY:
				await _animate_gravity(step["moves"])
		if not _is_current(generation):
			return
		if step_pause > 0.0:
			await _wait(step_pause)
			if not _is_current(generation):
				return

	_sync_tile_layout()
	is_resolving = false
	resolution_finished.emit(cleared_tiles, cascade_count)


func _animate_clear(cells: Array) -> void:
	var tween := _make_tween()
	var tweened := 0
	for cell in cells:
		var tile: Tile = _tiles.get(cell)
		if tile == null:
			continue
		tween.tween_property(tile, "scale", Vector2.ZERO, clear_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(tile, "modulate:a", 0.0, clear_duration * 0.6) \
			.set_delay(clear_duration * 0.4)
		tweened += 1

	if tweened > 0:
		await tween.finished
	else:
		tween.kill()

	if not is_inside_tree():
		return
	for cell in cells:
		var tile: Tile = _tiles.get(cell)
		if tile == null:
			continue
		_tiles.erase(cell)
		tile.queue_free()


func _animate_gravity(moves: Array) -> void:
	var tween := _make_tween()
	var landed: Array = []
	for move in moves:
		var from := Vector2i(move["column"], move["from_row"])
		var to := Vector2i(move["column"], move["to_row"])
		var tile: Tile = _tiles.get(from)
		if tile == null:
			continue
		_tiles.erase(from)
		landed.append([to, tile])
		tile.grid_position = to
		tween.tween_property(tile, "position", get_slot_rect(to).position, fall_duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Re-insert after erasing everything so a tile can land on a cell that
	# another moving tile just vacated.
	for pair in landed:
		_tiles[pair[0]] = pair[1]

	if landed.is_empty():
		tween.kill()
		return
	await tween.finished


func _bump_tile(cell: Vector2i) -> void:
	var tile: Tile = _tiles.get(cell)
	if tile == null:
		return
	var tween := _make_tween()
	tween.set_parallel(false)
	tween.tween_property(tile, "scale", Vector2(1.12, 1.12), 0.06)
	tween.tween_property(tile, "scale", Vector2.ONE, 0.08)


# ---------------------------------------------------------------------------
# Tile node helpers
# ---------------------------------------------------------------------------

func _spawn_tile(cell: Vector2i, tile_type: int) -> Tile:
	var tile := Tile.new()
	tile.name = "Tile_%d_%d" % [cell.x, cell.y]
	tile.grid_position = cell
	_tile_layer.add_child(tile)
	tile.setup(tile_type)
	_place_tile_node(tile, cell)
	_tiles[cell] = tile
	return tile


func _place_tile_node(tile: Tile, cell: Vector2i) -> void:
	var rect := get_slot_rect(cell)
	tile.position = rect.position
	tile.size = rect.size
	tile.pivot_offset = rect.size * 0.5


## Snaps every tile node to the cell it logically occupies.
func _sync_tile_layout() -> void:
	for cell in _tiles.keys():
		var tile: Tile = _tiles[cell]
		if not is_instance_valid(tile):
			_tiles.erase(cell)
			continue
		_place_tile_node(tile, cell)
		tile.scale = Vector2.ONE
		tile.modulate.a = 1.0


# ---------------------------------------------------------------------------
# Layout & drawing
# ---------------------------------------------------------------------------

func _on_resized() -> void:
	if columns <= 0 or rows <= 0:
		return
	_cell_size = minf(size.x / float(columns), size.y / float(rows))
	var grid_size := Vector2(_cell_size * columns, _cell_size * rows)
	_grid_origin = ((size - grid_size) * 0.5).floor()

	var gap := _gap()
	_board_style.set_corner_radius_all(int(gap * 2.0))
	_slot_style.set_corner_radius_all(int(_cell_size * 0.16))

	_sync_tile_layout()
	queue_redraw()


func _draw() -> void:
	if _cell_size <= 0.0:
		return
	var gap := _gap()
	var grid_rect := Rect2(_grid_origin, Vector2(_cell_size * columns, _cell_size * rows))
	draw_style_box(_board_style, grid_rect.grow(gap))
	for row in range(rows):
		for column in range(columns):
			draw_style_box(_slot_style, get_slot_rect(Vector2i(column, row)))


func _gap() -> float:
	return _cell_size * cell_gap_ratio


# ---------------------------------------------------------------------------
# Tween / coroutine utilities
# ---------------------------------------------------------------------------

func _make_tween() -> Tween:
	_prune_tweens()
	var tween := create_tween()
	tween.set_parallel(true)
	_active_tweens.append(tween)
	return tween


func _prune_tweens() -> void:
	for i in range(_active_tweens.size() - 1, -1, -1):
		var tween := _active_tweens[i]
		if tween == null or not tween.is_valid() or not tween.is_running():
			_active_tweens.remove_at(i)


func _kill_active_tweens() -> void:
	for tween in _active_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_active_tweens.clear()


func _wait(seconds: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout


## A resolution is abandoned when the board was reset (generation changed)
## or removed from the tree while an animation was awaiting.
func _is_current(generation: int) -> bool:
	return generation == _generation and is_inside_tree()
