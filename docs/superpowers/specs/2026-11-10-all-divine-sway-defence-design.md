# The All-Divine: the sway-and-duck defence

This amends the foundation design (`2026-10-25-all-divine-rpg-foundation-design.md`), sections 4.1 (controls), 4.2
(feel) and 4.4 (perilous attacks). Where the two differ, this document wins.

## 1. What was asked, and what was decided

**The owner's direction (2026-11-10), after playing the preview:**

- Replace the dodge roll with Dragon Ball-style dodging: sways side to side, and ducks.
- On PC, the direction keys become sways and ducks while the parry key is held.
- The flow should read: attack, the enemy attacks, parry, sway, parry, parry, sway, sway, attack.
- Fights stay close. Rolling around the map is what made space before; it should not be the answer any more.
- Swarmed by several enemies, one dodge can avoid several attacks.
- After a dodge come "recoil" attacks (counters), and attacks that spread the enemies out.

**The owner's review of the first draft (the same day):**

- A dodge sequence starts with weighty boxer slips: that is its opening rhythm.
- Against enemies with longer attack patterns, where Abarax stands in place and dodges, the rhythm rises and so does the
  demand on the buttons. The dodges become quick, near-instant, "almost like perfect dodging".
- The longer he dodges in place, the bigger the opening he earns and the more dangerous he is to the enemy; and the more
  he risks, because he can be knocked out of it, which is a moment of crowd control on him.
- A minimal dash stays, for larger enemies and area attacks.
- The work is close-combat sequences.

**Decided with the owner:**

| Question | Decision |
|---|---|
| How much does the direction matter? | Timing first. Any well-timed sway or duck avoids an ordinary attack. The direction that fits the attack makes it a **perfect dodge**. |
| What does the old dodge key do? | The roll is removed. A tap with a direction is a short **dash-step** with no invulnerability. A tap with no direction is the hop. Held, it sprints. |
| How do unblockable attacks work? | Each keeps one answer, shown by its icon: the sweep is hopped, the thrust is caught with a parry, the grab is slipped with any sway or duck. |
| How does a dodge sequence feel over time? | It builds. Defences that succeed in a row form a **chain** that moves through three tempos: weighty slips, quick dodges, then a flurry of near-instant ones. The chain raises what the counter is worth, and what a mistake costs. |

**The purpose** is a close-quarters rhythm of parries, sways and counters, in which the player makes space by what
they land, not by leaving, and in which standing his ground under a long attack is the bravest and most rewarding thing
he can do.

**Closest references:** Sifu (hold guard and flick a direction to weave, duck or hop) for the input; a boxer's slips for
the opening tempo; Dragon Ball for the flurry and the afterimage.

## 2. Controls

| Action | Gamepad | Keyboard and mouse |
|---|---|---|
| Guard; a timed tap parries | LB | Q |
| Sway (guard held) | LB + flick the left stick left, right or up | Q + A, D or W |
| Duck (guard held) | LB + flick the left stick down | Q + S |
| Dash-step | A / Cross + a direction | Shift or Space + a direction |
| Hop | A / Cross, stick at rest | Shift or Space, no direction |
| Sprint | hold A / Cross | hold Shift or Space |

- **A sway is a press, not a hold.** A direction that goes down while guard is held starts a sway or duck. A direction
  already held when guard goes down starts nothing.
- **Guard and a direction pressed on the same frame** is a sway. The guard need not be up first, so the answer comes
  within the 2-frame response limit.
- **The stick flicks** with the thresholds target switching already uses: down past 0.6, up again below 0.35.
- **Abarax stands his ground while guard is held.** He no longer walks with his guard up. Letting go of guard gives the
  legs back.
- **Directions are the screen's.** A, D and W sway toward that side of the screen. S always ducks.
- All of it can be rebound, as every control can.

## 3. The rules

### 3.1 Sways and ducks

An **ordinary blow** is any blow that is not a sweep, a thrust or a grab.

