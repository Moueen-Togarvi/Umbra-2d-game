import 'dart:ui' show Color;

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/cave_props.dart';
import '../entities/ground.dart';
import '../entities/player.dart';
import '../entities/water_props.dart';
import '../physics/water.dart';
import '../render/mood.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/scenery.dart';
import '../story/creatures.dart';
import '../story/vampire.dart';
import 'chapter.dart';
import '../world/stage.dart';

/// Chapter five, The Crypt.
///
/// Under the castle the dead lie in water. A flooded hall crossed on the
/// coffins chained in it: each floats only until he stands on it, then
/// sinks under his weight, so he must keep going from one to the next. A
/// drowned passage, emptied by a drain he opens, leaves a coffin aground
/// against the far wall as a step. Then the long hall of the tombs, where
/// a lid shifts as he passes and one of them climbs out after him: he must
/// reach the running stream across the floor, the one thing it will not
/// cross.
///
/// ```
///  0 stairs  27–41 the coffins  52.9 drain  54–68 the passage
///  80 the tomb  97–100.5 the stream  176 out
/// ```
class CryptChapter extends Chapter {
  CryptChapter({required super.intent});

  @override
  void restoreWorld(double x) {
    if (x >= drainRight) {
      drain.pressed = true;
      passage.setLevel(9.45);
    }
    if (x >= streamLeft) {
      _woken = true;
      tomb.gone = true;
    }
  }

  @override
  String? get ambience => 'cave';
  @override
  String get footing => 'gravel';
  @override
  int get number => 11;
  @override
  String get title => 'The Crypt';
  @override
  double get coreWidth => 180;
  @override
  MoodTrack get moods => const MoodTrack(Mood.crypt);
  @override
  List<FogLayerSpec> get backdropSpecs => FogBackdrop.hallSpecs;

  static const double hallLeft = 27, hallRight = 41;
  static const double drainLeft = 54, drainRight = 68;
  static const double streamLeft = 97, streamRight = 100.5;
  static const double tombX = 80.3;

  @override
  List<List<double>> get baseProfile => const [
    [
      0, 6.2, 5, 6.2, 7, 6.45, 9, 6.7, 11, 6.95, 13, 7.0, 18, 7.0, //
      24, 7.0, hallLeft, 7.0,
    ],
    [hallRight, 7.0, 46, 7.0, 50, 6.95, drainLeft, 7.0],
    [drainRight, 7.0, 74, 7.0, 80, 6.95, 86, 7.0, 92, 7.0, streamLeft, 7.0],
    [
      streamRight, 7.0, 106, 7.0, 112, 6.8, 120, 6.4, 128, 6.0, 136, 5.8, //
      146, 5.8, 156, 6.2, 166, 6.6, 175, 7.0, 180, 7.0,
    ],
  ];

  @override
  List<double> get coreCheckpointXs => const [14, 42.5, 69.5, 102, 140];

  @override
  Vector2 get spawn => Vector2(3, 6.2 - GameConfig.playerHeight / 2);

  @override
  double get coreExitX => 176;

  @override
  List<String> get art => const [
    'part2/ch5_crypt_arches.png',
    'part2/ch5_crypt_arches_far.png',
    'part2/ch5_catacomb_shelves.png',
    'part2/ch5_catacomb_shelves_far.png',
    'part2/ch5_sarcophagus.png',
    'part2/ch5_weeping_angel.png',
    'part2/ch5_weeping_angel_far.png',
    'part2/ch5_candelabra.png',
    'part2/ch5_crypt_gate.png',
    'part1/ch3_hanging_chains.png',
  ];

  late final WaterBody hall, passage, stream;
  late final FootPedal drain;
  final List<Coffin> floating = [];
  late final Coffin aground;
  late final Coffin obstacle;
  final Vampire tomb = Vampire(x: tombX, groundY: 7.0, facing: 1);
  bool _woken = false;
  bool _caught = false;

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    switch (index) {
      case 0:
        final parts = waterPit(left, right, surface: 7.25, floor: 10.0);
        hall = parts.whereType<WaterBody>().single;
        return parts;
      case 1:
        final parts = waterPit(left, right, surface: 6.95, floor: 9.8);
        passage = parts.whereType<WaterBody>().single;
        return parts;
      case 2:
        // Running water: shallow enough to wade, and it flows.
        final parts = waterPit(
          left,
          right,
          surface: 7.2,
          floor: 7.75,
          current: 1.2,
        );
        stream = parts.whereType<WaterBody>().single;
        return parts;
    }
    return super.buildPit(index, left, right, lip);
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    double g(double x) => groundAt(x);

