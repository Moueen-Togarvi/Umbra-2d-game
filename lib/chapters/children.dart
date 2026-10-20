import 'dart:ui' show Canvas, Color, Offset, Paint, Path, Rect;

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/castle_props.dart';
import '../entities/dungeon_props.dart';
import '../entities/physics_props.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/children.dart';
import '../story/cutscene.dart';
import '../story/hunters.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter eleven, The Children.
///
/// Down in the dungeons under the tower, the other stolen children. A cord
/// by each cell lifts its bars, and the child inside follows him. In the
/// corridor one of them keeps watch under an oil lamp; dropped on the
/// stone, the lamp's oil catches and runs burning along the floor, and
/// the watcher, driven before it to the corridor's end, burns. In a low
/// passage a chest is too heavy for him alone, not for him and two
/// others: out of the passage, he can climb over it. At the end, a drain too small for him: the children go out
/// through it, one after another, into the night.
///
/// ```
///  0  13.5 cell A  21 lamp cord  31 the lamp  20–39.5 the watcher
///  42 cell B  49–62 low passage and its chest  68 cell C
///  88 the drain  104 out
/// ```
class ChildrenChapter extends Chapter {
  ChildrenChapter({required super.intent});

  @override
  void restoreWorld(double x) {
    for (var i = 0; i < cells.length; i++) {
      if (cells[i].left < x) {
        cells[i].open();
        kids[i].following = true;
        kids[i].feet.setValues(x - kids[i].back, floor);
      }
    }
    if (x >= corridorEnd) watcher.gone = true;
    if (x >= drainX) {
      _escaped = true;
      for (final kid in kids) {
        kid.gone = true;
      }
    }
  }

  @override
  String? get ambience => 'dungeon';
  @override
  int get number => 25;
  @override
  String get title => 'The Children';
  @override
  double get coreWidth => 110;
  @override
  MoodTrack get moods => const MoodTrack(Mood.castle);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.hallSpecs;
  @override
  bool get grassy => false;

  static const double floor = 7.0;
  static const double lampX = 31, corridorEnd = 39.5;
  static const double passageLeft = 49, passageRight = 62;
  static const double drainX = 88;

  @override
  List<List<double>> get baseProfile => const [
    [0, floor, 110, floor],
  ];

  @override
  List<double> get coreCheckpointXs => const [10, 19, 41, 47, 66, 80];

  @override
  Vector2 get spawn => Vector2(3, floor - GameConfig.playerHeight / 2);

  @override
  double get coreExitX => 104;

  @override
  List<String> get art => const [
    'part4/ch11_hanging_cages.png',
    'part4/ch11_hanging_cages_far.png',
    'part4/ch11_prison_cells.png',
    'part4/ch11_prison_cells_far.png',
    'part3/ch8_banners.png',
  ];

  final List<CellFront> cells = [];
  final List<Child> kids = [];
  final List<PullCord> cellCords = [];
  late final Following following;
  late final OilLamp lamp;
  late final PullCord lampCord;
  late final PhysicsCrate chest;
  final Vampire watcher = Vampire(x: 33, groundY: floor, facing: -1);
  late final Stalker watch;
  bool _escaped = false;

