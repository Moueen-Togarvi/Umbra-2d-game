import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../physics/collision_layers.dart';
import '../render/culling.dart';
import '../render/mood.dart';
import '../story/vampire.dart';
import '../world/footprint.dart';
import '../world/stage.dart';
import 'castle_props.dart' show TallBookcase;
import 'physics_props.dart';
import 'player.dart';

const Color _black = Color(0xFF060606);

/// A wolf of the woods, run down on all fours. It hunts as a vampire does
/// (a Pursuer drives it, one that cannot climb), and is drawn as itself.
class Wolf extends Vampire {
  Wolf({required super.x, required super.groundY, super.facing = 1});

  double _stride = 0, _speed = 0, _lastX = double.nan;

  @override
  void update(double dt) {
    super.update(dt);
    if (dt <= 0) return;
    if (!_lastX.isNaN) {
      final double v = ((x - _lastX) / dt).abs();
      _speed += (math.min(v, 8) - _speed) * math.min(1, dt * 8);
    }
    _lastX = x;
    _stride += dt * (1.5 + _speed * 2.8);
  }

  static final Paint _fur = Paint()..color = _black;
  static final Paint _leg = Paint()
    ..color = _black
    ..strokeWidth = 0.085
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  static final Paint _eye = Paint()..color = const Color(0xFFE6E2D4);

  @override
  void paint(Canvas canvas, Vector2 cam, Mood mood) {
    if (gone) return;
    final double run = (_speed / 3.2).clamp(0.0, 1.0);
    final bool pounce = mode == VampireMode.grab;
    final double s = math.sin(_stride);
    canvas.save();
    canvas.translate(x, groundY - lift);
    canvas.scale(facing >= 0 ? 1 : -1, 1);
    if (pounce) canvas.rotate(-0.25);
    // The back, bobbing with the stride.
    final double back = -0.66 - run * 0.04 * s.abs();
    // Legs: shoulder and hip swing in turn, the knee folding back.
    void leg(double hipX, double phase, bool front) {
      final double swing = pounce
          ? (front ? -0.9 : 0.7)
          : math.sin(_stride + phase) * (0.15 + run * 0.55);
      final Offset hip = Offset(hipX, back + 0.18);
      final Offset knee =
          hip + Offset(math.sin(swing) * 0.3, math.cos(swing) * 0.3);
      final double bend = front ? -0.35 : 0.45;
      final Offset paw =
          knee +
          Offset(
            math.sin(swing + bend * (0.4 + run)) * 0.28,
            math.cos(swing + bend * (0.4 + run)) * 0.28,
          );
      canvas.drawLine(hip, knee, _leg);
      canvas.drawLine(knee, paw, _leg);
    }

    leg(-0.5, math.pi, false);
    leg(0.3, 0, true);
    final body = Path()
      ..moveTo(-0.62, back + 0.04)
      ..quadraticBezierTo(-0.2, back - 0.08, 0.32, back - 0.06)
      ..quadraticBezierTo(0.5, back - 0.06, 0.6, back - 0.14)
      // The head, ears up, the muzzle long.
      ..lineTo(0.66, back - 0.36)
      ..lineTo(0.72, back - 0.22)
      ..lineTo(0.78, back - 0.34)
      ..lineTo(0.8, back - 0.18)
      ..quadraticBezierTo(0.92, back - 0.14, 1.04, back - 0.06)
      ..lineTo(1.03, back)
      ..quadraticBezierTo(0.86, back + 0.02, 0.72, back + 0.08)
      // Chest, a ruff, the belly tucked up.
      ..quadraticBezierTo(0.55, back + 0.36, 0.38, back + 0.34)
      ..quadraticBezierTo(0.0, back + 0.2, -0.44, back + 0.3)
      ..quadraticBezierTo(-0.66, back + 0.28, -0.62, back + 0.04)
      ..close();
    canvas.drawPath(body, _fur);
    // The tail, out behind at a run, low when it stands.
    final double tail = 0.22 - run * 0.2 + (pounce ? -0.2 : 0);
    canvas.drawPath(
      Path()
        ..moveTo(-0.6, back + 0.02)
        ..quadraticBezierTo(-0.9, back + tail - 0.05, -1.08, back + tail + 0.12)
        ..quadraticBezierTo(-0.88, back + tail + 0.06, -0.58, back + 0.12)
        ..close(),
      _fur,
    );
    leg(-0.42, math.pi + 0.6, false);
    leg(0.38, 0.6, true);
    canvas.drawCircle(Offset(0.86, back - 0.13), 0.022, _eye);
    canvas.restore();
  }
}

