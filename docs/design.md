# Turn-Based MOBA — Design Document

Oct 22, 2026 · @Lucy

## Overview

A 1v1, single-lane MOBA played in simultaneous turns. Both players lock in orders each turn, then the turn resolves in a fixed phase order. A match runs about 20 turns, roughly 12–15 minutes. Every name in this document is a functional placeholder.

**Core experience.** Players win by predicting each other — when the opponent will dodge, contest a last hit or retreat — and by manipulating a shared minion wave so the opponent's mistakes compound.

**Why turn-based.** Real-time MOBAs test execution; this tests prediction. Turn-based play also removes the most expensive parts of building a MOBA: netcode, lag compensation, animation feel and a large art budget. Each turn is a deterministic function of two sets of orders, so the game is testable, replayable and buildable by one person.

## Design pillars

Five rules settle design arguments; an idea that conflicts with one of them is cut.

1. **Every turn is a read.** Both players lock in at the same time. No turn should have a best move that ignores what the opponent might do.
2. **Movement is a commitment.** Attacks resolve before movement, so where a hero ends the turn is where it can be hit next turn. Only dashes dodge.
3. **Minions are a shared puzzle.** Minions follow visible rules and telegraph their next action one turn ahead. Both players can manipulate the wave.
4. **Small enough to finish.** One lane, one neutral objective, four heroes, six items. Every addition has to justify itself against this pillar.
5. **A full arc in every match.** Laning, a first tower, an objective fight, a push, a comeback window and an ending, all in about 20 turns.

## Match structure

A player wins by destroying the enemy Base, which can only be attacked after the enemy Tower falls. All numbers are starting values to tune in playtests.

| Element | Starting value |
| --- | --- |
| Players | 1v1 (2v2 is a later mode) |
| Target length | About 20 turns, 12–15 minutes |
| Turn timer | 30 s ranked, 60 s casual, 24 h async |
| Minion waves | Every 3 turns, starting turn 1 |
| Neutral objective | Appears turn 6; respawns 6 turns after it is taken |
| Sudden death | Starts turn 20 |
| Hard cap | Turn 30: higher Base HP wins; a tie is a draw |

**Sudden death** guarantees an ending. From turn 20, every wave spawns one extra minion, and all minions gain +1 damage for each wave since sudden death began. Defending under the Tower stops being viable.

## The turn

Both players secretly lock in orders, then the turn resolves in a fixed six-phase order. This order is the most important rule in the game; most of the strategy comes from it.

**Orders.** Each hero gets one **Move** (up to its Speed in tiles, default 2) and one **Action**: Basic Attack, an Ability, Guard or an item. Recall uses both.

**Resolution order:**

1. **Guard** — Guard (half damage this turn, rounded down) and other protective effects activate.
2. **Dash** — dash abilities move their heroes instantly. A dash uses the Action, so dodging costs the attack.
3. **Attack** — all attacks and abilities hit their target tiles at the same moment. Both heroes can die in the same phase.
4. **Move** — normal movement. Traps placed on tiles trigger here.
5. **Minions** — minions move and attack, then structures fire, exactly as telegraphed (see Minions and structures).
6. **Upkeep** — gold and XP are awarded, cooldowns tick down, respawn timers count down, and next turn's telegraphs appear.

**Targeting.** Attacks target tiles, not units. Whatever occupies the tile after the Dash phase is hit. If the opponent is visible, their tile is known, and the question is whether they will dash. If they are in fog or cover, the attacker is guessing.

**Why Attack comes before Move.** Normal movement never dodges an attack in the same turn; it only sets where the hero stands next turn. This makes every Move a commitment and dashes valuable. It also keeps each guess to a few meaningful options instead of a dozen possible tiles.

**Collisions.** Two units cannot share a tile. If two moves end on the same tile, both stop one tile short. Heroes cannot move through enemy units.

**Playback.** After both players lock in, the turn replays phase by phase with each phase labelled, so players can see what hit what and why.

## The map

One lane, 3 tiles wide and 13 long, plus a 3-tile pocket above mid-lane that holds the neutral objective. The map is mirrored left to right, so neither side has an advantage.

