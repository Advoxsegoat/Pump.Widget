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
damage is. The Drummer's string was never met by `counter` at 18 (a bot that dies on the first wave does not reach it); at 14 it takes 20 HP in the two
waves `counter` clears with him, at 10 it takes 5.

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
