import 'dart:ui' show Color;

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/ground.dart';
import '../entities/physics_props.dart';
import '../entities/rock.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/creatures.dart';
import '../story/cutscene.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter two, The Night Forest.
///
/// Eyes in the undergrowth that go out as he comes near; bats bursting
/// from a dead tree. A hunters' stake pit too wide to jump: the crate
/// beside it has to go in first, onto the stakes, to be a step down and
/// up. A ravine crossed on a rope while a swarm streams past; a bank so
/// steep he slides down it, and far off in the fog a tall figure walking
/// with red eyes. A fallen giant to climb, a graveyard where nothing
/// watches any more, and a clearing where he stops to look back for the
/// lamp — and something drops from the trees.
///
/// ```
///  0  10–22 eyes  32 crate  36.5–39.1 stakes  66.5–70.9 rope  93.5 slide
///  98 glimpse  124–131 fallen giant  156–180 graves  188 the clearing
/// ```
class ForestChapter extends Chapter {
  ForestChapter({required super.intent});

  @override
  int get number => 2;
  @override
  String get title => 'The Night Forest';
  @override
  double get width => 204;
  @override
  MoodTrack get moods => const MoodTrack(Mood.night);

  static const double stakesLeft = 36.5, stakesRight = 39.1;
  static const double ravineLeft = 66.5, ravineRight = 69.9;

  @override
  List<List<double>> get profile => const [
    [
      0,
      7.0,
      6,
      7.05,
      12,
      6.9,
      18,
      7.0,
      24,
      7.1,
      30,
      7.0,
      34.5,
      7.0,
      stakesLeft,
      7.0,
    ],
    [stakesRight, 7.0, 44, 6.95, 50, 7.05, 56, 6.9, 62, 6.8, ravineLeft, 6.7],
    [
      ravineRight, 6.7, 76, 6.6, 82, 6.75, 88, 6.5, 91, 6.4, 93.5, 6.6, //
      95.5, 8.2, 97, 9.0, 99, 9.3, 104, 9.4, 110, 9.2, 116, 9.0, 121, 9.1, //
      131, 9.0, 138, 8.6, 146, 7.6, 152, 7.1, 160, 7.0, 168, 7.05, //
      176, 6.95, 184, 7.0, 192, 6.95, 198, 7.0, 204, 7.0,
    ],
  ];

  @override
  List<double> get checkpointXs => const [14, 34, 41, 72, 100, 133, 160, 184];

  @override
  Vector2 get spawn => Vector2(3, 7.0 - GameConfig.playerHeight / 2);

  /// Never crossed: the chapter ends in the clearing's scene.
  @override
  double get exitX => width + 10;

  @override
  List<String> get art => const [
    'part1/ch2_giant_tree_a.png',
    'part1/ch2_giant_tree_b.png',
    'part1/ch2_giant_tree_c.png',
    'part1/ch2_giant_tree_a_far.png',
    'part1/ch2_giant_tree_b_far.png',
    'part1/ch2_giant_tree_c_far.png',
    'part1/ch2_bramble.png',
    'part1/ch2_signpost.png',
    'part1/ch2_hunters_shed_far.png',
    'part1/ch2_owl.png',
    'part1/ch2_graves.png',
    'part1/ch2_graves_far.png',
    'part1/ch2_wooden_cross.png',
  ];

  late final PhysicsCrate crate;
  late final BatFlock bats;
  late final BatFlock swarm;
  final Vampire stranger = Vampire(x: 0, groundY: 7, depth: 0.7);
  late final Vampire taker;
  bool _swarmed = false;

