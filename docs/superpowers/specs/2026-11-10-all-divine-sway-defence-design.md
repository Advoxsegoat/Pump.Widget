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

**Decided with the owner:**

| Question | Decision |
|---|---|
| How much does the direction matter? | Timing first. Any well-timed sway or duck avoids an ordinary attack. The direction that fits the attack makes it a **perfect dodge** with a stronger counter. |
| What does the old dodge key do? | The roll is removed. A tap with a direction is a short **dash-step** with no invulnerability. A tap with no direction is the hop. Held, it sprints. |
| How do unblockable attacks work? | Each keeps one answer, shown by its icon: the sweep is hopped, the thrust is caught with a parry, the grab is slipped with any sway or duck. |

**The purpose** is a close-quarters rhythm of parries, sways and counters, in which the player makes space by what
they land, not by leaving.

**Closest references:** Sifu (hold guard and flick a direction to weave, duck or hop) for the input; Dragon Ball for the
look of a flurry slipped by leaning, and the afterimage.

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

| Move | Length | Evade window | Stamina |
|---|---|---|---|
| Sway | 22 frames | frames 2–11 (10 frames) | 6 |
| Duck | 26 frames | frames 2–13 (12 frames) | 8 |

- The feet stay planted. A sway leans the body about 0.2 m; a duck drops it. He stays in range.
- A sway leans toward the pressed side of the screen. Measured against the way he faces, that is a lean to his left, to
  his right, or back (a pull). A press straight toward the foe is a slip to his left.
- **An evade window does not stop a sweep or a thrust.** Those have their own answers (3.4).
- **Outside its evade window a sway or duck does not guard.** A blow that lands in its other frames is a hit.
- A sway or duck needs stamina as any dodge does. With none, the press is refused and the stamina bar says so.

### 3.2 The perfect dodge

Every blow has a **line** in its data: **straight** (a jab, a cross, a thrust) or **round** (a hook, a swing).

| The blow | The matching dodge |
|---|---|
| Straight | Sway |
| Round | Duck |
| Grab | Either |

An evade with the matching dodge is a **perfect dodge**:

- its stamina cost comes back, and 4 more;
- the fight slows to 40% for 12 frames (once per 0.75 s at most, so a slipped combo does not turn to syrup);
- an afterimage and a cue mark it (section 5);
- the counter that follows is stronger (3.3).

An evade with the other dodge still avoids the blow. It only earns the plain counter.

### 3.3 Counters and clear-outs

After an evade, the next palm or heavy pressed within 24 frames is that dodge's counter. After a dodge that avoided
nothing, palm and heavy are the ordinary jab and heavy.

| Dodged with | Palm: the counter | Heavy: the clear-out |
|---|---|---|
| Sway | A hook to the body: fast (blow by frame 8), one target, flinches | A turning back-palm across a 150° arc in front, reach 1.8 m: knocks each foe it meets about 2 m sideways |
| Duck | A rising palm: fast (blow by frame 9), one target, staggers | A low palm wave all round him, radius 2 m: shoves everyone about 2 m back |

- A clear-out costs 20 stamina, does little damage, and is there to make room.
- A body knocked back by a clear-out stops at walls and at other bodies, as every knockback does.
- **After a perfect dodge** the counter does half as much posture damage again, and the clear-out throws its targets 3 m.
- A counter or clear-out is an attack like any other: it can be parried by an enemy that can parry, and it leaves
  Abarax open if it misses.

### 3.4 Unblockable attacks

Each keeps one answer, and its icon shows it.

| Attack | Answer | Icon |
|---|---|---|
| Sweep | Hop it. A sway or a duck is hit. | The upward chevron over a low bar (unchanged) |
| Thrust | Catch it with a parry. A sway or a duck is hit. | The point between two brackets (unchanged) |
| Grab | Slip it with any sway or duck; that is a perfect dodge. | A new glyph: a body leaning off a line. It replaces the sideways double chevron ("roll away") |

A dash-step that carries Abarax out of reach before the blow lands avoids anything, as walking away would.

### 3.5 Chaining

- **After an evade**, the sway or duck can be cancelled from the frame its evade window closes (frame 12 of a sway,
  14 of a duck) into another sway, a duck, a parry, a guard, a counter or a clear-out. So parry, sway, sway, duck flows
  without a gap.
- **After a dodge that avoided nothing**, another sway or duck cannot start until 2 frames before its end (frame 20 of
  a sway, 24 of a duck). A sway is a commitment. Mashing sways covers at most half of any stretch of time, and drains
  stamina.
- A parry can be cancelled into a sway or duck once its window has closed, and a sway into a parry by the rule above.
- The parry's own rule stands: a guard pressed again within 20 frames opens no fresh parry window.
- The 9-frame input buffer holds a sway or duck as it holds any press.

### 3.6 The dash-step and the hop

| Move | Travel | Length | Invulnerable | Stamina |
|---|---|---|---|---|
| Dash-step | 1.3 m along the stick, over 10 frames | 18 frames | Never | 8 |
| Hop | As today | As today | Airborne, as today: a low blow passes under | 12 |

- The dash-step keeps Abarax facing his target (the lock, or the cursor; with neither, the way he already faces) and
  stops at bodies and walls.
- From frame 10 it can be cancelled into a palm, a heavy, a guard, a sway or a duck: dash in and strike.
- Holding the key after the dash-step sprints, as it did after the roll.

## 4. Enemies

- Every enemy blow gets its line in data. The Knuckle: jab and cross straight, hook and second hook round, thrust
  straight (and caught), sweep low (and hopped), grab slipped.
