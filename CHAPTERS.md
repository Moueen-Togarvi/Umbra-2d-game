# Umbra chapters

The story: a boy runs from home after an argument, vampires take him in the night forest, and he has to escape their land. It is told in 15 wordless chapters. **Part 1** (chapters 1–3) and **Part 2** (chapters 4–6, the water under the castle) are built.

Run the story with `flutter run`. Pass `--dart-define=UMBRA_PROVING_GROUND=true` to open the 96 m test level instead, which is the one all the physics and character tests use. Pass `--dart-define=UMBRA_UNLOCK_ALL=true` to open every chapter in the title's chapter list, for checking a later chapter on a device (it saves that progress).

## How a chapter is made

- **`Stage`** (`lib/world/stage.dart`) is what the game holds. It has a size, its air (a `MoodTrack`), the boy and the checkpoints. `Level` (the proving ground) and every chapter are stages.
- **`Chapter`** (`lib/chapters/chapter.dart`) builds the ground from data: a few control points per bank, with a pit wherever two banks don't touch. It also:
  - adds the walls and the boy
  - saves at the checkpoints
  - runs `onReach(x)` triggers and cutscenes
  - notices the exit

  A subclass describes its land and furnishes it in `furnish()`.
- **`ChapterDirector`** (`lib/story/chapter_director.dart`) runs the story:
  - the title over the first scene
  - the card before each chapter
  - the fades
  - the end of the part

  It is a queue of steps played in game time, so it behaves the same at any frame rate and in tests. Progress (the furthest chapter reached) is saved with `shared_preferences`.
- **`Cutscene`** (`lib/story/cutscene.dart`) is a list of beats: `Run`, `Wait`, `Do`, `Look` (camera), `Fade`, `WaitUntil`, `Together` and `Sequence`. While one runs it holds the controls, so the touch buttons hide and keys do nothing.
- **Moods** (`lib/render/mood.dart`) set the fog: dusk, night or cave. `MoodTrack` blends from one to another across x. A cave mood stands rock in the fog instead of trees.
- **Water** (`WaterBody`, `lib/physics/water.dart`) floats everything by Archimedes. Each step:
  - the part of every shape under the surface is found exactly: polygons are clipped against the surface, and circles are cut into segments
  - the water pushes up on that part's centroid with the weight it displaces
  - it drags towards its current
  - it resists turning, in proportion to the wet part's second moment of area
  - it resists bobbing (added mass)

  So a crate floats as deep as its density says, settles under the boy's weight and tips when he stands near an end. His feet press on whatever he stands on, so the water carries his real weight. He can't swim: he wades slowly where he can stand, and drowns if his head stays under for 0.7 s. The level can be raised or lowered (`floodTo`), the surface ripples where things break it, and what is under it fades into the dark. `Chapter.waterPit` fills a pit with water instead of stakes. The floating things are in `lib/entities/water_props.dart`: `FloatingLog`, `Coffin` (optionally chained to the floor), `Barrel` (a cask lying on its side), and `LogSource` (logs sent down a river to a sinkhole).
- **Scenery** (`SceneryProp`) is the AI-generated art, baked to silhouettes. Anything further off than depth 0.85 is drawn by the backdrop, between the fog layers nearer and further than it.

## Chapter 1: Home (dusk into night, 122 m)

| x (m) | What happens |
|---|---|
| 0–15 | **Opening.** The cottage at dusk, its lamp lit. Two shadows argue behind the upper window's curtain. The door is thrown open (a one-dimensional hinge simulation drawn in perspective), the boy runs out, his mother comes to the doorway and reaches after him. He looks back. |
| 21–26.5 | Sheets on a washing line: Verlet cloth pegged at three points, stirred by the breeze and by the air he pushes past them. |
| 28.6 | A fence running into the fog, to hop. |
| 31–36 | A **cart** on two real wheel joints, to push against the dry-stone wall. The wall is 2.8 m, too high to reach from the ground, so he climbs the wall from the cart. |
| 46.6–51.2 | A ditch crossed on a **plank on a post** that tips under his weight. |
| 58 | A fallen tree. |
| 66–69.5 | A gully crossed on a **tyre swing**. |
| 99.5 | **Scene:** on top of the hill he looks back at the one lit window, far away. |
| 118.5 | The forest edge leads to chapter 2. |

## Chapter 2: The Night Forest (night, 204 m)

| x (m) | What happens |
|---|---|
| 10–22 | Eyes in the brambles that go out as he comes near. Bats burst from a dead tree. |
| 32–39 | A hunters' **stake pit** too wide to jump. He pushes the crate in first; it lands on the stakes, and he steps down onto it and catches the far lip. |
| 66.5–70.2 | A ravine crossed on a rope. A swarm of bats streams past as he swings. |
| 93.5 | A bank steep enough that he slides down it. |
| 97.5 | **Glimpse:** far off in the fog, a tall figure with red eyes walks the other way. |
| 124–131 | A fallen giant to catch and climb. |
| 156–180 | The graveyard. Nothing watches any more. |
| 188 | **Scene:** he looks back for the lamp; a vampire drops from the trees, lands, rises with its claws out. Cut to black. |