A sway or a duck opens an **evade window**. While it is open, every ordinary blow and every grab that would land on
Abarax is **evaded**, whoever throws it and from whichever side. One sway therefore slips two or three blows that land
together.

- The feet stay planted. A sway is a slip and a dip: the head goes about 0.3 m off the line and drops a little with
  it; a duck drops the whole body. He stays in range.
- **A dodge must be seen.** The game is drawn small (a fighter is about 55 pixels tall), so each sway, pull and duck is
  sized by what shows on screen, whichever way he faces, not by what a real boxer's slip measures.
- A sway leans toward the pressed side of the screen. Measured against the way he faces, that is a lean to his left, to
  his right, or back (a pull). A press straight toward the foe is a slip to his left.
- **An evade window does not stop a sweep or a thrust.** Those have their own answers (3.5).
- **Outside its evade window a sway or duck does not guard.** A blow that lands in its other frames is a hit.
- A sway or duck needs stamina as any dodge does. With none, the press is refused and the stamina bar says so.
- How long a sway or duck takes, how long its window is and what it costs depend on the chain's tempo (3.3).

### 3.2 The perfect dodge

Every blow has a **line** in its data: **straight** (a jab, a cross, a thrust) or **round** (a hook, a swing).

| The blow | The matching dodge |
|---|---|
| Straight | Sway |
| Round | Duck |
| Grab | Either |

An evade with the matching dodge is a **perfect dodge**:

- its stamina cost comes back, and 4 more;
- it counts double toward the chain (3.3);
- an afterimage and a cue mark it (section 5).

An evade with the other dodge still avoids the blow, and counts once.

### 3.3 The chain: from slips to a flurry

Defences that succeed in a row form a **chain**. It is the rhythm of standing one's ground.

**What builds it.** Each evade and each parry or catch adds 1. A perfect dodge adds 2.

**What ends it.**

- Abarax attacks: the chain is cashed in (3.4).
- He walks, dash-steps or hops.
- 60 frames pass without a defence that succeeds.
- A blow lands on him: he is **knocked out** of the chain (below). A broken guard ends it too.

A blow he guards neither builds the chain nor ends it.

**The three tempos.** The chain's count sets the tempo of every sway and duck he makes.

| Tempo | Chain | Sway: length, window | Duck: length, window | Stamina (sway, duck) | Each evade takes from the attacker's posture |
|---|---|---|---|---|---|
| **Slip** | 0–2 | 22 frames, 10 | 26 frames, 12 | 6, 8 | 0 |
| **Quick** | 3–6 | 16 frames, 8 | 18 frames, 9 | 4, 5 | 4 |
| **Flurry** | 7 and up | 12 frames, 6 | 14 frames, 7 | 3, 4 | 8 |

- Every evade window opens on the move's second frame.
- **Slip** is the weighty boxer's slip: the weight shifts and the body commits. It is the opening rhythm.
- **Quick** is shorter and sharper. It keeps pace with a faster string, and its window is tighter.
- **Flurry** is near-instant, and every dodge leaves an afterimage. Its window is 6 or 7 frames: the buttons have to be
  known by now.
- From Quick on, dodging is itself an attack on the enemy's balance: each blow it throws at nothing costs it posture.
  A perfect dodge doubles that. A long string dodged through can break the attacker's posture and open the finisher.

**Knocked out.** A blow that lands on Abarax while the chain is at Quick or Flurry does more than hurt: whatever its
weight, he is **staggered** (the long reaction), and the chain is gone. At Slip a blow that lands is an ordinary hit.
The longer he stands and dodges, the more he has to lose.

**The slow-down.** The fight slows to 40% for 12 frames at two moments only: the first perfect dodge of a chain, and
the dodge that carries the chain into Flurry. After that the rhythm only climbs.

### 3.4 Counters and clear-outs

After an evade, the next palm or heavy pressed within 24 frames is that dodge's counter. After a dodge that avoided
nothing, palm and heavy are the ordinary jab and heavy.

