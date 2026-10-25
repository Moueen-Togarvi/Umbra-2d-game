import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart'
    show BodyComponent, BodyType, QueryFilter;
import '../physics/collision_layers.dart';

import '../config/game_config.dart';
import 'campaign_catalog.dart';
import 'puzzle_route.dart';
import '../entities/ground.dart';
import '../entities/hazard.dart';
import '../entities/hill_ground.dart';
import '../entities/player.dart';
import '../input/player_intent.dart';
import '../physics/water.dart';
import '../render/dust.dart';
import '../render/chapter_backgrounds.dart';
import '../render/grass.dart';
import '../render/near_layer.dart';
import '../render/white_blossom_tree.dart';
import 'decor_layout.dart';
import '../render/chapter_exit_gate.dart';
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
  @override
  bool get touchControlsUsed => intent.touchUsed;

  /// Its place in the story, from 1, and its name on the card.
  int get number;
  String get id => CampaignCatalog.ids[number - 1];
  @override
  ChapterBackground get backgroundPlan {
    final plan = ChapterBackgrounds.forChapter(number);
    return ChapterBackground(number, [
      for (var i = 0; i < 4; i++)
        BackgroundArea(i * width / 4, plan.areas[i].name),
    ]);
  }

  String get title;

  /// Each bank as flat x, y pairs, left to right.
  List<List<double>> get baseProfile => const [];
  double get coreWidth => 0;
  double get coreExitX => coreWidth - 4;
  List<double> get coreCheckpointXs => const [];
  static const extensionPlans = <int, List<PuzzleKind>>{
    1: [PuzzleKind.bats, PuzzleKind.crawl, PuzzleKind.plateGate],
    5: [PuzzleKind.fireflies, PuzzleKind.bridge, PuzzleKind.bog],
    6: [PuzzleKind.cages, PuzzleKind.ropeClimb],
    8: [PuzzleKind.stalactites, PuzzleKind.raft],
    11: [PuzzleKind.crusher, PuzzleKind.coffinHands, PuzzleKind.twoCrates],
    13: [PuzzleKind.fallingFloor, PuzzleKind.boulder, PuzzleKind.barrelRun],
    16: [PuzzleKind.fallingStairs, PuzzleKind.timedDoor],
    18: [PuzzleKind.moonWindow, PuzzleKind.patrol, PuzzleKind.fireChase],
    20: [PuzzleKind.chandelier, PuzzleKind.pendulum, PuzzleKind.cages],
    22: [PuzzleKind.hammer, PuzzleKind.crusher],
    25: [PuzzleKind.cages, PuzzleKind.crawl],
    28: [PuzzleKind.movingPlatform, PuzzleKind.drain],
    33: [PuzzleKind.drawbridge, PuzzleKind.cageLift],
    35: [PuzzleKind.rockfall, PuzzleKind.collapse],
    40: [PuzzleKind.chase, PuzzleKind.logBridge],
  };
  double get extensionRoomLength => number <= 5
      ? 36
      : number <= 10
      ? 42
      : number <= 20
      ? 48
      : 54;
  double get extensionLength => extensionPlans.containsKey(number)
      ? extensionPlans[number]!.length * extensionRoomLength + 18
      : 0;
  @override
  double get width => coreWidth + extensionLength;
  late final List<PuzzleRoom> extensionRooms = [
    for (var i = 0; i < (extensionPlans[number]?.length ?? 0); i++)
      PuzzleRoom(
        extensionPlans[number]![i],
        coreWidth + i * extensionRoomLength,
        floor: baseProfile.last.last,
        length: extensionRoomLength,
      ),
  ];
  late final PuzzleRoute extensionRoute = PuzzleRoute(this, extensionRooms);

  List<List<double>> get profile {
    final result = [for (final bank in baseProfile) List<double>.of(bank)];
    if (extensionRooms.isEmpty) return result;
    final floor = baseProfile.last.last;
    var from = result.last[result.last.length - 2];
    void point(double x, double y) {
      // Never two points at one x, nor going back.
      if (x <= result.last[result.last.length - 2] + 1e-6) return;
      result.last.addAll([x, y]);
    }

    for (final room in extensionRooms) {
      // The room's own hill or hollow, where it has one.
      for (final (at, up) in room.rise) {
        point(room.x + at, floor - up);
      }
      final gap = room.gap;
      if (gap == null) continue;
      point(gap.$1, floor);
      result.add([gap.$2, floor]);
      from = gap.$2;
    }
    if (width > from) result.last.addAll([width, floor]);
    return result;
  }

  /// Where the boy comes back after a death, as he passes each.
  List<double> get checkpointXs => [
    ...coreCheckpointXs,
    for (final room in extensionRooms) room.x + 2,
  ];

  /// Where he starts.
  Vector2 get spawn;

  /// Crossing this x ends the chapter.
  double get exitX => coreExitX + extensionLength;

  /// Where the gate out stands, the last thing he walks through; none
  /// where the chapter ends in a scene of its own instead of a way out.
  double? get exitGateX => exitX < width ? exitX - 1.0 : null;

  /// Source artwork roster for auditing. Live components load their own art;
  /// paintings replaced by the atlas must not enter the decoded image cache.
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

  /// A checkpoint rests on permanent geometry, including galleries above
  /// the terrain profile. Never resume inside a staircase or on a moving crate.
  Vector2 checkpointPosition(double x) {
    final ground = groundAt(x);
    var surface = ground;
    if (player.isMounted) {
      var best = 2.0;
      player.body.world.castRay(Vector2(x, ground - 4), Vector2(0, 8), (hit) {
        if (hit.shape.isSensor ||
            hit.shape.body.type != BodyType.static ||
            hit.normal.y > -.5) {
          return -1;
        }
        if (hit.fraction < best) {
          best = hit.fraction;
          surface = hit.point.y;
        }
        return hit.fraction;
      }, filter: QueryFilter(maskBits: CollisionLayers.solid));
    }
    return Vector2(x, surface - GameConfig.playerHeight / 2);
  }

  /// Three story-wide blossom landmarks, spaced across safe ground, out in
  /// the open (never in a cave or a castle hall).
  /// If a nominal position lands over a pit it moves to the nearest bank.
  List<double> get blossomTreeXs => [
    if (grassy)
      for (final fraction in const [.22, .50, .78])
        _nearestSurfaceX(width * fraction),
  ];

  double _nearestSurfaceX(double target) {
    if (terrain.segmentAt(target) != null) return target;
    var best = terrain.segments.first.left;
    var distance = double.infinity;
    for (final segment in terrain.segments) {
      final inset = ((segment.right - segment.left) * .08).clamp(.35, 1.2);
      final candidate = target.clamp(
        segment.left + inset,
        segment.right - inset,
      );
      final d = (candidate - target).abs();
      if (d < distance) {
        best = candidate;
        distance = d;
      }
    }
    return best;
  }

  /// What fills the gap after bank [index], from [left] to [right] below
  /// the lower lip at [lip]: stakes, unless a chapter fills it otherwise
  /// (with water, say).
  List<Component> buildPit(int index, double left, double right, double lip) =>
      [
        Hazard.zone(
          left: left,
          right: right,
          top: lip + GameConfig.pitDepth,
          bottom: height,
        ),
      ];

  /// A pit full of water: a rock floor at [floor] and the water over it up
  /// to [surface].
  List<Component> waterPit(
    double left,
    double right, {
    required double surface,
    required double floor,
    double current = 0,
  }) => [
    Ground.slab(
      left: left - 0.1,
      right: right + 0.1,
      top: floor,
      thickness: height + 2 - floor,
    ),
    WaterBody(
      left: left,
      right: right,
      surface: surface,
      bottom: floor,
      current: current,
      player: player,
    ),
  ];

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
  void Function(String id)? onCheckpoint;
  String? _pendingRestore;
  void resumeAt(String checkpointId) => _pendingRestore = checkpointId;
  void restartCheckpoint() {
    cutscene?.stop();
    cutscene = null;
    intent.endScript();
    cameraFocus = null;
    extensionRoute.restoreAt(checkpoints.activeCheckpoint.x);
    onRespawned();
    player.teleportTo(checkpoints.activeCheckpoint);
  }

  /// A quick recovery action for a stuck puzzle. Bespoke chapters use their
  /// authored checkpoint restore; reusable-room chapters narrow this further.
  void resetCurrentPuzzle() => restartCheckpoint();

  /// Reconstitute puzzle outcomes before placing the player at a safe boundary.
  void restoreWorld(double x) {}

  bool _restorePending() {
    final id = _pendingRestore;
    if (id == null || !player.isMounted) return false;
    _pendingRestore = null;
    final index = int.tryParse(id.replaceFirst('checkpoint-', ''));
    if (index == null || index < 0 || index >= checkpointXs.length) {
      return false;
    }
    final x = checkpointXs[index];
    cutscene?.stop();
    cutscene = null;
    intent.endScript();
    cameraFocus = null;
    _triggers.removeWhere((t) => t.$1 <= x);
    _nextCheckpoint = index + 1;
    checkpoints.setCheckpoint(checkpointPosition(x));
    restoreWorld(x);
    extensionRoute.restoreAt(x);
    player.teleportTo(checkpoints.activeCheckpoint);
    onRespawned();
    return true;
  }

  @override
  Future<void> onLoad() async {
    final List<Component> pieces = [];
    // First, since the water in the pits watches him.
    player = Player(
      intent: intent,
      spawnPosition: checkpoints.activeCheckpoint,
    );
    banks = [
      for (var i = 0; i < terrain.segments.length; i++)
        HillGround(
          segment: terrain.segments[i],
          pitDepth: GameConfig.pitDepth,
          wind: wind,
          pitOnLeft: i > 0,
          pitOnRight: i < terrain.segments.length - 1,
          bottom: height + 1,
          bare: !grassy,
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
      final extension = extensionRooms
          .where((r) => r.gap != null && (r.gap!.$1 - a.right).abs() < .05)
          .firstOrNull;
      if (extension == null) {
        pieces.addAll(buildPit(i, a.right, b.left, lip));
      } else {
        final pit = extension.pit(this);
        pieces.addAll(
          pit.isNotEmpty
              ? pit
              : [
                  Hazard.zone(
                    left: a.right,
                    right: b.left,
                    top: lip + GameConfig.pitDepth,
                    bottom: height,
                  ),
                ],
        );
      }
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

    await furnish(pieces);
    for (final room in extensionRooms) {
      room.furnish(this, pieces);
    }
    if (extensionRooms.isNotEmpty) pieces.add(extensionRoute);
    for (var i = 0; i < blossomTreeXs.length; i++) {
      final x = blossomTreeXs[i];
      pieces.add(
        WhiteBlossomTree(
          kind: i == 1
              ? WhiteBlossomTreeKind.weeping
              : WhiteBlossomTreeKind.windSwept,
          at: Vector2(x, groundAt(x) + .08),
          height: i == 1 ? 5.0 : (i == 0 ? 4.7 : 4.4),
          seed: number * 101 + i * 37,
          flip: i == 2,
        ),
      );
    }
    final double? gateX = exitGateX;
    if (gateX != null) {
      pieces.add(
        ChapterExitGate(
          design: ChapterExitGate.designFor[id] ?? 'ch04',
          x: gateX,
          groundAt: groundAt,
        ),
      );
    }
    pieces
      ..add(player)
      ..add(DustField(player: player))
      ..add(
        NearLayer(
          kind: grassy
              ? NearKind.branches
              : footing == 'gravel'
              ? NearKind.roots
              : NearKind.chains,
          width: width,
          seed: number,
        ),
      );
    if (grassy) pieces.add(FrontGrass(banks: banks, wind: wind));
    await addAll(pieces);
  }

  /// The trees and standing props are settled on clear ground once all of
  /// the chapter, its rooms' pieces too, is in the world.
  bool _decorPending = true;
  int _framesSeen = 0;

  void _arrangeDecorWhenLoaded() {
    if (!_decorPending || ++_framesSeen < 2) return;
    final all = descendants().toList();
    final bool ready = all.whereType<BodyComponent>().every((b) => b.isLoaded);
    if (!ready && _framesSeen < 30) return;
    _decorPending = false;
    arrangeSurfaceDecor(this, all);
  }

  @override
  void onMount() {
    super.onMount();
    begin();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _arrangeDecorWhenLoaded();
    wind.update(dt);
    if (_restorePending()) return;
    final Cutscene? scene = cutscene;
    if (scene != null && scene.update(dt)) cutscene = null;
    if (!player.isMounted) return;
    wind.pusherX = player.isDead ? double.nan : player.cameraPosition.x;
    wind.pusherSpeed = player.velocity.x;
    final Vector2 at = player.cameraPosition;
    if (at.y > height + 3 || at.x < -1 || at.x > width + 1) {
      player.die(cause: DeathCause.fall);
    }
    if (_wasDead && !player.isDead) {
      extensionRoute.restoreAt(checkpoints.activeCheckpoint.x);
      onRespawned();
    }
    _wasDead = player.isDead;
    if (player.isDead) return;
    final double x = player.body.position.x;
    while (_nextCheckpoint < checkpointXs.length &&
        x >= checkpointXs[_nextCheckpoint] &&
        player.isOnGround &&
        !intent.isScripted) {
      final double cx = checkpointXs[_nextCheckpoint++];
      checkpoints.setCheckpoint(checkpointPosition(cx));
      onCheckpoint?.call('checkpoint-${_nextCheckpoint - 1}');
      // A soft breath as the place takes note; not at the very start.
      if (cx > spawn.x + 3) cue('checkpoint', weight: 0.7);
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