  @override
  Future<void> furnish(List<Component> pieces) async {
    pieces.add(LightLayer());
    // --- Stone: the vault, the low passage, the steps out ------------------
    pieces.addAll([
      StoneBlock(left: -3, top: -8, right: 113, bottom: 1.5, seed: 81),
      StoneBlock(
        left: passageLeft,
        top: 1.5,
        right: passageRight,
        bottom: floor - 1.4,
        seed: 82,
      ),
      StoneBlock(
        left: 96,
        top: 5.8,
        right: 113,
        bottom: floor + 0.05,
        seed: 83,
      ),
      StoneBlock(left: 100, top: 4.6, right: 113, bottom: 5.9, seed: 84),
    ]);

    // --- Art ---------------------------------------------------------------
    pieces.addAll([
      for (final x in const [10.0, 52.0, 92.0])
        SceneryProp(
          'part4/ch11_prison_cells.png',
          x: x,
          baseY: 7.6,
          height: 4.5,
          depth: 0.6,
        ),
      for (final x in const [24.0, 78.0])
        SceneryProp(
          'part4/ch11_hanging_cages.png',
          x: x,
          baseY: 4.2,
          height: 2.8,
          depth: 0.85,
          fog: 0.12,
          priority: -36,
        ),
      _Drain(x: drainX, floorY: floor),
    ]);

    // --- The cells, their cords, the children in them -----------------------
    for (final (int i, double left, double cord) in const [
      (0, 13.5, 17.0),
      (1, 42.0, 45.4),
      (2, 68.0, 71.4),
    ]) {
      final cell = CellFront(left: left, right: left + 2, floorY: floor);
      cells.add(cell);
      kids.add(Child(home: left + 1, groundY: floor, index: i));
      cellCords.add(
        PullCord(
          anchor: Vector2(cord, floor - 4.5),
          length: 3.6,
          onPulled: cell.open,
        ),
      );
    }
    following = Following(kids);
    pieces
      ..addAll(cells)
      ..addAll(kids)
      ..addAll(cellCords)
      ..add(following);

    // --- The watcher and the lamp ----------------------------------------
    lamp = OilLamp(
      anchor: Vector2(lampX, 1.5),
      chain: 1.0,
      floorY: floor,
      spreadTo: corridorEnd + 0.1,
    );
    lampCord = PullCord(
      anchor: Vector2(21, floor - 4.5),
      length: 3.6,
      onPulled: lamp.drop,
    );
    watch = Stalker(
      watcher,
      stage: this,
      ground: (_) => floor,
      left: 20,
      right: corridorEnd,
      wake: 5.5,
      patrolA: 28,
      patrolB: 37,
    );
    pieces.addAll([lamp, lampCord, watcher]);

    // --- The chest in the low passage ---------------------------------------
    chest = PhysicsCrate(
      position: Vector2(passageLeft + 2.2, floor - 0.5),
      size: Vector2(1, 1),
      massKg: 90,
      friction: 0.4,
    );
    pieces.add(chest);
  }

  @override
  void begin() {
    onReach(drainX - 4, () => play(_escape()));
  }

  /// At the drain: the children out through it, one after another.
  Cutscene _escape() => Cutscene([
    Do((_) {
      for (var i = 0; i < kids.length; i++) {
        if (!kids[i].following) continue;
        following.goals[kids[i]] = Vector2(drainX - 0.6 + i * 0.05, floor);
      }
    }),
    Look(Vector2(drainX - 1.5, 5.6)),
    Do((_) => player.forceLookBack = false),
    Wait(0.6),
    for (var i = 0; i < 3; i++) ...[
      WaitUntil(
        (_) =>
            !kids[i].following || (kids[i].feet.x - (drainX - 0.6)).abs() < 0.1,
        timeout: 6,
      ),
      Do((_) {
        if (kids[i].following) {
          following.goals[kids[i]] = Vector2(drainX + 0.6, floor);
        }
      }),
      Wait(0.8),
      Do((_) => kids[i].gone = kids[i].following || kids[i].gone),
    ],
    Do((_) => _escaped = true),
    Wait(0.6),
    Look(null),
  ]);

  /// Whether the children got away.
  bool get escaped => _escaped;

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted) return;
    for (var i = 0; i < cells.length; i++) {
      if (cells[i].isOpen && !kids[i].following && !kids[i].gone) {
        kids[i].following = true;
      }
    }
    watch.update(dt);
  }

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (at < corridorEnd) {
      lamp.rehang();
      lampCord.reset();
      watch.reset(33);
    }
    if (at < passageLeft) chest.resetToStart();
    following.trail.clear();
    for (var i = 0; i < kids.length; i++) {
      final kid = kids[i];
      final cell = cells[i];
      if (cell.left > at) {
        // Not yet freed when he passed this checkpoint.
        cell.shut();
        cellCords[i].reset();
        kid.reset();
      } else if (kid.following) {
        // Back beside him.
        kid.feet.setValues(at - kid.back, floor);
      }
    }
  }
}

/// A low arched drain in the foot of the wall, a grating long since gone:
/// big enough for a small child, not for him.
class _Drain extends Component {
  _Drain({required this.x, required this.floorY}) : super(priority: -20);
  final double x, floorY;

  static final Paint _stone = Paint()..color = const Color(0xFF070707);
  static final Paint _hole = Paint()..color = const Color(0xFF000000);
  static final Paint _rim = Paint()..color = const Color(0x22D8D0C0);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTRB(x - 1.2, floorY - 1.4, x + 1.2, floorY),
      _stone,
    );
    final arch = Path()
      ..moveTo(x - 0.42, floorY)
      ..lineTo(x - 0.42, floorY - 0.5)
      ..quadraticBezierTo(x, floorY - 0.95, x + 0.42, floorY - 0.5)
      ..lineTo(x + 0.42, floorY)
      ..close();
    canvas.drawPath(arch, _hole);
    canvas.drawLine(
      Offset(x - 0.45, floorY - 0.5),
      Offset(x - 0.45, floorY),
      _rim..strokeWidth = 0.02,
    );
  }
}
