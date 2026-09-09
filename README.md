# Umbra

A Limbo-inspired atmospheric 2D platformer for **Android**: solid black
silhouettes on a flat light-grey background, played in landscape.

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

Walking into the pit respawns you at the checkpoint.

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

These need no Android SDK and run anywhere Flutter does.

## Layout

```
lib/
  config/     tuning constants and the colour palette — every magic number lives here
  entities/   one file per thing in the world (player, ground, hazard)
  game/       the Forge2DGame subclass: camera, background, wiring
  input/      keyboard and touch -> PlayerIntent. Knows nothing about physics.
  world/      level layout and the checkpoint/respawn system
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
