# Umbra character and physics update

The existing six-area Flutter game now uses a shared character controller, a solved visual skeleton, physical interactions and a separate passive ragdoll. The approved hooded raincoat character is preset **3** and remains the default. Presets 1 (scarf) and 2 (satchel) are original procedural alternatives using the same collision dimensions and controller.

## Run and controls

```sh
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Native desktop tests require a C compiler because Forge2D builds Box2D through native assets. Android builds require the Android SDK/NDK.

| Action | Keyboard | Touch |
|---|---|---|
| Walk | A/D or Left/Right | Left/Right |
| Run | Hold Shift | Toggle RUN, then hold direction |
| Variable-height jump | Hold/release Space | Hold/release Jump |
| Grab/pull, catch rope/ledge | Hold E | Hold GRAB |
| Climb a held ledge | Move toward it or Space while holding E | Direction or Jump while holding GRAB |
| Release rope/ledge | Release E; S drops | Release GRAB; DUCK drops |
| Crouch | S/Down | DUCK |
| Character preset | 1/2/3 | LOOK cycles presets |
| Reset at checkpoint | R | RESET in debug mode |
| Physics diagnostics | F1 | DBG |
| Knockdown demonstration | K | FALL in debug mode |
| Ambient sound | M | SOUND |

Jump detaches a rope without adding an arbitrary launch velocity. Release GRAB/E before catching it again. Normal jumping resumes on a later press after reaching ground. Simultaneous movement, jump and grab are supported. Cancelling a touch or pausing the app clears held input.

## Where to try the interactions

World positions are metres and can be inspected in the debug overlay.

- The first forest contains an 8 kg crate near x=6 and a 35 kg crate near x=10. Walk into them to push; hold GRAB/E close to the side, then move backward to pull.
- The bridge area contains a horizontal platform at x=24–27 and a rope near x=29. Jump toward the rope end while holding GRAB/E, then steer the swing.
- The quarry has a vertical platform near x=42.
- The marsh contains a taller ledge at x=73. Jump toward its wall while holding GRAB/E; keep holding and move toward the ledge to climb.
- All six terrain areas, gaps, logs, hazards and progress checkpoints remain playable.

## Physics authority and animation

`Player` owns a fixed-rotation dynamic capsule. Bounded horizontal impulses accelerate toward walking or running speed. The capsule keeps real collision resistance; pushing a blocked or heavy crate cannot move it through a wall. Downward rays validate surface normals and contact distance. Surface velocity is inherited by a standing player and during takeoff. Material friction changes traction, and surfaces beyond the configured slope limit do not count as walkable support.

`CharacterInteractions` temporarily owns motion during rope swinging or ledge hanging/climbing. Crate pulling uses a force-limited motor joint; the rope uses distance joints. The ledge controller validates a wall, reachable top, standing clearance and sampled capsule clearance along a staged path, then drives a bounded motor target. No normal locomotion or climb path teleports the body.

`CharacterRig` solves head, spine, pelvis, shoulders, elbows, hips, knees, ankles and feet. Both legs and arms use reach-clamped two-bone IK. `FootPlacement` stores a stance foot in its support body's local coordinates, so it stays planted and follows a moving platform. Swing feet query their next surface. Arms receive the actual crate, rope or ledge grip point. Walk/run gait, braking lean, anticipation, crouching, landing and hand reach are blended.

`CharacterState` has one active state; constrained interactions, ragdoll and recovery take precedence over locomotion. State, contacts, velocity, feet and joint anchors are visible through the debug overlay.

`CharacterRagdoll` creates 13 dynamic bodies and 12 limited revolute joints from the currently solved skeleton, preserving world joint positions and linear velocity. The capsule is disabled while these bodies own motion. Self-collision is disabled within a character through a negative collision group; terrain and props still collide. This is a **passive ragdoll**, not an active balance controller. After the rig settles, a floor/clearance query chooses a valid standing capsule; the visual pose blends into standing before capsule control returns. Reset always cleans up constraints and ragdoll bodies.

## Tunable scale and timing

`lib/config/game_config.dart` contains movement tuning in metres, kilograms and seconds. The existing level's 1.3 m child scale and 22 m/s² platformer gravity are retained; the prompt's 1.6 m / 10–15 m/s² values were starting suggestions rather than fixed requirements. Walking is 1.8 m/s and running is 3.2 m/s. Jump launch velocity is derived from a 1.15 m apex. Early release cuts ascent; coyote time and buffering are both 0.12 seconds.

The display loop accumulates bounded elapsed time and advances Flame/Forge2D at 120 Hz. Forge2D steps once per simulation update; there is no second manual world step. App resume clears accumulated time. Camera smoothing runs once per display frame, with a dead zone, velocity look-ahead and bounds. Background plates drift more slowly than the physical foreground. Contact shadows and fog are efficient stylized rendering, not physically accurate lighting.

A quiet generated wind loop uses Android's native `AudioTrack`. It pauses with the app and can be muted. Other platforms run silently. No extra package was needed.

## Dependency/API verification

The lockfile resolves Flame 1.38.2, flame_forge2d 0.20.0 and Forge2D 0.15.1. APIs were checked against installed package source and the official references:

- [flame_forge2d 0.20 migration](https://pub.dev/packages/flame_forge2d/versions/0.20.0)
- [Forge2D 0.15.1 native Box2D bindings](https://pub.dev/packages/forge2d/versions/0.15.1)
- [Box2D simulation reference](https://box2d.org/documentation/md_simulation.html)

All geometry uses `ShapeDef`, capsules, polygons or chains. Interactions use `World.createMotorJoint`, `createDistanceJoint` and `createRevoluteJoint`; contact/sensor events are dispatched by the current Flame bridge. No legacy FixtureDef, RopeJoint or ContactListener is used.

## Replacing the procedural characters with images

The supplied screenshot references are visual references; a flat PNG is not an articulated rig. To preserve three new designs, separate or reconstruct each head/hair, torso/pelvis, upper arm, forearm/hand, thigh, shin and foot into transparent layers. Use a consistent rest pose, scale and pivot for all pieces.

1. Add character-specific data to `lib/character/character_preset.dart` and include assets in `pubspec.yaml`.
2. In `lib/render/raincoat_silhouette.dart`, draw each layer between the corresponding `RigJoint` anchors. Scale and rotate around its actual shoulder, elbow, hip, knee or ankle.
3. Keep physics and interaction code shared. If changing height/width, change the capsule, rig dimensions, ray reach, hand constraints and recovery clearance together.
4. Re-run controller and ragdoll tests, then inspect walking, gripping, air poses and the animation-to-ragdoll transition at gameplay scale.

The default procedural render remains a complete visible fallback. It uses native Canvas paths and articulated limb drawing, not a translated single PNG.

## Files changed in this update

New production files:

- `lib/audio/ambient_audio.dart`
- `lib/character/character_interactions.dart`
- `lib/character/character_preset.dart`
- `lib/character/character_ragdoll.dart`
- `lib/character/character_rig.dart`
- `lib/character/character_state.dart`
- `lib/character/foot_placement.dart`
- `lib/entities/physics_props.dart`
- `lib/physics/collision_layers.dart`

Updated production files:

- `README.md` and this guide
- `lib/config/game_config.dart`
- `lib/entities/player.dart`, `ground.dart`, `hill_ground.dart`, `hazard.dart`
- `lib/world/level.dart`
- `lib/game/umbra_game.dart`
- `lib/input/player_intent.dart`, `keyboard_input.dart`, `touch_controls.dart`
- `lib/render/raincoat_silhouette.dart`, `debug_hud.dart`, `six_areas_backdrop.dart`
- `android/app/src/main/kotlin/com/moueen/umbra/MainActivity.kt`
- `pubspec.yaml` (app version 0.2.0+2)

Tests added/updated:

- `test/character_controller_test.dart`
- `test/character_rig_ragdoll_test.dart`
- `test/interaction_test.dart`
- `test/interaction_player_test.dart`
- `test/input_intent_test.dart`
- `test/player_motion_regression_test.dart`
- `test/physics_smoke_test.dart`
- `test/touch_controls_test.dart`

Existing terrain surface tests are also included in the full suite. Generated background artwork and character concept sheets are retained.

## Measured performance

The capture harness measured actual `game.update` work on the Linux host with a 60 Hz display delta and 120 Hz simulation. Over 300 idle frames, mean CPU time was **0.279 ms**, with **0.576 ms** at the 95th percentile. Across the first 60 ragdoll frames, mean time was **0.322 ms**, with **1.015 ms** at the 95th percentile. The smoothed physics step measured **0.106 ms** per tick. Raw measurements are in `build/advanced-preview/host-profile.json`.

These are Flutter widget-test/JIT CPU measurements; they exclude rendering and Android device frame timing. A physical phone's sustained 60 FPS, GPU cost, battery use and audible wind playback remain unverified. The Android emulator uses software graphics and is suitable for installation/input checks, not a reliable phone performance benchmark.

## Verification results — 12 October 2026

Verified with Flutter **3.47.7** and Dart **3.13.5**:

- Dependency resolution completed successfully.
- Formatting: **38 Dart files checked, 0 changes required**.
- Static analysis: **No issues found**; log in `build/advanced-preview/analysis.txt`.
- Full suite: **59 tests passed** in 27 seconds; log in `build/advanced-preview/test-results.txt`.
- The complete six-area route was traversed by actual keyboard input, including crate jumps and the mandatory ledge climb, without checkpoint respawns.
- Actual Player tests verify both crate masses, both hands at the grip, blocked-crate collision and deliberate rope release while GRAB remains held. Focused rig tests cover both facings, three presets, ragdoll stability and recovery clearance.
- Flutter renderer captures include walk/run/jump, crouch, push/pull, rope, ragdoll/recovery and multiple screen sizes. `build/advanced-preview/gameplay.mp4` is a 3.13-second actual renderer capture, not concept art.
- Final release APK **0.2.0+2** built successfully (57.3 MB); Android APK signature verification passed. The same delivered file was installed and cold-launched on the Android 36 emulator; touch walking moved the player and the sampled AndroidRuntime/Flutter error log was empty. Final screenshots are `build/advanced-preview/android-final-idle.png` and `android-final-walk.png`.
- The delivered APK is `/home/moueen-togarvi/Downloads/Umbra-character-physics.apk`. SHA-256: `0869234fad2918f18c6b74da4fe1b4e0ef55521ae993c91f2ae7b397527501ef`. It uses the project's development signing key for direct installation, not store release.

The normal controller and passive ragdoll have separate collision authority. Hands and feet are visual IK during locomotion; all 13 bodies become physical during ragdoll. These implementation details and the device profiling limits above are deliberate boundaries of the delivered system.
