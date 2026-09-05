# Level data

`chapter_one.json` contains the six introductory campaign levels. IDs must be
consecutive, starting at 1. Each level supplies a title, hint, positive move
budget, clear goal and non-negative tile-queue seed. `LevelCatalog` validates
the entire file before the campaign starts. Retry resets that level's seed.

All current levels begin with an empty board and use the original five tile
types. The goal counts total cleared tiles, including cascades. Score does not
gate completion. The campaign logic tests verify a legal placement solution
for every level; run them whenever changing a goal, move budget or seed.