/// Crows on the graves, pecking. Anything coming near upright, or quick,
/// sends them up cawing, and that wakes what sleeps there; crept past, low
/// and slow, they stay where they are.
class CrowFlock extends Component
    with OffScreenCulling
    implements HasFootprint {
  CrowFlock({
    required this.perches,
    required this.stage,
    required this.onFlush,
    this.reach = 2.2,
  }) : super(priority: 3);

  /// Where each one stands, its feet, world metres.
  final List<Vector2> perches;
  final Stage stage;
  final void Function() onFlush;
  final double reach;

  bool flushed = false;
  final List<_Crow> _crows = [];
  double _time = 0;

  @override
  Rect get footprint {
    double l = double.infinity, r = -double.infinity, t = double.infinity;
    double b = -double.infinity;
    for (final p in perches) {
      l = math.min(l, p.x);
      r = math.max(r, p.x);
      t = math.min(t, p.y);
      b = math.max(b, p.y);
    }
    return Rect.fromLTRB(l - 0.3, t - 0.5, r + 0.3, b);
  }

  @override
  Future<void> onLoad() async => reset();

  /// Back on their perches, as they were.
  void reset() {
    flushed = false;
    _crows
      ..clear()
      ..addAll([for (final (i, p) in perches.indexed) _Crow(p.clone(), i)]);
  }

  /// Up and away, cawing.
  void flush({double? from}) {
    if (flushed) return;
    flushed = true;
    for (final c in _crows) {
      final double away = from == null || c.at.x >= from ? 1 : -1;
      c
        ..flying = true
        ..velocity.setValues(away * (2.2 + (c.seed % 3) * 0.5), -2.4);
    }
    final Vector2 at = _crows.first.at;
    stage.cue('creak', weight: 0.8, at: at);
    stage.cue('rope', weight: 0.6, at: at);
    onFlush();
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    final Player boy = stage.player;
    if (!flushed && boy.isMounted && !boy.isDead) {
      final Vector2 p = boy.body.position;
      final bool loud =
          !boy.isLow || boy.velocity.x.abs() > 1.3 || !boy.isOnGround;
      if (loud &&
          _crows.any(
            (c) => (c.at.x - p.x).abs() < reach && (c.at.y - p.y).abs() < 2.5,
          )) {
        flush(from: p.x);
      }
    }
    for (final c in _crows) {
      if (!c.flying) continue;
      c.velocity.y -= dt * 1.6;
      c.at.add(c.velocity * dt);
    }
  }

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint.inflate(flushed ? 12 : 1))) return;
    for (final c in _crows) {
      _draw(canvas, c);
    }
  }

  void _draw(Canvas canvas, _Crow c) {
    final double f = c.flying
        ? c.velocity.x.sign
        : (c.seed.isEven ? 1.0 : -1.0);
    canvas.save();
    canvas.translate(c.at.x, c.at.y);
    canvas.scale(f * 1.7, 1.7);
    if (c.flying) {
      final double beat = math.sin(_time * 18 + c.seed);
      canvas.drawOval(const Rect.fromLTRB(-0.15, -0.06, 0.15, 0.06), _paint);
      canvas.drawCircle(const Offset(0.16, -0.03), 0.055, _paint);
      for (final side in const [1.0, -0.6]) {
        canvas.drawPath(
          Path()
            ..moveTo(-0.05, 0)
            ..lineTo(-0.02 - 0.12 * side, -0.28 * beat * side)
            ..lineTo(0.08, -0.02)
            ..close(),
          _paint,
        );
      }
    } else {
      // Pecking now and then: the head down to the grass and up.
      final double peck = math.max(
        0,
        math.sin(_time * (1.4 + c.seed * 0.17) + c.seed * 2.3) * 3 - 2,
      );
      canvas.drawOval(const Rect.fromLTRB(-0.15, -0.28, 0.12, -0.12), _paint);
      canvas.drawPath(
        Path()
          ..moveTo(-0.12, -0.24)
          ..lineTo(-0.3, -0.16)
          ..lineTo(-0.11, -0.15)
          ..close(),
        _paint,
      );
      final Offset head = Offset(0.13 + peck * 0.05, -0.3 + peck * 0.2);
      canvas.drawCircle(head, 0.06, _paint);
      canvas.drawPath(
        Path()
          ..moveTo(head.dx + 0.04, head.dy - 0.02)
          ..lineTo(head.dx + 0.15, head.dy + 0.02 + peck * 0.04)
          ..lineTo(head.dx + 0.03, head.dy + 0.03)
          ..close(),
        _paint,
      );
      canvas.drawLine(
        const Offset(-0.02, -0.13),
        const Offset(-0.04, 0),
        _legs,
      );
      canvas.drawLine(const Offset(0.03, -0.13), const Offset(0.04, 0), _legs);
    }
    canvas.restore();
  }

  static final Paint _paint = Paint()..color = _black;
  static final Paint _legs = Paint()
    ..color = _black
    ..strokeWidth = 0.018;
}

