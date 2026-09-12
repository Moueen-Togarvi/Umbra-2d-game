# Umbra

A Limbo-inspired atmospheric 2D platformer for **Android**: a small black
silhouette with glowing eyes, walking through a fog-lit forest of layered
silhouettes, played in landscape.

Physics is simulated with **Box2D** via
[`flame_forge2d`](https://pub.dev/packages/flame_forge2d) 0.20, so the world is
laid out in **metres, kilograms and seconds** rather than pixels. See
[`STEP1_NOTES.md`](STEP1_NOTES.md) for why that matters and for a translation
table from the pre-0.20 API you will find in most tutorials.

## Requirements

- Flutter **3.44.0 or newer** (`flame_forge2d` 0.20 needs it)
- Android SDK
- **The Android NDK.** This one is easy to miss. `forge2d` does not ship a
  prebuilt binary — it compiles Box2D from C source at build time through Dart's
  build hooks, so an Android build needs a C toolchain targeting Android. Install
  it via Android Studio → SDK Manager → SDK Tools → *NDK (Side by side)*, or
  `sdkmanager "ndk;<version>"`. Without it the Dart code analyses and tests fine
  and then the APK build fails.

Native assets are enabled by default on the stable channel, so no feature flag
is needed.

Verify your setup with:

```bash
flutter doctor -v
```

The "Android toolchain" section must be green **and** list an NDK.

## Build and run

```bash
flutter pub get
flutter run -d <your-device>          # debug, on a plugged-in phone
flutter build apk --release           # installable APK
```

The release APK lands in `build/app/outputs/flutter-apk/app-release.apk`.

To confirm the native physics layer actually made it in:

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep libbox2d
```

You should see `lib/arm64-v8a/libbox2d.so`. If that line is missing, the NDK
step above did not happen.

> The release build is signed with the **debug** key (Flutter's default), which
> is fine for sideloading onto your own phone but cannot be published to the
> Play Store. Add a real signing config in `android/app/build.gradle.kts` when
> you get there.

## Controls

Touch controls appear along the bottom of the screen: two walk buttons on the
left, jump on the right. Multi-touch works, so you can hold a direction and jump
at the same time.

Keyboard input is also still wired up — not for shipping, but because it makes
the game playable on desktop while developing and it is what the test suite
drives the player with.

| Action | Touch | Keyboard |
|---|---|---|
| Walk | ◀ / ▶ buttons, bottom-left | `A` / `D`, or `←` / `→` |
| Jump | ▲ button, bottom-right | `Space`, `W`, or `↑` |

Walking into a spiked pit respawns you at the checkpoint.

## The look

Every visible thing is either black or a shade of fog. Depth is *lightness*:
the further away a silhouette is, the more fog sits in front of it and the
paler it draws. That single rule is what makes a two-colour scene read as deep.

The other rule is **emptiness**. The reference frames are mostly fog: a
dark ground, a pale light somewhere behind the mist, and one or two black
shapes per screen. So the scenery is not tiled — it is *placed*, one prop at a
time along the level, and things arrive as you walk.

The scene is assembled in three bands, back to front:

1. **`camera.backdrop`** — [`render/atmosphere_backdrop.dart`](lib/render/atmosphere_backdrop.dart).
   A breathing radial fog glow that darkens gently towards the top and the
   bottom, a barely-there row of far trees, then the placed scenery from
   `GameConfig.scenery` — each prop with a *depth* that sets how slowly it
   scrolls, how faint it draws, and whether the blurred variant of its art is
   used — and a couple of faint light shafts.
2. **The world** — the physics bodies. Ground slabs draw as low hills with a
   fine fringe of grass; logs lie across the path as hop-over obstacles; pits
   are spike beds. The player is a small child — big round head, short body,
   glowing eyes — posed procedurally from its velocity: a walk cycle driven by
   distance so the feet never slide, trailing legs in the air, blinking.
3. **`camera.viewport`** — [`render/foreground_overlay.dart`](lib/render/foreground_overlay.dart).
   Only the lens: drifting dust motes, a gentle vignette, film grain.

The camera eases towards a point above and slightly ahead of the player and is
clamped to the level, so the edges never show and a fall into a pit never
drags the view down into the fog.

### Movement feel

Every number is in [`config/game_config.dart`](lib/config/game_config.dart).
The pieces that make the controls feel planted rather than physics-y:

- horizontal speed ramps up over ~⅛ s on the ground (slower in the air) and
  stops instantly on release;
- gravity is 1.45× on the way *down*, so a jump reaches its apex and then
  falls quickly and heavily;
- **coyote time** (0.12 s after leaving an edge a jump still works) and a
  **jump buffer** (a press up to 0.12 s before landing is honoured), both
  spent on use so neither can pay for a double jump;
- pits are 1.4 m wide against a ~2.4 m running jump — about half a second in
  which pressing jump clears them, but never walkable; logs sit 1.1 m above
  their floor, which blocks walking but leaves a generous hop.

### Art pipeline

The props in `assets/images/props/` are **generated, then baked**:

```bash
# 1. Generate raw props (needs an Alibaba Model Studio key; ~1 minute).
python3 tools/gen_assets_qwen.py assets/raw tools/qwen_props.json

# 2. Bake them into game-ready PNGs (crop, key to alpha, trim, blur).
python3 tools/bake_props.py assets/raw assets/images/props
```

`tools/bake_props.py` is the important half. It turns each raw image into a
**black PNG whose alpha channel is the silhouette**, keyed on a luminance band
so that gradient backgrounds and soft shadows drop out and only the black
shape survives; crops away any ground line or border the model added; trims
to the silhouette so the image's bottom edge *is* the prop's base; and writes
a `_soft` blurred twin for use deep in the fog. The two tileable strips (the
far trees and the grass fringe) are mirrored to repeat without a seam. The raw
generations are kept in `assets/raw/` so the bake is reproducible without
paying for generation again; tweak a crop or a key in the `SPECS` table and
re-run step 2.

`tools/gen_assets_gemini.py` does the same job against the Gemini image API,
for keys that have image-generation quota.

### Play-testing on this machine

The native test runner needs `clang` for forge2d, so the game is verified on a
web build in a real browser. Build with `--dart-define=UMBRA_DEBUG=true` and
[`render/debug_hud.dart`](lib/render/debug_hud.dart) draws the player's
position as pixel bars a script can read from a screenshot; in any other build
it does not exist.

## Tests

```bash
flutter test
```

Eleven tests, all driving the real physics world:

- **`physics_smoke_test.dart`** — the player rests on the floor, walks, jumps to
  the configured height, cannot double-jump, and respawns cleanly at the
  checkpoint. Driven through real key events.
- **`touch_controls_test.dart`** — the three buttons mount into the viewport, sit
  on screen within thumb reach, walk the player both ways, jump, work under
  multi-touch, and correctly keep walking when one of two held buttons is
  released. Driven through real pointer gestures at the buttons' actual screen
  positions.

These need no Android SDK, but they do need a C compiler (`clang`) for the
native Box2D build hook: `sudo apt install clang` on Ubuntu.

## Layout

```
lib/
  config/     tuning constants, the level layout and the colour palette
  entities/   one file per thing in the world (player, ground, hazard)
  game/       the Forge2DGame subclass: camera follow, art loading, wiring
  input/      keyboard and touch -> PlayerIntent. Knows nothing about physics.
  render/     the fog, parallax and lens effects. Knows nothing about physics.
  world/      builds the level from config, and the checkpoint/respawn system
assets/
  images/     baked, game-ready props and strips (black + alpha)
  raw/        the generated source art the bake is built from
tools/        the art generation and bake scripts
```

The separation to preserve as this grows: **input never touches a physics
body**, **constants never get inlined into an entity**, and **the checkpoint
system keeps working after every change**.

Touch controls were added without changing a single line of physics, entity or
checkpoint code — `PlayerIntent` exists precisely so that input sources can be
swapped and added freely. Adding a gamepad later would be the same shape of
change again.

Note that `config/game_config.dart` holds two kinds of number, and the file says
so loudly: the physics constants are in **metres**, while the on-screen control
sizes are in **logical pixels**. Never mix them.
