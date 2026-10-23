# Old Domains MOBA

A turn-based MOBA prototype built in **Godot 4.5** (GDScript, 2D, Compatibility renderer).

## Opening it in Godot

1. Clone the repo: `git clone https://github.com/slimefromdq/old-domains-MOBA.git`
2. In the Godot Project Manager choose **Import**, then select `project.godot` in the cloned folder.
3. Press **F5** to play.

If you already have a local Godot project named `old-domains-MOBA`, copy any assets you want to keep into the
cloned folder and use the clone from then on. That way the Godot project and the Git repo are the same folder.

## How to play (current prototype)

Two players, one machine (hotseat). Blue starts in the bottom-left, Red in the top-right. There are three lanes:
top, mid (the diagonal) and bot, with a jungle between them.

- **Click** one of your heroes to select it. Blue tiles show where it can move; red outlines show enemies it can hit.
- Each hero gets **one move and one attack per turn**, in either order.
- **Space / Enter** ends the turn. **Tab** selects the next hero. **Esc / right-click** deselects.
- **Hover** over any unit to see its stats and attack range.
- When your turn ends, your towers and core fire first, then your minions march down their lanes and attack.
- Both teams get a new minion wave every 3 rounds.
- Dead heroes respawn at base after 3 of their team's turns.
- A **core is shielded** while any of its team's towers stand. Destroy the enemy core to win. Press **R** to restart.

| Unit   | HP | ATK | Range | Move |
|--------|----|-----|-------|------|
| Warden | 32 | 6   | 1     | 3    |
| Ranger | 22 | 5   | 2     | 3    |
| Minion | 10 | 3   | 1     | 2    |
| Tower  | 40 | 6   | 2     | -    |
| Core   | 60 | 4   | 2     | -    |

Distance is counted in king moves (diagonals count as 1).

## Code layout

```
scripts/core/      Game rules. No rendering or input.
  game_state.gd    Turn flow, movement, combat, minion/tower AI, win check
  map_data.gd      Map layout (ASCII), bases, towers, lanes. Red side is mirrored from Blue
  unit.gd          Unit data
  unit_defs.gd     Stats table. Edit balance numbers here
scripts/view/
  board_view.gd    Draws the board with placeholder shapes and turns clicks into grid cells
scripts/main.gd    Connects the rules, the board and the side panel
scenes/main.tscn   Main scene
tests/run_tests.gd Headless rules tests
```

The rules (`GameState`) know nothing about the screen. That makes them easy to test and easy to drive from AI or
networking later.

## Running tests

```
godot --headless --path . --import          # first time only, builds the class cache
godot --headless --path . -s tests/run_tests.gd
```