class _Crow {
  _Crow(this.at, this.seed);
  final Vector2 at;
  final int seed;
  final Vector2 velocity = Vector2.zero();
  bool flying = false;
}

/// A stretch of wood too dark to see the ground in, but for a few
/// fireflies: they drift on ahead of him and wait over whatever lies in
/// the way, and he sees it only by their light.
class FireflyGuide extends Component with OffScreenCulling {
  FireflyGuide({
    required this.left,
    required this.right,
    required this.floor,
    required this.stops,
    required this.stage,
  }) : super(priority: 40);

  final double left, right, floor;

  /// What they show him, in order: the x of each thing in the way.
  final List<double> stops;
  final Stage stage;

  final Vector2 centre = Vector2.zero();
  double _time = 0;

  @override
  Future<void> onLoad() async => reset();

  void reset() => centre.setValues(left + 1.5, floor - 1.5);

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    final Player boy = stage.player;
    if (!boy.isMounted) return;
    final double bx = boy.body.position.x;
    if (bx < left - 3) return;
    // Over the next thing he has not yet passed, if it is near; else a
    // little ahead of him.
    final double? next = stops.where((s) => s > bx - 0.3).firstOrNull;
    final double goal = next == null
        ? right + 3
        : math.min(next, math.max(bx + 3, left + 1.5));
    final double hover = floor - 1.1 + math.sin(_time * 1.3) * 0.15;
    final Vector2 to = Vector2(goal, hover) - centre;
    final double step = math.min(to.length, dt * 3.4);
    if (to.length > 1e-4) centre.add(to.normalized() * step);
  }

  static const Color _dark = Color(0xF2020303);
  final Paint _shade = Paint();
  final Paint _hole = Paint()..blendMode = BlendMode.dstOut;
  static final Paint _glow = Paint()..color = const Color(0x40D8F28A);
  static final Paint _spark = Paint()..color = const Color(0xFFEFFAC4);

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTRB(left - 3, floor - 16, right + 3, floor + 6);
    if (!isOnScreen(rect)) return;
    final double w = rect.width;
    canvas.saveLayer(rect, Paint());
    _shade.shader = Gradient.linear(
      Offset(rect.left, 0),
      Offset(rect.right, 0),
      const [Color(0x00020303), _dark, _dark, Color(0x00020303)],
      [0, 3.5 / w, 1 - 3.5 / w, 1],
    );
    canvas.drawRect(rect, _shade);
    void light(Offset at, double radius, double strength) {
      _hole.shader = Gradient.radial(at, radius, [
        Color.fromARGB((255 * strength).round(), 0, 0, 0),
        const Color(0x00000000),
      ]);
      canvas.drawCircle(at, radius, _hole);
    }

    final double flicker = 0.92 + 0.08 * math.sin(_time * 7.3);
    light(centre.toOffset(), 3.1 * flicker, 1);
    final Player boy = stage.player;
    if (boy.isMounted) light(boy.body.position.toOffset(), 1.3, 0.55);
    canvas.restore();
    // The fireflies themselves, each on its own loop.
    for (var i = 0; i < 7; i++) {
      final double t = _time * (0.9 + i * 0.13) + i * 2.1;
      final Offset at =
          centre.toOffset() +
          Offset(math.sin(t * 1.3) * 0.55, math.cos(t * 1.7) * 0.35);
      final double on = 0.5 + 0.5 * math.sin(_time * (2 + i * 0.4) + i);
      canvas.drawCircle(at, 0.1 + 0.08 * on, _glow);
      canvas.drawCircle(at, 0.03 + 0.015 * on, _spark);
    }
  }
}

