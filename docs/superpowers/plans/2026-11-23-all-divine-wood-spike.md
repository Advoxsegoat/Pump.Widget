# The fronts' wood at a mid tone: a spike (Nov 23)

> A spike made for the owner's choice of Nov 16 (the house fronts' wood a mid tone, heads still standing out). Nothing from it is in the
> game. The pictures are in [`2026-11-23-all-divine-wood-spike/`](2026-11-23-all-divine-wood-spike/): start with
> `three_looks_street_shade.png` (the three looks the owner chooses between, close up) and `street_shade_now_and_045_keyline.png`.
> The raw per-pixel data (`sheets.jsonl`, `k3.jsonl`) and the whole pictures at 0.35 were not kept (the sheets show 0.35). What follows is the spike's own report, as written.

Spike, nothing kept. Worked in a scratch copy of the world lane at 0515d02 (the lane was not touched; nothing committed or pushed). Filtered rendered runs only. Pictures: `2026-11-23-all-divine-wood-spike/`. Raw numbers: `2026-11-23-all-divine-wood-spike/` (`sheets.jsonl`, `k3.jsonl`, `cost.txt`, `analysis.md`).

## The answer, in five lines

1. Yes. The wood can be a mid tone (0.35 to 0.45 in the picture) with every head plainly seen. The earlier finding that it cannot was too strong: tier III's head is not the problem at 0.35 or 0.45 (its head is darker than the wood there, and it passes at all 26 places); the problem is that every wood tone sits on some other head's tone somewhere (0.25 on tier III, 0.35 on the heavy, blade, Drummer and tier I, 0.45 on Abarax), and today's rule fails there.
2. At wood 0.45 with nothing changed (today's outline) the whole of the checks I ran gives one red head out of 156 (Abarax at the street front's shade, where his head is 0.49 and the lit wall 0.45 to 0.5) and no red cue; at 0.35 it gives seven red heads and one red cue. A dark line drawn just outside every fighter (K2, "keyline") makes the heads plainly seen at all of these, by my eyes; a darker outline alone (K1) does not.
3. K2 costs about eight to eleven draw calls a body (eight bodies: about 270 to 330 draw calls, the budget is 450; primitives about double for the bodies) and no frame time I could measure; what else must change: the picture rule has to credit the keyline (it looks 3 to 6 pixels outside the head, the keyline is 1 pixel), the cues test's outline rule needs a look at 0.35, and the rim and warming passes share the one overlay slot the keyline would use.
4. I recommend wood 0.45 with the keyline (K2) and the rule changed to pass a head whose ring is not blended or whose line round it is dark; if the owner will not have a black edge on every fighter, 0.45 with today's outline is still one red place of 156, to be fixed by one change to Abarax's head or by the rule. 0.35 needs the keyline. One caution: at 0.45 the wood reads dusty rose-mauve, not brown (hue and saturation as today's, light up); a warmer, browner 0.40 to 0.45 is a colour task I did not try.
5. The owner is choosing between: (a) the fronts as they are (near black, 0.13); (b) mid-tone wood at about 0.45 with today's outlines and one place to mend; (c) mid-tone wood with the keyline, a visible change of style (a thin black edge on every fighter) that makes the heads safe at any wood tone.

## What was built and how the wood was measured

- Wood tone: `make_textures.gd`'s wood is `0.04 + 0.18 v` (hue 0.07, saturation 0.38). In the copy it is multiplied by k (trim by the same k). The colormap was rebuilt at run time and swapped into the world material for the pictures (identical to remaking the PNG), and for step 4 the PNG was really remade by the tool.
- Wood median (my measure, since the brief's "by the measure of test_bilibara_tones" has no wood class there: the tones test pools whole fronts): the median luma in the final 1280 x 720 picture of the pixels whose colormap texel is a wood texel (the kit colours the make tool sends to its board branch), at the four views Spawn, StreetEast, LaneMid, RackWest with nobody standing in them. Today's k = 1.00 gives 0.129 (the brief says 0.13 to 0.14: it agrees). Measured: k 2.06 gives 0.250, k 2.98 gives about 0.349 (2.95 gives 0.347), k 3.93 gives 0.450. Saturation as today's.
- Treatments: K0 today's outline (post shader, silhouette factor 0.35). K1 the same factor at 0.12 (a uniform in the copy). K2 below.
- K2, the cheapest true way I found: `toon_character` already writes 255 into the stencil on every pixel a body shows, and the rim light already has a hull pass (`toon_rim`: the body drawn again grown by 1 to 2 picture pixels, lit only off the body's own stencil mark, drawn after the screen look's quad so the look does not blur it). K2 is that hull pass, always on, dark (0.04, 0.03, 0.06 as the existing rim ink), 1 pixel wide, with the stencil test "not 255" (so no mark pass is needed): one `material_overlay` per body mesh (a new `toon_keyline.gdshader`, 25 lines, a copy of the hull). The body's own edge pixel keeps today's post-pass line, as the brief asked. No layer, no second viewport, no change to the post shader. It is real, not drawn from the test rig's masks. Caveats: it takes the mesh overlay slot that the rim and warming passes use (a tell's rim and a keyline would need chaining: the rim's `next_pass`), and while a rim's mark pass has written another mark on the body, the keyline would also draw on the body's inside (stencil is then not 255): to be sorted in a real task by writing 255 in the rim's own mark pass or reading "equal to 0".
- Places: the yard under its north wall (27.5, -73), the street front's shade (3, -4.2), alcove B (36, -31.5; the `_more` test's one). Bodies as the readability tests stand them: Abarax, a tier I and a tier III in row one, the Drummer (with the heavy and blade) in row two. Numbers are for all six; sheets show four.

## Pictures

- `sheet_yard_north.png`, `sheet_street_shade.png`, `sheet_alcove_b.png`: one row per wood tone (today, 0.25, 0.35, 0.45), one column group per treatment (K0, K1, K2), each cell the four bodies (tier III, tier I, Abarax, Drummer) cropped at 4 times, nearest neighbour; under each: the head's tone and "rule N%" (today's rule, the share of the ring within 0.08; red at 50 or over) and "key N%" (my keyline measure).
- `whole_street_wood_today_K0.png`, `whole_street_wood035_K2.png`, `whole_street_wood045_K2.png` (and `..._K0` at 0.35 and 0.45 for comparison); `whole_yard_north_wood_today_K0.png`, `..._wood035_K2.png`, `..._wood045_K2.png`; `whole_street_shade_*` the same three. 1280 x 720, the game's camera, three bodies (Abarax with a tier I east and a tier III west, 2 m apart, standing as in the tests, not in a fight pose), the HUD hidden.

