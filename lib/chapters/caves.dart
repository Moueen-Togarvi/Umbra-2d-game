import 'dart:ui' show Color;

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/cave_props.dart';
import '../entities/ground.dart';
import '../entities/physics_props.dart';
import '../entities/water_props.dart';
import '../physics/water.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/creatures.dart';
import 'chapter.dart';

/// Chapter four, The Caves.
///
/// Out of the cage tunnel and down into the caves, where water runs under
/// the vampires' land. He cannot swim. A pool too wide to jump: the crate
/// on the bank floats, and the slow draw of the water carries it, and him
/// on it, across. A shallow ford to wade. An underground river that comes
/// out of the rock and runs fast to a sinkhole: logs come down it, one at
/// a time; he rides one and must leap for the high bank before the hole
/// takes it. Last, a dry cistern with its only way out far above: a crank
/// in the floor opens the sluice, the water comes in, and the crate he
/// stands on rises with it to the exit.
///
/// ```
///  0  20.6 crate  22.5–28.5 pool  52.5–61.5 ford  70–92 the river
///  113 cistern edge  116–126 the cistern (crank at 121.8)  196 out
/// ```
class CavesChapter extends Chapter {
  CavesChapter({required super.intent});

  @override
  int get number => 4;
  @override
  String get title => 'The Caves';
  @override
  double get width => 200;
  @override
  MoodTrack get moods => const MoodTrack(Mood.cave);

  static const double poolLeft = 22.5, poolRight = 28.5;
  static const double riverLeft = 70, riverRight = 92;
  static const double cisternLeft = 116, cisternRight = 126;
  static const double exitTop = 4.6;
  static const double cisternFloor = 9.45;

  @override
  List<List<double>> get profile => const [
    [0, 7.0, 6, 7.0, 12, 7.1, 18, 6.9, poolLeft, 7.0],
    [
      poolRight, 7.0, 32, 6.95, 38, 7.05, 44, 6.9, 48, 6.8, 52, 6.75, //
      53.6, 7.25, 55, 7.6, 59, 7.6, 60.4, 7.2, 62, 6.8, 66, 6.75, //
      riverLeft, 6.6,
    ],
    // Down a steep ramp under the rock into the cistern.
    [
      riverRight, 5.6, 98, 5.7, 104, 6.2, 108, 6.8, 112, 7.0, 113.4, 7.15, //
      115.0, 9.0, cisternLeft, cisternFloor,
    ],
    [
      cisternRight, exitTop, 132, 4.7, 140, 5.4, 150, 6.4, 160, 7.0, //
      170, 7.0, 180, 6.9, 190, 7.0, 200, 7.0,
    ],
  ];

  @override
  List<double> get checkpointXs => const [12, 29.5, 64, 96, 112, 129, 165];

  @override
  Vector2 get spawn => Vector2(3, 7.0 - GameConfig.playerHeight / 2);

  @override
  double get exitX => 196;

  @override
  List<String> get art => const [
    'part2/ch4_river_arch.png',
    'part2/ch4_hanging_roots.png',
    'part2/ch4_fungi.png',
    'part2/ch4_rock_column_far.png',
    'part2/ch4_rock_column.png',
    'part2/ch4_sluice.png',
    'part1/ch3_stalagmites_far.png',
  ];

  late final PhysicsCrate crate;
  late final PhysicsCrate lift;
  late final WaterBody pool, river, cistern;

  /// The shallow ford he wades through.
  late final WaterBody ford = WaterBody(
    left: 53.3,
    right: 60.7,
    surface: 7.0,
    bottom: 7.62,
    player: player,
  );
  late final LogSource logs;
  late final FootPedal crank;
  late final SlidingGate gate;
  double _floodIn = -1;
  double _stir = 0;

  @override
  void update(double dt) {
    super.update(dt);
    if (_floodIn > 0) {
      _floodIn -= dt;
      if (_floodIn <= 0) cistern.floodTo(exitTop + 0.05, speed: 0.22);
    }
    // Water pouring in through the sluice by the gate pushes what floats
    // over to the far wall, where the way out is, and stirs a while after.
    if (!cistern.isSettled) {
      _stir = 6;
    } else if (_stir > 0) {
      _stir -= dt;
    }
    cistern.current = _stir > 0 && cistern.level < cisternFloor - 0.05
        ? 0.35
        : 0;
  }

  /// Back from a death: what he was in the middle of is as it was.
  @override
  void onRespawned() {
    final double x = checkpoints.activeCheckpoint.x;
    if (x < poolRight) crate.resetToStart();
    if (x < cisternRight && x > riverRight) {
      _floodIn = -1;
      cistern.setLevel(cisternFloor - 0.01);
      gate.shut = false;
      crank.reset();
      lift.resetToStart();
    }
  }

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    switch (index) {
      case 0:
        final parts = waterPit(
          left,
          right,
          surface: 7.45,
          floor: 10.4,
          current: 0.35,
        );
        pool = parts.whereType<WaterBody>().single;
        return parts;
      case 1:
        final parts = waterPit(
          left,
          right,
          surface: 7.2,
          floor: 10.8,
          current: 1.3,
        );
        river = parts.whereType<WaterBody>().single;
        return parts;
      case 2:
        // Dry, until the sluice is opened.
        final parts = waterPit(
          left,
          right,
          surface: cisternFloor - 0.01,
          floor: cisternFloor,
        );
        cistern = parts.whereType<WaterBody>().single;
        return parts;
    }
    return super.buildPit(index, left, right, lip);
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    double g(double x) => groundAt(x);