/// Black mud between the trees. He wades in it, slowly, and sinks if he
/// stays: only by keeping on, jumping clear or reaching a stone does he
/// get through.
class Bog extends Component with OffScreenCulling implements HasFootprint {
  Bog({
    required this.left,
    required this.right,
    required this.floor,
    required this.stage,
  }) : super(priority: 20);

  final double left, right, floor;
  final Stage stage;

  /// How far he has gone down, 0 to 1 (under).
  double sink = 0;
  double _time = 0, _bubble = 0;
  bool _in = false;

  static const double _top = 0.22;

  @override
  Rect get footprint => Rect.fromLTRB(left, floor - 0.4, right, floor + 0.3);

  void reset() {
    sink = 0;
    _in = false;
    final Player boy = stage.player;
    if (boy.isMounted) boy.reportWaterDepth(this, 0);
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    _bubble -= dt;
    if (_bubble < 0) _bubble = 2.4;
    final Player boy = stage.player;
    if (!boy.isMounted || boy.isDead) return;
    final Vector2 p = boy.body.position;
    final double feet = p.y + GameConfig.playerHeight / 2;
    _in = p.x > left + 0.15 && p.x < right - 0.15 && feet > floor - _top - .06;
    if (_in && boy.isOnGround) {
      sink += dt * (boy.velocity.x.abs() < 0.5 ? 0.85 : 0.32);
    } else {
      sink = math.max(0, sink - dt * (boy.isOnGround ? 2.5 : 1.1));
    }
    boy.reportWaterDepth(this, _in ? 0.45 + sink * 0.4 : 0);
    if (sink >= 1) {
      stage.cue('splash', weight: 0.9, at: p);
      boy.reportWaterDepth(this, 0);
      boy.die();
    }
  }

