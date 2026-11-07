# The All-Divine: Between the Rooms — design

A real-time, tile-grid dungeon crawler set in the world of *The All-Divine*. It plays like a Game
Boy Advance Zelda, is built like a roguelike (Risk of Rain's stacking items and difficulty clock,
Pixel Dungeon's depths and unidentified consumables), and is made for a phone first. It reuses the
art engine, cast, places and lore of *All-Divine Tactics*, which stays as it is.

Status: approved in conversation, part by part, on 2026-10-19. This document is the written record
for review before the build plan.

## 1. What was asked, and what was decided

From the conversation, in the user's terms:

- A dungeon-crawling roguelike using the assets of the book and of the Tactics game, "more like
  Legend of Zelda, the Game Boy Advance version".
- Playable on a phone, with buttons that are not too big but still accessible.
- Support items in the manner of Risk of Rain.
- Goblins and one-eyed wyverns as filler enemies, with the roster growing as the player goes deeper.
- "A pixel dungeon kind of creation": depth, systems, real game logic and event logic.
- Sound and UI that match every move; attack effects; damage bars.
- No screen intros or attack intros: quick pacing, roguelike tile movement, fluid animation.
- A settings choice between True GBA (240×160) and GBA shape (360×240) as performance against
  quality.

Decisions taken by the user (multiple choice, the recommended option each time unless noted):

| Question | Decision |
|---|---|
| Replace Tactics or build alongside | A new game alongside; Tactics 1.4 is untouched |
| Run shape | Roguelike runs plus a hub that keeps unlocks |
| Who is played | Abarax first; rescued friends become playable |
| Screen | Both 240×160 and 360×240, chosen in Settings |
| Movement | Real time on the tile grid |
| Build approach | A new project carrying over Tactics' engine |
| Name | *The All-Divine: Between the Rooms* |

The name comes from the book: Mother Kesra says of the Tessellate, *"It lives in the seams between
the rooms of the world."*

## 2. Structure

### 2.1 The descent

The dungeon is the Seams: the rooms of the world stitched together wrong. It runs 25 depths in five
regions of five, each region one part of the book, plus an endless sixth.

| Depths | Region (part of the book) | Places | Boss (one of two per run) |
|---|---|---|---|
| 1–5 | Bilibara | Rue Caillou, the harbor, the Tanneries | First Knuckle / The Glass Saint |
| 6–10 | The Liberation | Saint-Mireille, the Coast Road | The Devourer / Ser Aurelian |
| 11–15 | The First Flame | The Gorse Hills, Forty-One, Ink | The Concordance / Corvin Lark |
| 16–20 | Dark Rodden | The Great Stair, the Spit, the White Spire | High Prime Gideon / The High Seer |
| 21–25 | The Ruin | The Cathedral, the Tide | The Tide / Finger One |
| 26+ | The Seam (*The Shelter*) | Between the rooms | Wick, The Hook, The Iron Giant in rotation every 5 depths; the Tessellate every 10 |

The Seam opens after the first clear of depth 25. The Tessellate is the book's thing that lives
between the rooms: it is fought first as one of the Unbound Three in the Ruin, escapes, and waits
at the bottom of the Seam.

### 2.2 A run

1. In the Garden, the player picks a hero (by talking to them), a difficulty and optionally a seed,
   and steps through the tear in the wall.
2. Each depth is a floor of 8–16 flip-screen rooms (section 6). Its exit is a Seam Gate (6.4).
3. Depths 5, 10, 15, 20 and 25 end in a boss arena. Beating the depth-25 boss wins the run.
4. Death ends the run. The run's items, coins, keys and consumables are lost. Rose petals, unlocks
   and Book entries are kept.

### 2.3 The difficulty clock (Risk of Rain)

    coefficient = (1 + 0.0506 × d × minutes) × 1.15 ^ depthsCleared
    d = 1 (Dawn), 2 (Dusk), 3 (Rose Hour)
    enemy level = 1 + floor((coefficient − 1) / 0.33)

`minutes` counts time inside depths: it pauses in menus, in the Garden, and during the run summary.
It does not pause in shops. The HUD shows the clock and a difficulty bar that steps through named
bands every 5 minutes at Dusk (Calm, Restless, Hunted, Haunted, Unbound, Between, *It has
noticed*), as Risk of Rain does, faster at Rose Hour and slower at Dawn.

Enemies scale from their base stats by level: HP × (1 + 0.3 × (level − 1)), damage
× (1 + 0.2 × (level − 1)).

Winning at Rose Hour unlocks Rose Hour I, and each tier won unlocks the next, up to VIII. Each tier
adds one modifier cumulatively:

| Tier | Modifier |
|---|---|
| I | Enemies start at level +2 |
| II | Healing −25% |
| III | Elites are 20% more common |
| IV | Chest prices +25% |
| V | Bosses have one more shield pip |
| VI | Fall damage and trap damage double |
| VII | The clock runs 25% faster |
| VIII | Max HP −20% |

## 3. Pacing, feel and feedback

- 60 fps fixed-step simulation. Nothing in play stops for a cut-in: there are no intro screens,
  no attack intros, no face-off card and no boss cutscenes.
- Movement is real time on the tile grid. A body glides from tile to tile; the base hero speed is
  7.5 tiles a second (8 frames a tile). A held direction chains steps with no stop between them. A
  direction pressed during a step is buffered and taken the frame the step ends. An attack pressed
  during a step fires on arrival.
- Diagonal steps are allowed when both orthogonal neighbours are free (no corner cutting).
- Enemies appear with a 0.3 s spawn shimmer and cannot act or be hit during it. That is fairness,
  not an intro.
- Bosses: the name and health bar slide in at the bottom while the boss is already acting.
- Hit feedback on every blow: 3 frames of hit-stop (5 on a crit), knockback where the attack says
  so, a white flash on the struck sprite, a spark sized to the damage, and a short screen shake
  that the Settings can turn down or off.
- Damage numbers rise from the struck tile, coloured by type: white (normal), gold (crit), orange
  (burn), red (bleed), blue (chill), purple (spark), green (heal). Numbers from the same source
  within 10 frames merge into one.
- Health bars: enemies show a small bar over their head once damaged; elites show their affix
  icon beside it; bosses use the bottom bar, with shield pips and phase marks.
- Sound matches motion: every move has its own sound, triggered on the move's own frames (wind-up
  whoosh, impact on the active frame, a different impact on a crit and on a block), footsteps that
  follow the step cadence and change with the floor (stone, wood, water, grass), a door slam when
  a room seals, a chime when it clears, a rising tone while a Seam Gate charges.
