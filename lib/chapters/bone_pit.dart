import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/cave_props.dart';
import '../entities/ground.dart';
import '../entities/water_props.dart';
import '../physics/water.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/creatures.dart';
import '../story/cutscene.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter six, The Bone Pit.
///
/// The castle's cistern, where the bones end up. A black pool with old
/// barrels floating in it, the only footing, rolling under him. A flooded
/// chamber whose only way on is a tunnel under its far wall: he lets the
/// water out, and walks through the bones it leaves. Then the shaft: as
/// he reaches its foot a figure at the top opens the sluices, and the
/// water comes up after him while he climbs from ledge to ledge.
///
/// ```
///  0  25–38 the barrels  52.6 drain  54–78 the chamber, tunnel to 92
///  92.4–101 the shaft  146 out
/// ```
class BonePitChapter extends Chapter {
  BonePitChapter({required super.intent});

  @override
  String? get ambience => 'dungeon';
  @override
  int get number => 6;
  @override
  String get title => 'The Bone Pit';
  @override
  double get width => 150;
  @override
  MoodTrack get moods => const MoodTrack(Mood.cave);

  static const double barrelsLeft = 25, barrelsRight = 38.0;
  static const double chamberLeft = 54, chamberRight = 78;
  static const double floor = 9.6;
  static const double shaftLeft = 92.4, shaftRight = 101;
  static const double exitTop = 2.4;

  @override
  List<List<double>> get profile => const [
    [0, 6.0, 6, 6.0, 9, 6.5, 12, 7.0, 18, 7.0, 22, 7.0, barrelsLeft, 7.0],
    [barrelsRight, 7.0, 44, 7.0, 50, 6.9, chamberLeft, 7.0],
    [
      chamberRight,
      floor,
      84,
      floor,
      90,
      floor,
      shaftLeft,
      floor,
      shaftRight,
      floor,
    ],
    [
      shaftRight, exitTop, 108, exitTop, 116, 2.8, 126, 3.6, 136, 4.4, //
      146, 5.0, 150, 5.0,
    ],
  ];

  @override
  List<double> get checkpointXs => const [14, 39.5, 80, 104];

  @override
  Vector2 get spawn => Vector2(3, 6.0 - GameConfig.playerHeight / 2);

  @override
  double get exitX => 146;

  @override
  List<String> get art => const [
    'part2/ch6_bone_heap.png',
    'part2/ch6_bone_heap_far.png',
    'part2/ch6_beast_ribs.png',
    'part2/ch6_beast_ribs_far.png',
    'part2/ch6_chained_skeleton.png',
    'part2/ch6_cistern_pipes.png',
    'part1/ch3_hanging_chains.png',
  ];

  late final WaterBody pool, chamber, shaft;
  late final FootPedal drain;
  final List<Barrel> barrels = [];
  final Vampire keeper = Vampire(x: 104, groundY: exitTop, facing: -1);
  bool _flooding = false;

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    switch (index) {
      case 0:
        final parts = waterPit(left, right, surface: 7.35, floor: 10.2);
        pool = parts.whereType<WaterBody>().single;
        return parts;
      case 1:
        // The chamber's water reaches on under the rock into the tunnel.
        chamber = WaterBody(
          left: left,
          right: 88,
          surface: 7.15,
          bottom: floor,
          player: player,
        );
        return [
          Ground.slab(
            left: left - 0.1,
            right: right + 0.1,
            top: floor,
            thickness: height + 2 - floor,
          ),
          chamber,
        ];
      case 2:
        // Not a gap: the shaft's own floor runs on from the tunnel.
        return [];
    }
    return super.buildPit(index, left, right, lip);
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    double g(double x) => groundAt(x);

    // --- Rock: the roof, the tunnel, the shaft and its ledges -------------
    pieces.addAll([
      RockMass([
        Vector2(-3, -4),
        Vector2(78, -4),
        Vector2(78, 2.0),
        Vector2(70, 1.2),
        Vector2(60, 2.2),
        Vector2(46, 1.0),
        Vector2(34, 1.8),
        Vector2(20, 0.8),
        Vector2(8, 1.4),
        Vector2(-3, 0.6),
      ], seed: 51),
      // Over the tunnel and the shaft's left wall: worn, never lower than
      // 1.4 m over the tunnel floor, never back from the ledge it holds.
      RockMass(
        [
          Vector2(78, -4),
          Vector2(shaftLeft, -4),
          ..._worn(
            Vector2(shaftLeft, -0.8),
            Vector2(shaftLeft, floor - 1.5),
            Vector2(1, 0),
            0.28,
            1,
          ),
          Vector2(shaftLeft, floor - 1.5),
          ..._worn(
            Vector2(shaftLeft, floor - 1.5),
            Vector2(78, floor - 1.5),
            Vector2(0, -1),
            0.12,
            2,
            inward: 0.1,
          ),
          Vector2(78, floor - 1.5),
          ..._worn(
            Vector2(78, floor - 1.5),
            Vector2(78, 2.4),
            Vector2(-1, 0),
            0.3,
            3,
            inward: 0.25,
          ),
          Vector2(78, 2.0),
        ],
        drips: false,
        seed: 52,
      ),
      // The shaft's right wall below the last ledge, worn the same way.
      RockMass(
        [
          Vector2(shaftRight, 4.6),
          Vector2(shaftRight + 0.8, 4.6),
          Vector2(shaftRight + 0.8, floor),
          Vector2(shaftRight, floor),
          ..._worn(
            Vector2(shaftRight, floor),
            Vector2(shaftRight, 4.6),
            Vector2(-1, 0),
            0.26,
            4,
          ),
        ],
        drips: false,
        seed: 54,
      ),
      // The roof over the way out, high above the shaft.
      RockMass([
        Vector2(shaftLeft, -4),
        Vector2(153, -4),
        Vector2(153, -0.4),
        Vector2(130, 0.2),
        Vector2(110, -0.6),
        Vector2(shaftLeft, -0.8),
      ], seed: 53),
      // Ledges up the shaft, side to side, each 1.8 m above the last.
      for (final (l, r, top) in const [
        (96.4, shaftRight, 7.8),
        (shaftLeft, 97.0, 6.0),
        (96.4, shaftRight, 4.2),
      ])
        RockMass(
          [
            Vector2(l, top),
            Vector2(r, top),
            Vector2(r, top + 0.4),
            Vector2(l, top + 0.4),
          ],
          drips: true,
          seed: (l * 10).round(),
        ),
    ]);
    shaft = WaterBody(
      left: shaftLeft,
      right: shaftRight,
      surface: floor - 0.02,
      bottom: floor,
      player: player,
    );

