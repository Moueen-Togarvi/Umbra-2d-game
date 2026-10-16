import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import '../config/game_config.dart';
import '../entities/ground.dart';
import '../entities/hazard.dart';
import '../entities/hill_ground.dart';
import '../entities/player.dart';
import '../input/player_intent.dart';
import '../render/dust.dart';
import '../render/grass.dart';
import '../story/cutscene.dart';
import '../world/checkpoint_service.dart';
import '../world/stage.dart';
import '../world/terrain.dart';

/// One chapter of the story: a stretch of land with its own air, its
/// set pieces and its scripted moments, from where he comes in to where
/// he leaves.
///
/// The ground is data, the same as the proving ground's: a few control
/// points per bank, with a pit wherever two banks do not touch. A
/// subclass describes the chapter ([profile], [checkpointXs], [exitX]…)
/// and furnishes it in [furnish]; this class builds the banks, pits and
/// walls, puts the boy in, saves his progress at the checkpoints and
/// notices when he reaches the end.
abstract class Chapter extends Stage {
  Chapter({required this.intent});

  final PlayerIntent intent;

  /// Its place in the story, from 1, and its name on the card.
  int get number;
  String get title;

  /// Each bank as flat x, y pairs, left to right.
  List<List<double>> get profile;

  /// Where the boy comes back after a death, as he passes each.
  List<double> get checkpointXs;

  /// Where he starts.
  Vector2 get spawn;

  /// Crossing this x ends the chapter.
  double get exitX;

  /// Every image the chapter draws, loaded before it builds.
  List<String> get art => const [];

  @override
  double get height => GameConfig.levelHeight;
  @override
  double get cameraMaxY => GameConfig.cameraMaxY;

  late final Terrain terrain = Terrain([
    for (final flat in profile)
      [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Vector2(flat[i], flat[i + 1]),
      ],
  ]);

  final GrassWind wind = GrassWind();
  late final List<HillGround> banks;

  @override
  late final CheckpointService checkpoints = CheckpointService(
    initialCheckpoint: spawn,
  );

  @override
  late final Player player;

  int _nextCheckpoint = 0;
  bool _complete = false;
  @override
  bool get isComplete => _complete;

  /// The scene running now, if any.
  Cutscene? cutscene;

  @override
  bool get controlsHidden => cutscene != null;

  final List<(double, void Function())> _triggers = [];

  /// Calls [action] once, the first time the boy passes [x].
  void onReach(double x, void Function() action) => _triggers.add((x, action));

  /// The far hills follow the land: the ground here, averaged over a wide
  /// stretch so a pit or a bump does not move them.
  @override
  double Function(double cameraX)? get backdropGround => (x) {
    double sum = 0;
    for (var i = -6; i <= 6; i++) {
      sum +=
          (terrain.heightAt(x + i * 2.0) ??
          terrain.heightAt(x + i * 2.0 + 3) ??
          7.0);
    }
    return sum / 13;
  };

  /// Ends the chapter now, whatever x he is at (a scene can end it).
  void complete() => _complete = true;

  /// Starts [scene], replacing any running.
  void play(Cutscene scene) {
    cutscene?.stop();
    cutscene = scene..start(this);
  }

  /// The ground as drawn at [x], or the collision surface over a pit.
  double groundAt(double x) {
    for (final bank in banks) {
      if (x >= bank.segment.left && x <= bank.segment.right) {
        return bank.drawnHeightAt(x);
      }
    }
    return terrain.heightAt(x) ?? GameConfig.floorSurfaceY;
  }

  /// Puts the chapter's set pieces into [pieces]: scenery, things to
  /// push and climb, NPCs, triggers and cutscenes.
  Future<void> furnish(List<Component> pieces);

  /// Called once the chapter is built and in the world.
  void begin() {}

  /// Called when the story reaches this chapter (after its card, or from
  /// the title): the place for an opening scene.
  void startStory() {}

  /// Called when he comes back at a checkpoint after a death.
  void onRespawned() {}
  bool _wasDead = false;

  @override
  Future<void> onLoad() async {
    for (final name in art) {
      try {
        await Flame.images.load(name);
      } catch (_) {
        // A bare test binding has no assets; the scenery leaves itself out.
      }
    }
    final List<Component> pieces = [];
    banks = [
      for (var i = 0; i < terrain.segments.length; i++)
        HillGround(
          segment: terrain.segments[i],
          pitDepth: GameConfig.pitDepth,
          wind: wind,
          pitOnLeft: i > 0,
          pitOnRight: i < terrain.segments.length - 1,
          bottom: height + 1,
        ),
    ];
    pieces.addAll(banks);

    for (var i = 0; i + 1 < terrain.segments.length; i++) {
      final TerrainSegment a = terrain.segments[i];
      final TerrainSegment b = terrain.segments[i + 1];
      if (b.left <= a.right) continue;
      final double lip = a.surface.last.y > b.surface.first.y
          ? a.surface.last.y
          : b.surface.first.y;
      pieces.add(
        Hazard.zone(
          left: a.right,
          right: b.left,
          top: lip + GameConfig.pitDepth,
          bottom: height,
        ),
      );
    }

    // Walls at both ends; the exit is a little short of the right one.
    for (final (left, right) in [
      (-GameConfig.wallThickness, 0.0),
      (width, width + GameConfig.wallThickness),
    ]) {
      pieces.add(
        Ground.slab(
          left: left,
          right: right,
          top: -height,
          thickness: height * 2,
          style: GroundStyle.wall,
        ),
      );
    }

    player = Player(
      intent: intent,
      spawnPosition: checkpoints.activeCheckpoint,
    );
    await furnish(pieces);
    pieces
      ..add(player)
      ..add(DustField(player: player))
      ..add(FrontGrass(banks: banks, wind: wind));
    await addAll(pieces);
  }

  @override
  void onMount() {
    super.onMount();
    begin();
  }

  @override
  void update(double dt) {
    super.update(dt);
    wind.update(dt);
    final Cutscene? scene = cutscene;
    if (scene != null && scene.update(dt)) cutscene = null;
    if (!player.isMounted) return;
    wind.pusherX = player.isDead ? double.nan : player.cameraPosition.x;
    wind.pusherSpeed = player.velocity.x;
    final Vector2 at = player.cameraPosition;
    if (at.y > height + 3 || at.x < -1 || at.x > width + 1) player.die();
    if (_wasDead && !player.isDead) onRespawned();
    _wasDead = player.isDead;
    if (player.isDead) return;
    final double x = player.body.position.x;
    while (_nextCheckpoint < checkpointXs.length &&
        x >= checkpointXs[_nextCheckpoint]) {
      final double cx = checkpointXs[_nextCheckpoint++];
      checkpoints.setCheckpoint(
        Vector2(cx, groundAt(cx) - GameConfig.playerHeight / 2),
      );
    }
    for (var i = 0; i < _triggers.length; i++) {
      final (tx, action) = _triggers[i];
      if (x >= tx) {
        _triggers.removeAt(i--);
        action();
      }
    }
    if (!_complete && x >= exitX) _complete = true;
  }
}
