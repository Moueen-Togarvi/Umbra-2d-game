# Umbra

A Limbo-inspired atmospheric 2D platformer in Flutter + Flame: solid black
silhouettes on a flat light-grey background.

Physics is simulated with **Box2D** via
[`flame_forge2d`](https://pub.dev/packages/flame_forge2d) 0.20, so the world is
laid out in **metres, kilograms and seconds** rather than pixels. See
[`STEP1_NOTES.md`](STEP1_NOTES.md) for why that matters and for a translation
table from the pre-0.20 API you will find in most tutorials.

## Requirements

- Flutter **3.44.0 or newer** (`flame_forge2d` 0.20 needs it)
- Dart SDK 3.12.0 or newer

## Running

The repository holds only portable code — no generated platform folders. Create
them once for whichever platforms you want:

```bash
flutter create --project-name umbra --platforms=linux,macos,windows,web .
flutter pub get
flutter run -d linux      # or macos / windows / chrome
```

`flutter create` will not overwrite anything already in `lib/` or `pubspec.yaml`.

## Controls

| Action | Keys |
|---|---|
| Walk | `A` / `D`, or `←` / `→` |
| Jump | `Space`, `W`, or `↑` |

Walking into the pit respawns you at the checkpoint.

## Tests

```bash
flutter test
```

These run the real physics world and drive it through real key events, checking
that the player rests on the floor, walks, jumps to the configured height,
cannot double-jump, and respawns cleanly at the checkpoint.

## Layout

```
lib/
  config/     tuning constants and the colour palette — every magic number lives here
  entities/   one file per thing in the world (player, ground, hazard)
  game/       the Forge2DGame subclass: camera, background, wiring
  input/      keyboard -> intent. Knows nothing about physics.
  world/      level layout and the checkpoint/respawn system
```

The separation to preserve as this grows: **input never touches a physics
body**, **constants never get inlined into an entity**, and **the checkpoint
system keeps working after every change**.
