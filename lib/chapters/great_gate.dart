import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/castle_props.dart';
import '../entities/ground.dart';
import '../entities/outdoor_props.dart';
import '../entities/physics_props.dart';
import '../physics/water.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/creatures.dart';
import '../story/cutscene.dart';
import '../story/hunters.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter thirteen, The Great Gate.
///
/// Out at last into the night air, in the castle's courtyard, braziers
/// burning on its walls. The great gate is shut; its counterweight is a
/// bucket at the end of the gallery over the courtyard, and one crate in
/// it is not enough to lift all that iron. Two are: he shoves both along
/// the gallery and into it, it sinks, and the gate goes up with a groan; the bell in the tower tolls, and the keeper
/// comes down off the wall behind him. Beyond the gate the moat, and the
/// drawbridge standing up on its chain: a cord at the edge lets the
/// chain run, and the bridge comes down across the water just in time.
///
/// ```
///  0  6 brazier  14–24 the gallery, two crates  24–26.4 the bucket
///  28 the gate  32.2 the keeper  41 cart  48.6 cord  50–56.4 the moat
///  74 out
/// ```
class GreatGateChapter extends Chapter {
  GreatGateChapter({required super.intent});

  @override
  int get number => 13;
  @override
  String get title => 'The Great Gate';
  @override
  double get width => 80;
  @override
  MoodTrack get moods => const MoodTrack(Mood.night);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.sparse;

  static const double floor = 7.0;
  static const double galleryLeft = 14, galleryTop = 5.6;
  static const double panLeft = 24, panRight = 26.4;
  static const double gateX = 28;
  static const double moatLeft = 50, moatRight = 56.4;

  @override
  List<List<double>> get profile => const [
    [0, floor, panLeft, floor],
    [panRight, floor, moatLeft, floor],
    [moatRight, floor, 62, 6.9, 70, 6.7, 80, 6.6],
  ];

  @override
  List<double> get checkpointXs => const [10, 31, 46, 60];

  @override
  Vector2 get spawn => Vector2(3, floor - GameConfig.playerHeight / 2);

  @override
  double get exitX => 74;

  @override
  List<String> get art => const [
    'part4/ch13_great_gate.png',
    'part4/ch13_great_gate_far.png',
    'part1/ch2_giant_tree_a.png',
    'part1/ch2_giant_tree_a_far.png',
  ];

  late final WeighPan pan;
  late final Portcullis gate;
  late final PhysicsCrate crateA, crateB;
  late final Drawbridge bridge;
  late final PullCord bridgeCord;
  late final WaterBody moat;
  final Vampire keeper = Vampire(x: 26, groundY: floor, facing: 1);
  late final Pursuer pursuer = Pursuer(keeper, stage: this, speed: 2.9);
  bool chasing = false;
  double _restart = 0;

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    if (index == 0) {
      return [
        Ground.slab(
          left: left - 0.1,
          right: right + 0.1,
          top: galleryTop + 2.9,
          thickness: height + 2 - galleryTop - 2.9,
        ),
      ];
    }
    final parts = waterPit(left, right, surface: 8.0, floor: 11.5);
    moat = parts.whereType<WaterBody>().single;
    return parts;
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    pieces.add(LightLayer());
    // --- The courtyard's walls and the gatehouse ----------------------------
    pieces.addAll([
      StoneBlock(
        left: -3,
        top: -8,
        right: 0.4,
        bottom: floor + 0.05,
        seed: 111,
      ),
      // The gallery along the courtyard wall, ending at the bucket.
      StoneBlock(
        left: galleryLeft,
        top: galleryTop,
        right: panLeft,
        bottom: floor + 0.05,
        seed: 112,
      ),
      // The wall beyond the bucket, open below for the way to the gate.
      StoneBlock(left: panRight, top: -8, right: 26.9, bottom: 5.5, seed: 115),
      // The gatehouse over the gate, the gate's slot in it.
      StoneBlock(
        left: 26.9,
        top: -8,
        right: gateX - 0.16,
        bottom: 3.8,
        seed: 113,
      ),
      StoneBlock(
        left: gateX + 0.16,
        top: -8,
        right: 31,
        bottom: 3.8,
        seed: 114,
      ),
      // The gatehouse's legs, down to the ground behind the passage, so
      // it stands as an arch and does not hang in the sky.
      StoneBlock(
        left: panRight,
        top: 5.4,
        right: 26.9,
        bottom: floor + 0.05,
        seed: 116,
        solid: false,
        priority: -37,
      ),
      StoneBlock(
        left: 30.4,
        top: 3.7,
        right: 31,
        bottom: floor + 0.05,
        seed: 117,
        solid: false,
        priority: -37,
      ),
      Brazier(x: 6, floorY: floor),
    ]);
    pieces.addAll([
      SceneryProp(
        'part4/ch13_great_gate.png',
        x: 30,
        baseY: 7.7,
        height: 9,
        depth: 0.62,
      ),
      for (final x in const [64.0, 75.0])
        SceneryProp(
          'part1/ch2_giant_tree_a.png',
          x: x,
          baseY: 7.0,
          height: 6.5,
          depth: 0.9,
          fog: 0.12,
          priority: -30,
        ),
      BatFlock(roost: Vector2(30, 1.0), player: player, count: 14, seed: 131),
    ]);

