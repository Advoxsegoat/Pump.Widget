# F1 feel numbers: what the combat bot found (Task 16)

What this is: how the fight plays, measured by the combat bot (`tools/bot`) on the game as it stood on Nov 15 (main at fd516de plus the bot's
per-blow table). Not a tuning pass: nothing in the game was changed for any number below. The two questions were the owner's: does timing
beat mashing without mashing being worthless, and is the game fair to a person's reactions.

## What was run

Seeds 1 to 10, 7,200 frames each (two minutes of play), the yard's own waves, the bot playing Abarax as a pad player:

    tools/godot.sh --headless -s res://tools/bot/run_bot.gd -- --seeds=1-10 --frames=7200 --policy=<p> --reaction=<r> --detail

for mash, aggress, counter and mixed at the default reaction of 14 frames (a person's, about 230 ms; the bot sees nothing sooner than
that, each blow's reaction jittered by up to 3 frames), and counter and mixed again at 10 and 18. "Waves" is waves cleared in the ten
seeds together (the yard has twelve and a seed reaches the fourth or fifth); "dealt" and "taken" are HP; a "death" is the bot's Abarax dying
(the yard resets him). 0 problems (no soft-lock, no engine error, nothing out of bounds) in all 80 runs. In one of them (counter at 14, seed 7)
the engine itself died (signal 11, the known one in long runs); the supervisor ran that seed again and the numbers below are of the rerun.
The foes the bot met: tier I and II, the Drummer, and the blade (twice, at a reaction of 10). Nobody met tier III or the heavy Knuckle in
two minutes. The yard's waves hold at most two foes alive, so the three-foe surround (which the owner decided on Nov 15 to keep: a fight
with three foes is 7 to 32% harder, and that is wanted) is not in these tables; it is in the frame budget's four-Knuckle fight.

## Does timing beat mashing (reaction 14)

| policy | waves | deaths | dealt | taken | taken per HP dealt | seeds with a wave |
|---|---|---|---|---|---|---|
| mash | 31 | 43 | 5994 | 6667 | 1.11 | 10 of 10 |
| aggress | 17 | 28 | 2826 | 4009 | 1.42 | 10 of 10 |
| counter | 12 | 18 | 2123 | 2675 | 1.26 | 10 of 10 |
| mixed | 34 | 11 | 4162 | 2803 | 0.67 | 10 of 10 |

The first addendum expected `counter` and `mixed` to clear several times more waves than `mash`. They do not: at 14 frames `mixed` clears a
few more (34 against 31) and dies a quarter as often (11 against 43), and `counter` clears fewer than half as many (12). The reason is in the
by-blow table below: a player who starts nothing and answers only what it sees is hit by the tier I's jab (15 frames from its tell to its
blow) as often as it is not. At a reaction of 10 timing wins by a long way (next table). The suite holds the ordering over three seeds
(`tests/bot/test_feel_ordering.gd`: the masher clears a wave in most seeds and takes about as much as it deals; mixed at 14 takes less than it
deals and dies under half as often; counter at 10 takes under half of what it deals and clears as many waves with no more deaths).

## Is the game fair to a person's reactions (counter and mixed at 10, 14 and 18)

| policy | reaction | waves | deaths | dealt | taken | taken per HP dealt | seeds with a wave | fewest frames from a tell to a defence |
|---|---|---|---|---|---|---|---|---|
| counter | 10 | 40 | 3 | 4859 | 1259 | 0.26 | 10 of 10 | 7 |
| counter | 14 | 12 | 18 | 2123 | 2675 | 1.26 | 10 of 10 | 11 |
| counter | 18 | 5 | 33 | 1632 | 4255 | 2.61 | 5 of 10 | 15 |
| mixed | 10 | 43 | 7 | 4928 | 2040 | 0.41 | 10 of 10 | 7 |
| mixed | 14 | 34 | 11 | 4162 | 2803 | 0.67 | 10 of 10 | 11 |
| mixed | 18 | 10 | 47 | 2909 | 6004 | 2.06 | 10 of 10 | 15 |