    // --- The cave: roof and its columns ---------------------------------
    pieces.addAll([
      RockMass([
        Vector2(-3, -4),
        Vector2(66, -4),
        Vector2(66, 0.4),
        Vector2(58, 0.9),
        Vector2(50, 0.2),
        Vector2(42, 1.0),
        Vector2(34, 0.4),
        Vector2(26, 1.2),
        Vector2(18, 0.5),
        Vector2(10, 1.1),
        Vector2(3, 0.6),
        Vector2(-3, 1.4),
      ], seed: 11),
      RockMass([
        Vector2(66, -4),
        Vector2(130, -4),
        Vector2(130, -0.3),
        Vector2(122, 0.3),
        Vector2(112, 0.6),
        Vector2(100, 0.1),
        Vector2(92, 1.4),
        Vector2(84, 2.1),
        Vector2(76, 1.6),
        Vector2(66, 0.4),
      ], seed: 12),
      RockMass([
        Vector2(130, -4),
        Vector2(203, -4),
        Vector2(203, 1.0),
        Vector2(192, 0.6),
        Vector2(180, 1.3),
        Vector2(166, 0.7),
        Vector2(150, 1.2),
        Vector2(140, 0.6),
        Vector2(130, -0.3),
      ], seed: 13),
    ]);
    for (final (x, h, depth) in const [
      (9.0, 9.0, 0.6),
      (40.0, 10.0, 0.5),
      (101.0, 9.0, 0.55),
      (145.0, 10.0, 0.5),
      (176.0, 9.0, 0.6),
    ]) {
      pieces.add(
        SceneryProp(
          'part2/ch4_rock_column.png',
          x: x,
          baseY: 7.8,
          height: h,
          depth: depth,
        ),
      );
    }
    pieces.addAll([
      SceneryProp(
        'part2/ch4_hanging_roots.png',
        x: 31,
        baseY: 3.6,
        height: 3.2,
        depth: 0.9,
        fog: 0.12,
        priority: -40,
      ),
      SceneryProp(
        'part2/ch4_hanging_roots.png',
        x: 134,
        baseY: 3.0,
        height: 2.8,
        depth: 0.9,
        fog: 0.12,
        flip: true,
        priority: -40,
      ),
      SceneryProp(
        'part2/ch4_fungi.png',
        x: 15.5,
        baseY: g(15.5) + 0.1,
        height: 0.9,
        depth: 0.95,
        fog: 0.12,
        priority: -20,
      ),
      SceneryProp(
        'part2/ch4_fungi.png',
        x: 47,
        baseY: g(47) + 0.1,
        height: 0.75,
        depth: 0.95,
        fog: 0.12,
        flip: true,
        priority: -20,
      ),
      SceneryProp(
        'part2/ch4_fungi.png',
        x: 163,
        baseY: g(163) + 0.1,
        height: 1.0,
        depth: 0.95,
        fog: 0.12,
        priority: -20,
      ),
      // The river runs under a low arch of rock.
      SceneryProp(
        'part2/ch4_river_arch.png',
        x: 81,
        baseY: 8.2,
        height: 6.2,
        depth: 0.82,
      ),
      SceneryProp(
        'part2/ch4_sluice.png',
        x: 127.6,
        baseY: 9.3,
        height: 2.6,
        depth: 0.93,
        fog: 0.13,
        priority: -20,
      ),
      WatchingEyes(
        x: 56,
        y: 5.6,
        depth: 0.55,
        color: const Color(0xFFC21E1E),
        shyDistance: 0,
        seed: 21,
      ),
      BatFlock(roost: Vector2(84, 2.6), player: player, count: 12, seed: 23),
    ]);

    // --- The pool, the river, the cistern --------------------------------
    crate = PhysicsCrate(
      // A wide flat crate: wide, so it stays level when he lands on it.
      position: Vector2(19.6, g(19.6) - 0.45 - 0.02),
      size: Vector2(3.0, 0.9),
      massKg: 36,
      friction: 0.45,
    );
    logs = LogSource(
      at: Vector2(riverLeft + 1.8, 6.75),
      sink: riverRight - 1.6,
      every: 6,
      firstAfter: 1.0,
    );
    // A wide, low crate: with him on it, it still floats a hand high.
    lift = PhysicsCrate(
      position: Vector2(124.3, cisternFloor - 0.36),
      size: Vector2(2.2, 0.7),
      massKg: 6,
      friction: 0.7,
    );
    gate = SlidingGate(x: 115.85, openTop: 6.0, shutTop: cisternFloor - 1.75);
    crank = FootPedal(
      hinge: Vector2(122.1, cisternFloor - 0.07),
      length: 1.2,
      massKg: 20,
      hertz: 2.2,
      onPress: () {
        // The gate drops behind him; a moment later the water comes in.
        gate.shut = true;
        _floodIn = 2.2;
      },
    );
    pieces.addAll([
      ford,
      crate,
      ...logs.logs,
      logs,
      lift,
      gate,
      crank,
      // The rock over the way in, with the gate's slot through it; its
      // underside follows the ramp with room for him below.
      RockMass(
        [
          Vector2(113.2, -4),
          Vector2(cisternLeft, -4),
          Vector2(cisternLeft, cisternFloor - 1.75),
          Vector2(115.6, cisternFloor - 1.75),
          Vector2(115.0, 7.3),
          Vector2(113.6, 5.3),
        ],
        drips: false,
        seed: 14,
      ),
      Ground.restingLog(
        left: 160.4,
        right: 162.0,
        diameter: 0.5,
        groundBelow: groundAt,
      ),
    ]);
  }
}
