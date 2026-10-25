import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../world/footprint.dart';
import '../entities/cave_props.dart';
import '../entities/ground.dart';
import '../entities/player.dart';
import '../render/culling.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/creatures.dart';
import '../story/cutscene.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter three, The Cage.
///
/// He wakes on the floor of an iron cage hanging over a pit of stakes in
/// the vampires' cave. Running from side to side swings it, higher each
/// time, until it strikes the rock hard enough to snap the rusted latch;
/// the door falls open onto the ledge like a drawbridge. Further in, two
/// cages hang over a second pit, their roofs the only way across, swinging
/// under him as he lands. A lever pushed over lets a winch lower a third
/// cage into the next pit to make a bridge. In the low tunnel beyond, one
/// of them walks up and down; the only place to hide is a black niche in
/// the wall, where he must keep still while it passes. Then the way out,
/// towards the moonlight.
///
/// ```
///  0 cage over stakes  6.1 ledge  36–40 step  40–46.6 cages  53.5 lever
///  56.5–61 winch pit  70–100 the tunnel (niche at 85.8)  118 the way out
/// ```
class CageChapter extends Chapter {
  CageChapter({required super.intent});

  @override
  void restoreWorld(double x) {
    if (x >= 7) cell.restoreOpen();
    if (x >= 63) {
      bridge.restoreLowered();
      lever.pressed = true;
    }
  }

  @override
  String? get ambience => 'cave';
  @override
  String get footing => 'gravel';
  @override
  int get number => 6;
  @override
  String get title => 'The Cage';
  @override
  double get coreWidth => 124;
  @override
  MoodTrack get moods => const MoodTrack(Mood.cave);

  static const double ledgeX = 6.1, ledgeY = 4.95;
  static const double stepPitLeft = 40.0, stepPitRight = 46.6;
  static const double winchLeft = 56.5, winchRight = 61.0;
  static const double nicheLeft = 85.0, nicheRight = 86.6;

  @override
  List<List<double>> get baseProfile => const [
    [0, ledgeY, 1.6, ledgeY],
    [
      ledgeX, ledgeY, 10, 5.0, 13, 4.9, 16, 5.1, 19, 5.5, 22, 6.1, //
      25, 6.7, 28, 7.0, 33, 7.0, stepPitLeft, 7.0,
    ],
    [stepPitRight, 7.0, 50, 7.0, 54, 7.05, winchLeft, 7.0],
    [
      winchRight, 7.0, 66, 7.0, 72, 6.9, 78, 7.0, 84, 7.0, 90, 7.05, //
      96, 6.95, 102, 7.0, 108, 6.9, 114, 6.6, 120, 6.2, 124, 6.0,
    ],
  ];

  @override
  List<double> get coreCheckpointXs => const [7.0, 30, 49.6, 63, 100];

  @override
  Vector2 get spawn => Vector2(4.15, 4.35);

  @override
  double get coreExitX => 118;

  @override
  List<String> get art => const [
    'part1/ch3_cage_child_a_far.png',
    'part1/ch3_cage_child_b_far.png',
    'part1/ch3_cage_child_c_far.png',
    'part1/ch3_cage_child_a.png',
    'part1/ch3_cage_child_c.png',
    'part1/ch3_stalactites_far.png',
    'part1/ch3_stalagmites_far.png',
    'part1/ch3_bones.png',
    'part1/ch3_winch.png',
    'part1/ch3_hanging_chains.png',
    'part1/ch3_tunnel_mouth.png',
  ];

  late final HangingCage cell;
  late final List<HangingCage> stepping;
  late final WinchCage bridge;

  /// The winch's foot pedal.
  late final FootPedal lever;
  late final Vampire guard;
  bool _caught = false;

