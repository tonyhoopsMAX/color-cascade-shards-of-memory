class_name TileTypes
extends RefCounted
## Static catalogue of the five placeholder tile colours.
##
## Everything here is static/const so any script (scene code, pure logic or
## headless tests) can query tile visuals without depending on an autoload.
## The integer value of a Kind doubles as the value stored in BoardState.

enum Kind { RED, BLUE, GREEN, YELLOW, PURPLE }

const DEFINITIONS := {
	Kind.RED: {"name": "Red", "symbol": "R", "color": Color("e5484d")},
	Kind.BLUE: {"name": "Blue", "symbol": "B", "color": Color("3b82f6")},
	Kind.GREEN: {"name": "Green", "symbol": "G", "color": Color("22c55e")},
	Kind.YELLOW: {"name": "Yellow", "symbol": "Y", "color": Color("facc15")},
	Kind.PURPLE: {"name": "Purple", "symbol": "P", "color": Color("a855f7")},
}


## Every placeable tile type, in a stable ascending order.
static func all() -> Array[int]:
	var kinds: Array[int] = []
	for kind in DEFINITIONS.keys():
		kinds.append(kind)
	kinds.sort()
	return kinds


static func count() -> int:
	return DEFINITIONS.size()


static func is_valid(tile_type: int) -> bool:
	return DEFINITIONS.has(tile_type)


static func color_of(tile_type: int) -> Color:
	if DEFINITIONS.has(tile_type):
		return DEFINITIONS[tile_type]["color"]
	return Color.MAGENTA


static func symbol_of(tile_type: int) -> String:
	if DEFINITIONS.has(tile_type):
		return DEFINITIONS[tile_type]["symbol"]
	return "?"


static func name_of(tile_type: int) -> String:
	if DEFINITIONS.has(tile_type):
		return DEFINITIONS[tile_type]["name"]
	return "Unknown"
