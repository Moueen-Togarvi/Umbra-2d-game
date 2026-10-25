import 'package:flame/components.dart';
import '../config/game_config.dart';
import '../render/mood.dart';
import '../render/chapter_backgrounds.dart';
import 'chapter.dart';
import 'campaign_catalog.dart';
import 'puzzle_route.dart';

/// Authored routes between the original story's major events.
class JourneyChapter extends Chapter {
  JourneyChapter({required super.intent, required this.number});
  @override
  final int number;
  @override
  String get title => CampaignCatalog.titles[number - 1];
  static const routes = <int, List<PuzzleKind>>{
    // Each of the first chapters its own handful: one easy to begin, a
    // few to think about, and one to remember at the end (docs/puzzles.md).
    2: [
      PuzzleKind.weight,
      PuzzleKind.rope,
      PuzzleKind.spikes,
      PuzzleKind.barrel,
      PuzzleKind.seesaw,
    ],
    3: [
      PuzzleKind.traps,
      PuzzleKind.zipline,
      PuzzleKind.logBridge,
      PuzzleKind.bridge,
      PuzzleKind.wolves,
    ],
    4: [
      PuzzleKind.patrol,
      PuzzleKind.coffin,
      PuzzleKind.crows,
      PuzzleKind.pullCrate,
      PuzzleKind.chase,
    ],
    7: [
      PuzzleKind.cageLift,
      PuzzleKind.drawbridge,
      PuzzleKind.hammer,
      PuzzleKind.levers,
      PuzzleKind.twoRopes,
    ],
    9: [
      PuzzleKind.drain,
      PuzzleKind.sluice,
      PuzzleKind.logFloat,
      PuzzleKind.crawl,
      PuzzleKind.floodTrap,
    ],
    10: [
      PuzzleKind.floatCrate,
      PuzzleKind.sinkingRaft,
      PuzzleKind.rockfall,
      PuzzleKind.collapse,
      PuzzleKind.zipline,
    ],
    12: [
      PuzzleKind.coffin,
      PuzzleKind.patrol,
      PuzzleKind.sleeper,
      PuzzleKind.heavyLight,
      PuzzleKind.raft,
    ],
    14: [
      PuzzleKind.drain,
      PuzzleKind.raft,
      PuzzleKind.moonWindow,
      PuzzleKind.ropeClimb,
      PuzzleKind.floodRise,
    ],
    15: [
      PuzzleKind.weight,
      PuzzleKind.lift,
      PuzzleKind.bookcase,
      PuzzleKind.fireJets,
      PuzzleKind.crate,
    ],
    17: [
      PuzzleKind.plateGate,
      PuzzleKind.pullCrate,
      PuzzleKind.fallingStairs,
      PuzzleKind.bell,
      PuzzleKind.chandelier,
    ],
    19: [
      PuzzleKind.lantern,
      PuzzleKind.watchEye,
      PuzzleKind.moonWindow,
      PuzzleKind.coffinHands,
      PuzzleKind.pendulum,
    ],
    21: [
      PuzzleKind.levers,
      PuzzleKind.twoRopes,
      PuzzleKind.tripwire,
      PuzzleKind.twoPlates,
      PuzzleKind.bellGate,
    ],
    23: [
      PuzzleKind.bell,
      PuzzleKind.plateGate,
      PuzzleKind.fireJets,
      PuzzleKind.seesaw,
      PuzzleKind.fireChase,
    ],
    24: [
      PuzzleKind.watchEye,
      PuzzleKind.tripwire,
      PuzzleKind.fallingFloor,
      PuzzleKind.leapRope,
      PuzzleKind.oil,
    ],
    26: [
      PuzzleKind.sleeper,
      PuzzleKind.heavyLight,
      PuzzleKind.lantern,
      PuzzleKind.crows,
      PuzzleKind.coffinHands,
    ],
    27: [
      PuzzleKind.sluice,
      PuzzleKind.logFloat,
      PuzzleKind.stalactites,
      PuzzleKind.fallingStairs,
      PuzzleKind.collapse,
    ],
    29: [
      PuzzleKind.logBridge,
      PuzzleKind.ropeClimb,
      PuzzleKind.boulder,
      PuzzleKind.leapRope,
      PuzzleKind.boulderChase,
    ],
    30: [
      PuzzleKind.floatCrate,
      PuzzleKind.sinkingRaft,
      PuzzleKind.raft,
      PuzzleKind.bats,
      PuzzleKind.floodRise,
    ],
    31: [
      PuzzleKind.oil,
      PuzzleKind.lantern,
      PuzzleKind.burningRope,
      PuzzleKind.fallingFloor,
      PuzzleKind.fireChase,
    ],
    32: [
      PuzzleKind.boulderChase,
      PuzzleKind.barrelRun,
      PuzzleKind.crate,
      PuzzleKind.spikes,
      PuzzleKind.tripwire,
    ],
    34: [
      PuzzleKind.ropeClimb,
      PuzzleKind.movingPlatform,
      PuzzleKind.barrel,
      PuzzleKind.weight,
    ],
    // The last of the way home: what he has learnt, met once more and
    // harder (docs/puzzles.md).
    36: [
      PuzzleKind.movingPlatform,
      PuzzleKind.bog,
      PuzzleKind.twoCrates,
      PuzzleKind.returnLoop,
      PuzzleKind.wolves,
    ],
    37: [
      PuzzleKind.patrol,
      PuzzleKind.timedDoor,
      PuzzleKind.returnLoop,
      PuzzleKind.watchEye,
      PuzzleKind.bellGate,
    ],
    38: [
      PuzzleKind.fireflies,
      PuzzleKind.spikes,
      PuzzleKind.cages,
      PuzzleKind.traps,
      PuzzleKind.ropeClimb,
    ],
    39: [
      PuzzleKind.barrel,
      PuzzleKind.seesaw,
      PuzzleKind.movingPlatform,
      PuzzleKind.twoCrates,
      PuzzleKind.crusher,
    ],
  };

