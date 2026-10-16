# Umbra

An original monochrome 2D platformer for Android, built with Flutter, Flame and native Box2D v3 through `flame_forge2d` 0.20. Its character, physics, ground and environment are modelled on the feel of LIMBO: a small black boy with glowing eyes running through a fogged forest, a fixed jump, ledges and ropes caught automatically, and deaths that fade to black and put you back a few seconds earlier.

The story: a boy runs from home after an argument, vampires take him in the night forest, and he must escape their land. Part 1 (Home, The Night Forest, The Cage) and Part 2 (The Caves, The Crypt, The Bone Pit, where real buoyancy carries him across the water) are playable from the title screen; [CHAPTERS.md](CHAPTERS.md) describes the chapters, the scene system and how they are tested. [BRANDING.md](BRANDING.md) is the brand: colours, Cinzel, the wordmark and the icon.

See [CHARACTER_SYSTEM.md](CHARACTER_SYSTEM.md) for the architecture, tuning, verification and what each system does. [STEP1_NOTES.md](STEP1_NOTES.md) records the project's initial setup and migration notes.

## Requirements

- Flutter 3.44 or newer, with Dart 3.12 or newer.
- Android SDK and NDK for an APK build.
- A native C compiler (clang) for `flutter test`: Forge2D compiles bundled Box2D using Dart native assets.

## Build and run

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
flutter build apk --release
```

The app opens on the title. `--dart-define=UMBRA_PROVING_GROUND=true` opens the 96 m test level (the one the physics tests use) instead.

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The current signing configuration uses the development key for direct phone testing; configure a production signing key before store distribution.

## Controls

LIMBO's whole vocabulary: move, jump and one action. The boy always runs; there is no run button and no crouch.

| Action | Keyboard | Touch |
|---|---|---|
| Run left / right | A/D, Left/Right | ◀ ▶ |
| Jump (always the same height) | Space, W, Up | ▲ |
| Grab and pull an object | Hold E or Ctrl | Hold ✋ |
| Climb a caught ledge | Toward it, or jump | Toward it, or ▲ |
| Let go of a ledge | S/Down, or steer away | Steer away |
| Climb up / down a rope | W/Up, S/Down | ˄ ˅ (shown only on a rope) |
| Let go of a rope | Hold S/Down at its bottom | Hold ˅ at its bottom |
| Kick off a rope | Space | ▲ |

Ledges and ropes are caught automatically when the boy reaches them in the air, a rope anywhere along it. Pushing happens by running into a crate. Steep banks (over 32°) are slid down on his feet.

Development builds (`--dart-define=UMBRA_DEBUG=true`) add on-screen DBG, RESET, FALL and SOUND buttons; on a keyboard F1 toggles the physics overlay, R resets to the checkpoint, K knocks the boy down and M toggles the wind.

## Verification

`flutter test` exercises the actual native physics: running speed and reversal, the fixed jump height at 30/60/120 fps, coyote time and jump buffering, ceilings, moving platforms, planted feet with a real flight phase in the run, push/pull mass resistance, automatic rope and ledge catches, rope climbing, letting go, sliding, tipping crates, arm and leg physics, the turn, idle life, landing dust and camera shake, hard landings, deaths on the stakes and from long falls with the fade and respawn, the complete level route, touch controls, and seamless baked fog layers. The water (Archimedes buoyancy, drag, drowning) is tested on its own. Each of the six chapters is also played start to finish by a scripted bot (see CHAPTERS.md).

To look at the result frame by frame, `flutter test tool/capture/capture_frames_test.dart` renders gameplay scenes to `build/limbo-preview/`, and `python3 tools/contact_sheet.py run` crops the boy into contact sheets. `flutter test tool/capture/capture_chapters_test.dart` does the same for the title and the chapters (`build/chapters-preview/`). `python3 tools/playtest.py` plays the level in real Chrome on a release web build, records a video and reports FPS.
