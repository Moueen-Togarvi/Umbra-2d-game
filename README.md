# Umbra

An original monochrome 2D platformer for Android, built with Flutter, Flame and native Box2D v3 through `flame_forge2d` 0.20. Its character, physics, ground and environment are modelled on the feel of LIMBO: a small black boy with glowing eyes running through a fogged forest, a fixed jump, ledges and ropes caught automatically, and deaths that fade to black and put you back a few seconds earlier.

The story follows a boy from home, through the vampires’ castle, and back into dawn. The campaign now has **40 chapters**, arranged in eight groups of five. The original fifteen story chapters keep their relative order; Dawn is chapter 40. Every chapter has its own four-panel WebP background atlas. Added routes combine low passages, patrol cover, moving coffin cover, counterweight lifts, tipping platforms, ropes, cages, rafts, drainage and fire traps.

Continue restores the last safe checkpoint, including completed machinery and rescued children. Chapter replay starts at the beginning. Existing fifteen-chapter saves migrate to stable chapter IDs. Threat music responds to nearby vampires and active pursuits; browser sound shares one audio context with at most twelve SFX voices. Settings include vibration and a reset that preserves story progress.

[CHAPTERS.md](CHAPTERS.md) describes the campaign and architecture. [PLAYTEST.md](PLAYTEST.md) is the human feedback checklist; automated routes do not establish human completion times. [BRANDING.md](BRANDING.md) records the visual identity.

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
| Pause, controls and settings | Esc | II (top right) |

Ledges and ropes are caught automatically when the boy reaches them in the air, a rope anywhere along it. Pushing happens by running into a crate. Steep banks (over 32°) are slid down on his feet.

Development builds (`--dart-define=UMBRA_DEBUG=true`) add on-screen DBG, RESET, FALL and SOUND buttons; on a keyboard F1 toggles the physics overlay, R resets to the checkpoint, K knocks the boy down and M toggles sound.

The mother and the vampires are drawn from generated artwork in `assets/images/characters/` (prompts and notes in `assets/design/characters/README.md`); the boy's visual rig is unchanged. The original concept sheets are archived outside the repo (see `assets/design/archive-manifest.json`).

## Verification

`flutter test` exercises the actual native physics: running speed and reversal, the fixed jump height at 30/60/120 fps, coyote time and jump buffering, ceilings, moving platforms, planted feet with a real flight phase in the run, push/pull mass resistance, automatic rope and ledge catches, rope climbing, letting go, sliding, tipping crates, arm and leg physics, the turn, idle life, landing dust and camera shake, hard landings, deaths on the stakes and from long falls with the fade and respawn, the complete level route, touch controls, and seamless baked fog layers. The water (Archimedes buoyancy, drag, drowning) is tested on its own. The castle's pulleys, lift, chandeliers and bookcases are tested the same way. The forty chapters have control-driven automated route tests, and every checkpoint has fresh-world and death-respawn checks (see CHAPTERS.md).

To look at the result frame by frame, `flutter test tool/capture/capture_frames_test.dart` renders gameplay scenes to `build/limbo-preview/`, and `python3 tools/contact_sheet.py run` crops the boy into contact sheets. `flutter test tool/capture/capture_chapters_test.dart` does the same for the title and the chapters (`build/chapters-preview/`). `python3 tools/playtest.py` plays the level in real Chrome on a release web build, records a video and reports FPS.

## Visual and interaction review fixes

The existing scenery assets are retained. Background scenery uses its blurred variants at depth, shares a consistent fog tone, and is drawn beneath the matching terrain layer. The root-heavy tree uses a shared source crop, so its roots no longer float above the forest floor. Cottage windows have warm room light without duplicate character silhouettes. The hero rig is unchanged; its oval backdrop has been replaced with a small grounded contact shadow. Ropes have a readable wrapped grip, stakes use subdued highlights, and railings sit behind the hero in a lighter tone.

Pause (Escape or the top-right button) now offers brightness, film effects, separate ambience/effect volume, touch-button size and opacity, checkpoint restart and a return to the main menu. Settings persist through `shared_preferences`. Chapters distinguish the current chapter, replayable chapters and locked chapters, with keyboard-accessible choices.

Audio uses `audioplayers` on supported platforms, unlocked by the first click, tap or key. The effects, loops and music are CC0 recordings (credited in `assets/audio/CREDITS.md`), cut, levelled and given their room by `python3 tool/audio/build_sounds.py`, which also writes `lib/audio/sound_bank.dart`. On the web every sound shares one AudioContext (`lib/audio/ambient_audio_web.dart`). Headless `UmbraGame` harnesses omit audio output; the application explicitly enables it.

Climbing now keeps terrain/prop collisions enabled and follows a capsule-clear path above the corner, with no final position snap. Narrow-phase clearance rejects actual shapes, including closed cave-rock interiors, without treating a tilted crate's entire bounding box as solid. Moving obstacles are checked throughout the mantle. The far bank after Chapter III's swinging cages is lower to make the crossing reachable with collision enabled. Stake sensors are built from the same hulls that are drawn.

Review screenshots can be regenerated with:

```sh
flutter test tool/capture/capture_chapters_test.dart --name '^(title|forest tour|crypt tour|halls tour|chandeliers tour|review.*)$'
```

The screenshot harness loads Flutter's bundled Roboto and Material Icons in addition to Cinzel, so captured menus use real glyphs rather than the widget-test placeholder font. Screenshots validate composition; scripted native-physics tests validate interactions. Real-phone frame rate, thermal behavior and speaker/headphone mixing still require device testing.

`tool/capture/browser_review.py` launches the release build in Chrome, records a short run, checks pause/resume and saves network/audio errors with unedited frames. Web startup explicitly selects Flutter's bundled Box2D WASM asset. `tool/capture/build_review_gallery.py` produces the local before/after gallery and changed-file inventory under `build/review-results/`.
