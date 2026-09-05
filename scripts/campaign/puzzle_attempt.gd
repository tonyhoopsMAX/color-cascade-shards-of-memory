class_name PuzzleAttempt
extends RefCounted
## Scoring for one attempt, independent of nodes, animation and persistence.

const POINTS_PER_TILE := 10
const EXTRA_WAVE_BONUS := 50

var clear_goal: int
var cleared_tiles := 0
var score := 0
var best_cascade := 0


func _init(goal: int) -> void:
	clear_goal = maxi(1, goal)


func record_resolution(cleared: int, waves: int) -> void:
	if cleared <= 0 or waves <= 0:
		return
	cleared_tiles += cleared
	score += cleared * POINTS_PER_TILE + maxi(0, waves - 1) * EXTRA_WAVE_BONUS
	best_cascade = maxi(best_cascade, waves)


func is_won() -> bool:
	return cleared_tiles >= clear_goal
