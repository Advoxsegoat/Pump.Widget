# The All-Divine: Between the Rooms

A top-down action roguelike in the style of Zelda on the Game Boy Advance, set in the book's world.
Abarax steps through a tear in the Garden wall into the Seams and fights down through the depths
of Bilibara, one flip-screen room at a time. Risk of Rain gives it stacking items and a difficulty
clock; Pixel Dungeon gives it unknown draughts and pages, traps, secrets and burning grass. Death
ends the run, but rose petals, unlocks and the Book stay.

This is milestone 1, the vertical slice: Abarax's whole kit, Bilibara depths 1–5, goblins, wyvern
whelps, vermin and the book's enemies, three mini-bosses, the Seam Gates, First Knuckle, the M1
items, a basic Garden and saving. It runs offline as one HTML file, in a browser or as an Android
app that asks for no permissions.

| Path | What it is |
|---|---|
| [`web/index.html`](web/index.html) | The game, built from `src/` by `tools/build.mjs`. |
| [`src/`](src/) | The sources: `engine/`, `sim/` (the simulation, plain data, no drawing), `gen/`, `data/`, `art/`, `view/`, `ui/`, `game/`. [`src/order.txt`](src/order.txt) is the build order. |
| [`tests/`](tests/) | The Node test suite (187 tests). |
| [`tools/playtest/`](tools/playtest/) | Browser checks: smoke, performance and memory, contact sheets, phone layouts, screens, and the bot sweep. |
| [`android/`](android/) | The Android app: a full-screen WebView around the game, plus [`android-shell.js`](android/app/src/main/assets/android-shell.js) for the clipboard and haptics. |
| [`tools/render-icons.mjs`](tools/render-icons.mjs) | Draws the launcher icon from the game's own art: Abarax in front of the tear. |
| [`tools/build-apk-offline.sh`](tools/build-apk-offline.sh) | Builds the APK on a machine without the Android SDK. |

The design is [`docs/superpowers/specs/2026-10-19-between-the-rooms-design.md`](../docs/superpowers/specs/2026-10-19-between-the-rooms-design.md)
and the build plan [`docs/superpowers/plans/2026-10-19-between-the-rooms-m1.md`](../docs/superpowers/plans/2026-10-19-between-the-rooms-m1.md).

## Playing

- **In a browser:** open `web/index.html`. Saves live in the browser's local storage.
- **On Android:** install the APK from the workflow run or a release (below). It installs beside
  All-Divine Tactics; the two are separate apps.

### A run

1. In the Garden, walk to the tear in the wall and press A. Pick a difficulty (Dawn, Dusk or Rose
   Hour) and, if you like, type a seed.
2. Each depth is a floor of 8–16 rooms. Combat rooms seal until their waves are beaten. Treasure
   rooms hold chests (some behind locked doors), secret rooms hide behind cracked walls, and the
   rest room has a campfire and a page of the Book.
