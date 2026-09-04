class_name TileQueue
extends RefCounted
## Produces the "current" and "next" tiles the player places.
##
## Keeps a small look-ahead so the UI can preview the upcoming tile. Uses its
## own RandomNumberGenerator so a seed can be supplied for deterministic tests.

signal queue_changed(current_tile: int, next_tile: int)

const LOOKAHEAD := 2

var _rng := RandomNumberGenerator.new()
var _tile_types: Array[int] = []
var _queue: Array[int] = []


func _init(tile_types: Array[int], seed_value: int = -1) -> void:
	_tile_types = tile_types.duplicate()
	if _tile_types.is_empty():
		push_error("TileQueue created without any tile types.")
		_tile_types = [0]
	reset(seed_value)


## Clears and refills the queue. Pass a seed >= 0 for reproducible sequences.
func reset(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_queue.clear()
	_refill()
	queue_changed.emit(get_current(), get_next())


## The tile the player will place on their next tap.
func get_current() -> int:
	return _queue[0]


## The tile that will become current after the next placement.
func get_next() -> int:
	return _queue[1]


## Removes and returns the current tile, advancing the queue.
func pop_current() -> int:
	var tile := _queue.pop_front() as int
	_refill()
	queue_changed.emit(get_current(), get_next())
	return tile


func _refill() -> void:
	while _queue.size() < LOOKAHEAD:
		_queue.append(_tile_types[_rng.randi_range(0, _tile_types.size() - 1)])
