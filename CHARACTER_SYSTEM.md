# Umbra character, physics, ground and environment

This round rebuilt the boy, his movement, the ground surface and the environment to play and look like LIMBO. The reference was the IGN full walkthrough (youtu.be/uYy9iYtzcDg), studied frame by frame: the boy's proportions, a 30-frame run cycle, jumps, falls, ledge catches, pushing, and the fogged forest. Levels and puzzles are the next round. The current six-area route is unchanged apart from a lowered moving platform.

## What LIMBO does, and what Umbra now does

| LIMBO | Umbra |
|---|---|
| A black boy with a very big head, messy hair and two small white eyes | `CharacterSilhouette`: the head is about a third of his height, with a mop of hair, glowing eyes, a loose shirt and tapered limbs. Smooth anti-aliased curves, no stick limbs. |
| One gait, a light run: about 4.3 steps a second, a high heel kick, moments with both feet off the ground | Always runs at 3.2 m/s. `Gait`: each foot is planted for a third of the cycle, so there is a flight phase; the swinging foot trails behind with the heel kicked up. |
| A short, fixed jump: knees tuck going up, legs dangle coming down | Fixed 1.0 m apex (≈0.64 s in the air, ≈2 m running jump); holding jump changes nothing. Knees tuck going up; legs hang and arms lift coming down. |
| Grabs ledges and ropes by himself | Ledges and ropes in reach are caught automatically in the air. Toward or jump climbs; down or steering away lets go; jump kicks off a rope. |
| One action button | E/Ctrl or the ✋ button only grabs and pulls. Pushing happens by running into a crate. |
| No crouch, no HUD | No crouch. Release builds show only four faint glyph buttons. |
| Falls and traps kill: the body goes limp, the picture fades, he is back moments earlier | Landing faster than 14 m/s (about a 4.5 m drop), or touching stakes, makes the real 13-body ragdoll go limp and stay limp. `DeathSequence`: 1.3 s on the ground, fade to black, respawn at the checkpoint, fade in. Drops of about 1.5 m or more give a hard landing (deep crouch, a moment's pause). |
| Dark lumpy ground, wispy grass hiding the feet | Collision stays a smooth Box2D chain. The drawn edge has crumbs, stones, jagged cliff faces and hanging roots at pits. Two grass layers sway in the wind and part around his legs. |
| Grey fog, giant blurred trunks at several depths, a hazy light, black shapes passing in front, heavy vignette, grain, flicker | `FogBackdrop`: four baked depth layers (paler, blurrier and slower with distance), a light glow and shafts, ground mist and dust. `ForegroundFog`: blurred trunks and grass in front of the world. `ForegroundOverlay`: rounded vignette, film grain and flicker. |
| The camera keeps him small and leads where he runs | The view is 10.5 m tall, so the boy fills about 12% of the screen. 1.8 m look-ahead, eased so turning doesn't jerk the view, and a critically damped horizontal follow. |

## Legs, feet and ground contact (round 1b, 13 October 2026)

After testing on a phone, the legs looked stiff, the feet were thin slivers, and at a pit edge the feet hung in the air. LIMBO close-ups (0:39 on the log, 0:48–0:55 at the crate) show shorts, knees that are always soft, and chunky boots that sit flat on whatever they touch. The legs were rebuilt on that basis.

- **Leg physics** (`lib/character/leg_physics.dart`, now `limb_physics.dart`):
  - Each leg is a small Verlet chain (knee, ankle, toe) hanging from the solved hip.
  - The points have momentum and gravity and are pulled toward the animated pose. The pull is strong while swinging, loose in the air (legs trail on take-off) and weak when hanging from a rope (legs swing).
  - Constraints hold the bones at fixed length, keep knees bending forward and keep the ankle in range.
  - The soles collide with the real ground, which is looked up from the Box2D world once per step and then treated as a plane.
  - A planted foot is pinned. These simulated joints are what gets drawn, and what the death ragdoll starts from.
- **Pelvis spring** (`Player`):
  - The real impact speed of a landing, plus a small kick on each footstrike, drives a spring-damper (about 3.3 Hz).
  - The pelvis sinks and the knees fold to catch it, then it recovers. This replaces the old timed landing dip.
- **Feet on real ground** (`ground_probe.dart`, `foot_placement.dart`):
  - Feet stand on the *drawn* bank edge, not the hidden collision line.
  - Over a gap, a step comes back onto the lip.
  - Each sole follows the normal of the ground under it.
  - Each foot rolls heel–flat–toe. While pushing or pulling, steps are short and land behind the hips.
- **Stance:** soft knees (standing hip 0.195 H), feet apart (+0.07 H / −0.06 H), and a slow weight shift.
- **Drawing:** blocky shorts over the upper thigh, sturdier bare legs, and a real boot outline (0.13 H × 0.045 H: rounded heel, flat sole, upturned toe). The front grass is shorter, so the boots show.
- **Verification:**
  - **Tests:** 71 pass, including 6 new leg-physics tests and the no-skating, landing-spring and soft-knee checks.
  - **Chrome:** about 60 FPS.
  - **Android emulator:** the APK renders the new legs, and logcat shows no app errors.

## Arms, rope climbing, turn, idle, push, slide, crates and dust (round 1c, 13 October 2026)

The user's next eight picks were checked against the walkthrough's rope (0:58–1:04), slope (0:41.7–0:42.4), turn (0:52.6–0:53.2), and jump and fall frames.

- **Arm physics** (`lib/character/limb_physics.dart`, renamed from `leg_physics.dart`):
  - The arms are Verlet chains (shoulder → elbow → hand), like the legs.
    - Elbows only bend backwards.
    - A gripping hand is pinned to what it holds.
    - A hand can be put down on the ground but not through it.
    - They are loose in the air, so they trail on take-off.
  - Limb damping is now relative to the body. This keeps a long fall from blowing the arms and legs up over the head.
  - The air pose no longer points the arms straight ahead. Going up, the elbows are bent and the front hand is near the face. Falling, both arms go up and out with a slow flail.
- **Rope climbing** (`SwingRope`, `CharacterInteractions`, `rope_grips.dart`):
  - The rope is a real rope joint (no stiffness, a length limit), so it pulls when taut and never pushes.
  - It is caught anywhere along it: the bob moves to the catch point and the joint shortens to it.
  - The visible rope is a chain of points along its whole length. Taut above his hands, it is a straight line. Below his hands it hangs and swings, and his feet clamp it once enough rope hangs below him.
  - **Up** (W/↑, or the touch ˄) climbs at 0.9 m/s; **down** (S/↓, or ˅) at 1.4 m/s.
  - The hands go hand over hand: each grip stays put until the body has climbed past it, then that hand takes a new grip on the far side of the other.
  - Holding down at the bottom for 0.3 s lets go. The jump button kicks off; W/↑ on a rope climbs instead of jumping.
  - The two climb buttons only appear while he holds a rope.
- **Turn**:
  - The drawn facing turns on an angle and passes through a front view in 0.12 s.
  - The eyes slide to the middle of the face. The head stays at least 88% wide and the chest at least 55%.
  - The feet step round under him.
  - It replaces the old squash of the whole figure.
- **Idle life**: after 2.5 s standing still, every 3–6 s he does one of three things:
  - looks up
  - turns his face to the camera
  - shifts his feet to a new stance

  He goes through all three before repeating one. After a stop the feet take real little steps (0.2 s each) into place, instead of sliding.
- **Push and pull**:
  - While pushing, a brace shape (props only) grows out of the front of the body, 0.22 m plus up to 0.10 m with effort. He holds the crate at arm's length with nearly straight arms.
  - Effort comes from the crate's mass and how little it moves. It sets the lean (0.08–0.30 rad into a push, back from a pull), the crouch and how far the head drops.
  - The run lean no longer adds on top.
- **Sliding**:
  - Ground steeper than 32° starts a slide, which ends below 28°.
  - Speed along the slope gains g(sin θ − 0.15 cos θ), up to 7 m/s, and steering only nudges it.
  - He slides upright on both feet, leaning back, with his arms out.
  - After the slide the speed carries on, braking gently, for 0.6 s.
  - Jumping still works.
  - Area 03 now has a steep bank (up to 46°) to show it. The log there moved to 38.6–40.0 m.
- **Crates tip over**:
  - Crates can rotate now (angular damping 0.4). They tumble off edges and lie flat on slopes.
  - A steady push on flat ground can't topple one (tested below 0.05 rad).
- **Landing reactions** (`lib/render/dust.dart`):
  - Landings faster than 4 m/s throw up dark earth specks and grass bits, with a soft pale haze.
  - Sliding sprays specks behind him.
  - Landings faster than 7 m/s jolt the camera, by up to 0.12 m, fading over 0.5 s.
  - All of it is plain circles, lines and a radial gradient, with no blur filters.
- **Verification**:
  - **Tests:** 87 pass. They include new tests for:
    - the arms: bone lengths, elbows, falling pose, grips, hands on the ground
    - the turn
    - idle actions and stepping without sliding
    - push brace, straight arms and heavy-crate lean
    - crates tumbling off a ledge
    - sliding, no sliding on ordinary slopes, and jumping out of a slide
    - the rope: never pushing, catching part way down, climbing up and down, letting go at the bottom
    - landing dust and camera shake
    - the climb buttons
  - **Chrome:** about 60 FPS at 1280×576 and 1920×864.
  - **Android emulator:** the APK runs, touch running and pushing work, and logcat shows no app errors.

## Calm arms (round 1d, 14 October 2026)

On a phone the arms shook all the time. Two causes:
- **The arm physics was a bouncy spring.** Each step it pulled the points toward the pose while keeping their momentum. A 5 cm jolt overshot by 37% on the ground (53% in the air) and swung back and forth about 20 times.
- **The arm pose itself jumped.** Every moment's hop over a bump while running threw the arms into the raised air pose in about 0.08 s, and dropped them again on landing. A hand also swung into the side of the moving platform and was popped 25 cm up onto its top.

The fix:
- **One hand per arm.** It is followed in its shoulder's frame, so the torso's bob and lean carry the arm along without shaking it.
  - The spring is critically damped (6 Hz on the ground, 3.5 Hz in the air, 12 Hz and pinned when gripping), so it never overshoots.
  - The hand follows the pose at no more than 3 m/s, moves at no more than 5 m/s, and feels a small, capped share of the shoulder's jolts.
- **The elbow is solved by IK** from shoulder and hand, so it always bends backwards and the bones never stretch.
- **Arms go up only on a jump or a fall longer than 0.15 s**, and ease in and out of that pose. The landing crouches also come on over a few frames.
- **Calmer poses:** the fall flail went from ±0.25 rad to a slow ±0.06 rad drift, and the run swing is about 15% smaller.
- **Hand ground contact** only looks between where the palm was last step and where it is now.

Measured in the real game with `flutter test tool/capture/arm_jitter_test.dart` (worst one-step jolt of a hand relative to its shoulder, front/back hand):

| Scene | Before | After |
|---|---|---|
| Running | 194 / 213 mm | 8 / 12 mm |
| Jump | 152 / 216 mm | 13 / 14 mm |
| Fall and landing | 478 / 383 mm | 16 / 17 mm |

The run swing stays at about 41 cm. Tests: 91 pass, including new ones for:
- no wobble after a jolt
- no added jitter while running
- still hands while standing
- a small take-off trail with no bounce back

## Architecture

Physics authority hasn't changed. `Player` owns a fixed-rotation capsule (0.42 × 1.3 m, 40 kg). Movement is bounded velocity impulses, so crates and walls really resist it. `CharacterInteractions` owns the motor and distance joints for pulling, ropes and ledges. `CharacterRagdoll` takes over with 13 bodies and 12 limited revolute joints when he dies or is knocked down.

- `lib/character/character_rig.dart`: `CharacterPose` (what the controller wants) → `CharacterRig.solve` → `CharacterRigPose` (world joints in metres).
  - Proportions are constants on `CharacterRig`; `restShoulder` and `armReach` feed the interaction reach checks, so the two can't disagree.
  - Hanging from a rope lowers the body and shrugs the shoulders, so the hands hold above the big head.
- `Gait` sets run timing. Both the rig and `FootPlacement` use it, so the stance and swing that are drawn always match the stance and swing that are planted.
- `lib/render/character_silhouette.dart` draws the boy from the solved joints. The ragdoll is drawn by the same code.
- `lib/world/death_sequence.dart` turns `Player.isDead` into the fade and respawn. A manual reset cancels it.
- `lib/render/grass.dart` builds every blade of a layer into one path, so a screen of grass is one draw call. `GrassWind` is shared by every patch so they sway together.
- `lib/render/fog_layer.dart` bakes each depth layer once at load, at low resolution: blurred content loses nothing when scaled up.

## Tuning (`lib/config/game_config.dart`)

| Value | Setting |
|---|---|
| Run speed | 3.2 m/s; ground acceleration 18 m/s², braking 26 m/s², air 3.5 m/s² |
| Gravity | 18 m/s² rising, ×1.2 falling |
| Jump | 1.0 m apex, 0.017 s anticipation, 0.12 s coyote time and buffer |
| Rope kick-off | +3.6 m/s upward on top of the swing's momentum |
| Hard landing / death | 8.2 m/s / 14 m/s impact |
| Death beat | 1.3 s linger, 0.55 s fade out, 0.25 s black, 0.8 s fade in |
| Camera | 18.67 × 10.5 m view, 1.8 m look-ahead, 0.38 s horizontal smoothing |

## Engine problems found and fixed on the way

- **Pit walls never collided.** An open Box2D v3 chain treats its first and last points as ghost anchors, so the segments touching them don't collide. Each bank's chain now has an extra ghost point under each wall. A falling body used to slide under the banks; now it lands in the pit.
- **The boy was invisible in the browser.** Flutter web records a drawn `Path` by reference, so reusing one `Path` for several draws in a frame drew only the last shape. Every shape now gets its own `Path`. A `MaskFilter.blur` on paths at world scale also didn't render on the web, so the body uses plain anti-aliased edges.
- **The forest was missing on Android.** Impeller scales a save-layer blur by transforms applied inside the layer, which blurred the trees away. Layers are now baked in two passes (sharp, then blurred with no transform). The vignette and light glow are baked images too.
- **Frame rate in the browser.** Profiling showed path building and drawing was about 40% of a frame. Banks off screen are now skipped, the drawn ground edge uses fewer vertices, and grass has a blade budget.

## Verification (12 October 2026)

- `flutter analyze`: no issues. `dart format`: 40 files, no changes.
- `flutter test`: **64 tests passed**. They cover:
  - running speed, reversal and turning
  - the fixed jump height, also across 30/60/120 fps
  - coyote time and the jump buffer
  - ceilings and moving platforms
  - planted feet not sliding, with a real flight phase in the run
  - push/pull mass resistance
  - automatic rope and ledge catches, letting go, and no re-catching
  - the rope kick-off
  - hard landings
  - death from a long fall and on the stakes, including the fade and respawn
  - the debug knockdown and recovery
  - the whole level route without dying
  - touch controls, including multi-touch and debug buttons
  - LIMBO proportions
  - seamless fog layers under 16 MB
- Real Chrome, release web build (`tools/playtest.py`, headed): a steady **60 FPS** at 640×288, 1280×576 and 1920×864 (worst frame 16.8 ms); 57–60 FPS while also recording video. The only console errors are two 404s from Forge2D probing for its WASM file before loading it from the next path.
- Android: release APK built (43.4 MB) and installed on the `UmbraTest` emulator (Impeller, OpenGL ES).
  - The game launches and the fogged forest renders.
  - Holding the touch ▶ runs the boy.
  - No app errors appear in logcat.
- Not verified:
  - Frame rate on a real phone: the emulator uses software graphics.
  - Faint dotted rings in the emulator's gradients. They are banding from its software GPU and also appear in older screenshots of the previous build.

To look at the result yourself:

```sh
flutter test tool/capture/capture_frames_test.dart   # frames -> build/limbo-preview/
python3 tools/contact_sheet.py run                    # close-up sheet of the run cycle
flutter build web --release && python3 tools/playtest.py
```

## Files

New:
- `lib/render/character_silhouette.dart`
- `lib/render/fog_backdrop.dart`
- `lib/render/fog_layer.dart`
- `lib/render/grass.dart`
- `lib/world/death_sequence.dart`
- `test/environment_test.dart`
- `tool/capture/capture_frames_test.dart`
- `tools/contact_sheet.py`

Rewritten:
- `lib/character/character_rig.dart`
- `lib/entities/player.dart`
- `lib/entities/hill_ground.dart`
- `lib/entities/ground.dart`
- `lib/entities/hazard.dart`
- `lib/render/foreground_overlay.dart`
- `lib/input/player_intent.dart`
- `lib/input/touch_controls.dart`
- `tools/playtest.py`

Updated:
- `lib/character/character_interactions.dart`
- `lib/character/character_ragdoll.dart`
- `lib/character/character_state.dart`
- `lib/character/foot_placement.dart`
- `lib/config/game_config.dart`
- `lib/entities/physics_props.dart`
- `lib/game/umbra_game.dart`
- `lib/input/keyboard_input.dart`
- `lib/render/debug_hud.dart`
- `lib/world/level.dart`
- `pubspec.yaml`
- `README.md`
- all tests

Removed:
- `lib/character/character_preset.dart`
- `lib/render/raincoat_silhouette.dart`
- `lib/render/boy_silhouette.dart`
- `lib/render/atmosphere_backdrop.dart`
- `lib/render/six_areas_backdrop.dart`

The painted background and prop images stay in `assets/images/`, but they are no longer bundled.