  static final Paint _mud = Paint()..color = const Color(0xFF131313);
  static final Paint _sheen = Paint()
    ..color = const Color(0x8CA8A8A8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.03;
  static final Paint _reed = Paint()
    ..color = const Color(0xFF060606)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.035
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint.inflate(1))) return;
    final top = Path()..moveTo(left, floor + 0.4);
    final sheen = Path();
    for (double x = left; x <= right + 1e-6; x += 0.25) {
      final double y = floor - _top + math.sin(x * 2.1 + _time * 0.7) * 0.02;
      top.lineTo(x, y);
      if (x == left) {
        sheen.moveTo(x, y);
      } else {
        sheen.lineTo(x, y);
      }
    }
    top
      ..lineTo(right, floor + 0.4)
      ..close();
    canvas.drawPath(top, _mud);
    canvas.drawPath(sheen, _sheen);
    // Reeds at its edges, and here and there in it, bending.
    for (var i = 0; i < 14; i++) {
      final double t = i < 4
          ? i * 0.012
          : i > 9
          ? 1 - (i - 10) * 0.012
          : 0.1 + (i - 4) * 0.15;
      final double x = left + (right - left) * t;
      final double h = 0.5 + 0.35 * math.sin(i * 2.3);
      final double bend = 0.12 * math.sin(_time * 0.8 + i);
      canvas.drawPath(
        Path()
          ..moveTo(x, floor - _top + 0.04)
          ..quadraticBezierTo(
            x,
            floor - _top - h * 0.6,
            x + bend,
            floor - _top - h,
          ),
        _reed,
      );
    }
    // A bubble rising and breaking, now here, now there.
    final double bx = left + (right - left) * ((_time * 0.37) % 1);
    final double grow = (2.4 - _bubble) / 2.4;
    canvas.drawCircle(Offset(bx, floor - _top), 0.04 + grow * 0.07, _sheen);
    // Round his legs, the mud he has gone down into.
    final Player boy = stage.player;
    if (_in && boy.isMounted && !boy.isDead) {
      final double x = boy.body.position.x;
      final double up = 0.1 + sink * 0.9;
      canvas.drawPath(
        Path()
          ..moveTo(x - 0.5, floor - _top)
          ..quadraticBezierTo(x - 0.22, floor - _top - up, x, floor - _top - up)
          ..quadraticBezierTo(
            x + 0.22,
            floor - _top - up,
            x + 0.5,
            floor - _top,
          )
          ..close(),
        _mud,
      );
    }
  }
}

/// A hunters' line strung across a ravine from post to post, a pulley
/// running on it with a short rope and a handle. Caught, it runs down the
/// line with him to the far post.
class ZipLine extends Component with OffScreenCulling implements HasFootprint {
  ZipLine({
    required this.from,
    required this.to,
    required this.groundFrom,
    required this.groundTo,
    double rope = 1.5,
  }) : super(priority: -1) {
    handle = ZipHandle(this, length: rope);
  }

  /// The line's ends, world metres, high at [from].
  final Vector2 from, to;
  final double groundFrom, groundTo;
  late final ZipHandle handle;

  /// How far below the line the pulley's rope hangs from.
  static const double drop = 0.22;

  double get runLength => (to - from).length - 0.9;

  /// Where the rope hangs from, [along] metres down the line from where
  /// it starts.
  Vector2 pointAt(double along) {
    final Vector2 dir = (to - from).normalized();
    return from + dir * (0.45 + along) + Vector2(0, drop);
  }

  @override
  Rect get footprint =>
      Rect.fromLTRB(from.x - 0.4, from.y - 0.4, to.x + 0.4, groundTo);

  static final Paint _wood = Paint()..color = _black;
  static final Paint _cable = Paint()
    ..color = const Color(0xFF101010)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.03;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint)) return;
    // A post at each end, leaning back against the pull, and a stay.
    for (final (top, ground, lean) in [
      (from, groundFrom, -1.0),
      (to, groundTo, 1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(top.x - 0.09, top.y - 0.25)
          ..lineTo(top.x + 0.09, top.y - 0.25)
          ..lineTo(top.x + 0.14 - lean * 0.3, ground + 0.05)
          ..lineTo(top.x - 0.14 - lean * 0.3, ground + 0.05)
          ..close(),
        _wood,
      );
      canvas.drawLine(
        Offset(top.x, top.y),
        Offset(top.x + lean * 1.4, ground + 0.02),
        _cable,
      );
    }
    canvas.drawLine(from.toOffset(), to.toOffset(), _cable);
  }
}

/// The pulley block on a [ZipLine], with its rope: taken hold of, it runs.
class ZipHandle extends SwingRope {
  ZipHandle(this.line, {super.length = 1.5})
    : super(anchor: line.pointAt(0), support: RopeSupport.pulley);