&#91;embedded content: Map · 3 × 13 lane with the objective pocket\]

Each side has a Base at its end, a Spawn tile beside it, and a Tower two tiles in. Cover tiles sit on both edges of the lane in front of each Tower; they are where ambushes and fog guesses happen.

The 3-tile width is deliberate: wide enough to dodge and flank, narrow enough that every guess stays meaningful.

## Minions and structures

Minions push automatically, follow rules both players can see, and telegraph their next action one turn ahead.

**Waves.** Every 3 turns each side spawns a wave on its Spawn tile: 2 melee minions and 1 ranged minion. Minions move 2 tiles a turn toward the enemy Base and stop when an enemy is in range.

| Minion | HP | Damage | Range | Gold for last hit |
| --- | --- | --- | --- | --- |
| Melee | 4 | 1 | 1 | 2 |
| Ranged | 3 | 1 | 2 | 3 |
| Siege (objective reward) | 8 | 3 to structures, 1 to units | 1 | 4 |

**Telegraphs.** At the start of planning, each minion shows its intent: the tile it will move to and the unit it will hit. Intents are computed from the current board, so players can plan around them and sometimes break them.

**Minion targeting, in priority order:**

1. **Aggro:** an enemy hero who attacks an allied hero while within 2 tiles of these minions. Telegraphs that could change this way show a warning mark.
2. The nearest enemy minion.
3. The nearest enemy hero.
4. The nearest enemy structure.

Aggro means harassing the opponent inside their wave costs HP.

**Tower.** 30 HP, range 2, deals 2 to minions and 4 to heroes. It targets minions first but always switches to an enemy hero who attacked an allied hero in its range. Its target is telegraphed. Minions deal full damage to structures and heroes deal half, so pushing happens through waves.

**Base.** 30 HP, attacks like a weaker Tower (2 damage to heroes), and cannot be targeted until its side's Tower falls. Heroes respawn and shop here.

**Neutral objective.** Sits in the pocket above mid-lane: 12 HP, deals 2 to any adjacent hero each turn. The contested-kill rule (see Economy) applies to it. Taking it adds a siege minion to the taker's next wave. Leaving lane to take it costs last hits, which is the trade-off it exists to create.

## Heroes and actions

Every hero uses the same template, so adding a hero means adding rule exceptions, not new systems.

**Stats:** HP, Speed (tiles per Move), Basic Attack (damage and range).

**Kit:**

- **Trait** — a passive that modifies one core rule: the contested-kill rule, attack timing, aggro or telegraphs.
- **Ability 1** — available from level 1.
- **Ability 2** — unlocks at level 3.
- **Ultimate** — unlocks at level 5, 8-turn cooldown.

**Ability format.** Every ability specifies its phase (Guard, Dash, Attack or Move), target shape (tile, line or area), range, effect and cooldown in turns. Phase matters most, because it determines what the ability can dodge, interrupt or be dodged by.

**Universal actions:**

- **Basic Attack** — Attack phase, any tile in range.
- **Guard** — Guard phase. Half damage this turn, and immune to forced movement.
- **Recall** — uses Move and Action. In Upkeep the hero moves to its Base, unless it took damage this turn. Easy to read, easy to punish.

## Economy, levels and items

Gold comes mostly from last hits, and the contested-kill rule makes every last hit contestable at a cost.

**Gold sources:**

- Last hits: 2 (melee), 3 (ranged), 4 (siege)
- Passive income: 1 gold per turn
- Hero kill: 8, plus the victim's bounty
- Tower: 6 to the side that destroys it

**Contested-kill rule.** If both heroes hit a minion in the same Attack phase and it dies, nobody gets the gold. Heroes can also kill their own minions to deny them. Contesting a last hit always works, but it spends the Action, so the hero does not attack the opponent or dash that turn.

**XP and levels.** A hero earns XP whenever an enemy minion dies within 3 tiles, regardless of who killed it, so staying in lane pays even when losing last hits. Levels run 1–6. Each level adds +2 max HP; levels 3 and 5 also add +1 Basic Attack damage and unlock Ability 2 and the Ultimate.

**Shop.** Buying is only possible while standing on the Base, which makes Recall a strategic choice. Two item slots; selling refunds half.

