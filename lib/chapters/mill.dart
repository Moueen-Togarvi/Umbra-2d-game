import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/castle_props.dart';
import '../entities/mill_props.dart';
import '../entities/physics_props.dart';
import '../physics/water.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/hunters.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter twelve, The Mill.
///
/// The castle's water: a mill race under a stone bridge, its wheel
/// standing still in a trickle, and beyond a gate the wheel winds up. A
/// cord opens the sluice; the race fills and runs, the water drives the
/// wheel round, and turn by turn its shaft winds the gate open. Then the
/// cistern, empty, two of them below in the dark; high on its far side
/// the way out. A cord pulls the pin from the dam over it: the water
/// thunders in, closes over them, and lifts a floating crate, with him on
/// it, up to the far ledge.
///
/// ```
///  0  12.5 sluice cord  15–31 the race and the wheel  35 the gate
///  44.5 dam cord  46–62 the cistern  62 ledge, 112 out
/// ```
class MillChapter extends Chapter {
  MillChapter({required super.intent});

  @override
  int get number => 12;
  @override
  String get title => 'The Mill';
  @override
  double get width => 120;
  @override
  MoodTrack get moods => const MoodTrack(Mood.castle);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.hallSpecs;
  @override
  bool get grassy => false;

  static const double floor = 7.0;
  static const double raceLeft = 15, raceRight = 31;
  static const double gateX = 35;
  static const double basinLeft = 46, basinRight = 62;
  static const double basinFloor = 11.0, ledge = 4.0;

  @override
  List<List<double>> get profile => const [
    [0, floor, raceLeft, floor],
    [raceRight, floor, basinLeft, floor],
    [basinRight, ledge, 120, ledge],
  ];

  @override
  List<double> get checkpointXs => const [10, 33, 42, 66];

  @override
  Vector2 get spawn => Vector2(3, floor - GameConfig.playerHeight / 2);

  @override
  double get exitX => 112;

  @override
  List<String> get art => const [
    'part4/ch12_aqueduct.png',
    'part4/ch12_aqueduct_far.png',
    'part4/ch12_dam_wall.png',
    'part4/ch12_dam_wall_far.png',
    'part4/ch12_waterwheel.png',
    'part4/ch12_waterwheel_far.png',
  ];

  late final WaterBody race, basin;
  late final Waterwheel wheel;
  late final WinchGate gate;
  late final PullCord sluiceCord, damCord;
  late final PhysicsCrate raft;
  final List<Vampire> drowned = [
    Vampire(x: 50, groundY: basinFloor, facing: 1),
    Vampire(x: 57, groundY: basinFloor, facing: -1),
  ];
  final List<Stalker> _below = [];
  bool _sluice = false, _flood = false;

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    if (index == 0) {
      final parts = waterPit(left, right, surface: 8.6, floor: 10.0);
      race = parts.whereType<WaterBody>().single;
      return parts;
    }
    final parts = waterPit(
      left,
      right,
      surface: basinFloor - 0.02,
      floor: basinFloor,
    );
    basin = parts.whereType<WaterBody>().single;
    return parts;
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    pieces.add(LightLayer());
    // --- Stone: the vault, the bridge over the race --------------------------
    pieces.addAll([
      StoneBlock(left: -3, top: -8, right: 123, bottom: 0.6, seed: 91),
      StoneBlock(
        left: raceLeft - 0.1,
        top: floor,
        right: raceRight + 0.1,
        bottom: floor + 0.4,
        seed: 92,
      ),
    ]);

    // --- Art ---------------------------------------------------------------
    pieces.addAll([
      SceneryProp(
        'part4/ch12_aqueduct.png',
        x: 26,
        baseY: 7.6,
        height: 6,
        depth: 0.55,
      ),
      SceneryProp(
        'part4/ch12_dam_wall.png',
        x: 54,
        baseY: 7.8,
        height: 5.5,
        depth: 0.62,
      ),
      SceneryProp(
        'part4/ch12_waterwheel.png',
        x: 90,
        baseY: 7.6,
        height: 6,
        depth: 0.5,
      ),
    ]);

    // --- The race, its wheel, the gate it winds ---------------------------
    wheel = Waterwheel(axle: Vector2(23, 6.0), radius: 2.0, race: race);
    gate = WinchGate(x: gateX, floorY: floor, wheel: wheel);
    sluiceCord = PullCord(
      anchor: Vector2(12.5, floor - 4.5),
      length: 3.6,
      onPulled: () => _sluice = true,
    );
    pieces.addAll([wheel, gate, sluiceCord]);

    // --- The cistern, the dam, the raft -------------------------------------
    damCord = PullCord(
      anchor: Vector2(44.5, floor - 4.5),
      length: 3.6,
      onPulled: () {
        _flood = true;
        basin.floodTo(ledge + 0.25, speed: 0.3);
      },
    );
    // As wide and heavy as the raft in the caves: it takes his weight at
    // one end without tipping.
    raft = PhysicsCrate(
      position: Vector2(basinLeft + 1.7, basinFloor - 0.45),
      size: Vector2(3.0, 0.9),
      massKg: 36,
    );
    for (final v in drowned) {
      _below.add(
        Stalker(
          v,
          stage: this,
          ground: (_) => basinFloor,
          left: basinLeft + 0.6,
          right: basinRight - 0.6,
          patrolA: v.x - 2.5,
          patrolB: v.x + 2.5,
        ),
      );
    }
    pieces.addAll([damCord, raft, ...drowned]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted) return;
    // The sluice open: the race fills and runs.
    if (_sluice) {
      race.current = (race.current + dt * 1.4).clamp(0.0, 2.8);
      if (race.isSettled && race.level > 7.9) race.floodTo(7.8, speed: 0.4);
    }
    // The cistern filling: once it is up past the floor he stood on, the
    // water pouring in from the dam pushes what floats away across it.
    if (_flood) {
      basin.current = basin.level < floor - 1.0 ? 2.2 : 0;
    }
    for (var i = 0; i < drowned.length; i++) {
      final v = drowned[i];
      if (!v.gone && basin.level < v.groundY - 1.7) v.drown();
      _below[i].update(dt);
    }
  }

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (at < raceLeft) {
      _sluice = false;
      race
        ..current = 0
        ..setLevel(8.6);
      sluiceCord.reset();
      gate.reset();
    }
    if (at < basinRight) {
      _flood = false;
      basin
        ..current = 0
        ..setLevel(basinFloor - 0.02);
      damCord.reset();
      raft.resetToStart();
      for (var i = 0; i < drowned.length; i++) {
        _below[i].reset(i == 0 ? 50 : 57);
      }
    }
  }
}