- Against the Knuckle's jab, cross, hook, the perfect line is sway, sway, duck, then a counter.
- **The Knuckle's brain does not change.** It already chooses by range, commits, and can be smothered and escaped.
- **Not in this piece:** enemies that sway, and enemies that bait a sway with a delayed swing. They belong to later
  tiers and to the elite Finger of the Hand, as the foundation design's "skill-aware variants" describes.

## 5. Look, sound and readability

- **Sway:** an upper-body lean from the planted guard stance, out and back. **Duck:** a drop under the swing and up.
- **Evade:** a soft whoosh, and the blow visibly passes where the head was.
- **Perfect dodge:** an afterimage (a fading copy of his silhouette where he stood, about 8 frames), a brighter cue, and
  the slow-down. The afterimage is drawn behind him; nothing covers his outfit.
- **Counter and clear-out:** the palm trail the open hand already has. The duck's clear-out sends a pale gold ring across
  the ground from his feet, the same kind of ground wave the unblockable tells use.
- The tells from the readability pass stand: the blue-white rim on blows that can be parried, the rose rim, ground wave
  and icon on unblockable ones.
- The controls hint lists the new keys.
- Every length, window, cost, distance and colour above is tuning data. The slow-down and the afterimage each have a
  switch.

## 6. Architecture

The change follows the existing layers: input, intent, moves and marks, the rules of a blow, effects.

- **Input.** `PlayerBrain` turns "a direction pressed while guard is held" into the actions `sway` and `duck`, with the
  direction. An enemy brain can press the same actions later. Nothing else reads raw keys.
- **Moves.** `sway`, `duck` and `dash_step` are moves in Abarax's moveset, with their timelines in marks, like every
  move. The dodge action starts `dash_step`, and its neutral variant stays the hop. `dodge_roll` is deleted.
- **Marks.** A new pair, `evade_on` and `evade_off`, opens and closes the evade window. A move says which dodge it is
  (sway or duck). `iframes_on/off` stays for moves that are untouchable by everything.
- **The rules of a blow** (`Combat.resolve`) gain one rule and one outcome, **EVADED**, with a `perfect` flag:
  an evading target avoids an ordinary blow or a grab; a sweep or a thrust goes on down the rules. The defender learns
  of an evade through the same `got_hit` signal every outcome uses, so effects, the counter window and the slow-down
  hang off one place.
- **`HitProfile`** gains `line` (straight or round).
- **The counter window** lives in the move runner: after an evade, the cancel windows of the sway and duck lead to the
  counters; otherwise to the ordinary jab and heavy.
- **The slow-down** is counted in frames and applied the way hit-stop is, so a replay of recorded input stays exact.
- **The clip checker** learns the new rules: a sway or duck has exactly one evade window of the stated length inside
  its clip; a dash-step has none and no invulnerability; a counter's blow comes by the stated frame.
- **Clips.** The animation packs hold no sway or duck. They are built the way other missing moves are: hand-keyed bone
  layers over existing clips (the guard stance for sways; the crouch clip for the duck), and joined clips for the
  counters and the dash-step. Each is checked on a contact sheet at 640×360.

## 7. Testing

- **Rules:** every pairing of dodge and blow (ordinary straight, ordinary round, sweep, thrust, grab) gives the outcome
  the tables state, and the perfect flag follows the match table.
- **Windows:** the evade window's frames; nothing is avoided a frame before or after it.
- **Several attackers:** three blows landing inside one window are all evaded; a fourth landing after it hits.
- **Mashing:** sways mashed with no blow incoming are evading at most half the frames; mashing never lengthens a window.
- **Chains:** parry, sway, sway, duck against a scripted jab, cross, hook takes no damage and scores three perfect
  dodges; each cancel opens on its stated frame.
- **Input:** a direction pressed with guard held sways; a direction already held does not; guard and a direction on the
  same frame sways within 2 frames; the stick's flick thresholds; S ducks whatever way he faces.
- **The planted guard:** no travel while guard is held.
- **Dash-step:** its travel, that a blow during it lands, that it stops at bodies and walls, its cancel frame.
- **Counters:** they follow only an evade; the clear-outs move each body they meet the stated distance and none through
  a wall or a corner of the yard.
- **The slow-down:** its length in frames, its 0.75 s limit, and that a recorded fight replays to the same state.
- **Look:** render tests that the afterimage changes no pixel of his body's interior, and that the grab's new icon
  draws.
- **The game still plays:** the self-test fights with sways and a dash-step in place of the roll, and exits clean.

## 8. Where it fits

- It is built inside F1, after Task 14 (the yard and the HUD) and before the Knuckle variants, the combat bot and the
  feel metrics. The bot and the replay tool must play with the final defence, and the variants' attack mixes should be
  tuned against it.
- F1's constraint "the dodge has 13 invulnerable frames of 30" is replaced by the windows in section 3.
- It gets its own short implementation plan.

## 9. Out of scope

- Enemies that sway or bait sways.
- Fighting styles, the powers, and timed-input specials. Each style will bring its own sways and counters; this piece
  builds the one set the Open Hand starts with, in a shape styles can replace as data.
- A cinematic camera for perfect dodges (F4).

## 10. Risks

| Risk | Answer |
|---|---|
| Hand-keyed sways look stiff | Contact sheets and rendered frames are reviewed before the moves are accepted; the lean rides on the breathing and look layers already in the rig |
| The evade window makes the player untouchable | The whiff rule (3.5), stamina, and the two attacks an evade does not stop; measured by the mashing test and by the bot |
| The slow-down drags | It is limited to once per 0.75 s, is tuning data, and has a switch |
| Losing the roll leaves no escape from a corner | The dash-step, the clear-outs, and the yard's corner tests |
| Screen-relative sways confuse when he faces sideways | A sideways press reads as a pull back or a slip in, both real dodges; on the owner's checklist to feel |
