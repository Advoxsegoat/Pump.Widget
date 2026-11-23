# The All-Divine: the calls made on the owner's behalf, and the review minors left for later (from Nov 16)

This file is the durable copy of the build's ledger: every ruling the controller made where the plan or the owner's words left a choice
(with what it costs if it is wrong), and every review finding graded minor and left for later. It is added to at each merge.

**What is not here.** The working ledgers of F1 (combat core), the sway-and-duck defence, the menus, the Director, the Bilibara stretch and
the portraits lived only on the build machine, which was replaced on Nov 20 while work was stopped. Their rulings and deferred minors from
before Nov 16, 16:00 UTC are lost as lists. What the owner needs from them was written into `all-divine/STATE.md` at each merge and is
still there: the Done lines, the owner checklists, "Known limits / notes for later" and "Decisions". The final review of the whole branch
reads the code again and will find afresh whatever those lists held. F0's record is its own file
(`2026-10-25-all-divine-rpg-f0-foundation-record.md`).

## Standing rulings

- A merge whose tree is the lane head's apart from `STATE.md` (and docs) is pushed without a second whole headless run on the main tree,
  when the lane head has had the whole run and a green cloud run. Cost if wrong: none seen in seven uses.
- A commit that changes only docs, or only render tests, needs no whole headless run. Cost if wrong: a red cloud run.
- A small fix round (specific findings, each with its test, the reviewer's own mutations repeated) is checked by the controller instead
  of a second reviewer, and that is written down each time. Cost if wrong: the final whole-branch review reads the code again.

## Rulings

### F1 Task 15c (foes and walls), merged Nov 16

- No whole headless run on the main tree before the push: the standing ruling above (the lane head's cloud run: 2048 passed, 0 failed).

### F1 Task 17 (the fight's tuning the owner chose on Nov 16)

- "Timing pays more" is built as an **open foe**: a foe whose blow was turned or perfectly dodged takes 1.5 times HP, posture and hit-stop
  from the one who did it, for 40 frames or until he starts a move. "Mashing costs stamina" is built as a **hammer tax** (redundant presses
  after the first, 2 stamina each) plus **strain** (a sway that evades nothing makes the next dearer, up to x3), both scaled by
  100 / max_stamina so that a later stamina upgrade buys more room. The tier I's long jab is its own move (`knuckle_jab_long`, 20 frames);
  tiers II, III and the Drummer keep 15. The owner chose the directions, not the mechanisms: these are the smallest the bot can measure and
  a test can hold. Cost if wrong: the owner dislikes the feel of a taxed double-press or of the punish's size: three numbers in Abarax's
  tuning file turn each off (scale 1, tax 0, strain 0) without touching code.
- The implementer may move `punish_frames`, `punish_scale`, `hammer_tax` and the strain's step to reach five stated aims and must report an
  aim it cannot reach instead of adding a mechanism: the bot is the judge and is not tuned. Cost if wrong: an aim is missed and a second
  round is needed.
- The tuning's lane was brought up to Task 15c before Task 15c reached the main branch (approved, waiting only for its cloud run): the
  tables must be measured on the brain that comes round walls. Cost if wrong: none (it merged unchanged).

### F1 Task 18 (two small choices: the feather hangs; "Off" is dim), merged Nov 22

- The feather is merged at 8 cm as built and its length is put to the owner (the portraits' checklist, item 5): the owner chose "hang it
  as drawn", and a feather that hangs and never crosses the scarf's collar is the honest version of that; as long as drawn needs a lower
  collar or accepted crossings, which is the owner's choice. Cost if wrong: one number in the build script and a rebuilt model.
- No second reviewer (two small jobs, 166 lines, the model rebuilt by its script; the controller read the menu's change and looked at the
  three pictures). Cost if wrong: the final whole-branch review reads 166 lines again.

### The town's systems (plan `2026-11-15-all-divine-stretch-systems.md`)

- The plan's rows 9 and 11 (the Collector bars the lane) wait on the owner's answer about optional mini-bosses; Tasks 1 to 6 go ahead:
  where the toll gate stands is data. Cost if wrong: Task 5's gate data is moved.
- "The Bell slows them" is read as the Pack's chain gap doubled (36 to 72 frames) until the owner says more: the smallest change that is
  a slowing and keeps the Pack a pack. Cost if wrong: one number and its test in Task 6.
- Task 1, fix round 1: no second reviewer (the standing ruling). Cost if wrong: the final review reads the save code again.
- Task 2 started on its lane before Task 1's merge reached the main branch (Task 1 was reviewed and fixed and waited only for its cloud
  run; the merge is made from Task 1's commit, not from the lane's moving head). Cost if wrong: a fix to Task 1 on a lane where Task 2 is
  being written (a small join).
- Task 2: `StretchGround` lives in the game (`world/stretch/stretch_ground.gd`), not in `tests/support` as the plan says: loading a saved
  position must ask whether the place is standing ground, and the game loads nothing from `tests/`. Cost if wrong: none (a file's place).
- Task 2: safe ground is "no living actor of another team within 12 m" behind one function (`StretchRun.is_safe`), which Task 4 narrows
  to "awake": Task 2 has no sleeping foes yet. Cost if wrong: Task 4 changes one function.
- Task 2: a saved game never loads dead or exhausted (HP at least 1; exhaustion and a broken posture are not saved): a load must hand
  over a body that can act. Cost if wrong: a player who saved at 0 stamina loads able to act a second sooner.
- Task 2 pins the yard's hash on its own base and Task 17 (the tuning) re-makes the pin when the two meet, whichever merges second: the
  pin proves Task 2 moved nothing, and that proof is made inside Task 2's lane. Cost if wrong: one extra re-make.

### After the build machine was replaced (Nov 22)

- The Drummer's rim picture test was fixed on the main branch without a whole headless run (a render-test-only commit: the standing
  ruling). Cost if wrong: a red cloud run (it was green: run 643).
- The saved game (systems Task 1) was staged on the main branch of the day in an idle lane for its cloud run (run 644: green, 2094
  passed) and merged from there: its own lane had moved on to Task 2. Cost if wrong: none.
- The texture pass: **the heads come first**. The finishing brief asks for the lightest wood at which every head passes at every
  measured place, with no list of known misses: the owner's words were "lighten the wood, re-check that heads still stand out", and the
  range 0.20 to 0.28 was the controller's number. Cost if wrong: the wood is a little darker than a mid tone at two fronts; one number
  in the texture tool.
- The three tasks that were mid-flight when the machine was lost (the fight's tuning, the shrines, the texture pass) are finished by
  fresh implementers from the commits that were pushed, each with a finishing brief, and then reviewed; every Critical or Important
  finding is reproduced by a second agent before it is fixed (one workflow: finish, review, verify, fix). Cost if wrong: a finding that
  could not be reproduced is dropped; the final whole-branch review is the backstop.
- Review and implementer models stay as before (the cheaper tier for implementers and task reviewers, the most capable for the final
  whole-branch review), though the session was switched to its most thorough mode on Nov 22: the weekly limit stopped all work for five
  days on Nov 16, and that is the cost that matters most to the owner's schedule. Cost if wrong: a task review misses what the stronger
  model would have caught; the final review is on the stronger model.

## Deferred minors

- Systems Task 1: a whole new game verified in `save.tmp` is ignored when the main file is missing after a crash between the last two
  renames (the backup, the game before, is read: the brief allows it).
- Systems Task 1: there is no fsync (GDScript has none): a power cut right after the final rename can leave a bad main file; the backup
  covers it.
- Systems Task 1: `SaveStore.write` returns OK when the folder may not be used (a test, a script): by design; nothing may show "saved"
  on it (Task 2's brief says so).
- Systems Task 1: `at` accepts finite but absurd numbers (1e308, a yaw of 720): Task 2 checks the place against the ground and
  normalises the yaw.
- F1 Task 18: the new capsule on the scarf's simulator nudges the scarf's physics slightly (`test_scarf` passes); for the art pass.

## Findings kept for the final review

- Seeded fights are not the same on every machine (the cloud's is not the build machine): a rule tuned to ten seeds here failed there
  (Task 15c's gate test). Filed replays depend on fights being the same everywhere; rules over seeded fights need room.
- A picture test can depend on what ran before it in the same process: `tests/render/test_drummer_start_shots.gd` measured the Drummer's
  red rim at 80.2% against a floor of 80% when it ran first and 78.8% after any other picture file (the player beside him is alive and
  breathing inside the measured box). Found when the saved game's lane dealt the shards differently (Nov 16); fixed on Nov 22.

## For the owner's checklists (kept in STATE.md)

- The saved game on a Windows machine (a virus scanner or indexer holding the save during the rename; the save folder on OneDrive or a
  network share; a read-only save file; a decimal-comma locale; a power cut during a save): STATE.md, "Owner checklist for the town's
  systems", from the task that makes the game save.
