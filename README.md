# Old Domains MOBA

A 1v1, single-lane, simultaneous-turn MOBA prototype in **Godot 4.7** (GDScript, 3D).
Design: [`docs/design.md`](docs/design.md). How the prototype reads it: [`docs/rules-notes.md`](docs/rules-notes.md).

## Opening it

1. `git clone https://github.com/slimefromdq/old-domains-MOBA.git`
2. Godot Project Manager -> **Import** -> pick `project.godot` in the clone.
3. Press **F5**.

## Playing

Pick **Play vs AI** (you are West; a simple bot plays East from what East can see) or **Hot-seat** (two players, one device).

1. Pick a hero (**Hero A**: ranged, delayed shots; **Hero D**: tank, tether).
2. Plan your turn: one Move and one Action. Nothing happens until both sides have planned; then the turn plays out.
   - Your hero has a pulsing ring. Click a **blue tile** to move there (a see-through copy shows where you'll end up).
     Click your hero to stay put.
   - Click an **enemy in range** to Basic Attack it, or press **1-6** / the buttons for other actions, then click
     **orange tiles** to target. Attacks hit *tiles*, not units.
   - Hero A's **Delayed shot** box makes the Basic Attack land after the Move phase (-1 damage).
   - Each action button shows what it does, which phase it lands in, and what it costs (cooldown, or your Move for Recall).
     **0 / Just move** skips the action: moving without attacking is always allowed.
   - The phase bar at the top shows the turn order and highlights where your Move and Action happen.
     During playback it lights up the phase being shown.
   - The corner chips show each hero's level, HP, Tower, Base and gold. Hover a chip or a hero on the board for
     the full card. Press **L** for the match log.
     Targeted tiles preview the damage, and the panel says what's there and whether it dies.
   - **Space** or **Enter** ends the turn. **Esc** or right-click cancels.
   - Hot-seat only: West plans, then the device is passed and East plans. Neither sees the other's orders.
3. The turn plays back phase by phase: Guard -> Dash -> Attack -> Move -> Minions -> Tower & Base -> Upkeep.
   Vs AI it plays automatically; **Space** steps forward, or use Auto / Skip.

Camera: **mouse wheel** zooms, **middle-drag** orbits, **Q / E** turn 45 degrees, **R** resets the view.
You can click a unit's model or the tile under it; both pick that tile.

Fog of war:
- You see 3 tiles around your hero, Tower and Base, and 2 around your minions. Darkened tiles are fog.
- A hero on a cover tile (grass) is hidden unless one of your units stands next to it.
- A **?** marks where you last saw the enemy hero.
- You can attack fogged tiles. Hitting a hidden hero reveals it.
- Hot-seat playback is shared, so it only shows a unit when its opponent can see it. Vs AI, playback shows what you see.

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
  enemy_ai.gd        The vs-AI bot: plans one hero's orders from its own side's view
  vision.gd          Fog of war: who sees what, per-player and public views
  heroes.gd          Hero kits
  rules.gd           Every tunable number
  map_data.gd        The lane layout
  unit.gd, orders.gd Data types
scripts/view/        The 3D board and the order panel
  board_view.gd      Camera, clicks, animation, 2D labels (HP bars, damage numbers) on top
  board_models.gd    Low-poly tiles and unit models built from primitive meshes
  board_overlay.gd   Flat ground markings: move/target tiles, fog, arrows, crosshairs, attack arcs
scripts/main.gd      Match flow: mode -> pick -> plan (vs AI, or pass + plan x2 hot-seat) -> playback
tests/run_tests.gd   Rules tests, including the design doc's worked example
```

## Tests

```
godot --headless --path . --import          # first time only
godot --headless --path . -s tests/run_tests.gd
```
