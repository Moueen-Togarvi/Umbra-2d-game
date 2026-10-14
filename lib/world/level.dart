import 'package:flame/components.dart' show Component;
import 'package:flame/game.dart' show Vector2;

import '../config/game_config.dart';
import '../entities/ground.dart';
import '../entities/hazard.dart';
import '../entities/hill_ground.dart';
import '../entities/player.dart';
import '../entities/physics_props.dart';
import '../input/player_intent.dart';
import '../render/dust.dart';
import '../render/grass.dart';
import 'checkpoint_service.dart';
import 'terrain.dart';

/// Builds the level from the terrain profile in [GameConfig] and owns
/// nothing else.
///
/// Level layout is its own concern, kept out of both the game class and the
/// entities. The layout itself is data — a few control points per hill — so
/// a second level is a second list, not a second copy of this file.
///
/// The level, in metres, with y pointing down and the camera showing 10.5 m:
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

  /// The ground's curve.
  final Terrain terrain;

  /// Wind for every blade of grass, and the boy's legs pushing through it.
  final GrassWind wind = GrassWind();

  /// Available as soon as the level loads, before its children mount.
  late final Player player;

  static const List<double> _checkpointXs = [17, 33, 49, 65, 81];
  int _nextCheckpoint = 0;

  @override
  void update(double dt) {
    super.update(dt);
    wind.update(dt);
    if (!player.isMounted) return;
    wind.pusherX = player.isDead ? double.nan : player.cameraPosition.x;
    wind.pusherSpeed = player.velocity.x;
    // Out of the world is a death like any other; the death sequence brings
    // him back.
    if (player.cameraPosition.y > GameConfig.levelHeight + 3 ||
        player.cameraPosition.x < -1 ||
        player.cameraPosition.x > GameConfig.levelWidth + 1) {
      player.die();
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

    // --- The ground: one bank per stretch of the profile -------------------
    final banks = <HillGround>[
      for (var i = 0; i < terrain.segments.length; i++)
        HillGround(
          segment: terrain.segments[i],
          pitDepth: GameConfig.pitDepth,
          wind: wind,
          pitOnLeft: i > 0,
          pitOnRight: i < terrain.segments.length - 1,
        ),
    ];
    pieces.addAll(banks);

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
        from: Vector2(24, 6.15),
        to: Vector2(27, 6.15),
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
      // A bank too tall to jump onto: it has to be caught and climbed.
      Ground.slab(left: 73, right: 74.4, top: 5.5, thickness: 1.8, wind: wind),
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

    // Dirt and grass kicked up by his landings and slides.
    pieces.add(DustField(player: player));

    // The short grass in front of his feet draws over everything else.
    pieces.add(FrontGrass(banks: banks, wind: wind));

    await addAll(pieces);
  }
}
