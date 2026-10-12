# Umbra

An original monochrome 2D platformer for Android, built with Flutter, Flame and native Box2D v3 through `flame_forge2d` 0.20.

The six-area level includes a procedural silhouette character, planted-foot IK, distinct walking/running, variable jumps, crates with different masses, moving platforms, a swinging rope, ledge climbing and a 13-body passive ragdoll with recovery. Character **3**, the hooded raincoat child, is selected by default.

See [CHARACTER_SYSTEM.md](CHARACTER_SYSTEM.md) for architecture, tuning, the interaction locations, API references, verification results and instructions for adapting new character artwork. [STEP1_NOTES.md](STEP1_NOTES.md) records the project's initial setup and migration notes.

## Requirements

- Flutter 3.44 or newer, with Dart 3.12 or newer.
- Android SDK and NDK for an APK build.
- A native C compiler for desktop tests: Forge2D compiles bundled Box2D using Dart native assets.

## Build and run

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The current signing configuration uses the development key for direct phone testing; configure a production signing key before store distribution.

## Controls

| Action | Keyboard | Touch |
|---|---|---|
| Walk | A/D, Left/Right | Left/Right |
| Run | Hold Shift | Toggle RUN |
| Jump | Hold/release Space | Hold/release Jump |
| Grab/pull/rope/ledge | Hold E | Hold GRAB |
| Climb a held ledge | Toward ledge or Space | Direction or Jump |
| Crouch/drop | S/Down | DUCK |
| Character preset | 1/2/3 | LOOK |
| Reset checkpoint | R | RESET, visible in debug mode |
| Physics diagnostics | F1 | DBG |
| Knockdown | K | FALL, visible in debug mode |
| Wind audio | M | SOUND |

Touch controls support simultaneous actions and cancellation. Release GRAB/E to detach from a rope or object. App pause clears held input and stops ambient audio. Audio is implemented on Android; other targets are silent.

## World and rendering

Simulation uses metres, kilograms and seconds. A bounded accumulator advances physics at 120 Hz, with the camera updated separately. `GameConfig` exposes movement tuning. The 1.3 m character uses a capsule during locomotion; actual bodies and revolute constraints take over during a knockdown.

The approved six background plates in `assets/images/backgrounds/` use slight parallax and blended transitions. Terrain visuals follow the same sampled vertices as their collision geometry. Native Canvas drawing renders the skeleton, small lantern, grass, contact shadow and foreground grain/vignette. No WebView or HTML is involved.

Character concept sheets remain in `design/`. The older prop generators in `tools/` and `assets/raw/` are retained for asset work; regenerating them is not required to build the current game.

## Verification

The tests exercise actual native physics, controller input, frame-rate consistency, jump timing, feet and floor agreement, ceiling/crouch clearance, moving platforms, push/pull mass resistance, rope release momentum, ledge clearance, ragdoll stability/recovery and the complete six-area route. F1/DBG shows velocity, state, grounded status, measured physics timing, body shapes, contacts, joint anchors and foot targets.