  @override
  Future<void> furnish(List<Component> pieces) async {
    double g(double x) => groundAt(x);

    // --- The cave around: roof, walls, the step, the tunnel --------------
    pieces.addAll([
      RockMass([
        Vector2(-3, -4),
        Vector2(30, -4),
        Vector2(30, -0.6),
        Vector2(24, 0.2),
        Vector2(16, -0.2),
        Vector2(10, 0.5),
        Vector2(6, 0.1),
        Vector2(2, 0.6),
        Vector2(-3, 1.2),
      ], seed: 1),
      RockMass([
        Vector2(30, -4),
        Vector2(70, -4),
        Vector2(70, 0.3),
        Vector2(60, -0.1),
        Vector2(52, 0.5),
        Vector2(46, 0.2),
        Vector2(40, -0.1),
        Vector2(34, 0.6),
        Vector2(30, -0.6),
      ], seed: 2),
      // The step up to the cages, and the ledge on the far side.
      RockMass(
        [
          // A square edge: hands find the top of a corner, not a slope.
          Vector2(36.4, 7.6),
          Vector2(36.4, 5.4),
          Vector2(stepPitLeft, 5.4),
          Vector2(stepPitLeft, 7.6),
        ],
        drips: false,
        seed: 3,
      ),
      RockMass(
        [
          Vector2(stepPitRight, 7.6),
          // A reachable bank after the swinging cage. The old high bank
          // could only be crossed by clipping through its lower face.
          Vector2(stepPitRight, 6.2),
          Vector2(49.55, 6.2),
          Vector2(49.55, 7.6),
        ],
        drips: false,
        seed: 4,
      ),
      // The tunnel's low roof.
      RockMass([
        Vector2(68, -4),
        Vector2(104, -4),
        Vector2(104, 3.3),
        Vector2(99, 3.9),
        Vector2(93, 3.75),
        Vector2(87, 4.05),
        Vector2(81, 3.85),
        Vector2(75, 3.95),
        Vector2(70, 3.4),
        Vector2(68, 0.4),
      ], seed: 5),
      RockMass([
        Vector2(104, -4),
        Vector2(127, -4),
        Vector2(127, 0.0),
        Vector2(116, 1.0),
        Vector2(110, 1.8),
        Vector2(104, 3.3),
      ], seed: 6),
    ]);

    // --- The children in the cages, far off in the dark --------------------
    for (final (x, y, image, h, depth) in const [
      (12.0, 2.4, 'a', 2.6, 0.55),
      (22.0, 1.6, 'b', 2.8, 0.45),
      (33.0, 2.8, 'c', 2.4, 0.6),
      (52.0, 2.2, 'a', 2.6, 0.5),
      (64.0, 1.8, 'b', 2.8, 0.55),
      (110.0, 2.4, 'c', 2.4, 0.5),
    ]) {
      pieces.add(
        SceneryProp(
          'part1/ch3_cage_child_$image.png',
          x: x,
          baseY: y + h,
          height: h,
          depth: depth,
        ),
      );
    }
    for (final (x, image, h) in const [(16.0, 'a', 2.2), (27.5, 'c', 2.1)]) {
      pieces.add(
        SceneryProp(
          'part1/ch3_cage_child_$image.png',
          x: x,
          baseY: g(x) - 0.9,
          height: h,
          depth: 0.92,
          fog: 0.14,
          priority: -30,
        ),
      );
    }
    pieces.addAll([
      SceneryProp(
        'part1/ch3_hanging_chains.png',
        x: 30,
        baseY: 3.4,
        height: 4,
        depth: 0.88,
        fog: 0.12,
        priority: -40,
      ),
      SceneryProp(
        'part1/ch3_bones.png',
        x: 31.5,
        baseY: g(31.5) + 0.12,
        height: 0.7,
        depth: 0.95,
        fog: 0.12,
        priority: -20,
      ),
      SceneryProp(
        'part1/ch3_winch.png',
        x: 51.8,
        baseY: g(51.8) + 0.15,
        height: 2.0,
        depth: 0.93,
        fog: 0.13,
        priority: -20,
      ),
      SceneryProp(
        'part1/ch3_bones.png',
        x: 66.5,
        baseY: g(66.5) + 0.12,
        height: 0.6,
        depth: 0.95,
        fog: 0.12,
        flip: true,
        priority: -20,
      ),
      SceneryProp(
        'part1/ch3_tunnel_mouth.png',
        x: 117.5,
        baseY: g(117.5) + 0.4,
        height: 5.2,
        depth: 0.96,
        fog: 0.16,
        priority: -30,
      ),
      WatchingEyes(
        x: 25,
        y: 3.0,
        depth: 0.6,
        color: const Color(0xFFC21E1E),
        shyDistance: 0,
        seed: 7,
      ),
      _Niche(left: nicheLeft, right: nicheRight, floor: g(85.8)),
      BatFlock(roost: Vector2(108, 1.6), player: player, count: 10, seed: 13),
    ]);

    // --- His cage, and the way out of it ----------------------------------
    cell = HangingCage(
      anchor: Vector2(4.4, 0.6),
      chainLength: 2.6,
      breakSpeed: 2.6,
    );
    stepping = [
      HangingCage(
        anchor: Vector2(41.9, 0.3),
        chainLength: 5.25,
        width: 1.5,
        height: 1.6,
        child: true,
      ),
      HangingCage(
        anchor: Vector2(44.6, 0.3),
        chainLength: 5.25,
        width: 1.5,
        height: 1.6,
      ),
    ];
    bridge = WinchCage(
      anchor: Vector2((winchLeft + winchRight) / 2, 0.6),
      startTop: 2.4,
      endTop: 7.0,
      width: 4.2,
    );
    lever = FootPedal(
      hinge: Vector2(54.4, g(54.4) - 0.07),
      onPress: () => bridge.lowering = true,
    );
    guard = Vampire(x: 92, groundY: g(92), facing: -1)..walkSpeed = 1.05;
    pieces.addAll([cell, ...stepping, bridge, lever, guard]);
    // A fallen beam to hop on the way down.
    pieces.add(
      Ground.restingLog(
        left: 18.2,
        right: 19.6,
        diameter: 0.45,
        groundBelow: groundAt,
      ),
    );
  }

