import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';

Filter _propFilter({bool collideWithPlayer = true}) => Filter(
  categoryBits: CollisionLayers.prop,
  maskBits:
      CollisionLayers.terrain |
      CollisionLayers.prop |
      CollisionLayers.ragdoll |
      (collideWithPlayer ? CollisionLayers.player : 0),
);

/// A real dynamic crate; density, mass and floor friction determine resistance.
class PhysicsCrate extends BodyComponent {
  PhysicsCrate({
    required Vector2 position,
    required Vector2 size,
    required this.massKg,
    this.friction = 0.25,
  }) : _initialPosition = position.clone(),
       size = size.clone(),
       super(renderBody: false);

  final Vector2 _initialPosition;
  final Vector2 size;
  final double massKg;
  final double friction;
  bool _created = false;
  bool get isReady => _created && body.isValid;

  @override
  Body createBody() {
    final result = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: _initialPosition,
        fixedRotation: true,
        linearDamping: 0.12,
        userData: this,
        isBullet: true,
      ),
    );
    const corner = 0.025;
    final area = size.x * size.y - (4 - math.pi) * corner * corner;
    result.createShape(
      Polygon.box(size.x / 2 - corner, size.y / 2 - corner, radius: corner),
      ShapeDef(
        density: massKg / area,
        filter: _propFilter(),
        material: SurfaceMaterial(friction: friction, restitution: 0),
        enableContactEvents: true,
        enableSensorEvents: true,
      ),
    );
    // Native rounded-polygon integration approximates the corner area. Keep
    // the chosen kilogram mass exact while preserving its computed inertia.
    result.massData = MassData(
      mass: massKg,
      center: result.localCenterOfMass,
      rotationalInertia: result.rotationalInertia * massKg / result.mass,
    );
    _created = true;
    return result;
  }

  static final Paint _wood = Paint()..color = const Color(0xFF0A0A0A);
  static final Paint _gap = Paint()..color = const Color(0x2EBDBDBD);
  static final Paint _iron = Paint()..color = const Color(0xFF050505);

  @override
  void render(Canvas canvas) {
    // A slatted wooden crate: horizontal planks with thin gaps the fog shows
    // through, nailed to corner posts. The heavy one is banded with iron.
    final double hw = size.x / 2, hh = size.y / 2;
    final rect = Rect.fromLTRB(-hw, -hh, hw, hh);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(0.02)),
      _wood,
    );
    final int planks = math.max(3, (size.y / 0.16).round());
    final double post = math.min(0.085, size.x * 0.12);
    for (var i = 1; i < planks; i++) {
      final double y = -hh + i * size.y / planks;
      // Gaps run between the posts, slightly uneven like hand-cut boards.
      final double wobble = ((i * 37) % 7 - 3) * 0.0025;
      canvas.drawRect(
        Rect.fromLTRB(-hw + post, y - 0.007 + wobble, hw - post, y + 0.006),
        _gap,
      );
    }
    // Knot holes and a split board, so it is wood and not a grille.
    canvas.drawCircle(Offset(hw * 0.35, -hh * 0.15), 0.012, _gap);
    canvas.drawRect(
      Rect.fromLTRB(-hw * 0.2, hh * 0.55, hw * 0.25, hh * 0.55 + 0.005),
      _gap,
    );
    if (massKg >= 25) {
      for (final x in [-hw * 0.45, hw * 0.45]) {
        canvas.drawRect(Rect.fromLTRB(x - 0.03, -hh, x + 0.03, hh), _iron);
        for (final y in [-hh * 0.8, 0.0, hh * 0.8]) {
          canvas.drawCircle(Offset(x, y), 0.009, _gap);
        }
      }
    }
  }
}

/// Kinematic motion uses velocity, so standing bodies inherit real movement.
class MovingPlatform extends BodyComponent {
  MovingPlatform({
    required Vector2 from,
    required Vector2 to,
    required Vector2 size,
    this.speed = 0.8,
  }) : from = from.clone(),
       to = to.clone(),
       size = size.clone(),
       super(renderBody: false);

  final Vector2 from, to, size;
  final double speed;
  bool _towardEnd = true;
  bool _created = false;
  bool get isReady => _created && body.isValid;

