import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';
import '../render/culling.dart';
import '../world/footprint.dart';
import '../world/stage.dart';
import 'player.dart';

/// What stands on or moves through a patch of ground: the boy, or a prop
/// he moves (a crate, a log). Polled rather than sensed, so it finds
/// crates, which do not take part in sensor events.
Iterable<Body> _bodiesIn(Component from, Rect zone) {
  final game = from.findGame();
  if (game is! Forge2DGame) return const [];
  final shapes = game.world.physicsWorld.overlapAabb(
    Aabb(Vector2(zone.left, zone.top), Vector2(zone.right, zone.bottom)),
    filter: QueryFilter(
      categoryBits: CollisionLayers.all,
      maskBits: CollisionLayers.player | CollisionLayers.prop,
    ),
  );
  return {
    for (final s in shapes)
      if (s.isValid && !s.isSensor && s.body.type == BodyType.dynamic) s.body,
  };
}

/// A hunter's trap set in the grass: iron jaws lying open. The boy's foot
/// in it is the end of him; a crate pushed onto it springs it shut on
/// wood, and then it is only a thing to walk over.
class BearTrap extends Component with OffScreenCulling implements HasFootprint {
  BearTrap({required this.x, required this.groundY, required this.stage})
    : super(priority: 2);

  final double x, groundY;
  final Stage stage;

  /// Half its width, and how high the open jaws stand.
  static const double half = 0.42, rise = 0.2;

  bool sprung = false;
  double _shut = 0;

  /// Where a foot or a crate sets it off.
  Rect get zone =>
      Rect.fromLTRB(x - half, groundY - rise - 0.05, x + half, groundY + 0.05);

  @override
  Rect get footprint => zone;

  /// Open again, as it was set.
  void reset() {
    sprung = false;
    _shut = 0;
  }

  @override
  void update(double dt) {
    if (sprung) {
      _shut = math.min(1, _shut + dt * 14);
      return;
    }
    for (final body in _bodiesIn(this, zone)) {
      sprung = true;
      stage.cue('chain', at: Vector2(x, groundY), shake: 0.2);
      stage.cue('wood', weight: 0.6, at: Vector2(x, groundY));
      final data = body.userData;
      if (data is Player && !data.isDead) {
        data.die(cause: DeathCause.trap);
      }
      break;
    }
  }

  static final Paint _iron = Paint()..color = const Color(0xFF0B0B0B);
  static final Paint _glint = Paint()
    ..color = const Color(0x70C8CCC6)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.016;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(zone.inflate(0.5))) return;
    final double g = groundY;
    // The stake it is chained to, leaning, and its chain.
    canvas.drawPath(
      Path()
        ..moveTo(x + 0.58, g + 0.02)
        ..lineTo(x + 0.64, g - 0.32)
        ..lineTo(x + 0.69, g + 0.02)
        ..close(),
      _iron,
    );
    canvas.drawLine(
      Offset(x + 0.3, g - 0.03),
      Offset(x + 0.62, g - 0.12),
      _glint,
    );
    // Each jaw a half ring of toothed iron. Open, they lie spread flat
    // with their teeth standing up in a row; shut, they rise and meet in
    // an arch over the spring.
    for (final side in const [-1.0, 1.0]) {
      final double lie = (1 - _shut) * 1.0;
      canvas.save();
      canvas.translate(x, g - 0.035);
      canvas.rotate(side * lie);
      final jaw = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(side * 0.05, -0.4, side * -0.02, -0.42)
        ..lineTo(side * -0.02, -0.38)
        ..quadraticBezierTo(side * 0.0, -0.34, side * -0.005, 0)
        ..close();
      canvas.drawPath(jaw, _iron);
      // Teeth along its edge, facing the other jaw.
      for (var i = 1; i <= 6; i++) {
        final double t = i / 7;
        final double y = -0.4 * t;
        final teeth = Path()
          ..moveTo(0, y - 0.025)
          ..lineTo(side * -0.14, y)
          ..lineTo(0, y + 0.025)
          ..close();
        canvas.drawPath(teeth, _iron);
      }
      canvas.drawLine(const Offset(0, 0), Offset(side * 0.03, -0.4), _glint);
      canvas.restore();
    }
    // The spring plate in the middle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(x - 0.13, g - 0.07, x + 0.13, g + 0.01),
        const Radius.circular(0.02),
      ),
      _iron,
    );
    canvas.drawLine(
      Offset(x - 0.12, g - 0.07),
      Offset(x + 0.12, g - 0.07),
      _glint,
    );
  }
}

