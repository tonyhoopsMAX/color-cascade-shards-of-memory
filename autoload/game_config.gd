extends Node
## Global gameplay configuration, registered as the "GameConfig" autoload.
##
## Central place for scene code to read the puzzle tunables (PuzzleRules) and
## the tile catalogue (TileTypes). Later milestones can layer per-level
## overrides on top of these defaults here without touching the puzzle systems.

## Grid value used for an empty cell (mirrors BoardState.EMPTY).
const EMPTY := -1

const BOARD_COLUMNS := PuzzleRules.BOARD_COLUMNS
const BOARD_ROWS := PuzzleRules.BOARD_ROWS
const MIN_MATCH_SIZE := PuzzleRules.MIN_MATCH_SIZE
const STARTING_MOVES := PuzzleRules.STARTING_MOVES


## Returns every placeable tile type in a stable order.
func get_tile_types() -> Array[int]:
	return TileTypes.all()


func get_tile_color(tile_type: int) -> Color:
	return TileTypes.color_of(tile_type)


func get_tile_symbol(tile_type: int) -> String:
	return TileTypes.symbol_of(tile_type)


func get_tile_name(tile_type: int) -> String:
	return TileTypes.name_of(tile_type)