    // --- Bones, ribs, chains ----------------------------------------------
    pieces.addAll([
      for (final (x, h, depth) in const [
        (20.0, 9.0, 0.55),
        (66.0, 8.0, 0.5),
        (124.0, 9.0, 0.55),
      ])
        SceneryProp(
          'part2/ch6_beast_ribs.png',
          x: x,
          baseY: 7.6,
          height: h,
          depth: depth,
        ),
      for (final (x, h) in const [
        (10.0, 1.6),
        (46.0, 1.4),
        (84.0, 1.2),
        (118.0, 1.6),
      ])
        SceneryProp(
          'part2/ch6_bone_heap.png',
          x: x,
          baseY: g(x) + 0.2,
          height: h,
          depth: 0.94,
          fog: 0.13,
          priority: -25,
        ),
      SceneryProp(
        'part2/ch6_chained_skeleton.png',
        x: 31,
        baseY: 4.8,
        height: 3.2,
        depth: 0.88,
        fog: 0.12,
        priority: -40,
      ),
      SceneryProp(
        'part2/ch6_chained_skeleton.png',
        x: 132,
        baseY: 3.0,
        height: 2.8,
        depth: 0.88,
        fog: 0.12,
        flip: true,
        priority: -40,
      ),
      SceneryProp(
        'part2/ch6_cistern_pipes.png',
        x: 60,
        baseY: 9.8,
        height: 4.2,
        depth: 0.9,
        fog: 0.12,
        priority: -40,
      ),
      SceneryProp(
        'part1/ch3_hanging_chains.png',
        x: 97,
        baseY: 1.2,
        height: 3.0,
        depth: 0.86,
        fog: 0.12,
        priority: -40,
      ),
      WatchingEyes(
        x: 40,
        y: 3.4,
        depth: 0.6,
        color: const Color(0xFFC21E1E),
        shyDistance: 0,
        seed: 61,
      ),
      BatFlock(roost: Vector2(112, 0.6), player: player, count: 12, seed: 63),
    ]);

    // --- The barrels, the drain, the shaft --------------------------------
    // Big casks: long enough to stand on near an end without tipping off.
    for (final x in const [26.8, 29.8, 32.8, 35.8]) {
      barrels.add(Barrel(at: Vector2(x, 7.1), length: 2.4, massKg: 20));
    }
    drain = FootPedal(
      hinge: Vector2(52.6, g(52.6) - 0.07),
      length: 1.3,
      onPress: () => chamber.floodTo(floor - 0.35, speed: 0.5),
    );
    pieces.addAll([
      ...barrels,
      drain,
      shaft,
      keeper..gone = true,
      Ground.restingLog(
        left: 120.4,
        right: 122.0,
        diameter: 0.5,
        groundBelow: groundAt,
      ),
    ]);
  }

  /// Points between [a] and [b] pushed out along [out] by up to [amp]
  /// (and back by up to [inward]), about every 0.7 m: a worn rock face.
  static List<Vector2> _worn(
    Vector2 a,
    Vector2 b,
    Vector2 out,
    double amp,
    int seed, {
    double inward = 0,
  }) {
    final random = math.Random(seed * 97 + 5);
    final double len = a.distanceTo(b);
    final int n = math.max(1, (len / 0.7).round());
    return [
      for (var i = 1; i < n; i++)
        a +
            (b - a) * ((i + (random.nextDouble() - 0.5) * 0.5) / n) +
            out * (random.nextDouble() * (amp + inward) - inward),
    ];
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted || player.isDead) return;
    if (!_flooding && player.body.position.x > shaftLeft + 0.6) {
      _flooding = true;
      play(_sluices());
    }
  }

  /// At the shaft's foot: a figure at the top, the sluices, the water.
  Cutscene _sluices() => Cutscene([
    Do((_) {
      keeper
        ..gone = false
        ..x = 103.2
        ..groundY = exitTop
        ..facing = -1
        ..eyes = 1
        ..mode = VampireMode.stand;
    }),
    Look(Vector2(98.5, 5.0)),
    Do((_) => player.forceLookUp = true),
    Wait(1.4),
    Do((_) => shaft.floodTo(exitTop + 0.3, speed: 0.3)),
    Wait(0.8),
    Do((_) {
      player.forceLookUp = false;
      keeper.walkTo(112);
    }),
    Look(null),
  ]);

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    for (final barrel in barrels) {
      barrel.resetToStart();
    }
    if (at < chamberRight) {
      drain.reset();
      chamber.setLevel(7.15);
    }
    if (at < shaftRight) {
      _flooding = false;
      shaft.setLevel(floor - 0.02);
      keeper.gone = true;
    }
  }
}