| Dodged with | Palm: the counter | Heavy: the clear-out |
|---|---|---|
| Sway | A hook to the body: fast (blow by frame 8), one target, flinches | A turning back-palm across a 150° arc in front, reach 1.8 m: knocks each foe it meets about 2 m sideways |
| Duck | A rising palm: fast (blow by frame 9), one target, staggers | A low palm wave all round him, radius 2 m: shoves everyone about 2 m back |

A counter or clear-out cashes the chain in. What it is worth depends on the tempo the chain had reached:

| Tempo reached | Damage and posture damage | Clear-out throws | Also |
|---|---|---|---|
| Slip | the move's own | 2 m | |
| Quick | half as much again | 2.5 m | |
| Flurry | double | 3 m | the counter staggers its target whatever its poise |

- A clear-out costs 20 stamina, does little damage, and is there to make room.
- A body knocked back by a clear-out stops at walls and at other bodies, as every knockback does.
- A counter or clear-out is an attack like any other: it can be parried by an enemy that can parry, and it leaves
  Abarax open if it misses.

### 3.5 Unblockable attacks

Each keeps one answer, and its icon shows it.

| Attack | Answer | Icon |
|---|---|---|
| Sweep | Hop it. A sway or a duck is hit. | The upward chevron over a low bar (unchanged) |
| Thrust | Catch it with a parry. A sway or a duck is hit. | The point between two brackets (unchanged) |
| Grab | Slip it with any sway or duck; that is a perfect dodge. | A new glyph: a body leaning off a line. It replaces the sideways double chevron ("roll away") |

- A catch adds to the chain as a parry does. A hop ends the chain: it is an answer, not part of the rhythm.
- A dash-step that carries Abarax out of reach before the blow lands avoids anything, as walking away would.

### 3.6 Chaining one move into the next

- **After an evade**, the sway or duck can be cancelled from the frame its evade window closes into another sway, a
  duck, a parry, a guard, a counter or a clear-out. So parry, sway, sway, duck flows without a gap, at every tempo.
- **After a dodge that avoided nothing**, another sway or duck cannot start until twice the window's length has passed
  (frame 20 of a Slip sway, 16 of a Quick one, 12 of a Flurry one). A sway is a commitment. Mashing sways covers at most
  half of any stretch of time, at every tempo, and drains stamina.
- A parry can be cancelled into a sway or duck once its window has closed, and a sway into a parry by the rule above.
- The parry's own rule stands: a guard pressed again within 20 frames opens no fresh parry window.
- The 9-frame input buffer holds a sway or duck as it holds any press.

### 3.7 The dash-step and the hop

| Move | Travel | Length | Invulnerable | Stamina |
|---|---|---|---|---|
| Dash-step | 1.3 m along the stick, over 10 frames | 18 frames | Never | 8 |
| Hop | As today | As today | Airborne, as today: a low blow passes under | 12 |

- The dash-step is the minimal dash: for a larger enemy's reach, for an area attack, for closing in.
- It keeps Abarax facing his target (the lock, or the cursor; with neither, the way he already faces) and stops at
  bodies and walls.
- It is a step, not a slide: the legs stride the way he goes and come back under him as he stops.
- From frame 10 it can be cancelled into a palm, a heavy, a guard, a sway or a duck: dash in and strike.
- Holding the key after the dash-step sprints, as it did after the roll.

## 4. Enemies

- Every enemy blow gets its line in data. The Knuckle: jab and cross straight, hook and second hook round, thrust
  straight (and caught), sweep low (and hopped), grab slipped.
- Against the Knuckle's jab, cross, hook, the perfect line is sway, sway, duck: two slips and then a Quick duck, a chain
  of 6, and a counter worth half as much again. The rhythm already rises inside one combo.
- **The Knuckle's brain does not change in this piece.** It already chooses by range, commits, and can be smothered and
  escaped.
- **Strings to stand in.** The chain needs enemies whose attacks go on: strings of five to seven blows that gather
  speed and mix straight and round, so that the player is asked to stand and dodge, faster and faster. Enemy strings are
  already data. The Knuckle variants (the task after this piece) include at least one such string, and are tuned
  against the chain.
