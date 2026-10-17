# Campaign backgrounds

15 original generated grayscale atlases, with four different paintings per chapter (60 locations). Created with the imagegen tool on 2026-10-18 using the three user-approved visual samples as tone references. No Playdead artwork is packaged.

Each `chapter_NN.png` is a 2×2 atlas in reading order. The paintings contain scenery, not characters, playable terrain or collision geometry. Native atlas resolution is 1672×941; this is soft background art, not four individual full-HD frames. The atlas adds approximately 36 MiB of packaged PNG assets in total.

## Locations

| Chapter | Background areas, in travel order |
| --- | --- |
| 1. Home | Village edge → Quiet fields → Old orchard → Forest boundary |
| 2. The Night Forest | Old woodland → Hunters ravine → Deep hollow → Graveyard clearing |
| 3. The Cage | Holding cavern → Hanging cages → Winch chamber → Low tunnel |
| 4. The Caves | Limestone pool → River gorge → Old cistern → Dry ascent |
| 5. The Crypt | Crypt entrance → Burial gallery → Flooded vault → Ancient passage |
| 6. The Bone Pit | Lower cavern → Bone chamber → Flood shaft → Stone throat |
| 7. The Chase | Service corridor → Abandoned library → Stair gallery → Escape passage |
| 8. The Halls | Vaulted entrance → Shadow gallery → Lift shaft → Upper windows |
| 9. The Chandeliers | Ballroom approach → Grand ballroom → Organ gallery → Throne arcade |
| 10. The Clock Tower | Pendulum shaft → Striking train → Clock face → Belfry |
| 11. The Children | Cell corridor → Old ward → Service passage → Drain tunnel |
| 12. The Mill | Mill race → Wheel chamber → Reservoir → Stone channel |
| 13. The Great Gate | Courtyard → Gatehouse → Moat → Outer wall |
| 14. The Storm | Coastal path → Windblown crags → Sea chasm → Exposed ridge |
| 15. Dawn | Last woodland → First light → Morning orchard → Homeward fields |

## Runtime

- `lib/render/chapter_backgrounds.dart` sets location boundaries in world metres.
- `lib/render/chapter_backdrop.dart` crops one panel (two during transitions), covers the viewport without stretching, and pans gently within its overscan. Eight-metre smoothstep crossfades are reversible when walking back.
- These are painted plates with camera panning. Painted depth layers are not independently animated parallax sprites.
- Each active chapter owns one decoded atlas (~6 MiB pixel data). The old image is disposed when its backdrop is removed. Decode finishes before new physics bodies are created so disk/browser loading cannot advance a puzzle's initial state.
- Campaign far scenery and selected oversized background props are replaced. Original foreground surface dressing, live hazards, weather, lights, hero renderer, terrain colors and physics remain. The proving ground retains its procedural backdrop.
- Sunshine is not baked into the plates. Dawn retains the existing live sunrise gameplay.

## Reproduce review

```sh
flutter test
flutter test tool/capture/capture_chapters_test.dart --plain-name 'background review'
python3 tool/capture/build_background_gallery.py
flutter analyze
flutter build web --release --base-href=/build/web/
python3 -m http.server 8790 --bind 127.0.0.1
```

Open `/build/review-results/all-backgrounds/index.html` on that server for all 60 captures, or `/build/web/` to play. Review frames use test-only camera/player positioning and do not represent a complete recorded playthrough. No mobile performance or memory profiler result is claimed.
