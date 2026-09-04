class_name PuzzleRules
extends RefCounted
## Compile-time constants describing the core puzzle rules.
##
## Kept in a plain class (not an autoload) so pure-logic scripts and headless
## tests can reference them without any scene-tree or load-order dependency.
## GameConfig (autoload) re-exports these for scene code.

## Board dimensions (portrait: fewer columns than rows).
const BOARD_COLUMNS := 7
const BOARD_ROWS := 8

## Minimum number of orthogonally connected tiles that form a clearable group.
const MIN_MATCH_SIZE := 3

## Moves available at the start of a puzzle.
const STARTING_MOVES := 20
