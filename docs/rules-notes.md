# Rules notes

How the prototype reads the design doc (`docs/design.md`), and the numbers it had to invent.
Every tunable number lives in `scripts/core/rules.gd` (or `scripts/core/heroes.gd` for hero kits).

## What's in this milestone

- **Turns:** simultaneous hot-seat turns. You pass the device, each player plans, then the turn plays back phase by phase.
- **Phases:** all six, in the doc's order. Hero A's delayed shots get their own step right after Move.
- **Heroes:** Hero A and Hero D, with full kits. The one exception is A's *Area reveal*, which needs fog of war.
- **Minions:** melee, ranged and siege. Each one telegraphs its next move and target, and aggro can override that.
- **Tower and Base:** the Tower switches target to a hero who hit a hero. The Base can't be attacked while its Tower
  stands. When a Tower falls, its Base gets a shield and that side's next wave gets a siege minion.
- **Economy:** gold, XP, levels, bounty, the contested-kill rule, denies, Recall, respawn timers, sudden death and the
  turn-30 hard cap.

**Not yet:** fog/cover effects, the neutral objective, items/shop, Heroes B and C, bot, online play.
Cover tiles and the objective spot are drawn on the map but do nothing yet.

## Map

```
col:    0 1 2 3 4 5 6 7 8 9 A B C
row 0   # # # # # . o . # # # # #     pocket (o = objective spot)
row 1   f . . . c . . . c . . . f
row 2   B S T . . . . . . . T S B
row 3   f . . . c . . . c . . . f
```

- **Cover at col 4, not col 3.** With orthogonal range 2, col 3 is inside your own Tower's range, which would make
  it a safe turtling spot. At col 4 it sits just outside, so it's a forward tile both players fight over.
- **Fountain (f):** the tiles beside each Base. Heroes start, respawn and Recall here; the shop will live here too.

## Interpretations

- **Distance is orthogonal (Manhattan)** for movement, ranges, "adjacent", aggro radius and XP radius.
- **Range is checked when orders are locked in, not again during resolution.**
  - A pushed hero's attack still lands on its tile, as the worked example requires.
  - A delayed shot's range is measured from the hero's *planned* Move destination.
- **Pushed heroes lose their Move.** A hero displaced by Dash push before the Move phase doesn't move that turn.
- **Movement is blocked by where enemy units stood when the Move phase began.** You can walk through allied minions
  but can't end on them. If two heroes would end on the same tile, both stop one tile short.
- **Minion telegraphs:** planning runs the exact function the Minions phase uses, so a telegraph only changes if the
  board changes or aggro triggers. A yellow **!** means an enemy hero is close enough to trigger aggro.
  - Ties are broken by distance, then lowest HP, then oldest.
  - Minions move one at a time, West and East alternating; their attacks land together.
- **Aggro trigger:** an enemy hero hits an allied hero while standing within 2 tiles of the minion.
- **Tower switch trigger:** the attacking hero was inside the Tower's range when it hit an allied hero.
- **Heroes vs. structures:** heroes deal half damage, rounded down, minimum 1.
- **The Base** deals 2 to heroes and 1 to minions. It fires every turn, even while protected.
- **Tower-loss shield:** absorbs damage before Base HP. The hard cap compares Base HP only, not the shield.
- **Contested kills:** a minion that dies in a phase where both heroes hit it gives no last-hit gold. Contests only
  count within a single phase (Attack, or After Move).
- **Denies:** heroes can attack their own minions. That gives nobody gold, but enemy heroes nearby still get XP.
- **Hero kill credit:** the enemy hero gets the kill gold if it damaged the victim at any point that turn, even when a
  minion or Tower lands the final hit.
- **Cooldown N:** an ability used on turn t is ready again on turn t+N. Abilities go on cooldown when ordered, even if
  they miss.
- **Respawn:** a hero who dies on turn t sits out turns t+1 and t+2 (and t+3 from level 4).
- **Tether:** deals no damage when applied. It triggers at most once (4 damage), then breaks.
- **Follow lock:**
  - D copies the target's move offset; if that tile is blocked, D takes the free tile next to the target that's
    closest to D.
  - D's own Move is ignored while locked, and D can't be pushed.
  - The lock lasts the turn it's cast plus the next turn.
- **Level-ups** add +2 to both max HP and current HP.

## Invented numbers (tune in playtests)

| What | Value |
| --- | --- |
| XP per enemy minion death within 3 tiles | 2 (siege 4) |
| XP for a hero kill | 6 (x1.5 if the victim was higher level) |
| Total XP for levels 2-6 | 6 / 14 / 24 / 34 / 46 |
| Base damage to minions | 1 |

## First pacing signal

Simple scripted bots (attack the weakest thing in range, otherwise walk toward the enemy Tower) drew every test match
at the turn-30 cap without either Tower falling. Bots that dumb say little about real play. Still, watch for it in
playtests: if real games stall too, sudden death may need to ramp harder, or towers may need less HP.
