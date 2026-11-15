# The owner's drawings

Art drawn by the game's owner, kept here as the reference the game's portraits and models are made from. These
files are sources, not game assets: the game's own copies live under `all-divine/assets/` with their rows in
`all-divine/ASSETS.md`.

| File | What it is | Received |
|---|---|---|
| `abarax-portrait-sketch-2026-11-14.jpg` | Abarax, a bust in pencil, for his dialogue portrait and as the style for every character's portrait. | 14 Nov 2026 |
| `abarax-portrait-sketch-2026-11-14.recipe.json` | Ours, not the owner's: the recipe `all-divine/tools/portraits/sketch_to_portrait.py` reads to make Abarax's portrait from the drawing (the crop, what to wipe or leave alone where a rule lay on a line, the soft tints). The drawing itself is never edited. | 14 Nov 2026 |

## Abarax, as drawn (what the portrait and, later, his model follow)

- **Hair:** pulled back into a top-knot bun, comb lines running to it; the sides cut short; one loose forelock
  falling to the bridge of his nose; a small tie at his left temple.
- **Face:** thick, low, textured brows; heavy-lidded eyes looking down, a long upper lash line; a broad nose shaded
  at the nostrils; full closed lips; stubble along the jaw and a patch on the chin; a mole on his left cheek, under
  the eye.
- **Ears:** large; a small ring in his right lobe; from his left ear hangs a link, a spiral ring, two beads on a
  cord and a large barred feather that swings out past his jaw.
- **Neck and collar:** a long, strong neck with the two tendons and the collarbone notches drawn; a plain V collar.
- **Manner:** a confident pencil contour, short hatching at the edges of forms (temples, jaw, under the lip), little
  shading inside them; proportions a little long, calm and stern.

## Adding a drawing

The cast's portraits are your own drawings, cleaned and lightly tinted; nothing of ours draws a face. This is how a new
one gets into the game, in a few minutes.

**Photographing it.** Lay the page flat and get the whole page in the picture, with a little paper showing on every side.
Use even light (daylight from a window is best; no flash, no lamp glare across the pencil, no hand shadow). Hold the camera
straight above the page, not at an angle. Plain paper is safest, then ruled paper with its lines roughly level in the photograph
(the tool finds the rules and takes them out, as it did for Abarax); when it cannot do a page it says so in one line and what to
change. A drawing in soft pencil on a clean page gives the best result.

**Where the file goes and what to call it.** Put the photograph in this folder (`docs/art/owner/`) and name it
`<speaker>-<expression>-<date>.jpg`, for example `kesra-neutral-2026-12-02.jpg`. The speaker is the lower-case id of the
character; the expression is one of `neutral`, `smile`, `serious`, `angry`, `sad`, `surprise`. Your photograph is never
edited by anything.

**Once, before the first drawing.** From the `all-divine` folder of the project run `tools/setup.sh --portraits`. It makes (or adds
to) the project's own Python in `tools/.venv` and puts the two libraries the tool needs into it, at the versions the pictures
were made with. The tool must be run with that Python (`tools/.venv/bin/python`), not with the computer's `python3`: a plain
`pip install` puts the libraries where `python3 -I` does not look. If you forget, the tool says so in one line and tells you this.

**The two commands.** From the `all-divine` folder of the project:

1. `tools/.venv/bin/python -I tools/portraits/sketch_to_portrait.py --init-recipe ../docs/art/owner/<file>.jpg --out ../docs/art/owner/<file>.recipe.json`
   looks at your photograph and writes a first recipe by itself: whether the paper is ruled or plain, where the drawing
   is, and which expression it is (read from the file's name; a name that does not follow the pattern, or an expression it does
   not know, gives `neutral` and says so). It adds no colour. If it cannot handle the photograph it says so in one line and what
   would help (plain or ruled paper, the whole page in the photograph, even light).
2. `tools/.venv/bin/python -I tools/portraits/sketch_to_portrait.py --sketch ../docs/art/owner/<file>.jpg --recipe ../docs/art/owner/<file>.recipe.json --out assets/portraits/<speaker>`
   makes the portrait: your drawing, cleaned, with no tint. To see each step, add `--stages <a folder>`.

Open the picture it made. The washes of colour, a stroke that lies along one of the notebook's rules, and anything left over
are then added to the recipe by hand, looking at the result (the header of
`tools/portraits/sketch_to_portrait.py` lists every setting); Claude can do that with you. The recipe's `expressions` names
the picture it makes (taken from the file's name): change it there if it is not the expression you drew.

**What happens to a speaker with no drawing yet.** Their dialogue shows a plain cream card with a grey head-and-shoulders
shape, and the story checker lists that line as a stand-in (the final check refuses a scene that has one). The moment their
drawing is in the game (its picture listed in the speaker's file under `data/speakers/` and in `ASSETS.md`: tell Claude which
speaker and expression, and it adds those two lines) the plain card gives way to your drawing.