## Chapter 3: The Cage (cave, 124 m)

| x (m) | What happens |
|---|---|
| 0–6 | He wakes in an **iron cage** hanging over stakes on a chain of jointed links. His feet push the floor as hard as it pushes him, so running against the swing pumps it higher. A blow against the rock at 2.6 m/s or more snaps the latch, and the door, hinged at its foot, falls open onto the ledge. |
| 36–49.5 | A rock step, then **two hanging cages** whose roofs are the only way over a pit. They swing as he lands on them. |
| 54.4 | A spring **foot pedal**. Stepping on it lets the winch go, and a cage is lowered into the next pit as a bridge. |
| 70–100 | **The tunnel:** a vampire paces 77–97 m. Anywhere in front of it within reach is death. The only hiding place is a black niche at 85–86.6 m, where he must keep still while it passes. |
| 118 | The way out leads into chapter 4. |

## Chapter 4: The Caves (cave, 200 m)

The water under the vampires' land. He can't swim.

| x (m) | What happens |
|---|---|
| 19.6–28.5 | A **pool** too wide to jump. The crate on the bank floats: he pushes it in, climbs on, and the slow draw of the water carries it, and him, across. |
| 53.3–60.7 | A shallow **ford**: he wades, slowly, up to his waist. |
| 70–92 | An **underground river** comes out of the rock and runs fast to a sinkhole. Logs come down it one at a time. He rides one and must leap for the high bank before the hole takes it. |
| 116–126 | A **dry cistern** whose only way out is far above. He goes down a ramp under the rock and steps on a crank in the floor: a gate shuts behind him, the sluice opens, and the crate he stands on rises with the water to the exit. |
| 196 | Out. |

## Chapter 5: The Crypt (cave, 180 m)

| x (m) | What happens |
|---|---|
| 27–41 | A flooded hall crossed on **five coffins chained to the floor**. Each floats only until he stands on it, then sinks under his weight, so he must keep moving from one to the next. |
| 52.9 | A **drain** pedal. The drowned passage beyond (54–68) empties to wading depth, leaving a coffin aground against the far wall as a step. |
| 80.3 | **The tomb.** As he passes, the lid shifts and a vampire climbs out after him. |
| 89.2 | A heavy coffin in the way, to hop. |
| 97–100.5 | **Running water**, the one thing it won't cross. It stops at the edge and reaches for him over the stream. |
| 176 | The crypt gate. |

## Chapter 6: The Bone Pit (cave, 150 m)

| x (m) | What happens |
|---|---|
| 25–38 | A black pool with **four old casks** floating in it, the only footing. Each dips and tips under him: he stands near the far end and hops to the next. |
| 52.6 | A **drain**. The flooded chamber (54–88) runs out under the rock, and he walks through the tunnel the water leaves. |
| 92.4–101 | **The shaft.** At its foot, a figure at the top opens the sluices and the water comes up after him. He climbs from ledge to ledge (7.8, 6.0, 4.2) to the top at 2.4, ahead of the water. |
| 146 | The way out leads to "End of Part Two", then the title. |

## Tests

Each chapter is played start to finish by a scripted bot that only uses the controls a player has:
- `test/chapter_home_test.dart`
- `test/chapter_forest_test.dart`
- `test/chapter_cage_test.dart`
- `test/chapter_caves_test.dart`
- `test/chapter_crypt_test.dart`
- `test/chapter_bone_pit_test.dart`

`test/support/campaign.dart` boots the story and enters any chapter for them. `test/water_test.dart` checks the water on its own: a light crate floats as deep as its density says, a heavy one sinks, one set on its corner rights itself, a current carries it along, and a load pushes it deeper.

They also check:
- the title holds the controls
- the opening scene hands them back
- the wall can't be climbed without the cart
- the cage can't open by itself
- walking into the guard kills him
- the boy drowns in deep water and wades in the ford
- the raft carries his real weight (about 40 kg) without tipping
- a coffin sinks under him and rises again
- the vampire won't cross the stream
- a cask dips and tips under him

## Capturing frames

```
flutter test tool/capture/capture_chapters_test.dart --plain-name <scene>
```

The scenes are: `title`, `opening`, `tour`, `play`, `forest tour`, `taken`, `cage play`, `caves tour`, `crypt tour` and `pit tour`. `python3 tools/montage.py <dir> <out.png> <columns>` puts a scene's frames on one sheet. Frames go to `build/chapters-preview/<scene>/`.

## Art

- Generate the images: `python3 tools/gen_assets_qwen.py assets/raw/part1 tools/part1_assets.json`. This uses Alibaba Model Studio; the key is read from a local file and never printed.
- Bake them to silhouettes: `python3 tools/bake_silhouettes.py assets/raw/part1 assets/images/part1 tools/part1_bake.json`.
- Part 2 uses the same commands with `part2` (`tools/part2_assets.json`, `tools/part2_bake.json`).
- Brand assets: `python3 tools/make_brand.py`. See `BRANDING.md`.