  /// Preserve early-room staging; cap the late campaign's empty walks.
  double roomLength(PuzzleKind kind) {
    if (number == 37 && kind == PuzzleKind.patrol) return 60;
    final base = number <= 5
        ? 36.0
        : number <= 10
        ? 42.0
        : number <= 20
        ? 48.0
        : 48.0;
    final setPiece = switch (kind) {
      PuzzleKind.returnLoop => 52.0,
      PuzzleKind.lantern ||
      PuzzleKind.weight ||
      PuzzleKind.cageLift ||
      PuzzleKind.floodRise => 44.0,
      PuzzleKind.chase ||
      PuzzleKind.collapse ||
      PuzzleKind.fireChase ||
      PuzzleKind.boulderChase ||
      PuzzleKind.rockfall => 42.0,
      _ => 0.0,
    };
    return base > setPiece ? base : setPiece;
  }

  /// Ground rhythm changes by arc. The first room remains at the common spawn;
  /// later rooms climb, dip and return through short connecting slopes.
  double floorOf(int i) {
    if (i == 0) return 7;
    if (routes[number]![i] == PuzzleKind.returnLoop) return 7;
    const patterns = <List<double>>[
      [7, 6.4, 7.1, 6.6, 7.0],
      [7, 7.5, 6.8, 7.3, 6.6],
      [7, 6.2, 6.8, 7.4, 6.7],
      [7, 7.6, 6.9, 6.3, 7.2],
    ];
    final pattern = patterns[((number - 1) ~/ 10).clamp(0, 3).toInt()];
    return pattern[i % pattern.length];
  }

  static const _alternateRooms = <(int, int)>{
    (14, 3),
    (17, 0),
    (21, 3),
    (23, 1),
    (29, 1),
    (34, 1),
    (36, 0),
    (38, 4),
  };
  static const _quietRooms = <(int, int)>{
    (4, 1),
    (12, 2),
    (19, 2),
    (30, 2),
    (38, 2),
  };

  List<PuzzleRoom> _buildRooms() {
    final result = <PuzzleRoom>[];
    double x = 4;
    for (final (i, kind) in routes[number]!.indexed) {
      final length = roomLength(kind);
      result.add(
        PuzzleRoom(
          kind,
          x,
          floor: floorOf(i),
          length: length,
          withWatcher: number == 37,
          variant: (number + i) % 3,
          alternateRoute: _alternateRooms.contains((number, i)),
          quietFinish: _quietRooms.contains((number, i)),
        ),
      );
      x += length;
    }
    return result;
  }

  late final rooms = _buildRooms();
  late final route = PuzzleRoute(this, rooms);
  @override
  double get width => rooms.last.end + 4;
  @override
  double get exitX => width - 3;
  @override
  Vector2 get spawn => Vector2(2, 7 - GameConfig.playerHeight / 2);
  @override
  List<double> get checkpointXs => [
    for (final (i, room) in rooms.indexed)
      if (i.isEven) room.x + 2,
  ];
  @override
  String get footing => number < 6 || number > 33 ? 'grass' : 'stone';
  @override
  // Out in the open: no wind bed, only the rain at the end.
  String? get ambience => grassy
      ? (number < 35 ? null : 'rain')
      : number < 16
      ? 'cave'
      : 'dungeon';
  @override
  MoodTrack get moods => MoodTrack(grassy ? Mood.night : Mood.cave);
  @override
  ChapterBackground get backgroundPlan => ChapterBackground(number, [
    for (var i = 0; i < 4; i++)
      BackgroundArea(i * width / 4, '$title ${i + 1}'),
  ]);
  @override
  List<List<double>> get profile {
    // One bank after another, broken only at the rooms' gaps; between two
    // rooms on different ground, a slope over the first three metres of
    // the second (the first may have a low roof at its end); and a room's
    // own hill where it has one.
    final result = <List<double>>[];
    var bank = <double>[0, rooms.first.floor];
    void point(double x, double y) {
      // Never two points at one x: the ground there would have no length.
      if ((bank[bank.length - 2] - x).abs() < 1e-6) return;
      bank.addAll([x, y]);
    }

    for (var i = 0; i < rooms.length; i++) {
      final room = rooms[i];
      if (i > 0 && rooms[i - 1].floor != room.floor) {
        point(room.x, rooms[i - 1].floor);
        point(room.x + 3, room.floor);
      }
      for (final (at, up) in room.rise) {
        point(room.x + at, room.floor - up);
      }
      final gap = room.gap;
      if (gap == null) continue;
      point(gap.$1, room.floor);
      result.add(bank);
      bank = [gap.$2, room.floor];
    }
    point(width, rooms.last.floor);
    result.add(bank);
    return result;
  }

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    final room = rooms.firstWhere(
      (r) => r.gap != null && (r.gap!.$1 - left).abs() < .05,
    );
    final pit = room.pit(this);
    return pit.isNotEmpty ? pit : super.buildPit(index, left, right, lip);
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    for (final room in rooms) {
      room.furnish(this, pieces);
    }
    pieces.add(route);
  }

  @override
  void onRespawned() => route.restoreAt(checkpoints.activeCheckpoint.x);

  @override
  void resetCurrentPuzzle() {
    intent.clear();
    final safe = route.resetCurrent(player.body.position.x);
    player.teleportTo(safe);
  }
}
