# Mother and vampire artwork

The runtime art (`mother_reference.png`, `vampire_rig.png`) is bundled from `assets/images/characters/`. This folder keeps the prompts and the unused rig iteration out of the app.

Generated with the built-in imagegen tool from the two user-approved character reference sheets, 2026-10-18. Exact prompts are in `prompts.json`. Each RGBA atlas has eight isolated parts in a 4×2 grid; alpha bounds are read once by `NpcAtlas` and frames use ordinary Canvas transforms.

- `mother_reference.png`: the approved reaching figure isolated from the supplied sheet using built-in imagegen. Full portrait preserves dress/body proportions; the near arm rotates at the shoulder once, holds, then lowers permanently for that scene. Exact edit prompt: `mother_reference_prompt.txt`.
- `mother_rig.png`: earlier reconstructed rig, retained as an unused art iteration.
- `vampire_rig.png`: head, collar/torso, coat tails, upper sleeve, forearm sleeve, claw hand, thigh, shin/boot.

These are reconstructed layered assets, not independent layers extracted from the original flat reference. Mother now uses the reference portrait and a single 3.55-second reach gesture; repeated reach inputs cannot restart it. Doorway entry remains spring-driven. Vampires retain their existing AI, gait, crouch, reach, light reactions and ash effects. Cloth simulation drives coat-tail sway. Their bodies remain the existing query-driven NPC system, not new articulated rigid-body ragdolls. The hero renderer and collision system are unchanged.

The shared Flame image cache owns the portrait and vampire atlas. Cottage and vampire load hooks await their art; the campaign preloads both before creating its first physics stage. Generated eye color is desaturated at render time so the live red-eye effect can fade.

Review: `flutter test tool/capture/capture_chapters_test.dart --name 'review figures|reference characters in game'`. The figures sheet and doorway/enemy screenshots are actual game renderers, with test-only close-up framing. Run the full test suite for chapter behavior regressions.

## Vampire alignment review

The visible sleeve root is calibrated to UV `(0.20, 0.34)` in the torso alpha bounds. Both shoulder positions use the torso's own transform. Resting wrists target the pelvis at `-0.10 m` vertically; walking hand swing is limited to `0.06 m`. Small dark underlays sit beneath the textured shoulder, elbow and cuff junctions. Upper-arm, forearm and hand sockets use explicit UV anchors rather than the rectangle centres.

The archived alignment review split the combined shin/boot sprite into overlapping UV regions. That walking appearance has now been superseded by the approved floating direction below.

`tool/capture/capture_vampire_test.dart` captures matching 20-second, 20 FPS sequences and 12 still views (idle, walk, chase, reach, shield and crouch, each facing left/right). Each pass saves the renderer source used for that pass. Run with `--dart-define=VAMPIRE_REVIEW=before` before editing and `--dart-define=VAMPIRE_REVIEW=after` afterwards, then run `bash tool/capture/build_vampire_review.sh`. The gallery is written to `build/review-results/vampire-refine-v2/index.html`; individual and combined H.264 videos are included. These are deterministic renderer captures rather than recorded physics playthroughs.

## Approved floating appearance

Vampires now render no thighs, lower legs or boots. The existing articulated upper body drifts vertically by ±0.035 m, with a nominal 0.35 m clearance beneath the coat. Its original coat texture is deformed by a small triangle-strip mesh and fades into procedural wisps. A bounded pool of translucent mist stays at the local ground reference and fades out when the actor is far above/below that surface. Shader and vertex resources are disposed explicitly. Legacy leg artwork remains unused in the atlas.

This changes appearance and glide animation; existing ground-relative AI routes, interaction distances, drop/rise events and light/water responses remain authoritative. It does not add aerial navigation over level geometry.

Capture the current direction with `flutter test tool/capture/capture_vampire_test.dart --name 'vampire comparison stills and motion' --dart-define=VAMPIRE_REVIEW_DIR=build/review-results/vampire-hover --dart-define=VAMPIRE_HOVER_REVIEW=true`. `test/vampire_hover_test.dart` checks that the floor region contains mist but no opaque legs in both facing directions, and that mist stays local and disappears for a distant airborne actor.