- Each region has its own chiptune loop; boss arenas and Seam Gate events switch to a fight track
  within one bar.

## 4. Heroes

### 4.1 Stats and formulas

Every hero has: max HP, HP regen per second, base damage, armour, crit chance (crits deal double),
attack speed, move speed, roll charges, and a skill cooldown.

    damage dealt = base damage × skill % × (crit ? 2 : 1) × (1 + sum of % bonuses)
    damage taken = incoming × 100 / (100 + armour)            (armour ≥ 0)
    damage taken = incoming × (2 − 100 / (100 − armour))       (armour < 0)

Within a run, heroes level from experience (experience per kill = the monster's spawn cost × 0.5).
Each level adds +30% of base max HP and +20% of base damage. Level thresholds follow
`xpForLevel(n) = 20 × 1.55^(n−1)`.

### 4.2 Controls

| Button | Action |
|---|---|
| Stick / D-pad | Move (8 directions on the grid) |
| A | Attack. The first hit fires on the press; keeping A held for 40 frames charges a spin, released on letting go |
| B | Skill (cooldown) |
| R | Roll (charges) |
| L | Use equipment (cooldown) |
| Quickslots | Use a potion, scroll or bomb (2 slots, 3 with an unlock) |
| Start | Pause: inventory, map, Book, settings |

Keyboard: arrows or WASD, Z/J attack, X/K skill, C/L roll, V/; equipment, 1–3 quickslots, Enter or
Esc for Start, M for the map. Gamepad: stick or D-pad, south face attack, west face skill, east
face or RB roll, LB equipment, LT/RT quickslots, Start.

### 4.3 The cast

| Hero | Attack (A) | Skill (B) | Roll (R) | Passive | Unlock |
|---|---|---|---|---|---|
| Abarax | Three-hit palm combo | Three Gifts | Roll | Get Up | Start |
| Vanity | Thrown knives, 4 tiles | Murder of Crows | Shadow-step | Backstabs crit | Rescue in Bilibara |
| Benny | Four-hit wraps combo | Danny's Combo | Roll | Momentum | Rescue in Bilibara |
| Vehday | Arrow in a line | True Level | Backflip | Range bonus | Rescue in the Liberation |
| Liora | Rose whip, 2 tiles | Thorn turret | Petal blink | Rooted foes take +30% | Rescue in the First Flame |
| Kael | Greatsword cleave, 3-tile arc | Severance | Shoulder charge | Stands firm | Rescue in Dark Rodden |
| The Twins | Blade combo | Swap Night / Ivory | Roll | Swap empowers | Rescue in Dark Rodden |
| Reigna | Fireballs | Rebirth | Ember dash | Burns spread | Rescue in the Ruin |

Later updates add Hesper, Kesra, Gerace and Galt.

A friend's cell appears on a depth of their region (one cell per depth at most, on depths 2–4 of
the region) until they are rescued. Freeing them (clearing the guarded room and opening the cell)
unlocks them in the Garden for every later run.

### 4.4 Abarax (M1, exact)

Base: 110 HP, 1.0 HP/s regen, 12 damage, 0 armour, 1% crit, 1.0 attack speed, 7.5 tiles/s,
2 roll charges.

- **Palm combo (A).** Three hits on the tile ahead: 100%, 100%, 180%. Hit three also strikes the
  two tiles beside the target and pushes 1 tile. Frames per hit: wind-up 4, active 2, recovery 8;
  attack speed divides wind-up and recovery. Pressing A within the recovery chains the next hit; a
  pause longer than 20 frames resets the combo. Proc coefficient 1.0. Sounds: palm-whoosh, then
  thud; hit three is a heavier thud with a ring.
- **Charged spin (hold A, 40 frames).** 300% to all eight neighbouring tiles; 2 shield damage
  against bosses; proc coefficient 1.0. A gold glint and rising tone mark the charge.