  @override
  void begin() {
    guard.patrol(77, 97);
  }

  @override
  void startStory() {
    play(
      Cutscene([
        Do((c) {
          c.blackness = 1;
          player.knockDown();
        }),
        Look(Vector2(7.5, 3.6)),
        Fade(0, 2.6),
        WaitUntil((_) => player.isOnGround, timeout: 6),
        Wait(0.6),
        Do((_) => player.forceLookUp = true),
        Wait(1.6),
        Do((_) => player.forceLookUp = false),
        Look(null),
      ]),
    );
  }

  /// Whether he is pressed into the niche, still: the one place in the
  /// tunnel it cannot see him.
  bool get hidden {
    final double x = player.body.position.x;
    return player.isLow &&
        x > nicheLeft + 0.25 &&
        x < nicheRight - 0.25 &&
        player.velocity.x.abs() < 0.4 &&
        player.isOnGround;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted || player.isDead || _caught) return;
    // The guard: anything in front of it and near, not hidden, is caught.
    final double dx = player.body.position.x - guard.x;
    final bool ahead = dx * guard.facing > -0.4;
    if (dx.abs() < 1.25 && ahead && !hidden && player.body.position.y > 4.0) {
      _caught = true;
      guard
        ..facing = dx.sign
        ..seize();
      player.die(cause: DeathCause.vampire);
    }
  }

  /// Back on the beat after a respawn.
  void resetGuard() {
    _caught = false;
    guard
      ..x = 92
      ..patrol(77, 97);
  }

  @override
  void onRespawned() => resetGuard();
}

/// A niche in the tunnel wall, as black as he is: standing in it, still,
/// only his eyes show.
class _Niche extends Component with OffScreenCulling implements HasFootprint {
  _Niche({required this.left, required this.right, required this.floor})
    : super(priority: -10);
  final double left, right, floor;
  static final Paint _paint = Paint()..color = const Color(0xFF020202);

  @override
  Rect get footprint => Rect.fromLTRB(left, floor - 2.4, right, floor);

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(Rect.fromLTRB(left, floor - 2.4, right, floor))) return;
    final double w = right - left;
    canvas.drawPath(
      Path()
        ..moveTo(left - 0.1, floor + 0.1)
        ..lineTo(left, floor - 1.55)
        ..quadraticBezierTo(
          left + w * 0.1,
          floor - 2.25,
          left + w / 2,
          floor - 2.3,
        )
        ..quadraticBezierTo(right - w * 0.1, floor - 2.25, right, floor - 1.55)
        ..lineTo(right + 0.1, floor + 0.1)
        ..close(),
      _paint,
    );
    // Rough stones round its mouth.
    for (var i = 0; i < 9; i++) {
      final double t = i / 8;
      final double a = math.pi * (1 - t);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            left + w / 2 + math.cos(a) * (w / 2 + 0.08),
            floor - 1.55 - math.sin(a) * 0.75,
          ),
          width: 0.26,
          height: 0.18,
        ),
        _paint,
      );
    }
  }
}
