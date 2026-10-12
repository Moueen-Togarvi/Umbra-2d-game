import 'package:flame/components.dart' show Component;
import 'package:flame/game.dart' show Vector2;

import '../config/game_config.dart';
import '../entities/ground.dart';
import '../entities/hazard.dart';
import '../entities/hill_ground.dart';
import '../entities/player.dart';
import '../entities/physics_props.dart';
import '../input/player_intent.dart';
import 'checkpoint_service.dart';
import 'terrain.dart';

/// Builds the level from the terrain profile in [GameConfig] and owns
/// nothing else.
///
/// Level layout is its own concern, kept out of both the game class and the
/// entities. The layout itself is data — a few control points per hill — so
/// a second level is a second list, not a second copy of this file.
///
/// The level, in metres, with y pointing down and the camera showing 9 m:
///
/// ```
///   0            14 15.4        30 31.4         50 51.4          64
///   |   shore     |  |   mist    |  |   forest    |  |   descent   |
///   ____/‾‾‾‾‾‾‾‾‾   ‾‾\____/‾‾‾‾   ‾‾‾\___/‾‾‾‾‾‾‾   ‾‾\____/‾‾‾‾‾‾
///                 ^pit           ^pit            ^pit
/// ```
class Level extends Component {
  Level({required this._intent, required this.checkpoints})
    : terrain = Terrain([
        for (final flat in GameConfig.terrainProfile)
          [
            for (var i = 0; i + 1 < flat.length; i += 2)
              Vector2(flat[i], flat[i + 1]),
          ],
      ]);

  final PlayerIntent _intent;

  /// Exposed so the game can hand it to anything else that needs to kill or
  /// save the player later.
  final CheckpointService checkpoints;

  /// The ground's curve. The backdrop reads it too, for the far hills.
  final Terrain terrain;

  /// Available as soon as the level loads, before its children mount.
  late final Player player;

  static const List<double> _checkpointXs = [17, 33, 49, 65, 81];
  int _nextCheckpoint = 0;

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted) return;
    if (player.cameraPosition.y > GameConfig.levelHeight + 3 ||
        player.cameraPosition.x < -1 ||
        player.cameraPosition.x > GameConfig.levelWidth + 1) {
      checkpoints.respawn(player);
    }
    while (_nextCheckpoint < _checkpointXs.length &&
        player.body.position.x >= _checkpointXs[_nextCheckpoint]) {
      final double x = _checkpointXs[_nextCheckpoint++];
      final double y = terrain.heightAt(x) ?? GameConfig.floorSurfaceY;
      checkpoints.setCheckpoint(Vector2(x, y - GameConfig.playerHeight / 2));
    }
  }

  @override
  Future<void> onLoad() async {
    final List<Component> pieces = [];

    // --- The ground: one hill per stretch of the profile ---------------------
    for (final segment in terrain.segments) {
      pieces.add(HillGround(segment: segment, pitDepth: GameConfig.pitDepth));
    }

    // --- Pits: the gaps between stretches, spiked ------------------------------
    for (var i = 0; i + 1 < terrain.segments.length; i++) {
      final TerrainSegment a = terrain.segments[i];
      final TerrainSegment b = terrain.segments[i + 1];
      if (b.left <= a.right) {
        continue; // touching: no pit
      }
      // The pit floor sits a fixed depth below the *lower* of the two lips,
      // where both hills' chain walls end.
      final double lip = a.surface.last.y > b.surface.first.y
          ? a.surface.last.y
          : b.surface.first.y;
      pieces.add(
        Hazard.zone(
          left: a.right,
          right: b.left,
          top: lip + GameConfig.pitDepth,
          bottom: GameConfig.levelHeight,
          checkpoints: checkpoints,
        ),
      );
    }

    // --- Logs lying on the hill, to hop over ------------------------------------
    for (final span in GameConfig.logs) {
      final double left = span[0];
      final double right = span[1];
      final double ground =
          terrain.heightAt((left + right) / 2) ?? GameConfig.floorSurfaceY;
      pieces.add(
        Ground.slab(
          left: left,
          right: right,
          top: ground - GameConfig.ledgeThickness,
          thickness: GameConfig.ledgeThickness,
          style: GroundStyle.log,
        ),
      );
    }

    // Interactions are placed along the existing six areas, using the same
    // monochrome materials and real bodies as the terrain.
    for (final crate in const [
      (6.0, 0.75, 0.72, 8.0, 0.25),
      (10.0, 0.90, 0.68, 35.0, 0.15),
    ]) {
      final (x, width, height, mass, friction) = crate;
      pieces.add(
        PhysicsCrate(
          position: Vector2(x, terrain.heightAt(x)! - height / 2 - 0.025),
          size: Vector2(width, height),
          massKg: mass,
          friction: friction,
        ),
      );
    }
    pieces.addAll([
      MovingPlatform(
        from: Vector2(24, 5.9),
        to: Vector2(27, 5.9),
        size: Vector2(1.6, 0.22),
        speed: 0.65,
      ),
      MovingPlatform(
        from: Vector2(42, 5.5),
        to: Vector2(42, 4.3),
        size: Vector2(1.5, 0.22),
        speed: 0.5,
      ),
      SwingRope(anchor: Vector2(29, 1.4), length: 3.3),
      Ground.slab(
        left: 73,
        right: 74.4,
        top: 5.5,
        thickness: 1.8,
        style: GroundStyle.log,
      ),
    ]);

    // --- Walls, so the player cannot walk out of the level --------------------
    pieces.add(
      Ground.slab(
        left: -GameConfig.wallThickness,
        right: 0,
        top: -GameConfig.levelHeight,
        thickness: GameConfig.levelHeight * 2,
        style: GroundStyle.wall,
      ),
    );
    pieces.add(
      Ground.slab(
        left: GameConfig.levelWidth,
        right: GameConfig.levelWidth + GameConfig.wallThickness,
        top: -GameConfig.levelHeight,
        thickness: GameConfig.levelHeight * 2,
        style: GroundStyle.wall,
      ),
    );

    // --- The player, last so it draws on top of the ground --------------------
    player = Player(
      intent: _intent,
      spawnPosition: checkpoints.activeCheckpoint,
    );
    pieces.add(player);

    await addAll(pieces);
  }
}