- **Three Gifts (B).** Cooldown 4 s. Each press casts the next gift in turn and the HUD icon shows
  which comes next:
  - Flame: the tile ahead and the three tiles beyond it, 220%, Burn.
  - Bloom: a plus of five tiles centred two tiles ahead, 150%, Root 2 s.
  - Tide: a wave three tiles wide that travels four tiles, 120%, pushes 2 tiles.
- **Roll (R).** Two tiles in the held direction (or facing) over 14 frames; invulnerable for
  frames 1–12. Charges recharge one at a time, 3 s each.
- **Get Up (passive).** Once per depth, a lethal hit leaves him at 1 HP; he heals 20% of max HP
  over 1 s and is invulnerable for 2 s. A rose-gold burst and the Tactics *Get Up* sound play.

The other heroes get the same level of detail in their milestone's spec.

## 5. Items and progression

### 5.1 Item rules (Risk of Rain)

- Items are passive and stack without limit. Each has one of three stacking rules:
  - linear: `value = base + perStack × (n − 1)`;
  - hyperbolic, for chances that must stay under 100%: `chance = 1 − 1 / (1 + k × n)`;
  - diminishing, for cooldowns: `multiplier = 0.9 ^ n` (or as listed).
- Every hit is a damage record: source, target, amount, type, crit, proc coefficient, and a chain
  mask of the items already triggered in this chain. An on-hit chance is multiplied by the hit's
  proc coefficient, and an item never triggers from a chain that already contains it. This lets
  items trigger each other without loops.
- Tiers: Common (white), Uncommon (green), Legendary (red), Boss (gold), Seam (blue, strong with a
  cost), Equipment (orange, one active item with a cooldown, used with L).
- Picking up an item shows its name and one-line effect for 1.5 s over the HUD. Play does not
  stop.

### 5.2 Sources

| Source | Contents | Cost |
|---|---|---|
| Small chest | Common 79%, Uncommon 20%, Legendary 1% | `round(25 × coefficient^1.25)` coins |
| Large chest | Uncommon 80%, Legendary 20% | `round(50 × coefficient^1.25)` coins |
| Equipment barrel | One equipment item | `round(25 × coefficient^1.25)` coins |
| Midas's stall | Choose 1 of 3 of one tier | As the chest of that tier |
| Fortune's Bell | 45% chance per ring of an item (Common 79/Uncommon 20/Legendary 1); the price rises 1.5× per ring | Starts at the small chest price |
| The Tailor | Swap one item for a random item of the same tier | Free, once per depth |
| Seam Gate guardian | One item, Uncommon or better | — |
| Boss | Its boss item, plus +10% max HP and petals | — |
| Elite | 25% chance of a petal; 1 in 40 its affix as equipment | — |

Coins per kill: `ceil(spawnCost × 0.5 × (1 + 0.3 × (coefficient − 1)))`. Coins drift to the hero
within 2 tiles.

### 5.3 The M1 catalogue

Common (15):

| Item | Effect | Stacking |
|---|---|---|
| Lazyman Stack | +25 max HP | +25 |
| Coffee Flask | +14% move speed | +14% |
| Silk Scarf | +15% attack speed | +15% |
| Gambler's Chip | +10% crit chance | +10% |
| Tin Ring | 15% chance to block a hit entirely | hyperbolic, k = 0.15 |
| Rose Thorn | 10% chance on hit to Bleed: 240% base damage over 3 s | +10% chance |
| Bouillabaisse | Kills drop a heal: 8 HP + 2% max HP | +2% max HP |
| Warm Mitts | +75% damage to enemies above 90% HP | +75% |
| Taffy | +3 HP/s regen after 7 s without taking damage | +3 HP/s |
| Crow Feather | +1 roll charge | +1 |
| Bell Chime | Kills ring a chime: 100% damage to the 3×3 around the body | +75% |
| Throwing Knives | 10% chance on hit to throw a knife at another nearby enemy for 200% | +10% chance |
| Brass Buttons | Each incoming hit is reduced by 5 (to a minimum of 1) | +5 |
| Lucien's Watch | Skill cooldown × 0.9 | × 0.9 each |
| Sardine Tin | Heal 8% of max HP when a room clears | +8% |

Uncommon (7):

| Item | Effect | Stacking |
|---|---|---|
| Spark Coil | 25% chance on hit: lightning chains to 3 enemies for 80% each, proc 0.2 | +2 targets |
| Harpoon | On kill: +125% move speed, fading over 2 s | +25% |
| Petal Storm | 10% chance on hit: 3 seeking petals, 100% each, proc 0.33 | +1 petal |
| Ivory Shard | 8% chance on hit: a freezing burst on the 3×3, 150%, Chill 2 s | +8% chance |
| Bandolier | On kill: chance to refill roll charges and reset the skill | hyperbolic, k = 0.18 |
| Kael's Buckler | +30 armour while attacking | +30 |
| Bloodroot | Heal 1 HP per hit, × proc coefficient | +1 |

Legendary (2):

| Item | Effect | Stacking |
|---|---|---|
| Rose Divine Heart | On death, revive at full HP. The heart wilts (consumed) | Each copy is one revive |
| Brass Moon | Every third hit crits and chains a spark to 2 enemies | +1 enemy |

