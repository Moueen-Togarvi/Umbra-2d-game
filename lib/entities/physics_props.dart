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

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.x,
      height: size.y,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(0.035)),
      Paint()..color = const Color(0xFF090909),
    );
    final seam = Paint()
      ..color = const Color(0xFF303030)
      ..strokeWidth = 0.025
      ..strokeCap = StrokeCap.round;
    final inset = rect.deflate(0.07);
    canvas.drawLine(inset.topLeft, inset.bottomRight, seam);
    canvas.drawLine(inset.bottomLeft, inset.topRight, seam);
    canvas.drawRect(
      inset,
      Paint()
        ..color = const Color(0xFF232323)
        ..strokeWidth = 0.02
        ..style = PaintingStyle.stroke,
    );
    // Metal bands distinguish the heavy crate without a HUD label.
    if (massKg >= 25) {
      for (final x in [-size.x * 0.31, size.x * 0.31]) {
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), seam);
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

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: size.x, height: size.y),
        const Radius.circular(0.035),
      ),
      Paint()..color = const Color(0xFF111111),
    );
    final rim = Paint()
      ..color = const Color(0xFF444444)
      ..strokeWidth = 0.025;
    canvas.drawLine(
      Offset(-size.x / 2, -size.y / 2),
      Offset(size.x / 2, -size.y / 2),
      rim,
    );
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
    canvas.drawLine(
      Offset.zero,
      Offset(end.x, end.y),
      Paint()
        ..color = const Color(0xFF272727)
        ..strokeWidth = 0.035
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(end.x, end.y),
      0.085,
      Paint()..color = const Color(0xFF171717),
    );
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