  final ZipLine line;
  double _along = 0, _speed = 0;
  bool riding = false, arrived = false;
  Stage? _stage;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _stage = ancestors().whereType<Stage>().firstOrNull;
  }

  @override
  Body createBody() {
    final Body fixed = super.createBody();
    fixed.type = BodyType.kinematic;
    return fixed;
  }

  /// Back at the top of the line, still.
  void reset() {
    _along = 0;
    _speed = 0;
    riding = false;
    arrived = false;
    if (!isReady) return;
    final Vector2 start = line.pointAt(0);
    body
      ..setTransform(start, const Rot.identity())
      ..linearVelocity = Vector2.zero();
    anchor.setFrom(start);
    bob
      ..setTransform(start + Vector2(0, length), const Rot.identity())
      ..linearVelocity = Vector2.zero();
    holdLength = length;
  }

  @override
  void update(double dt) {
    if (isReady && dt > 0) {
      final Player? boy = _stage?.player;
      if (!riding &&
          boy != null &&
          boy.isMounted &&
          boy.interactions.attachedRope == this) {
        riding = true;
        cue('rope', at: anchor);
      }
      if (riding && !arrived) {
        _speed = math.min(_speed + dt * 3, 4.8);
        _along = math.min(line.runLength, _along + _speed * dt);
        if (_along >= line.runLength) {
          arrived = true;
          cue('wood', weight: 0.8, at: anchor, shake: 0.15);
        }
      }
      final Vector2 goal = line.pointAt(_along);
      body.linearVelocity = riding && !arrived
          ? (goal - body.position) / dt
          : Vector2.zero();
      anchor.setFrom(body.position);
    }
    super.update(dt);
  }

  static final Paint _wood = Paint()..color = _black;

  @override
  void drawEnd(Canvas canvas, Offset end, Offset down) {
    // A short bar of wood across the rope's end, to hold.
    canvas.save();
    canvas.translate(end.dx, end.dy);
    canvas.rotate(-math.atan2(down.dx, down.dy));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-0.18, 0.0, 0.18, 0.06),
        const Radius.circular(0.03),
      ),
      _wood,
    );
    canvas.restore();
  }
}

/// A dead tree standing at the edge of a ravine, rotten at the root:
/// pushed, it goes over and lies across, a bridge to walk.
class DeadTrunk extends TallBookcase {
  DeadTrunk({required super.x, required super.floorY, super.height = 4.8})
    : super(width: 0.55, massKg: 30);

  static final Paint _bark = Paint()..color = const Color(0xFF070706);
  static final Paint _grain = Paint()
    ..color = const Color(0x2EBDB6A8)
    ..strokeWidth = 0.018
    ..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas) {
    if (!isReady) return;
    final double hw = size.x / 2, hh = size.y / 2;
    // Thicker at the root, a split crown at the top, one snapped limb.
    canvas.drawPath(
      Path()
        ..moveTo(-hw - 0.06, hh)
        ..lineTo(-hw + 0.02, hh - 0.35)
        ..lineTo(-hw * 0.75, -hh + 0.3)
        ..lineTo(-hw * 0.9, -hh - 0.05)
        ..lineTo(-hw * 0.2, -hh + 0.2)
        ..lineTo(hw * 0.3, -hh - 0.12)
        ..lineTo(hw * 0.7, -hh + 0.35)
        ..lineTo(hw - 0.02, hh - 0.35)
        ..lineTo(hw + 0.08, hh)
        ..close(),
      _bark,
    );
    canvas.drawPath(
      Path()
        ..moveTo(hw * 0.6, -hh * 0.2)
        ..lineTo(hw + 0.45, -hh * 0.2 - 0.5)
        ..lineTo(hw + 0.5, -hh * 0.2 - 0.42)
        ..lineTo(hw * 0.6, -hh * 0.2 + 0.12)
        ..close(),
      _bark,
    );
    for (final dx in const [-0.12, 0.02, 0.13]) {
      canvas.drawLine(
        Offset(dx, hh - 0.4),
        Offset(dx * 0.7, -hh + 0.5),
        _grain,
      );
    }
  }
}

