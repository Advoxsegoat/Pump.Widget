# The All-Divine (action RPG): foundation design

Status: draft for the owner's review, 2026-10-25. This spec covers the foundation and the first
playable slice. Later stages (more Gifts, more regions, the full story) get their own specs on top
of it.

## 1. What was asked, and what was decided

The owner wants *The All-Divine* to become the RPG it should be. It should be built over months, to
feel as good as AAA games, not hurried into a small app. Three things come first:

- **Graphics that match character actions across cutscenes, mini-cutscenes and combat.**
- **Storyboarding.**
- **The structural integrity of the whole.**

Above all, functionality and playability: how the game plays. Characters must have the flow and
liveliness of people, never robotic motion. The book, the existing games (*Tactics of the Open
Hand*, *Between the Rooms*) and their art are the foundation to build up from. The owner writes
the items, the powers' details and the scenes. This project builds the engine, the systems and
the pipeline they plug into.

| Question | Decision |
|---|---|
| Combat pace | Real time, Souls-like: readable wind-ups, invulnerable dodges, stamina, punish windows. Free 360° movement, no tile grid. Supersedes the turn-based plan for *Between the Rooms* |
| Platform | PC first: gamepad, or keyboard and mouse. Phones and consoles maybe later |
| Look | HD-2D: pixel-art characters in a lit 3D world. A high 3/4 combat camera that can glide in for cutscenes |
| Engine | Godot 4 (one pinned stable version), plain-text project in git |
| Animation | Rigged 3D characters drawn through a pixel-art shader, so they read as sprites but move like people. One rig plays combat, cutscenes and close-ups from any angle. Turning the filter down later gives full 3D |
| World | Handcrafted, interconnected regions from the book. Rose shrines; petals lost on death and recovered once; shortcuts that loop regions back on themselves |
| Powers | You are always Abarax, the All-Divine, on the Open Hand, starting with one Gift: Flame, Bloom or Tide. Gold Flame awakens in the story and lets you mix Gifts |
| Storyboards | The owner describes a scene; Claude makes a shot-by-shot sheet, then an in-engine animatic video. A scene is final only once the owner approves it |
| Assets | Free and openly licensed only, plus what Claude makes: Quaternius and Kenney (CC0), CMU motion capture, Blender's Python module. No Mixamo (free, but not an open licence) |
| First slice | The Open Hand plus Flame, polished. A Bilibara stretch: 3–4 enemy types, a mini-boss, First Knuckle. Two shrines, the corpse run, levels and Flame items. One cutscene and First Knuckle's entrance. 20–30 minutes that feel great |
| Core approach | Animation drives combat. Every move is one clip with timeline marks for hitboxes, invulnerability, cancels and events. Gameplay reads the marks; cutscenes play the same clips |
| Customization | Builds, plus armour and outfits that show on Abarax, with dyes. No character creator |
| Dying twice | No. Progress comes only from items and skills found in the world. *Get Up* does not carry over |

**Success** is judged by feel and by the owner's approval:

- input response of 2 frames at most;
- enemies that read clearly;
- hits with weight;
- a steady 60 fps on a mid-range PC;
- every storyboard and animatic approved by the owner.

The current games stay as they are, shipped. Their art, lore, enemies, sound and designs are source
material, not code carried forward.

## 2. Architecture

Godot 4, one pinned stable version (the latest 4.x stable when F0 starts, recorded in the plan).
Gameplay in typed GDScript; C++ (GDExtension) only where profiling demands it.

### 2.1 Layers

Each layer has one job. Layers talk downward or through signals and events, never sideways into
another layer's internals.

1. **Core** (autoloads): the game state machine (boot, title, play, cutscene, menu, pause), saving,
   input (actions, rebinding, the input buffer), audio buses, and the data registry.
2. **Data:** Gifts, moves, items, enemies, attributes and scaling as text resources (`.tres`). The
   owner's lists arrive as spreadsheets (CSV) and an importer turns them into resources. Adding an
   item, a skill or an enemy tier never needs a code change.
3. **Actors:** one actor scene for every character: Abarax, enemies, bosses, townsfolk. Its parts:
   - **Body**: a `CharacterBody3D` with collision;
   - **Rig**: the 3D model, its `AnimationTree` and IK;
   - **Stats**: HP, stamina, posture, poise, resistances;
   - hit and hurt zones;
   - a swappable **Brain**: player input, enemy AI, or the cutscene director.
   A cutscene hands the actor to the director; the same rig and motion carry from combat into story
   and back.
