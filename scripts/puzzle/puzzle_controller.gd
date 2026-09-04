class_name PuzzleController
extends Control
## Glue between the HUD, the move budget, the tile queue and the BoardManager.
##
## Owns the "game state" of a single puzzle attempt: remaining moves, the
## current/next tile queue and whether the attempt is over. The board handles
## grid visuals and match resolution, this node decides *when* a tap counts as
## a move and keeps the UI labels in sync.

signal moves_changed(moves_left: int)
signal puzzle_over(reason: String)

const OVER_NO_MOVES := "no_moves"
const OVER_BOARD_FULL := "board_full"

@export var starting_moves: int = PuzzleRules.STARTING_MOVES
## Set >= 0 to make the tile sequence reproducible (debugging / tests).
@export var queue_seed: int = -1

@onready var board: BoardManager = %Board
@onready var moves_value_label: Label = %MovesValue
@onready var status_label: Label = %StatusLabel
@onready var current_tile_preview: Control = %CurrentTilePreview
@onready var next_tile_preview: Control = %NextTilePreview
@onready var restart_button: Button = %RestartButton

var moves_left: int = 0
var tile_queue: TileQueue
var is_over := false

var _current_preview_tile: Tile
var _next_preview_tile: Tile


func _ready() -> void:
	tile_queue = TileQueue.new(TileTypes.all(), queue_seed)
	tile_queue.queue_changed.connect(_on_queue_changed)

	_current_preview_tile = _make_preview_tile(current_tile_preview)
	_next_preview_tile = _make_preview_tile(next_tile_preview)

	board.cell_tapped.connect(_on_board_cell_tapped)
	board.tap_rejected.connect(_on_board_tap_rejected)
	board.resolution_finished.connect(_on_board_resolution_finished)
	restart_button.pressed.connect(restart)

	restart()


## Fully resets the attempt: board, queue, moves and status.
func restart() -> void:
	board.reset_board()
	tile_queue.reset(queue_seed)
	is_over = false
	_set_moves(starting_moves)
	board.accepting_input = true
	_set_status("Tap an empty cell to place the tile.")


## True when the player may place a tile right now.
func can_place() -> bool:
	return not is_over and not board.is_resolving and moves_left > 0


func _on_board_cell_tapped(cell: Vector2i) -> void:
	if not can_place():
		return
	var tile_type := tile_queue.get_current()
	if not board.place_tile(cell, tile_type):
		return
	# Placement succeeded: it costs a move and advances the queue immediately
	# so the HUD shows what comes next while the cascade animates.
	tile_queue.pop_current()
	_set_moves(moves_left - 1)
	_set_status("Resolving...")


func _on_board_tap_rejected(_cell: Vector2i, reason: String) -> void:
	match reason:
		BoardManager.REJECT_BUSY:
			_set_status("Wait for the cascade to finish.")
		BoardManager.REJECT_OCCUPIED:
			if not is_over:
				_set_status("That cell is taken. Pick an empty one.")
		BoardManager.REJECT_LOCKED:
			pass  # Puzzle is over; the status already explains why.


func _on_board_resolution_finished(cleared_tiles: int, cascade_count: int) -> void:
	if is_over:
		return
	if moves_left <= 0:
		_finish(OVER_NO_MOVES)
		return
	if board.board_state.is_full():
		_finish(OVER_BOARD_FULL)
		return

	if cleared_tiles > 0:
		if cascade_count > 1:
			_set_status("Cascade x%d! Cleared %d tiles." % [cascade_count, cleared_tiles])
		else:
			_set_status("Cleared %d tiles." % cleared_tiles)
	else:
		_set_status("Tap an empty cell to place the tile.")


func _finish(reason: String) -> void:
	is_over = true
	board.accepting_input = false
	match reason:
		OVER_NO_MOVES:
			_set_status("Out of moves! %d tiles left on the board. Tap Restart." % board.board_state.count_tiles())
		OVER_BOARD_FULL:
			_set_status("The board is full! Tap Restart to try again.")
	puzzle_over.emit(reason)


func _on_queue_changed(current_tile: int, next_tile: int) -> void:
	_current_preview_tile.setup(current_tile)
	_next_preview_tile.setup(next_tile)


func _set_moves(value: int) -> void:
	moves_left = maxi(0, value)
	moves_value_label.text = str(moves_left)
	moves_changed.emit(moves_left)


func _set_status(text: String) -> void:
	status_label.text = text


## Creates a Tile node that fills the given preview container.
func _make_preview_tile(container: Control) -> Tile:
	var tile := Tile.new()
	tile.name = "PreviewTile"
	container.add_child(tile)
	tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tile