"Gently" is not what this is. From 10 to 18 frames (130 ms) the waves cleared fall to an eighth for `counter` (40 to 5) and to under a quarter
for `mixed` (43 to 10), the HP taken rises 3.4 and 2.9 times, and the deaths rise 11 and 6.7 times. Half of that fall is between 14 and 18 (4 frames,
67 ms): `counter` 12 to 5, `mixed` 34 to 10. At 18 a careful player does still clear waves, but only the first: `mixed` clears exactly one in each of
the ten seeds (a lone tier I) and then dies; `counter` clears one in five of the seeds.

### The blow that does the damage at 18 (by blow; share of the HP taken)

| policy | blow | HP taken | share | how it met the bot |
|---|---|---|---|---|
| counter at 18 | tier I jab | 3030 | 71% | hit 303, parried 6, evaded 3 |
| counter at 18 | tier I cross | 1140 | 27% | hit 95, parried 102, evaded 65 |
| mixed at 18 | tier I jab | 3740 | 62% | hit 374, parried 4, evaded 1 |
| mixed at 18 | tier I cross | 1704 | 28% | hit 142, parried 80, evaded 67 |
| counter at 14 | tier I jab | 2050 | 77% | hit 205, parried 131, evaded 60 |
| mixed at 14 | tier I jab | 1350 | 48% | hit 135, parried 72, evaded 25 |
| counter at 10 | tier I jab | 420 | 33% | hit 42, parried 51, evaded 166 |

**The tier I's jab is the tell that is too short.** It accounts for most of the HP taken at 18 (71% and 62%) and is dodged on sight 3 times in 306
at that reaction (the bot answers a blow only after its reaction plus a dodge's 4-frame lead, and the jab's tell is 15 frames from the glint to
the blow). It goes to the owner's list; it is not changed here. (What would change it is the tell's length in the Knuckle's jab, or a longer
window for the sway's evade.) The cross (20 frames) is next and is mostly parried or evaded; the hook, the sweep and the thrust are not where the
damage is. The Drummer's string was never met by `counter` at 18 (a bot that dies on the first wave does not reach it); at 14 it takes 20 HP in the one
wave `counter` clears with him, at 10 it takes 5 in ten.

## What the three tables say

Timing beats mashing, and the margin is the player's reaction: at 10 frames the counter player clears 40 waves with 3 deaths and loses a quarter of an HP
for each it deals, at 14 the mixed player is still clearly ahead of the masher on deaths (11 against 43) and damage (0.67 against 1.11 HP taken per HP dealt)
but a player who only counters is not, and the masher is not worthless (it clears a wave in all ten seeds and about three in a seed). The game is not
fair by degrees to a slower reaction: between 10 and 18 frames the clears fall four to eight times and the deaths six to eleven times, a cliff and not a
slope. Most of it is one blow, the tier I's jab, whose 15-frame tell is about a person's reaction, so a slow-reacting player is hit by it nearly every time
and cannot get through the first waves.

## What the bot cannot do (one line each)

- It never met tier III or the heavy Knuckle within 7,200 frames at any reaction, and the blade only twice (reaction 10); a longer run
  (`--frames=43200 --reaction=10`) is the way to see them.