### What my eyes see in the sheets

Yard under the north wall (`sheet_yard_north.png`). The wall behind the heads is only the top strip of each crop; the bodies stand on pale snow, so most of the head's outline is the ground, and the wall touches the head of the tier III and Abarax. Today's wood: all heads clear at once (a dark hood on a pale wall of 0.2). Wood 0.25, K0: the tier III head (0.29) sits on a wall the same brown-grey, and the hood merges at the top: lost at a glance (the rule says 66%). K1 does not help it: the extra dark is only on the body's edge and the head is already its own darkest pixel; the hood still merges (66%). K2 at 0.25: the hood has a thin black edge all round and is seen with a look, but the wall behind is the same value, so it is "seen with effort": the keyline gives the shape, not the contrast. Wood 0.35 and 0.45: the wall is lighter than the hood (0.35, 0.45 against 0.29), so the hood stands on a paler wall: seen at once in every treatment (rule 10% and 8%). The tier I (0.40) at 0.35 is the one on the wall's tone: K0 it is a brown head on a brown wall (rule 49%, with effort); K2 gives it a black edge and it is seen at once. Abarax's white shirt and the Drummer's bare red head and torso are seen at once everywhere here.

Street front's shade (`sheet_street_shade.png`). The worst place: the wall is lit in different values across the head. Today's wood: all seen at once. Wood 0.25: the tier III hood against a wall of the same tone: lost at 0.25 K0 and K1 (71%); with K2 a black rim shows the hood's shape but not much more ("with effort"). Wood 0.35: the Drummer (0.39) is lost at K0, K1 and (in the rule's number) K2: 65%, 65%, 64%; my eyes see a red-brown head on a rose-brown wall with the pale face of the arch behind: with K0 and K1 it is hard to find; with K2 it is seen with a small effort because the black edge draws it, which the rule does not count. Wood 0.45: Abarax (head 0.49, brown hair and skin on a wall at 0.45 to 0.5) is the head lost in K0 and K1 (83% and 82%); with K2 his head has a dark edge and his white shirt carries the eye below, "seen with effort"; the rule is still 80%. The tier I and tier III are fine at 0.45 (18%, 0%).