Boss (1): **Knuckle Brass**, from First Knuckle: the charged spin strikes twice, and every hit
does +1 shield damage.

Equipment (4):

| Item | Effect | Cooldown |
|---|---|---|
| Tidebreaker's Anchor | Slam: 400% on the 3×3, pulls enemies within 2 tiles in | 30 s |
| Powder Barrel | Throw a barrel 4 tiles: 600% on the 5×5; opens cracked walls | 25 s |
| Pocket Bell | Reveal the floor's rooms on the map; stun enemies within 4 tiles for 1.5 s | 40 s |
| Henri's Skillet | For 3 s, block all damage from the front and send projectiles back | 20 s |

M2 brings the catalogue to 25 common, 18 uncommon, 10 legendary, one boss item per boss, 6 Seam
items and 12 equipment.

### 5.4 Pixel Dungeon layer

- **Signature weapon.** Each hero's own weapon (the Open Hand, Vanity's Crow's Thorn, and so on) is
  always carried. Scrolls of Upgrade raise it: +10% damage per level.
- **Armour.** One slot, drawn on the character as in Tactics 1.4. M1 pieces: Leather Jerkin (+5
  armour, +5% move speed), Chain Hauberk (+12 armour), Steel Plate (+22 armour, −6% move speed).
  Upgrade adds +3 armour per level. Found armour is unidentified until worn for one depth or read
  with Identify; 1 in 5 found pieces is cursed. A cursed piece cannot be removed until a Scroll of
  Remove Curse is read, has a level from −1 to −3, and has one hidden curse: Heavy (−10% move
  speed), Loud (noise radius doubled), Brittle (+10% damage taken) or Fickle (rolls cost 1 HP).
