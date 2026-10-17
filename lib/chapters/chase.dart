import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/castle_props.dart';
import '../entities/ground.dart';
import '../entities/physics_props.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/cutscene.dart';
import '../story/hunters.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter seven, The Chase.
///
/// Up out of the cistern into the castle's kitchens. The way on is shut by
/// an iron gate on a rope over two wheels, its other end tied to a
/// weighing pan set in the floor: a crate pushed into the pan outweighs
/// the gate, which rises. In the cellar beyond, the keeper drops through a
/// hatch behind him, and runs him down. A table to vault, a hole in the
/// floor, a step; a tall bookcase at the edge of a gap too wide to jump,
/// that he shoves over to make his bridge. Last, a gate held up on a
/// latch, and past it a deep pit with a cord hanging over it: his weight
/// on the cord slips the latch, and the gate crashes down behind him.
///
/// ```
///  0 kitchen  15.5 crate  20–22 pan  26 gate  30 hatch  38 the keeper
///  48 table  56–57.8 hole  63 step  70–72.4 bookcase gap  86 latched gate
///  88–91.4 the pit and the cord  100–106 steps  132 out
/// ```
class ChaseChapter extends Chapter {
  ChaseChapter({required super.intent});

  @override
  String? get ambience => 'dungeon';
  @override
  int get number => 7;
  @override
  String get title => 'The Chase';
  @override
  double get width => 140;
  @override
  MoodTrack get moods => const MoodTrack(Mood.castle);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.hallSpecs;
  @override
  bool get grassy => false;

  static const double floor = 7.0;
  static const double panLeft = 20, panRight = 22;
  static const double holeLeft = 56, holeRight = 57.8;
  static const double stepLeft = 63, stepTop = 5.7;
  static const double gapLeft = 70, gapRight = 72.4;
  static const double gateX = 86;
  static const double pitLeft = 88, pitRight = 91.4;
  static const double keeperStart = 30;

  @override
  List<List<double>> get profile => const [
    [0, floor, 10, floor, panLeft, floor],
    [panRight, floor, 40, floor, holeLeft, floor],
    [holeRight, floor, gapLeft, floor],
    [gapRight, floor, pitLeft, floor],
    [pitRight, floor, 140, floor],
  ];

  @override
  List<double> get checkpointXs => const [12, 36, 60, 80, 95, 110];

  @override
  Vector2 get spawn => Vector2(3, floor - GameConfig.playerHeight / 2);

  @override
  double get exitX => 132;

  @override
  List<String> get art => const [
    'part3/ch7_kitchen_hearth.png',
    'part3/ch7_hanging_pots.png',
    'part3/ch7_wine_cellar.png',
    'part3/ch7_wine_cellar_far.png',
    'part3/ch7_castle_corridor.png',
    'part3/ch7_castle_corridor_far.png',
    'part3/ch8_long_table.png',
    'part3/ch8_banners.png',
  ];

  late final WeighPan pan;
  late final Portcullis kitchenGate, latchedGate;
  late final PhysicsCrate crate;
  late final TallBookcase bookcase;
  late final PullCord cord;
  final Vampire keeper = Vampire(x: keeperStart, groundY: floor, facing: 1);
  late final Pursuer pursuer = Pursuer(keeper, stage: this);

  /// Whether the chase has begun (the keeper has come down).
  bool chasing = false;
  bool _gateDown = false;
  double _atGate = 0;
  double _restart = 0;

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    if (index == 0) {
      // The pan's pit: a stone floor under where the pan goes down to.
      return [
        Ground.slab(
          left: left - 0.1,
          right: right + 0.1,
          top: floor + 2.6,
          thickness: height + 2 - floor - 2.6,
        ),
      ];
    }
    return super.buildPit(index, left, right, lip);
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    // --- The vaults, the walls between rooms, the steps -------------------
    pieces.addAll([
      StoneBlock(left: -3, top: -4, right: 29.4, bottom: 2.0, seed: 1),
      StoneBlock(left: 31.2, top: -4, right: 84, bottom: 1.6, seed: 2),
      StoneBlock(left: 84, top: -4, right: 143, bottom: 2.1, seed: 3),
      // Over the kitchen gate, and over the latched one.
      // Over the two gates, with the slots they rise into.
      StoneBlock(left: 25.5, top: 3.4, right: 25.84, bottom: 4.4, seed: 4),
      StoneBlock(left: 26.16, top: 3.4, right: 26.5, bottom: 4.4, seed: 41),
      StoneBlock(left: 85.5, top: 2.1, right: 85.84, bottom: 4.4, seed: 5),
      StoneBlock(left: 86.16, top: 2.1, right: 86.5, bottom: 4.4, seed: 51),
      // The step up, and the far side of the bookcase's gap.
      StoneBlock(
        left: stepLeft,
        top: stepTop,
        right: gapLeft,
        bottom: floor + 0.05,
        seed: 6,
      ),
      StoneBlock(
        left: gapRight,
        top: stepTop,
        right: 78,
        bottom: floor + 0.05,
        seed: 7,
      ),
      // Steps up towards the halls.
      StoneBlock(
        left: 100,
        top: 5.8,
        right: 143,
        bottom: floor + 0.05,
        seed: 8,
      ),
      StoneBlock(left: 106, top: 4.6, right: 143, bottom: 5.9, seed: 9),
    ]);

