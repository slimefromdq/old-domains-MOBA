# Rules notes

How the prototype reads the design doc (`docs/design.md`), and the numbers it had to invent.
Every tunable number lives in `scripts/core/rules.gd` (or `scripts/core/heroes.gd` for hero kits).

## What's in this milestone

- **Turns:** simultaneous hot-seat turns. You pass the device, each player plans, then the turn plays back phase by phase.
- **Phases:** all six, in the doc's order. Hero A's delayed shots get their own step right after Move.
- **Heroes:** Hero A and Hero D, with full kits.
- **Minions:** melee, ranged and siege. Each one telegraphs its next move and target, and aggro can override that.
- **Tower and Base:** the Tower switches target to a hero who hit a hero. The Base can't be attacked while its Tower
  stands. When a Tower falls, its Base gets a shield and that side's next wave gets a siege minion.
- **Economy:** gold, XP, levels, bounty, the contested-kill rule, denies, Recall, respawn timers, sudden death and the
  turn-30 hard cap.
- **Fog of war:** vision radii, cover, last-known markers, hit reveals, and Area reveal (see "Fog of war" below).

**Not yet:** the neutral objective, items/shop (including the Vision item), Heroes B and C, bot, online play.
The objective spot is drawn on the map but does nothing yet.

**Temporary change:** Tower and Base HP are 15, not the doc's 30, while we test pacing.

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

## Fog of war

**From the doc:**
- **Vision:** you see tiles within 3 of your hero, 2 of your minions, and 3 of your Tower and Base. Distance is
  orthogonal, and walls don't block sight.
- **Cover:** a hero on a cover tile is hidden unless one of your units is orthogonally adjacent to it.
- **Last-known marker:** a hidden enemy hero leaves a "?" marker where you last saw it. It fades and disappears
  after 4 turns (the 4 is assumed).
- **Firing into fog:** attacking a tile you can't see is legal. Hitting a hidden hero reveals it for the rest of
  this turn and all of the next.
- **Area reveal (Hero A, level 3):** reveals a 3x3 area, including cover, from the Guard phase of this turn through
  the end of the next. Only the caster's side sees the zone.

**Interpretations:**
- **Structures are always visible**, along with their HP.
- **Cover only hides heroes.** Minions on cover tiles can be seen.
- **Minions, Towers and Bases only auto-target units their side can see.** A ranged minion can't shoot a hero hidden
  in cover; a melee minion is adjacent, so it spots the hero first. Aggro and Tower switching also need vision.
- **Attacking from fog does not reveal you.** The doc only says the *target* is revealed. Playback shows the hit as
  coming from "an unseen attacker".
- **Orders are judged against what the player could see.** Your planned path can run into a hidden unit. When it
  does, you stop on the last free tile before it.
- **Hero A's Multi-target strike** can only pick tiles A's side can currently see ("visible tiles" in the doc).
- **Hot-seat playback is public.** Both players watch the same screen, so playback only shows a unit if its
  *opponent* can see it. Your own hero hidden in cover won't appear on the shared screen. Events involving hidden
  units are reworded ("takes 3 from an unseen attacker") or left out. Each player sees their full fogged view while
  planning.

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

## Pacing signals (scripted bots)

The test bot is simple: it attacks the weakest thing in range, otherwise walks toward the enemy Tower.
- **Bot vs bot:** every match draws at turn 30 with no Tower down, even at 15 HP. Equal waves cancel out in mid, so
  this mostly shows the bots are mirror images of each other.
- **Bot vs a player who never acts:** the enemy Tower falls around turns 24-27, the Base is never hit, and the match
  is a **draw**. Both Bases are at full HP, and the hard cap only compares Base HP.

Two things to consider:
- Pushing may be too slow. Options: waves arrive faster, minions deal more damage to structures, or the turn cap
  goes up.
- Add a hard-cap tiebreaker, such as Towers standing, then total structure HP.
