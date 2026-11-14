# The All-Divine: portraits in the owner's hand — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The dialogue portraits are the owner's own pencil drawings, cleaned and tinted, shown as a large card beside the dialogue box; the rest of the cast and Abarax's in-game model follow that drawing.

**Architecture:** A Python tool turns a photographed pencil drawing plus a small recipe file into the game's portrait pictures (paper evened out, the notebook's rules removed, the bust cropped, soft tints laid under the line). The cutscene overlay shows a speaker's portrait as a card drawn at the window's resolution over the pixel picture, so the pencil line keeps its detail. Stand-ins for characters the owner has not drawn yet are made in the same manner and flagged, so that a final scene refuses them.

**Tech Stack:** Python 3 with Pillow and numpy (the tool and its tests); Godot 4.7.2, typed GDScript (the overlay, speakers, checker); Blender's `bpy` through `tools/bpy_test.sh` (the model, Task 3).

**Spec:** the design the owner approved in conversation on 14 Nov 2026, written here because it is short:
- *Your drawing is the portrait.* The scan is cleaned (notebook lines out, pencil kept) and used directly.
- *Tinted pencil* (the owner's choice of three): the line and hatching kept, restrained flat tones underneath (skin, hair, one accent colour a character).
- *A bigger portrait:* a bust about twice the old 48 px slot's height, standing at the left of the dialogue box and rising above it.
- *Expressions* come from small changes to the owner's own eye, brow and mouth lines; the owner can redraw any.
- *The rest of the cast* get stand-ins in the same manner, each with one signature ornament, marked as placeholders until the owner approves or replaces them.
- *His in-game model* is updated to match the drawing: top-knot, cut sides, forelock, stubble, feather earring, mole.
- The reference drawing and what it shows: `docs/art/owner/abarax-portrait-sketch-2026-11-14.jpg`, `docs/art/owner/README.md`.

## Global Constraints

- The owner's drawings are sources and are never edited: they live in `docs/art/owner/`; the game's pictures are made from them by the tool and committed under `all-divine/assets/portraits/<speaker>/<expr>.png`, each with its row in `all-divine/ASSETS.md` (license: ours, the owner's drawing).
- A portrait picture is **464 × 640** (four times the card's 116 × 160 picture pixels), RGB, no alpha.
- The tool is deterministic: the same drawing and recipe give the same bytes.
- Everything outside the card is exactly what it was: the 640×360 picture upscaled by a whole number; with no scene playing the game is byte for byte unchanged (Director Task 2's tests stay green).
- No model names in code, comments, docs or commit messages (the attribution trailer aside). Commit messages start `All-Divine F4: ` (Tasks 1–2) or `All-Divine F2: ` (Task 3).
- Lanes rules (`lanes.md` in the workspace): one lane, backups after every commit, whole headless suite through the lock, no whole render run locally, `STATE.md` is the controller's.

## Review Focus

1. **A drawing that is not this one.** The next drawing will have other rule spacing, a different tilt, a shadow on another side, or plain paper: the tool must fail with a clear line (not a mangled portrait) when it cannot find the page's rules, and work on plain paper.
2. **A stroke lying along a rule.** A lip line, a lash line or a brow that follows a notebook rule for some of its length must not be erased with it.
3. **The card over everything else.** The card is drawn at window resolution above the pixel picture: with the pause menu open, at ×1, ×2, ×3 and a window that does not divide evenly, on the web flag, and when a scene is cut short at any frame, nothing of it is left behind and it never covers the menu.
4. **A speaker with no drawing yet.** A line by a speaker who has only a stand-in, or no portrait at all, still shows a card and never an error; `story_check --final` refuses the stand-in by name.
5. **A long name and three rows of text** beside the wider card still fit the box at 640×360.

---

### Task 1: The sketch tool, Abarax's portrait, and the card

**Files:**
- Create: `all-divine/tools/portraits/sketch_to_portrait.py`, `all-divine/tools/portraits/tests/test_sketch_to_portrait.py`, `docs/art/owner/abarax-portrait-sketch-2026-11-14.recipe.json`, `all-divine/hud/portrait_card.gd`, `all-divine/tests/hud/test_portrait_card.gd`, `all-divine/tests/render/test_portrait_card_draw.gd`
- Modify: `all-divine/hud/cine_overlay.gd`, `all-divine/story/cine_pose.gd` (the free area), `all-divine/story/speaker.gd`, `all-divine/story/shot_checker.gd` (one rule), `all-divine/data/speakers/*.tres`, `all-divine/assets/portraits/abarax/*.png`, `all-divine/ASSETS.md`, `.github/workflows/all-divine.yml` (the Python tests' step), `all-divine/tests/tools/test_ci_workflow.gd`
- Test: the two new test files, `tests/story/` and `tests/render/test_cine_shots.gd` (brought along)

**Interfaces:**
- Consumes: `CineOverlay` (`box_rect`, `tab_rect`, `text_rect`, `portrait_rect`, `free_band`, `release`), `CinePose.solve(shot, progress, world, last, bars)`, `Speaker` (`id`, `display_name`, `portraits`), `ShotChecker` (`PLACEHOLDER`), `PixelStage` (the picture's rect and whole-number scale in the window).
- Produces:
  - `sketch_to_portrait.py --sketch <jpg> --recipe <json> --out <folder> [--only <expr>] [--stages <folder>]`: writes `<expr>.png` (464 × 640) for each expression in the recipe; `--stages` also writes each stage's picture (flat, rules, clean, crop, tint) for a person to look at. Exit 2 with one line naming the stage if it cannot do its work (no rules found on ruled paper, a crop outside the page, a recipe key it does not know).
  - The recipe (JSON): `paper` (`"ruled"` or `"plain"`), `crop` (x0, y0, x1, y1 as fractions of the page), `erase` (rectangles to wipe to paper), `keep` (rectangles the rule removal must not touch), `tints` (a list of `{name, colour, polygon}` in crop fractions, laid under the line as soft washes), `card` (`paper` colour, `ink` colour), `expressions` (`{"neutral": {}}` in this task).
  - `Speaker.placeholder_exprs: Array[StringName]` (expressions whose picture is a stand-in); `Speaker.card(expr) -> Texture2D` (the expression's picture, else `neutral`'s, else the built-in blank card).
  - `PortraitCard` (`Control`): `const CARD := Vector2i(116, 160)`; `show_card(texture)`, `hide_card()`; `card_rect() -> Rect2i` in picture pixels: its left 6 px inside the box's left edge, its bottom 2 px above the box's bottom edge; drawn in the window at the picture's whole-number scale with linear filtering and mipmaps, on top of the pixel picture; freed or hidden with the overlay (`release()`, `_exit_tree`).
  - `CineOverlay`: `portrait_rect()` is the card's rect; `text_rect()` and `tab_rect()` begin 8 px right of the card; `free_rect(bars) -> Rect2i` (right of the card, between the top bar and the tab's top) replaces `free_band` as what a shot with a line is framed in the middle of (`free_band` stays as its rows).
  - The checker lists `placeholder: line <n> of <shot>: <speaker>'s portrait '<expr>' is a stand-in` and `--final` refuses it.
  - `assets/portraits/abarax/neutral.png` made from the owner's drawing; his other five expressions point at it and are in `placeholder_exprs` until Task 2. Every other speaker shows the built-in blank card (cream paper, a grey bust shape) and all its expressions are in `placeholder_exprs` until Task 2.

- [ ] **Step 1: Write the failing tests.**

```python
# tools/portraits/tests/test_sketch_to_portrait.py  (a made page: paper with a shadow down one side, eleven rules tilted up to 4%,
# pencil strokes of several angles, two of them lying along a rule for 40 px, one 30 px horizontal stroke between rules)
def test_the_paper_is_evened_out(self):            # the made shadow is gone: paper within 0.03 of white everywhere outside strokes
def test_the_rules_are_removed(self):              # at least 97% of rule pixels end within 0.05 of paper
def test_strokes_that_cross_a_rule_are_bridged(self):   # every crossing stroke is still one connected dark line
def test_a_stroke_along_a_rule_is_kept(self):      # with its rectangle in `keep`: at least 90% of its pixels still dark; without: the test says how much is lost
def test_a_horizontal_stroke_between_rules_is_kept(self):
def test_plain_paper_needs_no_rules(self):         # paper "plain": the same strokes, untouched
def test_ruled_paper_with_no_rules_found_fails_with_a_line(self):  # exit 2, "rules: none found"
def test_the_output_is_464_by_640_and_the_same_twice(self):
def test_a_tint_lies_under_the_line(self):         # inside a tint's polygon paper pixels take its colour, stroke pixels stay within 10% of their darkness
def test_the_owners_drawing(self):                 # the real sketch and recipe: no rule left (the row profile of the bust's paper is flat within 0.02); the brows, the lash lines, the mole, the earring's ring and the feather keep at least 90% of their darkness; the mole is one dark dot
```

```gdscript
# tests/hud/test_portrait_card.gd
func test_the_card_stands_at_the_boxs_left_and_rises_above_it() -> void:   # card_rect == Rect2i(16, 194, 116, 160) with bars; its bottom 2 px above the box's
func test_text_and_tab_begin_right_of_the_card() -> void:                  # text_rect.position.x == 140; the tab likewise; a 35-character name and three rows of 140 characters still fit the box
func test_a_shot_with_a_line_is_framed_in_the_free_area() -> void:         # the fixture's close shot: the subject's head is inside free_rect, no row of him under the card
func test_a_speaker_with_no_drawing_shows_the_blank_card() -> void:        # no error line
func test_the_card_goes_with_the_overlay() -> void:                        # release() and freeing at five instants: no PortraitCard left the next frame
func test_the_card_never_covers_the_pause_menu() -> void:                  # the menu's panel (any page, scrolled) and card_rect do not meet
func test_final_refuses_a_stand_in_by_name() -> void:
# tests/render/test_portrait_card_draw.gd   (--render)
func test_the_card_is_drawn_at_the_windows_resolution() -> void:           # at x3: inside the card's rect the window holds more than 4 x the distinct pixel positions the 640x360 picture could; outside it the window equals the upscaled picture exactly
func test_the_card_at_x1_x2_and_an_uneven_window() -> void:                # the card's rect is whole picture pixels at each
func test_shots_for_a_person() -> void:                                    # out/story/card_abarax_640.png, _1080.png, with a line showing in the close shot
```

- [ ] **Step 2: Run** `python3 -I -m unittest discover -s tools/portraits/tests` and `tools/test.sh --filter=test_portrait_card`. Expected: FAIL (no tool, no card).
- [ ] **Step 3: Build the tool.** Start from the controller's probe (`probe/clean.py` in the workspace: even the paper by dividing by its own blurred brightest neighbourhood; find each rule in the page's margins and fit it across; remove a narrow band, bridging strokes that cross). The probe leaves two rules in the owner's drawing: fit each rule from the margins and from paper-only samples (not from the drawing's own lines), and use the recipe's `erase` and `keep` for what is left.
- [ ] **Step 4: Write Abarax's recipe** (crop to the bust with the feather inside; tints from his palette: skin, hair, the feather as his accent, the collar) and make `neutral.png`. Open every stage's picture and the result at full size: say plainly what you see (a rule's ghost, a smeared lash, a tint over a line), and fix it before going on.
- [ ] **Step 5: Build the card and bring the overlay, the pose and the checker along.** Run the story and cine tests.
- [ ] **Step 6: Look at it** in the fixture's close and over-the-shoulder shots at 640×360 and ×3 (`test_shots_for_a_person`): is the pencil line crisp at ×3 and legible at ×1; does the card sit well on the box; is the scene's subject clear of it.
- [ ] **Step 7: Run** the whole headless `tools/test.sh` (through the lock), `python3 -I -m unittest discover -s tools/portraits/tests`, the clip checker, `story_check` (plain; `--final` now lists the stand-ins), the self-test, and the render filters `test_cine` and `test_portrait_card`. Commit in pieces.

### Task 2: Expressions, and the cast's stand-ins

**Files:**
- Create: `all-divine/tools/portraits/pencil_stand_in.py`, `all-divine/tools/portraits/tests/test_pencil_stand_in.py`, `docs/art/stand-ins/<speaker>.recipe.json`
- Modify: `all-divine/tools/portraits/sketch_to_portrait.py` (expressions), `docs/art/owner/abarax-portrait-sketch-2026-11-14.recipe.json`, `all-divine/assets/portraits/*/*.png`, `all-divine/data/speakers/*.tres`, `all-divine/ASSETS.md`
- Test: `tools/portraits/tests/`, `tests/story/test_speakers.gd` (or where speakers are tested), `tests/render/test_portrait_card_draw.gd` (a sheet)

**Interfaces:**
- Consumes: Task 1's tool, recipe and card; the existing cast's designs (`tools/portraits/export_portraits.mjs` and its source art).
- Produces:
  - Recipe `expressions`: each expression is a list of warps (`{from: [x, y], to: [x, y], radius}` in crop fractions) applied to the **cleaned line** before tinting, so the owner's own strokes move: `serious` (none: the drawing as it is), `angry` (inner brow ends down, mouth corners down), `sad` (inner brow ends up, lids lower), `smile` (mouth corners up, lower lids up), `surprise` (brows up, the forelock lifted). No stroke is drawn that the owner did not draw. Each derived expression is in `placeholder_exprs` (the owner may redraw it).
  - `pencil_stand_in.py --speaker <id> --recipe <json> --out <folder>`: a stand-in card for a character the owner has not drawn, made from that character's existing design: its outlines redrawn as graphite strokes (line weight and hatch spacing measured from the owner's drawing), the same paper, the same tint method, and **one signature ornament** named in the recipe from the book (as Abarax has his feather). All six expressions; all in `placeholder_exprs`.
  - Speakers `goldtooth`, `kesra`, `noella`, `sierra` (and what the fixture uses) point at their stand-ins.

- [ ] **Step 1: Write the failing tests** (a warp moves only what is inside its radius and by its vector; `serious` equals `neutral`; a derived expression differs from `neutral` inside the eyes-brows-mouth boxes and nowhere else by more than a pixel's worth; every speaker has six pictures of 464 × 640; every stand-in is listed as one; `story_check --final` names them).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Build expressions; make Abarax's five; look at each beside `neutral`** at full size and at 640×360: a face, or a smear? An expression that does not read as its name is cut back to `neutral` and listed for the owner to draw, not shipped as a grimace.
- [ ] **Step 4: Build the stand-ins; look at the five characters side by side** (one sheet, `out/story/cast_cards.png`): do they belong to the same hand as the owner's Abarax? Say plainly where they do not.
- [ ] **Step 5: Run** everything of Task 1's Step 7. Commit in pieces.

### Task 3: Abarax's model follows the drawing

**Files:**
- Modify: the Abarax model's builder under `all-divine/tools/` (the `bpy` script that makes `assets/models/…`), its tests, the built model, `data/actors/*.tres` (hidden parts on every other actor), `data/palettes/` if a colour is added, `all-divine/ASSETS.md`
- Test: the builder's `bpy` tests (`tools/bpy_test.sh`), `tests/actors/` (who shows which part), `tests/render/` (a look test and shots)

**Interfaces:**
- Consumes: the model's builder and its parts convention (a part is a named mesh an `ActorDef` can hide, as `Knuckle_Hood`, `Knuckle_Blade`), the scarf's spring bones (the feather swings as the scarf does), `ActorDef.hidden_parts`, the palette's ramps.
- Produces: parts `Abarax_Topknot` (the bun and the pulled-back hair, the sides cut close), `Abarax_Forelock`, `Abarax_Feather` (from his left ear: ring, two beads, the barred feather, on a spring bone), `Abarax_EarRing` (his right lobe); stubble and the mole in his face's colours; every other actor hides the four parts. Nothing the game measures moves (hitboxes, hurtbox, feet, the head's look-at).

- [ ] **Step 1: Write the failing tests** (the parts exist on Abarax and are hidden on every other actor def; the feather hangs from the left ear's bone and swings when he turns (its tip moves more than 2 cm in a dash-step and comes to rest); the silhouette at the game's camera shows the bun above the head in all eight facings; every Knuckle's picture is pixel for pixel what it was; the clip checker's count is unchanged).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Build.** Rebuild the model with the repo's own command; commit the built files.
- [ ] **Step 4: Look at him** at the game's camera (zoom 1, eight facings, idle and a jab) and in a close shot at yaw 180 and 90 (zoom 3): does he read as the man in the drawing: the bun, the forelock, the feather? Put the old and new side by side in `out/shots/abarax/`. Say plainly what does not carry at 640×360.
- [ ] **Step 5: Run** the whole headless suite, `tools/bpy_test.sh`, the clip checker, the self-test, the render filters this touches. Commit.

## Self-review

- Every line of the design has a task: the drawing as the portrait and the tint (Task 1), the bigger card (Task 1), expressions and the cast's stand-ins with their ornaments and the placeholder flag (Tasks 1–2), the model (Task 3).
- Names agree between tasks: `PortraitCard.CARD`, `card_rect`, `Speaker.placeholder_exprs`, `Speaker.card`, `free_rect`, the recipe's keys, 464 × 640.
- Review Focus 1 and 2 are tested in Task 1's Python tests; 3, 4 and 5 in `test_portrait_card.gd` and the render test.