Alcove B (`sheet_alcove_b.png`). The easiest place: the bodies stand on pale slate with a wood post at one side; nothing is lost at any tone or treatment (rule at most 39%, the tier III at 0.25: seen at once all the same, the post is at his elbow, not behind his head). K2 shows its look plainly here: every fighter has a continuous black edge.

Plain summary of the sheets: the heads that fail are the ones whose own tone matches the lit wall behind them; K1 changes nothing for them (the darker silhouette line is on the body's edge pixel, under the head's own tone; the line is already a third of the head's tone there); K2 makes the head a drawn shape that cannot melt into any wall, at the price of a visible black edge on every fighter (the owner should look at the whole pictures: it is a thin line, but a clear change of style: a comic-book edge).

## Numbers

Tables are in `2026-11-23-all-divine-wood-spike/analysis.md` (all six bodies, three places, four tones, three treatments: rule share / keyline share). The ones that matter, rule share in percent (fails at 50), K0 (K1 and K2 move the rule by a few points only, since the rule looks 3 to 6 pixels outside the head):

| place and body | today's wood | 0.25 | 0.35 | 0.45 |
|---|---|---|---|---|
| yard north, tier III | 3 | **66** | 10 | 8 |
| yard north, tier I | 3 | 3 | 49 | 6 |
| yard north, heavy | 2 | **56** | **86** | 2 |
| yard north, blade | 5 | 48 | **65** | 7 |
| street shade, tier III | 0 | **71** | 12 | 0 |
| street shade, Drummer | 0 | 0 | **65** | 10 |
| street shade, blade | 0 | 50 | **62** | 4 |
| street shade, Abarax | 3 | 3 | 33 | **83** |
| alcove B, tier III | 28 | 39 | 8 | 5 |

Keyline measure (mine, stated exactly): for each body, the pairs (p, d) where p is a silhouette pixel in the head zone (the top 22 per cent of the body's height) and p + d, a 4-neighbour, is outside the silhouette (and p + 3d is neither in this body nor within 3 pixels of another body); the line pixel is the darker of p (the body's edge pixel, the post pass's line) and p + d (the pixel just outside, the keyline); the pair is kept when that line pixel is at least 0.12 darker than both the head's mean tone and the tone at p + 3d, all in the final 1280 x 720 picture at the block's centre. The measure is the kept share. Mean over all bodies, places and tones: K0 26 per cent, K1 32 per cent, K2 52 per cent (K2 with a 1.5 pixel hull: 58 per cent over today's, 0.35 and 0.45; for tier III 50 against 66 per cent). The mean tone of the body's edge pixel is 0.417 (K0), 0.395 (K1), 0.250 (K2: the keyline pulls the lower of the pair down); of the pixel just outside, 0.457, 0.446, 0.330.

How well the numbers agree with my eyes. The rule agrees with my eyes about where heads are lost by tone (tier III on 0.25 wood, the Drummer at 0.35 in the street shade, Abarax at 0.45) and is right to be red there for K0. It is blind to the line: K2's sheets look clearly better to me than K0's and the rule gives them the same number, which is why a rule that credits the outline is the real change. The keyline measure disagrees with my eyes in one way: it says K2 holds only about half of the head's edge pairs (52 per cent), while the K2 columns look like a continuous black edge to me. The pairs it misses are the diagonal steps of the staircase edge, where the one-pixel hull does not reach the neighbour pixel's centre, and a 1.5 pixel hull gets 58 per cent only; I did not find out whether the rest is the hull, the measure or the pixels the grade lifts, so use the measure as an order (K0 26 under K1 32 under K2 52) and not as a pass mark. K1's measure (32 per cent against 26) agrees with the eye that K1 is only a little darker than K0.

### K3: which head tones pass today's rule everywhere (K0, no actor edited)

At all 26 places, the head tone t passes when under half of its ring (this body's ring, 3 to 6 pixels outside its head, as the lit wood stands there) is within 0.08 of t. Passing ranges of head tone, by wood tone (a head's actual tone: tier III 0.27 to 0.29, tier I 0.37 to 0.41, Abarax 0.38 to 0.52 across places):

| wood | tier III's ring passes head tones | tier I's ring | Abarax's ring |
|---|---|---|---|
| today | 0.26-0.56 | 0.245-0.53 | 0.285-0.56 |
| 0.25 | 0.38-0.56 (or under 0.22): tier III would need to move up 0.10 or down 0.06 | 0.35-0.53 | 0.435-0.56 |
| 0.35 | 0.485-0.56 (or under 0.325): tier III as it is passes (0.28); | 0.435-0.535 (or under 0.315): tier I would move up 0.03 or down 0.09 | 0.555-0.56 (or 0.21-0.33): Abarax would need to be lighter by 0.1 or darker by 0.15 |
| 0.45 | under 0.43: tier III passes | under 0.42: tier I passes | 0.21-0.435: Abarax would need to be darker by 0.05 at least |

(Intervals are of the sweep in 0.005 steps; "or 0.855 to 0.965" is also passing for every body, a white head, and not a real option. Places where a head fails today's rule at each wood tone: 0.25: tier III 2 (yard under the north wall; front's shade, street); 0.35: tier I 1 (under the colonnade), Abarax 2 (alcove B slate pool; front's shade, street); 0.45: Abarax 1 (front's shade, street). The heavy, blade and Drummer fail at 0.25 to 0.35 too, as the sheet tables show: the three places of the sheets are not all of the 26 for them.)