- A `counter` player at 14 or 18 frames cannot clear the second wave (two tier I's together) in nine seeds of ten: it starts nothing, so what it deals comes from its counters alone.
- Its reaction is one number a blow; a person's varies with attention, and the bot never mistakes one blow for another.
- A long single-process sweep can kill the engine (signal 11); `run_bot.gd` plays a seed per process and runs it again once it dies.


# After the tuning of Nov 16 (Task 17)

What this is: the same sweep as above (seeds 1 to 10, 7,200 frames, `--detail`, the bot not changed: its policies, its reaction and its reading of tells are
as they were) on the game after the three changes the owner chose on Nov 16 (3.A, and "4.A-B, scaling with stamina xp, can be upgraded later"):

- **The tier I's jab gives a longer warning** (`knuckle_jab_long`, tier I only): 20 frames from the glint to the blow, not 15. Tiers II and III and the Drummer keep the 15-frame jab.
- **Timing pays more**: a foe whose blow Abarax parried, caught or perfectly dodged is *open* for 40 frames of Abarax's own clock (`CombatTuning.punish_frames`) until
  he starts a move of his own, and Abarax's blows on him are worth 1.5 times (`punish_scale`) in HP, posture and hit-stop. It multiplies with what a counter cashes
  (a Flurry counter is 2 x 1.5). The foes' tuning says 1.
- **Mashing costs stamina**, scaled by 100 / max_stamina (1 today, so the stamina stat the levelling raises later is what pays for more mashing): a press of palm, heavy,
  sway or duck made while the same action's last press is still waiting in the buffer, or while its move has not yet reached its first cancel window, is redundant; the
  first one in a move is free and each after it costs `hammer_tax` (2.0); and a sway or duck that evades nothing makes the next cost half its base more (x1.5 to x3,
  `strain_step` 0.5), until one evades something or 60 frames pass. The foes' tuning has both off.

The "before" is the game as it stood at c52b512 (main of Nov 16 with Task 15c: foes do not swing at walls), which is not the table above (Task 15c moved how foes move).
No number the brief named was moved: 40 frames, 1.5, 2.0 and 0.5 are the ones it gave.

## Before and after (ten seeds, 7,200 frames)

| policy | reaction | | waves | deaths | dealt | taken | taken per HP dealt | seeds with a wave |
|---|---|---|---|---|---|---|---|---|
| mash | 14 | before | 31 | 43 | 5994 | 6667 | 1.11 | 10 of 10 |
| mash | 14 | **after** | 10 | 75 | 1216 | 8981 | 7.39 | 10 of 10 |
| counter | 14 | before | 14 | 16 | 2191 | 2565 | 1.17 | 10 of 10 |
| counter | 14 | **after** | 36 | 0 | 4585 | 1294 | 0.28 | 10 of 10 |
| mixed | 14 | before | 34 | 10 | 4163 | 2757 | 0.66 | 10 of 10 |
| mixed | 14 | **after** | 43 | 10 | 5575 | 2680 | 0.48 | 10 of 10 |
| counter | 10 | before | 38 | 4 | 4741 | 1362 | 0.29 | 10 of 10 |
| counter | 10 | **after** | 42 | 0 | 5751 | 1084 | 0.19 | 10 of 10 |
| mixed | 10 | before | 44 | 7 | 5178 | 2026 | 0.39 | 10 of 10 |
| mixed | 10 | **after** | 46 | 6 | 5888 | 2207 | 0.37 | 10 of 10 |
| counter | 18 | before | 5 | 33 | 1632 | 4255 | 2.61 | 5 of 10 |
| counter | 18 | **after** | 14 | 14 | 2061 | 2529 | 1.23 | 10 of 10 |
| mixed | 18 | before | 10 | 47 | 2918 | 5868 | 2.01 | 10 of 10 |
| mixed | 18 | **after** | 39 | 11 | 4612 | 3557 | 0.77 | 10 of 10 |

0 problems (no soft-lock, no engine error) in all 70 runs of the "after" and in the 70 of the "before". The fewest frames from a tell to a defence is as it was (7, 11 and 15 at
10, 14 and 18): the bot's reaction was not changed.

## The blow that does the damage at 18 (the tier I's jab, by blow)

| policy | | HP taken | share | how it met the bot |
|---|---|---|---|---|
| counter at 18 | before: tier I jab | 3030 | 71% | hit 303, parried 6, evaded 3 |
| counter at 18 | **after**: tier I long jab | 1300 | 51% | hit 130, parried 119, evaded 87, guarded 1 |
| counter at 18 | before: tier I cross | 1140 | 27% | hit 95, parried 102, evaded 65 |
| counter at 18 | **after**: tier I cross | 984 | 39% | hit 82, parried 25, evaded 38, guarded 1 |
| mixed at 18 | before: tier I jab | 3710 | 63% | hit 371, parried 3, evaded 2 |
| mixed at 18 | **after**: tier I long jab | 860 | 24% | hit 86, parried 70, evaded 34 |
| counter at 14 | before: tier I jab | 1980 | 77% | hit 198, parried 123, evaded 60, guarded 2 |
| counter at 14 | **after**: tier I long jab | 190 | 15% | hit 19, parried 21, evaded 174, guarded 1 |

## What each change did (counter and mixed; the others as the first rows of the table; the jab first, then each of the other two added to it)

| | mash 14 | counter 14 | mixed 14 | counter 10 | counter 18 | tier I jab's share at 18 |
|---|---|---|---|---|---|---|
| before | 31 waves, 43 deaths, 1.11 | 14, 16, 1.17 | 34, 10, 0.66 | 38, 4, 0.29 | 5, 33, 2.61 | 71% |
| the long jab alone | 25, 40, 1.26 | 34, 2, 0.30 | 40, 7, 0.49 | 44, 1, 0.19 | 12, 12, 1.44 | 56% |
| + the open foe | 25, 40, 1.25 | 36, 0, 0.28 | 43, 10, 0.48 | 42, 0, 0.19 | 14, 14, 1.23 | 51% |
| the long jab + the cost of mashing (no open foe) | 10, 75, 7.42 | 34, 2, 0.30 | 40, 7, 0.49 | 44, 1, 0.19 | 12, 12, 1.44 | 56% |
| all three | 10, 75, 7.39 | 36, 0, 0.28 | 43, 10, 0.48 | 42, 0, 0.19 | 14, 14, 1.23 | 51% |

(each cell: waves, deaths, HP taken per HP dealt.) **The jab did the work on the cliff**: at 14 `counter` goes from 14 waves and 16 deaths to 34 and 2 with the longer jab alone, and
at 18 from 5 waves and 33 deaths to 12 and 12. **The open foe makes timing pay**: it takes the loss at 18 from 1.44 to 1.23 HP taken for each dealt and `counter` at 14 from 2 deaths
to 0; it is what lifts `mixed` at 14 from 40 to 43 waves. **The cost of mashing touches the masher alone**: `mash` goes from 25 waves to 10, from 1.26 to 7.4 HP taken for each dealt, and
no other policy moves (their presses are one for each blow and their sways mostly evade). A second try with a window of 50 and a scale of 1.7 and a tax of 1 (not kept) moved
nothing the aims depend on: 10 waves and 80 deaths for `mash`, `counter` at 18 12 waves with the jab's share at 54%.

## What the aims said, and where the numbers are

1. `counter` at 14 clears at least as many waves as `mash`: **met**, 36 against 10 (before: 14 against 31).
2. `mixed` at 14 dies at most a third as often as `mash` and clears more waves: **met**, 10 deaths against 75 and 43 waves against 10 (before: 10 against 43, 34 against 31).
3. `mash` clears a wave in at least 8 of 10 seeds: **met**, 10 of 10 (weaker, and not worthless by that count; but it dies 7.5 times a seed, and takes 7.4 HP for each it deals: the bot's masher presses a
   direction every fourth frame and palm every seventh, 15 and 8.6 presses a second, which a person does not; the next section corrects what this said of a person who taps more slowly).
4. The cliff is a slope: `counter` at 18 clears a wave in 10 of 10 seeds (before 5) **met**, takes 1.23 HP for each it deals (before 2.61, bound 1.5) **met**; the tier I jab's share of the HP taken at 18 is 51%
   (before 71%, bound under half): **not met, by a point and a half** (1300 of 2529 HP). At 18 frames the bot answers a blow only after its reaction (jittered by up to 3) and a dodge's 4-frame lead, 19 to 25
   frames, so the 20-frame jab is still hit 130 times in 337 (parried 119 times and evaded 87: three in five are now answered, against 3 in 312 before). What would take the share under half is the jab's 22 or 23
   frames (the brief fixed 20) or a window for the guard that opens a frame earlier; none of the three numbers the tuning could move did (the 50, 1.7 and 1 above gave 54%).
5. `counter` at 10 loses nothing: **met**, 42 waves against 38 and 0 deaths against 4.

The largest single blow now, against each tier: a Flurry counter_rise 14 x 2 x 1.5 = 42 HP and 66 posture, a charged heavy 34 x 1.5 = 51 HP and 52.5 posture, a Flurry counter_hook 36 HP and 54 posture.
Tier I (60 HP, 60 posture) has its posture broken by the counter_rise at Flurry and not its HP emptied; tier II (90 HP, 80 posture) and tier III (130 HP, 100 posture) are neither killed nor broken by
any single blow, from full health and full posture.

## What is still not as the aims say, and what the bot cannot say

- The tier I jab's share at 18 (above): 51%.
- (Mended in fix round 1, below: the long jab's added five frames were the Punch_Jab clip's own quiet guard slowed, 0.7 to 2.1 degrees a step, and a held pose; they now have a keyed layer that draws the lead arm back.)
- The bot's masher is an extreme (15 presses a second): how a person who mashes at 5 to 8 a second plays under the tax is for the owner's hands.
- With the cost of mashing off, the masher met a foe that "never engages" in 901 frames in two seeds (9 and 10) of ten; with it on, and in every other table, nothing: the brain of that foe was not touched here.

# After fix round 1 (the review of Task 17)

The review found three things the notes above had wrong or too kind about; this section is what was done and measured. The bot, its policies and its reaction are as they were.

## What changed

- **The tax is stamina and nothing else (I2).** Before, every taxed press, and the extra cost of a strained sway or duck, went through `spend_stamina` and restarted the 0.6 s wait before stamina comes back,
  so a tax of 2 cost far more than 2: a person tapping palm twice a second was out of stamina for 212 frames of 600 where the base game had 122. Now a tax and a strain's extra spend without restarting the wait
  (`Stats.spend_stamina(amount, false)`); a move, a sway, a block still restart it. **What was said above of a person who taps half as fast ("pays about half the tax") was true of the tax count (10 against 33
  in the review's probe) and not of the time lost (319 against 393 frames of 600), because of this restart.**
- **The cost of mashing gentled (I3), to the softest of the range the controller gave:** `hammer_tax` 2.0 to 1.0, `strain_step` 0.5 to 0.25, `strain_cap` 3.0 to 2.0 (x1.25, x1.5, x1.75, at most x2). Nothing else moved: not the 40 frames, the 1.5, the jab, the foes.
- **The long jab's wind-up is a drawing back (I1):** a hand-keyed layer (`assets/anim/layers/knuckle_jab_long.json`, laid over the clip by the clip tools) turns the lead shoulder back 20 degrees and folds the lead forearm 46 degrees
  toward it across the five drawn poses from the tell (f5, no layer) to f20, and is nothing at the blow (f25): the marks, the blow and everything after it are as they were (the clip checker passes with 68 moves; after the blow no bone is
  more than 1.1 degrees from the jab's pose five frames earlier, which is the warp's own).
- **A pad trigger hovering at 0.5 is one press (M1):** the triggers press at 0.5 and let go below 0.3, as a flick of the stick does.

## The masher, measured (bot, reaction 14, ten seeds, 7,200 frames)

| the cost of mashing | waves | deaths | dealt | taken | taken per HP dealt |
|---|---|---|---|---|---|
| none (hammer_tax 0, strain 0): the game as it was before the cost | 25 | 40 | 5036 | 6294 | 1.25 |
| first build (tax 2.0, strain 0.5, cap 3.0, restarting the wait) | 10 | 75 | 1216 | 8981 | 7.39 |
| tax 2.0, strain 0.5, cap 3.0, stamina only (I2 alone) | 10 | 78 | 2858 | 9123 | 3.19 |
| tax 1.0, no strain | 10 | 75 | 3866 | 8809 | 2.28 |
| no tax, strain 0.25, cap 2.0 | 20 | 52 | 5202 | 7254 | 1.39 |
| **tax 1.0, strain 0.25, cap 2.0, stamina only (kept)** | **10** | **76** | **3639** | **8799** | **2.42** |

**The band the controller set (15 to 26 waves, at most 60 deaths, 2,700 to 4,800 dealt) is NOT reached with the three levers.** The nearest is the kept row: dealt 3,639 is inside the band; waves 10 is under it (by 5) and deaths 76 is over it (by 16). The tax is what does it
(the row with the tax alone gives the same 10 waves and 75 deaths; the strain alone gives 20 and 52, inside the band), and the tax's softest allowed value, 1.0, is already too much for the bot, which presses palm every seventh frame. What the kept row does hold: the masher still
clears a wave in 10 of 10 seeds, stays below `mixed` (43) and `counter` (36) in waves, and takes 2.42 HP for each it deals against `mixed`'s 0.48 (five times as much; the band asked for twice). What would reach the band, which is not one of the three levers: a tax that starts at the
third redundant press, or one that is not paid on a press in a move's own first frames; or a lower floor than 1.0 on `hammer_tax` (the strain alone, at 0.25, gives 20 waves and 52 deaths).

## By hand speed (10 s of palm taps beside a tier I; frames of 600 in which Abarax cannot start a move)

| | steady tapper, 2 a second | masher, 6 a second |
|---|---|---|
| the base game (no cost) | 130 | 195 |
| the first build, in the review's probe | 212 | 365 (61% of ten seconds) |
| the tax restarting the wait, tuning as now (tests/actors/test_mash_cost.gd, foe 2 m off, seed 7) | 130 | 314 |
| **now** (stamina only, tuning as now) | **130** | **195** |

The bounds the controller set (a tapper at 2 a second out for at most 140 of 600, a masher at 6 a second able to act at least half the time) both hold, and both are tests (`test_a_steady_tapper_at_two_a_second_is_barely_held_back`,
`test_a_masher_at_six_a_second_can_still_act_half_the_time`). At these speeds the tax costs a person nothing of the time he is able to act: it is the bot's 8.6 and 15 presses a second that pay it.

## All the rows again (ten seeds, 7,200 frames; the by-blow table at 18 is as it was)

| policy | reaction | waves | deaths | dealt | taken | taken per HP dealt |
|---|---|---|---|---|---|---|
| mash | 14 | 10 | 76 | 3639 | 8799 | 2.42 |
| counter | 14 | 36 | 0 | 4585 | 1294 | 0.28 |
| mixed | 14 | 43 | 10 | 5575 | 2680 | 0.48 |
| counter | 10 | 42 | 0 | 5751 | 1084 | 0.19 |
| mixed | 10 | 46 | 6 | 5888 | 2207 | 0.37 |
| counter | 18 | 14 | 14 | 2061 | 2529 | 1.23 |
| mixed | 18 | 39 | 11 | 4612 | 3557 | 0.77 |

Every row but the masher is the same to the unit as the table above (the others do not mash), and the long jab's layer changed none of them (mash at 14 and counter at 18 were run again after it was built). Aim 4's jab share is measured again: the tier I long jab took
1,300 of the 2,529 HP taken at 18, 51%: still not under half, reported only.

`tests/bot/test_feel_ordering.gd` (seeds 1 to 3, 3,600 frames) measured again: mash 3 waves, 9 deaths, 627 dealt, 1187 taken; mixed 8, 1, 1028, 317; counter at 14 6, 0, 804, 157; counter at 10 9, 0, 1008, 135. It gained a bound a worthless masher fails: he deals at least 0.48 of what the mixed player
deals (0.61 measured; a fifth under it; at least the 0.35 asked).
