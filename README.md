# Color Cascade: Shards of Memory

A portrait, Android-first tile-placement puzzle game built with **Godot 4.x**
and **GDScript**. No paid dependencies, no networking, no backend, no ads, no
analytics, no plugins.

This branch adds **milestone 2: an introductory six-level campaign** to the
existing playable core. It includes clear goals, scoring, win/retry/next-level
flow, an unlocked-level picker and local progress saves. Story scenes, the
exploration hub, journal, boosters, audio and final pixel art remain future work.

The original prototype is preserved at `scenes/puzzle/puzzle_scene.tscn`; the
new main scene wraps it with campaign functionality. The existing placement
rules have not changed: this is **tile placement, not tile swapping**.

## Requirements

| Item | Requirement |
| --- | --- |
| Engine | Godot **4.4 or newer** (standard build, no C#/Mono needed). CI targets 4.4.1. See the GitHub Actions run for actual validation status. |
| Development OS | Windows, Linux or macOS (the project is desktop-runnable for testing). |
| Target | Android, portrait orientation. |

## Opening the project

1. Install Godot 4.4+ from <https://godotengine.org/download>.
2. Launch Godot → **Import** → select this repository's `project.godot`
   (or drag the folder onto the Project Manager).
3. Open the project. The first import generates the ignored `.godot/` cache
   folder; this is expected.

## Running the game

* Press **F5** (Run Project) — the main scene is
  `res://scenes/campaign/campaign_scene.tscn`.
* The desktop window opens at 540 × 960 (a half-scale portrait phone). Resize it
  freely; the layout is container-based and re-flows.
* Mouse clicks are converted to touch input, so playing with a mouse on
  Windows behaves the same as tapping on Android.

### How to play

1. The HUD shows your level, clear goal, score, **MOVES LEFT**, **CURRENT** tile
   and **NEXT** tile.
2. Tap any **empty** cell to place the current tile there. That costs one move
   and advances the queue.
3. Any group of **3 or more same-colour tiles connected up/down/left/right**
   is cleared. Diagonal contact does **not** connect tiles.
4. Remaining tiles fall straight down. If the fall creates new groups they
   clear automatically (a *cascade*) until the board is stable. Input is locked
   while this resolves.
5. Meet the clear goal before running out of moves. A goal reached on the last
   move **wins**. Level one has 20 moves; later levels use their own budgets.
6. **Retry** resets the attempt with the same tile sequence. **Next** unlocks
   after a win. **Levels** lets you replay unlocked levels; choosing one starts
   a fresh attempt. Back to puzzle closes the menu without resetting it.

### Campaign, score and saves

| Level | Title | Moves | Clear goal |
| --- | --- | ---: | ---: |
| 1 | First Light | 20 | 6 |
| 2 | Small Sparks | 22 | 9 |
| 3 | Forest Echo | 25 | 12 |
| 4 | Falling Colors | 28 | 15 |
| 5 | Chain Reaction | 30 | 18 |
| 6 | A Brighter Tomorrow | 36 | 24 |

Scoring: **10 points per cleared tile + 50 points for each extra clear wave
in the same placement**. A two-wave, seven-tile cascade is worth 120 points.
Scores are for replay improvement; level completion depends on the clear goal.
The campaign tests construct a legal solution for each seeded level.

Unlocked levels, selected level and best scores are saved locally in
`user://campaign_progress.json`, with a previous-save `.bak` recovery file.
Retries never lower a best score or remove an unlock. Invalid save data is
rejected; the game tries the backup and otherwise starts at level one with a
warning. Write failures show a visible warning while play remains available.
There is no cloud sync, and **an unfinished board is not resumed after closing
the app**. Uninstalling or clearing application data may remove saved progress.

### New campaign files

* `data/levels/chapter_one.json`: validated, seedable level definitions.
* `scripts/campaign/level_catalog.gd`: content loading and validation.
* `scripts/campaign/puzzle_attempt.gd`: pure scoring and goal tracking.
* `scripts/campaign/progress_store.gd`: versioned progress and backup recovery.
* `scripts/campaign/campaign_controller.gd`: campaign HUD, menu and level flow.
* `scenes/campaign/campaign_scene.tscn`: campaign wrapper of the original scene.
* `tests/test_campaign_logic.gd` and `tests/test_campaign_scene.gd`: new tests.
* `.github/workflows/godot-tests.yml`: import checks and all four test suites.

## Project structure

```text
/
├── project.godot                  Godot 4 project (portrait 1080×1920, canvas_items/expand stretch)
├── README.md
├── .gitignore
├── autoload/
│   └── game_config.gd             "GameConfig" singleton: rules + tile catalogue accessors
├── scenes/
│   └── puzzle/
│       └── puzzle_scene.tscn      Main scene: HUD + board + footer (container layout)
├── scripts/
│   └── puzzle/
│       ├── puzzle_rules.gd        Constants: 7 columns, 8 rows, match size 3, 20 moves
│       ├── tile_types.gd          The five tile colours (name, symbol, colour)
│       ├── board_state.gd         Pure grid data model + gravity
│       ├── match_detector.gd      Orthogonal flood-fill group detection (no diagonals)
│       ├── cascade_resolver.gd    match → clear → gravity loop until stable
│       ├── tile_queue.gd          Current / next tile queue (seedable RNG)
│       ├── tile.gd                Placeholder tile visual (code-drawn rounded panel + symbol)
│       ├── board_manager.gd       Grid drawing, tap → cell, tile nodes, animated playback, input lock
│       └── puzzle_controller.gd   Move counter, queue, HUD, restart, game-over
├── assets/
│   ├── placeholder/icon.svg       Placeholder app icon (code-friendly SVG)
│   ├── ui/puzzle_theme.tres       Theme: font sizes, button/panel styles, HUD variations
│   └── tiles/                     Reserved for future tile art
├── data/
│   └── levels/                    Reserved for future level definitions
└── tests/
    ├── test_puzzle_logic.gd       Headless unit tests for the rules
    └── test_puzzle_scene.gd       Headless integration tests for the real scene
```

### Architecture notes

* **Logic is separated from presentation.** `BoardState`, `MatchDetector`,
  `CascadeResolver` and `TileQueue` are plain `RefCounted` classes with no
  nodes, timers or rendering, so they are deterministic and unit-testable.
* `CascadeResolver.resolve()` computes the *entire* cascade up front and
  returns an ordered list of `clear` / `gravity` steps. `BoardManager` then
  plays those steps back with tweens. The logical board is always in its final
  state before any animation starts, which is what makes the input lock and
  mid-cascade restart safe.
* `BoardManager` sets `is_resolving` while animating; `PuzzleController`
  refuses taps until it is cleared. `reset_board()` bumps a generation counter
  so an abandoned coroutine can never touch a freshly reset board.
* UI uses `MarginContainer` → `VBoxContainer` → `HBoxContainer` /
  `AspectRatioContainer` (7:8) with theme-driven font sizes. Nothing is
  pixel-positioned; the board takes whatever space remains between the HUD and
  the footer and keeps its aspect ratio at any phone resolution.

## Original core features (preserved)

* Valid Godot 4 project, portrait 1080 × 1920 reference resolution, `canvas_items`
  stretch with `expand` aspect so different Android aspect ratios add space
  instead of cropping.
* 7 × 8 board with clearly visible slots, centred and aspect-locked.
* Five placeholder tile types (red, blue, green, yellow, purple) with letter
  symbols, drawn with Godot controls/StyleBoxes only.
* Current + next tile queue with on-screen previews.
* Tap an empty cell to place the current tile; consumes a move; queue advances.
* Match rule: 3+ orthogonally connected same-colour tiles. Diagonals never count.
* Clear animation, gravity (tiles never overlap; empties stay above), automatic
  cascades until stable.
* Input locked during placement/cascade resolution; occupied cells are rejected
  without spending a move.
* 20-move counter with a clear on-screen value; out-of-moves and board-full
  end states.
* Restart button that fully resets board, tiles, queue, moves and cascade state
  (safe even mid-cascade).
* Headless test suites covering all of the above.

## Running the tests (optional)

Requires a Godot 4.4+ executable on your `PATH` (any standard build works):

```bash
# Pure rules: board state, gravity, matches, no-diagonals, cascades, queue
godot --headless --path . --script res://tests/test_puzzle_logic.gd

# Real scene: tap input, move counter, queue, input lock, clear/gravity/cascade, restart, layout fit
godot --headless --path . --script res://tests/test_puzzle_scene.gd

# Level definitions, scoring, legal solutions and save/backup validation
godot --headless --path . --script res://tests/test_campaign_logic.gd

# Campaign UI, last-move wins, retry/next, unlocks and phone-size layout
godot --headless --path . --script res://tests/test_campaign_scene.gd
```

Each run prints `PASS`/`FAIL` lines and exits with code 0 on success.
If the scripts cannot find the class names on a fresh clone, open the project
once in the editor (or run `godot --headless --path . --import`) so Godot
generates its script class cache first.

CI imports the project first, rejects script errors, runs all four suites with
timeouts and preserves logs. The new tests use isolated save filenames, not
the player's save. A GitHub source ZIP is a **Godot project, not an Android APK**.

## Current limitations

* Six introductory puzzle levels only; no playable story, exploration hub,
  journal, memory system, boosters, audio, ads or monetisation yet.
* Visuals are code-drawn placeholders (flat colours + letters); final pixel art
  comes later. The app icon is a placeholder SVG.
* Tile sequence is uniformly random with a fixed per-level seed (no bag or
  difficulty shaping). Difficulty and final artwork still need playtesting.
* A freshly placed tile stays where it is tapped (it does not drop) unless a
  clear triggers gravity; this is configurable via `gravity_after_placement`
  on the Board node.
* No Android export preset is committed yet (`export_presets.cfg` is ignored);
  add one via **Project → Export** when you are ready to build an APK.