- **Potions** (the Corvel Reliquary's draughts). Each run assigns every potion a colour at random.
  Drinking one identifies it for the rest of the run, as does a Scroll of Identify. Fire, Frost and
  Toxic Gas are thrown with the quickslot (3 tiles ahead); the rest are drunk.

  | Potion | Effect |
  |---|---|
  | Healing | Heal 60% of max HP over 1 s, cure Bleed and Burn |
  | Haste | +50% move and attack speed for 8 s |
  | Toughness | +60 armour for 8 s |
  | Fire | Fire on a 3×3 that spreads on grass |
  | Frost | Freeze enemies on a 3×3 for 3 s; puts out fire |
  | Toxic Gas | 600 units of poison gas, spreading (6.4) |
  | Mind Vision | See every monster on the floor for 30 s |
  | Experience | Gain one level |

  M2 adds Invisibility, Levitation and Purity.
- **Scrolls** are pages torn from Lucien's Book, each given a rune at random per run:

  | Scroll | Effect |
  |---|---|
  | Identify | Identify one item or all carried potions and scrolls of one kind |
  | Upgrade | +1 to the weapon or the worn armour; removes a curse's level penalty |
  | Remove Curse | Uncurse the worn armour |
  | Magic Mapping | Reveal every room on the floor, including secrets |
  | Teleport | Move to a random cleared room |
  | Rage | Every awake enemy in the room attacks the nearest other enemy for 5 s |
  | Recharging | Reset the equipment and skill cooldowns and refill roll charges |
  | Lullaby | Enemies within 5 tiles fall asleep (a surprise hit wakes them) |

  M2 adds Terror and Mirror Image.
- **Bombs** (carried, max 9): placed on the tile ahead, 90-frame fuse, 300% on the 3×3, open
  cracked walls. **Small keys** (max 9) open locked doors and chests.

### 5.5 Rose petals and the Garden's unlocks

Petals: 10 per boss, 3 per mini-boss or gate guardian, 1 per depth reached, and the elite chance
above. They are kept on death.

| Unlock (Midas) | Petals |
|---|---|
| Start each run with a Healing draught | 30 |
| Third quickslot | 40 |
| +1 roll charge | 60 |
| One free chest reroll per depth | 80 |
| Midas's stalls 10% cheaper | 60 |
| Start at depth 6 / 11 / 16 (after that region's boss is beaten once) | 50 / 80 / 120 |

### 5.6 Achievements and the item pool

Runs start with a base pool of items. About 40 achievements, recorded in Lucien's Book, each add
one more item to the pool: for example, kill 100 goblins (*Goblin Tooth*), beat the Devourer
without being hit (*Undertow*), clear a depth in under 90 s (*Swallow's Wing*). Cosmetic outfits
and armour looks (from Tactics 1.4) are also unlocked by achievements and chosen at the Tailor in
the Garden.

## 6. Floors, rooms and events

### 6.1 Generation

- Each depth has its own seed derived from the run seed, with separate random streams for layout,
  combat and loot.
- The floor is laid out on a 9×8 grid of room slots. Room count:
  `min(16, 8 + floor(0.4 × depth) + rand(0..2))`.
- Growth: a queue walk outward from the start room. A slot is skipped if it already has a room, if
  it would touch more than one existing room, if the count is reached, or at random 50% of the
  time. Dead ends (rooms with one neighbour) are collected.
- Special rooms: the exit (Seam Gate) goes on the dead end farthest from the start by room steps;
  treasure, shop and cell (if any) on other dead ends; the secret room on the empty slot touching
  the most rooms (at least two), never beside the exit. If there are too few dead ends, the floor
  is regenerated.
- Locks and keys: locked doors are placed first; each key goes in a room reachable from the start
  without passing that lock (a reachability search per lock). The generator then checks that every
  room is reachable and rejects the seed if not.
- Rooms are 15×10 tiles with doors in the middle of each wall. Contents come from hand-made
  templates (about 30 per region), each usable mirrored and flipped, then dressed procedurally
  (grass, pots, water, rubble, lamps, banners) by region rules.

### 6.2 Room types

| Room | Behaviour |
|---|---|
| Start | Safe; the first visit shows the depth name for 1 s in the corner |
| Combat | Seals on entry. 1–3 waves from the spawner (6.3). Clearing it opens the doors and rolls a reward: 30% coins, 10% a key or consumable |
| Treasure | A chest; sometimes behind a locked door |
| Shop | Midas's stalls: items, consumables, keys, bombs |
| Shrine | One of: Fortune's Bell, the Tailor, a healing font (heal 50% once), a Seam altar (lose 20% max HP for a Seam item) |
| Puzzle | Push blocks onto plates, light every brazier, hit switches in order, or cross ice. Solving drops a key or chest |
| Trap | Timed spikes, arrow walls or collapsing floor between the doors |
| Challenge | Optional. Doors lock behind you for harder waves; the reward is a large chest |
| Cell | A friend held behind a guarded fight |
| Secret | Behind a cracked wall; rare drops |
| Rest | A campfire, no monsters, and the depth's lore page from the Book |
| Exit | The Seam Gate |

Room states: unvisited, entered, cleared. Cleared rooms stay cleared. A sealed room cannot be left
until it is cleared.

### 6.3 The spawner (Risk of Rain's director)

- A combat room gets a credit budget of `20 + 10 × coefficient` (×1.5 for a challenge room).
- It spends the budget in up to three waves. For each spawn it picks a monster from the region's
  weighted table among those it can afford. If the remaining credit is at least 6× the monster's
  cost and the depth is 3 or more, it makes it an elite (from depth 16, tier-2 elites at 18×).
- The next wave comes when the alive monsters' total cost falls below 30% of the current wave's.
- Spawn tiles are chosen away from the hero (at least 4 tiles) and away from doors.

### 6.4 The Seam Gate

- The exit room holds a gate. Touching it starts the event: a 30 s charge that advances only while
  the hero stands within 3 tiles of it.
- Starting it summons the region's mini-boss as the guardian (scaled by the clock) and makes the
  spawner send waves every 8 s from a budget of `15 + 8 × coefficient`.
- The way down opens when the charge is full and the guardian is dead. The guardian drops an item
  (Uncommon or better) and 3 petals.
- On depths 5, 10, 15, 20 and 25 the gate opens onto the boss arena instead.

### 6.5 The event bus

Every system talks through one bus. Events:

`enterRoom`, `roomClear`, `hit`, `hurt`, `kill`, `heal`, `pickup`, `levelUp`, `roll`,
`useEquipment`, `gateStart`, `gateCharged`, `bossPhase`, `depthStart`, `death`.

Items, room logic, the Book, achievements, sounds and HUD effects subscribe to it. Handlers run in
a fixed order (core rules, then items in pickup order, then presentation), so the same inputs always
give the same results.

### 6.6 World systems (Pixel Dungeon)

- **Gas** (poison, smoke, ash) is a volume per tile. Each tick, each tile's gas spreads evenly to
  itself and its open neighbours; walls block it; closed doors let 10% through; volume decays 2% a
  tick. Poison deals 1% max HP per second per 100 volume.
- **Fire** burns on flammable tiles (grass, wood, tall grass). Each tick a burning tile has a 12%
  chance to light each flammable neighbour, burns for 2–3 s, and leaves ash. Bodies on a burning
  tile gain Burn. Water and Frost put it out.
- **Water** slows walkers by 30%, puts out Burn on entry, and lets Spark chains jump 2 more tiles.
- **Traps** are faint until spotted. The hero spots traps within 2 tiles with a 20% chance per
  second (items and Mind Vision raise this). Kinds: spike, alarm (wakes the room), fire, gas,
  teleport, summoning, pit. Monsters avoid traps they know (all except summoned ones).
- **Light.** Regions set ambient light. Lamps, braziers, fire and some heroes cast light pools.
  Darkness limits monster sight lines and what the hero can see beyond 4 tiles.
- **Destructibles.** Pots, crates and tall grass drop coins (60%), hearts (15%) or nothing. Powder
  barrels explode (300%, 3×3). Cracked walls open to bombs, Powder Barrel and fire.
- **Pits.** Falling costs 10% of max HP and returns the hero to the room's entry tile.

### 6.7 Saving

- The run is saved each time a room is entered: seed, depth, clock, random stream states, hero,
  inventory, and each room's state and taken pickups. Quitting mid-run resumes at the last entry.
- Death deletes the run save. Garden data (petals, unlocks, the Book, achievements, settings, best
  runs) saves at once whenever it changes.
- Saves carry a schema version. An older save is migrated; an unreadable one is set aside with a
  plain message and never crashes the game.
- Each run has a shareable seed (for example `ROSE-4821`). The Daily Seam gives everyone the same
  seed for the day and keeps a local best (depth, time, score).

## 7. Monsters

### 7.1 Monster logic

- States: asleep, wandering, hunting, fleeing.
  - Some rooms start with sleepers. A first hit on a sleeper is a surprise and always crits.
  - Noise (attacks, bombs, rolls, alarms) wakes sleepers within its radius with a 50% chance per
    noise.
- Sight: line of sight on the tile grid (Bresenham). Walls and tall grass block it; darkness
  shortens it.
- Paths: a distance map from the hero, rebuilt when the hero changes tile. Ranged monsters use a
  keep-away map (the distance map inverted and scaled by −1.2, as Pixel Dungeon's flee maps).
  Flyers use a map that ignores pits and water.
- One body per tile. A step claims its destination tile when it starts; blocked monsters wait or
  take the next-best neighbour. Monsters never swap places.
- Attacks are data: a tile shape (adjacent, line N, cone, ring, 3×3, plus), wind-up, active and
  recovery frames, damage %, proc coefficient, and an optional status. During the wind-up the
  target tiles fill red; damage lands on the first active frame on whatever stands there; a roll's
  invulnerable frames dodge it. Recovery is the punish window.
- Targets: the hero, turrets, mirror images and other summons, chosen by distance and by who has
  hurt them.
- Morale: goblins below 25% HP flee (50% chance), towards a shaman if one lives.

### 7.2 Filler families (all regions)

Each region gives these its own look, and a new variant arrives every region or two.

- **Goblins.** Grunt (cleaver lunge), Slinger (keeps 3–4 tiles away, slings stones), Bomber (fused
  bombs on a plus; the bombs also open cracked walls), Shaman (heals and hastes goblins), Pickpocket
  (steals coins and runs), Trapper (lays snares; from the Liberation), Warboss (mini-boss; its
  banner gives nearby goblins +20 armour).
- **One-eyed wyverns.** Whelp (hop-bite), Wyvern (flies over pits and water, circles 3 tiles out,
  dives along a telegraphed line), Spitter (arcs fire globs that leave burning tiles), and regional
  elders (moon, ashen). The eye is a weak point: a hit to a wyvern in dive recovery stuns it for
  1.5 s.
- **Vermin.** Rats, gulls, moths, bats: cheap swarm filler.

### 7.3 Bilibara roster (M1, exact)

Base stats at level 1. Speed in tiles per second; frames are wind-up / active / recovery.

| Monster | HP | Damage | Speed | Cost | Attack |
|---|---|---|---|---|---|
| Rat | 20 | 4 | 6 | 3 | Bite, adjacent, 14/2/10 |
| Goblin Grunt | 60 | 10 | 5 | 8 | Lunge 1 tile then cleave, 24/3/18 |
| Goblin Slinger | 45 | 8 | 4.5 | 10 | Stone, 9 tiles/s, range 6, 30/1/24; keeps 3–4 tiles |
| Goblin Bomber | 50 | 18 | 4 | 14 | Throws a bomb 3 tiles: 90-frame fuse, plus shape |
| Goblin Shaman | 55 | — | 4 | 18 | Heals goblins within 3 tiles 15 HP every 4 s; haste +30% for 3 s |
| Goblin Pickpocket | 40 | 0 | 7 | 12 | Steals 10% of coins (5–50), flees, gone after 10 s; killed, it drops 1.5× |
| Wyvern Whelp (depth 3+) | 70 | 12 | 5 | 15 | Hop-bite 2 tiles, 20/3/20; flies over pits and water |
| Street Tough | 90 | 14 | 4.5 | 12 | Two club swings, adjacent, 22/2/14 then 12/2/20 |
| Gray Hound | 50 | 9 | 9 | 7 | Pounce 2 tiles, 16/3/16; spawns in threes |
| Crown Fusilier | 70 | 16 | 4 | 16 | Musket, line of 8, 45/2/40 |
| Brass Mask | 140 | 15 | 3.5 | 24 | Shield blocks 80% from the front; bash adjacent, 26/3/20 |
| Knuckle of the Hand | 110 | 18 | 5 | 20 | Three-hit combo adjacent, 18/2/8 ×3 |

Weights by depth: rats, grunts and hounds are common from depth 1; slingers and toughs from 1;
bombers, pickpockets and fusiliers from 2; whelps and shamans from 3; Brass Masks and Knuckles from
4.

Mini-bosses (gate guardians, one per depth, chosen at random among those not yet met this run, or
among all three once each has been met): **Gold
Tooth** (Street Tough boss: knife fan and charge), **Yaska's Fixer** (sword and brass knuckles,
calls two Toughs), **Lt. Marais** (sword and musket volley lines). Each has 900 HP at level 1,
20 damage, 3 shield pips and four telegraphed patterns.

### 7.4 Elites

| Affix | Effect |
|---|---|
| Gold-flame | Leaves burning tiles behind it; its hits Burn |
| Ivory | Its hits Chill; on death, a freezing burst on the 3×3 after 1 s |
| Spark-struck | Its hits attach a spark that bursts for 100% after 1.5 s |
| Thorned | Its hits stop the target healing for 4 s |
| Seam-touched | Blinks to a tile behind the hero every 4 s |
| Choir (tier 2) | Allies within 3 tiles cannot be targeted while it lives |
| Lantern (tier 2) | Skills cannot be used within 3 tiles of it |

Elites: 4× HP and 2× damage (tier 2: 18× and 6×), cost 6× (tier 2: 36×).

### 7.5 Statuses

| Status | Effect |
|---|---|
| Burn | 50% of the burner's base damage per second for 3 s; refreshes |
| Bleed | 240% of base damage over 3 s; stacks |
| Chill | −40% move and attack speed for 2 s |
| Root | Cannot move (can attack) for 2 s |
| Stun | Cannot act |
| Blind | 50% of attacks miss for 3 s |
| Poison | From gas (6.6) |
| Weaken | −30% damage dealt, −20 armour for 4 s |

### 7.6 Bosses

- Three phases, at 100%, 66% and 33% HP. Each boss has 4–6 telegraphed patterns and a desperation
  move in the last phase.
- Shields and Break (from Tactics): shield pips are worn down by heavy hits (charged spin, bombs,
  Severance, Knuckle Brass). At zero the boss is staggered for 3 s and takes +50% damage; the
  shield refills at the next phase.
- Rewards: the boss item, +10% max HP, 10 petals.

**First Knuckle (M1, exact).** 2,800 HP at level 1, 22 damage, 4 shield pips, the Tanneries yard
arena (15×10, two vats as cover).

| Pattern | Telegraph | Effect |
|---|---|---|
| Knuckle Dash | A 6-tile line, 36 frames | 160%; if he hits a wall or vat he is stunned 1.5 s |
| Three-Count | Three 3×3 squares in turn, 24 frames each | 120% each |
| Uppercut | The tile ahead, 18 frames | 200%, knocks back 2 |
| Call the Hand (66%) | — | Two Street Toughs enter from the doors |
| Debts Paid (33%) | Coins mark 8 random tiles, 40 frames | 100% where each lands; the coins stay as pickups |

**The Glass Saint** (Bilibara's other boss), and the bosses of later regions, are specified in
their milestone.

### 7.7 Later regions (roster names fixed now; numbers in each milestone)

- The Liberation: Crown Lancers, Ash Veil Sisters, Lantern Knights, Glass Moths; mini-bosses
  Colonel Feyd and Elder Sister.
- The First Flame: Gorse Bandits, Deserters, Hollows, Calder Wraiths; mini-bosses One-Eye (riding
  the oldest one-eyed wyvern) and the goblin Warboss.
- Dark Rodden: Choir of the Order, Fingers of the Hand, War Divines, Crown Lancers; mini-bosses the
  Church Captain and Queen Isaura.
- The Ruin: Compact Riflemen, Ironclads, Unbound, lesser Horrors; mini-bosses Finger Five and the
  Unbound Three (Nul, the Tessellate and Haar together).
- The Seam: Seamwalkers and every roster scaled up.

## 8. The Garden

Three connected screens of Selenne's Garden.

- Rescued friends stand about. Talking to one offers *Take the lead* to play as them next run.
- Selenne gives hints and lore. Lucien keeps the Book: bestiary, items, places, heroes,
  achievements, and run history, each entry with lore from the novel. Midas sells the petal
  unlocks. The Tailor sets outfits and armour looks.
- A training yard with a dummy that shows damage per second.
- The tear in the wall starts a run: difficulty, seed (random, typed, or the Daily Seam).
- The run summary on death or victory: depth, time, kills, an icon grid of items taken, what
  killed the hero, petals earned. One tap skips it.
- The first run shows short hints at the moment they apply (for example "A: attack" when the first
  goblin wakes). There are no tutorial screens.

## 9. Screen, interface and phone

### 9.1 Display modes

| Mode | Canvas | Tile | Figures | Effects |
|---|---|---|---|---|
| GBA shape HD (quality, default) | 360×240 | 24 px | 24×32 paper dolls | Bloom, light pools, full particles |
| True GBA (performance) | 240×160 | 16 px | 16×21 | Light pools without blur, half particles |

Rooms are 15×10 tiles in both. All game logic is in tiles and fractions of a tile and never reads
the screen size. True GBA art is made from the HD art at load by a 3:2 pixel downscale that keeps
outline pixels and the most saturated pixel of each cell (eyes, trims). Changing the mode in
Settings rebuilds the art caches in about a second without a restart. If the first 5 s of play
average more than 20 ms a frame, a one-line notice suggests True GBA.

### 9.2 HUD

- Top left: HP bar with the number, the level and an XP sliver beneath.
- Top right: coins, keys, bombs, the clock and difficulty band, and a small minimap of known rooms.
- Quickslots under the minimap (tappable on a phone).
- Bottom: the boss bar when a boss is present.
- The item list lives in the pause menu (grid with stack counts and descriptions), not on screen.

### 9.3 Phone

- Landscape: the game in the middle, a floating stick on the left that appears where the thumb
  lands, A, B and R in an arc on the right, L and Start smaller at the top corners.
- Portrait: the game at the top, the controls below it, like a GBA SP.
- Buttons are 48 CSS px by default (B and R 44, L 40, Start 32), half transparent, with hit areas
  1.5× their drawn size. Settings: size 80–130%, opacity 30–90%, left-handed layout, haptics on hit
  and on being hurt.
- Multi-touch: the stick and any button at once. Respects notches and safe areas.

### 9.4 Settings

Display mode, effects (bloom and lights on or off), screen shake (full, low, off), flashes (full,
low), damage numbers (on, off), control size, opacity and handedness, haptics, music and effects
volume.

## 10. Architecture

### 10.1 Project

    all-divine-seams/
      src/            readable sources, one module per file, and order.txt
      tools/build.mjs joins src/ into web/index.html (one offline file)
      web/index.html  the built game (also the artifact)
      android/        the Tactics app shell, new application ID com.advoxsegoat.alldivineseams
      tools/playtest/ bot, sweeps, fuzzers, probes, contact sheets
      README.md
    .github/workflows/all-divine-seams-apk.yml

### 10.2 Modules

Carried over from Tactics and adapted:

- `core`: fixed 60 Hz loop with an accumulator, the scene stack, seeded random streams (mulberry32),
  guarded storage, the error log, the watchdog and the scene rescue from Tactics 1.3.
- `input`: keyboard, gamepad and touch mapped to one set of virtual buttons and a stick; buffering.
- `audio`: the WebAudio synth; a new sound set and region tracks.
- `gfx`: the pixel font, panels, icons.
- `art/tiles`, `art/figures`: the Tactics tile painter and paper-doll figures, extended with
  top-down attack poses in four directions and the region tilesets.
- `art/downscale`: the 3:2 reducer for True GBA.

New:

- `sim/grid`: tiles, occupancy, sight lines, distance maps.
- `sim/entity`: bodies, the tile glide, projectiles, pickups.
- `sim/combat`: damage records, armour, crits, statuses, telegraphs.
- `sim/items`: item behaviours as event handlers; stacking maths.
- `sim/ai`: monster states and attack choice.
- `sim/director`: credits, waves, elites, the clock.
- `sim/world`: gas, fire, water, traps, light.
- `gen/floor`, `gen/room`: the room grid, special rooms, the lock-and-key check, templates.
- `game/run`, `game/hub`: depth flow, Seam Gates, saving, the Garden.
- `view/render`, `view/hud`, `ui/menus`: drawing, the HUD, pause, map, Book, settings, summary.
- `data/*`: heroes, items, monsters, bosses, regions and templates, consumables, achievements, lore.

### 10.3 Rules the code keeps

- The simulation is deterministic: the same seed and the same input log give the same state after
  any number of frames. Rendering, sound and the HUD only read the simulation.
- Each room's static layer is drawn once to an offscreen canvas and only changed tiles are redrawn.
  Sprite frames are cached per look and pose. Particles, numbers and projectiles come from pools.
- Budgets: 60 fps on a mid-range phone; simulation at most 3 ms a frame with 40 monsters; drawing
  at most 8 ms in HD.
- Every frame is guarded. An error is logged; a scene that keeps throwing is closed and the game
  returns to the Garden or the title. Settings → *Report a problem* copies the log.

## 11. Testing

- **Maths:** stacking rules, damage and armour, proc chains (no loops), the spawner's spending, and
  the clock against Risk of Rain's published curve.
- **Generator fuzzing:** 10,000 seeds across every depth. Every room reachable, every key reachable
  before its lock, the gate and special rooms present, every template valid.
- **Determinism:** recorded input logs replay to the same state hash.
- **Bot sweep:** a bot plays full runs through the real touch and keyboard paths across seeds and
  heroes; it reports stuck runs, errors, soft-locks (no progress for 60 s) and frame times.
- **Contact sheets:** each hero move in four directions, each monster and telegraph, rooms from
  each region, the HUD, in both display modes.
- **Phone:** layout tests in both orientations at four phone sizes (controls on screen, at least
  40 px, not covering the game); the performance and memory probes; APK checks as for Tactics.

## 12. Milestones

Each milestone ships playable: the artifact, an APK and a pull request.

| Milestone | Contents |
|---|---|
| M1: vertical slice | Engine, both display modes, phone controls; Abarax's full kit; Bilibara depths 1–5 with goblins, wyvern whelps, vermin and the book's enemies; the three mini-bosses; Seam Gates; First Knuckle; the M1 catalogue (5.3), potions, scrolls, armour and curses; a basic Garden (Midas's unlocks, the tear, the summary); saving |
| M2 | The Liberation and the First Flame; Vanity, Benny, Vehday and Liora; elites; the full item catalogue; shops, shrines, puzzles, challenge rooms; Lucien's Book; the Glass Saint |
| M3 | Dark Rodden and the Ruin; Kael, the Twins and Reigna; every remaining boss; achievements and the growing item pool; Rose Hour tiers; the Daily Seam |
| M4 | The endless Seam and the Tessellate; balance from bot data; polish |

## 13. Out of scope

- Online play, accounts and online leaderboards (the Daily Seam is local).
- Payments, ads or in-app purchases.
- Changes to *All-Divine Tactics*.