    // --- Two crates, the pan, the gate ---------------------------------------
    // Light enough that he can shove the two along together; one is not
    // enough against the gate, two are.
    crateA = PhysicsCrate(
      position: Vector2(19.3, galleryTop - 0.5),
      size: Vector2(1, 1),
      massKg: 25,
    );
    crateB = PhysicsCrate(
      position: Vector2(18.1, galleryTop - 0.5),
      size: Vector2(1, 1),
      massKg: 25,
    );
    pan = WeighPan(
      floorAt: Vector2((panLeft + panRight) / 2, galleryTop),
      width: panRight - panLeft - 0.1,
      drop: 2.4,
    );
    gate = Portcullis(
      position: Vector2(gateX, floor - 1.5),
      height: 3.0,
      massKg: 45,
      rise: 2.4,
    );
    pieces.addAll([
      crateA,
      crateB,
      pan,
      gate,
      Pulley(a: pan, b: gate, wheelY: 2.0),
    ]);

    // --- The moat and the drawbridge -----------------------------------------
    bridge = Drawbridge(
      hinge: Vector2(moatLeft, floor),
      length: moatRight - moatLeft + 0.3,
    );
    bridgeCord = PullCord(
      anchor: Vector2(moatLeft - 1.4, floor - 4.5),
      length: 3.6,
      onPulled: bridge.lower,
    );
    pieces.addAll([
      CastleTable(left: 41, right: 42.6, floorY: floor, height: 0.8),
      bridge,
      bridgeCord,
      keeper..gone = true,
    ]);
  }

  @override
  void begin() {
    onReach(gateX + 4.2, () => play(_alarm()));
  }

  /// The bell, and the keeper down off the wall behind him.
  Cutscene _alarm() => Cutscene([
    Do((_) {
      cue('bell', shake: 0.15);
      keeper
        ..revive()
        ..x = gateX + 0.2
        ..groundY = floor
        ..facing = 1
        ..eyes = 1
        ..dropFrom(4.0);
      player.forceLookBack = true;
    }),
    Look(Vector2(gateX, 5.0)),
    Wait(1.2),
    Do((_) {
      player.forceLookBack = false;
      chasing = true;
      pursuer.start();
    }),
    Look(null),
  ]);

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted) return;
    if (_restart > 0) {
      _restart -= dt;
      if (_restart <= 0) {
        chasing = true;
        pursuer.start();
      }
    }
    if (chasing) pursuer.update(dt);
  }

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (at < panRight) {
      crateA.resetToStart();
      crateB.resetToStart();
      pan.resetToStart();
      gate.resetToStart();
    }
    if (at < moatLeft) {
      bridge.raise();
      bridgeCord.reset();
    }
    if (at >= 31 && at < moatLeft && (chasing || pursuer.caught)) {
      final double from = at - 8;
      keeper
        ..revive()
        ..x = from
        ..groundY = from > galleryLeft && from < panLeft ? galleryTop : floor
        ..facing = 1
        ..eyes = 1;
      chasing = false;
      pursuer.stop();
      _restart = 1.2;
    }
  }
}