- **Not in this piece:** enemies that sway, and enemies that bait a sway with a delayed swing. They belong to later
  tiers and to the elite Finger of the Hand, as the foundation design's "skill-aware variants" describes.

## 5. Look, sound and readability

- **Slip:** a weighty slip and dip from the planted guard stance, out and back: the head and shoulders go off the line,
  the body sinks, the weight goes onto one leg. A pull back folds the body away and tucks the chin. **Duck:** a drop
  under the swing and up.
- **Quick:** the same shapes, smaller and sharper.
- **Flurry:** near-instant leans. Every dodge leaves an afterimage (a fading copy of his silhouette where he was, about
  8 frames), drawn behind him.
- **Evade:** a soft whoosh, and the blow visibly passes where the head was. The whoosh rises a step in pitch with each
  link of the chain, so the rhythm can be heard climbing.
- **The chain is read on Abarax, not on a meter:** his tempo, the afterimages, the rising pitch, and from Quick on a thin
  white-gold rim that brightens at Flurry. Nothing covers his outfit.
- **Perfect dodge:** an afterimage at any tempo, and a brighter cue.
- **Knocked out:** the rim and the pitch cut off, a hard cue, and the stagger.
- **Counter and clear-out:** the palm trail the open hand already has, larger with the tempo cashed in. The duck's
  clear-out sends a pale gold ring across the ground from his feet, the same kind of ground wave the unblockable tells
  use.
- The tells from the readability pass stand: the blue-white rim on blows that can be parried, the rose rim, ground wave
  and icon on unblockable ones.
- The controls hint lists the new keys.
- Every length, window, cost, distance, threshold and colour above is tuning data. The slow-down and the afterimage each
  have a switch.

## 6. Architecture

The change follows the existing layers: input, intent, moves and marks, the rules of a blow, effects.

- **Input.** `PlayerBrain` turns "a direction pressed while guard is held" into the actions `sway` and `duck`, with the
  direction. An enemy brain can press the same actions later. Nothing else reads raw keys.
- **Moves.** Sways, ducks and the dash-step are moves in Abarax's moveset, with their timelines in marks, like every
  move. Each tempo's sway and duck is its own move and clip, so the clip checker sees every one. The dodge action starts
  the dash-step, and its neutral variant stays the hop. `dodge_roll` is deleted.
- **Marks.** A new pair, `evade_on` and `evade_off`, opens and closes the evade window. A move says which dodge it is
  (sway or duck). `iframes_on/off` stays for moves that are untouchable by everything.
- **The rules of a blow** (`Combat.resolve`) gain one rule and one outcome, **EVADED**, with a `perfect` flag:
  an evading target avoids an ordinary blow or a grab; a sweep or a thrust goes on down the rules. The defender learns
  of an evade through the same `got_hit` signal every outcome uses.
- **`HitProfile`** gains `line` (straight or round).
- **The chain** is one small part of the actor. It listens to the outcomes of blows (an evade, a parry or a catch
  builds it; a hit knocks him out of it) and to what he does (an attack, a step or the clock ends it). Everything that
  depends on the tempo asks it: which sway to start, what a counter is worth, what an evade costs the attacker, what the
  effects show. Its thresholds and tables are one tuning resource, so a fighting style can bring its own later.
- **The counter window** lives in the move runner: after an evade, the cancel windows of the sway and duck lead to the
  counters; otherwise to the ordinary jab and heavy.
- **The slow-down** is counted in frames and applied the way hit-stop is, so a replay of recorded input stays exact.
- **The clip checker** learns the new rules: a sway or duck has exactly one evade window of its tempo's length inside
  its clip; a dash-step has none and no invulnerability; a counter's blow comes by the stated frame.
- **Clips.** The animation packs hold no sway or duck. They are built the way other missing moves are: hand-keyed bone
  layers over existing clips (the guard stance for sways; the crouch clip for the duck), retimed for each tempo, and
  joined clips for the counters and the dash-step. Each is checked on a contact sheet at 640×360.

