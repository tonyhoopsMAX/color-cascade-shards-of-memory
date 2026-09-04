class_name Tile
extends Control
## Visual representation of a single coloured tile.
##
## Placeholder art: a rounded coloured panel drawn in code plus a centred symbol
## label, so no external textures are needed yet. The tile knows nothing about
## the grid or the rules; BoardManager owns placement, movement and removal.
## The same node is reused for the "current" / "next" previews in the HUD.

const RIM_DARKEN := 0.35
const CORNER_RATIO := 0.18
const RIM_RATIO := 0.06
const SYMBOL_FONT_RATIO := 0.42
const MIN_FONT_SIZE := 12

var tile_type: int = BoardState.EMPTY
## Grid cell this tile currently represents (set by BoardManager).
var grid_position := Vector2i(-1, -1)

var _label: Label
var _style_rim := StyleBoxFlat.new()
var _style_fill := StyleBoxFlat.new()
var _style_highlight := StyleBoxFlat.new()


func _init() -> void:
	# Taps must fall through to the board, never be swallowed by a tile.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_style_highlight.bg_color = Color(1, 1, 1, 0.22)

	_label = Label.new()
	_label.name = "Symbol"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	resized.connect(_on_resized)
	_on_resized()


## Configures the tile's colour and symbol from a TileTypes.Kind value.
func setup(p_tile_type: int) -> void:
	tile_type = p_tile_type
	var fill := TileTypes.color_of(tile_type)
	_style_fill.bg_color = fill
	_style_rim.bg_color = fill.darkened(RIM_DARKEN)
	_label.text = TileTypes.symbol_of(tile_type)
	queue_redraw()


func _on_resized() -> void:
	pivot_offset = size * 0.5

	var min_side := minf(size.x, size.y)
	var font_size := maxi(MIN_FONT_SIZE, int(min_side * SYMBOL_FONT_RATIO))
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.12)))

	var corner := min_side * CORNER_RATIO
	var rim := _rim_width()
	_style_rim.set_corner_radius_all(int(corner))
	_style_fill.set_corner_radius_all(int(maxf(0.0, corner - rim)))
	_style_highlight.set_corner_radius_all(int(maxf(0.0, corner - rim * 2.0)))
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var rim := _rim_width()
	var min_side := minf(size.x, size.y)

	# Darker rim, inner fill, then a soft highlight strip near the top.
	draw_style_box(_style_rim, rect)
	draw_style_box(_style_fill, rect.grow(-rim))

	var highlight := Rect2(
		rect.position + Vector2(rim * 2.0, rim * 2.0),
		Vector2(size.x - rim * 4.0, min_side * 0.16)
	)
	if highlight.size.x > 0.0 and highlight.size.y > 0.0:
		draw_style_box(_style_highlight, highlight)


func _rim_width() -> float:
	return maxf(2.0, minf(size.x, size.y) * RIM_RATIO)