| Item | Cost | Effect |
| --- | --- | --- |
| Speed item | 8 | +1 Speed |
| Vision item | 8 | +1 vision range; see into adjacent cover |
| Damage item | 10 | +1 Basic Attack damage |
| Health item | 10 | +6 max HP |
| Wave item | 12 | The next 3 waves each spawn an extra melee minion |
| Guard item | 12 | While Guarding, take no damage from minions or structures |
| Heal (consumable, no slot) | 4 | Heal 2 per turn for 3 turns; ends if a hero deals damage to you |

## Vision and hidden information

Fog of war is required: with perfect information, a simultaneous-turn duel becomes solvable by calculation.

- Players see tiles within 3 of their hero, 2 of their minions, and 3 of their Tower and Base.
- A hero on a cover tile is hidden unless an enemy unit is adjacent to that tile.
- A hidden hero's last-known tile stays marked on the enemy's board and fades over time.
- Attacking an unseen tile is legal. Hitting a hidden hero reveals it for one turn.
- Traps and placed effects are visible only if their tile is in vision.

**Optional: hidden pre-match passive.** Before the match, each player secretly picks one of three small passives, revealed the first time it triggers. Not in the MVP; test once the base game works.

## Anti-snowball and comebacks

Turn-based play snowballs harder than real time: a gold lead is pure stat advantage, and the trailing player cannot outplay it mechanically. These rules keep the trailing player in the game without punishing the leader.

- **Bounty.** Each kill without dying adds +4 to a hero's bounty. The hero who kills them collects it.
- **Respawn cap.** Respawning takes 2 turns, 3 from level 4 on, never longer.
- **Underdog XP.** Killing a higher-level hero gives +50% XP.
- **Tower-loss shield.** When a side's Tower falls, its Base gains a 10-HP shield and its next wave spawns a siege minion.
- **Neutral objective.** One well-timed win there gives the trailing player a siege minion and a push.
- **Sudden death.** Late minion scaling prevents stalling: the leader has to close, and the trailing player keeps getting wave fights.

## Starter heroes

The MVP has four heroes, each built around one core rule it modifies.

### Hero A — ranged, delayed attacks

HP 18 · Speed 2 · Basic 3 damage, range 3.

- **Trait — Delayed shot.** May resolve its Basic Attack after the Move phase instead, at −1 damage. The only hero that can hit a tile an opponent moved to.
- **Root shot** (Attack, range 3, cooldown 3). 2 damage, and the target's Move this turn is cancelled.
- **Area reveal** (Guard, any tile, cooldown 4). Reveals a 3×3 area for 2 turns.
- **Ultimate — Multi-target strike** (after Move). Pick 3 visible tiles; each takes 5 damage after movement.

### Hero B — melee, economy

HP 20 · Speed 3 · Basic 3 damage, range 1.

- **Trait — Contest gold.** When a contested minion dies and Hero B was one of the attackers, Hero B gets the gold.
- **Dash strike** (Dash, up to 3 tiles in a line, cooldown 4). Unlike other dashes, Hero B still gets a Basic Attack this turn.
- **Gold steal** (Attack, adjacent, cooldown 4). Takes 3 gold from an adjacent hero.
- **Ultimate — Gold boost** (Guard, 3 turns). Last hits give double gold and heal 2.

### Hero C — lane control

HP 20 · Speed 2 · Basic 2 damage, range 2.

- **Trait — Extended telegraphs.** Sees enemy minion telegraphs two turns ahead instead of one.
- **Wall** (Move phase, range 3, cooldown 3). Places a blocking tile for 2 turns that stops heroes and minions. Stalls an enemy wave, cuts off a retreat, or holds an allied wave out of Tower range.
- **Hidden trap** (placed in Attack, range 3, cooldown 3). A hero who moves onto it is rooted next turn and takes 2. Rewards predicting movement.
- **Ultimate — Wave reversal** (Minions phase). The enemy wave moves backward 3 tiles this turn instead of advancing.

### Hero D — tank, tether

HP 26 · Speed 2 · Basic 3 damage, range 1.

