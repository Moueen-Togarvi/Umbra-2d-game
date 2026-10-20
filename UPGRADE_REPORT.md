# Umbra 0.3 campaign upgrade — verification record

This build is a 40-chapter playtest candidate. Automated route completion is not evidence that a chapter meets its intended human play time or that its puzzles are enjoyable.

## Implemented

- Forty stable chapter IDs, the agreed order, Dawn at 40, a scrollable eight-group chapter menu, and migration of the original 15 saved chapter positions.
- Twenty-five additional routes and expanded original chapters (40 chapters, 269 checkpoint anchors and 12,466 metres of combined horizontal width), using crawl tunnels, cover patrols, movable coffins, water/drainage, rafts, ropes, suspended cages, lifts, counterweights, pendulums, hammer and oil hazards. Existing global jump and movement tuning remains intact.
- Connected upper/lower return sections in chapters 30, 32, 33 and 35–40: unload the lift, reach an upper drain control, return to the courtyard and push the same chest through the drained crawl passage. Last Watch links its control to a shutter and vampire trap.
- Authored checkpoint reconstruction, Continue versus chapter replay, rescued-child and machinery restoration, and reset of unfinished room mechanisms after death.
- Ceiling-safe crouching, cover-based hiding, enemy search, stage threat music, directional vampire steps and cloth sounds.
- Shared browser AudioContext, a 12-SFX voice limit, lazy streaming music, cancellation on chapter changes, pause and mute.
- Silhouette controls, press-only haptics with a persisted toggle, settings reset that preserves progress, and a game-time-driven 60-second ending.
- Forty distinct generated four-panel background atlases (160 panels), WebP scenery, compressed music/ambience and recoverable source archives.

## Release artifacts

| Package | Bytes | MB (decimal) | MiB | Architectures |
|---|---:|---:|---:|---|
| [umbra-0.3.0-arm64.apk](build/releases/umbra-0.3.0-arm64.apk) | 60,177,775 | 60.18 | 57.39 | arm64-v8a |
| [umbra-0.3.0-universal.apk](build/releases/umbra-0.3.0-universal.apk) | 94,594,154 | 94.59 | 90.21 | arm64-v8a, armeabi-v7a, x86_64 |

The ARM64 package is below the approximately 70 MB target. SHA-256 hashes are in `build/releases/artifacts.json`. Both builds use version 0.3.0+3.

The release web export is also packaged as `build/releases/umbra-0.3.0-web.zip` (54,288,466 bytes). Extract it and serve the contents over HTTP; opening `index.html` directly as a local file is not a supported Flutter web launch.

## Evidence and reproducibility

Build and test logs are in `build/upgrade-baseline/`. Machine-readable route, audio, browser and asset results are in `build/review-results/`.

The final full Flutter regression completed with **254 tests passing** (`tests-connected-final.log`), including control-driven completion of all 40 chapters, connected return sections, enemy investigation, low-frame-rate ending timing and fresh/death restoration checks at every authored checkpoint. `flutter analyze` reported no issues (`analyze-connected-final.log`). Tests ran on Linux with Flutter's headless test runner; Android release compilation is not an Android device playtest.

A subsequent search regression exposed an enemy abandoning a distant last sighting before reaching it. Search now allows travel time plus three seconds to investigate, with a bounded timeout if light blocks the route. The new search check, existing cover/detection check and twelve affected new-chapter control routes all passed (**14 tests**, `search-routes-final.log`).

The seven affected original chapter files also passed (**13 tests**, `search-originals-final.log`). Connected-section tests exercised both physical return routes, the Last Watch shutter trap, death-respawn and fresh-world restoration. An immediate-restart regression found that a pressed pedal could activate itself again; resetting its physical resting pose fixed that issue. All three focused connected-section tests passed (`connected-restores-final.log`) and are included in the final full run.

The ending now uses elapsed active-frame time independently of the physics catch-up cap, and carries unused time between fade/wait operations. Muted 60 FPS and 5 FPS ending tests plus the complete chapter-unlock/order test passed (`ending-timing-final.log`, three tests). At 5 FPS the final credit fades out at 60 seconds; the red eyes follow the post-credit silence.

After the full run, unused legacy painted scenery was removed from eager decoding. Live components load their own images, including both chandelier types. Twelve focused physics, Home, Chandeliers, Dawn and image-cache checks passed on this final loading change (`lazy-scenery-verified.log`). The image-cache check confirms that the live cottage/chandeliers load while a replaced orchard painting remains undecoded. The isolated chandelier test now performs image decoding outside Flutter's fake test clock.