  @override
  Body createBody() {
    final result = world.createBody(
      BodyDef(type: BodyType.kinematic, position: from, userData: this),
    );
    result.createShape(
      Polygon.box(size.x / 2, size.y / 2),
      ShapeDef(
        filter: _propFilter(),
        material: SurfaceMaterial(friction: 0.7),
        enableContactEvents: true,
        enableSensorEvents: true,
      ),
    );
    _created = true;
    return result;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || dt <= 0) return;
    Vector2 delta = (_towardEnd ? to : from) - body.position;
    if (delta.length < 0.015) {
      _towardEnd = !_towardEnd;
      delta = (_towardEnd ? to : from) - body.position;
    }
    final distance = delta.length;
    body.linearVelocity = distance == 0
        ? Vector2.zero()
        : delta * (math.min(speed, distance / dt) / distance);
  }

  static final Paint _board = Paint()..color = const Color(0xFF0A0A0A);
  static final Paint _seam = Paint()..color = const Color(0x24BDBDBD);
  static final Paint _rope = Paint()
    ..color = const Color(0xFF101010)
    ..strokeWidth = 0.028
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    // Rough planks lashed side by side, hung from two ropes that run up out
    // of the picture to whatever winds them.
    final double hw = size.x / 2, hh = size.y / 2;
    for (final x in [-hw + 0.12, hw - 0.12]) {
      canvas.drawLine(Offset(x, -hh), Offset(x * 0.7, -hh - 14), _rope);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-hw, -hh, hw, hh),
        const Radius.circular(0.02),
      ),
      _board,
    );
    for (double x = -hw + 0.3; x < hw - 0.1; x += 0.3) {
      canvas.drawRect(
        Rect.fromLTRB(x - 0.004, -hh + 0.03, x + 0.004, hh),
        _seam,
      );
    }
  }
}

/// A gravity-driven rope end connected to a fixed anchor by a distance joint.
/// Its player attachment is a second constraint, owned by CharacterInteractions.
class SwingRope extends BodyComponent {
  SwingRope({required Vector2 anchor, required this.length})
    : anchor = anchor.clone(),
      super(renderBody: false);

  final Vector2 anchor;
  final double length;
  late Body bob;
  late DistanceJoint constraint;
  bool _created = false;
  bool get isReady => _created && body.isValid && bob.isValid;
  Vector2 get grip => bob.position;

  @override
  Body createBody() {
    final fixed = world.createBody(
      BodyDef(type: BodyType.static, position: anchor, userData: this),
    );
    fixed.createShape(
      Circle(radius: 0.06),
      ShapeDef(filter: _propFilter(collideWithPlayer: false)),
    );
    bob = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: anchor + Vector2(0, length),
        angularDamping: 0.1,
        userData: this,
        isBullet: true,
      ),
    );
    const radius = 0.085;
    bob.createShape(
      Circle(radius: radius),
      ShapeDef(
        density: 3 / (math.pi * radius * radius),
        filter: _propFilter(collideWithPlayer: false),
        material: SurfaceMaterial(friction: 0.4),
      ),
    );
    constraint = world.physicsWorld.createDistanceJoint(
      DistanceJointDef(bodyA: fixed, bodyB: bob, length: length),
    );
    _created = true;
    return fixed;
  }

  @override
  void render(Canvas canvas) {
    if (!isReady) return;
    // A high branch exits the frame; the small visible fastening marks the
    // actual static anchor. It sits above the reachable character space.
    final support = Path()
      ..moveTo(-0.07, 0.025)
      ..lineTo(0.035, -0.12)
      ..quadraticBezierTo(0.70, -0.25, 1.28, -1.05)
      ..lineTo(3.60, -4.50)
      ..lineTo(3.88, -4.50)
      ..lineTo(1.48, -0.92)
      ..quadraticBezierTo(0.70, -0.04, 0.06, 0.09)
      ..close();
    canvas.drawPath(support, Paint()..color = const Color(0xFF0B0B0B));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-0.085, -0.065, 0.16, 0.11),
        const Radius.circular(0.025),
      ),
      Paint()..color = const Color(0xFF242424),
    );
    canvas.drawCircle(
      const Offset(-0.012, -0.025),
      0.016,
      Paint()..color = const Color(0xFF606060),
    );
    final end = bob.position - body.position;
    final rope = Paint()
      ..color = const Color(0xFF181818)
      ..strokeWidth = 0.032
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(end.x, end.y), rope);
    // A knot and a frayed end below it, rather than a ball.
    final double length = end.length;
    if (length > 0) {
      final Offset dir = Offset(end.x / length, end.y / length);
      final Offset knot = Offset(end.x, end.y);
      canvas.drawCircle(knot, 0.03, Paint()..color = const Color(0xFF181818));
      rope.strokeWidth = 0.012;
      for (final splay in const [-0.25, 0.0, 0.3]) {
        final Offset tip =
            knot +
            Offset(
                  dir.dx * math.cos(splay) - dir.dy * math.sin(splay),
                  dir.dx * math.sin(splay) + dir.dy * math.cos(splay),
                ) *
                0.09;
        canvas.drawLine(knot, tip, rope);
      }
    }
  }

  @override
  void onRemove() {
    if (_created) {
      if (constraint.isValid) constraint.destroy();
      if (bob.isValid) world.destroyBody(bob);
    }
    super.onRemove();
  }
}
