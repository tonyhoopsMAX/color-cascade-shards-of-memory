# Level data

Reserved for future chapter/level definitions.

The current prototype has a single endless-style puzzle attempt with no level
files. `BoardState.load_from_strings()` already accepts a top-row-first string
pattern (digits = `GameConfig.TileType`, `.` = empty) so hand-authored starting
boards can be added here later without changing the puzzle systems.