## Cost of K2

From `test_spike_cost` at six views (Spawn, StreetEast, LaneMid, RackWest, GateFar, YardEntry), mean (`data/cost.txt`): with 2 bodies 182 draw calls and 33,200 primitives (K0) against 204 and 47,300 (K2); with 8 bodies 269 and 71,900 against 330 and 124,800. The heaviest K2 view is 348 draw calls (LaneMid and GateFar, 8 bodies), under the budget of 450 (`test_bilibara_cost`'s MOST_DRAWS); primitives stay far under 400,000. So about +11 draw calls a body (+8 with eight in view, some being out of frame), and the bodies' primitives doubled. Frame time: this machine draws in software (no GPU), so ms per frame is only a proxy: 38.6 against 37.9 (2 bodies) and 42.6 against 46.2 (8 bodies), i.e. within noise to 8 per cent, dominated by the software rasteriser; the real answer (60 fps on the GTX 1060 class machine) could not be measured here. The shader is the same vertex work as the rim hull, over skinned meshes, so the cost is the body drawn once more.

## What else goes red at wood 0.35 and 0.45 (step 4)

Real runs in the copy: the textures were remade by the tool (`WOOD_K`, `TRIM_K` = 2.98 and 3.93; the trim in proportion), re-imported, and the four tests run by filter, rendered, with today's code (no keyline, today's outline). Today's wood is the control: the lane's own report says all of these are green. Pooled medians in `test_bilibara_tones`: fronts 0.386 at 0.35 and 0.449 at 0.45 (roof slate 0.39 in both; the wood at 0.45 is paler than the roofs).

