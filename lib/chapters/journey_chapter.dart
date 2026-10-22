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
    2: [PuzzleKind.crawl, PuzzleKind.seesaw, PuzzleKind.rope, PuzzleKind.crate],
    3: [PuzzleKind.crate, PuzzleKind.rope, PuzzleKind.weight, PuzzleKind.crate],
    4: [
      PuzzleKind.crawl,
      PuzzleKind.patrol,
      PuzzleKind.crate,
      PuzzleKind.patrol,
    ],
    7: [PuzzleKind.cages, PuzzleKind.weight, PuzzleKind.cages, PuzzleKind.rope],
    9: [PuzzleKind.drain, PuzzleKind.raft, PuzzleKind.crawl, PuzzleKind.drain],
    10: [PuzzleKind.raft, PuzzleKind.rope, PuzzleKind.drain, PuzzleKind.raft],
    12: [
      PuzzleKind.coffin,
      PuzzleKind.patrol,
      PuzzleKind.raft,
      PuzzleKind.crawl,
      PuzzleKind.patrol,
    ],
    14: [
      PuzzleKind.drain,
      PuzzleKind.weight,
      PuzzleKind.raft,
      PuzzleKind.drain,
      PuzzleKind.rope,
    ],
    15: [
      PuzzleKind.weight,
      PuzzleKind.lift,
      PuzzleKind.crate,
      PuzzleKind.crawl,
      PuzzleKind.weight,
    ],
    17: [
      PuzzleKind.crawl,
      PuzzleKind.patrol,
      PuzzleKind.weight,
      PuzzleKind.crawl,
      PuzzleKind.patrol,
    ],
    19: [
      PuzzleKind.lantern,
      PuzzleKind.patrol,
      PuzzleKind.rope,
      PuzzleKind.lantern,
      PuzzleKind.weight,
    ],
    21: [
      PuzzleKind.lift,
      PuzzleKind.cages,
      PuzzleKind.pendulum,
      PuzzleKind.rope,
      PuzzleKind.weight,
      PuzzleKind.crawl,
    ],
    23: [
      PuzzleKind.hammer,
      PuzzleKind.crate,
      PuzzleKind.lift,
      PuzzleKind.pendulum,
      PuzzleKind.hammer,
      PuzzleKind.rope,
    ],
    24: [
      PuzzleKind.lantern,
      PuzzleKind.patrol,
      PuzzleKind.crawl,
      PuzzleKind.patrol,
      PuzzleKind.lantern,
      PuzzleKind.rope,
    ],
    26: [
      PuzzleKind.weight,
      PuzzleKind.crawl,
      PuzzleKind.patrol,
      PuzzleKind.crate,
      PuzzleKind.patrol,
      PuzzleKind.drain,
    ],
    27: [
      PuzzleKind.drain,
      PuzzleKind.raft,
      PuzzleKind.crawl,
      PuzzleKind.drain,
      PuzzleKind.rope,
      PuzzleKind.raft,
    ],
    29: [
      PuzzleKind.rope,
      PuzzleKind.drain,
      PuzzleKind.raft,
      PuzzleKind.weight,
      PuzzleKind.raft,
      PuzzleKind.pendulum,
    ],
    30: [
      PuzzleKind.floodTrap,
      PuzzleKind.lantern,
      PuzzleKind.drain,
      PuzzleKind.returnLoop,
      PuzzleKind.drain,
      PuzzleKind.raft,
    ],
    31: [
      PuzzleKind.oil,
      PuzzleKind.patrol,
      PuzzleKind.weight,
      PuzzleKind.crawl,
      PuzzleKind.oil,
      PuzzleKind.lantern,
      PuzzleKind.rope,
    ],
    32: [
      PuzzleKind.returnLoop,
      PuzzleKind.pendulum,
      PuzzleKind.patrol,
      PuzzleKind.rope,
      PuzzleKind.lantern,
      PuzzleKind.cages,
      PuzzleKind.weight,
    ],
    34: [
      PuzzleKind.rope,
      PuzzleKind.raft,
      PuzzleKind.drain,
      PuzzleKind.weight,
      PuzzleKind.raft,
      PuzzleKind.crawl,
      PuzzleKind.rope,
    ],
    36: [
      PuzzleKind.rope,
      PuzzleKind.pendulum,
      PuzzleKind.returnLoop,
      PuzzleKind.rope,
      PuzzleKind.crawl,
      PuzzleKind.patrol,
      PuzzleKind.rope,
    ],
    37: [
      PuzzleKind.patrol,
      PuzzleKind.crawl,
      PuzzleKind.lantern,
      PuzzleKind.returnLoop,
      PuzzleKind.patrol,
      PuzzleKind.rope,
      PuzzleKind.lantern,
      PuzzleKind.patrol,
    ],
    38: [
      PuzzleKind.rope,
      PuzzleKind.patrol,
      PuzzleKind.crawl,
      PuzzleKind.returnLoop,
      PuzzleKind.rope,
      PuzzleKind.patrol,
      PuzzleKind.crawl,
    ],
    39: [
      PuzzleKind.crate,
      PuzzleKind.rope,
      PuzzleKind.crawl,
      PuzzleKind.returnLoop,
      PuzzleKind.raft,
      PuzzleKind.crate,
      PuzzleKind.rope,
    ],
  };
  double get roomLength => number <= 10
      ? 42
      : number <= 20
      ? 48
      : number <= 30
      ? 54
      : 60;
  late final rooms = [
    for (var i = 0; i < routes[number]!.length; i++)
      PuzzleRoom(
        routes[number]![i],
        4 + i * roomLength,
        length: roomLength,
        withWatcher: number == 37,
      ),
  ];
  late final route = PuzzleRoute(this, rooms);
  @override
  double get width => 8 + routes[number]!.length * roomLength;
  @override
  double get exitX => width - 3;
  @override
  Vector2 get spawn => Vector2(2, 7 - GameConfig.playerHeight / 2);
  @override
  List<double> get checkpointXs => [for (final r in rooms) r.x + 2];
  @override
  bool get grassy => number < 6 || number > 33;
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
    final result = <List<double>>[];
    var from = 0.0;
    for (final room in rooms) {
      final gap = room.gap;
      if (gap == null) continue;
      result.add([from, 7, gap.$1, 7]);
      from = gap.$2;
    }
    result.add([from, 7, width, 7]);
    return result;
  }

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    final room = rooms.firstWhere((r) => r.gap?.$1 == left);
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
}