- **Trait — Structure armor.** Takes 1 less damage from minions and structures.
- **Tether** (Attack, adjacent, cooldown 3). Lasts this turn and the next. If the target ends a Move phase not adjacent to Hero D, it takes 4.
- **Dash push** (Dash, 2 tiles, cooldown 4). If Hero D lands next to a hero, that hero is pushed 1 tile away.
- **Ultimate — Follow lock** (Guard, 2 turns). Hero D binds to an adjacent enemy: when that enemy moves, Hero D moves with it, and Hero D cannot be displaced.

## Worked example: a contested last hit

A single routine laning turn already has no dominant move.

**Setup, turn 4.** Hero A (West) stands 3 tiles from Hero D (East). An East melee minion next to West's wave has 2 HP. Hero A's Basic Attack (3) can last-hit it; Hero D can deny it.

- Hero A's options: **Last-hit** the minion, **Poke** Hero D, or **Guard**.
- Hero D's options: **Deny** the minion, **Dash push** toward Hero A, or **Push** by attacking a West minion.

| Hero A ↓ · Hero D → | Deny | Dash push | Push |
| --- | --- | --- | --- |
| **Last-hit** | Contested; nobody gets gold | A +2 gold; D lands adjacent and pushes A | A +2 gold; D damages A's wave |
| **Poke** | D takes 3; minion denied | Poke hits an empty tile; D lands adjacent | D takes 3 |
| **Guard** | Wasted turn; minion denied | Push blocked; D adjacent with Tether ready | Wasted turn |

**Reading the grid.** Poke beats Deny and Push but misses against the dash. Last-hit beats Push and Dash push but loses to Deny. Guard is only correct if Hero D commits to the dash. No row wins against every column, so the right choice depends on predicting the opponent.

**Kits expand the grid.** Hero A can also use Delayed shot to target the tile where it expects Hero D's dash to land. That fourth option beats Dash push, at −1 damage, if the landing tile is guessed correctly. Each hero adds rows or columns like this, which is where depth comes from.

## Scope and prototype plan

Build in four steps, and write no game code until the paper version is fun.

1. **Paper prototype.** Grid paper, tokens, and order cards revealed together. Play at least 5 matches with two heroes. Cut any rule that does not create a prediction.
2. **Resolver.** One pure function: `resolve(state, westOrders, eastOrders) → (newState, events)`. Deterministic, no randomness, one unit test per phase. Replays, bots and online play all build on it.
3. **Hot-seat build (Godot).** Board, tokens, telegraphs, phase-by-phase playback, and a pass-the-device lock-in screen. All four heroes.
4. **Bot, then online.** A rules-based bot (last-hit when safe, retreat to Tower when low) so solo players always have a match. Then async online play on a small server running the same resolver.

**MVP:** one map, four heroes, six items plus the heal consumable, the neutral objective, a bot, hot-seat and async online.

**Cut from the MVP:** 2v2, the hidden pre-match passive, ranked play, cosmetics, extra heroes.

**Launch fit.** 1v1 and not team-based. Art needs are tiles and tokens. No netcode or frame-level feel to tune, and a deterministic resolver is easy to test and build with AI coding tools. The main risk is player count, which the bot and async play address.

## Risks and open questions

The largest risks are having opponents to play and making simultaneous resolution readable; the rest can be settled in paper playtests.

- **Player pool.** 1v1 strategy games fail without opponents. Bot quality and async play are core features, not extras.
- **Readability.** Simultaneous resolution can feel chaotic. Phase playback must be clear before anything else is polished.
- **Degenerate strategies.** Watch for always-deny, Tower turtling and repeated Recall. Current answers: sudden death, and the Action cost of denying.
- **Contested-kill rule.** Losing gold to a contest might feel bad. Test it against splitting the gold.
- **Turn budget.** Check whether 20 turns fits laning, an objective fight and a push.
- **2v2.** A later mode; adds coordination problems and roughly doubles balance work.

**To settle in paper tests:**

- [ ] Attack before Move vs. Move before Attack — test the opposite order to confirm the core rule
- [ ] Contested-kill rule vs. split gold
- [ ] Wave size and timing (3 minions every 3 turns)
- [ ] Whether 1 Move + 1 Action per turn gives enough choice, or too much