4. **Moves:** a move is an animation clip plus a `MoveData` resource. The clip's timeline carries
   method and value tracks for:
   - hitbox on and off (with shape and damage profile);
   - invulnerable frames;
   - cancel windows (into which moves);
   - root motion;
   - stamina cost and posture damage;
   - effects, sound, camera shake and hit-stop events.
   The combat system reads these marks, so what is seen is exactly what hits.
5. **World:** regions as scenes, split into areas that stream in and out, plus shrines, doors,
   shortcuts, lifts and secrets. World memory (opened shortcuts, defeated bosses, taken items, NPC
   states) is part of the save.
6. **Presentation:** the render pipeline (section 3), the camera rig (combat camera, lock-on,
   cutscene cameras), HUD and menus.
7. **Cinematics:** the Director (section 7), which plays timelines driving cameras, actors' clips,
   dialogue, music and sound.
8. **Tools** (`tools/`):
   - headless tests;
   - the combat bot;
   - input recording and replay;
   - the clip checker;
   - the CSV importer;
   - motion retargeting;
   - contact sheets;
   - animatic export (Godot's Movie Maker);
   - the storyboard-sheet generator.

### 2.2 Structural rules

- Content is data, never code. Every enemy, item, skill and scene is a file the owner or Claude can
  edit without touching systems.
- One way to animate anything: through a rig and clips. No special-case drawing for cutscenes.
- Every system ships with tests that run headless in the cloud container on each change.
- The project is resumable from the repository alone. `STATE.md` at the project root always says
  what is done, what is next, and where the decisions live.

## 3. Graphics and animation

### 3.1 The screen

- The game renders the 3D scene at a fixed internal resolution of 640×360. It is scaled up by whole
  numbers to 1920×1080 (×3), 2560×1440 (×4) or 3840×2160 (×6) with nearest-neighbour filtering, so
  every pixel keeps the same crisp size.
- The camera snaps to the pixel grid, so edges never shimmer. A sub-pixel offset applied at the
  upscale keeps camera motion smooth.
- HD-2D post effects:
  - tilt-shift depth of field (the HD-2D signature);
  - bloom;
  - volumetric fog;
  - per-region colour grading;
  - vignette.
  Each can be turned down in Settings.

### 3.2 Characters

- Low-poly rigged models (about 1,500–4,000 triangles), toon-shaded with a 3–4 step light ramp.
- Pixel outlines from depth and normal edges.
- Each character is held to its own palette, taken from the existing art: Abarax's rose-gold and the
  rest of the cast.
- Clips play smoothly at 60 fps or **stepped** per clip at 12 or 24 fps, for snappy retro attacks.
  Stepping is a clip setting, not a separate animation.
- **Liveliness layers** (what makes motion human):
  - blended 8-way locomotion by speed and angle;
  - foot IK on slopes and stairs;
  - look-at IK: heads and eyes turn toward targets and speakers;
  - additive hit reactions layered over any move;
  - spring bones for hair, cloth and scarves;
  - subtle idle breathing.
- Outfits and armour are separate meshes on the shared skeleton (head, body, arms, legs), so worn
  gear shows. Dyes recolour by palette slot.

### 3.3 Sources of models and motion (free and open only)

- **Bodies:** Quaternius CC0 base characters, dressed as our cast following the existing designs
  (Tactics portraits and figures, *Between the Rooms* looks).
- **Motion:**
  - Quaternius's CC0 animation library, and CMU motion capture (free for any use), retargeted onto
    our skeleton by `tools/anim/retarget`;
  - attacks, Gift arts and signature moves hand-keyed by scripted tools using Blender's Python
    module (`bpy`), run headless in the container.
- **Environment:** Kenney and Quaternius CC0 kits as a base, plus our own modular pieces with pixel
  textures.
- **Licence ledger:** `ASSETS.md` records every third-party file, its source, licence and changes.
  Nothing enters the repository without a line there.

### 3.4 The world's look

- Modular 3D tiles and props with pixel textures, at 32 texels per metre.
- Real lights (torches, lamps, the Gifts' glow) with shadows, plus day and night per region.
- Weather: snow and rain particles, puddles and wind on foliage.
- Gift effects as GPU particles snapped to the pixel grid: Flame embers, Bloom petals, Tide water.

### 3.5 Readability rules

- Every enemy attack has anticipation frames and a tell: a glint, a colour flash, a sound.
- Perilous attacks (section 4.4) add a red rose flash and their own sound.
- Silhouettes are checked at 640×360 on the contact sheets.

### 3.6 Performance

A steady 60 fps at 1920×1080 on a mid-range PC (GTX 1060 / RX 580 class, 4-core CPU, 8 GB RAM). The
640×360 internal resolution keeps the GPU cost low. A frame budget is profiled at every milestone.

## 4. Combat and controls

### 4.1 Controls

| Action | Gamepad | Keyboard and mouse |
|---|---|---|
| Move | Left stick | WASD |
| Palm strike (combo) | RB | Left mouse |
| Heavy strike (hold to charge) | RT | Right mouse |
| Guard; a timed tap parries | LB | Q |
| Gift (hold to aim) | LT | E |
| Dodge (hold to sprint) | A / Cross | Shift / Space |
| Use item | X / Square | R |
| Interact | Y / Triangle | F |
| Switch items and Gift arts | D-pad | 1–4, mouse wheel |
| Lock on, switch target | R3, right stick | Tab, mouse wheel while locked |
| Menu | Start | Esc |

When not locked on, keyboard and mouse aim facing toward the cursor. Every control can be rebound.

### 4.2 Feel

- **Input buffer:** about 150 ms (9 frames). A press just before a move's cancel window opens comes
  out on the window's first frame.
- **Cancels:** marked per clip (section 2.1). Attacks can cancel into dodge from their recovery, and
  combo steps chain inside their windows.
- **Aim assist:** attacks turn toward a target within about 30° of the stick during wind-up.
- **Dodge:** about 13 invulnerable frames out of 30, close to Souls' standard roll. Tide replaces it
  with a flowing dash. A dodge pressed during an attack's recovery cancels it.
- **Stamina:** spent by attacks, dodges, sprinting and guarding. It regenerates after a 0.6 s pause.
  At zero you can still move but cannot attack or dodge until it refills a little.
- **Hit weight:** every hit lands with:
  - hit-stop of 3–6 frames, scaled by the move's weight;
  - camera shake and knockback;
  - sparks;
  - an additive flinch on the target;
  - layered sound: impact, voice and surface.

### 4.3 Resources

- **HP**, healed by the **Rose Flask**: a few sips, refilled at shrines.
- **Stamina.**
- **Gift meter:** fills from landed palm strikes and parries, and is spent on Gift arts. Melee and
  Gift feed each other, rewarding aggression, as Bloodborne's rally does. Each Gift adds its twist:
  - **Flame** stacks burn on targets and can detonate it;
  - **Bloom** plants thorns that bloom a beat later;
  - **Tide** banks counters that release on the next dodge.

### 4.4 Poise, posture and perilous attacks

- **Poise:** enemies flinch unless a move's poise damage is lower than their poise. Heavy and
  charged strikes break poise into a stagger. Some of Abarax's heavies have hyper-armour frames,
  marked on the clip.
- **Posture:** a second bar besides HP. Parries, guards against heavy attacks, and heavy hits wear
  it down; it recovers when the fighter is not under pressure. A broken posture opens an **Open
  Hand finisher**: a mini-cutscene of 1.5 s at most (section 7.3).
- **Perilous attacks** are marked with the red rose flash, and each has one counter:
  - a sweep: jump or step over it;
  - a thrust: an Open Hand catch, a parry variant like Sekiro's Mikiri Counter;
  - a grab: dodge it.

### 4.5 Enemies

- **Brains** are data-driven state machines:
  - perception: sight cones, hearing, alertness;
  - spacing: each archetype's preferred range;
  - attack choice by range, angle, cooldown and weight;
  - reactions: flinch, stagger, retreat, regroup.
- **Attack tokens:** in ordinary fights only one or two enemies commit to an attack at a time, so
  groups pressure without cheap gang-ups.
- **Gank squads**, cheap on purpose: a few named groups (for example *the Hand's Pack* in Bilibara's
  alleys, or a goblin war-band led by a drummer) ignore the token rule. They commit together, flank
  and chain attacks. Each squad can be beaten:
  - by a **secret weakness**: an item hidden elsewhere in the world, hinted by lore, an item
    description or an NPC rumour (for example a Rose Bell that scatters the Pack, or smoke that
    silences the drummer and breaks the band's rhythm);
  - or by **pure skill**: every squad is readable and learnable, just brutal.
- **Tiers and growth:**
  - every archetype has tiers I–III; later regions field higher tiers with new tells, feints,
    delayed swings and combo extensions, not just bigger numbers;
  - **skill-aware variants**: as Abarax gains skills, later enemies answer them. Once the perfect
    parry is learned, later enemies delay swings to bait it; once the dash is mastered, they track
    it.
- **Bosses:** phases with pattern tables, every pattern built from readable clips. Bosses may use
  perilous attacks and have their own posture.

## 5. Progression and builds

- **Petals** are the souls and the currency. They drop where you die; you get one chance to reach
  them before they wilt.
- **Attributes**, raised with petals at shrines:
  - **Vigor**: HP;
  - **Endurance**: stamina and equip load;
  - **Might**: the Open Hand;
  - **Flame**, **Bloom** and **Tide**: Gift affinities.
  The starting Gift begins higher. Others can be raised, but their arts are usable only after Gold
  Flame awakens.
- **Equipment** (all data, from the owner's lists):
  - **Hands**: wraps and gauntlets that change the palm moveset and its scaling. These are the
    weapons;
  - a **Gift focus**: a talisman that changes Gift arts;
  - **armour**: head, body, arms and legs, visible, dyeable;
  - **charms**: 3–4 passive slots;
  - **quick items**: the Rose Flask, throwables, secret weaknesses.
  Hands and foci scale with attributes by letter grade, S to E, as Souls weapons do.
- **Skills are found, never bought:**
  - teachings hidden in the world (secret rooms, ledges, behind gank squads);
  - taught by NPCs at the end of quest lines;
  - chosen from a boss's remembrance;
  - Gift arts learned at Gift altars.
  A limited number are equipped at a time; that limit is where builds come from.
- **Skills open the world** (light Metroidvania): Flame burns thorn walls, Bloom grows vines to
  climb, Tide's dash crosses gaps. Shortcuts and secrets reward returning with new skills.
- **New Game+**, later: remixed enemy tiers and placements.

## 6. The world

- The Garden is the hub. Regions from the book (Bilibara first, then the Liberation, the First
  Flame, Dark Rodden and the Ruin) are handcrafted and interconnected. Each loops back on itself
  through shortcuts opened from the far side.
- **Rose shrines:** rest (refill the Flask, respawn enemies), level up, travel between found
  shrines, change equipped skills.
- **Death:** back to the last shrine, enemies reset, petals left where you fell.
- **Saving:** automatic, continuous, at shrines and on world changes (a shortcut opened, a boss
  down), with a backup slot. Old saves migrate by version.
- **The first slice's stretch of Bilibara:** two shrines, one shortcut loop, 3–4 enemy types, one
  gank squad and its secret weakness, a mini-boss, and First Knuckle's arena (the Tanneries yard).

## 7. Cinematics and storyboarding

### 7.1 The pipeline

Each scene lives in its own folder, `scenes/story/<scene>/`:

1. `script.md`: the owner's words: who is there, what happens, the feeling.
2. `shots.tres`: the shot list, as data. Each shot records:
   - framing: wide, medium, close, over-the-shoulder, insert;
   - camera move: static, pan, dolly, crane, orbit, handheld shake;
   - actors, with their clips and marks;
   - timing;
   - dialogue lines;
   - music cue and sound.
3. **Storyboard sheet:** a page with a thumbnail frame captured from the engine at each shot's key
   moment, beside its framing, action, line and timing. Reviewed as real frames.
4. **Animatic:** rendered by Godot's Movie Maker to video, using the real rigs (placeholder clips
   where moves do not exist yet), and sent for review.
5. The owner's notes, revisions, and approval. Only an approved scene becomes final.

Every revision is committed, and the owner's notes are kept in the scene folder (`notes.md`).

### 7.2 The Director

It builds a Godot timeline (`AnimationPlayer`) from the shot list. The timeline drives:

- camera paths (`Path3D` with look-at);
- actors' clips and positions;
- focus pulls on the depth of field;
- letterboxing;
- dialogue boxes with the book's pixel portraits and voice blips;
- music stingers and sound.

The generated timeline stays editable in the Godot editor.

### 7.3 Three kinds of scene, one pipeline

- **Cutscenes:** letterboxed story scenes, skippable after the first viewing.
- **Mini-cutscenes:** boss entrances of 3–6 s. The camera glides out of gameplay and back without a
  cut. They play fully the first time and are skippable on retries.
- **Combat moments:** posture-break finishers of 1.5 s at most, with a camera dip and a slow-motion
  beat. Combat flow never stalls, and Settings can turn the camera dips off. There are no attack
  intros and no intro screens.

### 7.4 The seamless rule

- A scene starts from the live game state, with actors where they stand.
- The camera blends from the gameplay camera.
- Control returns with Abarax's pose matching.
- No cuts to black and no loading screens between play and story.

## 8. Testing and tools

- **Headless tests:** data loading and the CSV importer, damage and scaling maths, saves, migration
  and world state, the input buffer and cancel rules, and enemy token allocation. A small test
  runner of our own is used, so no third-party test framework is required.
- **The clip checker:** every attack clip must mark hitbox on and off, cancel windows and recovery;
  every dodge its invulnerable frames; every move its sound and effect events. The build fails
  otherwise.
- **The combat bot:** plays encounters and the slice through real input actions; reports errors,
  soft-locks and broken encounters; records replays of failures.
- **Feel metrics:**
  - press-to-motion delay measured per move (2 frames at most);
  - frame-time budget (60 fps);
  - animation coverage (no T-poses, no missing clips per actor and state).
- **Contact sheets:** every clip at its key frames, for review by eye. These and the animatics are
  rendered in the container through software rendering (Godot's Compatibility renderer on Mesa
  llvmpipe under a virtual display). Final-quality captures may come from the owner's PC.
- **CI:** tests and Windows and Linux exports on every push, with a web export for a quick look in
  the browser.

## 9. Milestones

Each milestone ends with a build the owner plays on their PC, plus their notes.

| | Milestone | Delivers |
|---|---|---|
| F0 | Foundation | The Godot project; the render pipeline (pixel-art rigs, HD-2D world, upscale and snapping); the actor, brain and move system; the test harness and clip checker; `STATE.md` and `ASSETS.md`; Abarax rigged with locomotion and liveliness layers. A lit courtyard to walk in, where walking already feels good |
| F1 | Combat core | The Open Hand moveset, dodge, guard and parry, stamina, poise and posture, finishers, perilous attacks, hit feel, lock-on. One enemy archetype with tiers I–III. An arena |
| F2 | Flame and builds | The Flame kit and Gift meter; attributes and levels; equipment, scaling and dyes; the CSV importer with the owner's first item lists; found skills |
| F3 | The world | The Bilibara stretch: shrines, petals and the corpse run, saves, a shortcut loop, 3–4 enemy types, a gank squad and its secret weakness, the mini-boss |
| F4 | Cinematics | The Director, storyboard sheets, animatic export; the first cutscene and First Knuckle's entrance through the owner's approval loop; finishers as combat moments |
| F5 | First Knuckle and polish | The boss with its phases and perilous attacks; a feel-tuning pass; a performance pass. The 20–30 minute slice |

Each milestone gets its own implementation plan, written when the one before it is done.

## 10. Environment

- The project lives in this repository, in a new folder `all-divine/`, alongside the existing games.
- Godot and its export templates download from GitHub release assets; Quaternius, Kenney and itch.io
  are reachable. CMU's mocap site (`mocap.cs.cmu.edu`) is not yet allowed; its library is mirrored
  elsewhere, or it is added when F0 needs it.
- There is no GPU in the container: software rendering is used for sheets and animatics, which is
  slower but workable.
- The owner opens the project in the Godot editor on their PC to play and tweak. A Claude session on
  their computer (the desktop app, or `claude remote-control`) can drive work that needs their
  machine.

## 11. Risks

1. **Software rendering is slow.** Animatics render at lower frame rates in the container, and
   final captures can come from the owner's PC.
2. **Free-only motion is limited.** The retargeting tools are built in F0, and signature moves are
   hand-keyed.
3. **The cast's look from free bases.** Dressed and palette-matched to the existing designs; an
   artist can replace them later without engine changes.
4. **Feel needs the owner's hands.** Every milestone ends with the owner playing the build.
5. **Session limits.** All state lives in git: specs, plans, ledgers and `STATE.md`.

## 12. Out of scope for this foundation

- Bloom and Tide's full kits: their systems exist; their content comes after the slice.
- Regions beyond the Bilibara stretch.
- The full story.
- Phones and consoles.
- Voice acting.
- Online features.
- First-person play: considered and set aside; the rig pipeline keeps a later 3D third-person camera
  possible.