3. The exit room holds a Seam Gate. Touch it and stay within three tiles while it charges for
   30 seconds; a mini-boss guards it (Gold Tooth, Yaska's Fixer or Lt. Marais) and waves keep
   coming. When it is charged and the guardian is down, step through.
4. Depth 5's gate opens onto the Tanneries yard and First Knuckle. Beat him and the run is won.

The clock in the corner runs while you play. The longer a run takes, the stronger everything gets,
as in Risk of Rain. Coins open chests, keys open locked doors, and items stack. Draughts and pages
are unknown until you use one or read a Page of Identify. Death keeps the rose petals you found;
Midas spends them on unlocks in the Garden.

### Controls

| | Keyboard | Gamepad | Phone |
|---|---|---|---|
| Move (8 ways) | Arrows or WASD | Stick or D-pad | The stick: touch anywhere on the left and drag |
| Attack (tap); hold 40 frames for the spin | Z or J | South face (A) | A |
| Skill: the Three Gifts | X or K | West face (X) | B |
| Roll | C or L | East face (B) or R1 | R |
| Equipment | V or ; | L1 | L |
| Quickslots | 1, 2, 3 | L2, R2, north face (Y) | Tap the slot on the screen |
| Pause: items, map, Book, settings | Enter or Esc | Start | ≡ (and the phone's back gesture) |
| Map | M | Select | From the pause menu |

On a phone the controls show by themselves. Settings change their size (80–130%) and opacity, and
swap them for left hands. They also set the screen shake, the flashes, the damage numbers, the
haptics and the music and sound volumes. Leaving the app pauses the game.

### Display

Settings → Display picks **GBA shape HD** (the handheld's 3:2 shape at 360×240, 24-pixel tiles) or
**True GBA** (240×160, 16-pixel tiles, the art reduced to the real handheld's grid; it runs
lightest). Both draw the same game at the same speed.

## Building

```bash
cd all-divine-seams
node tools/build.mjs                       # src/ -> web/index.html
node tools/build.mjs --page out/page.html  # the same page without a document skeleton (the artifact)
```

### The Android app

```bash
cd all-divine-seams/android && ./gradlew assembleRelease   # with the Android SDK
# without it (Maven Central only: aapt2, android-all, dx, apksig):
VERSION_CODE=1 VERSION_NAME=0.1.0 bash all-divine-seams/tools/build-apk-offline.sh out/between-the-rooms-0.1.0.apk
node all-divine-seams/tools/render-icons.mjs [preview.png]  # redraw the launcher icons
```

Package `com.advoxsegoat.alldivineseams`, minSdk 24, targetSdk 36, no permissions. Builds are signed
with the committed sideload key (shared with Tactics), so each new APK installs over the last and
keeps the saves. That key is public: fine for sideloading, never for a store listing. Set the
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`
secrets and CI signs with your own key instead, and adds a Play bundle.

[`.github/workflows/all-divine-seams-apk.yml`](../.github/workflows/all-divine-seams-apk.yml) runs the
tests and checks that `web/index.html` matches its sources. It then builds the APK on every push
that touches `all-divine-seams/` and uploads it as a workflow artifact. Pushing a tag like
`all-divine-seams-v0.1.0` also publishes a GitHub Release.

## Testing

```bash
cd all-divine-seams
npm test                                           # the Node suite: maths, generation, combat, AI, saves...
node tools/playtest/smoke.mjs web/index.html       # boots, plays a room, the menus, audio, resume
node tools/playtest/perf.mjs web/index.html        # 40 monsters, fire and gas; memory across 30 rooms
node tools/playtest/sheets.mjs web/index.html      # contact sheets: hero, monsters, rooms, both modes
node tools/playtest/mobile.mjs web/index.html      # four phone sizes, both orientations
node tools/playtest/screens.mjs web/index.html out/screens   # every menu screen
node tools/playtest/sweep.mjs web/index.html 20 72000 4   # the bot: 20 seeds x keyboard and touch
```

The browser checks use Playwright with Chromium. `perf.mjs` passes when a simulation step takes
≤ 3 ms and a frame draws in ≤ 8 ms at the 95th percentile. Memory must also stay flat (±15%) and
within 16 M live canvas pixels. The sweep's bot plays the way a person does, through the real
keyboard and touch events, from the title to death or victory. It fails on any error or soft-lock
(a minute of no progress). At 0.1.0 it plays 40 runs with no problems; 13 reach depth 5 and 4 win.

## Milestones

| | Contents |
|---|---|
| **M1 (this)** | Engine, both display modes, phone controls; Abarax's full kit; Bilibara depths 1–5; the three mini-bosses; Seam Gates; First Knuckle; the M1 items, draughts, pages, armour and curses; a basic Garden; saving |
| M2 | The Liberation and the First Flame; Vanity, Benny, Vehday and Liora; elites; the full item catalogue; shops, shrines, puzzles, challenge rooms; Lucien's Book; the Glass Saint |
| M3 | Dark Rodden and the Ruin; Kael, the Twins and Reigna; the remaining bosses; achievements; Rose Hour tiers; the Daily Seam |
| M4 | The endless Seam and the Tessellate; balance from bot data; polish |