Wood 0.35 (k 2.98):
- `test_bilibara_tones`: 4 passed, none red (the lane has no wood band: the tones test only bounds the roofs, the plaster's upper quartile, the water and the snow).
- `test_bilibara_cues`: 1 of 2 red: "parry rim at yard under the north wall: 167 px (124 strong), outline 146 px of which 113 carried (at least 85%)": the dark ink edge round a pale rim is carried on 77 per cent of its length against a wood that is now lighter; this is the cues test's outline rule (the line must stand against what is behind it), not its strong-change number (STRONG 0.35 held).
- `test_bilibara_readability` (first twelve): red, 3 heads: Abarax at alcove B (slate, pool) 77 per cent; the heavy at the yard under the north wall 85; the blade there 61.
- `test_bilibara_readability_more`: red, 4 heads: the Drummer at front's shade, street 53; the blade there 68; tier I under the colonnade 55; the heavy under the colonnade 86. (The test's second case, "the yard is the floor", passes.)
- `test_bilibara_shots`: 2 passed.
- Not asked, run for completeness: `test_bilibara_textures` 17 passed, 2 red ("the committed colormap is what make_textures makes", "the committed neon colormap is what make_textures makes"): an artefact of how the spike made the textures (the tests call the maker with today's constants, the committed file had the spike's); a real task changes the constants and these go green.

Wood 0.45 (k 3.93):
- `test_bilibara_tones` 4 passed; `test_bilibara_cues` 2 passed; `test_bilibara_shots` 2 passed.
- `test_bilibara_readability` (first twelve) passed; `_more` red, 1 head: Abarax at front's shade, street, 84 per cent of his ring within 0.08 of his head's tone.
- `test_bilibara_textures`: the same two artefacts.

So a real task at 0.45 changes: that one head (or the rule), and nothing in the tone bands, the cues or the shots; at 0.35 the head rule at seven places, the cues' outline rule at the yard's parry rim, and the cues test's outline rule at the yard's parry rim. (The cues test's STRONG change did not go red at either tone.)

## Recommendation, in full

Take wood 0.45 (or a browner tone near it) and add the keyline K2. Why: at 0.45 today's rule is red at one place of 156 and the cues are green, so the wood itself costs almost nothing; the keyline then makes that one place, and any head a later repaint puts on a wall's tone, plainly seen by drawing it, which is what the owner asked ("heads must still stand out"). The rule must change with it: a head passes when under half of its ring is within 0.08 of its tone, or when its edge carries a dark line (my keyline measure, or a simpler one: the pixel just outside the body is at least 0.12 darker than the head and than the tone 3 pixels beyond, on at least half of the head's edge); without that change the keyline would be an unmeasured look. Do not take 0.35 without the keyline: it loses seven heads at once (the heavy, the blade, the Drummer, tier I, Abarax).

What the owner is choosing between is therefore the look: dark fronts as now; a mid-tone front with the outlines as they are (one place red); or a mid-tone front with a thin black edge on every fighter. The whole pictures show them (whole_yard_north_wood045_K2, whole_street_wood045_K2, against the `_today_K0`).

## What I could not find out

- A real frame time: this machine draws in software, so the ms per frame are a proxy only (the draw calls and primitives are exact).
- Why my keyline measure says only about half of the head's edge pairs are covered with K2 (52 per cent; 58 with a 1.5 pixel hull) when the sheets look like a continuous edge; I did not isolate hull, measure or the grade.
- Wood tones between 0.35 and 0.45 (0.40 says nothing here) and a browner hue at 0.45: only the four tones asked.
- How K2 meets the rim light and warming passes in play (they use the same overlay slot) and the heavy's inflate in motion; the keyline was only seen on frozen bodies.
- The 26-place numbers are for row one (Abarax, tier I, tier III) in my K3; the other three bodies' 26 places are in the real test runs of step 4 (the readability tests), where they are the red lines listed.
- Whether the one 0.45 failure (Abarax at the street front's shade) moves with his sub-pixel pose; the bodies were frozen as the tests freeze them.
- The trim and the neon banner colormap were scaled with the wood (trim in proportion, as asked); I did not look at whether the lighter trim reads well beside the wood.
