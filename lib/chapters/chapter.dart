import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show QueryFilter, BodyType;
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
import '../render/white_blossom_tree.dart';
import 'decor_layout.dart';
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
    1: [PuzzleKind.crawl, PuzzleKind.crate],
    5: [PuzzleKind.rope, PuzzleKind.crawl],
    6: [PuzzleKind.crawl, PuzzleKind.patrol],
    8: [PuzzleKind.drain, PuzzleKind.raft],
    11: [PuzzleKind.crawl, PuzzleKind.raft, PuzzleKind.patrol],
    13: [PuzzleKind.drain, PuzzleKind.rope, PuzzleKind.raft],
    16: [PuzzleKind.weight, PuzzleKind.crawl, PuzzleKind.rope],
    18: [PuzzleKind.lantern, PuzzleKind.patrol, PuzzleKind.weight],
    20: [PuzzleKind.rope, PuzzleKind.cages, PuzzleKind.pendulum],
    22: [
      PuzzleKind.pendulum,
      PuzzleKind.weight,
      PuzzleKind.hammer,
      PuzzleKind.rope,
    ],
    25: [
      PuzzleKind.crawl,
      PuzzleKind.patrol,
      PuzzleKind.drain,
      PuzzleKind.weight,
    ],
    28: [PuzzleKind.drain, PuzzleKind.raft, PuzzleKind.weight, PuzzleKind.raft],
    33: [
      PuzzleKind.returnLoop,
      PuzzleKind.patrol,
      PuzzleKind.rope,
      PuzzleKind.crawl,
      PuzzleKind.raft,
    ],
    35: [
      PuzzleKind.rope,
      PuzzleKind.returnLoop,
      PuzzleKind.pendulum,
      PuzzleKind.crawl,
      PuzzleKind.rope,
    ],
    40: [
      PuzzleKind.crate,
      PuzzleKind.rope,
      PuzzleKind.crawl,
      PuzzleKind.raft,
      PuzzleKind.returnLoop,
    ],
  };
  double get extensionRoomLength => number <= 10
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
    for (final room in extensionRooms) {
      final gap = room.gap;
      if (gap == null) continue;
      result.last.addAll([gap.$1, floor]);
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

  /// Source artwork roster for auditing. Live components load their own art;
  /// paintings replaced by the atlas must not enter the decoded image cache.
  List<String> get art => const [];

  /// Whether grass grows on its ground (not on a castle's stone floors).
  bool get grassy => true;

  /// Indoors (no grass), his feet fall on stone and the wind is far off.
  @override
  String get footing => grassy ? 'grass' : 'stone';
  @override
  double get windLevel => grassy ? 1 : 0.25;

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

  /// Three story-wide blossom landmarks, spaced across safe ground.
  /// If a nominal position lands over a pit it moves to the nearest bank.
  List<double> get blossomTreeXs => [
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
          .where((r) => r.gap?.$1 == a.right)
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
    pieces
      ..add(player)
      ..add(DustField(player: player));
    if (grassy) pieces.add(FrontGrass(banks: banks, wind: wind));
    await addAll(pieces);
    arrangeSurfaceDecor(this, pieces);
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
    if (_restorePending()) return;
    final Cutscene? scene = cutscene;
    if (scene != null && scene.update(dt)) cutscene = null;
    if (!player.isMounted) return;
    wind.pusherX = player.isDead ? double.nan : player.cameraPosition.x;
    wind.pusherSpeed = player.velocity.x;
    final Vector2 at = player.cameraPosition;
    if (at.y > height + 3 || at.x < -1 || at.x > width + 1) player.die();
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