The browser sound stress harness submits 100 simultaneous SFX requests. It observed one AudioContext, exactly 12 active voices under saturation, and zero after pause, transition cancellation and mute; no page errors. Run it by building `tool/audio/web_audio_probe.dart` into `build/web-audio-probe`, serving that directory on port 8766 and running `python3 tools/browser_audio_check.py`.

`test/checkpoint_restore_test.dart` reconstructs every authored checkpoint in all 40 chapters, checks its supported spawn, then kills and respawns the player. This tests safe restoration; it does not prove every possible out-of-order interaction or replay the entire remaining chapter from every checkpoint.

Expanded Bone Pit capture passed both alone and grouped with Crypt and Chase. Capture tours reposition the camera/player for screenshots; control-driven route tests are separate.

All 40 runtime background files have distinct SHA-256 hashes and total 3,369,772 bytes. The external archive contains 74 files totaling 160,918,471 bytes. Every archived size and checksum was verified against `assets/design/archive-manifest.json`. Location: `/home/moueen-togarvi/code/Umbra-source-archive/campaign40-2026-10-19/`. Active source inputs remain in the repository; export tooling can find the archived paintings. Git history was not rewritten. The pre-existing staged patch still matches its baseline checksum.

Audio loop analysis is in `build/review-results/audio-loop-report.json`. Numeric boundary checks are not headphone listening. `build/review-results/loop-review.html` provides a single-player end-to-start listening aid using the exported assets directly.

## Browser measurements

Six transitions (Cage, Children, Black Reservoir, Last Watch, Cage, Children) completed using Flutter accessibility actions and keyboard in headless Chromium at 960×540. Settings reset preserved progress, there were no page/console/HTTP errors, and one AudioContext remained across transitions. Normal gameplay peaked at two SFX voices; the separate stress harness reached the enforced limit of twelve.

These software-rendered samples were collected while the regression suite and desktop apps were running. Observed frame rates were **2.43–4.32 FPS**, with median frame times **250–467 ms** and p95 **267–533 ms**. These are poor results and do **not** establish acceptable browser or Android performance. Testing without concurrent builds/tests and physical-device profiling remain necessary.

After explicit garbage collection, JavaScript heap readings were 25.09, 25.82, 26.77, 28.92, 28.99 and 28.21 MB. The final repeated Children scene was 2.39 MB above its first sample; the last sample fell from the previous one. This is a short transition sample, not proof of leak-free operation, and excludes reliable GPU/native texture accounting. Details: `build/review-results/browser/report.json`.

The same six transitions were also measured in hardware-accelerated Chromium: **ANGLE / Mesa Intel UHD Graphics 620**, confirmed by WebGL renderer identification. Frame rates were **5.15–8.93 FPS**, median **117–183 ms**, and p95 **167–433 ms**. There were no browser errors; one AudioContext remained, with a normal-gameplay peak of five SFX voices. Retained JavaScript heap ranged from 24.79 to 29.13 MB and ended at 28.89 MB. This busy-host GPU run is still below a smooth frame rate: browser performance remains an open issue, not an acceptance pass. Details: `build/review-results/browser/gpu-report.json`.

A focused Last Watch profile reproduced 7.55 FPS (133 ms median, 217 ms p95), with one AudioContext and no browser errors. The CPU sampling record is `build/review-results/browser/profile-gpu-cpu.json`; it includes rendering/path construction and cape simulation, but is not sufficient to attribute the whole slowdown to one subsystem.

## Remaining acceptance work

- A human must play all 40 chapters using `PLAYTEST.md`. The requested early 5–8, middle 8–12 and final 12–18 minute durations remain targets, not measured results.
- Human review must judge the variety of reused mechanics and whether the connected return sections make the final chapters sufficiently substantial. Automated completion does not establish puzzle quality or pacing.
- Listen to exported loop joins through headphones and check the ending mix and credit readability.
- Install on a physical Android device to verify haptics, directional sound, cold app resume, touch comfort and sustained frame timing. Linux browser timing does not establish Android performance.
- Browser JavaScript heap samples do not measure native/GPU texture memory or prove absence of all leaks.

No physical Android device was connected during verification. The APK uses the project's existing signing setup for installation/playtesting. Store publishing and production signing are outside this delivery.