/// A stone slab set into the floor that sinks under weight: pressed while
/// the boy or a crate stands on it, and up again as soon as nothing does.
class PressurePlate extends Component
    with OffScreenCulling
    implements HasFootprint {
  PressurePlate({
    required this.left,
    required this.right,
    required this.groundY,
    required this.stage,
    this.minMass = 0,
  }) : super(priority: -1);

  final double left, right, groundY;
  final Stage stage;

  /// The least that presses it, kilograms: a light crate rests on a stiff
  /// plate without moving it.
  final double minMass;

  bool pressed = false;
  double _sink = 0;

  Rect get zone =>
      Rect.fromLTRB(left + 0.08, groundY - 0.3, right - 0.08, groundY + 0.02);

  @override
  Rect get footprint => Rect.fromLTRB(left, groundY - 0.1, right, groundY);

  @override
  void update(double dt) {
    final bool now = _bodiesIn(this, zone).any((b) => b.mass >= minMass);
    if (now != pressed) {
      stage.cue(
        now ? 'gear' : 'tick',
        at: Vector2((left + right) / 2, groundY),
      );
    }
    pressed = now;
    _sink += ((pressed ? 1.0 : 0.0) - _sink) * math.min(1, dt * 10);
  }

  static final Paint _stone = Paint()..color = const Color(0xFF101010);
  static final Paint _rim = Paint()
    ..color = const Color(0x66C8C4BA)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.02;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint.inflate(1))) return;
    final double top = groundY - 0.08 + _sink * 0.06;
    final slab = RRect.fromRectAndRadius(
      Rect.fromLTRB(left, top, right, groundY + 0.02),
      const Radius.circular(0.03),
    );
    canvas.drawRRect(slab, _stone);
    canvas.drawLine(Offset(left + 0.04, top), Offset(right - 0.04, top), _rim);
    // A carved mark in its face.
    final double mid = (left + right) / 2;
    canvas.drawCircle(Offset(mid, top + 0.045), 0.025, _rim);
  }
}

/// A row of sharpened stakes driven into the grass, points up: over them
/// at a jump, or onto them.
class StakeRow extends Component with OffScreenCulling implements HasFootprint {
  StakeRow({
    required this.left,
    required this.right,
    required this.groundY,
    this.high = 0.5,
  }) : super(priority: 2);

  final double left, right, groundY, high;

  @override
  Rect get footprint => Rect.fromLTRB(left, groundY - high, right, groundY);

  @override
  void update(double dt) {
    // The points, not the gaps between their feet.
    final points = Rect.fromLTRB(
      left + 0.1,
      groundY - high * 0.8,
      right - 0.1,
      groundY,
    );
    for (final body in _bodiesIn(this, points)) {
      final data = body.userData;
      if (data is Player && !data.isDead) {
        data.die(cause: DeathCause.spikes);
      }
    }
  }

  static final Paint _wood = Paint()..color = const Color(0xFF070707);

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint.inflate(0.5))) return;
    final int count = math.max(2, ((right - left) / 0.17).round());
    final double step = (right - left) / count;
    for (var i = 0; i < count; i++) {
      final double x = left + step * (i + 0.5);
      // Each a little different: height, lean.
      final double h = high * (0.75 + 0.25 * math.sin(i * 2.7 + left));
      final double lean = 0.05 * math.sin(i * 1.9 + left * 3);
      canvas.drawPath(
        Path()
          ..moveTo(x - step * 0.32, groundY + 0.02)
          ..lineTo(x + lean, groundY - h)
          ..lineTo(x + step * 0.32, groundY + 0.02)
          ..close(),
        _wood,
      );
    }
  }
}