    // --- The crypt: vaults and arches far and near ------------------------
    pieces.addAll([
      RockMass([
        Vector2(-3, -4),
        Vector2(183, -4),
        Vector2(183, 0.6),
        Vector2(150, 1.2),
        Vector2(120, 0.4),
        Vector2(100, 1.6),
        Vector2(90, 1.0),
        Vector2(70, 2.0),
        Vector2(54, 3.6),
        Vector2(40, 1.4),
        Vector2(20, 0.8),
        Vector2(-3, 1.2),
      ], seed: 31),
      for (final (x, depth, h) in const [
        (12.0, 0.55, 7.5),
        (48.0, 0.6, 8.0),
        (88.0, 0.55, 7.5),
        (122.0, 0.6, 8.0),
        (158.0, 0.55, 7.5),
      ])
        SceneryProp(
          'part2/ch5_crypt_arches.png',
          x: x,
          baseY: 7.8,
          height: h,
          depth: depth,
        ),
      for (final (x, h) in const [(20.0, 3.6), (76.0, 3.4), (130.0, 3.6)])
        SceneryProp(
          'part2/ch5_catacomb_shelves.png',
          x: x,
          baseY: 7.4,
          height: h,
          depth: 0.82,
        ),
      SceneryProp(
        'part2/ch5_weeping_angel.png',
        x: 17,
        baseY: g(17) + 0.15,
        height: 3.2,
        depth: 0.93,
        fog: 0.13,
        priority: -30,
      ),
      SceneryProp(
        'part2/ch5_weeping_angel.png',
        x: 150,
        baseY: g(150) + 0.15,
        height: 3.4,
        depth: 0.93,
        fog: 0.13,
        flip: true,
        priority: -30,
      ),
      for (final x in const [8.0, 45.0, 72.0, 92.0, 110.0, 166.0])
        SceneryProp(
          'part2/ch5_candelabra.png',
          x: x,
          baseY: g(x) + 0.1,
          height: 1.9,
          depth: 0.95,
          fog: 0.13,
          priority: -25,
        ),
      SceneryProp(
        'part1/ch3_hanging_chains.png',
        x: 61,
        baseY: 4.0,
        height: 3.0,
        depth: 0.88,
        fog: 0.12,
        priority: -40,
      ),
      SceneryProp(
        'part2/ch5_crypt_gate.png',
        x: 177.4,
        baseY: g(177.4) + 0.1,
        height: 4.0,
        depth: 0.98,
        fog: 0.15,
        priority: -20,
      ),
      WatchingEyes(
        x: 64,
        y: 3.2,
        depth: 0.6,
        color: const Color(0xFFC21E1E),
        shyDistance: 0,
        seed: 41,
      ),
      BatFlock(roost: Vector2(118, 1.8), player: player, count: 10, seed: 43),
    ]);

    // --- The flooded hall: coffins chained to the floor ------------------
    for (final x in const [29.0, 31.6, 34.2, 36.8, 39.3]) {
      final coffin = Coffin(
        position: Vector2(x, 7.27),
        // A little heavier than it and him can float: it settles, slowly,
        // under his weight.
        massKg: 36,
        chainedTo: Vector2(x, 10.0),
      );
      floating.add(coffin);
    }
    pieces.addAll(floating);

    // --- The drowned passage and its drain --------------------------------
    drain = FootPedal(
      hinge: Vector2(52.9, g(52.9) - 0.07),
      length: 1.3,
      onPress: () => passage.floodTo(9.45, speed: 0.45),
    );
    aground = Coffin(position: Vector2(66.4, 7.2), massKg: 28);
    pieces.addAll([drain, aground]);

    // --- The tomb, and the one who climbs out of it -----------------------
    obstacle = Coffin(position: Vector2(89.2, g(89.2) - 0.31), massKg: 60);
    pieces.addAll([
      tomb
        ..gone = true
        ..eyes = 1
        ..walkSpeed = 3.35,
      // The tomb is drawn over him, so he climbs out from inside it.
      SceneryProp(
        'part2/ch5_sarcophagus.png',
        x: tombX,
        baseY: g(tombX) + 0.1,
        height: 1.35,
        priority: 5,
      ),
      obstacle,
      Ground.restingLog(
        left: 128.4,
        right: 130.0,
        diameter: 0.5,
        groundBelow: groundAt,
      ),
    ]);
  }

  /// Whether he is in the running water, where it will not follow.
  bool get inStream {
    final double x = player.body.position.x;
    return x > streamLeft - 0.1 && x < streamRight + 0.1;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_woken &&
        !tomb.gone &&
        player.isMounted &&
        !player.isDead &&
        player.body.position.x < streamLeft) {
      reportThreat(ThreatLevel.chase);
    }
    if (!player.isMounted || player.isDead) return;
    final double x = player.body.position.x;
    if (!_woken && x > 84 && x < streamLeft) {
      _woken = true;
      tomb
        ..gone = false
        ..x = tombX
        ..groundY = groundAt(tombX)
        ..facing = 1
        ..riseFrom(1.6);
    }
    if (!_woken || !tomb.risen || _caught) return;
    // After him, as far as the water. There it stops, and reaches out
    // over it.
    final double edge = streamLeft - 0.45;
    if (x > edge) {
      if ((tomb.x - edge).abs() > 0.3) {
        if (tomb.mode != VampireMode.walk || (tomb.goalX - edge).abs() > 0.01) {
          tomb.walkTo(edge);
        }
      } else {
        tomb
          ..facing = 1
          ..mode = VampireMode.grab;
      }
    } else if ((x - tomb.goalX).abs() > 0.1 || tomb.mode != VampireMode.walk) {
      tomb.walkTo(x);
    }
    if ((x - tomb.x).abs() < 0.85 && !inStream && x < streamLeft) {
      _caught = true;
      tomb.seize();
      player.die(cause: DeathCause.vampire);
    }
  }

  /// Back from a death: the coffins as they were, the passage flooded
  /// again if he had not crossed it, and the tomb shut.
  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    for (final coffin in floating) {
      coffin.resetToStart();
    }
    if (at < drainRight) {
      drain.reset();
      passage.setLevel(6.95);
      aground.resetToStart();
    }
    if (at < streamLeft) {
      _woken = false;
      _caught = false;
      tomb
        ..gone = true
        ..mode = VampireMode.stand
        ..x = tombX;
    }
  }
}