## 7. Testing

- **Rules:** every pairing of dodge and blow (ordinary straight, ordinary round, sweep, thrust, grab) gives the outcome
  the tables state, and the perfect flag follows the match table.
- **Windows:** each tempo's evade window; nothing is avoided a frame before or after it.
- **Several attackers:** three blows landing inside one window are all evaded; a fourth landing after it hits.
- **The chain:** what adds 1 and what adds 2; each thing that ends it; the tempo at each count; the stamina cost and the
  posture taken from the attacker at each tempo.
- **Knocked out:** a blow landing at Quick or Flurry staggers whatever its weight and empties the chain; at Slip it is
  an ordinary hit.
- **Cashing in:** a counter and a clear-out from each tempo are worth what the table states; a Flurry counter staggers
  a foe whose poise would shrug the blow off.
- **A string climbed:** against a scripted string of seven blows that gathers speed, the right dodges take no damage,
  reach Flurry, and break the attacker's posture or leave it within one counter of breaking.
- **Mashing:** at every tempo, sways mashed with no blow incoming are evading at most half the frames; mashing never
  lengthens a window and never builds the chain.
- **Chains of moves:** parry, sway, sway, duck against a scripted jab, cross, hook takes no damage; each cancel opens on
  its stated frame.
- **Input:** a direction pressed with guard held sways; a direction already held does not; guard and a direction on the
  same frame sways within 2 frames; the stick's flick thresholds; S ducks whatever way he faces.
- **The planted guard:** no travel while guard is held.
- **Dash-step:** its travel, that a blow during it lands, that it stops at bodies and walls, its cancel frame, and that
  it ends the chain.
- **Counters:** they follow only an evade; the clear-outs move each body they meet the stated distance and none through
  a wall or a corner of the yard.
- **The slow-down:** its length in frames, that it comes at its two moments and no others, and that a recorded fight
  replays to the same state.
- **Look and sound:** render tests that the afterimage and the chain's rim change no pixel of his body's interior, and
  that the grab's new icon draws; the whoosh's pitch steps with the chain.
- **The game still plays:** the self-test fights with sways and a dash-step in place of the roll, and exits clean.

## 8. Where it fits

- It is built inside F1, after Task 14 (the yard and the HUD) and before the Knuckle variants, the combat bot and the
  feel metrics. The bot and the replay tool must play with the final defence, and the variants' strings are written for
  the chain.
- F1's constraint "the dodge has 13 invulnerable frames of 30" is replaced by the windows in section 3.
- It gets its own short implementation plan.

## 9. Out of scope

- Enemies that sway or bait sways.
- The long enemy strings themselves (the Knuckle variants' task), beyond a scripted one for the tests.
- Fighting styles, the powers, and timed-input specials. Each style will bring its own sways, counters and chain; this
  piece builds the one set the Open Hand starts with, in a shape styles can replace as data.
- A cinematic camera for perfect dodges and flurries (F4).

## 10. Risks

| Risk | Answer |
|---|---|
| Hand-keyed sways look stiff | Contact sheets and rendered frames are reviewed before the moves are accepted; the lean rides on the breathing and look layers already in the rig |
| The evade window makes the player untouchable | The whiff rule (3.6), stamina, the tighter windows of the faster tempos, the two attacks an evade does not stop, and the stagger for a mistake made deep in a chain; measured by the mashing test and by the bot |
| The chain is never felt, because the Knuckle's string is three blows | Three perfect dodges already reach Quick, so the third dodge of a combo is faster than the first; the variants' longer strings are what Flurry is built for |
| Being knocked out of a long chain feels unfair | Only a blow that really lands does it; every tell and icon still shows; the stagger's length is tuning data |
| The slow-down drags | It comes twice in a chain at most, is tuning data, and has a switch |
| Losing the roll leaves no escape from a corner | The dash-step, the clear-outs, and the yard's corner tests |
| Screen-relative sways confuse when he faces sideways | A sideways press reads as a pull back or a slip in, both real dodges; on the owner's checklist to feel |
