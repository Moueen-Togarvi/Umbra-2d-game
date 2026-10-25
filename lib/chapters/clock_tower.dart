import 'dart:math' as math;

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/castle_props.dart';
import '../entities/clock_props.dart';
import '../entities/hazard.dart';
import '../entities/physics_props.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/creatures.dart';
import 'chapter.dart';

/// Chapter ten, The Clock Tower.
///
/// Out of the ballroom and up into the tower over the castle, through the
/// works of its great clock. The pendulum swings over a drop into the
/// gears, a platform slung between twin rods: he rides it across. A gear
/// of the striking train turns a three-armed hammer across the walkway;
/// he can run between its blows, or push a crate into the slot over the
/// gear's teeth and jam the whole train. The minute hand, behind the
/// clock's glass, jumps a twelfth of a turn at a time: level, for a
/// moment, it bridges the shaft beside it. Then up past the bell.
///
/// ```
///  0  13.5–21.5 the pendulum  25 crate  29.4–30.6 slot over the gear
///  35 the hammer  46.4–51.6 the shaft and the minute hand  92 out
/// ```
class ClockTowerChapter extends Chapter {
  ClockTowerChapter({required super.intent});

  @override
  void restoreWorld(double x) {
    if (x >= 41) {
      gear.restoreJammed();
      crate.restoreAt(Vector2((slotLeft + slotRight) / 2, floor + .4));
    }
  }

  @override
  String? get ambience => 'clockwork';
  @override
  int get number => 22;
  @override
  String get title => 'The Clock Tower';
  @override
  double get coreWidth => 100;
  @override
  MoodTrack get moods => const MoodTrack(Mood.castle);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.hallSpecs;
  @override
  String get footing => 'stone';

  static const double floor = 7.0;
  static const double swingLeft = 13.5, swingRight = 21.5;
  static const double chamberLeft = 27.6, chamberRight = 32.6;
  static const double slotLeft = 29.4, slotRight = 30.6;
  static const double shaftLeft = 46.4, shaftRight = 51.6;
  static const double pivotX = 17.5, rod = 6, arc = 0.56;

  @override
  List<List<double>> get baseProfile => const [
    [0, floor, swingLeft, floor],
    [swingRight, floor, chamberLeft, floor],
    [chamberRight, floor, shaftLeft, floor],
    [shaftRight, floor, 100, floor],
  ];

  @override
  List<double> get coreCheckpointXs => const [10, 23, 41, 55, 75];

  @override
  Vector2 get spawn => Vector2(3, floor - GameConfig.playerHeight / 2);

  @override
  double get coreExitX => 92;

  @override
  List<String> get art => const [
    'part4/ch10_clock_face.png',
    'part4/ch10_clock_face_far.png',
    'part4/ch10_gear_cluster.png',
    'part4/ch10_gear_cluster_far.png',
    'part4/ch10_tower_beams.png',
    'part4/ch10_tower_beams_far.png',
    'part4/ch10_tower_bell.png',
  ];

  late final Pendulum pendulum;
  late final Gear gear;
  late final StrikingHammer hammer;
  late final PhysicsCrate crate;
  late final ClockHand hand;

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    if (index == 1) {
      // The gear's chamber: it turns down there, over a long drop.
      return [
        Hazard.zone(
          left: left,
          right: right,
          top: floor + 5,
          bottom: height,
          stakes: false,
        ),
      ];
    }
    // Down into the clockwork, a long way.
    return [
      Hazard.zone(
        left: left,
        right: right,
        top: lip + GameConfig.pitDepth + 1,
        bottom: height,
        stakes: false,
      ),
    ];
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    // --- The tower's stone, the walkway over the gear, steps up -----------
    pieces.addAll([
      StoneBlock(left: -3, top: -8, right: 103, bottom: -1.0, seed: 71),
      StoneBlock(
        left: chamberLeft - 0.1,
        top: floor,
        right: slotLeft,
        bottom: floor + 0.4,
        seed: 72,
      ),
      StoneBlock(
        left: slotRight,
        top: floor,
        right: chamberRight + 0.1,
        bottom: floor + 0.4,
        seed: 73,
      ),
      // Up to the belfry.
      StoneBlock(
        left: 64,
        top: 5.8,
        right: 103,
        bottom: floor + 0.05,
        seed: 74,
      ),
      StoneBlock(left: 70, top: 4.6, right: 103, bottom: 5.9, seed: 75),
      StoneBlock(left: 76, top: 3.4, right: 103, bottom: 4.7, seed: 76),
    ]);

    // --- Art ---------------------------------------------------------------
    pieces.addAll([
      for (final (double x, double depth, double h) in const [
        (8.0, 0.55, 8.0),
        (40.0, 0.6, 7.5),
        (86.0, 0.55, 8.0),
      ])
        SceneryProp(
          'part4/ch10_tower_beams.png',
          x: x,
          baseY: 7.6,
          height: h,
          depth: depth,
        ),
      for (final (double x, double y) in const [
        (4.0, 2.6),
        (27.0, 3.2),
        (60.0, 2.8),
      ])
        SceneryProp(
          'part4/ch10_gear_cluster.png',
          x: x,
          baseY: y,
          height: 3.0,
          depth: 0.8,
        ),
      // The back of the great clock's face, its glass lit by the night.
      SceneryProp(
        'part4/ch10_clock_face.png',
        x: shaftRight + 0.4,
        baseY: floor + 2.4,
        height: 8.6,
        depth: 0.97,
        fog: 0.06,
        flip: true,
        priority: -36,
      ),
      SceneryProp(
        'part4/ch10_tower_bell.png',
        x: 84,
        baseY: 1.6,
        height: 2.6,
        depth: 0.93,
        fog: 0.1,
        priority: -30,
      ),
      BatFlock(roost: Vector2(86, 0.2), player: player, count: 10, seed: 101),
    ]);

    // --- The pendulum over the drop -----------------------------------------
    final double pivotY = floor - (rod * math.cos(arc) - 0.1);
    pendulum = Pendulum(
      pivot: Vector2(pivotX, pivotY),
      length: rod,
      amplitude: arc,
      plate: 1.4,
    );
    pieces.add(pendulum);

    // --- The striking train: the gear, its slot, its hammer ------------------
    crate = PhysicsCrate(
      position: Vector2(25, floor - 0.5),
      size: Vector2(1, 1),
      massKg: 30,
    );
    gear = Gear(centre: Vector2((slotLeft + slotRight) / 2, 9.1), radius: 1.3);
    hammer = StrikingHammer(axle: Vector2(35, 2.6), arm: 3.6, gear: gear);
    pieces.addAll([crate, gear, hammer]);

    // --- The minute hand over the shaft -------------------------------------
    hand = ClockHand(
      hub: Vector2(shaftRight + 0.4, floor + 0.11),
      length: 6,
      startAngle: math.pi - math.pi / 6,
    );
    pieces.add(hand);
  }

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (at < swingRight) pendulum.reset();
    if (at < chamberLeft) {
      crate.resetToStart();
      gear.free();
    }
  }
}