    // --- Kitchens and cellars ---------------------------------------------
    pieces.addAll([
      SceneryProp(
        'part3/ch7_kitchen_hearth.png',
        x: 7,
        baseY: floor + 0.1,
        height: 3.4,
        depth: 0.95,
        fog: 0.1,
        priority: -30,
      ),
      SceneryProp(
        'part3/ch7_hanging_pots.png',
        x: 13.5,
        baseY: 4.4,
        height: 1.8,
        depth: 0.93,
        fog: 0.1,
        priority: -30,
      ),
      SceneryProp(
        'part3/ch8_long_table.png',
        x: 12,
        baseY: floor + 0.1,
        height: 1.5,
        depth: 0.9,
        fog: 0.12,
        priority: -35,
      ),
      for (final x in const [36.0, 46.0, 118.0])
        SceneryProp(
          'part3/ch7_wine_cellar.png',
          x: x,
          baseY: floor + 0.1,
          height: 2.3,
          depth: 0.9,
          fog: 0.12,
          priority: -35,
        ),
      for (final x in const [24.0, 70.0, 104.0])
        SceneryProp(
          'part3/ch7_castle_corridor.png',
          x: x,
          baseY: 7.6,
          height: 6.5,
          depth: 0.6,
        ),
      SceneryProp(
        'part3/ch8_banners.png',
        x: 95,
        baseY: 5.4,
        height: 3.0,
        depth: 0.9,
        fog: 0.12,
        priority: -35,
      ),
    ]);

    // --- The weighing pan and the kitchen gate -----------------------------
    pan = WeighPan(
      floorAt: Vector2((panLeft + panRight) / 2, floor),
      width: 1.9,
      drop: 2.2,
    );
    kitchenGate = Portcullis(position: Vector2(26, floor - 1.4), height: 2.8);
    crate = PhysicsCrate(
      position: Vector2(15.5, floor - 0.5),
      size: Vector2(1, 1),
      massKg: 35,
    );
    pieces.addAll([
      pan,
      kitchenGate,
      Pulley(a: pan, b: kitchenGate, wheelY: 3.0),
      crate,
    ]);

    // --- The chase ----------------------------------------------------------
    // Back from the edge, so he is not drawn after it as it goes; tall
    // enough to reach the far side from there.
    bookcase = TallBookcase(x: gapLeft - 0.66, floorY: stepTop, height: 3.4);
    // A raised stone kerb along the edge: its foot is stopped against it
    // and it turns over the kerb instead of sliding off into the gap.
    pieces.add(
      StoneBlock(
        left: gapLeft - 0.3,
        top: stepTop - 0.12,
        right: gapLeft,
        bottom: stepTop + 0.05,
        seed: 10,
      ),
    );
    latchedGate = Portcullis(
      position: Vector2(gateX, floor - 1.4),
      height: 2.8,
      startLift: 2.0,
      massKg: 60,
    );
    cord = PullCord(
      anchor: Vector2(pitLeft + 1.8, floor - 4.5),
      length: 3.6,
      onPulled: latchedGate.release,
    );
    pieces.addAll([
      CastleTable(left: 48, right: 50.4, floorY: floor),
      bookcase,
      latchedGate,
      cord,
      keeper..gone = true,
    ]);
  }

  @override
  void begin() {
    onReach(38, () => play(_hatch()));
  }

  /// A thud behind him: the keeper, down through a hatch in the vault.
  Cutscene _hatch() => Cutscene([
    Do((_) {
      cue('wood', weight: 0.7);
      keeper
        ..revive()
        ..x = keeperStart
        ..groundY = floor
        ..facing = 1
        ..eyes = 1
        ..dropFrom(3.6);
      player.forceLookBack = true;
    }),
    Look(Vector2(keeperStart + 4, 5.2)),
    Wait(1.3),
    Do((_) {
      player.forceLookBack = false;
      _startChase();
    }),
    Look(null),
  ]);

  void _startChase() {
    chasing = true;
    pursuer.start();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_restart > 0) {
      _restart -= dt;
      if (_restart <= 0) _startChase();
    }
    if (chasing) pursuer.update(dt);
    if (!latchedGate.isReady) return;
    // The latched gate crashing down on him, if he was under it.
    if (!_gateDown && latchedGate.isShut) {
      _gateDown = true;
    }
    if (!keeper.gone &&
        latchedGate.body.linearVelocity.y > 2 &&
        (keeper.x - gateX).abs() < 0.5) {
      keeper.crush();
      pursuer.stop();
    }
    // Shut out: he reaches through the bars a while, then goes.
    if (chasing && pursuer.blocked && player.body.position.x > pitRight) {
      _atGate += dt;
      if (_atGate > 3.5) {
        chasing = false;
        pursuer.stop();
        keeper
          ..reachGoal = 0
          ..walkTo(keeperStart);
      }
    }
    if (!chasing && keeper.mode == VampireMode.walk && keeper.x < gateX - 9) {
      keeper.gone = true;
    }
  }

  /// Back from a death: the room as it was before what killed him, and the
  /// keeper a little way behind him again if the chase was on.
  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (at < panRight) {
      crate.resetToStart();
      pan.resetToStart();
      kitchenGate.resetToStart();
    }
    if (at < gapLeft) bookcase.resetToStart();
    if (at < pitLeft) {
      latchedGate.relatch();
      cord.reset();
      _gateDown = false;
    }
    _atGate = 0;
    if (at >= 36 && at < pitLeft && (chasing || pursuer.caught)) {
      final double from = at - 8;
      keeper
        ..revive()
        ..x = from
        ..groundY = from > stepLeft && from < 78 ? stepTop : floor
        ..facing = 1
        ..eyes = 1;
      chasing = false;
      pursuer.stop();
      _restart = 1.2;
    } else if (at >= pitLeft) {
      chasing = false;
      pursuer.stop();
      keeper.gone = true;
    }
  }
}
