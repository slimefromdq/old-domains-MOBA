# Old Domains MOBA

A 1v1, single-lane, simultaneous-turn MOBA prototype in **Godot 4.7** (GDScript, 3D).
Design: [`docs/design.md`](docs/design.md). How the prototype reads it: [`docs/rules-notes.md`](docs/rules-notes.md).

## Opening it

1. `git clone https://github.com/slimefromdq/old-domains-MOBA.git`
2. Godot Project Manager -> **Import** -> pick `project.godot` in the clone.
3. Press **F5**.

## Playing (hot-seat)

1. Each side picks a hero (**Hero A**: ranged, delayed shots; **Hero D**: tank, tether).
2. Each turn, West plans, then the device is passed and East plans. Neither sees the other's orders.
   - Click a **blue tile** to Move (click your hero to stay put).
   - Pick an **Action**, then click **orange tiles** to target it. Attacks hit *tiles*, not units.
   - Hero A's **Delayed shot** box makes the Basic Attack land after the Move phase (-1 damage).
   - **Enter** locks in. **Esc** or right-click cancels.
3. The turn plays back phase by phase: Guard -> Dash -> Attack -> Move -> Minions -> Tower & Base -> Upkeep.
   **Space** steps forward, or use Auto / Skip.

Camera: **mouse wheel** zooms, **middle-drag** orbits, **Q / E** turn 45 degrees, **R** resets the view.
You can click a unit's model or the tile under it; both pick that tile.

Fog of war:
- You see 3 tiles around your hero, Tower and Base, and 2 around your minions. Darkened tiles are fog.
- A hero on a cover tile (grass) is hidden unless one of your units stands next to it.
- A **?** marks where you last saw the enemy hero.
- You can attack fogged tiles. Hitting a hidden hero reveals it.
- Playback is shared, so it only shows a unit when its opponent can see it.

Reading the board:
- Arrows from minions show where they'll move next turn. Dashed lines and crosshairs show what each minion and
  structure will hit.
- A yellow **!** means aggro could change that.
- Attacks resolve **before** movement, so moving never dodges; only a dash does.

## Code layout

```
scripts/core/        Rules. Pure data and functions, no nodes.
  resolver.gd        resolve(state, west_orders, east_orders) -> new state + events + per-phase snapshots
  match_state.gd     The full game state (clonable)
  legality.gd        Legal moves/targets; cleans up illegal orders
  minion_ai.gd       Minion + structure decisions and telegraphs
  vision.gd          Fog of war: who sees what, per-player and public views
  heroes.gd          Hero kits
  rules.gd           Every tunable number
  map_data.gd        The lane layout
  unit.gd, orders.gd Data types
scripts/view/        The 3D board and the order panel
  board_view.gd      Camera, clicks, animation, 2D labels (HP bars, damage numbers) on top
  board_models.gd    Low-poly tiles and unit models built from primitive meshes
  board_overlay.gd   Flat ground markings: move/target tiles, fog, arrows, crosshairs, attack arcs
scripts/main.gd      Hot-seat flow: pick -> pass -> plan x2 -> playback
tests/run_tests.gd   Rules tests, including the design doc's worked example
```

## Tests

```
godot --headless --path . --import          # first time only
godot --headless --path . -s tests/run_tests.gd
```
