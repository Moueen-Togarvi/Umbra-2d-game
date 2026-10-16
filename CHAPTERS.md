# Umbra chapters

The story: a boy runs from home after an argument, vampires take him in the night forest, and he has to escape their land. It is told in 15 wordless chapters. **Part 1** (chapters 1–3) is built.

Run the story with `flutter run`. Pass `--dart-define=UMBRA_PROVING_GROUND=true` to open the 96 m test level instead, which is the one all the physics and character tests use.

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
| 118 | The way out leads to "End of Part One", then the title. |

## Tests

Each chapter is played start to finish by a scripted bot that only uses the controls a player has:
- `test/chapter_home_test.dart`
- `test/chapter_forest_test.dart`
- `test/chapter_cage_test.dart`

They also check:
- the title holds the controls
- the opening scene hands them back
- the wall can't be climbed without the cart
- the cage can't open by itself
- walking into the guard kills him

## Capturing frames

```
flutter test tool/capture/capture_chapters_test.dart --plain-name <scene>
```

The scenes are: `title`, `opening`, `tour`, `play`, `forest tour`, `taken` and `cage play`. Frames go to `build/chapters-preview/<scene>/`.

## Art

- Generate the images: `python3 tools/gen_assets_qwen.py assets/raw/part1 tools/part1_assets.json`. This uses Alibaba Model Studio; the key is read from a local file and never printed.
- Bake them to silhouettes: `python3 tools/bake_silhouettes.py assets/raw/part1 assets/images/part1 tools/part1_bake.json`.
- Brand assets: `python3 tools/make_brand.py`. See `BRANDING.md`.