/// A cask on its side: pushed off the top of a slope it runs away down
/// it, and whatever is in its road at speed is knocked flat.
class RollingBarrel extends BodyComponent with OffScreenCulling {
  RollingBarrel({
    required Vector2 position,
    this.radius = 0.42,
    this.massKg = 22,
    this.settleIn,
    this.settleAt,
    this.parked = false,
  }) : _start = position.clone(),
       super(renderBody: false, priority: 2);

  final Vector2 _start;
  final double radius, massKg;

  /// Where, come to rest, it lodges and stays (in a plate's hollow).
  final Rect? settleIn;

  /// Where it lodges, if it is to fill a slot exactly.
  final Vector2? settleAt;

  /// Held where it is put, out of play, until set rolling.
  final bool parked;
  bool settled = false;
  double _resting = 0;
  bool _created = false;
  bool get isReady => _created && body.isValid;
  Stage? _stage;
  double _was = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _stage = ancestors().whereType<Stage>().firstOrNull;
  }

  @override
  Body createBody() {
    final b = world.createBody(
      BodyDef(
        type: parked ? BodyType.static : BodyType.dynamic,
        position: _start.clone(),
        angularDamping: 0.05,
        userData: this,
      ),
    );
    b.createShape(
      Circle(radius: radius),
      ShapeDef(
        density: massKg / (math.pi * radius * radius),
        filter: CollisionLayers.propFilter(),
        material: SurfaceMaterial(friction: 0.8),
      ),
    );
    _created = true;
    return b;
  }

  void resetToStart() => restoreAt(_start);

  /// At rest at [position].
  void restoreAt(Vector2 position) {
    if (!isReady) return;
    if (settled) {
      settled = false;
      body.type = BodyType.dynamic;
    }
    _resting = 0;
    body
      ..setTransform(position.clone(), const Rot.identity())
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || dt <= 0) return;
    final Vector2 v = body.linearVelocity;
    final double speed = v.length;
    // Stopped short against something: the knock of it.
    if (_was > 2.5 && speed < _was * 0.4) {
      cue('wood', weight: 0.9, at: body.position, shake: 0.25);
    }
    _was = speed;
    final Rect? hollow = settleIn;
    if (!settled && hollow != null) {
      _resting = hollow.contains(body.position.toOffset()) && speed < 0.3
          ? _resting + dt
          : 0;
      if (_resting > 0.35) {
        settled = true;
        final Vector2? at = settleAt;
        if (at != null) body.setTransform(at, body.rotation);
        body.type = BodyType.static;
      }
    }
    final Player? boy = _stage?.player;
    if (boy == null || !boy.isMounted || boy.isDead || speed < 2.4) return;
    final Vector2 d = boy.body.position - body.position;
    if (d.length < radius + 0.45 && d.dot(v) > 0) {
      boy.die(push: v * 0.6 + Vector2(0, -1.2));
    }
  }

  static final Paint _wood = Paint()..color = const Color(0xFF080706);
  static final Paint _hoop = Paint()
    ..color = const Color(0x4CC8C2B4)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.025;

  @override
  void render(Canvas canvas) {
    if (!isReady) return;
    // Its end, turning as it rolls: the hoops, the staves, the bung.
    canvas.drawCircle(Offset.zero, radius, _wood);
    canvas.drawCircle(Offset.zero, radius - 0.04, _hoop);
    canvas.drawCircle(Offset.zero, radius * 0.55, _hoop);
    for (var i = 0; i < 6; i++) {
      final double a = i * math.pi / 3;
      canvas.drawLine(
        Offset(math.cos(a), math.sin(a)) * (radius * 0.58),
        Offset(math.cos(a), math.sin(a)) * (radius - 0.06),
        _hoop,
      );
    }
    canvas.drawCircle(Offset(radius * 0.3, 0), 0.035, _hoop);
  }
}
