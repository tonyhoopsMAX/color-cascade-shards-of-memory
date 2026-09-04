class_name CascadeResolver
extends RefCounted
## Resolves a board to a stable state: match -> clear -> gravity -> repeat.
##
## This class is pure logic. It mutates the BoardState it is given and returns a
## list of "steps" describing what happened, in order, so that the scene layer
## (BoardManager) can play them back with animation. Because the whole cascade
## is computed up front, the result is deterministic and easy to unit-test.
##
## Step dictionary shapes:
##   {"type": "clear", "cells": Array[Vector2i], "groups": Array}
##   {"type": "gravity", "moves": Array[Dictionary]}   # see BoardState.apply_gravity
##
## A cascade with no matches returns an empty step list.

const STEP_CLEAR := "clear"
const STEP_GRAVITY := "gravity"

## Safety valve: a board can never cascade more times than it has cells, but
## keep a hard cap anyway to guarantee termination if logic ever regresses.
const MAX_ITERATIONS := 256

var match_detector: MatchDetector


func _init(p_match_detector: MatchDetector = null) -> void:
	match_detector = p_match_detector if p_match_detector != null else MatchDetector.new()


## Fully resolves the board. Returns the ordered list of steps that were applied.
func resolve(board: BoardState) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var iterations := 0
	while iterations < MAX_ITERATIONS:
		iterations += 1
		var groups := match_detector.find_matches(board)
		if groups.is_empty():
			break

		var cells := _unique_cells(groups)
		for cell in cells:
			board.clear_cell(cell.x, cell.y)
		steps.append({"type": STEP_CLEAR, "cells": cells, "groups": groups})

		var moves := board.apply_gravity()
		if not moves.is_empty():
			steps.append({"type": STEP_GRAVITY, "moves": moves})
		# Loop again: gravity may have created new adjacencies (a cascade).

	if iterations >= MAX_ITERATIONS:
		push_error("CascadeResolver hit MAX_ITERATIONS; board may not be stable.")
	return steps


## Number of clear steps in a step list (i.e. how many cascade "waves" happened).
static func count_clears(steps: Array[Dictionary]) -> int:
	var count := 0
	for step in steps:
		if step["type"] == STEP_CLEAR:
			count += 1
	return count


## Total tiles removed across every clear step.
static func count_cleared_tiles(steps: Array[Dictionary]) -> int:
	var count := 0
	for step in steps:
		if step["type"] == STEP_CLEAR:
			count += (step["cells"] as Array).size()
	return count


func _unique_cells(groups: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var seen := {}
	for group in groups:
		for cell in group:
			if not seen.has(cell):
				seen[cell] = true
				cells.append(cell)
	return cells