  @override
  Future<void> furnish(List<Component> pieces) async {
    double g(double x) => groundAt(x);

    // --- The forest at every depth ---------------------------------------
    for (final (x, image, h, depth, flip) in const [
      (8.0, 'a', 14.0, 0.62, false),
      (30.0, 'c', 15.0, 0.6, true),
      (58.0, 'b', 16.0, 0.62, false),
      (86.0, 'a', 15.0, 0.6, true),
      (118.0, 'c', 16.0, 0.62, false),
      (150.0, 'b', 14.0, 0.6, true),
      (182.0, 'a', 15.0, 0.62, false),
    ]) {
      pieces.add(
        SceneryProp(
          'part1/ch2_giant_tree_$image.png',
          x: x,
          baseY: 7.6,
          height: h,
          depth: depth,
          flip: flip,
        ),
      );
    }
    for (final (x, image, h, flip) in const [
      (1.5, 'b', 13.0, false),
      (20.0, 'a', 12.0, true),
      (45.0, 'c', 13.5, false),
      (79.0, 'b', 12.5, true),
      (108.0, 'a', 12.0, false),
      (140.0, 'c', 13.0, true),
      (168.0, 'b', 12.0, false),
      (200.0, 'a', 13.0, true),
    ]) {
      pieces.add(
        SceneryProp(
          'part1/ch2_giant_tree_$image.png',
          x: x,
          baseY: g(x) + 0.5,
          height: h,
          depth: 0.97,
          fog: 0.16,
          flip: flip,
          priority: -30,
        ),
      );
    }

    // --- Watchers, and the bats in the dead tree --------------------------
    for (final (x, seed) in const [(10.0, 1), (22.5, 2), (47.0, 3)]) {
      pieces
        ..add(
          SceneryProp(
            'part1/ch2_bramble.png',
            x: x,
            baseY: g(x) + 0.25,
            height: 1.4,
            depth: 0.92,
            fog: 0.12,
            priority: -20,
          ),
        )
        ..add(
          WatchingEyes(x: x + 0.1, y: g(x) - 0.55, player: player, seed: seed),
        );
    }
    bats = BatFlock(roost: Vector2(18.5, 2.6), player: player, count: 12);
    swarm = BatFlock(roost: Vector2(60, -5), count: 26, seed: 9);
    pieces.addAll([bats, swarm]);

    // --- The hunters' ground ---------------------------------------------
    // A cube: whichever way it tumbles into the pit, it lands on a face
    // and its top is a flat step.
    crate = PhysicsCrate(
      position: Vector2(32.4, g(32.4) - 0.7 - 0.03),
      size: Vector2(1.4, 1.4),
      massKg: 18,
      friction: 0.35,
    );
    pieces.addAll([
      SceneryProp(
        'part1/ch2_hunters_shed.png',
        x: 27,
        baseY: 7.6,
        height: 3.4,
        depth: 0.7,
      ),
      crate,
      Ground.restingLog(
        left: 48.0,
        right: 49.6,
        diameter: 0.5,
        groundBelow: groundAt,
      ),
      SceneryProp(
        'part1/ch2_signpost.png',
        x: 60.5,
        baseY: g(60.5) + 0.2,
        height: 2.3,
        depth: 0.95,
        fog: 0.14,
        flip: true,
        priority: -20,
      ),
      Rock(left: 55.6, right: 56.4, height: 0.4, groundBelow: groundAt),
      SwingRope(anchor: Vector2(68.3, 2.2), length: 3.6),
    ]);

    // --- The far side: the slide, the glimpse, the fallen giant -----------
    pieces.addAll([
      stranger
        ..eyes = 0
        ..gone = true,
      Ground.restingLog(
        left: 124,
        right: 131,
        diameter: 1.6,
        groundBelow: groundAt,
      ),
      SceneryProp(
        'part1/ch2_owl.png',
        x: 141,
        baseY: 4.6,
        height: 1.1,
        depth: 0.88,
        fog: 0.14,
        priority: -40,
      ),
      WatchingEyes(
        x: 141.1,
        y: 3.88,
        depth: 0.88,
        color: const Color(0xFFF0D890),
        shyDistance: 0,
        seed: 5,
      ),
      for (final (x, h) in const [(158.0, 1.9), (171.0, 2.1)])
        SceneryProp(
          'part1/ch2_graves.png',
          x: x,
          baseY: g(x) + 0.3,
          height: h,
          depth: 0.9,
          fog: 0.12,
          priority: -40,
        ),
      for (final (x, h) in const [(164.0, 1.8), (177.5, 1.6)])
        SceneryProp(
          'part1/ch2_wooden_cross.png',
          x: x,
          baseY: g(x) + 0.35,
          height: h,
          depth: 0.96,
          fog: 0.15,
          priority: -20,
        ),
      Rock(left: 166.4, right: 167.2, height: 0.38, groundBelow: groundAt),
      DistantLight(x: 120, y: 6.4, depth: 0.12, showFrom: 182, showTo: 190),
    ]);
    taker = Vampire(x: 200, groundY: g(200), facing: -1);
    pieces.add(taker..eyes = 0);

    onReach(97.5, () {
      // Far off in the fog, something tall walks the other way.
      final double cam = player.body.position.x;
      stranger
        ..gone = false
        ..x = cam + 13
        ..groundY = 7.3
        ..walkSpeed = 2.0
        ..eyes = 1
        ..walkTo(cam - 30);
    });
    onReach(188, () => play(_taken()));
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Once across, the far figure is gone into the fog.
    if (!stranger.gone && stranger.mode == VampireMode.stand) {
      stranger.gone = true;
    }
    if (!_swarmed && player.isMounted && player.isOnRope) {
      _swarmed = true;
      final double y = player.body.position.y;
      swarm.swarm([
        Vector2(ravineLeft - 9, y - 3.5),
        Vector2(ravineLeft + 2, y - 1.2),
        Vector2(ravineRight + 3, y - 1.5),
        Vector2(ravineRight + 14, y - 6),
      ]);
    }
  }

  /// The clearing: he looks back for the lamp, turns, and it is there.
  Cutscene _taken() => Cutscene([
    Wait(0.6),
    Do((_) => player.forceLookBack = true),
    Look(Vector2(player.body.position.x - 2.5, player.body.position.y - 1.6)),
    Wait(2.6),
    Do((_) {
      player.forceLookBack = false;
      final double x = player.body.position.x;
      taker
        ..x = x + 2.1
        ..groundY = groundAt(x + 2.1)
        ..facing = -1
        ..eyes = 1
        ..dropFrom(6.5);
    }),
    Look(Vector2(player.body.position.x + 1, player.body.position.y - 1.4)),
    WaitUntil((_) => taker.landed, timeout: 3),
    Wait(0.5),
    Run(-1, seconds: 0.35),
    Do((_) => taker.seize()),
    Wait(0.75),
    Fade(1, 0.18),
    Wait(1.2),
    Do((c) => c.complete()),
  ]);
}
